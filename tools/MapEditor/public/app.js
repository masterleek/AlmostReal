import { loadMap, saveMap, getProps, playGame } from "./api.js";
import { renderMapBrowser } from "./maps.js";
import { buildPalette, loadImage } from "./palette.js";
import { openTileManager } from "./tiles.js";
import { openPropManager } from "./props.js";
import { openSystemsManager } from "./systems.js";
import { MapCanvas, currentFrameIndex } from "./canvas.js";
import { pixelToCell, cellToPixel, TILE_W, TILE_H } from "./hexgrid.js";

const EYE_OPEN =
  '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z"/><circle cx="12" cy="12" r="3"/></svg>';
const EYE_CLOSED =
  '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/><path d="M6.6 6.6C3.4 8.5 1 12 1 12s4 8 11 8a9.26 9.26 0 0 0 5.4-1.6"/><path d="M14.12 14.12a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';

const statusEl = document.getElementById("status");

const menuMapsBtn = document.getElementById("menu-maps");
const menuSystemsBtn = document.getElementById("menu-systems");
const modalOverlay = document.getElementById("modal-overlay");
const modalClose = document.getElementById("modal-close");
const modalMapList = document.getElementById("modal-map-list");
const modalNewMapBtn = document.getElementById("modal-new-map-btn");

const tabStripEl = document.getElementById("tab-strip");
const nameInput = document.getElementById("map-name");
const widthInput = document.getElementById("map-width");
const heightInput = document.getElementById("map-height");

const paletteEl = document.getElementById("palette");
const propsPaletteEl = document.getElementById("props-palette");
const canvasWrapEl = document.getElementById("canvas-wrap");
const canvasEl = document.getElementById("map-canvas");
const propsCanvasEl = document.getElementById("props-canvas");
const previewFrameEl = document.getElementById("preview-frame");
const miniCanvasEl = document.getElementById("mini-canvas");
const miniWrapEl = document.getElementById("mini-preview-wrap");
const miniLabelEl = document.getElementById("mini-preview-label");
const miniToggleBtn = document.getElementById("mini-toggle-btn");

const zoomInBtn = document.getElementById("zoom-in");
const zoomOutBtn = document.getElementById("zoom-out");
const zoomLevelEl = document.getElementById("zoom-level");

const toolSaveBtn = document.getElementById("tool-save");
const toolUndoBtn = document.getElementById("tool-undo");
const toolEraseBtn = document.getElementById("tool-erase");
const toolEditBtn = document.getElementById("tool-edit");
const toolPropBtn = document.getElementById("tool-prop");
const toolRevealBtn = document.getElementById("tool-reveal");
const toolRevealPreviewBtn = document.getElementById("tool-reveal-preview");
const toolPlayBtn = document.getElementById("tool-play");
const manageTilesBtn = document.getElementById("manage-tiles-btn");
const managePropsBtn = document.getElementById("manage-props-btn");
const fixOverflowPropsBtn = document.getElementById("fix-overflow-props-btn");

const propInspectorEl = document.getElementById("prop-inspector");
const propInspectorNameEl = document.getElementById("prop-inspector-name");
const propZIndexInput = document.getElementById("prop-zindex");
const propDeleteBtn = document.getElementById("prop-delete-btn");

const openMaps = new Map(); // id -> map data (en mémoire, pour garder les onglets sans perdre les modifs)
const tabOrder = [];
let activeId = null;
let currentTool = "paint"; // 'paint' | 'erase' | 'prop' | 'reveal'
let currentBrush = null;
let currentPropBrush = null;
let currentRevealBrush = null; // tuile choisie dans la palette pour le mode "reveal"
let selectedProp = null;
let draggingProp = false;
let dragOffset = { x: 0, y: 0 };
let mapCanvas = null;
let paletteTiles = [];
let propsPaletteList = [];
let propImage = null;
let autoFitZoom = true; // tant que l'utilisateur n'a pas cliqué +/- manuellement
let hoverCell = null;
let hoverPixel = null;
let animatedTileSwatches = [];
let animatedPropSwatches = [];

// Anime les vignettes de palette (tuiles/props) qui ont plusieurs frames —
// indépendant de la boucle d'animation de la preview principale.
setInterval(() => {
  for (const s of animatedTileSwatches) {
    drawTileSwatch(s.ctx, s.image, s.frames[currentFrameIndex(s.frames, s.fps)]);
  }
  for (const s of animatedPropSwatches) {
    drawPropSwatch(s.ctx, s.image, s.frames[currentFrameIndex(s.frames, s.fps)]);
  }
}, 100);

