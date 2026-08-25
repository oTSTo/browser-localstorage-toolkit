# LocalStorage CSV Inspector (Electron)

Versione desktop di `LocalStorage-Inspector.html`, pensata per i CSV
**pesanti** che nella versione browser bloccavano la pagina.

## Perché la versione HTML si blocca su CSV grandi

`LocalStorage-Inspector.html` legge l'intero file in memoria, lo fa il
parsing in un unico ciclo sincrono e poi crea una riga `<tr>` nel DOM per
**ogni** riga del CSV tutta in un colpo. Con un file grande (molti record o
valori JSON pesanti) questo blocca il thread della pagina abbastanza a lungo
da far apparire "la pagina non risponde".

## Come risolve questa versione

- **Parsing in streaming**: il file viene letto a blocchi da 1MB nel
  processo main (Node), non nel renderer/finestra. Anche un CSV da centinaia
  di MB non blocca mai la UI, perché il parsing gira in un processo separato
  dalla finestra e i risultati arrivano via IPC a lotti di 2000 righe.
- **Tabella virtualizzata**: nella griglia esistono sempre solo ~50-80 righe
  DOM reali, quelle visibili nello scroll (più un margine). Non importa se
  un'origine ha 500 o 500.000 chiavi: il rendering resta leggero.
- **Indicizzazione per sito**: le righe sono raggruppate per sito già in
  fase di caricamento, quindi selezionare un'origine o cercare non richiede
  mai una scansione di tutto il dataset.

Stesso identico aspetto/funzionalità della versione HTML (rail dei siti,
filtro browser, ricerca chiavi/valori, pannello con pretty-print JSON/JWT,
copia negli appunti) — cambia solo cosa succede sotto al cofano.

## Uso

```powershell
cd csv-inspector-electron
npm install
npm start
```

Si apre la finestra dell'app: premi **Carica CSV** (dialogo nativo di
Windows) oppure trascina direttamente i file da `C:\ProgramData\Test`.

## Creare un eseguibile portabile (.exe), opzionale

```powershell
npm run dist
```

Genera un `.exe` portabile in `dist/` (via `electron-builder`), da poter
copiare e lanciare senza installare Node/Electron su un altro PC.

## Note

- Nessun dato lascia il tuo PC: tutto il parsing avviene in locale.
- Non serve Python qui — a differenza degli script PowerShell del toolkit,
  questa è un'app Node/Electron indipendente.
