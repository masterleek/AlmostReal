export async function listMaps() {
  const res = await fetch("/api/maps");
  return res.json();
}

export async function loadMap(id) {
  const res = await fetch(`/api/maps/${id}`);
  if (!res.ok) throw new Error("map not found");
  return res.json();
}

// Levée par saveMap() quand le serveur refuse la sauvegarde (verrou
// optimiste, cf. server.js) : la map a changé sur disque depuis le dernier
// chargement de ce client (autre onglet/session). `message` est déjà prêt à
// afficher tel quel à l'utilisateur.
export class MapConflictError extends Error {
  constructor(message, currentRev) {
    super(message);
    this.name = "MapConflictError";
    this.currentRev = currentRev;
  }
}

export async function saveMap(id, map) {
  const res = await fetch(`/api/maps/${id}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(map),
  });
  const body = await res.json();
  if (res.status === 409) {
    throw new MapConflictError(body.message, body.currentRev);
  }
  // Garde `map._rev` en phase avec le serveur : nécessaire pour que la
  // PROCHAINE sauvegarde de ce même objet (muté en place par les appelants)
  // soit acceptée sans devoir recharger entre chaque save.
  if (body.rev !== undefined) map._rev = body.rev;
  return body;
}

export async function deleteMap(id) {
  const res = await fetch(`/api/maps/${id}`, { method: "DELETE" });
  return res.json();
}

// Levée quand le serveur refuse une sauvegarde : le fichier a changé sur disque
// depuis que cette page l'a chargé, ou la page est trop ancienne pour dire sur
// quelle version elle travaille.
export class CatalogConflictError extends Error {
  constructor(message) {
    super(message);
    this.name = "CatalogConflictError";
  }
}

// Empreinte du fichier tel que cette page l'a chargé, par route.
//
// UNE SEULE PAIRE POUR LES CINQ CATALOGUES servis par metaRoutes — tuiles,
// props, textes, catalogues de combat, libellés de moments. Ils avaient chacun
// leur paire recopiée ; la conséquence n'était pas seulement de la répétition :
// quand le verrou est arrivé, il n'a été branché que sur les catalogues de
// combat, et les quatre autres sont restés sans protection.
const revisions = new Map();

async function loadCatalog(url) {
  const res = await fetch(url);
  const revision = res.headers.get("X-Catalog-Revision");
  if (revision) revisions.set(url, revision);
  else revisions.delete(url);
  return res.json();
}

async function saveCatalog(url, body) {
  const headers = { "Content-Type": "application/json" };
  const revision = revisions.get(url);
  if (revision) headers["X-Expected-Revision"] = revision;
  const res = await fetch(url, {
    method: "PUT", headers, body: JSON.stringify(body),
  });
  const payload = await res.json();
  if (res.status === 409 || res.status === 428) {
    // L'AVERTISSEMENT EST POSÉ ICI, dans la couche qui connaît le refus, et
    // pas laissé à chaque appelant. Ces sauvegardes sont lancées sans `catch`
    // depuis quatre pages : un refus s'y perdrait en promesse rejetée, et
    // l'auteur continuerait d'éditer une page dont plus rien n'est enregistré.
    // C'est exactement le silence qui a coûté deux fois des données.
    alert(payload.message);
    throw new CatalogConflictError(payload.message);
  }
  // La page garde le MÊME objet en mémoire d'une sauvegarde à l'autre : sans
  // cette mise à jour, la deuxième se ferait refuser par le verrou qu'on vient
  // de poser nous-mêmes.
  const next = res.headers.get("X-Catalog-Revision");
  if (next) revisions.set(url, next);
  return payload;
}

// Le fichier a-t-il changé sur disque depuis que cette page l'a chargé ? Une
// requête HEAD : on ne veut que l'empreinte, pas le catalogue entier.
function rememberRevision(url, revision) {
  revisions.set(url, revision);
}

async function catalogChanged(url) {
  const known = revisions.get(url);
  if (!known) return false;
  const res = await fetch(url, { method: "HEAD" });
  const current = res.headers.get("X-Catalog-Revision");
  return current !== null && current !== known;
}

export const getTiles = () => loadCatalog("/api/tiles");
export const saveTiles = (tiles) => saveCatalog("/api/tiles", tiles);
export const getProps = () => loadCatalog("/api/props");
export const saveProps = (props) => saveCatalog("/api/props", props);
export const getTexts = () => loadCatalog("/api/texts");
export const saveTexts = (catalog) => saveCatalog("/api/texts", catalog);

export async function getSystems() {
  const res = await fetch("/api/systems");
  return res.json();
}

// Les trois catalogues de combat partagent une seule paire de fonctions : ils
// ont la même route à un segment près, et les distinguer par trois paires
// identiques ne dirait rien de plus.
export const getBattleCatalog = (name) => loadCatalog(`/api/battle/${name}`);
export const saveBattleCatalog = (name, catalog) =>
  saveCatalog(`/api/battle/${name}`, catalog);
export const battleCatalogChanged = (name) => catalogChanged(`/api/battle/${name}`);

export async function getBattleSounds() {
  const res = await fetch("/api/battle/sounds");
  return res.json();
}

// Dépose un son dans Audio/Battle/Actions et rend le chemin `res://` qui en
// découle. Jumeau de `uploadBattleSheet` : corps brut, pas de multipart, et un
// `imported` qui dit si Godot a pu enchaîner sa passe — à faux, le fichier est
// là mais le jeu ne saura pas le jouer tant que l'éditeur Godot n'aura pas été
// ouvert une fois.
export async function uploadBattleSound(file, name, { overwrite = false } = {}) {
  const query = `?name=${encodeURIComponent(name)}${overwrite ? "&overwrite=1" : ""}`;
  const res = await fetch("/api/battle/sounds" + query, {
    method: "POST",
    // Le type déclaré par le navigateur peut être vide (certains .wav) : on
    // retombe alors sur un type générique que la route accepte, l'extension et
    // la signature faisant foi côté serveur.
    headers: { "Content-Type": file.type || "application/octet-stream" },
    body: file,
  });
  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    throw new Error(body?.error || `Import refusé (HTTP ${res.status}).`);
  }
  return body;
}

// Planches disponibles sous Sprites/Battle/, avec l'URL qui les sert : le choix
// d'une planche est une LISTE, et l'éditeur peut montrer l'image.
export async function getBattleSheets() {
  const res = await fetch("/api/battle/sheets");
  if (!res.ok) return [];
  try {
    return await res.json();
  } catch {
    return [];
  }
}

// Dépose un PNG dans Sprites/Battle et rend le chemin `res://` qui en découle.
// Le fichier part TEL QUEL dans le corps (image/png) : pas de multipart, donc
// pas de dépendance côté serveur pour un seul formulaire.
//
// `imported` dit si Godot a pu enchaîner sa passe d'import. À faux, le fichier
// est bien sur le disque mais le jeu ne saura pas le charger tant que l'éditeur
// Godot n'aura pas été ouvert une fois — l'appelant doit le dire.
export async function uploadBattleSheet(file, name, { overwrite = false } = {}) {
  const query = `?name=${encodeURIComponent(name)}${overwrite ? "&overwrite=1" : ""}`;
  const res = await fetch("/api/battle/sheets" + query, {
    method: "POST",
    headers: { "Content-Type": "image/png" },
    body: file,
  });
  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    throw new Error(body?.error || `Import refusé (HTTP ${res.status}).`);
  }
  return body;
}

