// La PLANCHE en grand : on la regarde, on s'y déplace, on y choisit l'extrait.
//
// POURQUOI UNE SEULE FENÊTRE POUR LES DEUX. « Chercher une pose » et « retenir
// cette pose » sont le même geste à un instant d'écart : chercher, c'est déjà
// désigner. Deux fenêtres — une visionneuse et un sélecteur — montreraient la
// même image côte à côte avec deux zooms qui divergent, et obligeraient à
// retrouver dans la seconde ce qu'on vient de repérer dans la première.
//
// POURQUOI PAS DEUX CHAMPS. `first_frame` et `frames` décrivent un extrait
// d'une grille qu'on ne voit pas : sur la planche d'attaque de Noah (3 × 7,
// 20 vignettes) l'auteur veut « la pose d'apprêt », pas « l'index 5 ». Les
// régler à l'aveugle demande de compter les cases sur l'image ouverte à côté,
// et une erreur d'un cran ne se voit qu'en jeu.
//
// LA GRILLE N'EST PAS DEVINÉE : elle vient des colonnes et des lignes déjà
// déclarées. Cette fenêtre ne mesure rien — c'est un travail d'atelier, fait
// sur l'image source, pas dans un éditeur web (cf. CLAUDE.md : une grille se
// mesure sur les gouttières d'alpha, elle ne se devine pas par division).

const overlay = document.getElementById("frame-picker-overlay");
const title = document.getElementById("frame-picker-title");
const closeBtn = document.getElementById("frame-picker-close");
const stage = document.getElementById("frame-picker-stage");
const info = document.getElementById("frame-picker-info");
const gridBox = document.getElementById("frame-picker-grid");
const allBtn = document.getElementById("frame-picker-all");
const applyBtn = document.getElementById("frame-picker-apply");
const zoomBtns = Array.from(document.querySelectorAll(".frame-zoom"));

// Les paliers sont ENTIERS : les planches sont du pixel-art, et un facteur
// fractionnaire double une colonne de pixels sur deux — la silhouette devient
// bancale et on juge une pose qui n'existe pas. « Ajusté » est le seul palier
// non entier, et seulement vers le BAS : il sert à embrasser une planche trop
// large (iris_win_before fait 1017 px), jamais à agrandir.
const STEPS = ["fit", "1", "2", "4"];
// En dessous, le numéro de vignette couvre le dessin qu'il annote.
const LABEL_MIN = 24;
// Un clic n'est jamais parfaitement immobile ; au-delà, c'était un glissement,
// et un glissement ne doit pas déplacer la sélection.
const DRAG_SLOP = 4;
const PAN_STEP = 48;

// Le réglage de vue survit à la fermeture : on ouvre six planches d'affilée
// pour la même unité, et redemander « 200 %, sans grille » à chaque fois est
// une corvée que l'outil doit s'épargner.
const view = { zoom: "fit", grid: true };

let state = null;
let resolve = null;
let cells = [];
let dragged = false;

// Rend {first_frame, frames}, ou null si l'auteur referme sans appliquer.
// `columns`/`rows` décrivent la grille, `count` le nombre de vignettes
// RÉELLEMENT dessinées (la dernière ligne peut être incomplète).
export function pickFrames(url, { columns, rows, first, count, name }) {
  state = {
    url,
    columns: Math.max(1, columns),
    rows: Math.max(1, rows),
    first: Math.max(0, first),
    last: Math.max(0, first) + Math.max(1, count) - 1,
    anchor: null,
    size: null,
    scale: 1,
  };
  title.textContent = name
    ? `Planche « ${name} » — ${url.split("/").pop()}`
    : `Planche — ${url.split("/").pop()}`;
  gridBox.checked = view.grid;
  overlay.classList.remove("hidden");
  render();
  return new Promise((r) => {
    resolve = r;
  });
}

function finish(value) {
  overlay.classList.add("hidden");
  stage.replaceChildren();
  cells = [];
  const done = resolve;
  resolve = null;
  state = null;
  if (done) done(value);
}

closeBtn.onclick = () => finish(null);
overlay.onclick = (evt) => {
  if (evt.target === overlay) finish(null);
};
applyBtn.onclick = () => {
  if (!state) return finish(null);
  finish({ first_frame: state.first, frames: state.last - state.first + 1 });
};
allBtn.onclick = () => {
  if (!state) return;
  state.first = 0;
  state.last = state.columns * state.rows - 1;
  state.anchor = null;
  refresh();
};
gridBox.onchange = () => {
  view.grid = gridBox.checked;
  applyGrid();
};
for (const button of zoomBtns) {
  button.type = "button";
  button.onclick = () => setZoom(button.dataset.zoom);
}

