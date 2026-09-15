import {
  getBattleCatalog,
  saveBattleCatalog,
  battleCatalogChanged,
  CatalogConflictError,
  getBattleSounds,
  getBattleVocabulary,
  getBattleSheets,
  uploadBattleSheet,
  uploadBattleSound,
  getBattleMomentLabels,
  saveBattleMomentLabels,
  getTexts,
  saveTexts,
} from "./api.js";
import { pickFrames } from "./frame-picker.js";
import { animationPreview, forgetSheetSize, sheetSize, staticFrame } from "./sheet-preview.js";
import { forgetSheetPixels, measureGrid, measureGround } from "./sheet-grid.js";
import { judgementWindows, rhythmPreview, sequenceTiming } from "./rhythm-preview.js";

// Page « Combat » : les trois catalogues de Battle/ (unités, Ekos, objets).
//
// UNE SEULE PAGE ET PAS TROIS, parce que les catalogues se renvoient l'un à
// l'autre — une unité connaît des Ekos, un comportement ennemi nomme une unité,
// une action nomme une planche déclarée chez l'unité. Les éditer dans trois
// onglets séparés obligerait à jongler, et surtout empêcherait de proposer les
// listes déroulantes qui suppriment la saisie d'un identifiant à la main.
//
// AUCUN LIBELLÉ NE VIT DANS CES FICHIERS : les noms et descriptions sont des
// ids `Localization` (`eko.<id>.name`). Ils sont donc affichés ici en lecture
// seule, résolus depuis le catalogue de textes — ouvrir une deuxième porte
// d'écriture sur le même texte serait le meilleur moyen de les désynchroniser.

const listEl = document.getElementById("battle-list");
const hintEl = document.getElementById("battle-hint");
const tabsEl = document.getElementById("battle-section-tabs");

// Chaque section connaît son fichier, la clé du dictionnaire qu'il contient, et
// le préfixe des ids Localization qui lui donnent ses libellés.
const SECTIONS = {
  units: { container: "units", textPrefix: "unit", singular: "unité" },
  ekos: { container: "ekos", textPrefix: "eko", singular: "Eko" },
  items: { container: "items", textPrefix: "item", singular: "objet" },
};

// La section « Sons » n'est pas un catalogue : elle n'a ni conteneur, ni ids
// Localization, ni bouton « Ajouter » — la liste des moments appartient au
// moteur. Elle vit donc à part de SECTIONS plutôt que d'y entrer avec des
// champs vides à tester partout.
const SOUNDS_SECTION = "sounds";

const ID_PATTERN = /^[a-z0-9_]+$/;

let catalogs = { units: null, ekos: null, items: null };
let texts = { texts: [], default_language: "en" };
let sounds = [];
let sheetFiles = [];
// États d'animation que le moteur va chercher par leur nom (lus dans le .gd).
let animationStates = [];
let actionAnimationDefault = "atk";
// État du personnage sur lequel retombe la pose tenue pendant la séquence de
// rythme, quand l'action n'en nomme pas (cf. BattleAssault.ANIM_RHYTHM).
let rhythmAnimationDefault = "rhythm";
let momentLabels = { labels: {} };
let vocabulary = {
  moments: [],
  moment_notes: {},
  unit_moments: [],
  unit_moment_notes: {},
  notes: [],
  // Le dessin de chaque note et les vitesses de la barre, lus dans
  // RhythmBar.gd. Les replis valent ce que le fichier disait le jour où ceci a
  // été écrit ; le serveur envoie les vrais dès qu'il sait les lire.
  note_icons: {},
  rhythm: {
    note_speed: 170, note_interval: 0.55, tail: 0.45, centre_x: 239.5,
    window_perfect: 5, window_great: 21, window_good: 32,
  },
  targets: [],
  ranges: [],
  damage_types: [],
  behaviours: [],
  parsed: {},
};
let activeSection = "units";
// Entrée ouverte dans le panneau de droite, par section. La page est un
// MAÎTRE/DÉTAIL : tout déplier d'un coup donnait une colonne de plusieurs
// milliers de pixels (trois unités × six planches × une quarantaine de champs),
// où l'on ne retrouvait ni ce qu'on cherchait ni ce qu'on venait de changer.
const selection = { units: null, ekos: null, items: null };
// Planches dépliées, par « section:unité:planche ». Hors du DOM parce que la
// liste est reconstruite à chaque modification.
const openSheets = new Set();

function entriesOf(section) {
  return catalogs[section]?.[SECTIONS[section].container] || {};
}

// Un conflit n'est PAS rattrapable ici : la page tient tout le catalogue en
// mémoire, il n'y a rien à fusionner. Il est déjà annoncé par api.js — la seule
// couche traversée par les sauvegardes des cinq pages — et on l'avale ici pour
// qu'il ne parte pas en promesse rejetée. Surtout pas un second `alert` : deux
// fenêtres pour un seul refus se lisent comme deux problèmes.
async function persist(section) {
  try {
    await saveBattleCatalog(section, catalogs[section]);
  } catch (err) {
    if (!(err instanceof CatalogConflictError)) throw err;
  }
}

// Un changement quelconque redessine la liste ET enregistre : les entrées
// s'influencent (cocher un Eko ajoute une case ailleurs, changer le moment d'un
// son le déplace de liste), et redessiner seulement le champ touché laisserait
// le reste mentir.
//
// `extra` nomme les catalogues touchés EN PLUS de celui qu'on parcourt. Le
// geste d'une action vit dans le bloc `animations` de chaque personnage : la
// page Ekos écrit donc aussi dans units.json — mais seulement depuis les
// commandes qui y touchent, pour ne pas renvoyer tout le catalogue des unités à
// chaque frappe dans un champ d'Eko.
function refresher(...extra) {
  const sections = [...new Set([activeSection, ...extra])];
  return async () => {
    renderList();
    for (const section of sections) await persist(section);
  };
}

// ──────────────────────────────────────────────────────────────────────────
//  Briques de formulaire
// ──────────────────────────────────────────────────────────────────────────

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

// Un champ que le moteur NE LIRA PAS dans l'état courant de l'action. Estompé
// et non désactivé : sa valeur reste visible et modifiable — elle redeviendra
// vivante si l'action change de nature — mais l'œil voit qu'elle ne compte pas.
function markIgnored(node, why) {
  node.classList.add("battle-field-ignored");
  node.title = why;
  const mark = el("span", "battle-field-ignored-mark", "ignoré");
  mark.title = why;
  node.appendChild(mark);
  return node;
}

function sectionTitle(text, note) {
  const head = el("div", "battle-section-head");
  head.appendChild(el("h4", "battle-section-title", text));
  if (note) head.appendChild(el("span", "battle-inline-hint", note));
  return head;
}

function field(labelText, control, title) {
  const label = el("label", "battle-field");
  label.appendChild(el("span", "battle-field-label", labelText));
  label.appendChild(control);
  if (title) label.title = title;
  return label;
}

// `optional` retire la clé quand la valeur retombe à 0, au lieu d'écrire un
// `heal: 0` ou un `power: 0` là où le catalogue n'avait rien. Le moteur lit ces
// champs avec un défaut (`get(…, 0)`), donc absent et 0 disent la même chose —
// mais les écrire ferait gonfler chaque entrée de champs que personne n'a
// demandés, à la première visite de la page. À NE PAS mettre sur un champ dont
// le défaut n'est pas 0 : `guard_below` vaut 0,35 par défaut, y effacer un 0
// changerait « ne se garde jamais » en « se garde sous 35 % ».
function objectNumberField(target, key, labelText, options = {}) {
  const { optional = false, title = null, ...inputOptions } = options;
  const control = numberInput(target[key] ?? 0, (value) => {
    if (optional && !value) delete target[key];
    else target[key] = value;
    options.onCommit();
  }, inputOptions);
  return field(labelText, control, title);
}

function numberInput(value, onCommit, { min = null, step = 1 } = {}) {
  const input = el("input", "battle-input");
  input.type = "number";
  input.step = String(step);
  if (min !== null) input.min = String(min);
  input.value = value ?? 0;
  input.onchange = () => onCommit(step < 1 ? parseFloat(input.value) : parseInt(input.value, 10));
  return input;
}

// Champ texte d'une ligne. `onchange` et non `oninput` : on valide en sortant du
// champ, comme les nombres — écrire à chaque frappe redessinerait la page (donc
// perdrait le focus) et sauvegarderait une fois par lettre.
function textInput(value, onCommit, { placeholder = "" } = {}) {
  const input = el("input", "battle-input");
  input.type = "text";
  input.value = value ?? "";
  if (placeholder) input.placeholder = placeholder;
  input.onchange = () => onCommit(input.value.trim());
  return input;
}

function checkboxInput(checked, onCommit) {
  const box = el("input", "battle-check-input");
  box.type = "checkbox";
  box.checked = checked;
  box.onchange = () => onCommit(box.checked);
  return box;
}

// `empty` ajoute une entrée vide en tête : un champ FACULTATIF (un soin sur un
// objet, une planche sur un Eko) doit pouvoir être remis à « rien », sinon la
// première ouverture de la page écrit une valeur dans chaque entrée du
// catalogue et le fichier gonfle de champs que personne n'a demandés.
//
// `labelOf` et `titleOf` séparent la VALEUR de ce qui s'affiche : les moments de
// son s'écrivent `hit` dans le JSON — c'est le vocabulaire du moteur — mais
// l'auteur les a renommés pour lui, et chacun porte l'explication de ce qui le
// déclenche. La valeur écrite ne change jamais, quel que soit l'habillage.
function selectInput(
  values, current, onCommit,
  { empty = null, labelOf = null, titleOf = null, groups = null } = {}
) {
  const select = el("select", "battle-input");
  if (empty !== null) {
    const option = el("option", null, empty);
    option.value = "";
    select.appendChild(option);
  }
  const addOption = (parent, value) => {
    const option = el("option", null, labelOf ? labelOf(value) : value);
    option.value = value;
    if (titleOf) option.title = titleOf(value) || "";
    parent.appendChild(option);
  };
  // `groups` range les entrées sous des intertitres. Une liste qui mélange deux
  // familles doit dire laquelle est laquelle : les libellés seuls
  // (« Impact », « Encaisse ») ne disent pas lequel s'applique à quoi.
  if (groups) {
    for (const group of groups) {
      const holder = document.createElement("optgroup");
      holder.label = group.label;
      for (const value of group.values) addOption(holder, value);
      select.appendChild(holder);
    }
  } else {
    for (const value of values) addOption(select, value);
  }
  select.value = current ?? "";
  // L'infobulle du `select` suit la sélection : une infobulle posée sur les
  // `option` seules ne se voit que liste dépliée, c'est-à-dire jamais quand on
  // relit une fiche.
  const syncTitle = () => {
    if (titleOf) select.title = titleOf(select.value) || "";
  };
  syncTitle();
  select.onchange = () => {
    syncTitle();
    onCommit(select.value);
  };
  return select;
}

// ──────────────────────────────────────────────────────────────────────────
//  Moments de son
// ──────────────────────────────────────────────────────────────────────────

// Le moteur ne connaît que les CLÉS (`hit`, `gesture`…) : ce sont elles qui
// s'écrivent dans les catalogues. Les libellés ne servent qu'ici, et une clé
// sans libellé s'affiche telle quelle — supprimer le fichier de libellés ne
// rend donc pas la page inutilisable.
function momentLabel(key) {
  return momentLabels.labels?.[key] || key;
}

// Le mode de ciblage en clair. Les clés du moteur (`enemy`, `enemies`, `ally`,
// `allies`, `self`) se ressemblent trop pour se relire d'un coup d'œil — et le
// piège n'est pas le pluriel, c'est que le mode se lit RELATIVEMENT à celui qui
// lance : « ally » désigne son propre camp, y compris quand c'est un ennemi qui
// s'en sert. Les libellés le disent.
function targetLabel(key) {
  return momentLabels.target_labels?.[key] || key;
}

// La portée en clair. « melee » et « ranged » disent ce que l'action EST ; le
// libellé dit ce qu'on VERRA, qui est la seule chose à comparer quand on hésite.
function rangeLabel(key) {
  return momentLabels.range_labels?.[key] || key;
}

// LECTURE EN CLAIR D'UNE ACTION, en une ligne : ce qu'elle coûte, ce qu'elle
// fait, sur qui, et si elle fait jouer la barre. Sert à deux endroits — l'index,
// où elle évite d'ouvrir six fiches pour retrouver « le soin de groupe », et le
// haut de la fiche, où elle relit les champs qu'on vient de régler.
//
// Elle suit les règles du moteur, pas les champs : un `heal` positif rend
// l'action non offensive (cf. BattleAssault._effect_of), sa puissance et sa
// nature de dégâts ne servent alors plus à rien — la ligne dit « soigne », pas
// « soigne et frappe ».
function actionSummary(section, action) {
  const parts = [];
  if (section === "ekos") {
    const cost = Number(action.ap_cost || 0);
    parts.push(cost > 0 ? `${cost} PA` : "gratuit");
  }
  const heal = Number(action.heal || 0);
  if (heal > 0) {
    parts.push(`soigne ${heal}`);
  } else {
    const power = Number(action.power || 0);
    const nature = action.damage_type || "direct";
    parts.push(power > 0 ? `${power} ${nature}` : `sans puissance (${nature})`);
  }
  parts.push(targetLabel(action.target || "enemy"));
  // La portée ne se dit que quand elle sort de l'ordinaire : toute action allait
  // au contact avant ce champ, et l'écrire partout noierait la seule qui compte.
  if (heal <= 0 && action.range === "ranged") parts.push("à distance");
  const notes = (action.sequence || []).length;
  parts.push(notes > 0 ? `${notes} note${notes > 1 ? "s" : ""}` : "sans séquence");
  return parts.join(" · ");
}

// L'explication, elle, vient des commentaires de SOUND_MOMENTS dans
// BattleAssault.gd : elle décrit un point RÉEL du déroulé de l'assaut, et
// doit donc suivre le code, pas les renommages de l'auteur.
function momentNote(key) {
  const note = vocabulary.moment_notes?.[key] ?? vocabulary.unit_moment_notes?.[key];
  return note ? `${key} — ${note}` : key;
}

// Un chemin `res://Audio/x.wav` se sert en `/audio/x.wav` (cf. server.js).
function audioUrl(path) {
  return path.startsWith("res://Audio/") ? "/audio/" + path.slice("res://Audio/".length) : null;
}

// UN SEUL lecteur pour toute la page : deux boutons pressés coup sur coup
// doivent s'interrompre, pas se superposer — on écoute pour comparer.
let preview = null;

function playButton(getPath) {
  const button = el("button", "battle-play", "▶");
  button.type = "button";
  button.title = "Écouter";
  button.onclick = () => {
    const url = audioUrl(getPath() || "");
    if (!url) return;
    if (preview) preview.pause();
    preview = new Audio(url);
    // Un échec se DIT, sur le bouton lui-même : sans ça un clic sur un fichier
    // absent — ou sur un serveur pas encore relancé, qui ne sert pas encore
    // /audio — ne produit rien du tout, et rien du tout ne donne aucune prise
    // pour chercher.
    preview.onerror = () => {
      button.classList.add("battle-play-failed");
      button.title = "Lecture impossible : fichier absent, ou serveur à relancer";
    };
    button.classList.remove("battle-play-failed");
    button.title = "Écouter";
    preview.play().catch(() => {});
  };
  return button;
}

// ──────────────────────────────────────────────────────────────────────────
//  Séquence de rythme
// ──────────────────────────────────────────────────────────────────────────

// LE DESSIN D'UNE NOTE, celui-là même que la barre pose à l'écran. « cross » et
// « circle » sont des noms de FICHIER — le vocabulaire fermé du moteur — et une
// suite de quatre mots ne se relit pas : ce que l'auteur compose, ce sont les
// pastilles d'une manette et des flèches, et c'est sous cette forme qu'il les
// reconnaîtra en jouant.
//
// Repli sur le NOM quand l'image manque : un serveur resté sur une version
// antérieure ne sert pas `UI/`, et une image cassée serait moins lisible qu'un
// mot. Même règle que partout ici — ce qui n'est que de la présentation dégrade,
// il ne bloque pas.
function noteIcon(id, size = 26) {
  const icon = vocabulary.note_icons?.[id];
  if (!icon) return el("span", "battle-note-name", id);
  const image = el("img", "battle-note-icon");
  image.src = icon.url;
  image.alt = id;
  image.width = size;
  image.height = size;
  // Les quatre directions partagent UN dessin de flèche, tourné — exactement ce
  // que fait RhythmBar._make_note avec ARROW_ROTATION.
  if (icon.rotation) image.style.transform = `rotate(${icon.rotation}deg)`;
  image.onerror = () => image.replaceWith(el("span", "battle-note-name", id));
  return image;
}

