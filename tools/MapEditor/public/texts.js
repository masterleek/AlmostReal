import { getTexts, saveTexts } from "./api.js";
import { wrapSelectionBold, wrapSelectionColor, clearSelectionFormatting } from "./bbcode.js";
import { openTextPreview } from "./text-preview.js";

const overlay = document.getElementById("texts-modal-overlay");
const closeBtn = document.getElementById("texts-modal-close");
const listEl = document.getElementById("texts-list");
const addBtn = document.getElementById("texts-add-btn");
const emptyHint = document.getElementById("texts-empty-hint");
const tabsEl = document.getElementById("texts-category-tabs");

let catalog = { languages: [], default_language: "en", texts: [] };
let onChange = null;
let activeCategory = "ui";
// Ligne actuellement ouverte dans la preview (cf openPreviewFor) : ses
// textarea, en étant modifiées, redéclenchent un rafraîchissement live —
// null quand aucune preview n'est ouverte, pour ne pas payer ce coût sinon.
let previewingEntry = null;
let previewDebounceTimer = null;

async function persist() {
  await saveTexts(catalog);
  onChange?.();
}

// Autres entrées qui pointent le même nœud (cf plan : plusieurs textes
// peuvent partager un même Label/RichTextLabel en jeu, seul le dernier style
// appliqué au runtime est visuellement effectif) — affiché comme
// avertissement discret plutôt que bloqué, le cas est rare (2 entrées pour
// l'instant) et le contournement (garder le même style) est simple.
function sharedNodeWarning(entry) {
  if (!entry.usage?.node_path) return null;
  const siblings = catalog.texts.filter(
    (t) => t !== entry && t.usage?.node_path === entry.usage.node_path
  );
  if (siblings.length === 0) return null;
  return `Partage son emplacement en jeu avec : ${siblings.map((t) => t.id).join(", ")} — garder le même style est recommandé.`;
}

function buildLangColumn(entry, lang) {
  const col = document.createElement("div");
  col.className = "text-lang-col";

  const label = document.createElement("div");
  label.className = "text-lang-label";
  label.textContent = lang.label;
  col.appendChild(label);

  const toolbar = document.createElement("div");
  toolbar.className = "bbcode-toolbar";

  const boldBtn = document.createElement("button");
  boldBtn.type = "button";
  boldBtn.className = "bbcode-btn";
  boldBtn.textContent = "G";
  boldBtn.title = "Mettre la sélection en gras ([b])";

  const colorInput = document.createElement("input");
  colorInput.type = "color";
  colorInput.className = "bbcode-color";
  colorInput.title = "Colorer la sélection";
  colorInput.value = "#ffffff";

  const clearBtn = document.createElement("button");
  clearBtn.type = "button";
  clearBtn.className = "bbcode-btn";
  clearBtn.textContent = "⌫";
  clearBtn.title = "Effacer le style de la sélection";

  toolbar.append(boldBtn, colorInput, clearBtn);
  col.appendChild(toolbar);

  const textarea = document.createElement("textarea");
  textarea.className = "text-lang-textarea";
  textarea.value = entry.translations?.[lang.code] || "";
  textarea.placeholder = `(${lang.label})`;

  const applyEdit = (fn) => {
    textarea.focus();
    const result = fn(textarea);
    textarea.value = result.value;
    textarea.setSelectionRange(result.selectionStart, result.selectionEnd);
    onTextareaChanged();
  };

  boldBtn.onclick = () => applyEdit(wrapSelectionBold);
  colorInput.oninput = () => applyEdit((ta) => wrapSelectionColor(ta, colorInput.value));
  clearBtn.onclick = () => applyEdit(clearSelectionFormatting);

  async function onTextareaChanged() {
    if (!entry.translations) entry.translations = {};
    entry.translations[lang.code] = textarea.value;
    schedulePreviewRefresh(entry, textarea.value);
    await persist();
  }
  textarea.addEventListener("change", onTextareaChanged);

  col.appendChild(textarea);
  return col;
}

// Un seul texte a besoin d'être rafraîchi en live (celui dont la preview est
// ouverte) : évite de brancher un debounce sur chaque textarea de chaque
// ligne, la plupart ne sont jamais previewées en même temps.
function schedulePreviewRefresh(entry, text) {
  if (previewingEntry !== entry) return;
  clearTimeout(previewDebounceTimer);
  previewDebounceTimer = setTimeout(() => {
    openTextPreview(entry, text);
  }, 150);
}

