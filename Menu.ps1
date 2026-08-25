<#
.SYNOPSIS
  Menu interattivo (selezione a frecce, stile Claude Code CLI) che riunisce
  tutti gli strumenti del toolkit in un unico punto d'ingresso da PowerShell.

.DESCRIPTION
  Se lo lanci da un clone locale del repo (.\Menu.ps1) usa i file li' accanto;
  se lo lanci al volo (irm .../Menu.ps1 | iex) scarica ogni strumento da
  GitHub solo quando lo scegli dal menu.

  La selezione e' a frecce (Su/Giu, Invio conferma, Esc torna indietro; funzionano
  anche i tasti numerici come scorciatoia diretta). Se lo stdin non e' una vera
  console interattiva (input rediretto, host senza supporto ReadKey, ecc.) il
  menu passa da solo alla modalita' classica a numero + Invio.

  Ogni strumento gira in un PROCESSO FIGLIO separato (non nella sessione del
  menu): gli script del toolkit usano "exit" sui percorsi di errore, e
  chiamare "exit" dentro uno scriptblock creato al volo chiude l'intera
  finestra PowerShell, non solo quel comando. Isolandolo in un processo
  figlio, un errore in uno strumento chiude solo quello e torni al menu.

.EXAMPLE
  irm https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master/Menu.ps1 | iex
#>

$ErrorActionPreference = "Stop"
$RepoRaw = "https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master"
$hostExe = (Get-Process -Id $PID).Path

function Invoke-ToolChild {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [hashtable]$Params = @{}
    )

    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $Name))) {
        $localPath = Join-Path $PSScriptRoot $Name
        $loadExpr = "& '$($localPath -replace "'", "''")'"
    } else {
        $url = "$RepoRaw/$Name"
        $loadExpr = "& ([scriptblock]::Create((irm '$url')))"
    }

    $paramExpr = ""
    foreach ($k in $Params.Keys) {
        $v = $Params[$k]
        if ($v -is [bool]) {
            if ($v) { $paramExpr += " -$k" }
        } else {
            $paramExpr += " -$k '$($v -replace "'", "''")'"
        }
    }

    $fullCommand = $loadExpr + $paramExpr
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($fullCommand)
    $encoded = [Convert]::ToBase64String($bytes)

    Start-Process -FilePath $hostExe `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) `
        -NoNewWindow -Wait
}

function Read-Pause {
    Write-Host ""
    Read-Host "Premi invio per tornare al menu" | Out-Null
}

# ---------------------------------------------------------------------
# Picker a frecce, stile Claude Code CLI. Ritorna l'indice scelto (0-based)
# oppure $null se annullato con Esc.
# ---------------------------------------------------------------------
function Show-ArrowMenu {
    param([string[]]$Items, [string]$Title, [string]$Hint)

    $selected = 0
    $origVisible = $true
    try { $origVisible = [Console]::CursorVisible } catch {}

    try {
        try { [Console]::CursorVisible = $false } catch {}
        while ($true) {
            Clear-Host
            if ($Title) {
                Write-Host $Title -ForegroundColor Cyan
                Write-Host ""
            }
            for ($i = 0; $i -lt $Items.Count; $i++) {
                if ($i -eq $selected) {
                    Write-Host ("  " + [char]0x276F + " " + $Items[$i]) -ForegroundColor Cyan
                } else {
                    Write-Host ("    " + $Items[$i]) -ForegroundColor DarkGray
                }
            }
            Write-Host ""
            Write-Host $Hint -ForegroundColor DarkGray

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
                "W"         { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
                "DownArrow" { $selected = ($selected + 1) % $Items.Count }
                "S"         { $selected = ($selected + 1) % $Items.Count }
                "Enter"     { return $selected }
                "Escape"    { return $null }
                default {
                    if ($key.KeyChar -match '^[1-9]$') {
                        $idx = [int]([string]$key.KeyChar) - 1
                        if ($idx -ge 0 -and $idx -lt $Items.Count) { return $idx }
                    }
                }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $origVisible } catch {}
    }
}

# ---------------------------------------------------------------------
# Fallback: numero + Invio, per host senza vera console interattiva
# (input rediretto, ISE, ecc.) dove ReadKey/Clear-Host non funzionano.
# ---------------------------------------------------------------------
function Show-FallbackMenu {
    param([string[]]$Items, [string]$Title)

    if ($Title) { Write-Host $Title -ForegroundColor Cyan; Write-Host "" }
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $Items[$i])
    }
    Write-Host ""

    while ($true) {
        $ans = Read-Host "Scegli un numero (Invio vuoto per annullare)"
        # Invio vuoto = annulla. Copre anche il caso in cui lo stdin non sia
        # davvero interattivo (input rediretto/esaurito): li' Read-Host smette
        # di bloccarsi e torna sempre vuoto, quindi si esce subito invece di
        # girare all'infinito.
        if ([string]::IsNullOrEmpty($ans)) { return $null }
        $n = 0
        if ([int]::TryParse($ans, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
            return $n - 1
        }
        Write-Warning "Scelta non valida."
    }
}

