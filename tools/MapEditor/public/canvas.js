import { cellToPixel, pixelToCell, TILE_W, TILE_H } from "./hexgrid.js";

const CELL = 64;
const PADDING = 16;

// Contour hexagonal "logique" d'une tuile (celui qui définit vraiment sa
// case, cf tile_size Vector2i(64,44) côté Godot) — pointe en haut/bas, côtés
// verticaux plats au milieu. Sert de zone de pose sûre pour les props (cf
// fixOverflowingProps côté app.js, qui utilise le même repère TILE_W/TILE_H).
// Distinct du rendu visuel du sprite (qui a un dégradé d'ombre donnant
// l'impression d'un bord plat vers le bas — un effet de lumière, pas la
// vraie forme de la case).
const HITZONE_POLY = [
  [TILE_W / 2, 0],
  [TILE_W, TILE_H * 0.25],
  [TILE_W, TILE_H * 0.75],
  [TILE_W / 2, TILE_H],
  [0, TILE_H * 0.75],
  [0, TILE_H * 0.25],
];

// Tuile révélée par défaut (Grass1) pour une case Empty sans cible assignée
// explicitement — doit rester synchronisée avec map_loader.gd (Godot).
const DEFAULT_REVEAL_ATLAS = [0, 0];

// Résolution cible du jeu : la mini-preview affiche toujours exactement ça,
// à l'échelle 1:1 (aucun zoom appliqué), comme le mini-éditeur d'Aseprite.
// Doit rester synchronisée avec ce que la Camera2D montre réellement dans
// Godot (fenêtre 1920x1080 / zoom caméra 4x = 480x270).
export const GAME_W = 480;
export const GAME_H = 270;

const MIN_ZOOM = 1;
const MAX_ZOOM = 20;
const DEFAULT_ZOOM = 3;

// Index de la frame courante d'une animation, dérivé de l'horloge globale :
// toutes les tuiles/props qui partagent le même fps restent synchronisés
// entre eux, sans avoir à stocker un temps de départ par instance.
export function currentFrameIndex(frames, fps) {
  if (!frames || frames.length <= 1) return 0;
  return Math.floor((Date.now() / 1000) * (fps || 4)) % frames.length;
}

export class MapCanvas {
  constructor(canvas, image, propImage, propsCanvas, frame, miniCanvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.image = image;
    this.propImage = propImage;
    this.propsCanvas = propsCanvas;
    this.propsCtx = propsCanvas.getContext("2d");
    this.map = null;
    this.offsetX = 0;
    this.offsetY = 0;

    this.frame = frame;
    this.mini = miniCanvas;
    this.miniCtx = miniCanvas.getContext("2d");
    this.zoom = DEFAULT_ZOOM;
    this.ghost = null; // { source_id, atlas, col, row } — nouvelle tuile prévisualisée sous le curseur (mode édition)
    this.dimCell = null; // { col, row } — tuile existante estompée à 50% sous le curseur (mode gomme)
    this.propGhost = null; // { rect, x, y } — nouveau prop prévisualisé sous le curseur (position libre)
    this.hitzoneHover = null; // { col, row } — contour de la zone de pose sûre, affiché en mode props
    this.selectedProp = null; // référence directe vers un élément de map.props
    this.dimProp = null; // référence vers un prop existant estompé à 50% sous le curseur (mode gomme)
    this.tileDefs = new Map(); // "x,y" (atlas) -> définition de tuile (pour résoudre les frames d'animation)
    // Aperçu révélé : montre chaque case Empty avec la tuile qu'elle deviendra
    // (reveal_atlas) au lieu de son apparence Empty, et les props qui lui sont
    // liés (reveal_cell) à pleine opacité — le rendu final que le joueur verra
    // une fois la case révélée, plutôt que l'état "en cours d'édition".
    this.revealPreview = false;

    this.frame.addEventListener("scroll", () => this.renderMini());
    this.applyZoom();
    this.startAnimationLoop();
  }

  // Nécessaire pour animer les tuiles posées : une cellule ne stocke que
  // l'atlas de sa frame 0, il faut la définition complète (frames + fps)
  // pour savoir quelle frame afficher à un instant donné.
  setTileDefs(tiles) {
    this.tileDefs = new Map(tiles.map((t) => [t.atlas.join(","), t]));
  }

  hasAnimatedContent() {
    if (!this.map) return false;
    for (const key in this.map.cells) {
      const def = this.tileDefs.get(this.map.cells[key].atlas.join(","));
      if (def?.frames?.length > 1) return true;
    }
    for (const prop of this.map.props || []) {
      if (prop.frames?.length > 1) return true;
    }
    return false;
  }

