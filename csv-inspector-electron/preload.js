const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("api", {
  pickCSVFiles: () => ipcRenderer.invoke("pick-csv-files"),
  loadCSVFiles: (paths) => ipcRenderer.send("load-csv-files", paths),
  // Electron non espone piu' File.path direttamente al renderer per motivi
  // di sicurezza: webUtils.getPathForFile e' il modo supportato per
  // recuperare il percorso reale di un file trascinato (drag & drop).
  getPathForFile: (file) => webUtils.getPathForFile(file),

  onRowsBatch: (cb) => {
    const handler = (_e, data) => cb(data);
    ipcRenderer.on("rows-batch", handler);
    return () => ipcRenderer.removeListener("rows-batch", handler);
  },
  onFileDone: (cb) => {
    const handler = (_e, data) => cb(data);
    ipcRenderer.on("file-done", handler);
    return () => ipcRenderer.removeListener("file-done", handler);
  },
  onFileError: (cb) => {
    const handler = (_e, data) => cb(data);
    ipcRenderer.on("file-error", handler);
    return () => ipcRenderer.removeListener("file-error", handler);
  },
  onLoadDone: (cb) => {
    const handler = () => cb();
    ipcRenderer.on("load-done", handler);
    return () => ipcRenderer.removeListener("load-done", handler);
  },
});
