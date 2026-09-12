import express from "express";
import fs from "fs/promises";
import fsSync from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { spawn } from "child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, "..", "..");
const MAPS_DIR = path.join(PROJECT_ROOT, "maps");
const SPRITES_DIR = path.join(PROJECT_ROOT, "Sprites");
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

const app = express();
app.use(express.json({ limit: "5mb" }));
app.use(express.static(path.join(__dirname, "public")));
app.use("/sprites", express.static(SPRITES_DIR));
app.use("/localization-previews", express.static(PREVIEWS_DIR));
app.use("/fonts", express.static(FONTS_DIR));

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
function metaRoutes(urlPath, filePath, defaultValue = []) {
  app.get(urlPath, async (req, res) => {
    try {
      const raw = await fs.readFile(filePath, "utf-8");
      res.json(JSON.parse(raw));
    } catch {
      res.json(defaultValue);
    }
  });

  app.put(urlPath, async (req, res) => {
    const body = req.body;
    if (!sameShape(body, defaultValue)) {
      return res.status(400).json({ error: "invalid payload" });
    }
    // Saut de ligne final : ces fichiers s'éditent AUSSI à la main, et
    // `JSON.stringify` n'en met pas. Sans lui, chaque sauvegarde depuis
    // l'éditeur produisait un diff git parasite (« \ No newline at end of
    // file ») sur un fichier par ailleurs inchangé.
    await fs.writeFile(filePath, JSON.stringify(body, null, 2) + "\n");
    res.json({ ok: true });
  });
}

metaRoutes("/api/tiles", TILE_META_PATH);
metaRoutes("/api/props", PROPS_META_PATH);
// Pas de verrou optimiste (_rev) ici contrairement aux maps : catalogue
// mono-utilisateur pour l'instant (cf CLAUDE.md) — même logique que
// tiles/props, rétrofitable avec le mécanisme des maps si l'édition
// concurrente devient un vrai problème.
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
// combat vit en JSON justement pour être éditable sans recompiler. Pas de
// verrou optimiste (_rev) ici non plus — catalogue mono-utilisateur, cf. la
// note sur /api/texts.
metaRoutes("/api/battle/units", path.join(BATTLE_DIR, "units.json"), { units: {} });
metaRoutes("/api/battle/ekos", path.join(BATTLE_DIR, "ekos.json"), { ekos: {} });
metaRoutes("/api/battle/items", path.join(BATTLE_DIR, "items.json"), { items: {} });

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
  const [assault, rhythm] = await Promise.all([
    readGd(BATTLE_ASSAULT_PATH),
    readGd(RHYTHM_BAR_PATH),
  ]);
  // Un repli est prévu pour chaque liste lue dans le code : si un refactor
  // renomme la constante, la page continue de fonctionner sur la dernière
  // valeur connue, et le champ `parsed` dit ce qui a réellement été lu — un
  // éditeur qui tombe en panne muette serait pire que la divergence qu'on
  // cherche à éviter.
  const moments = parseGdStringArray(assault, "SOUND_MOMENTS");
  const notes = parseGdDictionaryKeys(rhythm, "NOTE_ACTIONS");
  res.json({
    moments: moments || ["announce", "rhythm", "approach", "gesture", "hit", "return"],
    notes: notes || ["cross", "circle", "square", "triangle", "up", "down", "left", "right"],
    targets: ["enemy", "enemies", "ally", "allies", "self"],
    damage_types: ["direct", "injury"],
    behaviours: ["random", "aggressive", "defensive", "focused"],
    parsed: { moments: Boolean(moments), notes: Boolean(notes) },
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
