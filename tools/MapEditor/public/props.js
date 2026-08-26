import { getProps, saveProps } from "./api.js";
import { loadImage } from "./palette.js";

const overlay = document.getElementById("props-modal-overlay");
const closeBtn = document.getElementById("props-modal-close");
const listEl = document.getElementById("props-list");
const addBtn = document.getElementById("props-add-btn");

const pickerOverlay = document.getElementById("rect-picker-overlay");
const pickerClose = document.getElementById("rect-picker-close");
const pickerCanvas = document.getElementById("rect-picker-canvas");
const pickerCtx = pickerCanvas.getContext("2d");

let image = null;
let props = [];
let onChange = null;
let dragFromIndex = null;
let pickerTarget = null; // { propIndex, frameIndex } — frameIndex null = ajoute une frame
let pickerZoom = 1;

// Anciens props sans "frames" : migration en mémoire vers une séquence à une
// seule image, sans casser les props déjà enregistrés ailleurs.
function ensureFrames(prop) {
  if (!prop.frames || prop.frames.length === 0) prop.frames = [prop.rect];
  if (!prop.fps) prop.fps = 4;
  prop.rect = prop.frames[0];
  return prop;
}

function drawFrameSwatch(canvas, rect) {
  const [rx, ry, rw, rh] = rect;
  const size = 32;
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, size, size);
  if (!image || rw <= 0 || rh <= 0) return;
  const scale = Math.min(size / rw, size / rh);
  const dw = rw * scale;
  const dh = rh * scale;
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(image, rx, ry, rw, rh, (size - dw) / 2, (size - dh) / 2, dw, dh);
}

async function persist() {
  await saveProps(props);
  onChange?.();
}

