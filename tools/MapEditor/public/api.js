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

export async function getTiles() {
  const res = await fetch("/api/tiles");
  return res.json();
}

export async function saveTiles(tiles) {
  const res = await fetch("/api/tiles", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(tiles),
  });
  return res.json();
}

export async function getProps() {
  const res = await fetch("/api/props");
  return res.json();
}

export async function saveProps(props) {
  const res = await fetch("/api/props", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(props),
  });
  return res.json();
}

export async function getSystems() {
  const res = await fetch("/api/systems");
  return res.json();
}

export async function getTexts() {
  const res = await fetch("/api/texts");
  return res.json();
}

export async function saveTexts(catalog) {
  const res = await fetch("/api/texts", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(catalog),
  });
  return res.json();
}

// Les trois catalogues de combat partagent une seule paire de fonctions : ils
// ont la même route à un segment près, et les distinguer par trois paires
// identiques ne dirait rien de plus.
export async function getBattleCatalog(name) {
  const res = await fetch(`/api/battle/${name}`);
  return res.json();
}

export async function saveBattleCatalog(name, catalog) {
  const res = await fetch(`/api/battle/${name}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(catalog),
  });
  return res.json();
}

export async function getBattleSounds() {
  const res = await fetch("/api/battle/sounds");
  return res.json();
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
    return await res.json();
  } catch {
    return { labels: {}, stale: true };
  }
}

export async function saveBattleMomentLabels(data) {
  const res = await fetch("/api/battle/moment-labels", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  return res.json();
}

export async function playGame(mapId) {
  const res = await fetch("/api/play", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mapId }),
  });
  return res.json();
}
