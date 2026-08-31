import { listMaps, deleteMap, loadMap, saveMap, MapConflictError } from "./api.js";

// Liste de toutes les maps dans la popup "Maps" : clic = ouvrir, double-clic =
// renommer, bouton = supprimer.
export async function renderMapBrowser(container, { onOpen, onDelete, onRename }) {
  const maps = await listMaps();
  container.innerHTML = "";

  if (maps.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-hint";
    empty.textContent = "Aucune map pour le moment.";
    container.appendChild(empty);
    return maps;
  }

  for (const map of maps) {
    const row = document.createElement("div");
    row.className = "modal-map-row";

    const name = document.createElement("span");
    name.className = "modal-map-name";
    name.textContent = map.name || map.id;
    name.title = "Clic pour ouvrir, double-clic pour renommer";

    let clickTimer = null;
    name.onclick = () => {
      if (name.classList.contains("editing")) return;
      if (clickTimer) return;
      clickTimer = setTimeout(() => {
        clickTimer = null;
        onOpen(map.id);
      }, 250);
    };
    name.ondblclick = (evt) => {
      evt.stopPropagation();
      if (clickTimer) {
        clearTimeout(clickTimer);
        clickTimer = null;
      }
      startRename(name, map, onRename);
    };

    const del = document.createElement("button");
    del.className = "modal-map-delete";
    del.textContent = "🗑";
    del.title = "Supprimer cette map";
    del.onclick = async (evt) => {
      evt.stopPropagation();
      if (!confirm(`Supprimer la map "${map.name || map.id}" ?`)) return;
      await deleteMap(map.id);
      onDelete(map.id);
    };

    row.append(name, del);
    container.appendChild(row);
  }

  return maps;
}

function startRename(nameEl, map, onRename) {
  nameEl.classList.add("editing");
  nameEl.contentEditable = "true";
  nameEl.focus();

  const range = document.createRange();
  range.selectNodeContents(nameEl);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  const finish = async (commit) => {
    nameEl.classList.remove("editing");
    nameEl.contentEditable = "false";
    nameEl.removeEventListener("blur", onBlur);
    nameEl.removeEventListener("keydown", onKeydown);

    const newName = nameEl.textContent.trim();
    if (commit && newName && newName !== map.name) {
      const full = await loadMap(map.id);
      full.name = newName;
      try {
        await saveMap(map.id, full);
      } catch (err) {
        if (err instanceof MapConflictError) {
          alert(err.message);
          nameEl.textContent = map.name || map.id;
          return;
        }
        throw err;
      }
      map.name = newName;
      onRename?.(map.id, newName);
    } else {
      nameEl.textContent = map.name || map.id;
    }
  };

  const onBlur = () => finish(true);
  const onKeydown = (evt) => {
    if (evt.key === "Enter") {
      evt.preventDefault();
      nameEl.blur();
    }
    if (evt.key === "Escape") {
      evt.preventDefault();
      finish(false);
    }
  };

  nameEl.addEventListener("blur", onBlur);
  nameEl.addEventListener("keydown", onKeydown);
}
