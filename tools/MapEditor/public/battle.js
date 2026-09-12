import {
  getBattleCatalog,
  saveBattleCatalog,
  getBattleSounds,
  getBattleVocabulary,
  getTexts,
} from "./api.js";

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

const overlay = document.getElementById("battle-modal-overlay");
const closeBtn = document.getElementById("battle-modal-close");
const listEl = document.getElementById("battle-list");
const addBtn = document.getElementById("battle-add-btn");
const hintEl = document.getElementById("battle-hint");
const tabsEl = document.getElementById("battle-section-tabs");

// Chaque section connaît son fichier, la clé du dictionnaire qu'il contient, et
// le préfixe des ids Localization qui lui donnent ses libellés.
const SECTIONS = {
  units: { container: "units", textPrefix: "unit", singular: "unité" },
  ekos: { container: "ekos", textPrefix: "eko", singular: "Eko" },
  items: { container: "items", textPrefix: "item", singular: "objet" },
};

const ID_PATTERN = /^[a-z0-9_]+$/;

let catalogs = { units: null, ekos: null, items: null };
let texts = { texts: [], default_language: "en" };
let sounds = [];
let vocabulary = {
  moments: [],
  notes: [],
  targets: [],
  damage_types: [],
  behaviours: [],
  parsed: {},
};
let activeSection = "units";

function entriesOf(section) {
  return catalogs[section]?.[SECTIONS[section].container] || {};
}

async function persist(section) {
  await saveBattleCatalog(section, catalogs[section]);
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

// `empty` ajoute une entrée vide en tête : un champ FACULTATIF (un soin sur un
// objet, une planche sur un Eko) doit pouvoir être remis à « rien », sinon la
// première ouverture de la page écrit une valeur dans chaque entrée du
// catalogue et le fichier gonfle de champs que personne n'a demandés.
function selectInput(values, current, onCommit, { empty = null } = {}) {
  const select = el("select", "battle-input");
  if (empty !== null) {
    const option = el("option", null, empty);
    option.value = "";
    select.appendChild(option);
  }
  for (const value of values) {
    const option = el("option", null, value);
    option.value = value;
    select.appendChild(option);
  }
  select.value = current ?? "";
  select.onchange = () => onCommit(select.value);
  return select;
}

// ──────────────────────────────────────────────────────────────────────────
//  Séquence de rythme
// ──────────────────────────────────────────────────────────────────────────

// Les notes sont un vocabulaire fermé lu dans RhythmBar.gd : des pastilles
// cliquables plutôt qu'un champ texte, une note inventée ne pouvant produire
// qu'un silence dans la barre.
function sequenceEditor(action, onChanged) {
  const wrap = el("div", "battle-sequence");
  const notes = action.sequence || [];

  notes.forEach((note, index) => {
    const chip = el("span", "battle-note");
    chip.appendChild(
      selectInput(vocabulary.notes, note, (value) => {
        action.sequence[index] = value;
        onChanged();
      })
    );
    const remove = el("button", "battle-chip-remove", "×");
    remove.type = "button";
    remove.title = "Retirer cette note";
    remove.onclick = () => {
      action.sequence.splice(index, 1);
      onChanged();
    };
    chip.appendChild(remove);
    wrap.appendChild(chip);
  });

  const add = el("button", "battle-chip-add", "+ note");
  add.type = "button";
  add.onclick = () => {
    if (!action.sequence) action.sequence = [];
    action.sequence.push(vocabulary.notes[0]);
    onChanged();
  };
  wrap.appendChild(add);

  if (notes.length === 0) {
    wrap.appendChild(
      el("span", "battle-inline-hint", "Sans séquence, l'action ne fait pas jouer la barre.")
    );
  }
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
  if (Number(action.heal || 0) > 0) {
    unreachable.add("approach");
    unreachable.add("return");
  }
  if (!action.sequence || action.sequence.length === 0) unreachable.add("rhythm");
  return unreachable;
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

function soundsEditor(action, onChanged) {
  const wrap = el("div", "battle-sounds");
  const list = action.sounds || [];
  const unreachable = unreachableMoments(action);

  list.forEach((entry, index) => {
    const row = el("div", "battle-sound-row");

    row.appendChild(
      selectInput(vocabulary.moments, entry.at || "hit", (value) => {
        entry.at = value;
        onChanged();
      })
    );

    // Plusieurs fichiers sur une entrée = des VARIANTES tirées au hasard, pas
    // deux sons joués ensemble. Le libellé le dit, parce que la distinction ne
    // se devine pas d'une liste.
    const files = el("div", "battle-sound-files");
    const paths = soundPaths(entry);
    paths.forEach((path, fileIndex) => {
      const line = el("div", "battle-sound-file");
      line.appendChild(
        selectInput(sounds, path, (value) => {
          const next = soundPaths(entry);
          next[fileIndex] = value;
          setSoundPaths(entry, next);
          onChanged();
        })
      );
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
      action.sounds.splice(index, 1);
      onChanged();
    };
    row.appendChild(remove);

    wrap.appendChild(row);

    if (unreachable.has(entry.at || "hit")) {
      wrap.appendChild(
        el(
          "span",
          "battle-warning",
          `« ${entry.at} » n'existe pas pour cette action : elle ne l'atteint jamais, le son ne se jouera pas.`
        )
      );
    }
  });

  const add = el("button", "battle-chip-add", "+ son");
  add.type = "button";
  add.onclick = () => {
    if (!action.sounds) action.sounds = [];
    action.sounds.push({ at: "hit", sound: sounds[0] || "" });
    onChanged();
  };
  wrap.appendChild(add);
  return wrap;
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

// `fields` dit quels champs cette action-là possède : une attaque de base n'a
// ni coût en PA ni mode de ciblage (elle vise toujours un adversaire), un objet
// n'a pas de coût en PA, un Eko a tout.
function actionFields(action, fields, animations, onChanged) {
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
        }),
        "Lu RELATIVEMENT à celui qui agit : « ally » désigne son propre camp."
      )
    );
  }

  grid.appendChild(
    objectNumberField(action, "power", "Puissance", {
      optional: true,
      min: 0,
      onCommit: onChanged,
    })
  );

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

  grid.appendChild(
    field(
      "Nature",
      selectInput(vocabulary.damage_types, action.damage_type, (v) => {
        if (v) action.damage_type = v;
        else delete action.damage_type;
        onChanged();
      }, { empty: "(aucune)" }),
      "direct retire les PV tout de suite, injury les met en attente. Choisit aussi l'icône de la rangée."
    )
  );

  grid.appendChild(
    field(
      "Planche",
      selectInput(animations, action.animation, (v) => {
        if (v) action.animation = v;
        else delete action.animation;
        onChanged();
      }, { empty: "(pas en avant)" }),
      "Nom cherché dans le bloc « animations » de l'unité qui agit, pas ici."
    )
  );

  return grid;
}

