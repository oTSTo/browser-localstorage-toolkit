# Browser Local Storage Toolkit

Tre strumenti per esportare, ispezionare e ripulire il **Local Storage** di
Brave e Opera GX su Windows.

⚠️ Il Local Storage può contenere token di sessione e altri dati sensibili
dei siti che visiti. Se rendi questo repository **pubblico**, non caricarci
mai i CSV esportati — solo gli script.

## File

| File | Cosa fa |
|---|---|
| `Export-LocalStorage.ps1` | Esporta il Local Storage di tutti i profili Brave/Opera GX trovati in CSV leggibili (uno per profilo). |
| `LocalStorage-Inspector.html` | App standalone (apri col doppio click) per caricare i CSV e navigarli come nei DevTools: filtro per sito, ricerca, pretty-print JSON/JWT. Nessun dato lascia il browser. |
| `Clear-SiteLocalStorage.ps1` | Svuota il Local Storage di un singolo sito in Brave o Opera GX via Chrome DevTools Protocol, senza aprire il browser a schermo. Non tocca cookie/login. |

## Requisiti

- Windows con PowerShell.
- [Python](https://python.org) 3.11+ nel PATH (usato per leggere/scrivere lo storage in modo sicuro, senza toccare i file LevelDB a mano). Se manca, gli script provano a installarlo da soli con `winget --silent` (nessuna finestra a schermo) prima di procedere.

## Uso rapido (senza scaricare nulla — scarica ed esegue al volo)

**Esportare tutto in CSV:**
```powershell
irm https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master/Export-LocalStorage.ps1 | iex
```

**Svuotare il local storage di un sito:**
```powershell
$url  = "https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master/Clear-SiteLocalStorage.ps1"
$path = "$env:TEMP\Clear-SiteLocalStorage.ps1"
Invoke-WebRequest $url -OutFile $path
Unblock-File $path
& $path -Browser OperaGX -Site esempio.com
```
(`-Browser` accetta `Brave` oppure `OperaGX`. Chiudi il browser prima di eseguirlo.)

**Ispezionare i CSV:** scarica `LocalStorage-Inspector.html` e aprilo col doppio click, poi trascina dentro i CSV generati.

## Note

- `Export-LocalStorage.ps1` chiede il browser chiuso solo per i profili che risultano bloccati: continua comunque con gli altri.
- `Clear-SiteLocalStorage.ps1` richiede il browser **completamente chiuso** (apre una seconda istanza headless sullo stesso profilo).
- Nessuno script modifica direttamente i file LevelDB: passano sempre dalle API ufficiali del browser (lettura via libreria Python `chromium-reader`, cancellazione via Chrome DevTools Protocol).
- Entrambi gli script controllano all'avvio se Python è nel PATH: se manca, provano a installarlo automaticamente con `winget` (richiede Windows 10/11 con App Installer aggiornato). Se `winget` non è disponibile, va installato manualmente da [python.org](https://python.org).
