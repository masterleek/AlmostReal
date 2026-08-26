import { getSystems } from "./api.js";

const overlay = document.getElementById("systems-modal-overlay");
const closeBtn = document.getElementById("systems-modal-close");
const listEl = document.getElementById("systems-list");

function renderList(systems) {
  listEl.innerHTML = "";

  if (systems.length === 0) {
    const empty = document.createElement("p");
    empty.className = "hint";
    empty.textContent = "Aucun script sous Scripts/ pour l'instant.";
    listEl.appendChild(empty);
    return;
  }

  let currentCategory = null;
  for (const system of systems) {
    if (system.category !== currentCategory) {
      currentCategory = system.category;
      const label = document.createElement("p");
      label.className = "system-category-label";
      label.textContent = currentCategory;
      listEl.appendChild(label);
    }

    const row = document.createElement("div");
    row.className = "system-row";

    const head = document.createElement("div");
    head.className = "system-row-head";

    const name = document.createElement("span");
    name.className = "system-name";
    name.textContent = system.name;
    head.appendChild(name);

    if (system.isAutoload) {
      const badge = document.createElement("span");
      badge.className = "system-badge";
      badge.textContent = "Autoload";
      head.appendChild(badge);
    }

    row.appendChild(head);

    const path = document.createElement("span");
    path.className = "system-path";
    path.textContent = system.path;
    row.appendChild(path);

    if (system.description) {
      const desc = document.createElement("span");
      desc.className = "system-description";
      desc.textContent = system.description;
      row.appendChild(desc);
    }

    if (system.usedIn.length > 0) {
      const usedIn = document.createElement("span");
      usedIn.className = "system-used-in";
      usedIn.textContent = `Utilisé dans : ${system.usedIn.join(", ")}`;
      row.appendChild(usedIn);
    }

    listEl.appendChild(row);
  }
}

closeBtn.onclick = closeSystemsManager;
overlay.onclick = (evt) => {
  if (evt.target === overlay) closeSystemsManager();
};

function closeSystemsManager() {
  overlay.classList.add("hidden");
}

export async function openSystemsManager() {
  overlay.classList.remove("hidden");
  const systems = await getSystems();
  renderList(systems);
}
