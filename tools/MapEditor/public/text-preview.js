// Modal "Aperçu" pour un texte "ui" : vraie capture d'écran du jeu en fond
// (usage.preview_image), overlay DOM positionné/dimensionné par
// usage.node_rect à l'échelle de l'image affichée, texte rendu avec la
// police du jeu (@font-face, cf style.css) et le BBCode traduit en HTML
// restreint (cf bbcode.js). Fidélité assumée : valide position/taille/
// couleur/gras, pas un rendu pixel-identique — la vérité finale reste un
// screenshot in-game.
import { bbcodeToPreviewHtml } from "./bbcode.js";

const overlay = document.getElementById("text-preview-overlay");
const closeBtn = document.getElementById("text-preview-close");
const image = document.getElementById("text-preview-image");
const textEl = document.getElementById("text-preview-text");

export function openTextPreview(entry, bbcodeText) {
  const usage = entry.usage;
  if (!usage?.preview_image) return;

  image.src = `/localization-previews/${usage.preview_image}`;
  overlay.classList.remove("hidden");

  const render = () => {
    const [nodeX, nodeY, nodeW, nodeH] = usage.node_rect;
    const [viewportW, viewportH] = usage.viewport_size;
    const scale = image.clientWidth / viewportW;

    textEl.innerHTML = bbcodeToPreviewHtml(bbcodeText || "");
    textEl.style.fontSize = `${(entry.style?.font_size || 16) * scale}px`;

    // Le conteneur (HBoxContainer en jeu) est ancré à droite et grandit vers
    // la gauche selon la longueur du texte (cf commentaire dans
    // map_loader.gd au moment de la capture) : on ancre donc l'overlay par
    // son bord DROIT + centre vertical plutôt que par une largeur figée, qui
    // ne correspondrait qu'à la longueur du texte capturé au moment du screenshot.
    const rightEdge = (nodeX + nodeW) * scale;
    const centerY = (nodeY + nodeH / 2) * scale;
    textEl.style.right = `${image.clientWidth - rightEdge}px`;
    textEl.style.top = `${centerY}px`;
    textEl.style.transform = "translateY(-50%)";
  };

  if (image.complete) {
    render();
  } else {
    image.onload = render;
  }
  // Recalcule si l'utilisateur redimensionne la fenêtre pendant que la
  // preview est ouverte (l'image est en largeur fluide, cf style.css).
  window.addEventListener("resize", render);
  overlay._cleanupResize = () => window.removeEventListener("resize", render);
}

// Pas de fermeture au clic sur le fond : ce n'est plus un overlay bloquant
// (cf style.css) qui capte les clics en dehors de la modal elle-même.
closeBtn.onclick = closePreview;

function closePreview() {
  overlay.classList.add("hidden");
  overlay._cleanupResize?.();
}