function actionBlock(title, action, fields, animations, onChanged) {
  const block = el("div", "battle-block");
  block.appendChild(el("h4", "battle-block-title", title));
  block.appendChild(actionFields(action, fields, animations, onChanged));
  block.appendChild(el("span", "battle-sub-label", "Séquence de rythme"));
  block.appendChild(sequenceEditor(action, onChanged));
  block.appendChild(el("span", "battle-sub-label", "Sons"));
  block.appendChild(soundsEditor(action, onChanged));
  return block;
}

// ──────────────────────────────────────────────────────────────────────────
//  Libellés : lecture seule, résolus depuis le catalogue de textes
// ──────────────────────────────────────────────────────────────────────────

function localizedName(section, id) {
  const textId = `${SECTIONS[section].textPrefix}.${id}.name`;
  const entry = texts.texts?.find((t) => t.id === textId);
  if (!entry) return { textId, label: null };
  return {
    textId,
    label: entry.translations?.[texts.default_language] || entry.translations?.en || "",
  };
}

function nameLine(section, id) {
  const { textId, label } = localizedName(section, id);
  const line = el("span", "battle-name-line");
  if (label) {
    line.textContent = `« ${label} » — ${textId}, à modifier depuis la page Textes.`;
  } else {
    line.className = "battle-warning";
    line.textContent = `Aucun texte ${textId} : l'entrée n'aura pas de nom en jeu. À créer depuis la page Textes.`;
  }
  return line;
}

// ──────────────────────────────────────────────────────────────────────────
//  Rendu d'une entrée
// ──────────────────────────────────────────────────────────────────────────

