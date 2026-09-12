import express from "express";
import fs from "fs/promises";
import fsSync from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { spawn } from "child_process";
import { createHash } from "crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, "..", "..");
const MAPS_DIR = path.join(PROJECT_ROOT, "maps");
const SPRITES_DIR = path.join(PROJECT_ROOT, "Sprites");
// Les planches de combat vivent toutes là : c'est le dossier que la page
// « Combat » liste, et celui où elle dépose ce qu'on lui donne à importer.
const BATTLE_SHEETS_DIR = path.join(SPRITES_DIR, "Battle");
const TILE_META_PATH = path.join(SPRITES_DIR, "tile_meta.json");
const PROPS_META_PATH = path.join(SPRITES_DIR, "props_meta.json");
const SCRIPTS_DIR = path.join(PROJECT_ROOT, "Scripts");
const SCENES_DIR = path.join(PROJECT_ROOT, "Scenes");
const PROJECT_GODOT_PATH = path.join(PROJECT_ROOT, "project.godot");
const LOCALIZATION_DIR = path.join(PROJECT_ROOT, "Localization");
const TEXTS_PATH = path.join(LOCALIZATION_DIR, "texts.json");
const PREVIEWS_DIR = path.join(LOCALIZATION_DIR, "previews");
const FONTS_DIR = path.join(PROJECT_ROOT, "Fonts");
const BATTLE_DIR = path.join(PROJECT_ROOT, "Battle");
const AUDIO_DIR = path.join(PROJECT_ROOT, "Audio");
const BATTLE_ASSAULT_PATH = path.join(SCRIPTS_DIR, "Battle", "BattleAssault.gd");
const RHYTHM_BAR_PATH = path.join(SCRIPTS_DIR, "Battle", "UI", "RhythmBar.gd");
const BATTLE_DATA_PATH = path.join(SCRIPTS_DIR, "Battle", "BattleData.gd");
const BATTLE_SCENE_PATH = path.join(SCRIPTS_DIR, "Battle", "BattleScene.gd");
// Libellés que l'auteur donne aux moments de son. Côté OUTIL et pas côté jeu :
// le moteur ne connaît que les clés (`hit`, `gesture`…), qui sont son
// vocabulaire ; renommer ici ne change que ce qui s'affiche dans l'éditeur.
// Une clé absente retombe sur elle-même, donc supprimer ce fichier ne casse
// rien — il ne porte que de la présentation.
const BATTLE_LABELS_PATH = path.join(__dirname, "battle_moment_labels.json");

const app = express();
app.use(express.json({ limit: "5mb" }));
app.use(express.static(path.join(__dirname, "public")));
app.use("/sprites", express.static(SPRITES_DIR));
app.use("/localization-previews", express.static(PREVIEWS_DIR));
app.use("/fonts", express.static(FONTS_DIR));
// Les sons servis tels quels, pour que la page « Combat » puisse faire écouter
// ce qu'on est en train de choisir. Un chemin `res://Audio/x.wav` se lit donc
// aussi en `/audio/x.wav`.
app.use("/audio", express.static(AUDIO_DIR));

function isValidId(id) {
  return /^[a-zA-Z0-9_-]+$/.test(id);
}

app.get("/api/maps", async (req, res) => {
  const files = await fs.readdir(MAPS_DIR);
  const maps = [];
  for (const file of files) {
    if (!file.endsWith(".json")) continue;
    const raw = await fs.readFile(path.join(MAPS_DIR, file), "utf-8");
    const data = JSON.parse(raw);
    maps.push({ id: data.id, name: data.name });
  }
  res.json(maps);
});

app.get("/api/maps/:id", async (req, res) => {
  const { id } = req.params;
  if (!isValidId(id)) return res.status(400).json({ error: "invalid id" });
  const filePath = path.join(MAPS_DIR, `${id}.json`);
  try {
    const raw = await fs.readFile(filePath, "utf-8");
    const data = JSON.parse(raw);
    // _rev absent = fichier créé avant l'ajout du verrou optimiste ci-dessous
    // (cf. POST) : traité comme révision 0, compatible sans migration.
    if (data._rev === undefined) data._rev = 0;
    res.json(data);
  } catch {
    res.status(404).json({ error: "map not found" });
  }
});