// ---------- Annuler (undo) ----------
// Une pile d'historique par map (tuiles + props), pour ne pas mélanger
// l'undo de deux onglets différents.
const undoStacks = new Map(); // id -> snapshots[]
const MAX_UNDO = 50;

function pushUndo() {
  const map = activeMap();
  if (!map) return;
  if (!undoStacks.has(map.id)) undoStacks.set(map.id, []);
  const stack = undoStacks.get(map.id);
  stack.push({
    cells: JSON.parse(JSON.stringify(map.cells)),
    props: JSON.parse(JSON.stringify(map.props)),
  });
  if (stack.length > MAX_UNDO) stack.shift();
  updateUndoButton();
}

function undo() {
  const map = activeMap();
  if (!map) return;
  const stack = undoStacks.get(map.id);
  if (!stack || stack.length === 0) return;
  const snapshot = stack.pop();
  map.cells = snapshot.cells;
  map.props = snapshot.props;
  selectProp(null);
  mapCanvas.setMap(map);
  updateUndoButton();
}

function updateUndoButton() {
  const map = activeMap();
  const stack = map ? undoStacks.get(map.id) : null;
  toolUndoBtn.disabled = !stack || stack.length === 0;
}

function setStatus(text) {
  statusEl.textContent = text;
  if (text) setTimeout(() => (statusEl.textContent = ""), 2000);
}

function activeMap() {
  return activeId ? openMaps.get(activeId) : null;
}

function normalizeMap(map) {
  map.props = map.props || [];
  return map;
}

// ---------- Modal "Maps" ----------

function openModal() {
  modalOverlay.classList.remove("hidden");
  refreshModalList();
}

function closeModal() {
  modalOverlay.classList.add("hidden");
}

const modalHandlers = {
  onOpen: async (id) => {
    await openTab(id);
    closeModal();
  },
  onDelete: (id) => {
    if (openMaps.has(id)) closeTab(id);
    refreshModalList();
  },
  onRename: (id, newName) => {
    const map = openMaps.get(id);
    if (map) {
      map.name = newName;
      if (id === activeId) nameInput.value = newName;
      renderTabStrip();
    }
  },
};

async function refreshModalList() {
  return renderMapBrowser(modalMapList, modalHandlers);
}

menuMapsBtn.onclick = openModal;
menuSystemsBtn.onclick = openSystemsManager;
modalClose.onclick = closeModal;
modalOverlay.onclick = (evt) => {
  if (evt.target === modalOverlay) closeModal();
};

modalNewMapBtn.onclick = async () => {
  const id = prompt("Identifiant de la map (lettres/chiffres/tirets) :");
  if (!id || !/^[a-zA-Z0-9_-]+$/.test(id)) return;
  const map = { id, name: id, width: 480, height: 270, cells: {}, props: [] };
  await saveMap(id, map);
  openMaps.set(id, map);
  undoStacks.set(id, []);
  tabOrder.push(id);
  setActiveTab(id);
  closeModal();
};

// ---------- Onglets ----------

async function openTab(id) {
  if (!openMaps.has(id)) {
    const map = normalizeMap(await loadMap(id));
    openMaps.set(id, map);
    undoStacks.set(id, []);
    tabOrder.push(id);
  }
  setActiveTab(id);
}

function setActiveTab(id) {
  activeId = id;
  const map = openMaps.get(id);
  nameInput.value = map.name || "";
  widthInput.value = map.width;
  heightInput.value = map.height;
  selectProp(null);
  resyncPropsRevealCell(map);
  mapCanvas.setMap(map);
  renderTabStrip();
  updateUndoButton();
}

function closeTab(id) {
  const idx = tabOrder.indexOf(id);
  if (idx !== -1) tabOrder.splice(idx, 1);
  openMaps.delete(id);
  undoStacks.delete(id);

  if (activeId === id) {
    const next = tabOrder[idx] || tabOrder[idx - 1] || tabOrder[0] || null;
    if (next) {
      setActiveTab(next);
    } else {
      activeId = null;
      nameInput.value = "";
      widthInput.value = "";
      heightInput.value = "";
      selectProp(null);
      mapCanvas.clear();
      renderTabStrip();
      updateUndoButton();
    }
  } else {
    renderTabStrip();
  }
}

