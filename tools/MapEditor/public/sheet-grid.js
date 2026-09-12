// Relevé de la grille d'une planche, SUR L'IMAGE.
//
// POURQUOI MESURER ET NON DIVISER. Une grille ne se devine pas : « 315 de large
// pour trois personnages » n'a rien d'évident quand on ne sait pas combien il y
// en a. Ce qui se relève, en revanche, ce sont les GOUTTIÈRES — les colonnes et
// les lignes entièrement transparentes qui séparent les vignettes. Un découpage
// n'est retenu que si TOUTES ses frontières y tombent (cf. CLAUDE.md, où cette
// méthode a été posée en mesurant les planches à la main).
//
// VALIDÉE AVANT D'ÊTRE UTILISÉE, sur les douze planches déjà déclarées dans
// units.json : elle les redonne toutes au pixel. Le seul écart est
// `iris/atk`, dont le fichier annonce 3 × 9 alors que l'image ne porte que
// quatre bandes de lignes — c'est la DÉCLARATION qui est fausse, pas le relevé
// (392 ÷ 9 ne tombe même pas juste).

// Au-delà, on ne découpe plus une planche de combat : la plus fine du projet
// fait 12 lignes. La borne évite surtout de tester des découpages absurdes sur
// une image de 1017 px de large.
const MAX_SPLIT = 64;

// Encre en-deçà de laquelle une colonne (ou une ligne) compte quand même comme
// une GOUTTIÈRE. Zéro serait le bon seuil si les planches étaient propres : sur
// `iris_attack`, UN pixel isolé déborde une colonne à gauche de la coupe, et ce
// seul pixel faisait rendre 1 colonne au lieu de 3. Un pixel n'est pas un
// dessin.
const GUTTER_INK = 1;

// Opacité en-dessous de laquelle un pixel noir n'est pas pris pour de l'ombre.
//
// LE CANEVAS MENT SUR LES PIXELS PRESQUE TRANSPARENTS. Il stocke les couleurs
// pré-multipliées par l'alpha : à alpha 1/255 la couleur est écrasée à zéro et
// ne revient pas. Le halo de la lueur de tir d'`iris_attack` (orangé, alpha 1 à
// 48) ressort donc du canevas en NOIR PUR, et sans plancher il double la tache
// détectée — l'abscisse relevée passait de 51,5 à 36, soit 15 px d'erreur.
//
// Le seuil n'est pas délicat : de 32 à 128, les onze planches déclarées rendent
// toutes exactement le même point. 64 est le milieu confortable — l'ombre de ce
// projet porte 166 au cœur.
const SHADOW_ALPHA = 64;

// Rend {columns, rows, frames} ou null si l'image ne se lit pas.
//
// `frames` est le nombre de vignettes RÉELLEMENT dessinées : la dernière ligne
// d'une planche est souvent incomplète (noah_atkeff : 21 cases, 20 dessins), et
// laisser l'animation jouer les cases vides ferait clignoter le personnage.
export async function measureGrid(url) {
  const pixels = await pixelsOf(url);
  if (pixels === null) return null;
  const { data, width, height } = pixels;
  const columns = split(emptyColumns(data, width, height), width);
  const rows = split(emptyRows(data, width, height), height);
  return { columns, rows, frames: drawnFrames(data, width, height, columns, rows) };
}

