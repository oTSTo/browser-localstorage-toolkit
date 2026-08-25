// Processo main: apre la finestra e fa lo streaming/parsing dei CSV.
// Il parsing gira qui (processo Node separato dalla finestra), a blocchi,
// cosi' anche un CSV pesante non blocca mai la UI del renderer.

const { app, BrowserWindow, dialog, ipcMain } = require("electron");
const path = require("path");
const fs = require("fs");

const BATCH_SIZE = 2000; // righe per messaggio IPC verso il renderer
const CHUNK_BYTES = 1 << 20; // 1MB per lettura dal disco

let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1320,
    height: 840,
    minWidth: 760,
    minHeight: 480,
    backgroundColor: "#0f131a",
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));
}

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("pick-csv-files", async () => {
  const res = await dialog.showOpenDialog(mainWindow, {
    title: "Carica CSV",
    filters: [{ name: "CSV", extensions: ["csv"] }],
    properties: ["openFile", "multiSelections"],
  });
  if (res.canceled) return [];
  return res.filePaths;
});

ipcMain.on("load-csv-files", (event, filePaths) => {
  streamAllFiles(event.sender, Array.isArray(filePaths) ? filePaths : []);
});

// ---------------------------------------------------------------------
// Parser CSV incrementale: stesse regole di escaping del parser usato in
// LocalStorage-Inspector.html (virgolette doppie, campi con virgole/a-capo
// tra virgolette), ma con stato mantenuto tra un chunk e l'altro cosi' da
// poter leggere il file a blocchi invece che tutto in memoria in un colpo.
// ---------------------------------------------------------------------
class CsvStreamParser {
  constructor() {
    this.row = [];
    this.field = "";
    this.inQuotes = false;
    this.first = true;
  }

  push(chunk) {
    if (this.first) {
      this.first = false;
      if (chunk.charCodeAt(0) === 0xfeff) chunk = chunk.slice(1);
    }
    const out = [];
    for (let i = 0; i < chunk.length; i++) {
      const c = chunk[i];
      if (this.inQuotes) {
        if (c === '"') {
          if (chunk[i + 1] === '"') {
            this.field += '"';
            i++;
          } else {
            this.inQuotes = false;
          }
        } else {
          this.field += c;
        }
      } else if (c === '"') {
        this.inQuotes = true;
      } else if (c === ",") {
        this.row.push(this.field);
        this.field = "";
      } else if (c === "\n") {
        this.row.push(this.field);
        out.push(this.row);
        this.row = [];
        this.field = "";
      } else if (c !== "\r") {
        this.field += c;
      }
    }
    return out;
  }

  flush() {
    if (this.field.length || this.row.length) {
      this.row.push(this.field);
      const r = this.row;
      this.row = [];
      this.field = "";
      return [r];
    }
    return [];
  }
}

function streamAllFiles(sender, filePaths) {
  let idx = 0;
  function next() {
    if (idx >= filePaths.length) {
      sender.send("load-done");
      return;
    }
    streamOneFile(sender, filePaths[idx++], next);
  }
  next();
}

function streamOneFile(sender, filePath, done) {
  const fileName = path.basename(filePath);
  const parser = new CsvStreamParser();
  let headerHandled = false;
  let colIdx = null;
  let batch = [];
  let rowCount = 0;
  let finished = false;

  function flushBatch(force) {
    if (batch.length && (force || batch.length >= BATCH_SIZE)) {
      sender.send("rows-batch", { fileName, rows: batch });
      batch = [];
    }
  }

  function handleParsedRows(parsedRows) {
    for (const line of parsedRows) {
      if (line.length === 1 && line[0] === "") continue;
      if (!headerHandled) {
        headerHandled = true;
        const head = line.map((h) => String(h).trim().toLowerCase());
        let iB = head.indexOf("browser_profilo");
        let iS = head.indexOf("sito");
        let iK = head.indexOf("chiave");
        let iV = head.indexOf("valore");
        if (iK < 0 || iV < 0) {
          iB = 0;
          iS = 1;
          iK = 2;
          iV = 3;
        }
        colIdx = { iB, iS, iK, iV };
        continue;
      }
      const { iB, iS, iK, iV } = colIdx;
      batch.push({
        browser: line[iB] || "sconosciuto",
        site: line[iS] || "sconosciuto",
        key: line[iK] || "",
        value: line[iV] || "",
      });
      rowCount++;
    }
    flushBatch(false);
  }

  let stream;
  try {
    stream = fs.createReadStream(filePath, {
      encoding: "utf8",
      highWaterMark: CHUNK_BYTES,
    });
  } catch (err) {
    sender.send("file-error", { fileName, message: String((err && err.message) || err) });
    done();
    return;
  }

  stream.on("data", (chunk) => {
    const parsedRows = parser.push(chunk);
    if (parsedRows.length) handleParsedRows(parsedRows);
  });

  stream.on("end", () => {
    if (finished) return;
    finished = true;
    const parsedRows = parser.flush();
    if (parsedRows.length) handleParsedRows(parsedRows);
    flushBatch(true);
    sender.send("file-done", { fileName, rowCount });
    done();
  });

  stream.on("error", (err) => {
    if (finished) return;
    finished = true;
    sender.send("file-error", { fileName, message: String((err && err.message) || err) });
    done();
  });
}