function renderTabStrip() {
  tabStripEl.innerHTML = "";
  if (tabOrder.length === 0) {
    const hint = document.createElement("div");
    hint.className = "empty-hint";
    hint.textContent = "Aucune map ouverte — ouvre-en une depuis le menu Maps.";
    tabStripEl.appendChild(hint);
    return;
  }
  for (const id of tabOrder) {
    const map = openMaps.get(id);
    const tab = document.createElement("div");
    tab.className = "tab" + (id === activeId ? " active" : "");

    const label = document.createElement("span");
    label.className = "tab-name";
    label.textContent = map.name || id;
    label.onclick = () => setActiveTab(id);

    const close = document.createElement("button");
    close.className = "tab-close";
    close.textContent = "×";
    close.title = "Fermer l'onglet";
    close.onclick = (evt) => {
      evt.stopPropagation();
      closeTab(id);
    };

    tab.append(label, close);
    tab.onclick = () => setActiveTab(id);
    tabStripEl.appendChild(tab);
  }
}

// ---------- Outils (save / gomme / édition / props) ----------

function setTool(tool) {
  currentTool = tool;
  toolEraseBtn.classList.toggle("selected", tool === "erase");
  toolEditBtn.classList.toggle("selected", tool === "paint");
  toolPropBtn.classList.toggle("selected", tool === "prop");
  toolRevealBtn.classList.toggle("selected", tool === "reveal");

  if (tool !== "paint") {
    currentBrush = null;
    document
      .querySelectorAll(".palette-tile.selected")
      .forEach((el) => el.classList.remove("selected"));
  }
  if (tool !== "prop") {
    currentPropBrush = null;
    document
      .querySelectorAll(".prop-tile.selected")
      .forEach((el) => el.classList.remove("selected"));
    selectProp(null);
  }
  if (tool === "reveal" && currentRevealBrush) {
    // Réaffiche la sélection du pinceau "reveal" en revenant sur cet outil.
    const el = paletteEl.querySelector(
      `[data-atlas="${currentRevealBrush.atlas[0]},${currentRevealBrush.atlas[1]}"]`
    );
    el?.classList.add("selected");
  }
  if (tool === "prop" && !revealPreview) {
    // Poser des props sur le rendu final (tuiles révélées) plutôt que sur
    // les cases Empty brutes, sans étape manuelle en plus.
    setRevealPreview(true);
  }
  if (tool === "reveal" && revealPreview) {
    // L'outil "reveal" a besoin de voir les cases Empty telles quelles
    // (badge de révélation compris) pour cliquer dessus — l'aperçu révélé
    // les masquerait.
    setRevealPreview(false);
  }
  updateRevealPaletteState();
  updateToolPanels();
  updateGhost();
}

// Chaque outil n'a besoin que d'un des deux panneaux (tuiles/props), voire
// d'aucun (gomme) : l'autre est assombri et non cliquable pour éviter de
// laisser croire qu'un pinceau sélectionné là aurait un effet.
function updateToolPanels() {
  const paletteDisabled = currentTool === "erase" || currentTool === "prop";
  const propsDisabled = currentTool === "erase" || currentTool === "paint" || currentTool === "reveal";
  paletteEl.classList.toggle("panel-disabled", paletteDisabled);
  propsPaletteEl.classList.toggle("panel-disabled", propsDisabled);
}

// Une case Empty ne peut pas révéler une autre case Empty (ça n'aurait pas de
// sens) : la tuile "Empty" de la palette est assombrie/non cliquable tant que
// l'outil "reveal" est actif.
function updateRevealPaletteState() {
  const emptyTile = paletteTiles.find((t) => t.terrain_type === "empty1");
  if (!emptyTile) return;
  const el = paletteEl.querySelector(
    `[data-atlas="${emptyTile.atlas[0]},${emptyTile.atlas[1]}"]`
  );
  el?.classList.toggle("disabled", currentTool === "reveal");
}

