// Grille hexagonale flat-top, calquée EXACTEMENT sur la conversion coordonnées -> pixels
// du TileSet Godot (tile_shape=HEXAGON, tile_layout=5, tile_size=Vector2i(64,44)).
// Formule vérifiée en interrogeant directement TileMapLayer.map_to_local() dans Godot :
// ce n'est pas un simple décalage colonne/ligne, mais un système "diamant" où x ET y
// dépendent des deux coordonnées (a - b) et (a + b).
export const TILE_W = 64;
export const TILE_H = 44;

const HALF_W = TILE_W / 2; // 32
const HALF_H = TILE_H / 2; // 22
const STEP_Y = TILE_H * 0.75; // 33

export function cellToPixel(a, b) {
  return {
    x: HALF_W * (a - b + 1),
    y: STEP_Y * (a + b) + HALF_H,
  };
}

// Inverse exacte + arrondi "cube rounding" pour retomber sur la case hexagonale
// la plus proche (un simple arrondi indépendant de a et b peut violer la parité).
export function pixelToCell(px, py) {
  const d = px / HALF_W - 1; // = a - b (continu)
  const s = (py - HALF_H) / STEP_Y; // = a + b (continu)
  const aF = (s + d) / 2;
  const bF = (s - d) / 2;
  const cF = -aF - bF; // 3e coordonnée "cube" (a + b + c = 0)

  let ra = Math.round(aF);
  let rb = Math.round(bF);
  const rc = Math.round(cF);

  const da = Math.abs(ra - aF);
  const db = Math.abs(rb - bF);
  const dc = Math.abs(rc - cF);

  if (da > db && da > dc) ra = -rb - rc;
  else if (db > dc) rb = -ra - rc;

  return { col: ra, row: rb };
}
