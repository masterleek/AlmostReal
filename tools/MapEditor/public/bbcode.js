// Logique BBCode isolée du DOM : la textarea de chaque langue affiche le
// BBCode brut (pas de WYSIWYG contenteditable — évite les bugs de
// synchronisation rich-text<->BBCode), ces fonctions manipulent juste des
// chaînes/positions de curseur. Le sous-ensemble supporté est volontairement
// restreint à ce que la barre d'outils produit ([b], [color=#hex]) : Godot
// (RichTextLabel côté jeu) accepte bien plus de BBCode, mais rien d'autre
// n'est éditable depuis cette page pour l'instant.

// Enveloppe la sélection courante de `textarea` avec `openTag`/`closeTag`
// (ex. "[b]"/"[/b]"). Si rien n'est sélectionné, enveloppe un texte
// d'exemple pour que l'utilisateur voie immédiatement l'effet plutôt que de
// devoir deviner la syntaxe. Renvoie la nouvelle valeur (l'appelant est
// responsable de l'assigner à `textarea.value` et de redéclencher un événement
// "input" — gardé séparé du DOM pour rester testable).
export function wrapSelection(textarea, openTag, closeTag, placeholder = "texte") {
  const { value, selectionStart, selectionEnd } = textarea;
  const hasSelection = selectionEnd > selectionStart;
  const selected = hasSelection ? value.slice(selectionStart, selectionEnd) : placeholder;
  const before = value.slice(0, selectionStart);
  const after = value.slice(selectionEnd);
  const inserted = `${openTag}${selected}${closeTag}`;
  return {
    value: before + inserted + after,
    // Sélectionne le texte enveloppé (pas les balises) après coup, pour
    // pouvoir enchaîner un second style (ex. gras puis couleur) sans avoir à
    // re-sélectionner à la main.
    selectionStart: before.length + openTag.length,
    selectionEnd: before.length + openTag.length + selected.length,
  };
}

export function wrapSelectionBold(textarea) {
  return wrapSelection(textarea, "[b]", "[/b]");
}

export function wrapSelectionColor(textarea, hexColor) {
  return wrapSelection(textarea, `[color=${hexColor}]`, "[/color]");
}

// Retire UNE couche de [b]/[color=...] directement autour de la sélection
// (pas un nettoyage récursif profond) : couvre le cas d'usage principal
// "j'ai stylé par erreur, j'annule", pas un vrai désimbrication générale.
export function clearSelectionFormatting(textarea) {
  const { value, selectionStart, selectionEnd } = textarea;
  if (selectionEnd <= selectionStart) {
    return { value, selectionStart, selectionEnd };
  }
  let selected = value.slice(selectionStart, selectionEnd);
  selected = selected
    .replace(/^\[b\]([\s\S]*)\[\/b\]$/, "$1")
    .replace(/^\[color=[^\]]+\]([\s\S]*)\[\/color\]$/, "$1");
  const before = value.slice(0, selectionStart);
  const after = value.slice(selectionEnd);
  return {
    value: before + selected + after,
    selectionStart: before.length,
    selectionEnd: before.length + selected.length,
  };
}

// Convertit le sous-ensemble de BBCode produit par la barre d'outils en HTML
// pour la preview live — PAS un parseur BBCode général (pas d'imbrication
// arbitraire au-delà de [b] contenant du [color], balises inconnues laissées
// telles quelles plutôt que de planter). La vérité finale reste le
// screenshot in-game, cette conversion sert juste à valider position/taille/
// couleur/gras pendant l'édition.
export function bbcodeToPreviewHtml(bbcode) {
  const escaped = String(bbcode)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  return escaped
    .replace(/\[color=(#[0-9a-fA-F]{3,8})\]([\s\S]*?)\[\/color\]/g, '<span style="color:$1">$2</span>')
    .replace(/\[b\]([\s\S]*?)\[\/b\]/g, "<b>$1</b>");
}
