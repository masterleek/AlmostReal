// Icônes SVG partagées entre les pages de l'éditeur — un seul endroit pour ce
// qui se répétait, presque identique, dans battle.js/maps.js/props.js/
// tiles.js/texts.js.

// Croix blanche : `stroke="currentColor"`, la couleur vient du CSS du bouton
// qui la porte (cf. .icon-delete-btn, .battle-anim-delete), pas d'elle-même —
// deux tailles de médaillon cohabitent dans l'éditeur (26px posé dans une
// ligne, 18px en médaillon flottant sur une vignette), c'est au bouton de le
// dire.
export const DELETE_ICON =
  '<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor" '
  + 'stroke-width="3" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg>';
