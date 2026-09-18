// Aperçu ANIMÉ d'une planche, tel que le jeu la jouera.
//
// POURQUOI ANIMÉ ET PAS UNE VIGNETTE. Les réglages d'une planche ne se relisent
// pas : « 3 colonnes, 7 lignes, extrait 5, 1 vignette, 6 fps, en boucle » ne dit
// rien de ce qu'on verra. Un aperçu qui joue vraiment répond d'un coup aux
// quatre questions qui comptent — le bon découpage, le bon extrait, la bonne
// cadence, et si ça tourne en rond ou si ça s'arrête.
//
// UNE SEULE HORLOGE pour tous les aperçus de la page : une unité en porte six,
// la page en montre une vingtaine, et autant de `setInterval` dériveraient les
// uns par rapport aux autres tout en tournant dans des onglets cachés. La
// boucle se range d'elle-même quand un aperçu quitte le document — la liste est
// redessinée à chaque modification, donc ça arrive sans arrêt.

const previews = new Set();
let ticking = false;

// Deux tailles, parce que l'aperçu ne sert pas à la même chose selon l'état.
// REPLIÉ, il tient dans la vignette carrée de la planche-contact (cf.
// .battle-anim-thumb, 112×112 dans battle.js) — la borne laisse la place, sous
// le dessin, au bouton « ↻ Rejouer » d'une planche qui ne boucle pas. DÉPLIÉ,
// on juge le découpage et la cadence : il lui faut de la place. Les bornes
// tiennent compte des cellules réelles, de 46×68 (iris/win) à 339×103
// (iris/win_before).
const BOX_COLLAPSED = [96, 70];
const BOX_OPEN = [260, 148];
// Les planches sont du pixel-art : on ne les agrandit qu'en facteur ENTIER,
// sinon une colonne de pixels sur deux double de largeur et la silhouette
// devient bancale. La réduction, elle, n'a pas ce choix.
const MAX_ZOOM = 2;

// Taille en pixels d'une planche, mémorisée par URL. Le navigateur est le seul
// à la connaître (le serveur ne décode pas de PNG), et plusieurs endroits en ont
// besoin : l'aperçu pour se dimensionner, les champs d'ancrage pour afficher le
// défaut du moteur — le centre-bas de la CELLULE, qu'on ne peut pas deviner
// sans la taille de l'image.
const sizes = new Map();

// À appeler quand le FICHIER derrière une URL a changé (réimport par-dessus) :
// la taille mémorisée décrirait sinon l'ancienne image, et c'est elle qui sert
// à afficher la taille de vignette et le défaut d'ancrage.
export function forgetSheetSize(url) {
  sizes.delete(url);
}

export function sheetSize(url) {
  if (!url) return Promise.resolve(null);
  if (!sizes.has(url)) {
    sizes.set(url, new Promise((resolve) => {
      const image = new Image();
      image.onload = () => resolve([image.naturalWidth, image.naturalHeight]);
      image.onerror = () => resolve(null);
      image.src = url;
    }));
  }
  return sizes.get(url);
}

// Vignette FIXE d'une planche — sa première image, à l'échelle qui tient dans
// `box`. Sert d'icône dans la liste des unités : une vignette animée y
// attirerait l'œil en permanence, alors que cette colonne sert à se repérer, pas
// à juger une animation.
export function staticFrame(config, url, box) {
  const canvas = document.createElement("canvas");
  canvas.className = "sheet-thumb";
  canvas.width = box;
  canvas.height = box;
  if (!url) return canvas;
  const image = new Image();
  image.src = url;
  image.onload = () => {
    const columns = Math.max(1, Number(config.columns || 1));
    const rows = Math.max(1, Number(config.rows || 1));
    const cellW = image.naturalWidth / columns;
    const cellH = image.naturalHeight / rows;
    const index = Math.max(0, Number(config.first_frame || 0));
    const zoom = Math.min(box / cellW, box / cellH);
    const width = cellW * zoom;
    const height = cellH * zoom;
    const context = canvas.getContext("2d");
    context.imageSmoothingEnabled = false;
    context.drawImage(
      image,
      (index % columns) * cellW, Math.floor(index / columns) * cellH, cellW, cellH,
      (box - width) / 2, box - height, width, height
    );
  };
  return canvas;
}

