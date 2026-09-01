# AlmostReal — instructions pour Claude

Jeu de gestion/exploration en Godot 4.6 (GDScript), vue isométrique hexagonale.
Repo git, remote `origin` → github.com/masterleek/AlmostReal, branche `main`.

## Environnement

- Le binaire Godot n'est **pas** dans le PATH (`godot` introuvable). Utiliser le
  chemin complet : `/Applications/Godot.app/Contents/MacOS/Godot`
- Check de syntaxe rapide (sans lancer le jeu) :
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 3`
- Après l'ajout d'un nouvel asset au projet (image, son...), il faut un passage
  d'import avant de pouvoir le référencer dans une scène (génère le `.import` +
  l'UID) :
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --quit-after 15`
  (relire ensuite le `uid=` dans le `.import` généré pour l'`ext_resource` de
  la `.tscn`)
- Préférer les outils `mcp__godot__run_project` / `get_debug_output` /
  `stop_project` à `Bash` pour lancer le jeu et lire sa sortie en live.

## Assets

- Les assets bruts fournis par l'utilisateur atterrissent dans `../_assets/`
  (dossier frère du repo, non versionné). Toujours les copier dans le bon
  sous-dossier du projet avant utilisation :
  - `Sprites/` : tuiles, personnages, props, VFX en jeu.
  - `UI/` : icônes, curseurs, highlights, éléments de HUD.
- Un asset à fond vert uni (chroma-key) doit être dékeyé (alpha) avant import
  — jamais utilisé tel quel.

## MapEditor (`tools/MapEditor`)

- **Verrou optimiste sur les maps** (`server.js` : `POST /api/maps/:id`) :
  chaque map a un compteur `_rev`, incrémenté à chaque sauvegarde. Un onglet
  qui essaie de sauvegarder avec une `_rev` périmée (quelqu'un d'autre a
  sauvegardé depuis son dernier chargement) se fait refuser (409) plutôt que
  d'écraser silencieusement — cf. l'incident `Test.json`/`Worldmap.json` (un
  onglet resté ouvert sur l'ancien état a régénéré le fichier par-dessus du
  travail fait ailleurs). Si `server.js`, `api.js`, `app.js` ou `maps.js` sont
  retouchés côté sauvegarde de map, préserver ce mécanisme (ne pas
  réintroduire un `fs.writeFile` sans vérifier `_rev` d'abord).

## Qualité de code attendue

- Code propre, logique, optimisé côté performance.
- Découper fichiers et méthodes pour qu'ils soient réutilisables ailleurs dans
  le projet — éviter autant que possible le code spécifique à un seul cas
  d'usage.

Deux nuances à garder en tête avant d'appliquer ça trop littéralement, pour ne
pas partir en guerre contre des choix déjà faits et documentés dans ce repo :

- **Le scaffolding de debug temporaire** (cf. workflow de vérification
  ci-dessous) est hors sujet : par construction jetable, jamais commité,
  jamais généralisé — "pas de code spécifique" vise le code livré, pas ces
  vérifications ponctuelles.
- **Une fonction délibérément spécifique à un seul cas reste parfois la
  bonne décision**, quand la version générique existante s'est avérée
  mesurablement fausse pour ce cas précis — voir
  `TileGeometry.tile_empty_hitzone()` (silhouette mesurée pixel par pixel
  pour "Empty" uniquement ; `tile_art_hitzone()` reste la version générique
  pour tout le reste). Le commentaire du fichier explique pourquoi la
  généricité a été sacrifiée là : si le même besoin se reproduit, spécialiser
  consciemment et documenter pourquoi vaut mieux que forcer une solution
  générique inexacte.
- **"Optimisé" ne veut pas dire micro-optimiser sans discernement** : cf.
  `TileGeometry` qui réalloue volontairement un petit tableau à chaque appel
  plutôt que d'utiliser un `const` (qui, lui, casse la résolution
  inter-scripts sur cette version de Godot) — un coût jugé négligeable
  (tableau minuscule, appels rares) a été accepté pour la fiabilité. Une
  "optimisation" qui complexifie le code pour un gain non mesurable n'est pas
  souhaitable.

## Conventions de code (GDScript)

- **`preload()` plutôt que `class_name` global** pour accéder à un autre
  script (ex. `const TileGeometry = preload("res://Scripts/Worldmap/TileGeometry.gd")`)
  : la résolution par `class_name` seul s'est avérée peu fiable au tout
  premier chargement headless du projet. Voir `WorldmapCursor.gd`,
  `HeroShadow.gd`, `TileRevealController.gd`.
- **Fonctions statiques plutôt que `const` pour des tableaux** partagés entre
  scripts (`TileGeometry.gd`) : un `const` de type tableau ne se résout pas de
  façon fiable en accès inter-scripts sur cette version de Godot.
- **Commentaires en français, denses, orientés "pourquoi"** — pas juste
  "quoi". Le code existant explique systématiquement le raisonnement (pourquoi
  ce mécanisme plutôt qu'un autre), pas seulement l'action. Suivre ce style
  pour tout nouveau code.
- **Jamais de commentaire `#` en dehors d'un script GDScript** — un `.tscn`
  n'accepte PAS de ligne `#` libre dans sa section ressources (avant les
  `[node]`) : ça corrompt silencieusement la table de résolution des
  `SubResource`/`ExtResource` du parseur (erreur obscure
  `int_resources.has(id)` à l'ouverture, sans lien évident avec la vraie
  cause). Toute la documentation "pourquoi" reste dans les `.gd`, jamais
  directement dans un `.tscn`.