  // Boucle continue et légère (limitée à ~10 fps) qui ne redessine que s'il y
  // a au moins une tuile ou un prop animé visible sur la map courante.
  startAnimationLoop() {
    let lastTick = 0;
    const tick = (now) => {
      if (now - lastTick > 100 && this.map && this.hasAnimatedContent()) {
        lastTick = now;
        this.renderTiles();
        this.renderProps();
        this.renderMini();
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  setZoom(zoom) {
    this.zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, zoom));
    this.applyZoom();
    this.renderMini();
    return this.zoom;
  }

  // Ajuste le zoom pour que la preview (480px de large) occupe au mieux la
  // largeur disponible passée en paramètre. Arrondi à l'entier (comme les
  // crans +/- manuels) : un zoom fractionnaire casse le rendu net des props
  // (bords irréguliers), donc on sacrifie le remplissage exact au pixel près
  // pour garder un pixel-art propre partout.
  fitToWidth(availableWidth) {
    this.zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, Math.round(availableWidth / GAME_W)));
    this.applyZoom();
    this.renderMini();
    return this.zoom;
  }

  applyZoom() {
    this.canvas.style.transform = `scale(${this.zoom})`;
    this.frame.style.width = `${GAME_W * this.zoom}px`;
    this.frame.style.height = `${GAME_H * this.zoom}px`;
    // Le canvas des tuiles reste à sa résolution native, mis à l'échelle par
    // le navigateur via ce transform CSS + image-rendering: pixelated. Le
    // canvas des props, lui, est redessiné à sa résolution finale à chaque
    // changement de zoom (voir resizePropsCanvas + renderProps), en dessinant
    // chaque pixel source comme un bloc net (imageSmoothingEnabled = false) :
    // avec un zoom toujours entier, ça donne un pixel-art propre, sans
    // dépendre du comportement de mise à l'échelle CSS d'un navigateur à
    // l'autre.
    this.resizePropsCanvas();
    this.renderProps();
  }

  resizePropsCanvas() {
    if (!this.map) return;
    const w = this.map.width + PADDING * 2;
    const h = this.map.height + PADDING * 2;
    this.propsCanvas.width = Math.round(w * this.zoom);
    this.propsCanvas.height = Math.round(h * this.zoom);
  }

  setMap(map) {
    this.map = map;
    this.selectedProp = null;
    this.dimProp = null;
    this.resize();
    this.render();
  }

  clear() {
    this.map = null;
    this.selectedProp = null;
    this.dimProp = null;
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.propsCtx.clearRect(0, 0, this.propsCanvas.width, this.propsCanvas.height);
    this.miniCtx.clearRect(0, 0, this.mini.width, this.mini.height);
  }

  setGhost(ghost) {
    this.ghost = ghost;
    this.render();
  }

  setDimCell(cell) {
    this.dimCell = cell;
    this.render();
  }

  setPropGhost(ghost) {
    this.propGhost = ghost;
    this.render();
  }

  setHitzoneHover(cell) {
    this.hitzoneHover = cell;
    this.render();
  }

  // Contour de la zone de pose sûre d'une case (cf HITZONE_POLY) : un prop
  // entièrement dedans ne débordera jamais sur une case voisine.
  drawHitzone(x, y) {
    const { ctx } = this;
    ctx.save();
    ctx.beginPath();
    HITZONE_POLY.forEach(([px, py], i) => {
      const dx = x - TILE_W / 2 + px;
      const dy = y - TILE_H / 2 + py;
      if (i === 0) ctx.moveTo(dx, dy);
      else ctx.lineTo(dx, dy);
    });
    ctx.closePath();
    ctx.strokeStyle = "#ff5252";
    ctx.lineWidth = 1.5;
    ctx.setLineDash([3, 2]);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();
  }

  setSelectedProp(prop) {
    this.selectedProp = prop;
    this.render();
  }

  setDimProp(prop) {
    this.dimProp = prop;
    this.render();
  }

  setRevealPreview(value) {
    this.revealPreview = value;
    this.render();
  }

  // La largeur/hauteur de la map sont exprimées en pixels (résolution réelle du
  // jeu), pas en nombre de cases : le canvas fait donc simplement width x height,
  // avec un peu de marge pour ne pas rogner les tuiles qui débordent sur les bords.
  resize() {
    if (!this.map) return;
    this.offsetX = PADDING;
    this.offsetY = PADDING;
    this.canvas.width = this.map.width + PADDING * 2;
    this.canvas.height = this.map.height + PADDING * 2;
    this.resizePropsCanvas();
  }

  drawTile(x, y, tile, dimmed) {
    const { ctx } = this;
    const def = this.tileDefs.get(tile.atlas.join(","));
    // Aperçu révélé actif sur une case Empty : on dessine la tuile qu'elle
    // deviendra (reveal_atlas, ou Grass1 par défaut) à la place de son
    // apparence Empty — même valeur par défaut que get_reveal_target() côté
    // Godot (cf DEFAULT_REVEAL_ATLAS).
    const previewAtlas =
      this.revealPreview && def?.terrain_type === "empty1"
        ? tile.reveal_atlas || DEFAULT_REVEAL_ATLAS
        : null;
    const effectiveAtlas = previewAtlas || tile.atlas;
    const effectiveDef = previewAtlas
      ? this.tileDefs.get(previewAtlas.join(","))
      : def;
    const [ax, ay] =
      effectiveDef?.frames?.length > 1
        ? effectiveDef.frames[currentFrameIndex(effectiveDef.frames, effectiveDef.fps)]
        : effectiveAtlas;
    ctx.globalAlpha = dimmed ? 0.5 : 1;
    ctx.drawImage(
      this.image,
      ax * CELL,
      ay * CELL,
      CELL,
      CELL,
      x - CELL / 2,
      y - CELL / 2,
      CELL,
      CELL
    );
    ctx.globalAlpha = 1;
  }

  // Petite vignette centrée sur une case "Empty" montrant quelle tuile elle
  // révélera au joueur.
  drawRevealBadge(x, y, tile) {
    const { ctx } = this;
    const revealAtlas = tile.reveal_atlas || DEFAULT_REVEAL_ATLAS;
    const size = 22;
    const bx = x - size / 2;
    const by = y - size / 2;
    ctx.globalAlpha = 0.9;
    ctx.drawImage(
      this.image,
      revealAtlas[0] * CELL,
      revealAtlas[1] * CELL,
      CELL,
      CELL,
      bx,
      by,
      size,
      size
    );
    ctx.globalAlpha = 1;
  }

  // Dessine un prop directement à sa taille finale à l'écran (zoom entier) :
  // chaque pixel source est agrandi en bloc carré net (imageSmoothingEnabled
  // = false dans renderProps), plutôt que de compter sur le navigateur pour
  // mettre à l'échelle un canvas via CSS ensuite.
  drawProp(ctx, prop, opts = {}) {
    const frames = prop.frames?.length ? prop.frames : [prop.rect];
    const [rx, ry, rw, rh] = frames[currentFrameIndex(frames, prop.fps)];
    const z = this.zoom;
    const dx = (this.offsetX + prop.x - rw / 2) * z;
    const dy = (this.offsetY + prop.y - rh / 2) * z;
    const dw = rw * z;
    const dh = rh * z;
    ctx.globalAlpha = opts.alpha ?? 1;
    ctx.drawImage(this.propImage, rx, ry, rw, rh, dx, dy, dw, dh);
    ctx.globalAlpha = 1;
    if (opts.selected) {
      ctx.strokeStyle = "#7bc67e";
      ctx.lineWidth = 1;
      ctx.strokeRect(dx - 1, dy - 1, dw + 2, dh + 2);
    }
  }

  render() {
    if (!this.map) return;
    this.renderTiles();
    this.renderProps();
    this.renderMini();
  }

  // Tuiles en pixel-art net (image-rendering: pixelated sur #map-canvas).
  renderTiles() {
    const { ctx, canvas } = this;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.save();
    ctx.translate(this.offsetX, this.offsetY);

    // Y-sort : on dessine du fond vers l'avant (même règle que y_sort_enabled
    // côté Godot) pour que les falaises qui débordent sous une case se
    // superposent dans le bon ordre avec les cases situées devant elles.
    const ordered = Object.entries(this.map.cells)
      .map(([key, tile]) => {
        const [a, b] = key.split(",").map(Number);
        return { ...cellToPixel(a, b), col: a, row: b, tile };
      })
      .sort((p, q) => p.y - q.y);

    for (const { x, y, col, row, tile } of ordered) {
      const dimmed = this.dimCell && this.dimCell.col === col && this.dimCell.row === row;
      this.drawTile(x, y, tile, dimmed);
    }

    // Vignettes de révélation par-dessus tout le reste (sinon une case Empty
    // dessinée après pourrait recouvrir la vignette d'une case voisine).
    // Inutiles en aperçu révélé : la case montre déjà directement sa tuile
    // finale, plus besoin de l'indiquer.
    if (!this.revealPreview) {
      for (const { x, y, tile } of ordered) {
        const def = this.tileDefs.get(tile.atlas.join(","));
        if (def?.terrain_type === "empty1") this.drawRevealBadge(x, y, tile);
      }
    }

    // Aperçu de la tuile sélectionnée sous le curseur, à 50% d'opacité,
    // toujours dessiné par-dessus le reste pour rester visible.
    if (this.ghost) {
      const { x, y } = cellToPixel(this.ghost.col, this.ghost.row);
      this.drawTile(x, y, this.ghost, true);
    }

    if (this.hitzoneHover) {
      const { x, y } = cellToPixel(this.hitzoneHover.col, this.hitzoneHover.row);
      this.drawHitzone(x, y);
    }

    ctx.restore();
  }

  // Props sur un canvas séparé, redessiné à la résolution finale (zoom
  // compris) à chaque rendu ou changement de zoom : un lissage fiable et net
  // partout, indépendant du pixel-art des tuiles. Toujours au-dessus des
  // tuiles (comme TileMapLayer.z_index = -1 côté Godot) ; triées entre elles
  // par z_index puis Y.
  renderProps() {
    if (!this.map) return;
    const { propsCtx: ctx, propsCanvas } = this;
    ctx.clearRect(0, 0, propsCanvas.width, propsCanvas.height);
    // Rendu net façon pixel-art (comme les tuiles), pas lissé : avec un zoom
    // toujours entier (voir setZoom/fitToWidth), chaque pixel source devient
    // un bloc carré propre, sans bords irréguliers ni flou.
    ctx.imageSmoothingEnabled = false;

    const ordered = (this.map.props || [])
      .slice()
      .sort((a, b) => (a.z_index || 0) - (b.z_index || 0) || a.y - b.y);

    for (const prop of ordered) {
      // Lié à une case Empty (reveal_cell) : caché en jeu tant qu'elle n'est
      // pas révélée, donc pas la peine de l'afficher hors aperçu révélé — il
      // ne fait que brouiller la lecture de l'état "en cours d'édition".
      if (prop.reveal_cell && !this.revealPreview) continue;
      this.drawProp(ctx, prop, {
        selected: this.selectedProp === prop,
        alpha: this.dimProp === prop ? 0.5 : 1,
      });
    }

    if (this.propGhost) {
      this.drawProp(ctx, this.propGhost, { alpha: 0.5 });
    }
  }

  // Toujours la taille réelle (480x270, zoom x1) de la zone actuellement visible
  // dans la preview zoomée — permet de vérifier le rendu final sans le zoom.
  renderMini() {
    const { miniCtx, mini, canvas, propsCanvas, frame, zoom } = this;
    miniCtx.clearRect(0, 0, mini.width, mini.height);
    if (!this.map) return;
    const sx = frame.scrollLeft / zoom;
    const sy = frame.scrollTop / zoom;
    miniCtx.drawImage(canvas, sx, sy, GAME_W, GAME_H, 0, 0, GAME_W, GAME_H);
    // propsCanvas est stocké à la résolution finale (zoom compris) : le
    // ramener à la taille réelle est donc une réduction, pas une copie 1:1.
    // Sans désactiver le lissage ici, le navigateur moyenne les pixels en
    // rétrécissant et les props ressortent flous dans la mini-preview alors
    // qu'ils sont nets dans la preview principale.
    miniCtx.imageSmoothingEnabled = false;
    miniCtx.drawImage(
      propsCanvas,
      sx * zoom,
      sy * zoom,
      GAME_W * zoom,
      GAME_H * zoom,
      0,
      0,
      GAME_W,
      GAME_H
    );
  }

  cellAt(evt) {
    const { x, y } = this.pixelAt(evt);
    return pixelToCell(x, y);
  }

  // Position brute (non alignée sur la grille hexagonale), pour le placement
  // libre des props.
  pixelAt(evt) {
    const rect = this.canvas.getBoundingClientRect();
    const x = (evt.clientX - rect.left) / this.zoom - this.offsetX;
    const y = (evt.clientY - rect.top) / this.zoom - this.offsetY;
    return { x, y };
  }

  // Trouve le prop le plus proche du dessus (dernier dans l'ordre de dessin,
  // donc même règle z_index puis Y) dont la boîte englobante contient (x, y).
  propAt(x, y) {
    const props = this.map?.props || [];
    const ordered = props
      .slice()
      .sort((a, b) => (a.z_index || 0) - (b.z_index || 0) || a.y - b.y);

    for (let i = ordered.length - 1; i >= 0; i--) {
      const prop = ordered[i];
      const [, , rw, rh] = prop.rect;
      if (
        x >= prop.x - rw / 2 &&
        x <= prop.x + rw / 2 &&
        y >= prop.y - rh / 2 &&
        y <= prop.y + rh / 2
      ) {
        return prop;
      }
    }
    return null;
  }
}