export function animationPreview(config, url, open = false) {
  const wrap = document.createElement("div");
  wrap.className = "sheet-preview";
  if (!url) {
    wrap.appendChild(hint("Aucune image."));
    return wrap;
  }

  const canvas = document.createElement("canvas");
  canvas.className = "sheet-preview-canvas";
  wrap.appendChild(canvas);

  const image = new Image();
  image.src = url;
  image.onerror = () => {
    wrap.replaceChildren(hint(`Image introuvable (${url}).`));
  };
  image.onload = () => {
    const columns = Math.max(1, Number(config.columns || 1));
    const rows = Math.max(1, Number(config.rows || 1));
    const cell = [image.naturalWidth / columns, image.naturalHeight / rows];
    const [boxW, boxH] = open ? BOX_OPEN : BOX_COLLAPSED;
    const fit = Math.min(boxW / cell[0], boxH / cell[1]);
    const zoom = fit >= 1 ? Math.min(MAX_ZOOM, Math.floor(fit)) : fit;
    canvas.width = Math.round(cell[0] * zoom);
    canvas.height = Math.round(cell[1] * zoom);

    const preview = {
      canvas,
      context: canvas.getContext("2d"),
      image,
      columns,
      cell,
      zoom,
      first: Math.max(0, Number(config.first_frame || 0)),
      count: Math.max(1, Number(config.frames || 1)),
      fps: Math.max(1, Number(config.fps || 6)),
      loop: config.loop !== false,
      anchor: Array.isArray(config.anchor)
        ? config.anchor
        : [Math.floor(cell[0] / 2), cell[1]],
      startedAt: performance.now(),
    };
    previews.add(preview);
    start();

    // Une planche qui ne boucle pas s'arrête sur sa dernière vignette : sans
    // moyen de la relancer, on ne la verrait qu'une fois, au moment où on
    // regarde ailleurs.
    if (!preview.loop) {
      const again = document.createElement("button");
      again.type = "button";
      again.className = "text-btn";
      again.textContent = "↻ Rejouer";
      again.onclick = (evt) => {
        // CE QUE FAIT L'APERÇU AU CLIC DÉPEND DE L'APPELANT (cf. battle.js :
        // ouvrir la planche en grand, ou déplier/replier le bloc) — dans les
        // deux cas, sans stopPropagation() « rejouer » déclencherait CE geste
        // au lieu de relancer l'animation.
        evt.stopPropagation();
        preview.startedAt = performance.now();
        start();
      };
      wrap.appendChild(again);
    }
  };
  return wrap;
}

function hint(text) {
  const node = document.createElement("span");
  node.className = "battle-inline-hint";
  node.textContent = text;
  return node;
}

function start() {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(tick);
}

function tick(now) {
  for (const preview of previews) {
    // La liste des unités est redessinée à chaque modification : les anciens
    // canevas sortent du document sans que personne ne prévienne.
    if (!preview.canvas.isConnected) {
      previews.delete(preview);
      continue;
    }
    draw(preview, now);
  }
  if (previews.size === 0) {
    ticking = false;
    return;
  }
  requestAnimationFrame(tick);
}

function draw(preview, now) {
  const elapsed = ((now - preview.startedAt) / 1000) * preview.fps;
  const step = preview.loop
    ? Math.floor(elapsed) % preview.count
    : Math.min(Math.floor(elapsed), preview.count - 1);
  if (step === preview.drawn) return;
  preview.drawn = step;

  const index = preview.first + step;
  const [cellW, cellH] = preview.cell;
  const context = preview.context;
  context.imageSmoothingEnabled = false;
  context.clearRect(0, 0, preview.canvas.width, preview.canvas.height);
  context.drawImage(
    preview.image,
    (index % preview.columns) * cellW,
    Math.floor(index / preview.columns) * cellH,
    cellW, cellH,
    0, 0, preview.canvas.width, preview.canvas.height
  );

  // L'ANCRAGE, en croix : c'est le point de la cellule qui se pose sur
  // l'emplacement au sol, et le voir dit tout de suite s'il tombe sous les
  // pieds du personnage ou à côté — l'erreur qui fait sauter un personnage
  // quand il change de planche.
  const x = preview.anchor[0] * preview.zoom;
  const y = preview.anchor[1] * preview.zoom;
  context.strokeStyle = "rgba(120, 200, 255, 0.9)";
  context.lineWidth = 1;
  context.beginPath();
  context.moveTo(x - 4, y + 0.5);
  context.lineTo(x + 4, y + 0.5);
  context.moveTo(x + 0.5, y - 4);
  context.lineTo(x + 0.5, y + 4);
  context.stroke();
}