// Verrou optimiste : plusieurs onglets/sessions du MapEditor peuvent ouvrir
// la même map en même temps (pas de vrai backend, tout est fichier-based) —
// sans ça, un onglet resté ouvert sur un vieil état peut sauvegarder par-
// dessus le travail fait entre-temps ailleurs, en silence (c'est ce qui est
// arrivé à Worldmap.json/Test.json). `_rev` est un compteur écrit dans le
// JSON à chaque sauvegarde ; le client doit renvoyer la révision qu'il a
// chargée (cf. GET ci-dessus) — si elle ne correspond plus à celle sur
// disque, quelqu'un d'autre a sauvegardé depuis : on refuse (409) plutôt que
// d'écraser, le client doit recharger avant de réessayer.
app.post("/api/maps/:id", async (req, res) => {
  const { id } = req.params;
  if (!isValidId(id)) return res.status(400).json({ error: "invalid id" });
  const map = req.body;
  const filePath = path.join(MAPS_DIR, `${id}.json`);

  let currentRev = 0;
  try {
    const existing = JSON.parse(await fs.readFile(filePath, "utf-8"));
    currentRev = existing._rev || 0;
  } catch {
    // Le fichier n'existe pas encore (nouvelle map) : rien à comparer.
  }
  const clientRev = map._rev || 0;
  if (clientRev !== currentRev) {
    return res.status(409).json({
      error: "conflict",
      message:
        `Cette map a été modifiée ailleurs depuis ton dernier chargement ` +
        `(révision ${currentRev} sur disque, tu as la révision ${clientRev}). ` +
        `Recharge-la avant de sauvegarder pour ne pas écraser ces changements.`,
      currentRev,
    });
  }

  map.id = id;
  map._rev = currentRev + 1;
  await fs.writeFile(filePath, JSON.stringify(map, null, 2));
  res.json({ ok: true, rev: map._rev });
});

app.delete("/api/maps/:id", async (req, res) => {
  const { id } = req.params;
  if (!isValidId(id)) return res.status(400).json({ error: "invalid id" });
  await fs.unlink(path.join(MAPS_DIR, `${id}.json`));
  res.json({ ok: true });
});

// La forme attendue du PUT s'aligne sur celle de `defaultValue` : un tableau
// pour tiles/props, un objet portant les mêmes clés de conteneur pour les
// catalogues (textes, et les trois catalogues de combat). On vérifie que
// CHAQUE clé du modèle est présente, plutôt que « c'est un objet » : sans ça
// une requête malformée écrirait `{}` par-dessus un catalogue entier. Les clés
// commençant par `_` (`_comment`, `_champs`, qui documentent le fichier) sont
// exemptées — elles se perdraient à la première sauvegarde d'un client qui ne
// les renvoie pas, et c'est au client de les préserver, pas au validateur de
// les exiger.
function sameShape(body, model) {
  if (Array.isArray(model)) return Array.isArray(body);
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  return Object.keys(model)
    .filter((key) => !key.startsWith("_"))
    .every((key) => key in body);
}

// `defaultValue` généralise ce qui était autrefois toujours un tableau ([]) :
// un tableau vide pour tiles/props (comportement inchangé), un objet vide de
// catalogue pour /api/texts et pour les catalogues de combat (cf plus bas).
// Empreinte du CONTENU du fichier, annoncée au chargement et réclamée à la
// sauvegarde (cf. le verrou de metaRoutes ci-dessous).
//
// Une empreinte plutôt qu'un compteur `_rev` comme les maps : ces fichiers-là
// sont de la DONNÉE DE JEU, lue par Godot. Y écrire un compteur d'éditeur les
// salirait, et surtout il ne verrait pas passer une modification faite à la
// main dans un éditeur de texte — alors qu'une empreinte du contenu, si.
function revisionOf(text) {
  return createHash("sha1").update(text).digest("hex").slice(0, 16);
}