// Une note de la séquence : son dessin, de quoi la CHANGER, la DÉPLACER et la
// RETIRER.
//
// Le changement passe par un `select` étiré sur le DESSIN et rendu transparent.
// C'est un détour, et il est assumé : un `option` natif n'affiche pas d'image,
// or le vocabulaire doit rester une liste fermée (une note inventée ne produit
// qu'un silence dans la barre, découvert en lançant ce combat-là). Le détour
// rend les deux à la fois — on voit le dessin, on choisit dans la liste du
// moteur — et garde gratuitement le clavier.
function sequenceChip(action, index, onChanged) {
  const note = action.sequence[index];
  const chip = el("span", "battle-note");
  chip.draggable = true;

  // LA POIGNÉE EST INDISPENSABLE, pas décorative : le `select` recouvre le
  // dessin, et un appui dessus ouvre sa liste au lieu d'amorcer un glissement.
  // Sans une zone que rien n'intercepte, la pastille serait draggable et
  // impossible à saisir — le genre de commande qui « ne fait rien ».
  const grip = el("span", "battle-note-grip", "⠿");
  grip.title = `${note} — glisser pour déplacer`;
  chip.appendChild(grip);

  const face = el("span", "battle-note-face");
  face.title = `${note} — cliquer pour changer de note`;
  face.appendChild(noteIcon(note));
  const pick = selectInput(vocabulary.notes, note, (value) => {
    action.sequence[index] = value;
    onChanged();
  });
  pick.classList.add("battle-note-pick");
  face.appendChild(pick);
  chip.appendChild(face);

  const remove = el("button", "battle-chip-remove", "×");
  remove.type = "button";
  remove.title = "Retirer cette note";
  remove.onclick = () => {
    action.sequence.splice(index, 1);
    onChanged();
  };
  chip.appendChild(remove);

  // L'ORDRE EST LA MOITIÉ DE LA SÉQUENCE, et il n'y avait aucun moyen de le
  // changer : insérer une note au milieu obligeait à réécrire toute la suite.
  chip.ondragstart = (event) => {
    event.dataTransfer.setData("text/plain", String(index));
    event.dataTransfer.effectAllowed = "move";
    chip.classList.add("battle-note-dragging");
  };
  chip.ondragend = () => chip.classList.remove("battle-note-dragging");
  chip.ondragover = (event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    chip.classList.add("battle-note-over");
  };
  chip.ondragleave = () => chip.classList.remove("battle-note-over");
  chip.ondrop = (event) => {
    event.preventDefault();
    // Retiré AVANT le test qui suit : lâcher une pastille sur elle-même ne
    // redessine rien, et le surlignage du survol resterait allumé.
    chip.classList.remove("battle-note-over");
    const from = Number(event.dataTransfer.getData("text/plain"));
    if (!Number.isInteger(from) || from === index) return;
    action.sequence.splice(index, 0, action.sequence.splice(from, 1)[0]);
    onChanged();
  };
  return chip;
}

// Ce qu'une séquence DURE et à quelle tolérance elle se juge — deux choses
// qu'un nombre de notes ne dit pas, et qui décident pourtant de ce qu'elle
// vaut à jouer. Les chiffres viennent des constantes de la barre, pas d'ici.
function sequenceFacts(sequence) {
  const timings = vocabulary.rhythm;
  const line = el("p", "battle-inline-hint battle-sequence-facts");
  if (sequence.length === 0) {
    line.textContent = "Sans séquence, l'action ne fait pas jouer la barre : "
      + "elle frappe à puissance nominale.";
    return line;
  }
  const { total } = sequenceTiming(sequence, timings);
  const windows = judgementWindows(timings);
  const seconds = (value) => value.toFixed(2).replace(".", ",");
  line.textContent =
    `${sequence.length} note${sequence.length > 1 ? "s" : ""} · la barre tourne `
    + `${seconds(total)} s · une arrivée toutes les `
    + `${seconds(timings.note_interval)} s — PERFECT ±${windows.perfect} ms, `
    + `GREAT ±${windows.great} ms, GOOD ±${windows.good} ms.`;
  return line;
}

// Les notes sont un vocabulaire fermé lu dans RhythmBar.gd : des pastilles
// cliquables plutôt qu'un champ texte, une note inventée ne pouvant produire
// qu'un silence dans la barre.
//
// TROIS CHOSES SE RÈGLENT ICI, et la page ne montrait que la première : QUOI
// (les notes), DANS QUEL ORDRE (le glisser-déposer), et CE QUE ÇA DONNE (un
// aperçu qui défile à la vitesse du combat). Sans la troisième, deux Ekos de
// trois notes se ressemblent sur la page et ne se ressemblent pas manette en
// main.
function sequenceEditor(action, onChanged) {
  const wrap = el("div", "battle-sequence-editor");
  const notes = action.sequence || [];

  const row = el("div", "battle-sequence");
  notes.forEach((_, index) => row.appendChild(sequenceChip(action, index, onChanged)));
  if (notes.length === 0) {
    row.appendChild(el("span", "battle-inline-hint", "Aucune note."));
  }
  wrap.appendChild(row);

  // UNE PALETTE PLUTÔT QU'UN « + note » NEUTRE. L'ancien bouton ajoutait
  // toujours la première note du vocabulaire, qu'il fallait ensuite changer :
  // deux gestes pour un, et une valeur fausse écrite dans le fichier entre les
  // deux. Ici on ajoute LA note qu'on veut.
  const palette = el("div", "battle-note-palette");
  palette.appendChild(el("span", "battle-field-label", "Ajouter"));
  for (const id of vocabulary.notes) {
    const add = el("button", "battle-note-add");
    add.type = "button";
    add.title = `Ajouter « ${id} » à la fin`;
    add.appendChild(noteIcon(id, 22));
    add.onclick = () => {
      if (!action.sequence) action.sequence = [];
      action.sequence.push(id);
      onChanged();
    };
    palette.appendChild(add);
  }
  wrap.appendChild(palette);

  wrap.appendChild(sequenceFacts(notes));
  wrap.appendChild(rhythmPreview(notes, vocabulary.rhythm, vocabulary.note_icons || {}));
  return wrap;
}

// ──────────────────────────────────────────────────────────────────────────
//  Sons d'action
// ──────────────────────────────────────────────────────────────────────────

// Moments que cette action-là n'atteindra JAMAIS. Le moteur se contente de ne
// rien jouer ; l'éditeur, lui, a toute l'information pour le dire — et un son
// muet qu'on ne découvre qu'en lançant ce combat précis est exactement le
// genre de faute que cette page existe pour éviter.
//
// Les deux règles viennent de `BattleAssault._resolve` : l'approche et le
// retour n'ont lieu que pour une action OFFENSIVE (`offensive = heal <= 0`, cf.
// `_effect_of`), et le rythme que pour une action qui a une séquence.
function unreachableMoments(action) {
  const unreachable = new Set();
  // MÊME RÈGLE QUE LE MOTEUR : « approach » et « return » n'existent que pour
  // une action qui VA AU CONTACT (cf. BattleAssault._comes_to_contact). Ni un
  // soin, ni une attaque à distance n'y passent.
  if (Number(action.heal || 0) > 0 || action.range === "ranged") {
    unreachable.add("approach");
    unreachable.add("return");
  }
  if (!action.sequence || action.sequence.length === 0) unreachable.add("rhythm");
  return unreachable;
}

function soundLabel(path) {
  return path.split("/").pop() || path;
}

// Le dossier d'un son, tel qu'il s'affiche en intertitre de la liste.
function soundFolder(path) {
  const rel = path.startsWith("res://Audio/") ? path.slice("res://Audio/".length) : path;
  const cut = rel.lastIndexOf("/");
  return cut < 0 ? "Audio" : "Audio/" + rel.slice(0, cut);
}

