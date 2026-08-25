<#
.SYNOPSIS
  Esporta il Local Storage (LevelDB) di Brave e Opera GX in file CSV leggibili.

.DESCRIPTION
  1. Individua le cartelle "Local Storage\leveldb" dei profili Brave e Opera GX.
  2. Le copia in una cartella temporanea (per evitare il lock del browser).
  3. Usa il pacchetto Python "chromium-reader" (pip install chromium-reader)
     per decodificare il LevelDB e scrivere un CSV per ogni profilo trovato.

.NOTES
  - Richiede Python 3.11+ nel PATH.
  - Chiudi Brave e Opera GX prima di eseguire lo script: se il browser e'
    aperto, alcuni file possono essere bloccati e la copia di quel profilo
    fallisce (lo script continua comunque con gli altri profili).
  - I CSV finiscono in: C:\ProgramData\Test\<Browser>\<Profilo>.csv
    (una sottocartella per browser, un CSV per profilo)
  - Il Local Storage puo' contenere token di sessione o altri dati sensibili
    dei siti che hai visitato: tratta i CSV generati di conseguenza.
#>

$ErrorActionPreference = "Stop"

$outDir  = "C:\ProgramData\Test"
$workDir = Join-Path $env:TEMP "ls_export_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $outDir  | Out-Null
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

# ---------------------------------------------------------------------
# 1) Python (auto-installazione se manca) + pacchetto chromium-reader
# ---------------------------------------------------------------------
function Test-PythonWorks {
    # Su Windows, "python" puo' esistere nel PATH come stub "App execution alias"
    # dello Store anche se Python NON e' installato: Get-Command lo trova, ma
    # eseguirlo non stampa una versione reale. Verifichiamo l'output, non solo
    # la presenza del comando.
    try {
        $v = & python --version 2>&1
        return ($LASTEXITCODE -eq 0 -and $v -match 'Python \d+\.\d+')
    } catch { return $false }
}

function Test-PythonOrInstall {
    if (Test-PythonWorks) { return }

    Write-Warning "Python non trovato (o e' solo lo stub dello Store) nel PATH. Provo a installarlo in silenzioso con winget (nessuna finestra visibile)..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "winget non disponibile. Installa Python (>=3.11) da https://python.org e riprova."
        exit 1
    }

    winget install --id Python.Python.3.12 -e --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Installazione automatica di Python fallita. Installalo manualmente da https://python.org e riprova."
        exit 1
    }

    # winget aggiorna il PATH di sistema/utente, ma non quello della sessione corrente
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Test-PythonWorks)) {
        # Lo stub dello Store puo' avere priorita' nel PATH rispetto alla vera
        # installazione appena fatta: cerchiamo l'eseguibile reale e lo mettiamo davanti.
        $realPython = Get-ChildItem -Path @(
            "$env:LocalAppData\Programs\Python\Python3*\python.exe",
            "$env:ProgramFiles\Python3*\python.exe"
        ) -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($realPython) {
            $env:Path = (Split-Path $realPython.FullName) + ";" + $env:Path
        }
    }

    if (-not (Test-PythonWorks)) {
        Write-Error "Python e' stato installato ma 'python' non funziona ancora in questa sessione (probabile stub del Microsoft Store davanti nel PATH). Chiudi e riapri PowerShell e rilancia lo script; se persiste, disattiva l'alias in Impostazioni > App > Impostazioni app avanzate > Alias di esecuzione app > 'python.exe' su Off."
        exit 1
    }
    Write-Host "Python installato correttamente."
}

Test-PythonOrInstall

Write-Host "Verifico/installo il pacchetto Python 'chromium-reader'..."
python -m pip install --quiet --upgrade chromium-reader
if ($LASTEXITCODE -ne 0) {
    Write-Error "Installazione di chromium-reader fallita. Verifica pip/Python."
    exit 1
}

# ---------------------------------------------------------------------
# 2) Script Python di lettura (scritto su disco al volo)
# ---------------------------------------------------------------------
$readerPy = Join-Path $workDir "read_localstorage.py"
@'
import sys, csv
from pathlib import Path
from chromium_reader.localstorage import LocalStorageReader

leveldb_path = Path(sys.argv[1])
output_csv   = Path(sys.argv[2])
label        = sys.argv[3] if len(sys.argv) > 3 else str(leveldb_path)

rows = []
with LocalStorageReader(leveldb_path) as reader:
    for record in reader.records():
        host = getattr(record, "host", None) or getattr(record, "origin", "sconosciuto")
        rows.append((label, host, record.script_key, str(record.value)))

with open(output_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["browser_profilo", "sito", "chiave", "valore"])
    w.writerows(rows)

print(f"[{label}] {len(rows)} record -> {output_csv}")
'@ | Set-Content -Path $readerPy -Encoding UTF8

# ---------------------------------------------------------------------
# 3) Individua i profili Brave e Opera GX
# ---------------------------------------------------------------------
function Find-LocalStorageFolders($root) {
    if (-not (Test-Path $root)) { return @() }
    Get-ChildItem -Path $root -Recurse -Directory -Filter "leveldb" -ErrorAction SilentlyContinue |
        Where-Object { $_.Parent.Name -eq "Local Storage" }
}

$targets = @()

$braveRoot = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data"
Find-LocalStorageFolders $braveRoot | ForEach-Object {
    $targets += [PSCustomObject]@{ Browser = "Brave"; Profile = $_.Parent.Parent.Name; Path = $_.FullName }
}

$operaGxRoot = Join-Path $env:APPDATA "Opera Software\Opera GX Stable"
Find-LocalStorageFolders $operaGxRoot | ForEach-Object {
    $targets += [PSCustomObject]@{ Browser = "OperaGX"; Profile = $_.Parent.Parent.Name; Path = $_.FullName }
}

if ($targets.Count -eq 0) {
    Write-Warning "Nessuna cartella Local Storage trovata per Brave/Opera GX nei percorsi standard."
    exit 0
}

Write-Host "`nProfili trovati:"
$targets | ForEach-Object { Write-Host "  - $($_.Browser) [$($_.Profile)] -> $($_.Path)" }

# ---------------------------------------------------------------------
# 4) Copia ogni profilo ed esegue la conversione
# ---------------------------------------------------------------------
foreach ($t in $targets) {
    $label      = "$($t.Browser)_$($t.Profile)"
    $copyDest   = Join-Path $workDir $label
    $browserDir = Join-Path $outDir $t.Browser
    New-Item -ItemType Directory -Force -Path $browserDir | Out-Null
    $csvOut     = Join-Path $browserDir "$($t.Profile).csv"

    Write-Host "`nCopio $label..."
    try {
        Copy-Item -Path $t.Path -Destination $copyDest -Recurse -Force
    } catch {
        Write-Warning "Copia fallita per $label (probabilmente il browser e' aperto): $_"
        continue
    }

    python $readerPy $copyDest $csvOut $label
}

Write-Host "`nFatto. CSV salvati in: $outDir"