function startRename(nameEl, prop) {
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
    if (commit && newName && newName !== prop.name) {
      prop.name = newName;
      await persist();
    } else {
      nameEl.textContent = prop.name;
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

function renderFrameStrip(container, prop, propIndex) {
  container.innerHTML = "";
  prop.frames.forEach((frame, frameIndex) => {
    const wrap = document.createElement("div");
    wrap.className = "frame-swatch";
    wrap.title = "Clic pour changer cette image";

    const canvas = document.createElement("canvas");
    drawFrameSwatch(canvas, frame);
    wrap.appendChild(canvas);
    wrap.onclick = () => openPicker(propIndex, frameIndex);

    if (prop.frames.length > 1) {
      const del = document.createElement("button");
      del.className = "frame-remove";
      del.textContent = "×";
      del.title = "Retirer cette image de l'animation";
      del.onclick = async (evt) => {
        evt.stopPropagation();
        prop.frames.splice(frameIndex, 1);
        prop.rect = prop.frames[0];
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
  addFrame.onclick = () => openPicker(propIndex, null);
  container.appendChild(addFrame);
}

function renderList() {
  listEl.innerHTML = "";
  props.forEach((prop, index) => {
    ensureFrames(prop);
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
    renderFrameStrip(frameStrip, prop, index);

    const name = document.createElement("span");
    name.className = "tile-row-name";
    name.textContent = prop.name;
    name.title = "Double-clic pour renommer";
    name.ondblclick = () => startRename(name, prop);

    const fpsLabel = document.createElement("label");
    fpsLabel.className = "fps-label";
    fpsLabel.textContent = "FPS";
    const fpsInput = document.createElement("input");
    fpsInput.type = "number";
    fpsInput.min = "1";
    fpsInput.step = "1";
    fpsInput.value = prop.fps;
    fpsInput.title = "Images par seconde de l'animation";
    fpsInput.onchange = async () => {
      prop.fps = parseInt(fpsInput.value, 10) || 4;
      await persist();
    };
    fpsLabel.appendChild(fpsInput);

    const del = document.createElement("button");
    del.className = "modal-map-delete";
    del.textContent = "🗑";
    del.title = "Supprimer ce prop";
    del.onclick = async () => {
      if (!confirm(`Supprimer le prop "${prop.name}" ?`)) return;
      props.splice(index, 1);
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
      const [moved] = props.splice(dragFromIndex, 1);
      props.splice(index, 0, moved);
      dragFromIndex = null;
      renderList();
      await persist();
    });

    listEl.appendChild(row);
  });
}

function redrawPicker(liveRect) {
  const w = image.width * pickerZoom;
  const h = image.height * pickerZoom;
  pickerCanvas.width = w;
  pickerCanvas.height = h;
  pickerCtx.imageSmoothingEnabled = false;
  pickerCtx.clearRect(0, 0, w, h);
  pickerCtx.drawImage(image, 0, 0, w, h);

  const { propIndex, frameIndex } = pickerTarget;
  const current = frameIndex === null ? null : props[propIndex].frames[frameIndex];
  if (current && current[2] > 0) {
    pickerCtx.strokeStyle = "#7bc67e";
    pickerCtx.lineWidth = 2;
    pickerCtx.strokeRect(
      current[0] * pickerZoom,
      current[1] * pickerZoom,
      current[2] * pickerZoom,
      current[3] * pickerZoom
    );
  }

  if (liveRect) {
    pickerCtx.strokeStyle = "#e8e8ec";
    pickerCtx.lineWidth = 1;
    pickerCtx.setLineDash([4, 3]);
    pickerCtx.strokeRect(
      liveRect.x * pickerZoom,
      liveRect.y * pickerZoom,
      liveRect.w * pickerZoom,
      liveRect.h * pickerZoom
    );
    pickerCtx.setLineDash([]);
  }
}

function openPicker(propIndex, frameIndex) {
  pickerTarget = { propIndex, frameIndex };
  pickerZoom = Math.max(1, Math.floor(360 / Math.max(image.width, image.height)));
  redrawPicker(null);
  pickerOverlay.classList.remove("hidden");
}

function closePicker() {
  pickerOverlay.classList.add("hidden");
  pickerTarget = null;
}

let dragging = false;
let dragStart = null;

pickerCanvas.addEventListener("mousedown", (evt) => {
  const rect = pickerCanvas.getBoundingClientRect();
  const x = Math.round((evt.clientX - rect.left) / pickerZoom);
  const y = Math.round((evt.clientY - rect.top) / pickerZoom);
  dragStart = { x, y };
  dragging = true;
});

pickerCanvas.addEventListener("mousemove", (evt) => {
  if (!dragging) return;
  const rect = pickerCanvas.getBoundingClientRect();
  const x = Math.round((evt.clientX - rect.left) / pickerZoom);
  const y = Math.round((evt.clientY - rect.top) / pickerZoom);
  const liveRect = {
    x: Math.min(dragStart.x, x),
    y: Math.min(dragStart.y, y),
    w: Math.abs(x - dragStart.x),
    h: Math.abs(y - dragStart.y),
  };
  redrawPicker(liveRect);
});

window.addEventListener("mouseup", async (evt) => {
  if (!dragging) return;
  dragging = false;
  const rect = pickerCanvas.getBoundingClientRect();
  const x = Math.round((evt.clientX - rect.left) / pickerZoom);
  const y = Math.round((evt.clientY - rect.top) / pickerZoom);
  const finalRect = {
    x: Math.min(dragStart.x, x),
    y: Math.min(dragStart.y, y),
    w: Math.abs(x - dragStart.x),
    h: Math.abs(y - dragStart.y),
  };
  dragStart = null;
  if (finalRect.w < 2 || finalRect.h < 2 || !pickerTarget) return;

  const { propIndex, frameIndex } = pickerTarget;
  const prop = props[propIndex];
  const rectArr = [finalRect.x, finalRect.y, finalRect.w, finalRect.h];
  if (frameIndex === null) {
    prop.frames.push(rectArr);
  } else {
    prop.frames[frameIndex] = rectArr;
  }
  prop.rect = prop.frames[0];
  closePicker();
  renderList();
  await persist();
});

pickerClose.onclick = closePicker;
pickerOverlay.onclick = (evt) => {
  if (evt.target === pickerOverlay) closePicker();
};

addBtn.onclick = async () => {
  const rect = [0, 0, Math.min(20, image.width), Math.min(20, image.height)];
  const prop = {
    name: "Nouveau prop",
    rect,
    frames: [rect],
    fps: 4,
  };
  props.push(prop);
  renderList();
  await persist();
  openPicker(props.length - 1, 0);
};

closeBtn.onclick = closeManager;
overlay.onclick = (evt) => {
  if (evt.target === overlay) closeManager();
};

function closeManager() {
  overlay.classList.add("hidden");
  closePicker();
}

export async function openPropManager(opts) {
  onChange = opts?.onChange || null;
  if (!image) image = await loadImage("/sprites/props.png");
  props = await getProps();
  renderList();
  overlay.classList.remove("hidden");
}
