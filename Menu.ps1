<#
.SYNOPSIS
  Menu interattivo che riunisce tutti gli strumenti del toolkit in un unico
  punto d'ingresso da PowerShell.

.DESCRIPTION
  Se lo lanci da un clone locale del repo (.\Menu.ps1) usa i file li' accanto;
  se lo lanci al volo (irm .../Menu.ps1 | iex) scarica ogni strumento da
  GitHub solo quando lo scegli dal menu.

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

function Read-BrowserChoice {
    Write-Host "  1) Brave"
    Write-Host "  2) Opera GX"
    $c = Read-Host "Browser"
    if ($c -eq "2") { "OperaGX" } else { "Brave" }
}

function Read-DiscordAppChoice {
    Write-Host "  1) Discord (stabile)"
    Write-Host "  2) Discord PTB"
    Write-Host "  3) Discord Canary"
    Write-Host "  4) Discord Development"
    $c = Read-Host "Quale build (invio = stabile)"
    switch ($c) {
        "2" { "DiscordPTB" }
        "3" { "DiscordCanary" }
        "4" { "DiscordDevelopment" }
        default { "Discord" }
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Browser LocalStorage Toolkit" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Esporta Local Storage (Brave/Opera GX) in CSV"
    Write-Host "  2) Svuota Local Storage di un sito (Brave/Opera GX)"
    Write-Host "  3) Disconnetti / reset Discord"
    Write-Host "  4) Apri l'Inspector CSV (HTML)"
    Write-Host "  5) Apri l'Inspector CSV (Electron, CSV pesanti)"
    Write-Host "  0) Esci"
    Write-Host ""
}

$script:emptyStreak = 0

:menu while ($true) {
    Show-Menu
    $choice = Read-Host "Scegli un'opzione"

    # Se lo stdin non e' un terminale interattivo vero (es. rilancio non
    # interattivo, input rediretto esaurito), Read-Host smette di bloccarsi e
    # restituisce sempre stringa vuota: senza questa guardia il menu
    # girerebbe all'infinito a vuoto invece di aspettare un utente reale.
    if ([string]::IsNullOrEmpty($choice)) {
        $script:emptyStreak++
        if ($script:emptyStreak -ge 3) {
            Write-Warning "Nessun input disponibile, esco."
            break menu
        }
    } else {
        $script:emptyStreak = 0
    }

    switch ($choice) {
        "1" {
            Invoke-ToolChild -Name "Export-LocalStorage.ps1"
            Read-Pause
        }
        "2" {
            $browser = Read-BrowserChoice
            $site = Read-Host "Sito da svuotare (es. discord.com)"
            if ([string]::IsNullOrWhiteSpace($site)) {
                Write-Warning "Nessun sito inserito, annullato."
            } else {
                Invoke-ToolChild -Name "Clear-SiteLocalStorage.ps1" -Params @{ Browser = $browser; Site = $site }
            }
            Read-Pause
        }
        "3" {
            $app = Read-DiscordAppChoice
            $fullAns = Read-Host "Reset completo (impostazioni+cache+login) invece del solo Local Storage? (s/N)"
            $params = @{ App = $app }
            if ($fullAns -match '^[sS]') { $params["Full"] = $true }
            Invoke-ToolChild -Name "Clear-DiscordLocalStorage.ps1" -Params $params
            Read-Pause
        }
        "4" {
            $dest = Join-Path $env:TEMP "LocalStorage-Inspector.html"
            if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "LocalStorage-Inspector.html"))) {
                $dest = Join-Path $PSScriptRoot "LocalStorage-Inspector.html"
            } else {
                Invoke-RestMethod "$RepoRaw/LocalStorage-Inspector.html" -OutFile $dest
            }
            Start-Process $dest
        }
        "5" {
            $electronDir = if ($PSScriptRoot) { Join-Path $PSScriptRoot "csv-inspector-electron" } else { $null }
            if ($electronDir -and (Test-Path (Join-Path $electronDir "package.json"))) {
                if (-not (Test-Path (Join-Path $electronDir "node_modules"))) {
                    Write-Host "Prima installazione: eseguo 'npm install' in csv-inspector-electron (puo' volerci un minuto)..."
                    Start-Process -FilePath "npm" -ArgumentList @("install") -WorkingDirectory $electronDir -NoNewWindow -Wait
                }
                Start-Process -FilePath "npm" -ArgumentList @("start") -WorkingDirectory $electronDir -NoNewWindow
            } else {
                Write-Warning "Cartella csv-inspector-electron non trovata qui accanto. Clona il repo intero e riprova, oppure vedi csv-inspector-electron/README.md su GitHub."
                Read-Pause
            }
        }
        "0" { break menu }
        default {
            Write-Warning "Scelta non valida."
            Start-Sleep -Milliseconds 900
        }
    }
}

Write-Host "Ciao!"