function Show-InteractiveMenu {
    param(
        [Parameter(Mandatory=$true)][string[]]$Items,
        [string]$Title = "",
        [string]$Hint = "Su/Giu naviga  -  Invio conferma  -  Esc torna indietro"
    )
    if ([Console]::IsInputRedirected) {
        return Show-FallbackMenu -Items $Items -Title $Title
    }
    try {
        return Show-ArrowMenu -Items $Items -Title $Title -Hint $Hint
    } catch {
        return Show-FallbackMenu -Items $Items -Title $Title
    }
}

# ---------------------------------------------------------------------
# Menu principale
# ---------------------------------------------------------------------
$mainItems = @(
    "Esporta Local Storage (Brave/Opera GX) in CSV",
    "Svuota Local Storage di un sito (Brave/Opera GX)",
    "Disconnetti / reset Discord",
    "Esci"
)

while ($true) {
    $choice = Show-InteractiveMenu -Items $mainItems -Title "Browser LocalStorage Toolkit"

    if ($null -eq $choice -or $choice -eq ($mainItems.Count - 1)) { break }

    switch ($choice) {
        0 {
            Invoke-ToolChild -Name "Export-LocalStorage.ps1"
            Read-Pause
        }
        1 {
            $b = Show-InteractiveMenu -Items @("Brave", "Opera GX") -Title "Quale browser?"
            if ($null -ne $b) {
                $browser = if ($b -eq 1) { "OperaGX" } else { "Brave" }
                $site = Read-Host "Sito da svuotare (es. discord.com)"
                if ([string]::IsNullOrWhiteSpace($site)) {
                    Write-Warning "Nessun sito inserito, annullato."
                } else {
                    Invoke-ToolChild -Name "Clear-SiteLocalStorage.ps1" -Params @{ Browser = $browser; Site = $site }
                }
                Read-Pause
            }
        }
        2 {
            $appIdx = Show-InteractiveMenu -Items @("Discord (stabile)", "Discord PTB", "Discord Canary", "Discord Development") -Title "Quale build di Discord?"
            if ($null -ne $appIdx) {
                $app = @("Discord", "DiscordPTB", "DiscordCanary", "DiscordDevelopment")[$appIdx]
                $fullIdx = Show-InteractiveMenu -Items @("Solo Local Storage (ti disconnette)", "Reset completo (impostazioni + cache + login)") -Title "Cosa eliminare?"
                if ($null -ne $fullIdx) {
                    $params = @{ App = $app }
                    if ($fullIdx -eq 1) { $params["Full"] = $true }
                    Invoke-ToolChild -Name "Clear-DiscordLocalStorage.ps1" -Params $params
                    Read-Pause
                }
            }
        }
    }
}

Write-Host "Ciao!"