function metaRoutes(urlPath, filePath, defaultValue = []) {
  app.get(urlPath, async (req, res) => {
    try {
      const raw = await fs.readFile(filePath, "utf-8");
      res.set("X-Catalog-Revision", revisionOf(raw));
      res.json(JSON.parse(raw));
    } catch {
      res.json(defaultValue);
    }
  });

  // VERROU OPTIMISTE. La page tient TOUT le catalogue en mémoire et le renvoie
  // ENTIER à chaque changement : un onglet ouvert depuis une heure réécrit donc
  // le fichier tel qu'il était il y a une heure, et efface sans un mot ce qui a
  // été fait depuis — par un autre onglet, ou à la main dans le fichier. Ce
  // n'est pas une hypothèse : c'est ainsi qu'une série d'ancrages relevés au
  // pixel a disparu, remplacée par les valeurs d'avant, au premier import fait
  // depuis un onglet resté ouvert.
  //
  // Le client renvoie donc l'empreinte qu'il a chargée ; si le disque ne porte
  // plus la même, on REFUSE (409) au lieu d'écraser. Même politique que les
  // maps, dont la note disait déjà que ce mécanisme était rétrofitable « si
  // l'édition concurrente devient un vrai problème ». Elle l'est devenue.
  app.put(urlPath, async (req, res) => {
    const body = req.body;
    if (!sameShape(body, defaultValue)) {
      return res.status(400).json({ error: "invalid payload" });
    }
    const expected = req.get("X-Expected-Revision");
    if (expected) {
      let current = null;
      try {
        current = revisionOf(await fs.readFile(filePath, "utf-8"));
      } catch {
        // Fichier absent : il n'y a rien à écraser, la sauvegarde le crée.
      }
      if (current !== null && current !== expected) {
        return res.status(409).json({
          error: "conflict",
          message:
            "Ce catalogue a été modifié ailleurs depuis que cette page l'a "
            + "chargé. Recharge la page avant de sauvegarder : sans ça, tu "
            + "écraserais ces changements par l'état d'il y a un moment.",
        });
      }
    }
    // Saut de ligne final : ces fichiers s'éditent AUSSI à la main, et
    // `JSON.stringify` n'en met pas. Sans lui, chaque sauvegarde depuis
    // l'éditeur produisait un diff git parasite (« \ No newline at end of
    // file ») sur un fichier par ailleurs inchangé.
    const text = JSON.stringify(body, null, 2) + "\n";
    await fs.writeFile(filePath, text);
    res.set("X-Catalog-Revision", revisionOf(text));
    res.json({ ok: true });
  });
}

metaRoutes("/api/tiles", TILE_META_PATH);
metaRoutes("/api/props", PROPS_META_PATH);
metaRoutes("/api/texts", TEXTS_PATH, {
  languages: [
    { code: "en", label: "English" },
    { code: "fr", label: "French" },
  ],
  default_language: "en",
  texts: [],
});

// ---------- Combat : les trois catalogues, édités par la page « Combat » ----------
// Mêmes routes que tiles/props/texts, et pour la même raison : la donnée de
// combat vit en JSON justement pour être éditable sans recompiler — donc aussi
// à la main, en parallèle de la page. D'où le verrou optimiste de metaRoutes.
metaRoutes("/api/battle/units", path.join(BATTLE_DIR, "units.json"), { units: {} });
metaRoutes("/api/battle/ekos", path.join(BATTLE_DIR, "ekos.json"), { ekos: {} });
metaRoutes("/api/battle/items", path.join(BATTLE_DIR, "items.json"), { items: {} });
metaRoutes("/api/battle/moment-labels", BATTLE_LABELS_PATH, { labels: {} });

// Fichiers audio disponibles, pour que le choix d'un son d'action soit une
// LISTE et pas un chemin `res://` tapé à la main — une faute de frappe y donne
// un son qui ne part jamais, et l'avertissement runtime n'arrive que le jour
// où quelqu'un lance ce combat.
const AUDIO_EXTENSIONS = [".wav", ".mp3", ".ogg"];

app.get("/api/battle/sounds", async (req, res) => {
  const files = [];
  for (const extension of AUDIO_EXTENSIONS) {
    files.push(...(await walkFiles(AUDIO_DIR, extension)));
  }
  const sounds = files
    .map((file) => "res://Audio/" + path.relative(AUDIO_DIR, file).split(path.sep).join("/"))
    .sort();
  res.json(sounds);
});