- **`RichTextLabel` avec `bbcode_enabled` a des pièges de layout propres à
  ce nœud**, rencontrés en migrant `ActionLabel` (`Label` → `RichTextLabel`
  pour `Scripts/Localization.gd`) : `autowrap_mode` n'est pas désactivé par
  défaut comme sur `Label` — dans un `HBoxContainer`, ça peut écraser sa
  largeur à ~1px tant qu'il n'est pas explicitement mis à `0` (`AUTOWRAP_OFF`).
  Et `[b]` (BBCode) utilise l'item de thème `bold_font_size`, PAS
  `normal_font_size` — sans l'assigner aussi, le texte en gras retombe sur une
  taille de police par défaut du moteur (bien plus petite), pas juste "sans
  effet gras". Toujours régler explicitement `autowrap_mode = 0`,
  `bold_font_size` (= `normal_font_size`) et un `bold_font` réel
  (`FontVariation` avec `variation_embolden`, cf `Main.tscn`) plutôt que de
  compter sur des valeurs par défaut cohérentes avec `Label`. Autre piège du
  même genre : `clip_contents` vaut `true` par défaut sur `RichTextLabel`
  (`false` sur `Label`) — avec `fit_content = true`, la boîte est ajustée
  pile aux métriques nominales des glyphes, et l'outline/l'ombre (qui
  déborde de cette boîte, ex. `outline_size = 16`) se fait rogner sur les
  bords, surtout visible à gauche du premier caractère. Toujours mettre
  `clip_contents = false` explicitement sur un `RichTextLabel` qui a un
  outline/une ombre de thème.
- **Tri Y vs `z_index`** : `z_index` prime toujours sur le tri Y — deux nœuds
  dans des buckets `z_index` différents ne s'interclassent jamais. Pour qu'un
  overlay (ombre, highlight...) se laisse recouvrir par une tuile voisine tout
  en restant devant SA PROPRE tuile, le garder dans le même bucket que
  `TileMapLayer` (z=-1) et appliquer un nudge de position
  (`HIGHLIGHT_SORT_NUDGE`, `TileHoverVisuals.gd`) plutôt que de monter son
  `z_index`.
- **Masquage pixel-perfect** : pour garantir qu'un effet (ombre...) ne déborde
  jamais de la silhouette réelle d'une tuile, utiliser un shader
  `canvas_item` en espace MONDE (voir `HeroShadow.gd` +
  `hero_shadow_ellipse.gdshader`, ou `reveal_shadow_mask.gdshader`) plutôt que
  de compter sur la forme du `Polygon2D`/son `scale` seul.

## Workflow de vérification (avant de considérer une tâche terminée)

1. Check de syntaxe headless (`--quit-after 3`).
2. Pour un test comportemental/visuel : ajouter un scaffolding de debug
   temporaire dans `_ready()` de `Scripts/map_loader.gd` (script du nœud
   racine de `Main.tscn`), lancer via `mcp__godot__run_project`, lire
   `get_debug_output`, capturer un screenshot
   (`get_viewport().get_texture().get_image().save_png(...)`) dans le
   scratchpad de la session.
3. **Toujours retirer le scaffolding de debug et supprimer les PNG temporaires
   avant de terminer le tour** — `git diff --stat Scripts/map_loader.gd` doit
   revenir vide. Exception explicite : un PNG généré délibérément comme asset
   livré (ex. `Localization/previews/*.png`, consommé par la page "Textes"
   de MapEditor) se conserve — cette règle vise les captures de vérification
   ponctuelles, pas un asset généré intentionnellement.
4. L'environnement de debug peut tourner à une cadence irrégulière (plus
   vite/lentement que 60 fps réel) : éviter de compter sur un nombre de
   frames fixe pour viser un instant précis d'animation. Préférer
   `await get_tree().process_frame` lié à un vrai changement d'état, ralentir
   `AnimationPlayer.speed_scale` si besoin de capturer une phase précise, et
   simuler un vrai événement (`Input.parse_input_event()`) plutôt que de
   forcer l'état d'une action (`Input.action_press()`, qui ne teste pas le
   mapping réel clavier/manette → action).
5. Un screenshot pris juste après un changement d'état peut être obsolète
   (frame précédente) — recouper avec un `print()` du même état ou une
   attente liée à la vraie transition.
6. Si l'utilisateur signale qu'une touche/action "ne fait rien" en testant à
   la main : avant de soupçonner le code, vérifier qu'il a bien cliqué dans
   la vue du jeu (mode "Embed Game" de l'éditeur = focus clavier requis) —
   sinon les touches partent vers l'éditeur, pas vers le jeu.

## Modifications de `project.godot` (`[input]`, autoloads...)

- Ne jamais taper à la main un bloc `[input]` — risque d'erreur de syntaxe.
  Passer par un script temporaire (`ProjectSettings.set_setting(...)` +
  `ProjectSettings.save()`, exécuté une fois en headless) pour que Godot
  génère lui-même la sérialisation correcte.
- **L'éditeur Godot ne recharge pas `project.godot` à chaud** si le fichier
  est modifié depuis l'extérieur pendant qu'une session d'éditeur est déjà
  ouverte. Si un test en direct ne voit pas un changement (nouvelle action
  d'input, autoload...), vérifier d'abord un rechargement/redémarrage de
  l'éditeur avant de chercher un bug côté code.

## Git

- **Ne jamais commit/push/checkout/reset sans accord explicite de
  l'utilisateur pour CETTE instance précise** — même si l'état du repo semble
  le demander.
- Convention du projet : commits directement sur `main`, pas de branches de
  feature (historique de commits observé).
- Une fois une modification acceptée, proposer de commit rapidement si
  l'utilisateur ne l'a pas déjà demandé — des changements non commités ont
  déjà été perdus plusieurs fois dans ce projet (reverts locaux volontaires
  ou accidentels).
