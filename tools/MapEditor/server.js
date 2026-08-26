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

const app = express();
app.use(express.json({ limit: "5mb" }));
app.use(express.static(path.join(__dirname, "public")));
app.use("/sprites", express.static(SPRITES_DIR));

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
    res.json(JSON.parse(raw));
  } catch {
    res.status(404).json({ error: "map not found" });
  }
});

app.post("/api/maps/:id", async (req, res) => {
  const { id } = req.params;
  if (!isValidId(id)) return res.status(400).json({ error: "invalid id" });
  const map = req.body;
  map.id = id;
  await fs.writeFile(
    path.join(MAPS_DIR, `${id}.json`),
    JSON.stringify(map, null, 2)
  );
  res.json({ ok: true });
});

app.delete("/api/maps/:id", async (req, res) => {
  const { id } = req.params;
  if (!isValidId(id)) return res.status(400).json({ error: "invalid id" });
  await fs.unlink(path.join(MAPS_DIR, `${id}.json`));
  res.json({ ok: true });
});

function metaRoutes(urlPath, filePath) {
  app.get(urlPath, async (req, res) => {
    try {
      const raw = await fs.readFile(filePath, "utf-8");
      res.json(JSON.parse(raw));
    } catch {
      res.json([]);
    }
  });

  app.put(urlPath, async (req, res) => {
    const list = req.body;
    if (!Array.isArray(list)) return res.status(400).json({ error: "expected an array" });
    await fs.writeFile(filePath, JSON.stringify(list, null, 2));
    res.json({ ok: true });
  });
}

metaRoutes("/api/tiles", TILE_META_PATH);
metaRoutes("/api/props", PROPS_META_PATH);

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