// Aperçu en direct sous le curseur : la tuile sélectionnée à 50% d'opacité en
// mode édition, la tuile OU le prop existant estompé à 50% en mode gomme
// (le prop a priorité s'il y en a un sous le curseur, puisqu'il est
// visuellement au-dessus), ou le prop sélectionné en mode props.
function updateGhost() {
  if (!mapCanvas || !activeMap()) {
    mapCanvas?.setGhost(null);
    mapCanvas?.setDimCell(null);
    mapCanvas?.setDimProp(null);
    mapCanvas?.setPropGhost(null);
    mapCanvas?.setHitzoneHover(null);
    return;
  }

  // Contour de la zone de pose sûre d'une case, affiché au survol pendant le
  // placement de props : un prop entièrement dedans ne débordera jamais sur
  // une case voisine (cf fixOverflowingProps, même repère TILE_W/TILE_H).
  // hoverCell n'est pas tenu à jour en mode "prop" (cf mousemove : chemin
  // séparé via propMouseMove/hoverPixel), donc on recalcule depuis hoverPixel.
  mapCanvas.setHitzoneHover(
    currentTool === "prop" && hoverPixel ? pixelToCell(hoverPixel.x, hoverPixel.y) : null
  );

  if (currentTool === "erase" && hoverPixel) {
    const hitProp = mapCanvas.propAt(hoverPixel.x, hoverPixel.y);
    mapCanvas.setDimProp(hitProp);
    mapCanvas.setDimCell(
      !hitProp && hoverCell ? { col: hoverCell.col, row: hoverCell.row } : null
    );
  } else {
    mapCanvas.setDimProp(null);
    mapCanvas.setDimCell(null);
  }

  // En mode "reveal", survoler une case Empty montre la tuile choisie dans la
  // palette (currentRevealBrush, pas currentBrush — cf setBrush()) à 50%
  // par-dessus sa tuile révélée actuelle, pour prévisualiser la cible avant
  // de cliquer pour l'assigner.
  const hoveredCell = hoverCell && activeMap().cells[`${hoverCell.col},${hoverCell.row}`];
  const hoveredIsEmpty =
    hoveredCell && mapCanvas.tileDefs.get(hoveredCell.atlas.join(","))?.terrain_type === "empty1";
  const ghostBrush =
    currentTool === "paint"
      ? currentBrush
      : currentTool === "reveal" && hoveredIsEmpty
        ? currentRevealBrush
        : null;

  mapCanvas.setGhost(
    ghostBrush && hoverCell
      ? {
          source_id: ghostBrush.source_id,
          atlas: ghostBrush.atlas,
          col: hoverCell.col,
          row: hoverCell.row,
        }
      : null
  );

  mapCanvas.setPropGhost(
    currentTool === "prop" && currentPropBrush && hoverPixel && !draggingProp
      ? { rect: currentPropBrush.rect, x: hoverPixel.x, y: hoverPixel.y }
      : null
  );
}

toolEraseBtn.onclick = () => setTool("erase");
toolEditBtn.onclick = () => setTool("paint");
toolPropBtn.onclick = () => setTool("prop");
toolRevealBtn.onclick = () => setTool("reveal");
toolUndoBtn.onclick = () => undo();

// Aperçu révélé : bascule d'affichage indépendante de l'outil actif (pas un
// "outil" au sens édition, donc pas géré par setTool()) — mais activée
// automatiquement en passant sur l'outil "prop" (cf setTool()), pour placer
// les props sur le rendu final plutôt que sur les cases Empty brutes.
let revealPreview = false;
function setRevealPreview(value) {
  revealPreview = value;
  toolRevealPreviewBtn.classList.toggle("selected", revealPreview);
  mapCanvas.setRevealPreview(revealPreview);
}
toolRevealPreviewBtn.onclick = () => setRevealPreview(!revealPreview);

async function saveActiveMap() {
  const map = activeMap();
  if (!map) return null;
  map.name = nameInput.value;
  map.width = parseInt(widthInput.value, 10) || map.width;
  map.height = parseInt(heightInput.value, 10) || map.height;
  resyncPropsRevealCell(map);
  await saveMap(map.id, map);
  mapCanvas.setMap(map);
  renderTabStrip();
  return map;
}

toolSaveBtn.onclick = async () => {
  const map = await saveActiveMap();
  if (map) setStatus("Enregistré ✓");
};

toolPlayBtn.onclick = async () => {
  const map = await saveActiveMap();
  setStatus("Lancement du jeu…");
  const result = await playGame(map?.id);
  setStatus(result.ok ? "Jeu lancé ✓" : `Erreur : ${result.error}`);
};

