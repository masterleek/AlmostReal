import { getTiles } from "./api.js";

export const CELL = 64;

export async function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

// La palette est maintenant une liste ordonnée et curatée (Sprites/tile_meta.json),
// gérée depuis le gestionnaire de tuiles — plus une détection automatique des
// pixels non-transparents de la planche.
export async function buildPalette() {
  const [image, tiles] = await Promise.all([
    loadImage("/sprites/hex_tiles.png"),
    getTiles(),
  ]);
  return { image, tiles };
}

// Repère les cases 64x64 de l'atlas qui contiennent un pixel visible — utilisé
// par le sélecteur de région du gestionnaire de tuiles pour ne proposer que
// des cases réellement dessinées.
export function scanOccupiedCells(image) {
  const canvas = document.createElement("canvas");
  canvas.width = image.width;
  canvas.height = image.height;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(image, 0, 0);

  const cols = Math.floor(image.width / CELL);
  const rows = Math.floor(image.height / CELL);
  const cells = [];

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const { data } = ctx.getImageData(col * CELL, row * CELL, CELL, CELL);
      for (let i = 3; i < data.length; i += 4) {
        if (data[i] > 0) {
          cells.push([col, row]);
          break;
        }
      }
    }
  }

  return cells;
}
