import { getTiles, saveTiles } from "./api.js";
import { loadImage, scanOccupiedCells, CELL } from "./palette.js";

const overlay = document.getElementById("tiles-modal-overlay");
const closeBtn = document.getElementById("tiles-modal-close");
const listEl = document.getElementById("tiles-list");
const addBtn = document.getElementById("tiles-add-btn");

const pickerOverlay = document.getElementById("atlas-picker-overlay");
const pickerClose = document.getElementById("atlas-picker-close");
const pickerGrid = document.getElementById("atlas-picker-grid");

let image = null;
let tiles = [];
let onChange = null;
let dragFromIndex = null;
let pickerTarget = null; // { tileIndex, frameIndex } — frameIndex null = ajoute une frame

// Anciennes tuiles sans "frames" : on migre en mémoire vers une séquence à
// une seule image, sans casser les tuiles déjà enregistrées ailleurs.
function ensureFrames(tile) {
  if (!tile.frames || tile.frames.length === 0) tile.frames = [tile.atlas];
  if (!tile.fps) tile.fps = 4;
  tile.atlas = tile.frames[0];
  return tile;
}

function drawFrameSwatch(canvas, atlas) {
  canvas.width = 32;
  canvas.height = 32;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, 32, 32);
  if (!image) return;
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(image, atlas[0] * CELL, atlas[1] * CELL, CELL, CELL, 0, 0, 32, 32);
}

async function persist() {
  await saveTiles(tiles);
  onChange?.();
}

function startRename(nameEl, tile) {
  nameEl.classList.add("editing");
  nameEl.contentEditable = "true";
  nameEl.focus();

  const range = document.createRange();
  range.selectNodeContents(nameEl);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  const finish = async (commit) => {
    nameEl.classList.remove("editing");
    nameEl.contentEditable = "false";
    nameEl.removeEventListener("blur", onBlur);
    nameEl.removeEventListener("keydown", onKeydown);
    const newName = nameEl.textContent.trim();
    if (commit && newName && newName !== tile.name) {
      tile.name = newName;
      await persist();
    } else {
      nameEl.textContent = tile.name;
    }
  };

  const onBlur = () => finish(true);
  const onKeydown = (evt) => {
    if (evt.key === "Enter") {
      evt.preventDefault();
      nameEl.blur();
    }
    if (evt.key === "Escape") {
      evt.preventDefault();
      finish(false);
    }
  };

  nameEl.addEventListener("blur", onBlur);
  nameEl.addEventListener("keydown", onKeydown);
}

function renderFrameStrip(container, tile, tileIndex) {
  container.innerHTML = "";
  tile.frames.forEach((frame, frameIndex) => {
    const wrap = document.createElement("div");
    wrap.className = "frame-swatch";
    wrap.title = "Clic pour changer cette image";

    const canvas = document.createElement("canvas");
    drawFrameSwatch(canvas, frame);
    wrap.appendChild(canvas);
    wrap.onclick = () => openPicker(tileIndex, frameIndex);

    if (tile.frames.length > 1) {
      const del = document.createElement("button");
      del.className = "frame-remove";
      del.textContent = "×";
      del.title = "Retirer cette image de l'animation";
      del.onclick = async (evt) => {
        evt.stopPropagation();
        tile.frames.splice(frameIndex, 1);
        tile.atlas = tile.frames[0];
        renderList();
        await persist();
      };
      wrap.appendChild(del);
    }

    container.appendChild(wrap);
  });

  const addFrame = document.createElement("button");
  addFrame.className = "frame-add";
  addFrame.textContent = "+";
  addFrame.title = "Ajouter une image à l'animation";
  addFrame.onclick = () => openPicker(tileIndex, null);
  container.appendChild(addFrame);
}