// ---------- Champs Nom / Largeur / Hauteur (px) ----------

nameInput.onchange = () => {
  const map = activeMap();
  if (!map) return;
  map.name = nameInput.value;
  renderTabStrip();
};

widthInput.onchange = () => {
  const map = activeMap();
  if (!map) return;
  map.width = parseInt(widthInput.value, 10) || map.width;
  mapCanvas.setMap(map);
};

heightInput.onchange = () => {
  const map = activeMap();
  if (!map) return;
  map.height = parseInt(heightInput.value, 10) || map.height;
  mapCanvas.setMap(map);
};

// ---------- Palette (tuiles) ----------

// En mode "reveal", cliquer une tuile de la palette choisit la cible de
// révélation au lieu de changer le pinceau de peinture (et sans quitter
// l'outil "reveal") — clic sur une case Empty ensuite pour l'assigner.
function setBrush(tile) {
  if (currentTool === "reveal") {
    if (tile.terrain_type === "empty1") return; // ne peut pas révéler vers Empty
    currentRevealBrush = tile;
  } else {
    currentBrush = tile;
    setTool("paint");
  }
  document
    .querySelectorAll(".palette-tile")
    .forEach((el) => el.classList.remove("selected"));
  const el = paletteEl.querySelector(
    `[data-atlas="${tile.atlas[0]},${tile.atlas[1]}"]`
  );
  el?.classList.add("selected");
}

async function refreshPalette() {
  const { image, tiles } = await buildPalette();
  paletteTiles = tiles;
  renderPalette(tiles, image);
  mapCanvas?.setTileDefs(tiles);

  const stillExists =
    currentBrush &&
    tiles.find(
      (t) => t.atlas[0] === currentBrush.atlas[0] && t.atlas[1] === currentBrush.atlas[1]
    );
  if (stillExists) {
    setBrush(stillExists);
  } else if (tiles.length > 0) {
    setBrush(tiles[0]);
  } else {
    currentBrush = null;
    updateGhost();
  }
}

manageTilesBtn.onclick = () => openTileManager({ onChange: refreshPalette });

fixOverflowPropsBtn.onclick = () => {
  const map = activeMap();
  if (!map) return;
  pushUndo();
  const fixedCount = fixOverflowingProps(map);
  if (fixedCount === 0) {
    setStatus("Aucun prop ne déborde de sa case");
  } else {
    setStatus(`${fixedCount} prop(s) recentré(s) ✓`);
    mapCanvas.render();
  }
};

function drawTileSwatch(ctx, image, atlas) {
  ctx.clearRect(0, 0, 48, 48);
  ctx.drawImage(image, atlas[0] * 64, atlas[1] * 64, 64, 64, 0, 0, 48, 48);
}

function renderPalette(tiles, image) {
  paletteEl.innerHTML = "";
  animatedTileSwatches = [];
  for (const tile of tiles) {
    const wrap = document.createElement("div");
    wrap.className = "palette-tile";
    wrap.dataset.atlas = tile.atlas.join(",");

    const swatch = document.createElement("canvas");
    swatch.width = 48;
    swatch.height = 48;
    const ctx = swatch.getContext("2d");
    drawTileSwatch(ctx, image, tile.atlas);
    if (tile.frames?.length > 1) {
      animatedTileSwatches.push({ ctx, image, frames: tile.frames, fps: tile.fps });
    }

    const label = document.createElement("span");
    label.className = "tile-name";
    label.textContent = tile.name;

    wrap.append(swatch, label);
    wrap.onclick = () => setBrush(tile);
    paletteEl.appendChild(wrap);
  }
  updateRevealPaletteState();
}

// ---------- Palette (props) ----------

function setPropBrush(prop) {
  currentPropBrush = prop;
  setTool("prop");
  document
    .querySelectorAll(".prop-tile")
    .forEach((el) => el.classList.remove("selected"));
  const el = propsPaletteEl.querySelector(`[data-rect="${prop.rect.join(",")}"]`);
  el?.classList.add("selected");
}

async function refreshPropsPalette() {
  propsPaletteList = await getProps();
  renderPropsPalette(propsPaletteList, propImage);
  currentPropBrush = null;
  document
    .querySelectorAll(".prop-tile.selected")
    .forEach((el) => el.classList.remove("selected"));
  updateGhost();
}

managePropsBtn.onclick = () => openPropManager({ onChange: refreshPropsPalette });

