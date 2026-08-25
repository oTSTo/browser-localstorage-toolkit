<#
.SYNOPSIS
  Svuota il Local Storage di UN sito in Brave o Opera GX, senza aprire il
  browser a schermo, usando il Chrome DevTools Protocol (CDP) — lo stesso
  meccanismo che usano i DevTools quando premi "Clear" sul pannello
  Application > Local Storage. Non tocca cookie, cache o login: cancella
  solo il local storage.

.PARAMETER Browser
  "Brave" oppure "OperaGX".

.PARAMETER Site
  Dominio o origin del sito da svuotare, es. "esempio.com" oppure
  "https://esempio.com". Usa lo stesso valore che vedi nella colonna "sito"
  del CSV / nella sidebar del tool di ispezione.

.PARAMETER ProfileDir
  Nome della cartella profilo (default "Default"). Se usi più profili nel
  browser, passa "Profile 1", "Profile 2", ecc.

.EXAMPLE
  .\Clear-SiteLocalStorage.ps1 -Browser Brave -Site esempio.com

.NOTES
  Chiudi COMPLETAMENTE il browser prima di eseguire lo script (Chromium non
  apre due istanze sullo stesso profilo). Svuotare il local storage di un
  sito lo disconnette e ne resetta lo stato salvato lato client — è
  l'equivalente esatto di premere "Clear" su quell'origine nei DevTools.
#>

param(
    [Parameter(Mandatory=$true)][ValidateSet("Brave","OperaGX")]$Browser,
    [Parameter(Mandatory=$true)][string]$Site,
    [string]$ProfileDir = "Default"
)

$ErrorActionPreference = "Stop"
$port = Get-Random -Minimum 9300 -Maximum 9400

# ---------------------------------------------------------------------
# 1) Normalizza l'origin (scheme://host[:port], niente path finale)
# ---------------------------------------------------------------------
$originInput = $Site
if ($originInput -notmatch '^https?://') { $originInput = "https://$originInput" }
$uri = [Uri]$originInput
$origin = "$($uri.Scheme)://$($uri.Authority)"

# ---------------------------------------------------------------------
# 2) Individua eseguibile, cartella profilo e nome processo
# ---------------------------------------------------------------------
switch ($Browser) {
    "Brave" {
        $procName = "brave"
        $exeCandidates = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
            "$env:LocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe"
        )
        $userDataDir = "$env:LocalAppData\BraveSoftware\Brave-Browser\User Data"
    }
    "OperaGX" {
        $procName = "opera"
        $exeCandidates = @(
            "$env:LocalAppData\Programs\Opera GX\opera.exe",
            "$env:LocalAppData\Programs\Opera GX\launcher.exe"
        )
        $userDataDir = "$env:AppData\Opera Software\Opera GX Stable"
    }
}

$exe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) {
    Write-Error "Eseguibile di $Browser non trovato nei percorsi noti. Apri lo script e correggi `$exeCandidates con il percorso giusto sul tuo PC."
    exit 1
}
if (-not (Test-Path $userDataDir)) {
    Write-Error "Cartella profilo non trovata: $userDataDir"
    exit 1
}

if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
    Write-Error "$Browser risulta aperto. Chiudilo completamente e riprova: serve per aprire il profilo in modalita' headless senza conflitti."
    exit 1
}

# ---------------------------------------------------------------------
# 3) Python + pacchetto websocket-client
# ---------------------------------------------------------------------
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python non trovato nel PATH."
    exit 1
}
Write-Host "Verifico/installo il pacchetto Python 'websocket-client'..."
python -m pip install --quiet --upgrade websocket-client
if ($LASTEXITCODE -ne 0) { Write-Error "Installazione di websocket-client fallita."; exit 1 }

# ---------------------------------------------------------------------
# 4) Script Python che parla CDP (scritto su disco al volo)
# ---------------------------------------------------------------------
$workDir = Join-Path $env:TEMP "cdp_clear_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$pyScript = Join-Path $workDir "clear_storage.py"
@'
import sys, json, urllib.request
import websocket

def http_json(url):
    with urllib.request.urlopen(url, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

port = sys.argv[1]
origin = sys.argv[2]

targets = http_json("http://127.0.0.1:" + port + "/json/list")
page = next((t for t in targets if t.get("type") == "page"), None)
if not page:
    print("ERRORE: nessuna scheda disponibile sul browser headless.")
    sys.exit(1)

ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=10)

def send(method, params, msg_id):
    ws.send(json.dumps({"id": msg_id, "method": method, "params": params}))
    while True:
        resp = json.loads(ws.recv())
        if resp.get("id") == msg_id:
            return resp

result = send("Storage.clearDataForOrigin",
               {"origin": origin, "storageTypes": "local_storage"}, 1)
ws.close()

if "error" in result:
    print("ERRORE CDP:", result["error"])
    sys.exit(1)

print("OK: local storage di " + origin + " svuotato (cookie e login non toccati).")
'@ | Set-Content -Path $pyScript -Encoding UTF8

# ---------------------------------------------------------------------
# 5) Avvia il browser in background, headless, sullo stesso profilo
# ---------------------------------------------------------------------
Write-Host "Avvio $Browser in background (nessuna finestra visibile)..."
$proc = Start-Process -FilePath $exe -ArgumentList @(
    "--headless=new",
    "--remote-debugging-port=$port",
    "--remote-allow-origins=*",
    "--user-data-dir=`"$userDataDir`"",
    "--profile-directory=`"$ProfileDir`"",
    "--no-first-run",
    "--disable-extensions",
    "about:blank"
) -PassThru -WindowStyle Hidden

# ---------------------------------------------------------------------
# 6) Attende che la porta di debug risponda
# ---------------------------------------------------------------------
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        Invoke-RestMethod "http://127.0.0.1:$port/json/version" -TimeoutSec 1 | Out-Null
        $ready = $true
        break
    } catch { }
}

if (-not $ready) {
    Write-Error "Il browser headless non ha risposto sulla porta $port entro il timeout."
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---------------------------------------------------------------------
# 7) Esegue la cancellazione via CDP e chiude tutto
# ---------------------------------------------------------------------
try {
    Write-Host "Svuoto il local storage di $origin ..."
    python $pyScript $port $origin
} finally {
    Start-Sleep -Milliseconds 400
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Istanza headless chiusa. Puoi riaprire $Browser normalmente."
}
