<#
.SYNOPSIS
  Cerca nei CSV esportati da Export-LocalStorage.ps1 le chiavi che sembrano
  token di sessione, e le mostra a schermo.

.DESCRIPTION
  1. Cerca i CSV in <BaseDir>\Brave\ e <BaseDir>\OperaGX\ (default
     C:\ProgramData\Test, la stessa cartella di default di
     Export-LocalStorage.ps1).
  2. Per ogni CSV, cerca le righe la cui chiave CONTIENE il testo indicato
     da -Pattern (case-insensitive): con il default "token" trova sia la
     chiave esatta "token" sia varianti comuni come "authToken",
     "access_token", "session_token", ecc.
  3. Mostra a schermo browser, profilo, sito, chiave e il valore trovato.
     Per default il valore viene MASCHERATO (mostra solo inizio/fine e la
     lunghezza): serve a capire dove si trova un token, non a leggerlo.

.PARAMETER BaseDir
  Cartella dove si trovano i CSV esportati. Default: C:\ProgramData\Test.

.PARAMETER Pattern
  Sottostringa da cercare nel nome della chiave (case-insensitive).
  Default: "token".

.PARAMETER Reveal
  Mostra il valore per intero invece che mascherato. Da usare solo se ti
  serve davvero leggere il token, con lo schermo non condiviso/registrato.

.EXAMPLE
  .\Find-SessionTokens.ps1
  .\Find-SessionTokens.ps1 -Pattern "jwt"
  .\Find-SessionTokens.ps1 -Reveal

.NOTES
  - Richiede di aver gia' esportato i CSV con Export-LocalStorage.ps1.
  - Anche mascherato, questo strumento conferma DOVE esistono dei token:
    tratta comunque l'output con cautela.
#>

param(
    [string]$BaseDir = "C:\ProgramData\Test",
    [string]$Pattern = "token",
    [switch]$Reveal
)

function Get-MaskedValue {
    param([string]$Value)
    $len = $Value.Length
    if ($len -le 8) { return ("*" * $len) }
    return $Value.Substring(0, 4) + ("*" * 6) + $Value.Substring($len - 4)
}

$ErrorActionPreference = "Stop"
$browsers = @("Brave", "OperaGX")
$foundAny = $false

Write-Host "`nCerco chiavi che contengono '$Pattern' nei CSV esportati..." -ForegroundColor Cyan
Write-Host ""

foreach ($browser in $browsers) {
    $browserDir = Join-Path $BaseDir $browser
    if (-not (Test-Path $browserDir)) {
        Write-Warning "Nessuna cartella per $browser in $browserDir"
        continue
    }

    $csvFiles = @(Get-ChildItem -Path $browserDir -Filter "*.csv" -File)
    if ($csvFiles.Count -eq 0) {
        Write-Warning "Nessun CSV trovato in $browserDir"
        continue
    }

    foreach ($csv in $csvFiles) {
        Write-Host "Analizzo: $($csv.FullName)" -ForegroundColor Gray

        $data = Import-Csv -Path $csv.FullName -Encoding UTF8
        $hits = @($data | Where-Object { $_.chiave -like "*$Pattern*" })

        if ($hits.Count -eq 0) {
            Write-Host "  Nessuna corrispondenza in questo profilo" -ForegroundColor DarkGray
            continue
        }

        $foundAny = $true
        foreach ($row in $hits) {
            $displayValue = if ($Reveal) { $row.valore } else { Get-MaskedValue $row.valore }
            Write-Host ""
            Write-Host "TROVATO" -ForegroundColor Green
            Write-Host "  Browser   : $browser"
            Write-Host "  Profilo   : $($csv.BaseName)"
            Write-Host "  Sito      : $($row.sito)"
            Write-Host "  Chiave    : $($row.chiave)"
            Write-Host "  Valore    : $displayValue" -ForegroundColor Yellow
            Write-Host "  Lunghezza : $($row.valore.Length) caratteri" -ForegroundColor DarkGray
            Write-Host "  ------------------------------------" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
if (-not $foundAny) {
    Write-Warning "Nessuna corrispondenza trovata in nessun CSV."
    Write-Host ""
    Write-Host "Verifica di:" -ForegroundColor Yellow
    Write-Host "  1. Aver esportato i CSV (opzione 'Esporta Local Storage' del menu)"
    Write-Host "  2. Aver chiuso i browser prima dell'esportazione"
    Write-Host "  3. Avere davvero sessioni attive salvate nei browser"
} else {
    Write-Host "Fatto." -ForegroundColor Green
}
