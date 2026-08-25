<#
.SYNOPSIS
  Disconnette Discord (stabile, PTB, Canary o Development) eliminando i suoi
  dati locali su disco — nessun CDP/remote debugging: Discord lo rileva e lo
  blocca attivamente come misura anti-tampering, quindi qui si lavora solo a
  livello di file, con l'app chiusa.

.DESCRIPTION
  Discord e' un'app Electron: il Local Storage vive come cartella LevelDB su
  disco, esattamente come nei browser Chromium. Per svuotarlo non serve altro
  che chiudere il processo ed eliminare quella cartella.

.PARAMETER App
  Quale build di Discord: "Discord" (stabile), "DiscordPTB", "DiscordCanary"
  o "DiscordDevelopment". Default "Discord".

.PARAMETER Full
  Se presente, elimina l'INTERA cartella dati dell'app (%AppData%\<app>)
  invece della sola "Local Storage": reset completo (impostazioni, cache,
  account salvati, tutto), non solo il login. Senza questo switch viene
  eliminata solo la cartella "Local Storage" (login incluso, il resto delle
  impostazioni resta).

.EXAMPLE
  .\Clear-DiscordLocalStorage.ps1
  Svuota solo il Local Storage di Discord stabile (ti disconnette).

.EXAMPLE
  .\Clear-DiscordLocalStorage.ps1 -App DiscordCanary -Full
  Reset completo di Discord Canary: cancella tutta la cartella dati.

.NOTES
  Lo script chiude Discord da solo (Stop-Process -Force) prima di toccare i
  file: non serve chiuderlo a mano, ma assicurati di non avere lavoro non
  salvato in altre app collegate (es. overlay, bot locali, ecc.).
#>

param(
    [ValidateSet("Discord", "DiscordPTB", "DiscordCanary", "DiscordDevelopment")]
    [string]$App = "Discord",
    [switch]$Full
)

$ErrorActionPreference = "Stop"

$appDir = Join-Path $env:AppData $App.ToLower()

if (-not (Test-Path $appDir)) {
    Write-Error "Cartella dati non trovata per $App`: $appDir. Verifica di aver scelto la build giusta con -App (Discord/DiscordPTB/DiscordCanary/DiscordDevelopment)."
    exit 1
}

Write-Host "Chiudo $App se aperto..."
Get-Process -Name $App -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

if ($Full) {
    Write-Host "Elimino l'intera cartella dati di $App`: $appDir"
    Remove-Item $appDir -Recurse -Force
    Write-Host "Fatto. $App e' stato resettato completamente (impostazioni, cache e login: tutto pulito)."
} else {
    $lsDir = Join-Path $appDir "Local Storage"
    if (-not (Test-Path $lsDir)) {
        Write-Warning "Nessuna cartella 'Local Storage' trovata per $App (forse era gia' pulita)."
        exit 0
    }
    Write-Host "Elimino il Local Storage di $App`: $lsDir"
    Remove-Item $lsDir -Recurse -Force
    Write-Host "Fatto. Local storage di $App svuotato (ti disconnette). Le altre impostazioni restano."
}
