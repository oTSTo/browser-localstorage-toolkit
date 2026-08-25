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

`Clear-SiteLocalStorage.ps1` richiede parametri (`-Browser`, `-Site`), quindi
il semplice `irm URL | iex` non basta da solo (scarica solo il testo, non lo
esegue con argomenti). Due modi per lanciarlo con i parametri:

One-liner, tutto in memoria, niente file salvato su disco:
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master/Clear-SiteLocalStorage.ps1))) -Browser Brave -Site discord.com
```

Oppure scaricalo su file e poi eseguilo:
```powershell
$url  = "https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master/Clear-SiteLocalStorage.ps1"
$path = "$env:TEMP\Clear-SiteLocalStorage.ps1"
Invoke-WebRequest $url -OutFile $path
Unblock-File $path
& $path -Browser OperaGX -Site esempio.com
```
(`-Browser` accetta `Brave` oppure `OperaGX`, `-Site` è il dominio del sito. Chiudi il browser prima di eseguirlo.)

**Ispezionare i CSV:** scarica `LocalStorage-Inspector.html` e aprilo col doppio click, poi trascina dentro i CSV generati.

## Eseguire su un PC secondario (senza clonare il repo)

Gli script non hanno dipendenze da percorsi locali o nomi utente: usano solo
variabili d'ambiente (`$env:LOCALAPPDATA`, `$env:APPDATA`, `$env:TEMP`, ecc.),
quindi funzionano su qualunque PC Windows così come sono, senza modifiche.
Su un PC dove non hai clonato il repo, apri PowerShell (non serve admin) e
lancia direttamente i comandi della sezione "Uso rapido" qui sopra:

```powershell
irm https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/master/Export-LocalStorage.ps1 | iex
```

Usando `irm | iex` lo script gira come comandi in memoria, quindi non serve
`Unblock-File` né toccare l'Execution Policy. Per lo script con parametri
(`Clear-SiteLocalStorage.ps1`) usa il one-liner con scriptblock (vedi sopra
"Svuotare il local storage di un sito"). Se sul PC secondario manca Python,
viene installato da solo in silenzioso — vedi la nota sotto.

I CSV generati restano su **quel** PC, in `C:\ProgramData\Test`: per
analizzarli sul PC principale vanno copiati manualmente (USB, rete, ecc.).

**Se subito dopo un push l'URL con `/master/` esegue ancora la versione
precedente dello script:** è la cache CDN di `raw.githubusercontent.com` che
non si è ancora aggiornata (di solito impiega pochi minuti). Nel frattempo
punta al commit esatto invece del branch, usando lo SHA dell'ultimo commit
(visibile su GitHub o con `git rev-parse HEAD`):

```powershell
irm https://raw.githubusercontent.com/oTSTo/browser-localstorage-toolkit/<COMMIT_SHA>/Export-LocalStorage.ps1 | iex
```

## Note

- Nessuno script apre finestre a schermo (Esplora file, browser, ecc.): lavorano tutti in silenzioso, il percorso dei CSV compare solo come testo in console.
- `Export-LocalStorage.ps1` chiede il browser chiuso solo per i profili che risultano bloccati: continua comunque con gli altri.
- `Clear-SiteLocalStorage.ps1` richiede il browser **completamente chiuso** (apre una seconda istanza headless sullo stesso profilo).
- Nessuno script modifica direttamente i file LevelDB: passano sempre dalle API ufficiali del browser (lettura via libreria Python `chromium-reader`, cancellazione via Chrome DevTools Protocol).
- Entrambi gli script controllano all'avvio se Python è nel PATH: se manca, provano a installarlo automaticamente con `winget` (richiede Windows 10/11 con App Installer aggiornato). Se `winget` non è disponibile, va installato manualmente da [python.org](https://python.org).
- **PC senza Python mai installato:** Windows mette comunque un finto `python.exe` nel PATH (l'"App execution alias" collegato al Microsoft Store), quindi se lanci `python --version` a mano ottieni "Python was not found; run without arguments to install from the Microsoft Store...". Gli script lo riconoscono e installano comunque Python davvero con `winget`; se dopo l'installazione vedi ancora errori, apri **Impostazioni > App > Impostazioni app avanzate > Alias di esecuzione app** e disattiva `python.exe`/`python3.exe`, poi riapri PowerShell e rilancia lo script.