// Planches disponibles pour une animation d'unité. Elles vivent toutes sous
// Sprites/Battle/ ; les servir en liste évite de taper un chemin `res://` à la
// main, où une faute donne une unité invisible et aucune erreur avant le combat.
//
// La TAILLE en pixels n'est pas renvoyée : le client charge l'image de toute
// façon pour la montrer, et `naturalWidth` la lui donne sans que le serveur ait
// à décoder du PNG.
app.get("/api/battle/sheets", async (req, res) => {
  const files = await walkFiles(BATTLE_SHEETS_DIR, ".png");
  res.json(
    files
      .map((file) => path.relative(SPRITES_DIR, file).split(path.sep).join("/"))
      .sort()
      .map((rel) => ({
        path: "res://Sprites/" + rel,
        url: "/sprites/" + rel,
        // Godot ne lit pas un PNG posé sur le disque : il lui faut son `.import`
        // et la texture compilée qui va avec. Un fichier qui n'en a pas est
        // visible ICI et INVISIBLE EN JEU — l'éditeur doit donc le dire, sinon
        // l'auteur choisit une planche qui laissera son personnage vide.
        imported: fsSync.existsSync(path.join(SPRITES_DIR, rel) + ".import"),
      }))
  );
});

// Les huit octets de signature d'un PNG.
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

// Nom de fichier acceptable pour une planche : pas de séparateur, pas de `..`,
// et l'extension que Godot importe. On ne se contente pas d'assainir le nom
// donné — un nom refusé se répare à la main, un nom silencieusement transformé
// se retrouve dans `units.json` sans que personne ne l'ait voulu.
function isValidSheetName(name) {
  return /^[A-Za-z0-9_-]+\.png$/.test(name);
}

// Import d'une planche DEPUIS LE DISQUE de l'auteur. Le corps est le PNG brut
// (Content-Type: image/png) plutôt qu'un multipart : ça évite une dépendance
// pour un seul formulaire, et le client n'a qu'à passer le File tel quel.
app.post(
  "/api/battle/sheets",
  express.raw({ type: "image/png", limit: "24mb" }),
  async (req, res) => {
    const name = String(req.query.name || "");
    if (!isValidSheetName(name)) {
      return res.status(400).json({
        error: "Nom de planche invalide : lettres, chiffres, _ et -, extension .png.",
      });
    }
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length === 0) {
      return res.status(400).json({ error: "Corps vide : envoie le PNG en image/png." });
    }
    // Un fichier mal choisi (un JPEG renommé, une planche exportée en WebP)
    // passerait autrement jusque dans `units.json`, et n'échouerait qu'au
    // combat.
    if (!body.subarray(0, 8).equals(PNG_SIGNATURE)) {
      return res.status(400).json({ error: "Ce fichier n'est pas un PNG." });
    }
    const target = path.join(BATTLE_SHEETS_DIR, name);
    if (fsSync.existsSync(target) && req.query.overwrite !== "1") {
      return res.status(409).json({ error: `« ${name} » existe déjà.` });
    }
    try {
      await fs.mkdir(BATTLE_SHEETS_DIR, { recursive: true });
      await fs.writeFile(target, body);
    } catch (err) {
      return res.status(500).json({ error: String(err) });
    }
    const imported = await importWithGodot();
    const rel = path.relative(SPRITES_DIR, target).split(path.sep).join("/");
    res.json({
      path: "res://Sprites/" + rel,
      url: "/sprites/" + rel,
      imported: imported && fsSync.existsSync(target + ".import"),
    });
  }
);

// Passe d'import de Godot, ATTENDUE : tant qu'elle n'a pas tourné, le fichier
// existe sur le disque mais le jeu ne sait pas le charger. On rend la main
// seulement quand c'est fait, pour que la réponse puisse le dire honnêtement.
//
// `--quit-after 40` borne la passe : un éditeur qui resterait ouvert bloquerait
// la requête indéfiniment.
function importWithGodot() {
  if (!fsSync.existsSync(GODOT_BIN)) return Promise.resolve(false);
  return new Promise((resolve) => {
    const child = spawn(
      GODOT_BIN,
      ["--headless", "--path", PROJECT_ROOT, "--editor", "--quit-after", "40"],
      { stdio: "ignore" }
    );
    child.on("error", () => resolve(false));
    child.on("exit", () => resolve(true));
  });
}