function renderPropsPalette(list, image) {
  propsPaletteEl.innerHTML = "";
  animatedPropSwatches = [];
  for (const prop of list) {
    const wrap = document.createElement("div");
    wrap.className = "palette-tile prop-tile";
    wrap.dataset.rect = prop.rect.join(",");

    const swatch = document.createElement("canvas");
    swatch.width = 48;
    swatch.height = 48;
    const ctx = swatch.getContext("2d");
    drawPropSwatch(ctx, image, prop.rect);
    if (prop.frames?.length > 1) {
      animatedPropSwatches.push({ ctx, image, frames: prop.frames, fps: prop.fps });
    }

    const label = document.createElement("span");
    label.className = "tile-name";
    label.textContent = prop.name;

    wrap.append(swatch, label);
    wrap.onclick = () => setPropBrush(prop);
    propsPaletteEl.appendChild(wrap);
  }
}

function drawPropSwatch(ctx, image, rect) {
  ctx.clearRect(0, 0, 48, 48);
  const [rx, ry, rw, rh] = rect;
  if (rw <= 0 || rh <= 0) return;
  const scale = Math.min(48 / rw, 48 / rh);
  const dw = rw * scale;
  const dh = rh * scale;
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(image, rx, ry, rw, rh, (48 - dw) / 2, (48 - dh) / 2, dw, dh);
}

// ---------- Sélection d'un prop déjà posé ----------

function selectProp(prop) {
  selectedProp = prop;
  mapCanvas?.setSelectedProp(prop);
  if (prop) {
    propInspectorEl.classList.remove("hidden");
    propInspectorNameEl.textContent = prop.name;
    propZIndexInput.value = prop.z_index || 0;
  } else {
    propInspectorEl.classList.add("hidden");
  }
}

propZIndexInput.onchange = () => {
  if (!selectedProp) return;
  pushUndo();
  selectedProp.z_index = parseInt(propZIndexInput.value, 10) || 0;
  mapCanvas.render();
};

propDeleteBtn.onclick = () => {
  const map = activeMap();
  if (!map || !selectedProp) return;
  pushUndo();
  const idx = map.props.indexOf(selectedProp);
  if (idx !== -1) map.props.splice(idx, 1);
  selectProp(null);
  mapCanvas.render();
};

// ---------- Peinture sur le canvas ----------

function paintAt(evt) {
  const map = activeMap();
  if (!map) return;

  if (currentTool === "erase") {
    const { x, y } = mapCanvas.pixelAt(evt);
    const hitProp = mapCanvas.propAt(x, y);
    if (hitProp) {
      // Un clic précis sur un prop ne supprime que lui, la tuile reste.
      const idx = map.props.indexOf(hitProp);
      if (idx !== -1) map.props.splice(idx, 1);
      if (selectedProp === hitProp) selectProp(null);
      mapCanvas.setDimProp(null);
      mapCanvas.render();
      return;
    }
    const { col, row } = mapCanvas.cellAt(evt);
    const key = `${col},${row}`;
    if (!map.cells[key]) return;
    delete map.cells[key];
    // Supprime aussi tous les props posés sur cette case : sans tuile
    // dessous, ils resteraient affichés "dans le vide".
    map.props = (map.props || []).filter((prop) => {
      const cell = pixelToCell(prop.x, prop.y);
      return !(cell.col === col && cell.row === row);
    });
    mapCanvas.render();
    return;
  }

  if (currentTool === "reveal") {
    if (!currentRevealBrush) {
      setStatus("Choisis d'abord une tuile dans la palette");
      return;
    }
    const { col, row } = mapCanvas.cellAt(evt);
    const cell = map.cells[`${col},${row}`];
    const def = cell && mapCanvas.tileDefs.get(cell.atlas.join(","));
    if (!cell || def?.terrain_type !== "empty1") {
      setStatus("Clique une case Empty pour lui assigner une révélation");
      return;
    }
    cell.reveal_atlas = currentRevealBrush.atlas;
    mapCanvas.render();
    return;
  }

  if (currentBrush) {
    const { col, row } = mapCanvas.cellAt(evt);
    map.cells[`${col},${row}`] = {
      source_id: currentBrush.source_id,
      atlas: currentBrush.atlas,
    };
    resyncPropsRevealCell(map);
    mapCanvas.render();
  }
}