function rowHead(section, id, badge) {
  const head = el("div", "battle-row-head");
  head.appendChild(el("span", "battle-id", id));
  if (badge) head.appendChild(el("span", "battle-badge", badge));

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

function renderUnit(id, unit, refresh) {
  const row = el("div", "battle-row");
  row.appendChild(rowHead("units", id, unit.behaviour ? "ennemi" : null));
  row.appendChild(nameLine("units", id));

  const stats = el("div", "battle-grid");
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
  row.appendChild(el("span", "battle-sub-label", "Statistiques"));
  row.appendChild(stats);

  // Les planches sont en LECTURE SEULE : leur grille, leur ancrage et leur
  // fourchette de frames se relèvent au pixel sur l'image (cf. CLAUDE.md), ce
  // qu'un formulaire web ne peut pas faire — proposer de les saisir à la main
  // inviterait à poser des valeurs plausibles et fausses.
  const sheets = Object.keys(unit.animations || {});
  row.appendChild(el("span", "battle-sub-label", "Planches"));
  if (sheets.length === 0) {
    row.appendChild(
      el("span", "battle-warning", "Aucune planche : l'unité n'a rien à afficher en combat.")
    );
  } else {
    const chips = el("div", "battle-sequence");
    for (const name of sheets) chips.appendChild(el("span", "battle-note-static", name));
    chips.appendChild(
      el("span", "battle-inline-hint", "Lecture seule — grille et ancrage se relèvent sur l'image.")
    );
    row.appendChild(chips);
  }

  if (!unit.basic_attack) unit.basic_attack = {};
  row.appendChild(
    actionBlock("Attaque de base", unit.basic_attack, ["heal"], sheets, refresh)
  );

  // Ekos connus : des cases à cocher sur le catalogue réel, jamais une saisie
  // d'identifiant — un id qui n'existe pas ne produirait qu'une entrée de menu
  // vide, découverte en jeu.
  row.appendChild(el("span", "battle-sub-label", "Ekos connus"));
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

  row.appendChild(behaviourBlock(id, unit, refresh));
  return row;
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
  const row = el("div", "battle-row");
  row.appendChild(rowHead(section, id, null));
  row.appendChild(nameLine(section, id));
  const fields = section === "ekos" ? ["ap_cost", "target", "heal"] : ["target", "heal"];
  row.appendChild(actionBlock("Effet", action, fields, allAnimationNames(), refresh));
  return row;
}

// ──────────────────────────────────────────────────────────────────────────
//  Liste
// ──────────────────────────────────────────────────────────────────────────

const HINTS = {
  units:
    "Statistiques, attaque de base, Ekos connus et — pour un ennemi — son comportement. Les planches d'animation sont en lecture seule.",
  ekos: "Compétences, partagées par les deux camps : un mode de ciblage se lit relativement à celui qui lance.",
  items: "Mêmes champs que les Ekos, sans coût en PA.",
};

function renderList() {
  listEl.innerHTML = "";
  hintEl.textContent = HINTS[activeSection];

  const entries = entriesOf(activeSection);
  const ids = Object.keys(entries);
  if (ids.length === 0) {
    listEl.appendChild(el("p", "hint", "Catalogue vide."));
    return;
  }

  // Un changement quelconque redessine la liste ET sauvegarde : les entrées
  // s'influencent (cocher un Eko ajoute une case ailleurs, vider une séquence
  // fait apparaître un avertissement de son injouable), et redessiner seulement
  // la ligne touchée laisserait les autres mentir.
  const refresh = async () => {
    renderList();
    await persist(activeSection);
  };

  for (const id of ids) {
    listEl.appendChild(
      activeSection === "units"
        ? renderUnit(id, entries[id], refresh)
        : renderAction(activeSection, id, entries[id], refresh)
    );
  }
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

addBtn.onclick = async () => {
  const singular = SECTIONS[activeSection].singular;
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
  renderList();
  await persist(activeSection);
};

for (const tab of tabsEl.querySelectorAll(".battle-tab")) {
  tab.onclick = () => {
    tabsEl.querySelectorAll(".battle-tab").forEach((t) => t.classList.remove("selected"));
    tab.classList.add("selected");
    activeSection = tab.dataset.section;
    addBtn.textContent = `+ Ajouter ${SECTIONS[activeSection].singular === "unité" ? "une unité" : "un " + SECTIONS[activeSection].singular}`;
    renderList();
  };
}

closeBtn.onclick = closeManager;
overlay.onclick = (evt) => {
  if (evt.target === overlay) closeManager();
};

function closeManager() {
  overlay.classList.add("hidden");
}

export async function openBattleManager() {
  // Les trois catalogues sont chargés ENSEMBLE, même si une seule section est
  // visible : ils se citent l'un l'autre (les Ekos connus d'une unité, la cible
  // d'un `focus`, les planches disponibles pour une action), et une section
  // rendue sans les autres afficherait des listes déroulantes vides.
  const [units, ekos, items, catalogTexts, soundList, vocab] = await Promise.all([
    getBattleCatalog("units"),
    getBattleCatalog("ekos"),
    getBattleCatalog("items"),
    getTexts(),
    getBattleSounds(),
    getBattleVocabulary(),
  ]);
  catalogs = { units, ekos, items };
  texts = catalogTexts;
  sounds = soundList;
  vocabulary = vocab;

  activeSection = "units";
  tabsEl
    .querySelectorAll(".battle-tab")
    .forEach((t) => t.classList.toggle("selected", t.dataset.section === "units"));
  addBtn.textContent = "+ Ajouter une unité";
  renderList();
  overlay.classList.remove("hidden");
}