// Vocabulaires FERMÉS du combat. Ceux qui sont déclarés une fois pour toutes
// dans le code Godot sont LUS LÀ-BAS plutôt que recopiés ici : deux listes qui
// disent la même chose finissent par se contredire, et c'est précisément le
// genre de divergence qui donne un son accroché à un moment qui n'existe pas.
// Les autres (modes de ciblage, natures de dégâts, comportements) n'ont pas de
// déclaration unique côté moteur — ils sont éparpillés dans des `match` — et
// restent donc écrits ici, documentés dans les `_champs` des catalogues.
// `String.raw` et pas un gabarit ordinaire : dans un gabarit, `\s` vaut « s »
// et la classe de caractères disparaît sans erreur au moment de l'écriture —
// elle n'explose qu'à la construction de la RegExp, à la première requête.
function parseGdStringArray(content, name) {
  const match = content.match(
    new RegExp(String.raw`const\s+${name}[^=]*=\s*\[([\s\S]*?)\]`)
  );
  if (!match) return null;
  const values = [...match[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  return values.length ? values : null;
}

// Commentaire de fin de ligne de chaque entrée d'un `const … = [...]`, rendu
// sous la forme { valeur: commentaire }. C'est la MÊME déclaration qui donne la
// liste et ses explications : le jour où quelqu'un ajoute un moment au moteur,
// son infobulle arrive avec lui, sans qu'un texte de l'éditeur ait à suivre.
function parseGdStringArrayNotes(content, name) {
  const match = content.match(
    new RegExp(String.raw`const\s+${name}[^=]*=\s*\[([\s\S]*?)\]`)
  );
  if (!match) return null;
  const notes = {};
  for (const ligne of match[1].split("\n")) {
    const entry = ligne.match(/"([^"]+)"\s*,?\s*#\s*(.+?)\s*$/);
    if (entry) notes[entry[1]] = entry[2];
  }
  return Object.keys(notes).length ? notes : null;
}

// Constantes de NOM D'ANIMATION du moteur : `const ANIM_IDLE := "idle"`, avec
// le bloc de commentaires `##` qui la précède. Lues dans le .gd plutôt que
// recopiées ici, pour la même raison que les moments de son : deux listes qui
// disent la même chose finissent par se contredire, et c'est le jeu qui a
// raison.
//
// Le COMMENTAIRE est ce qui donne son sens à l'état. « atkeff » ne dit rien ;
// « pose de visée, tenue figée pendant qu'il choisit sa cible » dit tout.
function parseGdAnimationStates(content) {
  const states = [];
  const lines = content.split("\n");
  let note = [];
  for (const line of lines) {
    const comment = line.match(/^\s*##\s?(.*)$/);
    if (comment) {
      note.push(comment[1].trim());
      continue;
    }
    const decl = line.match(/^const\s+(ANIM_[A-Z_]+)\s*:?=\s*"([^"]+)"/);
    if (decl) {
      states.push({
        key: decl[2],
        constant: decl[1],
        note: note.join(" ").trim(),
      });
    }
    // Toute ligne qui n'est pas un commentaire ferme le bloc en cours : un
    // commentaire doit TOUCHER sa constante pour lui appartenir.
    if (line.trim() !== "" || note.length === 0) note = [];
  }
  return states.length ? states : null;
}

// Nom de planche qu'une ACTION joue quand elle n'en déclare pas — lu dans son
// propre défaut, `get("animation", …)`, plutôt que fixé ici. Le défaut peut
// être écrit en clair ou renvoyer à une constante d'état, qu'on résout alors
// dans la liste déjà lue.
function parseGdActionAnimationDefault(content, states) {
  const match = content.match(/get\("animation",\s*(?:"([^"]+)"|([A-Z][A-Z0-9_]*))\)/);
  if (!match) return null;
  if (match[1]) return match[1];
  const named = states.find((state) => state.constant === match[2]);
  return named ? named.key : null;
}

function parseGdDictionaryKeys(content, name) {
  const match = content.match(
    new RegExp(String.raw`const\s+${name}[^=]*=\s*\{([\s\S]*?)\n\}`)
  );
  if (!match) return null;
  const keys = [...match[1].matchAll(/"([^"]+)"\s*:/g)].map((m) => m[1]);
  return keys.length ? keys : null;
}

async function readGd(filePath) {
  try {
    return await fs.readFile(filePath, "utf-8");
  } catch {
    return "";
  }
}

app.get("/api/battle/vocabulary", async (req, res) => {
  const [assault, rhythm, battleData, battleScene] = await Promise.all([
    readGd(BATTLE_ASSAULT_PATH),
    readGd(RHYTHM_BAR_PATH),
    readGd(BATTLE_DATA_PATH),
    readGd(BATTLE_SCENE_PATH),
  ]);
  // Un repli est prévu pour chaque liste lue dans le code : si un refactor
  // renomme la constante, la page continue de fonctionner sur la dernière
  // valeur connue, et le champ `parsed` dit ce qui a réellement été lu — un
  // éditeur qui tombe en panne muette serait pire que la divergence qu'on
  // cherche à éviter.
  const moments = parseGdStringArray(assault, "SOUND_MOMENTS");
  const momentNotes = parseGdStringArrayNotes(assault, "SOUND_MOMENTS");
  const notes = parseGdDictionaryKeys(rhythm, "NOTE_ACTIONS");
  // Deux familles de sons, deux vocabulaires. Ceux d'une ACTION se déclenchent
  // aux six points du geste de celui qui frappe ; ceux d'une UNITÉ lui
  // appartiennent (elle encaisse, elle prend la main, elle choisit une
  // commande) et n'ont pas tous un geste derrière eux. Les mélanger ferait
  // proposer partout des moments que l'entrée ne peut pas atteindre.
  const unitMoments = parseGdStringArray(battleData, "UNIT_SOUNDS");
  const unitMomentNotes = parseGdStringArrayNotes(battleData, "UNIT_SOUNDS");
  // Les ÉTATS D'ANIMATION que le moteur va chercher par leur nom. Les deux
  // fichiers ne portent pas les mêmes : la scène tient le tour d'un allié
  // (repos, visée, attente, victoire), l'assaut tient le retour à
  // l'emplacement. Une planche nommée autrement reste valide — c'est ainsi
  // qu'une action désigne la sienne — mais AUCUN état ne la jouera.
  const animationStates = [
    ...(parseGdAnimationStates(battleScene) || []),
    ...(parseGdAnimationStates(assault) || []),
  ].reduce((kept, state) => {
    // DÉDOUBLONNAGE PAR ÉTAT, pas par constante. Un même état peut être
    // déclaré dans les DEUX fichiers — `idle` l'est, parce que l'écran et la
    // phase d'assaut le jouent tous les deux et qu'aucun ne peut lire les
    // constantes de l'autre. Sans ça, la liste déroulante proposait deux fois
    // « Repos » et l'auteur se demandait laquelle choisir.
    const seen = kept.find((s) => s.key === state.key);
    if (!seen) kept.push(state);
    // À doublon, on garde le commentaire le plus fourni : il n'y a aucune
    // raison que ce soit toujours le premier fichier lu qui l'explique le mieux.
    else if (state.note.length > seen.note.length) seen.note = state.note;
    return kept;
  }, []);
  const actionDefault = parseGdActionAnimationDefault(assault, animationStates);

  res.json({
    animation_states: animationStates.length ? animationStates : [
      { key: "idle", constant: "ANIM_IDLE", note: "pose de repos" },
      { key: "atkeff", constant: "ANIM_AIMING", note: "pose de visée, pendant le ciblage" },
      { key: "standby", constant: "ANIM_STANDBY", note: "attente, action retenue" },
      { key: "win_before", constant: "ANIM_WIN_BEFORE", note: "célébration, jouée une fois" },
      { key: "win", constant: "ANIM_WIN", note: "pose de victoire, tenue" },
      { key: "move_back", constant: "ANIM_RETURN", note: "retour à l'emplacement" },
    ],
    action_animation_default: actionDefault || "attack",
    moments: moments || ["announce", "rhythm", "approach", "gesture", "hit", "return"],
    // Repli volontairement PLUS PAUVRE que les commentaires du .gd : il dit
    // l'essentiel sans prétendre être à jour. Une copie détaillée finirait par
    // contredire le code, ce qui est exactement ce qu'on évite en le lisant.
    moment_notes: momentNotes || {
      announce: "la pastille de l'action s'affiche",
      rhythm: "la séquence de notes commence",
      approach: "l'attaquant s'élance vers sa cible",
      gesture: "le geste part",
      hit: "l'effet s'applique",
      return: "l'attaquant repart vers son emplacement",
    },
    unit_moments: unitMoments || [
      "turn", "menu_attack", "menu_eko", "menu_items", "menu_guard", "hurt",
    ],
    unit_moment_notes: unitMomentNotes || {
      turn: "l'unité prend la main",
      menu_attack: "elle retient « Attack »",
      menu_eko: "elle ouvre sa liste d'Ekos",
      menu_items: "elle ouvre le sac",
      menu_guard: "elle se met en garde",
      hurt: "elle encaisse des dégâts",
    },
    notes: notes || ["cross", "circle", "square", "triangle", "up", "down", "left", "right"],
    targets: ["enemy", "enemies", "ally", "allies", "self"],
    damage_types: ["direct", "injury"],
    behaviours: ["random", "aggressive", "defensive", "focused"],
    parsed: {
      moments: Boolean(moments),
      moment_notes: Boolean(momentNotes),
      unit_moments: Boolean(unitMoments),
      unit_moment_notes: Boolean(unitMomentNotes),
      notes: Boolean(notes),
    },
  });
});

// ---------- Systèmes : catalogue auto-détecté à partir de Scripts/ ----------
// Rien n'est déclaré à la main : le simple fait d'ajouter un .gd sous
// Scripts/ le fait apparaître ici, avec sa description tirée de son
// commentaire de doc ("##") pour rester la seule source de vérité.

async function walkFiles(dir, extension) {
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  let results = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results = results.concat(await walkFiles(full, extension));
    } else if (entry.name.endsWith(extension)) {
      results.push(full);
    }
  }
  return results;
}