function renderList() {
  listEl.innerHTML = "";
  tiles.forEach((tile, index) => {
    ensureFrames(tile);
    const row = document.createElement("div");
    row.className = "tile-row";
    row.draggable = true;
    row.dataset.index = String(index);

    const handle = document.createElement("span");
    handle.className = "tile-drag-handle";
    handle.textContent = "⠿";
    handle.title = "Glisser pour réordonner";

    const frameStrip = document.createElement("div");
    frameStrip.className = "frame-strip";
    renderFrameStrip(frameStrip, tile, index);

    const name = document.createElement("span");
    name.className = "tile-row-name";
    name.textContent = tile.name;
    name.title = "Double-clic pour renommer";
    name.ondblclick = () => startRename(name, tile);

    const fpsLabel = document.createElement("label");
    fpsLabel.className = "fps-label";
    fpsLabel.textContent = "FPS";
    const fpsInput = document.createElement("input");
    fpsInput.type = "number";
    fpsInput.min = "1";
    fpsInput.step = "1";
    fpsInput.value = tile.fps;
    fpsInput.title = "Images par seconde de l'animation";
    fpsInput.onchange = async () => {
      tile.fps = parseInt(fpsInput.value, 10) || 4;
      await persist();
    };
    fpsLabel.appendChild(fpsInput);

    const del = document.createElement("button");
    del.className = "modal-map-delete";
    del.textContent = "🗑";
    del.title = "Supprimer cette tuile";
    del.onclick = async () => {
      if (!confirm(`Supprimer la tuile "${tile.name}" ?`)) return;
      tiles.splice(index, 1);
      renderList();
      await persist();
    };

    row.append(handle, frameStrip, name, fpsLabel, del);

    row.addEventListener("dragstart", (evt) => {
      dragFromIndex = index;
      evt.dataTransfer.effectAllowed = "move";
      row.classList.add("dragging");
    });
    row.addEventListener("dragend", () => {
      row.classList.remove("dragging");
      listEl
        .querySelectorAll(".tile-row")
        .forEach((el) => el.classList.remove("drag-over"));
    });
    row.addEventListener("dragover", (evt) => {
      evt.preventDefault();
      row.classList.add("drag-over");
    });
    row.addEventListener("dragleave", () => {
      row.classList.remove("drag-over");
    });
    row.addEventListener("drop", async (evt) => {
      evt.preventDefault();
      row.classList.remove("drag-over");
      if (dragFromIndex === null || dragFromIndex === index) return;
      const [moved] = tiles.splice(dragFromIndex, 1);
      tiles.splice(index, 0, moved);
      dragFromIndex = null;
      renderList();
      await persist();
    });

    listEl.appendChild(row);
  });
}

function openPicker(tileIndex, frameIndex) {
  pickerTarget = { tileIndex, frameIndex };
  const cells = scanOccupiedCells(image);
  pickerGrid.innerHTML = "";
  const tile = tiles[tileIndex];
  const current = frameIndex === null ? null : tile.frames[frameIndex];

  for (const [col, row] of cells) {
    const cell = document.createElement("div");
    cell.className = "atlas-picker-cell";
    if (current && col === current[0] && row === current[1]) {
      cell.classList.add("selected");
    }

    const swatch = document.createElement("canvas");
    swatch.width = 48;
    swatch.height = 48;
    const ctx = swatch.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(image, col * CELL, row * CELL, CELL, CELL, 0, 0, 48, 48);

    cell.appendChild(swatch);
    cell.onclick = async () => {
      const { tileIndex, frameIndex } = pickerTarget;
      const t = tiles[tileIndex];
      if (frameIndex === null) {
        t.frames.push([col, row]);
      } else {
        t.frames[frameIndex] = [col, row];
      }
      t.atlas = t.frames[0];
      closePicker();
      renderList();
      await persist();
    };

    pickerGrid.appendChild(cell);
  }

  pickerOverlay.classList.remove("hidden");
}

function closePicker() {
  pickerOverlay.classList.add("hidden");
  pickerTarget = null;
}

pickerClose.onclick = closePicker;
pickerOverlay.onclick = (evt) => {
  if (evt.target === pickerOverlay) closePicker();
};

addBtn.onclick = async () => {
  const cells = scanOccupiedCells(image);
  const used = new Set(tiles.map((t) => `${t.atlas[0]},${t.atlas[1]}`));
  const free = cells.find(([c, r]) => !used.has(`${c},${r}`)) || cells[0];
  const tile = {
    name: "Nouvelle tuile",
    source_id: 0,
    atlas: free,
    frames: [free],
    fps: 4,
    terrain_type: null,
    walkable: true,
    movement_cost: 1,
  };
  tiles.push(tile);
  renderList();
  await persist();
  openPicker(tiles.length - 1, 0);
};

closeBtn.onclick = closeManager;
overlay.onclick = (evt) => {
  if (evt.target === overlay) closeManager();
};

function closeManager() {
  overlay.classList.add("hidden");
  closePicker();
}

export async function openTileManager(opts) {
  onChange = opts?.onChange || null;
  if (!image) image = await loadImage("/sprites/hex_tiles.png");
  tiles = await getTiles();
  renderList();
  overlay.classList.remove("hidden");
}