// Renomme une planche déjà déposée. `from`/`to` sont des NOMS de fichier
// (`noah_idle.png`), pas des chemins `res://` : c'est ce que porte l'invite qui
// appelle cette fonction, et le chemin complet ne s'en déduit que côté serveur
// (dossier fixe, `Sprites/Battle/`).
export async function renameBattleSheet(from, to, { overwrite = false } = {}) {
  const query = overwrite ? "?overwrite=1" : "";
  const res = await fetch("/api/battle/sheets/rename" + query, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ from, to }),
  });
  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    throw new Error(body?.error || `Renommage refusé (HTTP ${res.status}).`);
  }
  return body;
}

export async function getBattleVocabulary() {
  const res = await fetch("/api/battle/vocabulary");
  return res.json();
}

// Libellés d'affichage des moments de son. Côté OUTIL : le moteur ne connaît
// que les clés, renommer ne touche ni au jeu ni aux catalogues de Battle/.
//
// DÉGRADE au lieu d'échouer. Ces libellés ne sont que de la présentation — sans
// eux la page affiche les clés, ce qui reste utilisable. Une route absente
// (serveur pas encore relancé après une mise à jour) rend une page d'erreur
// HTML, dont `res.json()` lève : sans ce repli, une simple question de
// présentation empêchait la page entière de s'ouvrir.
// `stale` dit que le serveur ne connaît PAS cette route — donc qu'il tourne sur
// une version antérieure de server.js. Les routes de cette livraison
// (`moment-labels` et le service de `/audio`) sont arrivées ensemble : ce seul
// signal suffit à savoir que l'écoute ne marchera pas non plus, sans aller le
// vérifier par une seconde requête.
export async function getBattleMomentLabels() {
  const res = await fetch("/api/battle/moment-labels");
  if (!res.ok) return { labels: {}, stale: true };
  try {
    const data = await res.json();
    // Retenir l'empreinte comme loadCatalog le ferait : sans elle, la
    // sauvegarde des libellés serait refusée par le verrou.
    const revision = res.headers.get("X-Catalog-Revision");
    if (revision) rememberRevision("/api/battle/moment-labels", revision);
    return data;
  } catch {
    return { labels: {}, stale: true };
  }
}

export const saveBattleMomentLabels = (data) =>
  saveCatalog("/api/battle/moment-labels", data);

export async function playGame(mapId) {
  const res = await fetch("/api/play", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mapId }),
  });
  return res.json();
}