// LA LISTE DES SONS EST RANGÉE PAR DOSSIER. À plat, elle aligne soixante-dix
// fichiers étiquetés de leur seul nom : trouver le fracas d'un Eko oblige à
// faire défiler toutes les répliques de Noah. Le dossier est précisément
// l'information qui manque pour s'y retrouver, et c'est déjà celle qui range
// les fichiers sur le disque.
//
// `current` rejoint la liste s'il n'y est pas, sous un intertitre qui le dit :
// un chemin dont le fichier a disparu doit rester VISIBLE et sélectionné, sinon
// le menu se rabat sur du vide et la prochaine modification de la fiche efface
// le chemin sans que personne l'ait demandé.
function soundGroups(current) {
  const byFolder = new Map();
  const push = (folder, value) => {
    if (!byFolder.has(folder)) byFolder.set(folder, []);
    byFolder.get(folder).push(value);
  };
  for (const path of sounds) push(soundFolder(path), path);
  const named = [...byFolder.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  if (current && !sounds.includes(current)) {
    named.unshift(["Introuvable sur le disque", [current]]);
  }
  return named.map(([label, values]) => ({ label, values }));
}

// Nom proposé pour un son importé. Depuis la ligne d'une action,
// <action>_<moment> — même convention que pour les planches
// (<unité>_<planche>), et elle range le dossier toute seule. Depuis la
// bibliothèque, où rien ne dit à quoi le fichier servira, son propre nom.
// Proposé et pas imposé : l'auteur peut garder le nom de son export.
function suggestedSoundName(moment, file) {
  const extension = (file.name.split(".").pop() || "wav").toLowerCase();
  const owner = selection[activeSection];
  const stem = moment && owner
    ? `${owner}_${moment}`
    : (file.name.split(".").slice(0, -1).join(".") || "son");
  return `${stem}.${extension}`.toLowerCase().replace(/[^a-z0-9_.-]/g, "_");
}

// Bouton d'import posé SUR LA LIGNE du fichier : importer un son, c'est
// remplacer celui de cette variante-là, pas en ajouter une. Le fichier part
// dans Audio/Battle/Actions, la liste se recharge, et le chemin retenu est
// celui que le serveur rend — jamais celui qu'on croit avoir écrit.
function soundImportButton(moment, assign, onChanged, { label = null } = {}) {
  const button = el("button", "battle-sound-import", label || "⇧");
  button.type = "button";
  button.title = label
    ? "Déposer un son dans Audio/Battle/Actions, sans l'affecter à une action"
    : "Importer un son depuis le disque et l'affecter à cette variante";
  const picker = el("input");
  picker.type = "file";
  picker.accept = "audio/wav,audio/ogg,audio/mpeg,.wav,.ogg,.mp3";
  picker.hidden = true;
  picker.onchange = async () => {
    const file = picker.files && picker.files[0];
    // Remis à zéro tout de suite : sans ça, réimporter DEUX FOIS le même
    // fichier ne déclencherait pas de second `change`.
    picker.value = "";
    if (!file) return;
    const wanted = prompt(
      "Nom du fichier dans Audio/Battle/Actions :", suggestedSoundName(moment, file)
    );
    if (!wanted) return;
    button.disabled = true;
    button.textContent = "…";
    try {
      let result;
      try {
        result = await uploadBattleSound(file, wanted);
      } catch (err) {
        // 409 : le fichier existe. Seule erreur qui vaut une seconde chance, et
        // elle se pose explicitement — écraser un son déjà employé par une
        // autre action ne se devine pas.
        if (!String(err.message).includes("existe déjà")) throw err;
        if (!confirm(`${err.message} L'écraser ?`)) return;
        result = await uploadBattleSound(file, wanted, { overwrite: true });
      }
      sounds = await getBattleSounds();
      assign(result.path);
      if (!result.imported) {
        alert(
          "Le fichier est en place, mais Godot ne l'a pas importé : ouvre "
          + "l'éditeur Godot une fois pour qu'il se joue en jeu."
        );
      }
      onChanged();
    } catch (err) {
      alert(`Import impossible : ${err.message}`);
    } finally {
      button.disabled = false;
      button.textContent = label || "⇧";
    }
  };
  button.onclick = () => picker.click();
  const holder = el("span", "battle-sound-import-holder");
  holder.appendChild(button);
  holder.appendChild(picker);
  return holder;
}

// Les lanceurs auxquels une entrée est réservée. Vide = tout le monde. Accepte
// un id seul comme une liste, exactement comme `sound` accepte un chemin seul —
// c'est la même commodité de lecture à la main, et le moteur en fait autant
// (cf. BattleData._performers_of).
function soundUnits(entry) {
  const declared = entry.units;
  if (Array.isArray(declared)) return declared.filter(Boolean);
  return declared ? [declared] : [];
}

function soundPaths(entry) {
  if (Array.isArray(entry.sound)) return entry.sound;
  return entry.sound ? [entry.sound] : [];
}

// Un seul chemin s'écrit en chaîne, plusieurs en tableau : c'est la forme que
// lit `BattleAssault._sounds_of`, et celle qui reste lisible à la main dans le
// JSON pour le cas courant.
function setSoundPaths(entry, paths) {
  const kept = paths.filter(Boolean);
  entry.sound = kept.length === 1 ? kept[0] : kept;
}

// `families` décrit les listes dans lesquelles un son peut vivre. Il y en a
// DEUX sur une unité — le geste de son attaque de base, et sa voix propre — et
// une seule sur un Eko ou un objet.
//
// L'AFFICHAGE est fusionné, le RANGEMENT non. Pour l'auteur, une unité « a des
// sons » et le moment choisi suffit à dire de quoi il s'agit : une seule liste,
// un seul menu déroulant. Mais le moteur, lui, cherche la voix du blessé sur la
// fiche de l'unité et les sons du geste sur la définition de l'action ; une
// entrée rangée du mauvais côté serait écartée avec un avertissement. Changer
// le moment d'une entrée la DÉPLACE donc d'une liste à l'autre, sans que
// l'auteur ait à savoir qu'il y en a deux.
// La famille des sons portés par une ACTION (attaque de base, Eko, objet).
//
// `performers` = les personnages qui peuvent la lancer. Une entrée peut leur
// être RÉSERVÉE (champ `units`), ce qui permet à deux personnages de partager un
// Eko sans partager le cri qu'ils poussent en le lançant.
function actionFamily(action, performers = []) {
  return {
    owner: action,
    moments: vocabulary.moments,
    label: "Pendant le geste",
    fallback: "hit",
    unreachable: unreachableMoments(action),
    performers,
  };
}

// Celle des sons portés par l'UNITÉ, qui ne dépendent d'aucun geste.
function unitFamily(unit) {
  return {
    owner: unit,
    moments: vocabulary.unit_moments,
    label: "Voix du personnage",
    fallback: vocabulary.unit_moments[0],
  };
}

function soundsEditor(families, onChanged) {
  const wrap = el("div", "battle-sounds");
  const groups = families.length > 1
    ? families.map((f) => ({ label: f.label, values: f.moments }))
    : null;
  const allMoments = families.flatMap((f) => f.moments);
  const familyOf = (moment) =>
    families.find((f) => f.moments.includes(moment)) || families[0];

  for (const family of families) {
    const list = family.owner.sounds || [];
    list.forEach((entry, index) => {
      wrap.appendChild(soundRow(family, entry, index, families, {
        groups, allMoments, familyOf, onChanged,
      }));
      const moment = entry.at || family.fallback;
      if (family.unreachable?.has(moment)) {
        wrap.appendChild(
          el(
            "span",
            "battle-warning",
            `« ${momentLabel(moment)} » n'existe pas pour cette action : elle ne l'atteint jamais, le son ne se jouera pas.`
          )
        );
      }
    });
  }

  const add = el("button", "battle-chip-add", "+ son");
  add.type = "button";
  add.onclick = () => {
    const family = families[0];
    if (!family.owner.sounds) family.owner.sounds = [];
    family.owner.sounds.push({ at: family.fallback, sound: sounds[0] || "" });
    onChanged();
  };
  wrap.appendChild(add);
  return wrap;
}

function soundRow(family, entry, index, families, ctx) {
  const { groups, allMoments, familyOf, onChanged } = ctx;
  const row = el("div", "battle-sound-row");

  row.appendChild(
    selectInput(allMoments, entry.at || family.fallback, (value) => {
      const cible = familyOf(value);
      entry.at = value;
      if (cible !== family) {
        family.owner.sounds.splice(index, 1);
        if (!cible.owner.sounds) cible.owner.sounds = [];
        cible.owner.sounds.push(entry);
        // La liste vidée disparaît du JSON : un `"sounds": []` traînant ferait
        // gonfler le catalogue d'un champ que personne n'a demandé.
        if (family.owner.sounds.length === 0) delete family.owner.sounds;
      }
      onChanged();
    }, { labelOf: momentLabel, titleOf: momentNote, groups })
  );

  // POUR QUI. Un Eko est partagé par tous ceux qui l'ont appris, mais la voix
  // ne l'est pas : cette liste réserve l'entrée à un personnage. Le moteur fait
  // passer les entrées nommées DEVANT celles de tout le monde (cf.
  // BattleData.sounds_of), donc un son réservé remplace le son commun pour ce
  // personnage-là, et les autres gardent le commun.
  //
  // Seulement sur une action : les sons d'une unité n'ont pas de lanceur à
  // départager, c'est elle.
  if (family.performers && family.performers.length > 0) {
    const reserved = soundUnits(entry);
    const current = reserved[0] || "";
    // Un id réservé à quelqu'un qui ne connaît plus l'action reste AFFICHÉ :
    // sans ça, la liste se rabat sur « tout le monde » et la prochaine
    // modification de la fiche élargirait le son sans que personne l'ait
    // demandé.
    const offered = family.performers.includes(current) || current === ""
      ? family.performers
      : [current, ...family.performers];
    // La rangée passe à quatre colonnes : sans ça la corbeille, quatrième
    // enfant d'une grille qui n'en attend que trois, tombe à la ligne.
    row.classList.add("battle-sound-row-performer");
    row.appendChild(
      selectInput(offered, current, (value) => {
        if (value) entry.units = [value];
        else delete entry.units;
        onChanged();
      }, {
        empty: "Tout le monde",
        labelOf: (unitId) => localizedName("units", unitId).label || unitId,
        titleOf: (unitId) => (unitId
          ? `Seulement quand ${unitId} lance cette action`
          : "Pour tous ceux qui lancent cette action"),
      })
    );
  }

  // Plusieurs fichiers sur une entrée = des VARIANTES tirées au hasard, pas
  // deux sons joués ensemble. Le libellé le dit, parce que la distinction ne
  // se devine pas d'une liste.
  const files = el("div", "battle-sound-files");
  const paths = soundPaths(entry);
  const moment = entry.at || family.fallback;
  const setPath = (fileIndex, value) => {
    const next = soundPaths(entry);
    next[fileIndex] = value;
    setSoundPaths(entry, next);
  };
  paths.forEach((path, fileIndex) => {
    const line = el("div", "battle-sound-file");
    const picker = selectInput(sounds, path, (value) => {
      setPath(fileIndex, value);
      onChanged();
    }, { labelOf: soundLabel, titleOf: (value) => value, groups: soundGroups(path) });
    line.appendChild(picker);
    // Le bouton lit la valeur COURANTE du menu, pas celle capturée au montage :
    // changer de fichier puis écouter doit faire entendre le nouveau, et le
    // redessin de la liste n'arrive qu'après la sauvegarde.
    line.appendChild(playButton(() => picker.value));
    // Choisir, écouter, importer : les trois gestes du même fichier, sur la
    // même ligne. Importer AFFECTE aussitôt — c'est ce qu'on vient faire.
    line.appendChild(soundImportButton(moment, (value) => setPath(fileIndex, value), onChanged));
    const remove = el("button", "battle-chip-remove", "×");
    remove.type = "button";
    remove.title = "Retirer ce fichier";
    remove.onclick = () => {
      const next = soundPaths(entry);
      next.splice(fileIndex, 1);
      setSoundPaths(entry, next);
      onChanged();
    };
    line.appendChild(remove);
    files.appendChild(line);
  });

  // Une entrée SANS fichier reste importable : elle affiche la ligne d'import
  // seule, plutôt qu'un « + variante » qui obligerait à passer par un son
  // quelconque avant de déposer le sien.
  if (paths.length === 0) {
    const line = el("div", "battle-sound-file");
    line.appendChild(el("span", "battle-inline-hint", "Aucun fichier."));
    line.appendChild(
      soundImportButton(moment, (value) => setSoundPaths(entry, [value]), onChanged)
    );
    files.appendChild(line);
  }

  const addFile = el("button", "battle-chip-add", "+ variante");
  addFile.type = "button";
  addFile.title = "Une variante de plus : le moteur en tire une au hasard à chaque fois";
  addFile.onclick = () => {
    setSoundPaths(entry, [...soundPaths(entry), sounds[0] || ""]);
    onChanged();
  };
  files.appendChild(addFile);
  row.appendChild(files);

  const remove = el("button", "modal-map-delete", "🗑");
  remove.type = "button";
  remove.title = "Retirer ce son";
  remove.onclick = () => {
    family.owner.sounds.splice(index, 1);
    if (family.owner.sounds.length === 0) delete family.owner.sounds;
    onChanged();
  };
  row.appendChild(remove);
  return row;
}

// ──────────────────────────────────────────────────────────────────────────
//  Bloc commun aux actions (attaque de base, Eko, objet)
// ──────────────────────────────────────────────────────────────────────────

// Toutes les planches déclarées, unités confondues. Une action de catalogue
// nomme une planche cherchée dans le bloc `animations` de l'unité QUI AGIT,
// pas dans son propre fichier : un Eko partagé par plusieurs personnages se
// joue avec la planche de chacun. L'union est donc la seule liste honnête ici.
function allAnimationNames() {
  const names = new Set();
  for (const unit of Object.values(entriesOf("units"))) {
    for (const name of Object.keys(unit.animations || {})) names.add(name);
  }
  return [...names].sort();
}

// Valeur sentinelle de la liste « Planche » : elle ne peut pas entrer en
// collision avec un nom de planche, qui passe par ID_PATTERN.
const NEW_ANIMATION = "+";

// LES DEUX MOMENTS OÙ UNE ACTION NOMME UNE PLANCHE que le PERSONNAGE déclare.
// C'est une seule règle côté moteur (`BattleAssault._sheet_for` : le nom que
// porte l'action, sinon l'état du personnage), et c'est donc un seul tableau
// ici — décrit en donnée plutôt que recopié en deux fonctions jumelles qui
// finiraient par diverger.
//
// `fallback` est une FONCTION et non une valeur : les deux défauts sont lus
// dans les `.gd` au chargement de la page, donc après l'évaluation de ce bloc.
const ACTION_SHEETS = {
  gesture: {
    field: "animation",
    label: "Planche du geste",
    fallback: () => actionAnimationDefault,
    hint: "Nom cherché dans le bloc « animations » de l'unité qui agit, pas ici.",
    empty: "(pas en avant)",
    title: "Geste, par personnage",
    note: "la planche que chacun joue quand le coup part",
    none: "il frappe sans rien montrer, d'un simple pas en avant",
  },
  approach: {
    field: "approach_animation",
    label: "Planche du déplacement",
    fallback: () => "approach",
    hint: "Jouée pendant que l'unité traverse le terrain, et au moins aussi "
      + "longtemps que le trajet.",
    empty: "(il glisse sur sa planche du moment)",
    title: "Déplacement, par personnage",
    note: "la planche que chacun joue en s'élançant",
    none: "il glisse jusqu'au contact sur la planche qu'il porte",
  },
  rhythm: {
    field: "rhythm_animation",
    label: "Planche tenue",
    fallback: () => rhythmAnimationDefault,
    hint: "Pose prise dès la première note, avant que l'unité ne se déplace.",
    empty: "(pas de pose)",
    title: "Pose pendant la séquence, par personnage",
    note: "ce que chacun montre pendant qu'on joue les notes",
    none: "il garde la planche qu'il portait, comme avant",
  },
};

// `fields` dit quels champs cette action-là possède : une attaque de base n'a
// ni coût en PA ni mode de ciblage (elle vise toujours un adversaire), un objet
// n'a pas de coût en PA, un Eko a tout.
//
// `suggestion` est le nom proposé quand l'auteur crée un geste depuis ici —
// l'identifiant de l'action, qui est la convention naturelle (l'Eko « aubaine »
// joue la planche « aubaine »). Vide, la liste ne propose pas d'en créer un.
function actionFields(action, fields, animations, onChanged, suggestion = "") {
  const grid = el("div", "battle-grid");

  if (fields.includes("ap_cost")) {
    grid.appendChild(
      objectNumberField(action, "ap_cost", "Coût PA", {
        optional: true,
        min: 0,
        title: "0 = gratuit",
        onCommit: onChanged,
      })
    );
  }

  if (fields.includes("target")) {
    grid.appendChild(
      field(
        "Ciblage",
        selectInput(vocabulary.targets, action.target || "enemy", (v) => {
          action.target = v;
          onChanged();
        }, { labelOf: targetLabel, titleOf: (key) => key }),
        "Lu RELATIVEMENT à celui qui agit : « ally » désigne son propre camp."
      )
    );
  }

  // UN SOIN IGNORE LA PUISSANCE ET LA NATURE DES DÉGÂTS : le moteur bascule sur
  // `heal` dès qu'il est positif (cf. BattleAssault._effect_of) et ne lit plus
  // les deux autres. Les laisser vifs laissait croire à une action qui frappe ET
  // soigne — un Eko à `heal: 18` et `power: 14` n'inflige rien du tout.
  const heals = Number(action.heal || 0) > 0;
  const powerField = objectNumberField(action, "power", "Puissance", {
    optional: true,
    min: 0,
    onCommit: onChanged,
  });
  if (heals) markIgnored(powerField, "Ignorée : cette action soigne.");
  grid.appendChild(powerField);

  if (fields.includes("heal")) {
    grid.appendChild(
      objectNumberField(action, "heal", "Soin", {
        optional: true,
        min: 0,
        title: "Un soin (> 0) rend l'action non offensive : elle ne se déplace pas vers sa cible.",
        onCommit: onChanged,
      })
    );
  }

  const natureField = field(
    "Nature",
    selectInput(vocabulary.damage_types, action.damage_type, (v) => {
      if (v) action.damage_type = v;
      else delete action.damage_type;
      onChanged();
    }, { empty: "(aucune)" }),
    "direct retire les PV tout de suite, injury les met en attente. Choisit aussi l'icône de la rangée."
  );
  if (heals) markIgnored(natureField, "Ignorée : cette action soigne.");
  grid.appendChild(natureField);

  grid.appendChild(sheetField(action, ACTION_SHEETS.gesture, animations, suggestion, onChanged));
  return grid;
}

// LE NOM D'UNE PLANCHE SE CRÉE ICI, et pas seulement dans la fiche d'un
// personnage. La liste ne pouvait offrir que les planches DÉJÀ déclarées
// quelque part : donner un geste propre à un Eko obligeait donc à aller d'abord
// en inventer un chez chaque personnage, pour revenir le choisir ici. C'est
// pourtant sur l'action que la question se pose — « Aubaine ne doit pas faire
// le même geste qu'une attaque » — et le tableau qui suit permet ensuite de
// donner sa planche à chacun sans quitter la page.
function sheetField(action, spec, animations, suggestion, onChanged) {
  const choices = suggestion ? [...animations, NEW_ANIMATION] : animations;
  return field(
    spec.label,
    selectInput(choices, action[spec.field], (v) => {
      if (v === NEW_ANIMATION) nameNewAnimation(action, spec, suggestion);
      else if (v) action[spec.field] = v;
      else delete action[spec.field];
      onChanged();
    }, { empty: spec.empty, labelOf: animationOptionLabel }),
    spec.hint
  );
}

// Demande un nom de planche et le pose sur l'action. Un refus (annulation, nom
// invalide) laisse l'action telle quelle : l'appelant redessine de toute façon,
// donc la liste revient d'elle-même sur la valeur d'avant.
//
// Le nom proposé est celui de l'action pour le geste, et suffixé pour les
// autres moments : un même Eko peut vouloir deux planches, et « aubaine » pour
// les deux ferait jouer la même des deux côtés sans que rien ne le dise.
function nameNewAnimation(action, spec, suggestion) {
  const proposed = spec === ACTION_SHEETS.gesture ? suggestion : `${suggestion}_${spec.fallback()}`;
  const name = prompt(
    "Nom de la planche. Chaque personnage qui lance cette action jouera SA "
      + "planche portant ce nom :",
    proposed
  );
  if (!name) return;
  if (!ID_PATTERN.test(name)) {
    alert("Nom invalide : minuscules, chiffres et « _ » seulement.");
    return;
  }
  action[spec.field] = name;
}

// MÊME VOCABULAIRE QUE LA PAGE UNITÉS. Une action ne porte pas une planche,
// elle porte le NOM d'une planche que l'unité qui agit doit déclarer — c'est
// exactement la liaison que le champ « État » montre de l'autre côté. Les
// libellés sont donc les mêmes des deux bords, sinon la même chaîne s'appelle
// « Repos — idle » ici et « idle » là.
function animationOptionLabel(key) {
  if (key === NEW_ANIMATION) return "+ nouvelle planche…";
  const label = momentLabels.animation_labels?.[key];
  if (label) return `${label} — ${key}`;
  return key === actionAnimationDefault
    ? `${key} (planche d'action, par défaut)`
    : `${key} (nom libre)`;
}

// Qui sait jouer cette planche, et qui ne sait pas. Le pendant exact du
// « qui l'appelle » affiché sur une planche d'unité : une action qui nomme une
// planche qu'aucun personnage ne déclare ne fait AUCUN geste, sans erreur.
//
// `performers` limite la question À CEUX QUE ÇA CONCERNE : l'attaque de base
// d'une unité ne regarde qu'elle, un Eko ne regarde que les personnages qui le
// connaissent. Sans ça, la ligne accuserait un manque chez des unités qui ne
// lanceront jamais cette action.
function animationCoverage(action, performers, spec) {
  const fallback = spec.fallback();
  const name = action[spec.field] || fallback;
  const units = entriesOf("units");
  const has = [];
  const replaced = [];
  const none = [];
  for (const id of performers) {
    const unit = units[id];
    if (!unit) continue;
    const sheets = unit.animations || {};
    // Le moteur retombe sur l'ATTAQUE DU PERSONNAGE quand l'action nomme une
    // planche qu'il n'a pas (cf. BattleAssault._gesture_for) : l'éditeur doit
    // dire la même chose, sinon il annonce un geste manquant là où il y en a un.
    if (sheets[name]) has.push(id);
    else if (sheets[fallback]) replaced.push(id);
    else none.push(id);
  }
  return { name, fallback, has, replaced, none };
}

// Ligne d'information sous les champs d'une action, dans le même esprit que
// « États sans planche : … » côté unité.
function actionCoverageLine(action, performers, spec) {
  const line = el("span", "battle-inline-hint");
  if (!performers || performers.length === 0) {
    line.textContent = "Aucune unité ne connaît cette action pour l'instant.";
    return line;
  }
  const { name, fallback, has, replaced, none } = animationCoverage(action, performers, spec);
  const parts = [];
  if (has.length) parts.push(`déclarée par ${has.join(", ")}`);
  if (replaced.length) {
    parts.push(`${replaced.join(", ")} jouera « ${fallback} » à la place`);
  }
  if (none.length) parts.push(`rien pour ${none.join(", ")}, ${spec.none}`);
  line.textContent = `Planche « ${name} » : ${parts.join(" ; ")}.`;
  // Rouge seulement quand quelqu'un frappe VRAIMENT sans rien montrer : un
  // repli sur la planche du personnage est un fonctionnement normal, pas une
  // alerte.
  if (none.length) line.classList.add("battle-warning");
  return line;
}

// CE QUE CHACUN MONTRE QUAND IL LANCE CETTE ACTION, et de quoi le régler sans
// quitter la page.
//
// POURQUOI ICI, alors que la planche vit dans la fiche du personnage. Une
// action ne PORTE pas un geste, elle en NOMME un (`animation`) ; c'est chaque
// unité qui déclare la planche de ce nom, avec sa propre grille et son propre
// ancrage (cf. BattleAssault._gesture_for). La question se pose donc dans ce
// sens-là — « quand Noah lance Aubaine, qu'est-ce qu'on voit ? » — et y
// répondre obligeait jusqu'ici à ouvrir les unités une par une. C'est le
// pendant exact du tableau « Son du geste, par Eko » de la fiche d'unité, vu de
// l'autre bord.
//
// C'est aussi ce qui manquait pour que le réglage soit FAISABLE d'ici : la
// ligne d'information annonçait « aucun geste pour iris » sans offrir le geste
// qui l'aurait corrigé.
function sheetTable(action, performers, onChanged, spec) {
  const block = el("div", "battle-block");
  const name = action[spec.field] || spec.fallback();
  block.appendChild(sectionTitle(spec.title, `${spec.note} — sous le nom « ${name} »`));
  if (performers.length === 0) {
    block.appendChild(el("p", "battle-inline-hint", "Personne ne lance cette action."));
    return block;
  }
  const table = el("div", "battle-gestures");
  for (const id of performers) {
    table.appendChild(performerSheetLine(id, name, onChanged, spec));
  }
  block.appendChild(table);
  return block;
}

// Une ligne du tableau : qui, et ce qu'il joue. Trois cas, et un seul d'entre
// eux se règle vraiment ici — les deux autres disent ce que le MOTEUR fera à la
// place, parce qu'aucun des deux ne lève d'erreur en jeu.
function performerSheetLine(unitId, name, onChanged, spec) {
  const unit = entriesOf("units")[unitId];
  const line = el("div", "battle-gesture");
  const head = el("div", "battle-gesture-head");
  const open = el("button", "battle-eko-link", localizedName("units", unitId).label || unitId);
  open.type = "button";
  open.title = `Ouvrir « ${unitId} »`;
  open.onclick = () => goToEntry("units", unitId);
  head.appendChild(open);
  // L'ID À CÔTÉ DU NOM, comme partout ailleurs : « Noah » est le nom de jeu,
  // `noah` est la clé qu'on retrouve dans units.json et dans les cases à cocher.
  head.appendChild(el("span", "battle-index-id", unitId));
  line.appendChild(head);
  if (!unit) {
    head.appendChild(el("span", "battle-warning", "absent du catalogue"));
    return line;
  }

  if (unit.animations?.[name]) {
    head.appendChild(el("span", "battle-badge", "planche propre"));
    line.appendChild(animationBlock(unitId, unit, name, onChanged, { state: false }));
    return line;
  }

  const note = el("div", "battle-gesture-fallback");
  // Le moteur retombe sur l'ÉTAT DU PERSONNAGE quand l'action nomme une planche
  // qu'il n'a pas — et sur rien du tout s'il n'a pas celle-là non plus
  // (cf. BattleAssault._sheet_for). Les deux sont des fonctionnements normaux ;
  // seul le second mérite du rouge.
  const state = spec.fallback();
  const fallback = unit.animations?.[state];
  if (fallback) {
    head.appendChild(el("span", "battle-badge", "repli"));
    note.appendChild(staticFrame(fallback, sheetUrl(fallback.sheet), 40));
    note.appendChild(
      el("span", "battle-inline-hint",
        `Pas de planche « ${name} » : il joue sa planche « ${state} ».`)
    );
  } else {
    head.appendChild(el("span", "battle-warning", "rien à montrer"));
    // L'ACTION QUI NE NOMME RIEN retombe sur l'état du personnage : les deux
    // noms sont alors le MÊME, et « ni rhythm ni rhythm » se lit comme un bug
    // de l'éditeur. Un seul nom, une seule fois.
    note.appendChild(
      el("span", "battle-inline-hint",
        name === state
          ? `Aucune planche « ${name} » : ${spec.none}.`
          : `Ni « ${name} » ni « ${state} » : ${spec.none}.`)
    );
  }
  const add = el("button", "battle-chip-add", `+ planche « ${name} »`);
  add.type = "button";
  add.title = `Donner à ${unitId} une planche propre à cette action.`;
  add.onclick = () => {
    if (!unit.animations) unit.animations = {};
    unit.animations[name] = blankSheet(true);
    // Dépliée d'office : elle est vide, et la seule chose à faire ensuite est
    // d'y importer une image.
    openSheets.add(`units:${unitId}:${name}`);
    onChanged();
  };
  note.appendChild(add);
  line.appendChild(note);
  return line;
}

// Les personnages qui peuvent lancer cette action : eux seuls doivent déclarer
// sa planche.
function performersOf(section, id) {
  const units = Object.entries(entriesOf("units"));
  if (section === "ekos") {
    return units.filter(([, u]) => (u.ekos || []).includes(id)).map(([uid]) => uid);
  }
  // Un objet est utilisable par n'importe quel allié : tout le monde est
  // concerné, sauf les ennemis, qui n'ouvrent pas le sac.
  return units.filter(([, u]) => !u.behaviour).map(([uid]) => uid);
}

// Les moments que CETTE action n'atteindra jamais, dits une fois pour toutes
// plutôt qu'au coup par coup sur une entrée déjà posée — comme la ligne des
// états sans planche, qui se lit avant d'ouvrir quoi que ce soit.
function unreachableLine(action) {
  const unreachable = [...unreachableMoments(action)];
  if (unreachable.length === 0) return null;
  return el("p", "battle-inline-hint battle-anim-missing",
    "Moments que cette action n'atteint pas : "
    + unreachable.map(momentLabel).join(", ")
    + " — un son posé là ne se jouera pas.");
}

// ──────────────────────────────────────────────────────────────────────────
//  Déplacement
// ──────────────────────────────────────────────────────────────────────────

// AU CONTACT OU À DISTANCE, et la planche du trajet.
//
// Jusqu'ici toute action offensive traversait le terrain : juste d'un coup
// d'épée, faux d'un tir ou d'un sort lancé de loin. « ranged » supprime les deux
// déplacements d'un bloc — l'aller ET le retour, qui n'a plus rien à ramener —
// ainsi que le glissement du terrain, qui existe pour accompagner celui qui
// s'élance (cf. BattleAssault._comes_to_contact).
//
// CE QUI DEVIENT SANS OBJET EST ESTOMPÉ, PAS CACHÉ : la planche du trajet garde
// sa valeur, visiblement inerte, et redevient vivante si l'action repasse au
// contact. Le TABLEAU par personnage, lui, disparaît — c'est un bloc haut, et
// le garder pour dire « ceci ne sert à rien » occuperait l'écran au lieu de
// l'informer.
function rangeBlock(action, performers, animations, suggestion, onChanged, onGestureChanged) {
  const wrap = el("div", "battle-range");
  const heals = Number(action.heal || 0) > 0;
  const ranged = action.range === "ranged";

  const grid = el("div", "battle-grid");
  const rangeField = field(
    "Portée",
    selectInput(vocabulary.ranges, action.range || "melee", (value) => {
      // « melee » est le DÉFAUT du moteur : ne pas l'écrire garde les
      // catalogues tels qu'ils étaient avant ce champ, et une entrée qu'on
      // n'a pas touchée ne gagne pas une ligne à la première visite.
      if (value === "ranged") action.range = value;
      else delete action.range;
      onChanged();
    }, { labelOf: rangeLabel, titleOf: (key) => key }),
    "Au contact, l'unité va vers sa cible et revient. À distance, elle frappe "
      + "depuis son emplacement et il n'y a pas de repli."
  );
  // UN SOIN NE SE DÉPLACE JAMAIS, quelle que soit la portée déclarée : le
  // moteur le sort avant même de lire ce champ (cf. _comes_to_contact).
  if (heals) markIgnored(rangeField, "Ignorée : un soin ne se déplace pas.");
  grid.appendChild(rangeField);

  const sheet = sheetField(action, ACTION_SHEETS.approach, animations, suggestion, onChanged);
  if (heals) markIgnored(sheet, "Ignorée : un soin ne se déplace pas.");
  else if (ranged) markIgnored(sheet, "Ignorée : à distance, l'unité ne bouge pas.");
  grid.appendChild(sheet);
  wrap.appendChild(grid);

  if (heals || ranged) {
    wrap.appendChild(
      el("p", "battle-inline-hint",
        heals
          ? "Un soin part de son emplacement : ni approche, ni repli."
          : "À distance : l'unité reste à son emplacement, le terrain ne glisse "
            + "pas, et il n'y a pas de repli. Les sons posés sur « Approche » et "
            + "« Retour » ne partiront jamais.")
    );
    return wrap;
  }
  wrap.appendChild(
    byPerformer(action, performers, onChanged, onGestureChanged, ACTION_SHEETS.approach)
  );
  return wrap;
}

// ──────────────────────────────────────────────────────────────────────────
//  Effet d'impact
// ──────────────────────────────────────────────────────────────────────────

// Modes de fusion d'un effet, et ce qu'ils veulent dire pour l'auteur. Le
// vocabulaire est celui du moteur (cf. BattleVfx.BLEND_ADD) ; l'explication,
// elle, est en termes de PLANCHE — c'est en la regardant qu'on choisit, et
// « fond noir » se vérifie d'un coup d'œil là où « BLEND_MODE_ADD » ne se
// vérifie nulle part.
const VFX_BLENDS = ["", "add"];
const VFX_BLEND_LABELS = {
  "": "normale (planche détourée)",
  add: "additive (planche sur fond noir)",
};

// L'EFFET QUI ÉCLATE SUR LA CIBLE QUAND L'ACTION PORTE.
//
// POURQUOI IL VIT SUR L'ACTION et pas sur un personnage, contrairement au geste
// et à la pose. Ces deux-là sont des planches du PERSONNAGE — c'est lui qui
// bouge, et deux héros ne lancent pas le même Eko de la même façon. L'impact,
// lui, est ce que l'ACTION fait à celui qui le reçoit : une attaque normale et
// un Eko de foudre ne montrent pas la même chose, quel que soit celui qui
// frappe. Il n'y a donc rien à chercher chez le lanceur, et sa planche est
// décrite ici même.
//
// PAS DE BOUCLAGE À RÉGLER : un impact se joue une fois et s'efface, c'est le
// moteur qui le fixe (cf. BattleVfx.play_once). Un champ `loop` dans la donnée
// serait lu par personne.
function vfxBlock(action, suggestion, onChanged) {
  const wrap = el("div", "battle-vfx");
  const config = action.impact_vfx;
  if (!config) {
    wrap.appendChild(
      el("p", "battle-inline-hint",
        "Aucun effet : la cible encaisse sans rien d'autre que son éclat blanc "
        + "et son nombre de dégâts.")
    );
    const add = el("button", "battle-chip-add", "+ effet d'impact");
    add.type = "button";
    add.onclick = () => {
      action.impact_vfx = blankSheet();
      onChanged();
    };
    wrap.appendChild(add);
    return wrap;
  }

  const body = el("div", "battle-anim-body");
  // La planche jouée UNE FOIS dans l'aperçu comme en jeu : `loop` n'existe pas
  // dans la donnée d'un impact, et un aperçu qui tourne en rond donnerait une
  // idée fausse de sa durée.
  const preview = animationPreview({ ...config, loop: false }, sheetUrl(config.sheet), true);
  if (config.blend === "add") preview.classList.add("battle-vfx-add");
  if (config.sheet) {
    preview.classList.add("sheet-preview-openable");
    preview.title = "Voir la planche entière";
    preview.onclick = () => openSheet(config, "impact", onChanged);
  }
  body.appendChild(preview);

  const column = el("div", "battle-anim-settings");
  const head = el("div", "battle-anim-head");
  head.appendChild(el("span", "battle-inline-hint", vfxSummary(config)));
  const drop = el("button", "modal-map-delete", "🗑");
  drop.type = "button";
  drop.title = "Retirer l'effet d'impact";
  drop.onclick = () => {
    if (!confirm("Retirer l'effet d'impact de cette action ?")) return;
    delete action.impact_vfx;
    onChanged();
  };
  head.appendChild(drop);
  column.appendChild(head);

  // Le fichier, la grille et l'extrait se règlent EXACTEMENT comme une planche
  // de personnage : ce sont les mêmes mesures sur la même sorte d'image, et
  // l'auteur n'a pas à réapprendre trois commandes parce que l'image sert à
  // autre chose. `{}` en guise d'unité : le relevé d'ancrage n'a pas de sens
  // ici — un effet n'a pas de planche de repos sur laquelle se recaler — et la
  // mesure rend alors `null`, ce qui efface simplement l'ancrage.
  column.appendChild(sheetLine(suggestion, {}, config, "impact", onChanged));
  const grid = el("div", "battle-grid");
  for (const [key, label, options] of SHEET_FIELDS) {
    grid.appendChild(objectNumberField(config, key, label, { ...options, onCommit: onChanged }));
  }
  column.appendChild(grid);
  column.appendChild(gridLine({}, "impact", config, onChanged));
  column.appendChild(framesLine(config, "impact", onChanged));

  const options = el("div", "battle-grid");
  options.appendChild(
    field(
      "Fusion",
      selectInput(VFX_BLENDS, config.blend || "", (value) => {
        if (value) config.blend = value;
        else delete config.blend;
        onChanged();
      }, { labelOf: (key) => VFX_BLEND_LABELS[key] || key }),
      "Une planche peinte sur fond noir s'ajoute à l'image au lieu de la "
        + "recouvrir : son noir n'apporte rien, et seule sa lumière passe."
    )
  );
  column.appendChild(options);
  column.appendChild(vfxOffsetLine(config, onChanged));

  body.appendChild(column);
  wrap.appendChild(body);
  return wrap;
}

function vfxSummary(config) {
  const count = Math.max(1, Number(config.frames || 1));
  const fps = Math.max(1, Number(config.fps || 6));
  return `${count} vignette${count > 1 ? "s" : ""} · ${fps} fps · `
    + `${(count / fps).toFixed(2).replace(".", ",")} s`;
}

// OÙ L'EFFET SE POSE, compté depuis le CENTRE DU DESSIN de la cible — pas
// depuis son point au sol, qui est sous ses pieds (cf. BattleAssault._pop_vfx).
// Zéro veut donc dire « au milieu du personnage touché », ce qui est le bon
// défaut pour un impact et n'a rien d'un point inventé : il est mesuré sur les
// pixels réellement dessinés.
//
// La paire est écrite ENTIÈRE ou effacée : `offset` est un couple dans le
// fichier, et n'en écrire qu'une moitié donnerait un tableau incomplet que le
// moteur ignorerait en silence.
function vfxOffsetLine(config, onChanged) {
  const line = el("div", "battle-grid");
  const declared = Array.isArray(config.offset) ? config.offset : [0, 0];
  const inputs = [];
  const commit = (index, value) => {
    const pair = [Number(inputs[0].value) || 0, Number(inputs[1].value) || 0];
    pair[index] = value;
    if (pair[0] === 0 && pair[1] === 0) delete config.offset;
    else config.offset = pair;
    onChanged();
  };
  ["Décalage X", "Décalage Y"].forEach((label, index) => {
    const input = numberInput(declared[index] ?? 0, (value) => commit(index, value));
    inputs.push(input);
    line.appendChild(
      field(label, input,
        index === 0
          ? "Depuis le centre du dessin de la cible. Positif = vers la droite."
          : "Depuis le centre du dessin de la cible. Négatif = vers le haut.")
    );
  });
  return line;
}

// Le tableau par personnage quand on peut y agir, la ligne d'information sinon.
//
// La fiche d'une UNITÉ montre déjà toutes ses planches juste au-dessus : y
// répéter le tableau ne dirait rien de neuf. Sur un Eko ou un objet, au
// contraire, c'est le seul endroit d'où l'on voit — et règle — ce que joue
// chacun de ceux qui le lancent.
function byPerformer(action, performers, onChanged, onGestureChanged, spec) {
  return onGestureChanged
    ? sheetTable(action, performers, onGestureChanged, spec)
    : actionCoverageLine(action, performers, spec);
}

// `sounds = false` sur l'attaque de base d'une unité : ses sons rejoignent la
// liste unique de l'unité, avec la voix du personnage. Un Eko ou un objet, lui,
// n'a qu'une famille et garde ses sons dans son propre bloc.
function actionBlock(
  title, action, fields, animations, onChanged,
  { sounds = true, performers = [], suggestion = "", onGestureChanged = null } = {}
) {
  const block = el("div", "battle-block");
  // MÊME INTERTITRE QUE LES AUTRES SECTIONS. Il y en avait trois formes pour
  // le même rôle — `battle-block-title` ici, `battle-sub-label` en dessous,
  // `battle-section-title` sur la page Unités — et la page Ekos n'avait donc
  // pas le même rythme de lecture qu'une unité, alors qu'elle dit la même
  // chose : des réglages, un geste, des sons.
  block.appendChild(sectionTitle(title));
  block.appendChild(actionFields(action, fields, animations, onChanged, suggestion));
  block.appendChild(byPerformer(action, performers, onChanged, onGestureChanged, ACTION_SHEETS.gesture));
  block.appendChild(sectionTitle("Séquence de rythme"));
  block.appendChild(sequenceEditor(action, onChanged));

  // LA POSE RESTE DANS LA SECTION DU RYTHME, sans intertitre à elle : elle se
  // prend à la première note, et le tableau qui la suit porte déjà son titre.
  // Deux en-têtes qui se suivent en disant la même chose se lisent comme une
  // répétition, pas comme une hiérarchie.
  const pose = el("div", "battle-grid");
  const poseField = sheetField(
    action, ACTION_SHEETS.rhythm, animations, suggestion, onChanged
  );
  // SANS SÉQUENCE, PAS DE POSE : la barre ne se joue pas du tout (cf.
  // BattleAssault._run_rhythm, qui sort avant). Le dire plutôt que de laisser
  // régler une planche qui ne se montrera jamais.
  if ((action.sequence || []).length === 0) {
    markIgnored(poseField, "Ignorée : sans séquence, la barre ne se joue pas.");
  }
  pose.appendChild(poseField);
  block.appendChild(pose);
  block.appendChild(byPerformer(action, performers, onChanged, onGestureChanged, ACTION_SHEETS.rhythm));

  block.appendChild(sectionTitle("Déplacement", "comment l'unité rejoint sa cible"));
  block.appendChild(
    rangeBlock(action, performers, animations, suggestion, onChanged, onGestureChanged)
  );

  block.appendChild(
    sectionTitle("Impact", "ce qui éclate sur la cible quand l'effet porte")
  );
  block.appendChild(vfxBlock(action, suggestion, onChanged));
  if (sounds) {
    block.appendChild(
      sectionTitle("Sons", "de CETTE action, aux six moments de son geste")
    );
    const unreachable = unreachableLine(action);
    if (unreachable) block.appendChild(unreachable);
    block.appendChild(soundsEditor([actionFamily(action, performers)], onChanged));
  }
  return block;
}

// ──────────────────────────────────────────────────────────────────────────
//  Libellés : lecture seule, résolus depuis le catalogue de textes
// ──────────────────────────────────────────────────────────────────────────

// Le texte de jeu d'une entrée de catalogue. `suffix` est « name » ou « desc » :
// ce sont les deux que le moteur va chercher — le nom pour la rangée de menu,
// la description pour le cadre du bas (cf. BattleScene._show_description, qui
// compose « <source>.<id>.desc »).
function localizedText(section, id, suffix) {
  const textId = `${SECTIONS[section].textPrefix}.${id}.${suffix}`;
  const entry = texts.texts?.find((t) => t.id === textId) || null;
  const label = entry
    ? entry.translations?.[texts.default_language] || entry.translations?.en || ""
    : null;
  return { textId, entry, label };
}

function localizedName(section, id) {
  const { textId, label } = localizedText(section, id, "name");
  return { textId, label };
}

// Style des entrées de texte créées d'ici. LES MÊMES QUE LEURS VOISINES : deux
// textes qui partagent un emplacement en jeu doivent partager leur style, et un
// nom d'Eko créé ici s'affichera dans la rangée de menu où s'affichent déjà les
// autres (cf. le rappel de la page Textes sur les styles partagés). Relevés sur
// les entrées existantes : 15 pour un nom, 12 pour une description.
const TEXT_FONT_SIZE = { name: 15, desc: 12 };

// L'entrée de texte, créée à la volée si elle manque. Une entrée de catalogue
// toute neuve n'a pas encore ses textes, et l'auteur qui tape son nom ici ne
// doit pas avoir à aller le déclarer ailleurs d'abord.
function ensureText(section, id, suffix) {
  const { textId, entry } = localizedText(section, id, suffix);
  if (entry) return entry;
  const created = {
    id: textId,
    category: "ui",
    translations: {},
    style: { font_size: TEXT_FONT_SIZE[suffix] || 15 },
  };
  if (!texts.texts) texts.texts = [];
  texts.texts.push(created);
  return created;
}

// Sauvegarde du catalogue de TEXTES, à côté de celle des catalogues de combat.
// Même traitement du conflit : le verrou du serveur refuse une page périmée, et
// `watchForStaleCatalogs` a déjà prévenu — un second `alert` ferait deux
// fenêtres pour un seul refus.
async function persistTexts() {
  try {
    await saveTexts(texts);
  } catch (err) {
    if (!(err instanceof CatalogConflictError)) throw err;
  }
}

// NOM ET DESCRIPTION, sur la fiche même de l'entrée.
//
// Ils ne vivent PAS dans les catalogues de Battle/ : ce sont des textes de jeu,
// rangés avec tous les autres dans Localization/texts.json sous l'id
// `<préfixe>.<id>.name` (et `.desc`, que le moteur affiche dans le cadre du bas,
// cf. BattleScene._show_description). Ils restent donc écrits là-bas — ce bloc
// n'ouvre pas un second stockage, il ouvre une seconde PORTE sur le même. C'est
// ce qu'il faut : on baptise une compétence en la réglant, pas trois pages plus
// loin, et la page Textes garde la vue d'ensemble et les styles.
//
// UNE LIGNE PAR LANGUE. Ne proposer que la langue par défaut donnerait un nom
// changé d'un côté et resté vieux de l'autre, sans que rien le signale — la
// désynchronisation exacte que cette page doit éviter.
//
// La DESCRIPTION est en lecture seule ici : elle se rédige (avec ses styles, ses
// sauts de ligne) sur la page Textes, mais on doit la VOIR en réglant l'action,
// puisqu'elle promet au joueur ce que les champs du dessous font vraiment.
function textLines(section, id, refresh) {
  const block = el("div", "battle-texts");
  const withDesc = section !== "units";
  const { textId: nameId } = localizedText(section, id, "name");
  const { textId: descId, entry: descEntry } = localizedText(section, id, "desc");
  block.appendChild(
    sectionTitle(
      "Nom et description",
      withDesc ? `${nameId} · ${descId} — partagés avec la page Textes` : `${nameId}`
    )
  );
  for (const language of texts.languages || []) {
    const code = language.code;
    // Sans description — une unité n'en a pas — la ligne se resserre : garder la
    // troisième colonne laisserait un vide large comme la page à droite du nom.
    const line = el("div", withDesc ? "battle-text-line" : "battle-text-line battle-text-line-short");
    line.appendChild(el("span", "battle-text-lang", language.label || code));
    line.appendChild(
      textInput(localizedText(section, id, "name").entry?.translations?.[code] || "", (value) => {
        const entry = ensureText(section, id, "name");
        if (value) entry.translations[code] = value;
        else delete entry.translations[code];
        renderList();
        persistTexts();
      }, { placeholder: "sans nom" })
    );
    if (withDesc) {
      const description = descEntry?.translations?.[code] || "";
      const text = el("span", "battle-text-desc", description || "aucune description");
      if (!description) text.classList.add("battle-inline-hint");
      text.title = `${descId} — se rédige depuis la page Textes`;
      line.appendChild(text);
    }
    block.appendChild(line);
  }
  return block;
}

// ──────────────────────────────────────────────────────────────────────────
//  Rendu d'une entrée
// ──────────────────────────────────────────────────────────────────────────

// En-tête du panneau de droite. Le NOM DE JEU d'abord, en gros : c'est par lui
// qu'on reconnaît une entrée, alors que l'identifiant n'est qu'une clé de
// fichier — l'ancien en-tête ne montrait que celui-ci, en monospace.
function rowHead(section, id, badge) {
  const head = el("div", "battle-detail-head");
  const titles = el("div", "battle-detail-titles");
  const { label } = localizedName(section, id);
  titles.appendChild(el("h3", "battle-detail-name", label || id));
  const meta = el("div", "battle-detail-meta");
  meta.appendChild(el("code", "battle-id", id));
  if (badge) meta.appendChild(el("span", "battle-badge", badge));
  titles.appendChild(meta);
  head.appendChild(titles);

  const del = el("button", "modal-map-delete", "🗑");
  del.type = "button";
  del.title = `Supprimer cette ${SECTIONS[section].singular}`;
  del.onclick = async () => {
    if (!confirm(`Supprimer « ${id} » ?`)) return;
    delete entriesOf(section)[id];
    renderList();
    await persist(section);
  };
  head.appendChild(del);
  return head;
}

const STAT_FIELDS = [
  ["hp_max", "PV max"],
  ["ap_max", "PA max"],
  ["force", "Force"],
  ["defense", "Défense"],
  ["agility", "Agilité"],
  ["luck", "Chance"],
];

// ──────────────────────────────────────────────────────────────────────────
//  Planches d'animation
// ──────────────────────────────────────────────────────────────────────────

// Ce qui se règle sur une planche, hors vignettes (choisies sur l'image) et
// hors ancrage (qui a sa propre paire de champs).
const SHEET_FIELDS = [
  ["columns", "Colonnes", { min: 1 }],
  ["rows", "Lignes", { min: 1 }],
  ["fps", "Cadence (fps)", { min: 1 }],
];

// Planche NEUVE, en attendant l'image. `sheet` reste VIDE, et c'est délibéré :
// proposer le premier fichier du dossier — ce que faisait « + planche » —
// affecte en silence la planche d'un AUTRE personnage, et l'aperçu montre alors
// quelque chose de plausible et de faux. Une grille 1 × 1 est le seul découpage
// vrai d'une planche qu'on n'a pas encore mesurée, et il se corrige en deux
// champs ; l'import, lui, relève la vraie grille du même geste.
//
// `gesture` est vrai pour une planche créée depuis une ACTION : un geste se
// joue UNE fois, là où un état (repos, attente) tourne en boucle. Le défaut du
// moteur étant le bouclage, l'oublier fige le personnage en fin de geste.
function blankSheet(gesture = false) {
  const config = { sheet: "", columns: 1, rows: 1, frames: 1, fps: 6 };
  if (gesture) config.loop = false;
  return config;
}

function animationSummary(config) {
  const count = Math.max(1, Number(config.frames || 1));
  const parts = [
    `${count} vignette${count > 1 ? "s" : ""}`,
    `${Number(config.fps || 6)} fps`,
    config.loop === false ? "une fois" : "en boucle",
  ];
  if (config.hit_frame !== undefined) parts.push(`impact ${config.hit_frame}`);
  return parts.join(" · ");
}

function sheetUrl(path) {
  return sheetFiles.find((f) => f.path === path)?.url || null;
}

function animationsEditor(unitId, unit, onChanged) {
  const wrap = el("div", "battle-anims");
  if (!unit.animations) unit.animations = {};
  const names = Object.keys(unit.animations);

  if (names.length === 0) {
    wrap.appendChild(
      el("span", "battle-warning", "Aucune planche : l'unité n'a rien à afficher en combat.")
    );
  }
  // Ce que le moteur RÉCLAME et que l'unité n'a pas. Un état manquant ne lève
  // aucune erreur en jeu : le personnage garde simplement la planche qu'il
  // avait, ou ne bouge pas. Le dire ici est le seul endroit où ça se voit.
  const missing = animationStates.filter((st) => !(st.key in unit.animations));
  if (missing.length) {
    wrap.appendChild(
      el("p", "battle-inline-hint battle-anim-missing",
        "États sans planche : "
        + missing.map((st) => momentLabels.animation_labels?.[st.key] || st.key).join(", ")
        + ".")
    );
  }
  for (const name of names) {
    wrap.appendChild(animationBlock(unitId, unit, name, onChanged));
  }

  const add = el("button", "battle-chip-add", "+ planche");
  add.type = "button";
  add.onclick = () => {
    const name = prompt(
      "Nom de la planche (l'état se choisit ensuite dans le bloc ; reconnus par le "
        + `moteur : ${animationStates.map((st) => st.key).join(", ")}) :`
    );
    if (!name) return;
    if (!ID_PATTERN.test(name)) {
      alert("Nom invalide : minuscules, chiffres et « _ » seulement.");
      return;
    }
    if (unit.animations[name]) {
      alert(`« ${name} » existe déjà.`);
      return;
    }
    unit.animations[name] = blankSheet();
    openSheets.add(`units:${unitId}:${name}`);
    onChanged();
  };
  wrap.appendChild(add);
  return wrap;
}

// Une planche REPLIÉE garde son aperçu et son résumé : c'est la galerie des
// animations de l'unité, qui se parcourt à l'œil. Dépliée, elle ouvre ses dix
// champs — six planches dépliées d'un coup faisaient l'essentiel du mur.
function animationBlock(unitId, unit, name, onChanged, { state = true } = {}) {
  const config = unit.animations[name];
  const key = `units:${unitId}:${name}`;
  const open = openSheets.has(key);
  const block = el("div", "battle-block battle-anim");
  if (open) block.classList.add("open");

  const body = el("div", "battle-anim-body");
  const preview = animationPreview(config, sheetUrl(config.sheet), open);
  if (config.sheet) {
    preview.classList.add("sheet-preview-openable");
    preview.title = "Voir la planche entière";
    preview.onclick = () => openSheet(config, name, onChanged);
  }
  body.appendChild(preview);

  const column = el("div", "battle-anim-settings");
  body.appendChild(column);
  block.appendChild(body);

  const head = el("div", "battle-anim-head");
  const toggle = el("button", "battle-anim-toggle");
  toggle.type = "button";
  toggle.appendChild(el("span", "battle-anim-caret", open ? "▾" : "▸"));
  toggle.appendChild(el("span", "battle-id", name));
  toggle.appendChild(el("span", "battle-inline-hint", animationSummary(config)));
  // L'AVERTISSEMENT EST DANS L'EN-TÊTE, donc visible planche REPLIÉE, et il est
  // DANS le bouton : le geste qu'il appelle est justement d'ouvrir la planche.
  // Le réserver aux champs d'ancrage le rendrait invisible — ces blocs sont
  // repliés par défaut, et on n'ouvre pas celui qu'on ne soupçonne pas.
  const warning = el("span", "battle-warning");
  warning.hidden = true;
  toggle.appendChild(warning);
  anchorDrift(unit, name, config).then((drift) => {
    if (!drift) return;
    warning.hidden = false;
    warning.textContent = `⚠ ancrage : ${describeDrift(drift)}`;
    warning.title = drift.implicit
      ? "Aucun ancrage déclaré : le moteur prend le centre-bas de la cellule, "
        + "qui n'est juste que pour une cellule collée au dessin."
      : `Déclaré ${drift.declared.join(" / ")}, relevé sur l'ombre `
        + `${drift.measured.join(" / ")}.`;
  });
  toggle.onclick = () => {
    if (open) openSheets.delete(key);
    else openSheets.add(key);
    onChanged();
  };
  head.appendChild(toggle);
  const drop = el("button", "modal-map-delete", "🗑");
  drop.type = "button";
  drop.title = "Retirer cette planche";
  drop.onclick = () => {
    if (!confirm(`Retirer la planche « ${name} » de cette unité ?`)) return;
    delete unit.animations[name];
    openSheets.delete(key);
    onChanged();
  };
  head.appendChild(drop);
  column.appendChild(head);

  if (!open) return block;
  const settings = el("div", "battle-anim-fields");
  column.appendChild(settings);

  // L'ÉTAT NE SE CHANGE PAS DEPUIS UNE ACTION. Renommer la planche la
  // détacherait de l'action qu'on est en train de régler, sans rien dire — et
  // le bloc disparaîtrait sous la main de l'auteur. La liaison se change par le
  // champ « Planche » de l'action, qui est de l'autre bord de la même chaîne.
  if (state) settings.appendChild(stateLine(unitId, unit, name, onChanged));
  settings.appendChild(sheetLine(unitId, unit, config, name, onChanged));

  const grid = el("div", "battle-grid");
  for (const [key, label, options] of SHEET_FIELDS) {
    grid.appendChild(
      objectNumberField(config, key, label, { ...options, onCommit: onChanged })
    );
  }
  settings.appendChild(grid);
  settings.appendChild(gridLine(unit, name, config, onChanged));

  settings.appendChild(framesLine(config, name, onChanged));

  const options = el("div", "battle-grid");
  // Le bouclage est une propriété de la PLANCHE : un repos tourne en rond, un
  // geste se joue une fois. Absent = vrai, comme dans le moteur.
  options.appendChild(
    field(
      "En boucle",
      checkboxInput(config.loop !== false, (checked) => {
        if (checked) delete config.loop;
        else config.loop = false;
        onChanged();
      }),
      "Décoché : la planche se joue une seule fois (un geste d'attaque, une intro de victoire)."
    )
  );
  // `hit_frame` ne vaut que pour une planche de GESTE : c'est la vignette où le
  // coup porte. Facultatif — à défaut, le moteur prend le milieu.
  options.appendChild(
    objectNumberField(config, "hit_frame", "Vignette d'impact", {
      optional: true, min: 0, onCommit: onChanged,
      title: "Vignette où le coup porte, comptée dans l'extrait. Vide = le milieu du geste.",
    })
  );
  settings.appendChild(options);

  settings.appendChild(anchorLine(unit, name, config, onChanged));
  return block;
}

// Les vignettes se choisissent SUR L'IMAGE : `first_frame` et `frames`
// décrivent un extrait d'une grille qu'on ne voit pas, et les régler de tête
// demande de compter les cases sur l'image ouverte à côté.
// À QUEL MOMENT DU COMBAT cette planche se joue.
//
// Le moteur va chercher ses planches PAR LEUR NOM : `idle` quand l'unité
// attend, `atkeff` pendant qu'elle vise, `win_before` puis `win` à la victoire
// (cf. les constantes ANIM_* lues dans les .gd). Une planche nommée autrement
// reste valide — c'est ainsi qu'une action désigne la sienne — mais aucun état
// ne la jouera : elle ne s'anime que si une attaque ou un Eko l'appelle.
//
// Cette liste rend donc visible ce que la clé du fichier cachait : renommer
// « atk » en « attack » est un geste anodin dans un éditeur de texte, et il
// détache la planche de tout ce qui la réclamait.
function stateLine(unitId, unit, name, onChanged) {
  const line = el("div", "battle-anim-state-line");
  const taken = new Set(Object.keys(unit.animations).filter((n) => n !== name));
  const known = animationStates.map((s) => s.key);
  const values = [...known];
  // Le nom courant figure toujours dans la liste, même s'il n'est pas un état :
  // un `select` qui ne sait pas afficher sa propre valeur se présente vide, et
  // l'auteur croit que rien n'est réglé.
  if (!values.includes(name)) values.push(name);

  const select = selectInput(values, name, (value) => {
    if (value === name) return;
    if (taken.has(value)) {
      alert(`« ${value} » est déjà pris par une autre planche de cette unité.`);
      onChanged();
      return;
    }
    renameAnimation(unitId, unit, name, value);
    onChanged();
  }, {
    labelOf: (key) => {
      const label = momentLabels.animation_labels?.[key];
      if (label) return `${label} — ${key}`;
      return key === actionAnimationDefault
        ? `${key} (planche d'action, par défaut)`
        : `${key} (nom libre)`;
    },
    titleOf: (key) => animationStates.find((s) => s.key === key)?.note || "",
  });
  line.appendChild(field("État", select));

  const state = animationStates.find((s) => s.key === name);
  const hint = el("span", "battle-inline-hint");
  if (state) {
    hint.textContent = state.note
      ? `Jouée automatiquement : ${state.note.toLowerCase()}`
      : "Jouée automatiquement par le moteur.";
  } else {
    const users = actionsUsing(unit, name);
    hint.textContent = users.length
      ? `Planche d'action, appelée par : ${users.join(", ")}.`
      : "Nom libre, et personne ne l'appelle : aucune action ne joue cette planche.";
    if (!users.length) hint.classList.add("battle-warning");
  }
  line.appendChild(hint);
  return line;
}

// Qui réclame une planche par ce nom : l'attaque de base de l'unité affichée,
// et les Ekos du catalogue. Les objets n'en nomment pas.
//
// L'unité est passée en paramètre plutôt que relue dans `catalogs` : c'est le
// même objet que celui qu'on est en train d'éditer, donc à jour même avant
// l'enregistrement.
function actionsUsing(unit, name) {
  const users = [];
  const declared = unit.basic_attack?.animation || actionAnimationDefault;
  if (declared === name) users.push("l'attaque de base");
  for (const [id, eko] of Object.entries(entriesOf("ekos"))) {
    if ((eko.animation || actionAnimationDefault) === name) users.push(id);
  }
  return users;
}

// Renomme une planche SANS la déplacer dans le fichier : une clé supprimée puis
// réécrite reviendrait en fin d'objet, et un simple changement d'état ferait un
// diff illisible. On reconstruit donc la table dans le même ordre.
//
// L'attaque de base de l'unité suit le renommage : elle désigne sa planche par
// ce nom, et elle appartient à la même unité — il n'y a pas d'ambiguïté. Les
// Ekos, eux, sont PARTAGÉS entre personnages : les réécrire depuis ici
// changerait la planche de tout le monde.
function renameAnimation(unitId, unit, from, to) {
  const rebuilt = {};
  for (const [key, value] of Object.entries(unit.animations)) {
    rebuilt[key === from ? to : key] = value;
  }
  unit.animations = rebuilt;
  if (unit.basic_attack && unit.basic_attack.animation === from) {
    unit.basic_attack.animation = to;
  }
  const oldKey = `units:${unitId}:${from}`;
  if (openSheets.delete(oldKey)) openSheets.add(`units:${unitId}:${to}`);
}

// Choix de la planche, et import d'une nouvelle. Les deux vont ensemble : c'est
// en cherchant un fichier dans la liste qu'on découvre qu'il n'y est pas, et
// envoyer l'auteur copier un PNG à la main dans Sprites/Battle — puis rouvrir
// Godot pour l'importer — casse net ce qu'il était en train de faire.
function sheetLine(unitId, unit, config, name, onChanged) {
  const line = el("div", "battle-sheet-line");
  line.appendChild(
    field(
      "Fichier",
      selectInput(
        sheetFiles.map((f) => f.path), config.sheet || "",
        (value) => {
          config.sheet = value;
          onChanged();
        },
        { labelOf: sheetLabel }
      )
    )
  );
  line.appendChild(importButton(unitId, unit, config, name, onChanged));
  // Une planche que Godot n'a pas importée existe sur le disque et reste
  // INVISIBLE EN JEU : le dire ici, là où on la choisit, plutôt que de laisser
  // l'auteur découvrir un personnage vide au combat.
  const entry = sheetFiles.find((f) => f.path === config.sheet);
  if (entry && entry.imported === false) {
    line.appendChild(
      el("p", "battle-warning", "Godot n'a pas encore importé cette planche : "
        + "elle ne s'affichera pas en jeu tant que l'éditeur Godot n'aura pas été ouvert.")
    );
  }
  return line;
}

// Le nom de fichier suffit à se repérer — les planches vivent toutes dans le
// même dossier — sauf pour celles que Godot ignore encore, qu'on marque.
function sheetLabel(path) {
  const file = path.split("/").pop();
  const entry = sheetFiles.find((f) => f.path === path);
  return entry && entry.imported === false ? `${file} (non importée)` : file;
}

// Le nom de destination suit la convention du dossier : <unité>_<planche>.png
// (noah_idle.png, iris_win_before.png). Proposé, pas imposé — l'auteur peut
// garder le nom d'origine, qui est souvent un numéro d'export (313000404_atk).
function suggestedSheetName(unitId, name) {
  return `${unitId || "unite"}_${name}.png`.toLowerCase().replace(/[^a-z0-9_.-]/g, "_");
}

function importButton(unitId, unit, config, name, onChanged) {
  const button = el("button", "text-btn", "Importer une planche…");
  button.type = "button";
  button.title = "Déposer un PNG dans Sprites/Battle et l'affecter à cette planche.";
  const picker = el("input");
  picker.type = "file";
  picker.accept = "image/png,.png";
  picker.hidden = true;
  picker.onchange = async () => {
    const file = picker.files && picker.files[0];
    // Le champ est remis à zéro tout de suite : sans ça, réimporter DEUX FOIS
    // le même fichier ne déclencherait pas de second `change`.
    picker.value = "";
    if (!file) return;
    const wanted = prompt(
      "Nom du fichier dans Sprites/Battle :", suggestedSheetName(unitId, name)
    );
    if (!wanted) return;
    button.disabled = true;
    button.textContent = "Import en cours…";
    try {
      let result;
      try {
        result = await uploadBattleSheet(file, wanted);
      } catch (err) {
        // 409 : le fichier existe. C'est la seule erreur qui vaut une seconde
        // chance, et elle doit être posée explicitement — écraser une planche
        // déjà utilisée par d'autres animations ne se devine pas.
        if (!String(err.message).includes("existe déjà")) throw err;
        if (!confirm(`${err.message} L'écraser ?`)) return;
        result = await uploadBattleSheet(file, wanted, { overwrite: true });
      }
      sheetFiles = await getBattleSheets();
      config.sheet = result.path;
      // Réimport PAR-DESSUS un nom existant : tout ce qui est mémorisé sous
      // cette URL décrit l'image d'AVANT. Le chemin, lui, n'a pas changé — donc
      // rien ne se périme tout seul, et le contrôle d'ancrage afficherait le
      // verdict rendu sur l'ancienne image.
      forgetSheetSize(result.url);
      forgetSheetPixels(result.url);
      anchorChecks.clear();
      const measured = await applyMeasuredGrid(unit, name, config, result.url, true);
      if (!result.imported) {
        alert(
          "Le fichier est en place, mais Godot ne l'a pas importé : ouvre "
          + "l'éditeur Godot une fois pour qu'il s'affiche en jeu."
        );
      } else if (measured === null) {
        alert("La grille n'a pas pu être relevée : règle les colonnes et les lignes à la main.");
      }
      onChanged();
    } catch (err) {
      alert(`Import impossible : ${err.message}`);
    } finally {
      button.disabled = false;
      button.textContent = "Importer une planche…";
    }
  };
  button.onclick = () => picker.click();
  const holder = el("span", "battle-sheet-import");
  holder.appendChild(button);
  holder.appendChild(picker);
  return holder;
}

// Le découpage relevé, et la taille de vignette qui en découle.
//
// LA TAILLE DE VIGNETTE N'EST PAS UNE DONNÉE : elle se déduit de l'image et du
// découpage (le moteur fait exactement ce calcul, en division entière). La
// montrer plutôt que de l'inventer en champ évite deux vérités concurrentes —
// mais il faut bien la MONTRER : « 3 colonnes, 7 lignes » ne dit pas si les
// vignettes font 75 × 94 ou 25 × 31, alors que c'est ce chiffre-là qu'on
// compare à la planche source ouverte à côté.
function gridLine(unit, name, config, onChanged) {
  const line = el("div", "battle-anim-grid-line");
  const note = el("span", "battle-inline-hint", "Vignette : …");
  const describe = () => {
    const columns = Math.max(1, Number(config.columns || 1));
    const rows = Math.max(1, Number(config.rows || 1));
    sheetSize(sheetUrl(config.sheet)).then((size) => {
      if (!size) {
        note.textContent = "Vignette : taille inconnue (image illisible).";
        return;
      }
      const w = Math.floor(size[0] / columns);
      const h = Math.floor(size[1] / rows);
      // Un découpage qui ne tombe pas juste est un PIÈGE silencieux : le moteur
      // tronque, et toutes les vignettes après la première ligne glissent.
      const exact = size[0] % columns === 0 && size[1] % rows === 0;
      note.textContent = `Planche ${size[0]}×${size[1]} — vignette ${w}×${h} px`
        + (exact ? "" : " ⚠ le découpage ne tombe pas juste");
      note.classList.toggle("battle-warning", !exact);
    });
  };
  describe();

  const auto = el("button", "text-btn", "Automatique");
  auto.type = "button";
  auto.title = "Relever sur l'image : colonnes, lignes, vignettes, et l'ancrage au sol.";
  auto.disabled = !config.sheet;
  auto.onclick = async () => {
    const url = sheetUrl(config.sheet);
    if (!url) return;
    auto.disabled = true;
    auto.textContent = "Relevé en cours…";
    const grid = await applyMeasuredGrid(unit, name, config, url);
    if (grid === null) {
      auto.disabled = false;
      auto.textContent = "Automatique";
      alert("La grille n'a pas pu être relevée sur cette image.");
      return;
    }
    onChanged();
  };
  line.appendChild(auto);
  line.appendChild(note);
  return line;
}

// Relève la grille sur l'image et la pose dans la planche. Sert à l'import
// comme au bouton « Automatique » : c'est le même geste, une fois subi et une
// fois demandé. Rend la grille mesurée, ou null si la lecture a échoué.
//
// CE QUI EST REMIS À ZÉRO, ET POURQUOI. `frames` et `first_frame` sont des
// CHOIX D'AUTEUR — l'extrait qu'il retient d'une planche — et on n'y touche que
// si la grille a bougé, auquel cas ils désignent des cases qui n'existent plus.
// L'ancrage, lui, est une MESURE : rien n'est gagné à garder celle d'hier quand
// on peut refaire celle d'aujourd'hui.
//
// D'où `remeasureAnchor`, que l'import passe et que « Automatique » ne passe
// pas. L'IMPORT CHANGE L'IMAGE : l'ancrage d'avant a été relevé sur une autre,
// il est caduc même si la grille tombe pareil. « Automatique » ne change rien à
// l'image, et re-relever écraserait sans prévenir les ancrages posés
// DÉLIBÉRÉMENT à côté du relevé (noah/standby est 1 px plus haut, exprès).
//
// LE RACCOURCI « MÊME GRILLE » A DÉJÀ LAISSÉ PASSER LE BUG UNE FOIS. Une
// planche importée dans un emplacement NEUF part de colonnes et lignes
// indéfinies, donc lues comme 1 × 1 ; une planche à vignette unique mesure
// 1 × 1 ; la grille était donc « inchangée » et l'ancrage n'était jamais
// relevé. C'est exactement ce qui est arrivé à `noah_approach`.
async function applyMeasuredGrid(unit, name, config, url, remeasureAnchor = false) {
  // La convention du « vide » se lit sur la planche elle-même : un effet joué
  // en fusion additive est peint sur du NOIR, pas détouré, et le relevé par
  // l'alpha n'y trouverait aucune coupe (cf. sheet-grid.measureGrid).
  const grid = await measureGrid(url, { onDark: config.blend === "add" });
  if (grid === null) return null;
  const same = Number(config.columns || 1) === grid.columns
    && Number(config.rows || 1) === grid.rows;
  config.columns = grid.columns;
  config.rows = grid.rows;
  if (!same) {
    config.frames = grid.frames;
    delete config.first_frame;
  }
  if (remeasureAnchor || !same) {
    // L'ancrage est RELEVÉ, plus seulement effacé. Le laisser au défaut était
    // un piège silencieux : le centre-bas n'est juste que pour une cellule
    // collée au dessin, et une planche de geste réserve de la place. Celle
    // d'attaque d'Iris garde 23 px sous les pieds — le personnage flottait
    // 18 px au-dessus du sol, et c'est exactement comme ça que le bug s'est vu.
    const anchor = await measureAnchor(unit, name, config);
    if (anchor === null) delete config.anchor;
    else config.anchor = anchor;
  }
  return grid;
}

// La planche dont l'ancrage sert de RÉFÉRENCE à toutes les autres.
const ANCHOR_REFERENCE = "idle";

// Écart toléré, en pixels, entre l'ancrage déclaré et le relevé sur l'ombre.
//
// 1 px et pas 0 : deux ancrages du projet sont posés DÉLIBÉRÉMENT un pixel à
// côté du relevé — le `standby` de Noah est remonté d'un pixel, son
// `win_before` est relevé sur la dernière vignette et non la première, et leurs
// commentaires le disent. Avertir sur ces deux-là apprendrait à ignorer
// l'avertissement, ce qui est exactement ce qu'on ne veut pas.
const ANCHOR_TOLERANCE = 1;

// Relevés déjà faits, par configuration. La liste se reconstruit à CHAQUE
// changement — une frappe dans un champ redessine toutes les planches de
// l'unité — et un relevé décode deux images. Sans ce cache, éditer un champ
// ferait relire une dizaine de PNG à chaque caractère.
const anchorChecks = new Map();

// Assez pour toutes les planches de toutes les unités, et une borne quand même :
// chaque réglage d'un champ d'ancrage crée une clé de plus, et une session
// d'atelier en empile sans fin. Ce sont trois nombres par entrée — la borne est
// là contre la fuite, pas contre le coût.
const ANCHOR_CHECK_LIMIT = 200;

function anchorCheckKey(unit, name, config) {
  const reference = unit.animations?.[ANCHOR_REFERENCE];
  return JSON.stringify([
    name, config.sheet, config.columns, config.rows, config.first_frame, config.anchor,
    reference?.sheet, reference?.columns, reference?.rows, reference?.anchor,
  ]);
}

// L'ÉCART entre l'ancrage que la planche porte vraiment et celui que l'ombre
// dicte. Rend null quand tout va bien (ou quand rien n'est mesurable).
//
// POURQUOI CE CONTRÔLE EXISTE. Un ancrage faux ne casse rien, n'affiche aucune
// erreur, et ne se voit qu'en lançant le combat et en amenant ce personnage
// dans cet état-là. Il est arrivé deux fois de suite qu'une planche parte en
// production avec le défaut du moteur et fasse flotter Iris 18 px au-dessus du
// sol. Ce que la page peut mesurer, la page doit le signaler.
async function anchorDrift(unit, name, config) {
  const key = anchorCheckKey(unit, name, config);
  if (anchorChecks.has(key)) return anchorChecks.get(key);
  const pending = (async () => {
    const measured = await measureAnchor(unit, name, config);
    if (measured === null) return null;
    const declared = await effectiveAnchor(config);
    if (declared === null) return null;
    const dx = declared[0] - measured[0];
    const dy = declared[1] - measured[1];
    if (Math.abs(dx) <= ANCHOR_TOLERANCE && Math.abs(dy) <= ANCHOR_TOLERANCE) return null;
    return { dx, dy, measured, declared, implicit: !Array.isArray(config.anchor) };
  })();
  if (anchorChecks.size >= ANCHOR_CHECK_LIMIT) {
    anchorChecks.delete(anchorChecks.keys().next().value);
  }
  anchorChecks.set(key, pending);
  return pending;
}

// L'écart dit DANS QUEL SENS LE PERSONNAGE PART, pas en coordonnées de cellule.
// « ancrage Y trop grand de 18 » ne se relie à rien ; « 18 px trop haut » se
// vérifie d'un coup d'œil sur la capture. L'ancrage étant le point de la
// cellule posé au sol, l'augmenter TIRE le dessin dans l'autre sens.
function describeDrift(drift) {
  const parts = [];
  if (drift.dx) parts.push(`${Math.abs(drift.dx)} px trop à ${drift.dx > 0 ? "gauche" : "droite"}`);
  if (drift.dy) parts.push(`${Math.abs(drift.dy)} px trop ${drift.dy > 0 ? "haut" : "bas"}`);
  return parts.join(", ");
}

// Relève l'ancrage d'une planche sur son ombre, RELATIVEMENT à la planche de
// repos de la même unité. Rend la paire, ou null si le relevé n'aboutit pas.
//
// POURQUOI UNE RÉFÉRENCE ET PAS UNE RÈGLE ABSOLUE. Le point au sol d'une unité
// est une convention arbitraire — chez Noah il tombe 7,5 px à gauche du milieu
// de son ombre, chez Iris 1,5 px à droite — fixée une bonne fois par la planche
// de repos. Ce qui doit être vrai n'est donc pas « le point au sol est au
// milieu de l'ombre », c'est « le personnage NE SAUTE PAS en changeant de
// planche » : même écart à l'ombre que sur `idle`. C'est aussi, mot pour mot,
// la méthode que les commentaires de units.json décrivent à la main.
//
// VALIDÉ AVANT D'ÊTRE UTILISÉ, sur les dix ancrages déjà déclarés : l'ordonnée
// tombe juste sur neuf — le dixième, noah/standby, est relevé 1 px plus haut
// DÉLIBÉRÉMENT et son commentaire le dit — et l'abscisse sur quatre, à 2 px
// près sur trois autres. Les deux écarts restants sont précisément ceux dont le
// commentaire dit déjà que la première vignette est le mauvais repère : l'ombre
// d'iris/win_before fusionne avec celle de sa mascotte, celle d'iris/atk dérive
// de 57 px pendant le recul du tir. D'où des champs qui restent MODIFIABLES :
// le relevé est un point de départ juste, pas un verdict.
async function measureAnchor(unit, name, config) {
  if (name === ANCHOR_REFERENCE) return null;
  const reference = unit.animations?.[ANCHOR_REFERENCE];
  if (!reference || !reference.sheet) return null;
  const here = await groundOf(config);
  const there = await groundOf(reference);
  if (here === null || there === null) return null;
  const base = await effectiveAnchor(reference);
  if (base === null) return null;
  return [
    Math.round(here.x + base[0] - there.x),
    Math.round(here.bottom + base[1] - there.bottom),
  ];
}

async function groundOf(config) {
  const url = sheetUrl(config.sheet);
  if (!url) return null;
  const { columns, rows } = gridOf(config);
  return measureGround(url, columns, rows, Number(config.first_frame || 0));
}

function gridOf(config) {
  return {
    columns: Math.max(1, Number(config.columns || 1)),
    rows: Math.max(1, Number(config.rows || 1)),
  };
}

// L'ancrage qu'une planche a VRAIMENT — celui qu'elle déclare, ou le centre-bas
// que le moteur lui donne à défaut. La référence n'en déclare souvent aucun
// (`idle` se contente du défaut chez les trois unités) : lire `config.anchor`
// seul rendrait alors zéro et enverrait toutes les autres planches une
// demi-cellule trop à gauche.
async function effectiveAnchor(config) {
  if (Array.isArray(config.anchor)) return config.anchor;
  const size = await sheetSize(sheetUrl(config.sheet));
  if (!size) return null;
  const { columns, rows } = gridOf(config);
  return [Math.floor(size[0] / columns / 2), Math.floor(size[1] / rows)];
}

function framesLine(config, name, onChanged) {
  const line = el("div", "battle-anim-frames");
  const first = Number(config.first_frame || 0);
  const count = Number(config.frames || 1);
  const last = first + count - 1;
  line.appendChild(el("span", "battle-field-label", "Vignettes"));
  line.appendChild(
    el("span", "battle-note-static", count === 1 ? `${first}` : `${first} → ${last}`)
  );
  line.appendChild(el("span", "battle-inline-hint", `${count} vignette${count > 1 ? "s" : ""}`));

  const url = sheetUrl(config.sheet);
  const choose = el("button", "text-btn", "Voir la planche…");
  choose.type = "button";
  choose.disabled = !url;
  choose.title = url
    ? "Ouvrir la planche en grand : s'y déplacer, et y choisir l'extrait."
    : "Aucune image : choisis d'abord un fichier.";
  choose.onclick = () => openSheet(config, name, onChanged);
  line.appendChild(choose);
  return line;
}

// La fenêtre de planche s'ouvre de DEUX endroits — le bouton de la ligne des
// vignettes, et l'aperçu lui-même. Le second n'est pas un doublon : quand on
// veut voir une pose en grand, on regarde déjà l'aperçu, et aller chercher un
// bouton trois lignes plus bas est un détour.
async function openSheet(config, name, onChanged) {
  const url = sheetUrl(config.sheet);
  if (!url) return;
  const picked = await pickFrames(url, {
    columns: Number(config.columns || 1),
    rows: Number(config.rows || 1),
    first: Number(config.first_frame || 0),
    count: Number(config.frames || 1),
    name,
  });
  if (!picked) return;
  // `first_frame` à 0 est le cas courant : on ne l'écrit pas, comme le moteur
  // qui le lit avec ce défaut (cf. objectNumberField).
  // Retenir la vignette 0 EFFACE la clé (cf. objectNumberField), et la
  // réécrire plus tard la remet en fin d'objet : un aller-retour par zéro
  // déplace `first_frame` dans le fichier sans rien changer à la donnée.
  if (picked.first_frame) config.first_frame = picked.first_frame;
  else delete config.first_frame;
  config.frames = picked.frames;
  onChanged();
}

// L'ancrage est le point de la CELLULE qui se pose sur l'emplacement au sol. Il
// se relève sur l'ellipse d'ombre, à l'atelier — d'où deux champs et pas un
// choix sur l'image : le sélecteur de vignettes ne mesure rien.
//
// QUAND RIEN N'EST DÉCLARÉ, les champs montrent le défaut du MOTEUR (le
// centre-bas de la cellule), pas zéro. Afficher 0/0 était un piège : l'auteur
// qui corrigeait l'ordonnée d'un pixel écrivait du même coup une abscisse de 0
// et déplaçait le personnage d'une demi-cellule — exactement le saut que
// l'ancrage existe pour éviter.
function anchorLine(unit, name, config, onChanged) {
  const line = el("div", "battle-grid");
  const declared = Array.isArray(config.anchor) ? config.anchor : null;
  const inputs = [];
  const commit = (index, value) => {
    // La paire est écrite ENTIÈRE : la valeur de l'autre champ est celle qui
    // est affichée, donc le défaut quand rien n'était déclaré.
    const pair = inputs.map((input) => parseInt(input.value, 10) || 0);
    pair[index] = value;
    config.anchor = pair;
    onChanged();
  };
  for (const [index, label] of [[0, "Ancrage X"], [1, "Ancrage Y"]]) {
    const input = numberInput(declared ? declared[index] : 0, (v) => commit(index, v), {});
    inputs.push(input);
    line.appendChild(
      field(
        label,
        input,
        index === 0
          ? "Point de la cellule posé sur l'emplacement au sol, relevé sur l'ellipse d'ombre. Sans valeur déclarée, c'est le centre-bas de la cellule."
          : null
      )
    );
  }
  if (!declared) {
    // La taille de la cellule n'est connue qu'une fois l'image chargée : les
    // champs partent donc à 0 et se corrigent, plutôt que de retarder toute la
    // ligne pour deux nombres.
    sheetSize(sheetUrl(config.sheet)).then((size) => {
      if (!size) return;
      const columns = Math.max(1, Number(config.columns || 1));
      const rows = Math.max(1, Number(config.rows || 1));
      inputs[0].value = String(Math.floor(size[0] / columns / 2));
      inputs[1].value = String(Math.floor(size[1] / rows));
      for (const input of inputs) input.classList.add("battle-input-default");
    });
  }
  // Le relevé est accessible SANS réimporter. Les planches déjà en place sont
  // le cas majoritaire, et jusqu'ici seul un changement de grille déclenchait la
  // mesure : une planche posée avant ce relevé n'avait aucun moyen d'y accéder,
  // sinon en cassant sa propre grille pour la refaire.
  const measure = el("button", "text-btn", "Relever sur l'ombre");
  measure.type = "button";
  measure.disabled = !config.sheet || name === ANCHOR_REFERENCE;
  measure.title = name === ANCHOR_REFERENCE
    ? "La planche de repos est la RÉFÉRENCE : c'est son ancrage qui définit où l'unité se tient, il n'y a rien au-dessus de quoi le relever."
    : "Poser l'ancrage pour que l'ombre tombe au même endroit que sur la planche de repos — le personnage ne saute pas en changeant d'état.";
  measure.onclick = async () => {
    measure.disabled = true;
    measure.textContent = "Relevé en cours…";
    const anchor = await measureAnchor(unit, name, config);
    if (anchor === null) {
      measure.disabled = false;
      measure.textContent = "Relever sur l'ombre";
      alert(
        "L'ancrage n'a pas pu être relevé : aucune ombre reconnaissable sur "
        + `cette planche ou sur « ${ANCHOR_REFERENCE} ». Règle les deux champs à la main.`
      );
      return;
    }
    config.anchor = anchor;
    onChanged();
  };
  line.appendChild(measure);

  // Le relevé est AFFICHÉ à côté des champs, pas seulement applicable. Un
  // avertissement qui ne dit pas quelle valeur il attend oblige à cliquer pour
  // savoir — et donc à écraser la valeur en place pour la comparer.
  const reading = el("span", "battle-inline-hint", "");
  reading.hidden = true;
  line.appendChild(reading);
  anchorDrift(unit, name, config).then((drift) => {
    if (!drift) return;
    reading.hidden = false;
    reading.className = "battle-warning";
    reading.textContent = `Relevé sur l'ombre : ${drift.measured.join(" / ")}`
      + ` — l'ancrage en place dessine ${describeDrift(drift)}.`;
  });

  const clear = el("button", "text-btn", "Défaut (centre-bas)");
  clear.type = "button";
  clear.disabled = !declared;
  clear.title = "Retire l'ancrage déclaré : le moteur reprend le centre-bas de la cellule.";
  clear.onclick = () => {
    delete config.anchor;
    onChanged();
  };
  line.appendChild(clear);
  return line;
}

function renderUnit(id, unit, refresh) {
  const row = el("div", "battle-row");
  row.appendChild(rowHead("units", id, unit.behaviour ? "ennemi" : null));
  row.appendChild(textLines("units", id, refresh));

  const stats = el("div", "battle-grid battle-stats");
  if (!unit.stats) unit.stats = {};
  for (const [key, label] of STAT_FIELDS) {
    stats.appendChild(
      field(
        label,
        numberInput(unit.stats[key] ?? 0, (v) => {
          unit.stats[key] = v;
          refresh();
        }, { min: 0 }),
        key === "ap_max" ? "Plafond du système : 5 (la rangée de losanges ne va pas au-delà)." : null
      )
    );
  }
  row.appendChild(sectionTitle("Statistiques"));
  row.appendChild(stats);

  // Les planches sont en LECTURE SEULE : leur grille, leur ancrage et leur
  // fourchette de frames se relèvent au pixel sur l'image (cf. CLAUDE.md), ce
  // qu'un formulaire web ne peut pas faire — proposer de les saisir à la main
  // inviterait à poser des valeurs plausibles et fausses.
  const sheets = Object.keys(unit.animations || {});
  row.appendChild(
    sectionTitle("Planches", "grille et ancrage se relèvent à l'atelier")
  );
  row.appendChild(animationsEditor(id, unit, refresh));

  if (!unit.basic_attack) unit.basic_attack = {};
  row.appendChild(
    actionBlock("Attaque de base", unit.basic_attack, ["heal"], sheets, refresh, {
      sounds: false,
      performers: [id],
      // Le nom du personnage sert de préfixe aux fichiers qu'on importe depuis
      // ici (noah_impact.png) et de base aux noms de planche qu'on y crée.
      suggestion: id,
    })
  );

  // UNE SEULE liste pour tous les sons du personnage : ceux de son geste
  // d'attaque et ceux qui lui appartiennent en propre. Elle est posée au niveau
  // de l'unité et non dans le bloc « Attaque de base », qui n'en porte que la
  // moitié — c'est le moment choisi, et lui seul, qui dit de quoi il s'agit.
  row.appendChild(sectionTitle("Sons", "geste de l'attaque et voix du personnage"));
  // Les moments inatteignables de l'attaque de base se disent ICI et pas dans
  // son bloc : c'est ici que sont ses sons.
  const unreachable = unreachableLine(unit.basic_attack);
  if (unreachable) row.appendChild(unreachable);
  row.appendChild(
    soundsEditor([actionFamily(unit.basic_attack), unitFamily(unit)], refresh)
  );

  // Ekos connus : des cases à cocher sur le catalogue réel, jamais une saisie
  // d'identifiant — un id qui n'existe pas ne produirait qu'une entrée de menu
  // vide, découverte en jeu.
  row.appendChild(sectionTitle("Ekos connus"));
  const ekos = el("div", "battle-checks");
  const known = unit.ekos || [];
  for (const ekoId of Object.keys(entriesOf("ekos"))) {
    const label = el("label", "battle-check");
    const box = el("input");
    box.type = "checkbox";
    box.checked = known.includes(ekoId);
    box.onchange = () => {
      if (!unit.ekos) unit.ekos = [];
      if (box.checked) unit.ekos.push(ekoId);
      else unit.ekos = unit.ekos.filter((e) => e !== ekoId);
      refresh();
    };
    label.appendChild(box);
    label.appendChild(el("span", null, ekoId));
    ekos.appendChild(label);
  }
  row.appendChild(ekos);
  row.appendChild(knownEkoSounds(id, unit));

  row.appendChild(behaviourBlock(id, unit, refresh));
  return row;
}

// Fichiers qu'une action fait entendre à un moment donné, POUR UN LANCEUR DONNÉ.
//
// Même règle que le moteur, et pas une approximation : les entrées réservées à
// ce personnage passent devant celles de tout le monde, et `pick()` s'arrête à
// la première qui porte le moment (cf. BattleData.sounds_of et pick). Ce qu'on
// affiche ici est donc ce qu'on entendra, pas la liste de ce qui existe.
function soundsAt(action, moment, performer = "") {
  const matching = (action?.sounds || []).filter((entry) => (entry.at || "hit") === moment);
  const applies = matching.filter((entry) => {
    const only = soundUnits(entry);
    return only.length === 0 || (performer !== "" && only.includes(performer));
  });
  const named = applies.filter((entry) => soundUnits(entry).length > 0);
  const chosen = named.length > 0 ? named[0] : applies[0];
  return chosen ? soundPaths(chosen) : [];
}

// CE QUE CHAQUE EKO CONNU FAIT ENTENDRE QUAND IL PART, vu depuis la fiche du
// personnage — avec le raccourci pour aller le régler.
//
// POURQUOI ICI, alors que le réglage vit sur l'Eko. La question se pose dans ce
// sens-là : « quand Noah lance Fulgura, qu'est-ce qu'on entend ? ». Y répondre
// obligeait à ouvrir les Ekos un par un pour voir lequel porte un son, et rien
// sur cette page ne disait que le son d'un Eko se règle sur l'Eko. Le tableau
// le montre et le dit.
//
// Le son appartient À LA COMPÉTENCE et pas à celui qui la lance : Noah et Iris
// qui connaissent le même Eko entendent le même fracas. C'est le même parti
// pris que la puissance et la séquence, qui vivent aussi sur l'Eko.
function knownEkoSounds(unitId, unit) {
  const block = el("div", "battle-block");
  const known = unit.ekos || [];
  block.appendChild(
    sectionTitle(
      "Son du geste, par Eko",
      "ce que CE personnage fait entendre : le son commun de l'Eko, ou le sien s'il en a un"
    )
  );
  if (known.length === 0) {
    block.appendChild(el("p", "battle-inline-hint", "Aucun Eko connu."));
    return block;
  }
  const table = el("div", "battle-eko-sounds");
  for (const ekoId of known) {
    const eko = entriesOf("ekos")[ekoId];
    const line = el("div", "battle-eko-sound");
    const open = el("button", "battle-eko-link", localizedName("ekos", ekoId).label || ekoId);
    open.type = "button";
    open.title = `Ouvrir « ${ekoId} » pour régler ses sons`;
    open.onclick = () => goToEntry("ekos", ekoId);
    line.appendChild(open);
    // L'ID À CÔTÉ DU NOM, comme dans l'index : les cases à cocher juste
    // au-dessus cochent des ids (`tempeste`) et le nom affiché est celui du
    // catalogue de textes (« Gale »). Sans le rappel, les deux listes ne se
    // recoupent pas à la lecture.
    line.appendChild(el("span", "battle-index-id", ekoId));
    if (!eko) {
      line.appendChild(el("span", "battle-warning", `« ${ekoId} » n'est pas au catalogue.`));
    } else {
      const paths = soundsAt(eko, "gesture", unitId);
      if (paths.length === 0) {
        line.appendChild(el("span", "battle-inline-hint", "aucun son au geste"));
      } else {
        for (const path of paths) {
          const file = el("span", "battle-eko-sound-file");
          file.appendChild(playButton(() => path));
          const name = el("span", "battle-sound-path", soundLabel(path));
          name.title = path;
          file.appendChild(name);
          line.appendChild(file);
        }
        if (paths.length > 1) {
          line.appendChild(el("span", "battle-inline-hint", "variantes tirées au hasard"));
        }
        // Dire QUAND le son est réservé : sans ça, deux personnages affichent
        // deux fichiers différents sans qu'on sache d'où vient la différence.
        if (soundsAt(eko, "gesture", "").join() !== paths.join()) {
          line.appendChild(el("span", "battle-badge", "à lui"));
        }
      }
    }
    table.appendChild(line);
  }
  block.appendChild(table);
  return block;
}

// Le bloc `behaviour` ne concerne QUE les ennemis : il dit comment ils
// choisissent leur action, faute de phase de préparation. Sa présence est donc
// aussi ce qui distingue un ennemi d'un allié dans le catalogue — d'où une
// case à cocher pour l'ajouter ou le retirer, et pas un champ toujours là.
function behaviourBlock(id, unit, refresh) {
  const block = el("div", "battle-block");
  const head = el("label", "battle-check");
  const box = el("input");
  box.type = "checkbox";
  box.checked = Boolean(unit.behaviour);
  box.onchange = () => {
    if (box.checked) unit.behaviour = { kind: "random" };
    else delete unit.behaviour;
    refresh();
  };
  head.appendChild(box);
  head.appendChild(el("span", "battle-block-title", "Comportement (ennemi)"));
  block.appendChild(head);

  if (!unit.behaviour) return block;
  const behaviour = unit.behaviour;
  const grid = el("div", "battle-grid");

  grid.appendChild(
    field(
      "Type",
      selectInput(vocabulary.behaviours, behaviour.kind || "random", (v) => {
        behaviour.kind = v;
        refresh();
      }),
      "random : au hasard · aggressive : le plus entamé en proportion · defensive : se garde sous un seuil · focused : s'acharne sur une unité"
    )
  );

  if (behaviour.kind === "focused") {
    // La cible d'un `focus` se choisit dans la liste des unités, pas en tapant
    // son id : nommer quelqu'un qui n'existe pas ferait frapper au hasard sans
    // rien dire.
    const others = Object.keys(entriesOf("units")).filter((u) => u !== id);
    grid.appendChild(
      field(
        "S'acharne sur",
        selectInput(others, behaviour.focus, (v) => {
          behaviour.focus = v;
          refresh();
        }, { empty: "(personne)" }),
        "Si elle est tombée, il frappe au hasard plutôt que de perdre son tour."
      )
    );
  }

  if (behaviour.kind === "defensive") {
    grid.appendChild(
      field(
        "Se garde sous",
        numberInput(behaviour.guard_below ?? 0.35, (v) => {
          behaviour.guard_below = v;
          refresh();
        }, { min: 0, step: 0.05 }),
        "Proportion de PV restants. 0,35 par défaut."
      )
    );
  }

  grid.appendChild(
    objectNumberField(behaviour, "eko_chance", "Chance d'Eko", {
      optional: true,
      min: 0,
      step: 0.05,
      title: "0 par défaut : déclarer des Ekos ne suffit pas, il faut aussi dire qu'il s'en sert.",
      onCommit: refresh,
    })
  );

  block.appendChild(grid);
  return block;
}

function renderAction(section, id, action, refresh) {
  // Le geste d'une action s'écrit dans units.json, pas dans le catalogue qu'on
  // parcourt : cette commande-là enregistre donc les DEUX fichiers.
  const refreshGesture = refresher("units");
  const row = el("div", "battle-row");
  row.appendChild(rowHead(section, id, null));
  row.appendChild(textLines(section, id, refresh));
  const performers = performersOf(section, id);
  row.appendChild(el("p", "battle-action-summary", actionSummary(section, action)));
  if (section === "ekos") row.appendChild(knownByLine(id, performers));
  const fields = section === "ekos" ? ["ap_cost", "target", "heal"] : ["target", "heal"];
  row.appendChild(
    actionBlock("Effet", action, fields, allAnimationNames(), refresh, {
      performers,
      // Un Eko qui veut son propre geste le nomme comme lui : c'est la
      // convention naturelle, et elle se relit d'un coup d'œil dans units.json.
      suggestion: id,
      onGestureChanged: refreshGesture,
    })
  );
  return row;
}

// QUI CONNAÎT CET EKO, et le chemin pour aller le voir. Le pendant exact du
// tableau « Son du geste, par Eko » de la fiche d'unité : un Eko est partagé, et
// la conséquence d'un réglage fait ici se lit chez ceux qui le lancent — sa
// puissance, sa séquence et son son valent pour tous.
//
// Un Eko que personne ne connaît n'est pas une faute : il peut être en cours
// d'écriture. Mais il ne se joue jamais, et il vaut mieux que ce soit dit.
function knownByLine(id, performers) {
  const line = el("p", "battle-known-by");
  if (performers.length === 0) {
    line.appendChild(
      el("span", "battle-warning", "Personne ne connaît cet Eko : il ne se lancera jamais.")
    );
    return line;
  }
  line.appendChild(el("span", "battle-inline-hint", "Connu de"));
  for (const unitId of performers) {
    const open = el("button", "battle-eko-link", localizedName("units", unitId).label || unitId);
    open.type = "button";
    open.title = `Ouvrir « ${unitId} »`;
    open.onclick = () => goToEntry("units", unitId);
    line.appendChild(open);
  }
  return line;
}

// ──────────────────────────────────────────────────────────────────────────
//  Liste
// ──────────────────────────────────────────────────────────────────────────

const HINTS = {
  units:
    "Statistiques, planches d'animation, attaque de base, Ekos connus et — pour un ennemi — son comportement. Une planche se découpe en vignettes sur l'image elle-même ; sa grille et son ancrage, eux, se relèvent à l'atelier sur les gouttières d'alpha.",
  ekos: "Compétences, partagées par les deux camps : un mode de ciblage se lit relativement à celui qui lance.",
  items: "Mêmes champs que les Ekos, sans coût en PA.",
  sounds:
    "Les moments où un son peut partir, en deux familles : ceux du geste d'une action, et ceux qui appartiennent au personnage. Leur LISTE appartient au moteur — on ne peut ni en ajouter ni en retirer d'ici — mais leur nom d'affichage est libre : il ne sert que dans cet éditeur, les catalogues continuent d'écrire la clé.",
};

// ──────────────────────────────────────────────────────────────────────────
//  Section « Sons »
// ──────────────────────────────────────────────────────────────────────────

function renderSounds() {
  if (!vocabulary.parsed?.moment_notes || !vocabulary.parsed?.unit_moment_notes) {
    listEl.appendChild(
      el(
        "p",
        "battle-warning",
        "Certaines explications n'ont pas pu être lues dans le code : ce sont des valeurs de repli, qui peuvent être en retard."
      )
    );
  }

  listEl.appendChild(el("h3", "battle-subtitle", "Moments d'une action"));
  listEl.appendChild(
    el("p", "hint", "Les six points du geste de celui qui agit, pendant l'assaut. Ils se règlent sur l'attaque de base d'une unité, sur un Eko ou sur un objet.")
  );
  listEl.appendChild(momentTable(vocabulary.moments));

  listEl.appendChild(el("h3", "battle-subtitle", "Voix d'un personnage"));
  listEl.appendChild(
    el("p", "hint", "Des moments qui appartiennent à l'unité, pas à son geste : ils se règlent sur la fiche de l'unité, dans « Voix du personnage ».")
  );
  listEl.appendChild(momentTable(vocabulary.unit_moments));

  renderSoundLibrary();
}

function momentTable(keys) {
  const table = el("div", "battle-moments");
  for (const key of keys) {
    const row = el("div", "battle-moment-row");
    row.appendChild(el("code", "battle-moment-key", key));

    const input = el("input", "battle-input");
    input.type = "text";
    input.value = momentLabel(key);
    input.placeholder = key;
    input.onchange = async () => {
      const value = input.value.trim();
      // Un libellé vidé RETIRE la clé au lieu d'écrire une chaîne vide : le
      // moment reprend alors son nom de code, ce qui est un état utile (et
      // lisible dans le fichier), là qu'une chaîne vide donnerait une liste
      // déroulante avec des entrées sans nom.
      if (value && value !== key) momentLabels.labels[key] = value;
      else delete momentLabels.labels[key];
      // Même avalement qu'en haut : le refus est déjà annoncé par api.js, il ne
      // doit pas finir en promesse rejetée ni empêcher le redessin.
      try {
        await saveBattleMomentLabels(momentLabels);
      } catch (err) {
        if (!(err instanceof CatalogConflictError)) throw err;
      }
      renderList();
    };
    row.appendChild(input);

    row.appendChild(
      el(
        "span",
        "battle-moment-note",
        vocabulary.moment_notes?.[key] || vocabulary.unit_moment_notes?.[key] || "—"
      )
    );
    table.appendChild(row);
  }
  return table;
}

function renderSoundLibrary() {
  const title = el("div", "battle-library-head");
  title.appendChild(el("h3", "battle-subtitle", "Fichiers disponibles"));
  // Importer DEPUIS LA BIBLIOTHÈQUE, en plus de la ligne d'un son : on ne
  // prépare pas toujours dans le même ordre. Tantôt on part d'un Eko et on lui
  // cherche un fracas, tantôt on rentre avec un dossier d'exports et on veut
  // les déposer d'un bloc avant de décider à quoi ils serviront. Ici le fichier
  // rejoint la liste, sans être affecté à quoi que ce soit.
  title.appendChild(
    soundImportButton(null, () => {}, () => renderList(), { label: "Importer un son…" })
  );
  listEl.appendChild(title);
  listEl.appendChild(
    el("p", "hint", `${sounds.length} fichiers sous Audio/. Le bouton les joue tels quels, sans le mixage du jeu (ni volume de musique, ni atténuation). Ce qu'on importe ici atterrit dans Audio/Battle/Actions.`)
  );
  const files = el("div", "battle-sound-library");
  for (const path of sounds) {
    const row = el("div", "battle-sound-file");
    row.appendChild(playButton(() => path));
    const name = el("span", "battle-sound-path", path.slice("res://Audio/".length));
    name.title = path;
    row.appendChild(name);
    files.appendChild(row);
  }
  listEl.appendChild(files);
}

// Le serveur du MapEditor ne se recharge pas tout seul, et il sert `public/`
// DEPUIS LE DISQUE : après une mise à jour, le navigateur a déjà le nouveau
// code client alors que les routes, elles, datent du démarrage. Le symptôme est
// alors incompréhensible — des boutons qui ne font rien — d'où cette bannière,
// qui nomme la cause et le geste plutôt que de laisser chercher.
function staleServerBanner() {
  const banner = el(
    "p",
    "battle-warning",
    "Ce serveur MapEditor tourne sur une version antérieure : il ne sert ni les sons (le bouton ▶ restera sans effet) ni les explications des moments. Relance-le — « npm start » dans tools/MapEditor — puis recharge cette page."
  );
  return banner;
}

function renderList() {
  listEl.innerHTML = "";
  hintEl.textContent = HINTS[activeSection];
  if (momentLabels.stale) listEl.appendChild(staleServerBanner());
  if (activeSection === SOUNDS_SECTION) return renderSounds();

  const entries = entriesOf(activeSection);
  const ids = Object.keys(entries);

  const refresh = refresher();

  const browser = el("div", "battle-browser");
  const index = el("nav", "battle-index");
  browser.appendChild(index);
  const detail = el("div", "battle-detail");
  browser.appendChild(detail);
  listEl.appendChild(browser);

  if (ids.length === 0) {
    detail.appendChild(el("p", "hint", "Catalogue vide."));
    index.appendChild(addButton());
    return;
  }
  // La sélection survit aux redessins, mais pas à la suppression de l'entrée
  // sélectionnée : on retombe alors sur la première, plutôt que sur un panneau
  // vide qui ferait croire à une page cassée.
  if (!ids.includes(selection[activeSection])) selection[activeSection] = ids[0];

  for (const id of ids) index.appendChild(indexEntry(id, entries[id]));
  index.appendChild(addButton());

  const current = selection[activeSection];
  detail.appendChild(
    activeSection === "units"
      ? renderUnit(current, entries[current], refresh)
      : renderAction(activeSection, current, entries[current], refresh)
  );
}

// Une ligne de la colonne de gauche : de quoi RECONNAÎTRE l'entrée, pas de quoi
// la juger — sa vignette, son nom tel qu'il sortira en jeu, et son identifiant.
function indexEntry(id, entry) {
  const item = el("button", "battle-index-item");
  item.type = "button";
  if (id === selection[activeSection]) item.classList.add("selected");
  if (activeSection === "units") {
    const idle = entry.animations?.idle || Object.values(entry.animations || {})[0];
    if (idle) item.appendChild(staticFrame(idle, sheetUrl(idle.sheet), 32));
  }
  const text = el("span", "battle-index-text");
  const { label } = localizedName(activeSection, id);
  text.appendChild(el("span", "battle-index-name", label || id));
  text.appendChild(el("span", "battle-index-id", id));
  // La lecture en clair sous le nom : l'index sert à RETROUVER une action, et
  // « Rosee » ne dit pas que c'est le soin unitaire à 1 PA. Sans elle, chercher
  // « le soin de groupe » revient à ouvrir les fiches une par une.
  if (activeSection === "ekos" || activeSection === "items") {
    text.appendChild(el("span", "battle-index-summary", actionSummary(activeSection, entry)));
  }
  item.appendChild(text);
  if (activeSection === "units" && entry.behaviour) {
    item.appendChild(el("span", "battle-badge", "ennemi"));
  }
  item.onclick = () => {
    selection[activeSection] = id;
    renderList();
  };
  return item;
}

function defaultEntry(section) {
  if (section === "units") {
    return {
      portrait: "",
      stats: { hp_max: 30, ap_max: 0, force: 5, defense: 5, agility: 5, luck: 5 },
      animations: {},
      ekos: [],
      basic_attack: { power: 5, damage_type: "direct", sequence: [] },
    };
  }
  const entry = { target: "enemy", power: 10, damage_type: "direct", sequence: [] };
  if (section === "ekos") entry.ap_cost = 1;
  return entry;
}

// Construit à chaque rendu, en pied de la colonne de gauche : il appartient au
// catalogue qu'on parcourt, pas à la page. Le déplacer depuis le HTML le faisait
// détruire par le vidage de la liste, et disparaître sur l'onglet « Sons ».
function addButton() {
  const singular = SECTIONS[activeSection].singular;
  const button = el(
    "button",
    "battle-index-add",
    `+ Ajouter ${singular === "unité" ? "une unité" : "un " + singular}`
  );
  button.type = "button";
  button.onclick = async () => {
    const id = prompt(`Identifiant de la nouvelle ${singular} (minuscules, chiffres, _) :`);
    if (!id) return;
    if (!ID_PATTERN.test(id)) {
      alert("Identifiant invalide : minuscules, chiffres et « _ » seulement.");
      return;
    }
    if (entriesOf(activeSection)[id]) {
      alert(`« ${id} » existe déjà.`);
      return;
    }
    entriesOf(activeSection)[id] = defaultEntry(activeSection);
    // L'entrée qu'on vient de créer s'ouvre : c'est pour l'éditer qu'on l'a
    // créée, et la laisser fermée obligerait à la chercher dans la liste.
    selection[activeSection] = id;
    renderList();
    await persist(activeSection);
  };
  return button;
}

// Ouvre une entrée d'une AUTRE section. Les catalogues se citent l'un l'autre —
// une unité connaît des Ekos — et la question « qu'est-ce que ça fait entendre,
// ça ? » se pose depuis la fiche qui cite, pas depuis celle qui porte le
// réglage. L'onglet suit, sans quoi la page changerait de contenu sans dire
// pourquoi.
function goToEntry(section, id) {
  activeSection = section;
  selection[section] = id;
  tabsEl
    .querySelectorAll(".battle-tab")
    .forEach((t) => t.classList.toggle("selected", t.dataset.section === section));
  renderList();
}

for (const tab of tabsEl.querySelectorAll(".battle-tab")) {
  tab.onclick = () => {
    tabsEl.querySelectorAll(".battle-tab").forEach((t) => t.classList.remove("selected"));
    tab.classList.add("selected");
    activeSection = tab.dataset.section;
    renderList();
  };
}

export async function openBattleManager() {
  // Les trois catalogues sont chargés ENSEMBLE, même si une seule section est
  // visible : ils se citent l'un l'autre (les Ekos connus d'une unité, la cible
  // d'un `focus`, les planches disponibles pour une action), et une section
  // rendue sans les autres afficherait des listes déroulantes vides.
  const [units, ekos, items, catalogTexts, soundList, vocab, labels, sheetList] =
    await Promise.all([
      getBattleCatalog("units"),
      getBattleCatalog("ekos"),
      getBattleCatalog("items"),
      getTexts(),
      getBattleSounds(),
      getBattleVocabulary(),
      getBattleMomentLabels(),
      getBattleSheets(),
    ]);
  catalogs = { units, ekos, items };
  texts = catalogTexts;
  sounds = soundList;
  // FUSION et non remplacement : le serveur ne se recharge pas tout seul, et
  // celui qui tourne peut dater d'avant une clé (les dessins de notes, les
  // vitesses de la barre). Elle garde alors le repli déclaré à la déclaration
  // de `vocabulary`, au lieu de devenir `undefined` et de casser la page à
  // l'endroit qui la lit.
  vocabulary = { ...vocabulary, ...vocab };
  animationStates = vocab.animation_states || [];
  actionAnimationDefault = vocab.action_animation_default || "atk";
  rhythmAnimationDefault = vocab.rhythm_animation_default || "rhythm";
  momentLabels = labels;
  sheetFiles = sheetList;
  if (!momentLabels.labels) momentLabels.labels = {};

  activeSection = "units";
  tabsEl
    .querySelectorAll(".battle-tab")
    .forEach((t) => t.classList.toggle("selected", t.dataset.section === "units"));
  renderList();
  watchForStaleCatalogs();
}

// ──────────────────────────────────────────────────────────────────────────
//  Page périmée
// ──────────────────────────────────────────────────────────────────────────

// Une page laissée ouverte pendant qu'on édite les mêmes fichiers ailleurs — un
// autre onglet, un éditeur de texte — travaille sur une copie d'avant. Le
// verrou du serveur l'empêche d'écraser quoi que ce soit, mais il ne parle
// qu'AU MOMENT DE SAUVEGARDER : trop tard, la modification vient d'être faite
// et sera refusée. On regarde donc au RETOUR SUR L'ONGLET, avant de toucher à
// quoi que ce soit.
//
// C'est le versant préventif d'un incident réel : un onglet resté ouvert a
// réécrit units.json tel qu'il était une heure plus tôt, effaçant une série
// d'ancrages relevés au pixel.
let staleNoticeShown = false;

function watchForStaleCatalogs() {
  window.addEventListener("focus", checkForStaleCatalogs);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) checkForStaleCatalogs();
  });
}