// L'aperçu se bâtit UNE fois ; cliquer, zoomer ou masquer la grille ne fait
// ensuite que reposer les cases sur la même image. Reconstruire à chaque geste
// rechargerait l'image, ferait clignoter la grille sous le curseur — et, plus
// insidieux, remplacerait la case qu'on vient de cliquer par une autre au même
// endroit.
function render() {
  stage.replaceChildren();
  cells = [];
  const image = new Image();
  image.className = "frame-picker-image";
  image.alt = "";
  // La grille se pose SUR l'image, à sa taille rendue : elle ne peut donc se
  // dimensionner qu'une fois l'image chargée, `naturalWidth` valant 0 avant
  // le décodage.
  image.onload = () => {
    const frame = document.createElement("div");
    frame.className = "frame-picker-frame";
    frame.appendChild(image);
    for (let index = 0; index < state.columns * state.rows; index += 1) {
      const cell = document.createElement("button");
      cell.type = "button";
      cell.className = "frame-picker-cell";
      cell.textContent = String(index);
      cell.onclick = () => select(index);
      frame.appendChild(cell);
      cells.push(cell);
    }
    stage.appendChild(frame);
    state.frame = frame;
    state.image = image;
    state.size = [image.naturalWidth, image.naturalHeight];
    layout();
    applyGrid();
    refresh();
    centreOnSelection();
    stage.focus({ preventScroll: true });
  };
  image.onerror = () => {
    stage.appendChild(
      Object.assign(document.createElement("p"), {
        className: "battle-warning",
        textContent: `Image introuvable (${state.url}).`,
      })
    );
  };
  image.src = state.url;
}

// « Ajusté » ne dépasse jamais 1 : la demande est de voir la planche EN TAILLE
// RÉELLE, et une petite planche étirée pour remplir la fenêtre montrerait des
// pixels qui n'existent pas.
function resolveZoom() {
  const [width, height] = state.size;
  if (view.zoom !== "fit") return Number(view.zoom);
  const fit = Math.min(stage.clientWidth / width, stage.clientHeight / height);
  return Math.min(1, fit);
}

function layout() {
  const scale = resolveZoom();
  state.scale = scale;
  const [width, height] = state.size;
  const cellW = (width / state.columns) * scale;
  const cellH = (height / state.rows) * scale;
  state.frame.style.width = `${width * scale}px`;
  state.frame.style.height = `${height * scale}px`;
  state.image.style.width = `${width * scale}px`;
  state.image.style.height = `${height * scale}px`;
  cells.forEach((cell, index) => {
    cell.style.left = `${(index % state.columns) * cellW}px`;
    cell.style.top = `${Math.floor(index / state.columns) * cellH}px`;
    cell.style.width = `${cellW}px`;
    cell.style.height = `${cellH}px`;
  });
  state.frame.classList.toggle("tiny", Math.min(cellW, cellH) < LABEL_MIN);
  for (const button of zoomBtns) {
    button.setAttribute("aria-pressed", String(button.dataset.zoom === view.zoom));
  }
  describe();
}

function applyGrid() {
  if (state && state.frame) state.frame.classList.toggle("no-grid", !view.grid);
}

// Zoomer en gardant SOUS LES YEUX ce qu'on regardait : sans cela, passer de
// 100 % à 400 % renvoie en haut à gauche de la planche, et il faut retrouver à
// la main la vignette qu'on était en train d'examiner.
function setZoom(value) {
  if (!state || !state.frame) {
    view.zoom = value;
    return;
  }
  const before = state.scale;
  const midX = (stage.scrollLeft + stage.clientWidth / 2) / before;
  const midY = (stage.scrollTop + stage.clientHeight / 2) / before;
  view.zoom = value;
  layout();
  stage.scrollLeft = midX * state.scale - stage.clientWidth / 2;
  stage.scrollTop = midY * state.scale - stage.clientHeight / 2;
}

function stepZoom(direction) {
  const rank = STEPS.indexOf(view.zoom);
  const next = Math.min(STEPS.length - 1, Math.max(0, rank + direction));
  if (next !== rank) setZoom(STEPS[next]);
}

