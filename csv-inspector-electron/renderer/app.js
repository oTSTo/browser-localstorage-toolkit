(function () {
  "use strict";

  var ROW_H = 30;

  // Dati indicizzati per sito fin dall'ingestione, cosi' filtrare/mostrare
  // un'origine non richiede mai una scansione di tutto il dataset: e'
  // questo, insieme alla tabella virtualizzata piu' sotto, il motivo per
  // cui qui i CSV pesanti non bloccano la UI.
  var rowsBySite = new Map(); // site -> Array<{browser,site,key,value}>
  var siteBrowserCounts = new Map(); // site -> Map<browser, count>
  var siteOrderSeen = []; // ordine di prima apparizione dei siti (no duplicati)
  var browsersSeen = new Set();
  var totalRows = 0;
  var fileNames = [];
  var loadErrors = [];
  var isLoading = false;

  var activeSite = null;
  var activeBrowser = null;
  var siteQuery = "";
  var findQuery = "";
  var filteredList = [];
  var selectedRowRef = null;

  var $ = function (id) { return document.getElementById(id); };
  var loadBtn = $("loadBtn"), resetBtn = $("resetBtn"), browserFilter = $("browserFilter"),
      loadMeta = $("loadMeta"), siteSearch = $("siteSearch"), railList = $("railList"),
      originCount = $("originCount"), curOrigin = $("curOrigin"), curBadge = $("curBadge"),
      findBox = $("findBox"), rowCount = $("rowCount"), blank = $("blank"),
      gridScroll = $("gridScroll"), gridSpacer = $("gridSpacer"), gridRows = $("gridRows"),
      inspect = $("inspect"), iKey = $("iKey"), iType = $("iType"), iSize = $("iSize"),
      iBody = $("iBody"), copyBtn = $("copyBtn"), closeBtn = $("closeBtn"), drop = $("drop");

  /* ---------------- Ingestione ---------------- */
  function ingestRows(newRows) {
    for (var i = 0; i < newRows.length; i++) {
      var r = newRows[i];
      totalRows++;

      var arr = rowsBySite.get(r.site);
      if (!arr) { arr = []; rowsBySite.set(r.site, arr); siteOrderSeen.push(r.site); }
      arr.push(r);

      var bc = siteBrowserCounts.get(r.site);
      if (!bc) { bc = new Map(); siteBrowserCounts.set(r.site, bc); }
      bc.set(r.browser, (bc.get(r.browser) || 0) + 1);

      browsersSeen.add(r.browser);
    }
  }

  function siteCount(site) {
    var bc = siteBrowserCounts.get(site);
    if (!bc) return 0;
    if (activeBrowser) return bc.get(activeBrowser) || 0;
    var sum = 0; bc.forEach(function (v) { sum += v; });
    return sum;
  }

  function orderedSites() {
    var sites = activeBrowser
      ? siteOrderSeen.filter(function (s) { return (siteBrowserCounts.get(s) || new Map()).has(activeBrowser); })
      : siteOrderSeen.slice();
    sites.sort(function (a, b) { return siteCount(b) - siteCount(a) || a.localeCompare(b); });
    return sites;
  }

  function currentList() {
    if (activeSite === null) return [];
    var list = rowsBySite.get(activeSite) || [];
    if (activeBrowser) list = list.filter(function (r) { return r.browser === activeBrowser; });
    if (findQuery) {
      list = list.filter(function (r) {
        return r.key.toLowerCase().indexOf(findQuery) >= 0 || r.value.toLowerCase().indexOf(findQuery) >= 0;
      });
    }
    return list;
  }

  function ensureSelection() {
    var order = orderedSites();
    if (!order.length) { activeSite = null; return; }
    if (activeSite === null || order.indexOf(activeSite) < 0) activeSite = order[0];
  }

  /* ---------------- Caricamento (IPC) ---------------- */
  function statusText() {
    if (isLoading) {
      var t = "Caricamento… " + totalRows + " record";
      if (loadErrors.length) t += " · " + loadErrors.length + " errori";
      return t;
    }
    if (totalRows === 0) return "nessun file · trascina qui i CSV";
    var s = fileNames.length + " file · " + totalRows + " record";
    if (loadErrors.length) s += " · " + loadErrors.length + " errori";
    return s;
  }

  function startLoad(paths) {
    if (!paths || !paths.length) return;
    isLoading = true;
    window.api.loadCSVFiles(paths);
    scheduleUIUpdate(false);
  }

  loadBtn.addEventListener("click", function () {
    window.api.pickCSVFiles().then(startLoad);
  });

  window.api.onRowsBatch(function (data) {
    ingestRows(data.rows);
    scheduleUIUpdate(false);
  });

  window.api.onFileDone(function (data) {
    if (fileNames.indexOf(data.fileName) < 0) fileNames.push(data.fileName);
    scheduleUIUpdate(false);
  });

  window.api.onFileError(function (data) {
    loadErrors.push(data.fileName + ": " + data.message);
    console.error("Errore CSV", data.fileName, data.message);
    scheduleUIUpdate(false);
  });

  window.api.onLoadDone(function () {
    isLoading = false;
    scheduleUIUpdate(false);
  });

  resetBtn.addEventListener("click", function () {
    rowsBySite = new Map();
    siteBrowserCounts = new Map();
    siteOrderSeen = [];
    browsersSeen = new Set();
    totalRows = 0;
    fileNames = [];
    loadErrors = [];
    activeSite = null; activeBrowser = null;
    siteSearch.value = ""; findBox.value = ""; findQuery = ""; siteQuery = "";
    selectedRowRef = null;
    inspect.classList.remove("open");
    refreshAll(true);
  });

  ["dragenter", "dragover"].forEach(function (ev) {
    window.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.add("on"); });
  });
  ["dragleave", "drop"].forEach(function (ev) {
    window.addEventListener(ev, function (e) {
      e.preventDefault();
      if (ev === "dragleave" && e.relatedTarget) return;
      drop.classList.remove("on");
    });
  });
  window.addEventListener("drop", function (e) {
    if (!e.dataTransfer || !e.dataTransfer.files) return;
    var files = Array.prototype.filter.call(e.dataTransfer.files, function (f) { return /\.csv$/i.test(f.name); });
    if (!files.length) return;
    var paths = files.map(function (f) { return window.api.getPathForFile(f); });
    startLoad(paths);
  });

  /* ---------------- Aggiornamento UI (coalescing con rAF) ---------------- */
  var uiScheduled = false, pendingReset = false;
  function scheduleUIUpdate(reset) {
    pendingReset = pendingReset || reset;
    if (uiScheduled) return;
    uiScheduled = true;
    requestAnimationFrame(function () {
      uiScheduled = false;
      var r = pendingReset; pendingReset = false;
      refreshAll(r);
    });
  }

  function refreshAll(forceReselect) {
    var has = totalRows > 0;
    siteSearch.disabled = !has;
    findBox.disabled = !has;
    resetBtn.disabled = !has;
    loadMeta.textContent = statusText();

    buildBrowserPicker();
    var prevSite = activeSite;
    if (forceReselect) activeSite = null;
    ensureSelection();
    var siteChanged = activeSite !== prevSite;
    buildRail();
    refilter(siteChanged);
    updateOriginBar();
  }

  function buildBrowserPicker() {
    var distinct = Array.from(browsersSeen).sort();
    if (distinct.length <= 1) {
      browserFilter.style.display = "none";
      activeBrowser = null;
      return;
    }
    browserFilter.style.display = "";
    var keep = activeBrowser;
    browserFilter.innerHTML = "";
    addOpt("", "Tutti i browser");
    distinct.forEach(function (b) { addOpt(b, b); });
    browserFilter.value = distinct.indexOf(keep) >= 0 ? keep : "";
    activeBrowser = browserFilter.value || null;
    function addOpt(v, t) { var o = document.createElement("option"); o.value = v; o.textContent = t; browserFilter.appendChild(o); }
  }

  browserFilter.addEventListener("change", function () {
    activeBrowser = browserFilter.value || null;
    activeSite = null;
    ensureSelection();
    buildRail();
    refilter(true);
    updateOriginBar();
  });

  /* ---------------- Rail (elenco origini) ---------------- */
  siteSearch.addEventListener("input", function () {
    siteQuery = siteSearch.value.trim().toLowerCase();
    buildRail();
  });

  function buildRail() {
    var all = orderedSites();
    originCount.textContent = all.length;
    railList.innerHTML = "";

    if (!all.length) {
      railList.appendChild(hint("Carica i CSV generati dagli script PowerShell per elencare qui i siti."));
      return;
    }

    var shown = siteQuery ? all.filter(function (s) { return s.toLowerCase().indexOf(siteQuery) >= 0; }) : all;

    if (!shown.length) {
      railList.appendChild(hint('Nessun sito contiene "' + siteSearch.value.trim() + '".'));
      return;
    }

    var max = 0;
    shown.forEach(function (s) { var c = siteCount(s); if (c > max) max = c; });

    shown.forEach(function (site) {
      var c = siteCount(site);
      var btn = document.createElement("button");
      btn.className = "origin" + (site === activeSite ? " on" : "");
      btn.style.setProperty("--chip", siteColor(site));

      var top = el("div", "origin-top");
      top.appendChild(el("span", "chip"));
      var host = el("span", "origin-host"); host.textContent = pretty(site); host.title = site;
      top.appendChild(host);
      var n = el("span", "origin-n"); n.textContent = c;
      top.appendChild(n);
      btn.appendChild(top);

      var meter = el("div", "origin-meter");
      var bar = document.createElement("i");
      bar.style.width = Math.max(3, Math.round(c / max * 100)) + "%";
      meter.appendChild(bar);
      btn.appendChild(meter);

      if (!activeBrowser) {
        var src = el("div", "origin-src");
        src.textContent = Array.from((siteBrowserCounts.get(site) || new Map()).keys()).join(" · ");
        btn.appendChild(src);
      }

      btn.addEventListener("click", function () { selectSite(site); });
      railList.appendChild(btn);
    });
  }

  function selectSite(site) {
    activeSite = site;
    selectedRowRef = null;
    inspect.classList.remove("open");
    buildRail();
    refilter(true);
    updateOriginBar();
  }

  function hint(t) { var d = el("div", "rail-empty"); d.textContent = t; return d; }
  function el(tag, cls) { var e = document.createElement(tag); e.className = cls; return e; }
  function pretty(site) { return String(site).replace(/^https?:\/\//, "").replace(/\/$/, ""); }
  function siteColor(site) {
    var h = 0, i;
    for (i = 0; i < site.length; i++) h = (h * 31 + site.charCodeAt(i)) % 360;
    return "hsl(" + h + ",58%,64%)";
  }

  /* ---------------- Origin bar ---------------- */
  findBox.addEventListener("input", function () {
    clearTimeout(findBox._t);
    findBox._t = setTimeout(function () {
      findQuery = findBox.value.trim().toLowerCase();
      refilter(true);
      updateOriginBar();
    }, 180);
  });

  function updateOriginBar() {
    if (activeSite === null) {
      curOrigin.textContent = "—";
      curBadge.innerHTML = "";
      rowCount.textContent = "";
      blank.style.display = "";
      blank.innerHTML = '<strong>Nessun dato caricato</strong>Premi <code>Carica CSV</code> oppure trascina qui i file da <code>C:\\ProgramData\\Test</code>.';
      return;
    }

    curOrigin.textContent = pretty(activeSite);
    curOrigin.title = activeSite;
    curBadge.innerHTML = "";
    (siteBrowserCounts.get(activeSite) || new Map()).forEach(function (_v, b) {
      var lb = b.toLowerCase();
      var cls = lb.indexOf("brave") >= 0 ? "brave" : lb.indexOf("opera") >= 0 ? "opera" : lb.indexOf("discord") >= 0 ? "discord" : "other";
      var s = el("span", "pill " + cls); s.textContent = b;
      curBadge.appendChild(s);
    });

    var total = siteCount(activeSite);
    rowCount.textContent = filteredList.length === total ? total + " chiavi" : filteredList.length + " / " + total;

    if (!filteredList.length) {
      blank.style.display = "";
      blank.innerHTML = "<strong>Nessuna corrispondenza</strong>Nessuna chiave o valore contiene il testo cercato in questa origine.";
    } else {
      blank.style.display = "none";
    }
  }

  /* ---------------- Tabella virtualizzata ---------------- */
  function refilter(resetScroll) {
    filteredList = currentList();
    gridSpacer.style.height = (filteredList.length * ROW_H) + "px";
    if (resetScroll) gridScroll.scrollTop = 0;
    renderVisibleRows();
  }

  function renderVisibleRows() {
    var scrollTop = gridScroll.scrollTop;
    var viewH = gridScroll.clientHeight || 400;
    var overscan = 10;
    var start = Math.max(0, Math.floor(scrollTop / ROW_H) - overscan);
    var end = Math.min(filteredList.length, Math.ceil((scrollTop + viewH) / ROW_H) + overscan);

    var q = findBox.value.trim();
    gridRows.innerHTML = "";
    for (var i = start; i < end; i++) {
      var r = filteredList[i];
      var div = document.createElement("div");
      div.className = "row" + (r === selectedRowRef ? " sel" : "");
      div.style.transform = "translateY(" + (i * ROW_H) + "px)";

      var k = el("div", "rc-key"); k.innerHTML = highlight(r.key, q); k.title = r.key;
      var v = el("div", "rc-val"); v.innerHTML = highlight(r.value, q); v.title = r.value;
      var s = el("div", "rc-size"); s.textContent = fmtSize(byteLen(r.value));

      div.appendChild(k); div.appendChild(v); div.appendChild(s);
      (function (row) { div.addEventListener("click", function () { selectRow(row); }); })(r);
      gridRows.appendChild(div);
    }
  }

  var scrollScheduled = false;
  gridScroll.addEventListener("scroll", function () {
    if (scrollScheduled) return;
    scrollScheduled = true;
    requestAnimationFrame(function () { scrollScheduled = false; renderVisibleRows(); });
  });
  window.addEventListener("resize", renderVisibleRows);

  function selectRow(r) {
    selectedRowRef = r;
    renderVisibleRows();
    openInspector(r);
  }

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function highlight(text, q) {
    if (!q) return esc(text);
    var lower = text.toLowerCase(), needle = q.toLowerCase(), out = "", at = 0, idx;
    while ((idx = lower.indexOf(needle, at)) >= 0) {
      out += esc(text.slice(at, idx)) + "<mark>" + esc(text.slice(idx, idx + needle.length)) + "</mark>";
      at = idx + needle.length;
    }
    return out + esc(text.slice(at));
  }

  function byteLen(s) { try { return new Blob([s]).size; } catch (e) { return s.length; } }
  function fmtSize(b) {
    if (b < 1024) return b + " B";
    if (b < 1048576) return (b / 1024).toFixed(1) + " KB";
    return (b / 1048576).toFixed(1) + " MB";
  }

  /* ---------------- Inspector ---------------- */
  var currentValue = "";

  function openInspector(r) {
    currentValue = r.value;
    iKey.textContent = r.key;
    iKey.title = r.key + "  —  " + r.site;
    iSize.textContent = fmtSize(byteLen(r.value));

    var jwt = asJWT(r.value);
    if (jwt) {
      iType.textContent = "token";
      iBody.innerHTML = '<span class="seg-title">Header</span>' + colorJSON(jwt.header) +
        '<span class="seg-title">Payload</span>' + colorJSON(jwt.payload) +
        '<span class="seg-title">Raw</span>' + esc(r.value);
    } else {
      var parsed = tryJSON(r.value);
      if (parsed.ok) {
        iType.textContent = Array.isArray(parsed.data) ? "array" : (parsed.data === null ? "null" : typeof parsed.data);
        iBody.innerHTML = colorJSON(JSON.stringify(parsed.data, null, 2));
      } else {
        iType.textContent = "testo";
        iBody.textContent = r.value;
      }
    }
    inspect.classList.add("open");
  }

  function tryJSON(s) {
    var t = s.trim();
    if (!t) return { ok: false };
    var c = t[0];
    if ("{[\"-0123456789tfn".indexOf(c) < 0) return { ok: false };
    try { return { ok: true, data: JSON.parse(t) }; } catch (e) { return { ok: false }; }
  }

  function asJWT(s) {
    var t = s.trim(), p = t.split(".");
    if (p.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(p[0]) || !/^[A-Za-z0-9_-]+$/.test(p[1])) return null;
    try {
      var h = JSON.parse(b64url(p[0])), b = JSON.parse(b64url(p[1]));
      if (typeof h !== "object" || h === null) return null;
      return { header: JSON.stringify(h, null, 2), payload: JSON.stringify(b, null, 2) };
    } catch (e) { return null; }
  }

  function b64url(s) {
    s = s.replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    return decodeURIComponent(Array.prototype.map.call(atob(s), function (c) {
      return "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2);
    }).join(""));
  }

  function colorJSON(json) {
    return esc(json).replace(
      /("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false)\b|\bnull\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
      function (m) {
        var cls = "j-num";
        if (/^"/.test(m)) cls = /:$/.test(m) ? "j-key" : "j-str";
        else if (/true|false/.test(m)) cls = "j-bool";
        else if (/null/.test(m)) cls = "j-null";
        return '<span class="' + cls + '">' + m + "</span>";
      }
    );
  }

  closeBtn.addEventListener("click", function () {
    inspect.classList.remove("open");
    selectedRowRef = null;
    renderVisibleRows();
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && inspect.classList.contains("open")) closeBtn.click();
  });

  copyBtn.addEventListener("click", function () {
    var done = function (txt) {
      copyBtn.textContent = txt; copyBtn.classList.add("flash");
      setTimeout(function () { copyBtn.textContent = "Copia"; copyBtn.classList.remove("flash"); }, 1200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(currentValue).then(function () { done("Copiato"); })
        .catch(function () { done("Copia dal pannello"); });
    } else { done("Copia dal pannello"); }
  });

  refreshAll(true);
})();
