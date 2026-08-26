export async function listMaps() {
  const res = await fetch("/api/maps");
  return res.json();
}

export async function loadMap(id) {
  const res = await fetch(`/api/maps/${id}`);
  if (!res.ok) throw new Error("map not found");
  return res.json();
}

export async function saveMap(id, map) {
  const res = await fetch(`/api/maps/${id}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(map),
  });
  return res.json();
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

export async function playGame(mapId) {
  const res = await fetch("/api/play", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mapId }),
  });
  return res.json();
}