async function checkForStaleCatalogs() {
  // Rien à dire si la page « Combat » n'est pas à l'écran, et rien à répéter :
  // un avertissement qu'on redemande à chaque clic sur la fenêtre s'ignore.
  if (staleNoticeShown || !listEl || listEl.offsetParent === null) return;
  const changed = [];
  for (const section of Object.keys(catalogs)) {
    try {
      if (await battleCatalogChanged(section)) changed.push(section);
    } catch {
      // Serveur arrêté ou redémarré : ce n'est pas un conflit, et bloquer
      // l'édition sur une requête ratée serait pire que de se taire.
    }
  }
  if (changed.length === 0) return;
  staleNoticeShown = true;
  // Nommés comme leurs onglets plutôt que par leur clé d'API : c'est sous ce
  // nom-là que l'auteur les connaît, et il n'y a pas de deuxième libellé à
  // tenir à jour.
  const quoi = changed
    .map((s) => tabsEl.querySelector(`[data-section="${s}"]`)?.textContent.trim() || s)
    .join(", ");
  if (confirm(
    `${quoi} : ce catalogue a changé sur disque depuis que cette page l'a `
    + "chargé. Cette page travaille sur la version d'avant, et tout ce que tu y "
    + "modifieras sera refusé à la sauvegarde.\n\nRecharger maintenant ?"
  )) {
    location.reload();
    return;
  }
  // Refus assumé : le drapeau est déjà posé plus haut, on ne redemande pas —
  // et le verrou du serveur fera son office à la première sauvegarde.
}