// Le point au SOL d'une vignette — abscisse du milieu de l'ombre et sa ligne la
// plus basse, en coordonnées de CELLULE. C'est la matière première de
// l'ancrage : cf. battle.js, qui en tire l'écart à la planche de repos.
//
// L'OMBRE SE RECONNAÎT À SA COULEUR : du noir PUR et partiellement transparent.
// Aucun autre pixel des planches du projet n'est les deux à la fois — le
// contour des personnages est noir, mais opaque. Relevé sur les douze planches
// déjà déclarées : chacune rend une tache large et basse, jamais autre chose.
//
// Rend null si rien ne ressemble à une ombre — l'appelant retombe alors sur le
// défaut du moteur, c'est-à-dire sur ce qui se passait avant ce relevé.
export async function measureGround(url, columns, rows, frame = 0) {
  const pixels = await pixelsOf(url);
  if (pixels === null) return null;
  const { data, width, height } = pixels;
  const cellW = Math.floor(width / Math.max(1, columns));
  const cellH = Math.floor(height / Math.max(1, rows));
  const x0 = (frame % columns) * cellW;
  const y0 = Math.floor(frame / columns) * cellH;
  let left = cellW;
  let right = -1;
  let top = cellH;
  let bottom = -1;
  for (let y = 0; y < cellH; y += 1) {
    const row = (y0 + y) * width;
    for (let x = 0; x < cellW; x += 1) {
      const i = (row + x0 + x) * 4;
      const a = data[i + 3];
      if (a < SHADOW_ALPHA || a === 255) continue;
      if (data[i] !== 0 || data[i + 1] !== 0 || data[i + 2] !== 0) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  if (right < 0) return null;
  // Une ombre est POSÉE AU SOL : son milieu tombe dans la moitié basse de la
  // cellule. Le garde-fou écarte une fumée ou un voile noir translucide dessiné
  // à hauteur d'épaule, qui passerait autrement pour le point d'appui.
  if ((top + bottom) / 2 < cellH / 2) return null;
  return { x: (left + right) / 2, bottom };
}

async function pixelsOf(url) {
  const image = await new Promise((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = url;
  });
  if (image === null) return null;
  const canvas = document.createElement("canvas");
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  context.drawImage(image, 0, 0);
  let data;
  try {
    data = context.getImageData(0, 0, canvas.width, canvas.height).data;
  } catch {
    // Canevas « teinté » par une image d'une autre origine. Ne peut pas arriver
    // ici (tout est servi par le même serveur), mais une lecture d'image qui
    // lève ne doit pas emporter l'import avec elle.
    return null;
  }
  return { data, width: canvas.width, height: canvas.height };
}

function emptyColumns(data, width, height) {
  const ink = new Uint32Array(width);
  for (let y = 0; y < height; y += 1) {
    const row = y * width;
    for (let x = 0; x < width; x += 1) if (data[(row + x) * 4 + 3] !== 0) ink[x] += 1;
  }
  return ink.map((n) => (n <= GUTTER_INK ? 1 : 0));
}

function emptyRows(data, width, height) {
  const ink = new Uint32Array(height);
  for (let y = 0; y < height; y += 1) {
    const row = y * width;
    for (let x = 0; x < width; x += 1) if (data[(row + x) * 4 + 3] !== 0) ink[y] += 1;
  }
  return ink.map((n) => (n <= GUTTER_INK ? 1 : 0));
}

function split(empty, size) {
  // Le moteur découpe en DIVISION ENTIÈRE (cf. UnitSprite.build_frames) : un
  // découpage qui ne tombe pas juste décale toutes les vignettes après la
  // première ligne. On ne propose donc que des diviseurs.
  const valid = [];
  for (let c = 1; c <= Math.min(size, MAX_SPLIT); c += 1) {
    if (size % c !== 0) continue;
    const step = size / c;
    let ok = true;
    // IL SUFFIT QU'UN CÔTÉ SOIT VIDE : ce qu'on interdit à une coupe, c'est de
    // TRANCHER une bande dessinée, pas de toucher un dessin. L'exiger des deux
    // côtés réclamait une gouttière de 2 px à cheval sur la coupe, et rejetait
    // les planches dont le dessin descend jusqu'au bord de sa cellule — sur
    // `iris_attack`, les étincelles du coup de pied.
    for (let k = 1; k < c && ok; k += 1) ok = !!empty[k * step - 1] || !!empty[k * step];
    if (ok) valid.push(c);
  }
  if (valid.length === 0) return 1;
  // Départager par ce que l'œil compte : le nombre de PLAGES DESSINÉES. À
  // égalité on prend le plus PETIT découpage — sur-découper coupe une vignette
  // en deux, alors qu'une cellule large est normale (le familier d'Iris traverse
  // son cadre sur `win_before` : 339 px pour un personnage de 70).
  const drawn = bandCount(empty);
  return valid.reduce((best, c) =>
    Math.abs(c - drawn) < Math.abs(best - drawn) ? c : best, valid[0]);
}

function bandCount(empty) {
  let count = 0;
  let inside = false;
  for (const value of empty) {
    if (!value && !inside) { count += 1; inside = true; }
    else if (value) inside = false;
  }
  return count;
}

// Nombre de vignettes jusqu'à la dernière qui porte quelque chose. On ne compte
// pas les cases vides INTERMÉDIAIRES comme une fin : une planche peut avoir une
// pose entièrement transparente au milieu (un clignotement), et s'arrêter là
// amputerait l'animation.
function drawnFrames(data, width, height, columns, rows) {
  const cellW = Math.floor(width / columns);
  const cellH = Math.floor(height / rows);
  let last = -1;
  for (let index = 0; index < columns * rows; index += 1) {
    const x0 = (index % columns) * cellW;
    const y0 = Math.floor(index / columns) * cellH;
    if (hasInk(data, width, x0, y0, cellW, cellH)) last = index;
  }
  return Math.max(1, last + 1);
}

function hasInk(data, width, x0, y0, w, h) {
  for (let y = y0; y < y0 + h; y += 1) {
    const row = y * width;
    for (let x = x0; x < x0 + w; x += 1) if (data[(row + x) * 4 + 3] !== 0) return true;
  }
  return false;
}