function parseDescription(content) {
  const lines = content.split("\n");
  let startIdx = lines.findIndex((l) => /^\s*(extends|class_name)\s/.test(l));
  if (startIdx === -1) startIdx = -1;
  const desc = [];
  for (let i = startIdx + 1; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (trimmed === "") {
      if (desc.length) break;
      continue;
    }
    if (trimmed.startsWith("##")) {
      desc.push(trimmed.replace(/^##\s?/, ""));
    } else {
      break;
    }
  }
  return desc.join(" ");
}

function parseAutoloadPaths() {
  const paths = new Set();
  let raw;
  try {
    raw = fsSync.readFileSync(PROJECT_GODOT_PATH, "utf-8");
  } catch {
    return paths;
  }
  let inAutoload = false;
  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("[")) {
      inAutoload = trimmed === "[autoload]";
      continue;
    }
    if (!inAutoload) continue;
    const m = trimmed.match(/="\*?(res:\/\/[^"]+)"/);
    if (m) paths.add(m[1]);
  }
  return paths;
}

app.get("/api/systems", async (req, res) => {
  try {
    const [scriptFiles, sceneFiles] = await Promise.all([
      walkFiles(SCRIPTS_DIR, ".gd"),
      walkFiles(SCENES_DIR, ".tscn"),
    ]);
    const autoloadPaths = parseAutoloadPaths();
    const scenes = await Promise.all(
      sceneFiles.map(async (f) => ({
        name: path.basename(f),
        content: await fs.readFile(f, "utf-8"),
      }))
    );

    const systems = await Promise.all(
      scriptFiles.map(async (file) => {
        const relFromScripts = path.relative(SCRIPTS_DIR, file);
        const resPath = "res://Scripts/" + relFromScripts.split(path.sep).join("/");
        const content = await fs.readFile(file, "utf-8");
        const parts = relFromScripts.split(path.sep);
        return {
          name: parts[parts.length - 1].replace(/\.gd$/, ""),
          path: resPath,
          category: parts.length > 1 ? parts[0] : "Racine",
          description: parseDescription(content),
          isAutoload: autoloadPaths.has(resPath),
          usedIn: scenes.filter((s) => s.content.includes(resPath)).map((s) => s.name),
        };
      })
    );

    systems.sort(
      (a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name)
    );
    res.json(systems);
  } catch (err) {
    res.status(500).json({ error: String(err) });
  }
});

const GODOT_BIN = "/Applications/Godot.app/Contents/MacOS/Godot";

app.post("/api/play", (req, res) => {
  if (!fsSync.existsSync(GODOT_BIN)) {
    return res.status(500).json({ error: `Godot introuvable à ${GODOT_BIN}` });
  }
  const { mapId } = req.body || {};
  const args = ["--path", PROJECT_ROOT];
  if (mapId && isValidId(mapId)) {
    args.push("--", `--map=${mapId}`);
  }
  try {
    const child = spawn(GODOT_BIN, args, { detached: true, stdio: "ignore" });
    child.unref();
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: String(err) });
  }
});

const PORT = process.env.PORT || 5173;
app.listen(PORT, () => {
  console.log(`MapEditor sur http://localhost:${PORT}`);
});
