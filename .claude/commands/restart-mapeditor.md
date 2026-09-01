---
description: Redémarre le serveur MapEditor (port 5173)
---

Redémarre le serveur MapEditor de ce projet :

1. Trouve le process qui écoute sur le port 5173 (`lsof -nP -iTCP:5173 -sTCP:LISTEN`).
2. Arrête-le (`kill <PID>`).
3. Relance-le depuis `tools/MapEditor` avec `npm run dev` (en arrière-plan, détaché).
4. Confirme qu'il répond (`curl -s http://localhost:5173/api/texts` ou équivalent) avant de dire que c'est bon.

Utile après toute modification de `tools/MapEditor/server.js` : le code serveur n'est pas rechargé à chaud, contrairement à `public/*.js`/`.html`/`.css`.