// Garde reveal_cell synchronisé avec la nature réelle de la case pour TOUS
// les props d'un coup (pas seulement ceux de la case qui vient d'être
// repeinte) : recalculé à l'ouverture et à la sauvegarde d'une map en plus
// d'après chaque case repeinte, pour rattraper aussi les props posés sur une
// case déjà Empty avant même l'existence de cette fonctionnalité (ou modifiés
// hors de l'éditeur). Une case Empty masque les props qui s'y trouvent (ils
// suivront sa révélation) ; toute autre tuile les rend visibles.
function resyncPropsRevealCell(map) {
  for (const prop of map.props || []) {
    const cell = pixelToCell(prop.x, prop.y);
    const tile = map.cells[`${cell.col},${cell.row}`];
    const isEmpty = tile && mapCanvas.tileDefs.get(tile.atlas.join(","))?.terrain_type === "empty1";
    if (isEmpty) {
      prop.reveal_cell = [cell.col, cell.row];
    } else {
      delete prop.reveal_cell;
    }
  }
}

// Recentre les props dont le sprite déborde du cadre (TILE_W x TILE_H) de la
// case à laquelle ils sont liés (reveal_cell) : posés trop près d'un bord,
// ils peuvent sembler "flotter" à côté de la case au moment de sa révélation
// plutôt que dessus, que le voisin soit peint ou non — le cadre de la tuile
// elle-même est la seule limite qui compte visuellement. Retourne le nombre
// de props effectivement déplacés.
function fixOverflowingProps(map) {
  const HALF_W = TILE_W / 2;
  const HALF_H = TILE_H / 2;
  let fixedCount = 0;
  for (const prop of map.props || []) {
    if (!prop.reveal_cell) continue;
    const center = cellToPixel(prop.reveal_cell[0], prop.reveal_cell[1]);
    const [, , rw, rh] = prop.rect;
    const maxDx = Math.max(0, HALF_W - rw / 2);
    const maxDy = Math.max(0, HALF_H - rh / 2);
    const dx = Math.min(maxDx, Math.max(-maxDx, prop.x - center.x));
    const dy = Math.min(maxDy, Math.max(-maxDy, prop.y - center.y));
    const newX = center.x + dx;
    const newY = center.y + dy;
    if (newX !== prop.x || newY !== prop.y) {
      prop.x = newX;
      prop.y = newY;
      fixedCount++;
    }
  }
  return fixedCount;
}

// ---------- Placement / sélection / déplacement des props ----------

function propMouseDown(evt) {
  const map = activeMap();
  if (!map) return;
  const { x, y } = mapCanvas.pixelAt(evt);
  const hit = mapCanvas.propAt(x, y);

  if (hit) {
    pushUndo();
    selectProp(hit);
    draggingProp = true;
    dragOffset = { x: x - hit.x, y: y - hit.y };
    return;
  }

  if (currentPropBrush) {
    pushUndo();
    const prop = {
      name: currentPropBrush.name,
      rect: currentPropBrush.rect,
      frames: currentPropBrush.frames,
      fps: currentPropBrush.fps,
      x,
      y,
      z_index: 0,
    };
    // Posé sur une case "Empty" : reste caché en jeu jusqu'à ce que cette
    // case soit révélée (cf run_reveal_sequence() côté Godot), sans réglage
    // manuel — déterminé simplement par ce qu'il y a sous le prop au moment
    // où on le pose.
    const { col, row } = mapCanvas.cellAt(evt);
    const underCell = map.cells[`${col},${row}`];
    const underDef = underCell && mapCanvas.tileDefs.get(underCell.atlas.join(","));
    if (underDef?.terrain_type === "empty1") {
      prop.reveal_cell = [col, row];
    }
    map.props.push(prop);
    selectProp(prop);
    draggingProp = true;
    dragOffset = { x: 0, y: 0 };
    mapCanvas.render();
    return;
  }

  selectProp(null);
}

function propMouseMove(evt) {
  hoverPixel = mapCanvas.pixelAt(evt);
  if (draggingProp && selectedProp) {
    selectedProp.x = hoverPixel.x - dragOffset.x;
    selectedProp.y = hoverPixel.y - dragOffset.y;
    mapCanvas.render();
  } else {
    updateGhost();
  }
}

// ---------- Mini-preview : afficher/masquer + déplacer ----------

