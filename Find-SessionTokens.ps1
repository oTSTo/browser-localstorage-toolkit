<#
.SYNOPSIS
  Cerca nei CSV esportati da Export-LocalStorage.ps1 le chiavi che sembrano
  token di sessione, filtrando per lunghezza del valore in stile token
  Discord, e le mostra a schermo per intero.

.DESCRIPTION
  1. Cerca i CSV in <BaseDir>\Brave\ e <BaseDir>\OperaGX\ (default
     C:\ProgramData\Test, la stessa cartella di default di
     Export-LocalStorage.ps1).
  2. Per ogni CSV, cerca le righe la cui chiave CONTIENE il testo indicato
     da -Pattern (case-insensitive): con il default "token" trova sia la
     chiave esatta "token" sia varianti comuni come "authToken",
     "access_token", "session_token", ecc.
  3. Tra quelle, tiene solo le righe il cui VALORE ha una lunghezza tra
     -MinLength e -MaxLength: i token Discord sono lunghi circa 59
     caratteri (standard pre-2022) fino a 70-80 (standard attuale), quindi
     il default 59-80 scarta il rumore (blob JSON, timestamp, contatori,
     ecc. che contengono "token" nella chiave ma non sono affatto un token).
  4. Mostra a schermo browser, profilo, sito, chiave e il valore per intero.

.PARAMETER BaseDir
  Cartella dove si trovano i CSV esportati. Default: C:\ProgramData\Test.

.PARAMETER Pattern
  Sottostringa da cercare nel nome della chiave (case-insensitive).
  Default: "token".

.PARAMETER MinLength
  Lunghezza minima del valore da mostrare. Default: 59.

.PARAMETER MaxLength
  Lunghezza massima del valore da mostrare. Default: 80.

.EXAMPLE
  .\Find-SessionTokens.ps1
  .\Find-SessionTokens.ps1 -MinLength 0 -MaxLength 999999
  (nessun filtro di lunghezza: mostra tutte le chiavi che contengono "token",
  utile se cerchi qualcosa che non e' un token Discord)

.NOTES
  - Richiede di aver gia' esportato i CSV con Export-LocalStorage.ps1.
  - I valori vengono mostrati in chiaro: trattali con cautela, non
    incollarli in posti pubblici (chat, issue, screenshot condivisi).
#>

param(
    [string]$BaseDir = "C:\ProgramData\Test",
    [string]$Pattern = "token",
    [int]$MinLength = 59,
    [int]$MaxLength = 80
)

$ErrorActionPreference = "Stop"
$browsers = @("Brave", "OperaGX")
$foundAny = $false

Write-Host "`nCerco chiavi che contengono '$Pattern' con valore lungo $MinLength-$MaxLength caratteri..." -ForegroundColor Cyan
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
        $hits = @($data | Where-Object {
            $_.chiave -like "*$Pattern*" -and
            $_.valore.Length -ge $MinLength -and
            $_.valore.Length -le $MaxLength
        })

        if ($hits.Count -eq 0) {
            Write-Host "  Nessuna corrispondenza in questo profilo" -ForegroundColor DarkGray
            continue
        }

        $foundAny = $true
        foreach ($row in $hits) {
            Write-Host ""
            Write-Host "TROVATO" -ForegroundColor Green
            Write-Host "  Browser   : $browser"
            Write-Host "  Profilo   : $($csv.BaseName)"
            Write-Host "  Sito      : $($row.sito)"
            Write-Host "  Chiave    : $($row.chiave)"
            Write-Host "  Valore    : $($row.valore)" -ForegroundColor Yellow
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
    Write-Host "  4. Provare ad allargare il filtro: -MinLength 0 -MaxLength 999999"
} else {
    Write-Host "Fatto." -ForegroundColor Green
}