function renderRow(entry) {
  const row = document.createElement("div");
  row.className = "text-row";

  const head = document.createElement("div");
  head.className = "text-row-head";

  const id = document.createElement("span");
  id.className = "text-id";
  id.textContent = entry.id;
  head.appendChild(id);

  const fontSizeLabel = document.createElement("label");
  fontSizeLabel.className = "text-fontsize-label";
  fontSizeLabel.textContent = "Taille";
  const fontSizeInput = document.createElement("input");
  fontSizeInput.type = "number";
  fontSizeInput.min = "1";
  fontSizeInput.step = "1";
  fontSizeInput.value = entry.style?.font_size ?? 16;
  fontSizeInput.onchange = async () => {
    if (!entry.style) entry.style = {};
    entry.style.font_size = parseInt(fontSizeInput.value, 10) || 16;
    await persist();
  };
  fontSizeLabel.appendChild(fontSizeInput);
  head.appendChild(fontSizeLabel);

  if (entry.category === "ui" && entry.usage?.preview_image) {
    const previewBtn = document.createElement("button");
    previewBtn.type = "button";
    previewBtn.className = "text-preview-btn";
    previewBtn.textContent = "Aperçu";
    previewBtn.onclick = () => {
      previewingEntry = entry;
      const text = entry.translations?.[catalog.default_language] || "";
      openTextPreview(entry, text);
    };
    head.appendChild(previewBtn);
  }

  const del = document.createElement("button");
  del.className = "modal-map-delete";
  del.textContent = "🗑";
  del.title = "Supprimer ce texte";
  del.onclick = async () => {
    if (!confirm(`Supprimer le texte "${entry.id}" ?`)) return;
    catalog.texts = catalog.texts.filter((t) => t !== entry);
    renderList();
    await persist();
  };
  head.appendChild(del);

  row.appendChild(head);

  if (entry.category === "ui" && entry.usage) {
    const usage = document.createElement("span");
    usage.className = "system-used-in";
    const scriptName = entry.usage.script?.split("/").pop() || entry.usage.script;
    usage.textContent = `Utilisé dans : ${scriptName} → ${entry.usage.node_path}`;
    row.appendChild(usage);
  }

  const warning = sharedNodeWarning(entry);
  if (warning) {
    const warn = document.createElement("span");
    warn.className = "text-shared-warning";
    warn.textContent = warning;
    row.appendChild(warn);
  }

  const languages = document.createElement("div");
  languages.className = "text-languages";
  for (const lang of catalog.languages) {
    languages.appendChild(buildLangColumn(entry, lang));
  }
  row.appendChild(languages);

  return row;
}

function renderList() {
  listEl.innerHTML = "";
  const entries = catalog.texts.filter((t) => t.category === activeCategory);

  if (entries.length === 0) {
    emptyHint.textContent =
      activeCategory === "dialogue"
        ? "Aucun texte de dialogue pour l'instant — le jeu n'a pas encore de système de dialogue, cette catégorie est prête à en recevoir."
        : "Aucun texte UI pour l'instant.";
    emptyHint.classList.remove("hidden");
  } else {
    emptyHint.classList.add("hidden");
  }

  for (const entry of entries) {
    listEl.appendChild(renderRow(entry));
  }

  // Un texte "ui" a besoin d'un nœud/script réel en jeu pour exister : cet
  // outil ne peut pas câbler ça tout seul, donc pas de création à la volée
  // pour cette catégorie (contrairement à "dialogue", qui n'a justement rien
  // à câbler puisqu'aucun système de dialogue n'existe encore).
  addBtn.disabled = activeCategory === "ui";
  addBtn.title = addBtn.disabled
    ? "Un texte UI doit d'abord être câblé dans le code du jeu (cf Localization.get_text) — pas de création depuis cette page."
    : "";
}

for (const tab of tabsEl.querySelectorAll(".texts-tab")) {
  tab.onclick = () => {
    tabsEl.querySelectorAll(".texts-tab").forEach((t) => t.classList.remove("selected"));
    tab.classList.add("selected");
    activeCategory = tab.dataset.category;
    renderList();
  };
}

addBtn.onclick = async () => {
  const id = prompt("Identifiant du texte (ex. npc_intro.line_1) :");
  if (!id || catalog.texts.some((t) => t.id === id)) return;
  const entry = {
    id,
    category: "dialogue",
    translations: Object.fromEntries(catalog.languages.map((l) => [l.code, ""])),
    style: { font_size: 16 },
  };
  catalog.texts.push(entry);
  renderList();
  await persist();
};

closeBtn.onclick = closeManager;
overlay.onclick = (evt) => {
  if (evt.target === overlay) closeManager();
};

function closeManager() {
  overlay.classList.add("hidden");
  previewingEntry = null;
}

export async function openTextsManager(opts) {
  onChange = opts?.onChange || null;
  catalog = await getTexts();
  activeCategory = "ui";
  tabsEl.querySelectorAll(".texts-tab").forEach((t) => t.classList.toggle("selected", t.dataset.category === "ui"));
  renderList();
  overlay.classList.remove("hidden");
}