// À l'ouverture, la fenêtre montre l'extrait DÉJÀ réglé : c'est lui qu'on vient
// vérifier ou corriger, et sur une planche de 21 cases il peut être n'importe
// où.
function centreOnSelection() {
  const cellW = (state.size[0] / state.columns) * state.scale;
  const cellH = (state.size[1] / state.rows) * state.scale;
  const firstCol = state.first % state.columns;
  const lastCol = state.last % state.columns;
  const midX = ((firstCol + lastCol) / 2 + 0.5) * cellW;
  const midY =
    ((Math.floor(state.first / state.columns) +
      Math.floor(state.last / state.columns)) /
      2 +
      0.5) *
    cellH;
  stage.scrollLeft = midX - stage.clientWidth / 2;
  stage.scrollTop = midY - stage.clientHeight / 2;
}

function refresh() {
  cells.forEach((cell, index) => {
    cell.classList.toggle("selected", index >= state.first && index <= state.last);
    cell.classList.toggle("anchor", index === state.anchor);
  });
  describe();
}

// Premier clic : point de départ, la sélection se réduit à cette vignette.
// Second : l'autre bout de l'intervalle, dans un sens comme dans l'autre.
function select(index) {
  if (dragged) return;
  if (state.anchor === null) {
    state.anchor = index;
    state.first = index;
    state.last = index;
  } else {
    state.first = Math.min(state.anchor, index);
    state.last = Math.max(state.anchor, index);
    state.anchor = null;
  }
  refresh();
}

// La taille est relevée au chargement de l'image (cf. render) : `describe` la
// lit dans l'état plutôt que de la recevoir, puisqu'il est aussi appelé après
// un simple clic, sans image à portée.
function describe() {
  const [width, height] = state.size || [0, 0];
  const total = state.columns * state.rows;
  const count = state.last - state.first + 1;
  const zoom = `${Math.round(state.scale * 100)} %`;
  info.textContent =
    `${width}×${height} à ${zoom} — cellule ${Math.round(width / state.columns)}×` +
    `${Math.round(height / state.rows)}, ${total} vignettes. ` +
    `Sélection : ${state.first} à ${state.last} (${count} vignette${count > 1 ? "s" : ""}).`;
}

// ---------- Navigation sur la planche ----------
//
// À 400 %, une planche de 1017 px en fait 4068 : les barres de défilement
// suffisent techniquement, mais on examine une planche comme une carte, en la
// tirant. Le glissement s'ajoute aux barres, il ne les remplace pas.

let pan = null;

stage.addEventListener("pointerdown", (evt) => {
  if (evt.button !== 0) return;
  dragged = false;
  pan = {
    id: evt.pointerId,
    x: evt.clientX,
    y: evt.clientY,
    left: stage.scrollLeft,
    top: stage.scrollTop,
  };
});

stage.addEventListener("pointermove", (evt) => {
  if (!pan || evt.pointerId !== pan.id) return;
  const dx = evt.clientX - pan.x;
  const dy = evt.clientY - pan.y;
  if (!dragged && Math.hypot(dx, dy) > DRAG_SLOP) {
    dragged = true;
    stage.classList.add("panning");
    // La capture n'est prise qu'une fois le glissement reconnu : la prendre au
    // pointerdown détournerait le clic des cases, qui ne recevraient plus rien.
    stage.setPointerCapture(pan.id);
  }
  if (!dragged) return;
  stage.scrollLeft = pan.left - dx;
  stage.scrollTop = pan.top - dy;
});

function endPan() {
  if (pan && stage.hasPointerCapture(pan.id)) stage.releasePointerCapture(pan.id);
  pan = null;
  stage.classList.remove("panning");
  // `dragged` est lu par `select`, appelé au clic — donc APRÈS ce relâchement.
  // On le laisse en place jusqu'au prochain appui.
}

stage.addEventListener("pointerup", endPan);
stage.addEventListener("pointercancel", endPan);

overlay.addEventListener("keydown", (evt) => {
  if (!state) return;
  if (evt.key === "Escape") {
    finish(null);
    return;
  }
  if (evt.key === "+" || evt.key === "=") {
    stepZoom(1);
  } else if (evt.key === "-" || evt.key === "_") {
    stepZoom(-1);
  } else if (evt.key.startsWith("Arrow")) {
    // Dans un champ de saisie, les flèches appartiennent au champ.
    if (evt.target.tagName === "INPUT" || evt.target.tagName === "SELECT") return;
    const step = PAN_STEP * (evt.shiftKey ? 5 : 1);
    if (evt.key === "ArrowLeft") stage.scrollLeft -= step;
    else if (evt.key === "ArrowRight") stage.scrollLeft += step;
    else if (evt.key === "ArrowUp") stage.scrollTop -= step;
    else stage.scrollTop += step;
  } else {
    return;
  }
  evt.preventDefault();
});
