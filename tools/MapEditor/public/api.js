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

export async function playGame(mapId) {
  const res = await fetch("/api/play", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mapId }),
  });
  return res.json();
}