function setMiniVisible(visible) {
  miniWrapEl.classList.toggle("collapsed", !visible);
  miniToggleBtn.innerHTML = visible ? EYE_OPEN : EYE_CLOSED;
  miniToggleBtn.title = visible ? "Masquer la preview" : "Afficher la preview";
}

miniToggleBtn.onclick = (evt) => {
  evt.stopPropagation();
  setMiniVisible(miniWrapEl.classList.contains("collapsed"));
};

function makeMiniDraggable() {
  let dragging = false;
  let startX, startY, startLeft, startTop;

  miniLabelEl.addEventListener("mousedown", (evt) => {
    if (evt.target.closest("#mini-toggle-btn")) return;
    const wrapRect = miniWrapEl.getBoundingClientRect();
    const parentRect = miniWrapEl.offsetParent.getBoundingClientRect();
    startLeft = wrapRect.left - parentRect.left;
    startTop = wrapRect.top - parentRect.top;
    miniWrapEl.style.right = "auto";
    miniWrapEl.style.bottom = "auto";
    miniWrapEl.style.left = `${startLeft}px`;
    miniWrapEl.style.top = `${startTop}px`;
    startX = evt.clientX;
    startY = evt.clientY;
    dragging = true;
    evt.preventDefault();
  });

  window.addEventListener("mousemove", (evt) => {
    if (!dragging) return;
    miniWrapEl.style.left = `${startLeft + (evt.clientX - startX)}px`;
    miniWrapEl.style.top = `${startTop + (evt.clientY - startY)}px`;
  });

  window.addEventListener("mouseup", () => {
    dragging = false;
  });
}

// ---------- Zoom : la preview occupe toute la largeur de #canvas-wrap ----------

function fitPreviewWidth() {
  if (!autoFitZoom || !mapCanvas) return;
  const style = getComputedStyle(canvasWrapEl);
  const available =
    canvasWrapEl.clientWidth -
    parseFloat(style.paddingLeft) -
    parseFloat(style.paddingRight);
  const zoom = mapCanvas.fitToWidth(available);
  zoomLevelEl.textContent = `${zoom}x`;
}

// ---------- Init ----------

async function init() {
  const { image, tiles } = await buildPalette();
  paletteTiles = tiles;
  renderPalette(tiles, image);

  propImage = await loadImage("/sprites/props.png");
  propsPaletteList = await getProps();
  renderPropsPalette(propsPaletteList, propImage);

  mapCanvas = new MapCanvas(canvasEl, image, propImage, propsCanvasEl, previewFrameEl, miniCanvasEl);
  mapCanvas.setTileDefs(paletteTiles);
  zoomLevelEl.textContent = `${mapCanvas.zoom}x`;
  setMiniVisible(true);
  makeMiniDraggable();
  setTool("paint");

  let painting = false;
  canvasEl.addEventListener("mousedown", (evt) => {
    if (currentTool === "prop") {
      propMouseDown(evt);
      return;
    }
    pushUndo();
    painting = true;
    paintAt(evt);
  });
  canvasEl.addEventListener("mousemove", (evt) => {
    if (currentTool === "prop") {
      propMouseMove(evt);
      return;
    }
    hoverCell = mapCanvas.cellAt(evt);
    hoverPixel = mapCanvas.pixelAt(evt);
    updateGhost();
    if (painting) paintAt(evt);
  });
  canvasEl.addEventListener("mouseleave", () => {
    hoverCell = null;
    hoverPixel = null;
    updateGhost();
  });
  window.addEventListener("mouseup", () => {
    painting = false;
    draggingProp = false;
  });

  zoomInBtn.onclick = () => {
    autoFitZoom = false;
    zoomLevelEl.textContent = `${mapCanvas.setZoom(Math.round(mapCanvas.zoom) + 1)}x`;
  };
  zoomOutBtn.onclick = () => {
    autoFitZoom = false;
    zoomLevelEl.textContent = `${mapCanvas.setZoom(Math.round(mapCanvas.zoom) - 1)}x`;
  };

  fitPreviewWidth();
  window.addEventListener("resize", fitPreviewWidth);

  renderTabStrip();

  const maps = await renderMapBrowser(modalMapList, modalHandlers);
  if (maps.length > 0) {
    await openTab(maps[0].id);
  }
  if (paletteTiles.length > 0) setBrush(paletteTiles[0]);
}

init();
