/*
 * railmap-popup.js — railprint's C5 bilingual station hover popup.
 *
 * Builds the popup model (every line through the hovered physical station,
 * deduped across the station group) and renders it to HTML rows with the
 * line logo / color swatch + a short company label.
 *
 * Publishes the RailMapPopup global (consumed by railmap-interactions.js).
 */
(function (global) {
  "use strict";

  const DEFAULT_LINE_COLOR = global.RailNetwork.DEFAULT_LINE_COLOR;

  // ───────────────────────── C5 hover popup (popup.ts + company.ts) ─────────────────────
  const companyLabel = global.RailOperatorBranding.companyLabel;
  const companyFor = global.RailOperatorBranding.companyFor;
  function escHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    })[c]);
  }
  function bilingualLabel(name, nameRoma) {
    return nameRoma ? name + " (" + nameRoma + ")" : name;
  }
  function assetUrl(p) {
    return encodeURI(String(p).replace(/^\//, "./"));
  }
  function lineBadgeHtml(row) {
    if (row.logo)
      return (
        '<img class="rp-line-logo' +
        (row.logoNeedsDarkMatte ? " rp-line-logo--dark-matte" : "") +
        '" src="' +
        escHtml(assetUrl(row.logo)) +
        '" alt="" loading="lazy" />'
      );
    return '<span class="rp-line-swatch" style="background:' + escHtml(row.color) + '"></span>';
  }
  function buildPopupModel(network, stationId, lineIdFallback, opts) {
    const st = network.stationById.get(stationId);
    const groupKey = st && st.stationGroupId ? st.stationGroupId : "solo:" + stationId;
    const members = network.groupMembers.get(groupKey) || [];
    const rows = [];
    // A canonical railway can be stored as several drawable strokes (main,
    // branch, rejoin or paired alignment). At a shared station those records
    // are still one passenger-facing line, so key the popup by its displayed
    // operator + name instead of by the internal stroke id. Railway identity
    // is deliberately not used here: it may join differently named through
    // railways for lane continuity (東北線 → 東海道線 at 東京), and both names
    // must remain visible to passengers.
    const seen = new Set();
    const add = (lineId) => {
      const line = network.lineById.get(lineId);
      if (!line) return;
      const displayKey = `${line.operator || ""}\u0000${line.name || ""}`;
      if (seen.has(displayKey)) return;
      seen.add(displayKey);
      const logo = global.RailOperatorBranding.logoForLine(line);
      rows.push({
        lineId: line.lineId,
        company: companyFor(line.operator, line.name),
        label: bilingualLabel(line.name, line.nameRoma),
        color: line.color || DEFAULT_LINE_COLOR,
        // Prefer a package-provided/per-line badge, then fall back to the
        // operator mark when the line has no dedicated identity.
        logo,
        logoNeedsDarkMatte:
          typeof global.RailOperatorBranding.logoNeedsDarkMatte === "function" &&
          global.RailOperatorBranding.logoNeedsDarkMatte(logo),
      });
    };
    for (const m of members) add(m.lineId);
    if (rows.length === 0 && lineIdFallback) add(lineIdFallback);
    rows.sort((a, b) => a.label.localeCompare(b.label));
    const rawName = st ? st.name : stationId;
    const name =
      global.I18N && typeof global.I18N.stationName === "function"
        ? global.I18N.stationName(rawName, st ? st.stationId : stationId)
        : rawName;
    const model = {
      name,
      nameRoma: st && st.nameRoma ? st.nameRoma : "",
      // Header readings from the curated station-readings reference (kana /
      // romaji / Chinese per the app's 顯示 toggles) when the app's i18n layer
      // is present, one per line under the name; null keeps the standalone
      // railmap behavior (single nameRoma subline).
      readings:
        global.I18N && typeof global.I18N.nameReadingsList === "function"
          ? global.I18N.nameReadingsList(rawName, st ? st.stationId : stationId)
          : null,
      lines: rows,
    };
    if (opts && opts.detailed) {
      const line = st && network.lineById.get(st.lineId);
      model.details = {
        rawName, alternateName: st && st.nameRoma, code: st ? st.stationGroupId : stationId,
        country: line && line.country,
        lon: st && st.lon, lat: st && st.lat,
        validFrom: st && st.validFrom, validTo: st && st.validTo,
        names: global.I18N && typeof global.I18N.stationNames === "function"
          ? global.I18N.stationNames(rawName, st ? st.stationId : stationId, st && st.stationGroupId) : [],
      };
      model.lines = rows.map((row) => ({ ...row,
        operatorName: network.lineById.get(row.lineId).operator || "" }));
    }
    return model;
  }
  function stationPopupHtml(model, opts) {
    // readings === null -> standalone railmap (no app i18n): keep nameRoma.
    // readings === []   -> app context with every reading toggle off: no sublines.
    // Each reading renders as its OWN line under the name (.rp-popup-head is a
    // column flexbox), so the popup grows with however many are enabled.
    const detailed = !!(opts && opts.detailed && model.details);
    const subs =
      detailed ? [] : model.readings != null
        ? model.readings
        : model.nameRoma
          ? [model.nameRoma]
          : [];
    const header =
      '<span class="rp-popup-ja">' +
      escHtml(model.name) +
      "</span>" +
      subs
        .map((s) => '<span class="rp-popup-roma">' + escHtml(s) + "</span>")
        .join("");
    const rows = model.lines
      .map((r) => {
        const co = r.company
          ? '<span class="rp-line-co">' + escHtml(r.company) + "</span>"
          : "";
        return (
          '<li class="rp-line-row">' +
          co +
          lineBadgeHtml(r) +
          '<span class="rp-line-name">' +
          escHtml(r.label) +
          "</span>" + (detailed && r.operatorName && r.operatorName !== r.company
            ? '<span class="rp-line-operator">' + escHtml(r.operatorName) + "</span>" : "") + "</li>"
        );
      })
      .join("");
    const fallbackLabels = {
      "popup.originalName": "Original name", "popup.alternateName": "Alternative name",
      "popup.names": "Station names", "popup.stationInfo": "Station information",
      "popup.stationCode": "Station code", "popup.region": "Region",
      "popup.coordinates": "Coordinates", "popup.validFrom": "Valid from",
      "popup.validTo": "Valid until", "popup.line": "Lines",
    };
    const t = (key) => global.I18N && typeof global.I18N.t === "function"
      ? global.I18N.t(key) : fallbackLabels[key] || key.replace(/^country\./, "").toUpperCase();
    const field = (label, value) => value == null || value === "" ? ""
      : "<dt>" + escHtml(label) + "</dt><dd>" + escHtml(value) + "</dd>";
    let details = "";
    if (detailed) {
      const d = model.details;
      const labels = { zh_Hant: "繁體中文", zh_Hans: "简体中文", ja: "日本語",
        en: "English", kana: "かな", katakana: "カタカナ", romaji: "Rōmaji" };
      const alternate = d.alternateName && d.alternateName !== d.rawName &&
        !d.names.some((n) => n.text === d.alternateName) ? d.alternateName : "";
      const names = field(t("popup.originalName"), d.rawName) +
        d.names.map((n) => field(labels[n.kind] || n.kind, n.text)).join("") +
        field(t("popup.alternateName"), alternate);
      const coordinates = Number.isFinite(d.lat) && Number.isFinite(d.lon)
        ? d.lat.toFixed(6) + ", " + d.lon.toFixed(6) : "";
      const info = field(t("popup.stationCode"), d.code) +
        field(t("popup.region"), d.country ? t("country." + String(d.country).toLowerCase()) : "") +
        field(t("popup.coordinates"), coordinates) +
        field(t("popup.validFrom"), d.validFrom) + field(t("popup.validTo"), d.validTo);
      details = '<section class="rp-station-details"><h3>' + escHtml(t("popup.names")) +
        "</h3><dl>" + names + "</dl><h3>" + escHtml(t("popup.stationInfo")) +
        "</h3><dl>" + info + "</dl></section>";
    }
    const subhead = opts && opts.subhead ? opts.subhead : "";
    return (
      '<div class="rp-popup' + (detailed ? ' rp-popup--details' : '') + '"><div class="rp-popup-head">' +
      header +
      "</div>" +
      subhead +
      details +
      (rows ? (detailed ? '<h3 class="rp-station-lines-heading">' + escHtml(t("popup.line")) + "</h3>" : "") +
        '<ul class="rp-line-list">' + rows + "</ul>" : "") +
      "</div>"
    );
  }

  // companyLabel is shared with the 統計 per-line breakdown, which groups its
  // rows by operating company and needs the same short label (JR東日本 etc.).
  global.RailMapPopup = { buildPopupModel, stationPopupHtml, companyLabel };
})(window);
