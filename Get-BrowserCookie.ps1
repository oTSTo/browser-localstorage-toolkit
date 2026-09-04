<#
.SYNOPSIS
  Legge un cookie (anche HttpOnly) dal tuo Chrome, Brave o Opera GX reale,
  senza che appaia mai una finestra visibile, usando il Chrome DevTools
  Protocol (CDP).

.PARAMETER Domain
  Dominio del sito di cui leggere il cookie, es. "instagram.com".

.PARAMETER CookieName
  Nome del cookie da leggere, es. "sessionid".

.PARAMETER Browser
  "Chrome", "Brave" oppure "OperaGX". Default "Chrome".

.PARAMETER ProfileDir
  Nome della cartella profilo (default "Default"). Se usi piu' profili nel
  browser, passa "Profile 1", "Profile 2", ecc.

.PARAMETER BrowserExe
  Percorso dell'eseguibile, solo se non e' in uno dei percorsi standard
  rilevati automaticamente per -Browser.

.COME FUNZIONA
  1. Chiude il browser normale (la porta di debug va impostata all'avvio,
     non si puo' "agganciare" un'istanza gia' in esecuzione).
  2. Riavvia il browser sul TUO profilo reale - non una copia: per Chrome, i
     cookie protetti da App-Bound Encryption (Chrome 127+) si decifrano
     correttamente solo nel profilo/percorso originale, una copia altrove
     restituisce sempre 0 cookie - ma posizionato fuori da qualunque
     monitor: non lo vedi mai comparire.
  3. Interroga quell'istanza via DevTools Protocol (Network.getAllCookies):
     e' il browser stesso a decifrare e restituire il valore in chiaro. Il
     client WebSocket e' scritto a mano su TcpClient per non dipendere da
     System.Net.WebSockets.Client (che su alcune macchine non si carica) ne'
     da un'installazione di Python.
  4. Chiude l'istanza fuori schermo e riavvia il browser normale, visibile,
     cosi' torni operativo come prima.

.EXAMPLE
  .\Get-BrowserCookie.ps1 -Domain "instagram.com" -CookieName "sessionid"

.EXAMPLE
  .\Get-BrowserCookie.ps1 -Domain "discord.com" -CookieName "token" -Browser Brave

.NOTE
  - Chiudere/riaprire il browser fa perdere le schede aperte se non hai
    attivo il ripristino sessione (impostazioni -> "Continua da dove eri
    rimasto").
  - Alcuni antivirus/EDR possono segnalare questo pattern (chiusura browser +
    riavvio con porta di debug) perche' e' simile a quello che fanno gli
    infostealer. E' lo stesso meccanismo, qui applicato al tuo stesso profilo
    per uno scopo legittimo (backup della tua sessione).
  - Mentre la porta di debug e' aperta, chiunque abbia accesso locale alla
    macchina potrebbe leggere i tuoi cookie: la finestra fuori schermo resta
    aperta solo per i pochi secondi necessari all'estrazione.
#>

param(
    [Parameter(Mandatory)] [string]$Domain,
    [Parameter(Mandatory)] [string]$CookieName,
    [ValidateSet("Chrome", "Brave", "OperaGX")] [string]$Browser = "Chrome",
    [string]$ProfileDir = "Default",
    [string]$BrowserExe = "",
    [int]$Port = 9319
)

$ErrorActionPreference = 'Stop'

# ---------- mini client WebSocket su TcpClient (nessun assembly extra) ----------

function Connect-WS {
    param([string]$Uri)
    $u = [Uri]$Uri
    $tcp = New-Object System.Net.Sockets.TcpClient($u.Host, $u.Port)
    $stream = $tcp.GetStream()

    $keyBytes = New-Object byte[] 16
    (New-Object Random).NextBytes($keyBytes)
    $key = [Convert]::ToBase64String($keyBytes)

    $req = "GET $($u.PathAndQuery) HTTP/1.1`r`nHost: $($u.Host):$($u.Port)`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: $key`r`nSec-WebSocket-Version: 13`r`n`r`n"
    $reqBytes = [System.Text.Encoding]::ASCII.GetBytes($req)
    $stream.Write($reqBytes, 0, $reqBytes.Length)

    $resp = New-Object System.Text.StringBuilder
    $b = New-Object byte[] 1
    while ($resp.ToString() -notmatch "`r`n`r`n") {
        if ($stream.Read($b, 0, 1) -eq 0) { throw "Handshake WebSocket fallito (connessione chiusa)." }
        [void]$resp.Append([char]$b[0])
    }
    if ($resp.ToString() -notmatch "101") { throw "Handshake WebSocket fallito: $($resp.ToString())" }

    [PSCustomObject]@{ Tcp = $tcp; Stream = $stream }
}

function Send-WSText {
    param($Conn, [string]$Text)
    $payload = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $len = $payload.Length
    $mask = New-Object byte[] 4
    (New-Object Random).NextBytes($mask)

    $frame = New-Object System.Collections.Generic.List[byte]
    $frame.Add([byte]0x81)
    if ($len -le 125) {
        $frame.Add([byte]($len -bor 0x80))
    } elseif ($len -le 65535) {
        $frame.Add([byte](126 -bor 0x80))
        $frame.Add([byte](($len -shr 8) -band 0xFF))
        $frame.Add([byte]($len -band 0xFF))
    } else {
        $frame.Add([byte](127 -bor 0x80))
        for ($i = 7; $i -ge 0; $i--) { $frame.Add([byte](($len -shr ($i * 8)) -band 0xFF)) }
    }
    $frame.AddRange($mask)
    for ($i = 0; $i -lt $len; $i++) { $frame.Add([byte]($payload[$i] -bxor $mask[$i % 4])) }

    $bytes = $frame.ToArray()
    $Conn.Stream.Write($bytes, 0, $bytes.Length)
}

function Receive-WSText {
    param($Conn)
    $stream = $Conn.Stream
    function ReadExact([int]$n) {
        $buf = New-Object byte[] $n
        $off = 0
        while ($off -lt $n) {
            $r = $stream.Read($buf, $off, $n - $off)
            if ($r -eq 0) { throw "Connessione WebSocket chiusa inaspettatamente." }
            $off += $r
        }
        return $buf
    }
    $full = New-Object System.Text.StringBuilder
    while ($true) {
        $hdr = ReadExact 2
        $fin = ($hdr[0] -band 0x80) -ne 0
        $masked = ($hdr[1] -band 0x80) -ne 0
        $len = [int64]($hdr[1] -band 0x7F)
        if ($len -eq 126) {
            $ext = ReadExact 2
            $len = ([int64]$ext[0] -shl 8) -bor [int64]$ext[1]
        } elseif ($len -eq 127) {
            $ext = ReadExact 8
            $len = 0
            for ($i = 0; $i -lt 8; $i++) { $len = ($len -shl 8) -bor [int64]$ext[$i] }
        }
        $maskKey = $null
        if ($masked) { $maskKey = ReadExact 4 }
        $payload = ReadExact ([int]$len)
        if ($masked) {
            for ($i = 0; $i -lt $len; $i++) { $payload[$i] = $payload[$i] -bxor $maskKey[$i % 4] }
        }
        [void]$full.Append([System.Text.Encoding]::UTF8.GetString($payload))
        if ($fin) { break }
    }
    return $full.ToString()
}

# ---------------------------------------------------------------------------
# Individua eseguibile e (per Brave/Opera GX) cartella User Data
# ---------------------------------------------------------------------------

$userDataDir = $null

if (-not $BrowserExe) {
    switch ($Browser) {
        "Chrome" {
            $BrowserExe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
            if (-not (Test-Path $BrowserExe)) {
                $BrowserExe = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            }
        }
        "Brave" {
            $BrowserExe = @(
                "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
                "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
                "$env:LocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe"
            ) | Where-Object { Test-Path $_ } | Select-Object -First 1
            $userDataDir = "$env:LocalAppData\BraveSoftware\Brave-Browser\User Data"
        }
        "OperaGX" {
            $BrowserExe = @(
                "$env:LocalAppData\Programs\Opera GX\opera.exe",
                "$env:LocalAppData\Programs\Opera GX\launcher.exe"
            ) | Where-Object { Test-Path $_ } | Select-Object -First 1
            $userDataDir = "$env:AppData\Opera Software\Opera GX Stable"
        }
    }
}
if (-not $BrowserExe -or -not (Test-Path $BrowserExe)) {
    throw "Eseguibile browser non trovato per '$Browser' (usa -BrowserExe per indicarlo a mano)."
}
if ($userDataDir -and -not (Test-Path $userDataDir)) {
    throw "Cartella profilo non trovata: $userDataDir"
}
$procName = [System.IO.Path]::GetFileNameWithoutExtension($BrowserExe)

$wasRunning = $null -ne (Get-Process -Name $procName -ErrorAction SilentlyContinue)
$offscreen  = $null

try {
    if ($wasRunning) {
        Write-Host "Chiudo $procName per poterlo riavviare con la porta di debug..."
        Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Process -Name $procName -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 300
        }
    }

    Write-Host "Avvio $procName fuori schermo sul tuo profilo reale..."
    $argList = @(
        "--remote-debugging-port=$Port",
        "--window-position=-32000,-32000",
        "--window-size=800,600",
        "--profile-directory=$ProfileDir"
    )
    if ($userDataDir) {
        $argList += "--user-data-dir=`"$userDataDir`""
        $argList += "--remote-allow-origins=*"
    }
    $argList += "about:blank"

    $offscreen = Start-Process $BrowserExe -ArgumentList $argList -PassThru -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(10)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 1 | Out-Null
            $ready = $true
            break
        } catch { Start-Sleep -Milliseconds 300 }
    }
    if (-not $ready) { throw "L'istanza fuori schermo non ha aperto la porta di debug in tempo." }

    $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json"
    $target = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    if (-not $target) { throw "Nessun target 'page' trovato nell'istanza fuori schermo." }

    $conn = Connect-WS -Uri $target.webSocketDebuggerUrl
    Send-WSText -Conn $conn -Text (@{ id = 1; method = "Network.getAllCookies" } | ConvertTo-Json -Compress)
    $raw = Receive-WSText -Conn $conn
    $conn.Tcp.Close()

    $response = $raw | ConvertFrom-Json
    Write-Host "DEBUG - cookie totali letti: $($response.result.cookies.Count)"
    $cookie = $response.result.cookies | Where-Object { $_.name -eq $CookieName -and $_.domain -like "*$Domain*" }

    if ($cookie) {
        foreach ($c in @($cookie)) {
            Write-Host "Dominio: $($c.domain)"
            $c.value
            if ($c.expires -gt 0) {
                $expiryDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$c.expires).LocalDateTime
                $expiryUtcIso = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]($c.expires * 1000)).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                Write-Host "Scadenza (raw, epoch seconds): $($c.expires)"
                Write-Host "Scadenza (ISO 8601 UTC): $expiryUtcIso"
                Write-Host "Scadenza: $expiryDate"
            } else {
                Write-Host "Scadenza: cookie di sessione (nessuna data fissa, scade alla chiusura del browser)"
            }
            Write-Host "---"
        }
    } else {
        Write-Warning "Cookie '$CookieName' non trovato per '$Domain'. Cookie disponibili per quel dominio:"
        $response.result.cookies | Where-Object { $_.domain -like "*$Domain*" } | Select-Object name, domain, httpOnly | Format-Table
    }
}
finally {
    if ($offscreen -and -not $offscreen.HasExited) {
        Stop-Process -Id $offscreen.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
    if ($wasRunning) {
        Write-Host "Riavvio $procName normale..."
        Start-Process $BrowserExe | Out-Null
    }
}
