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
- **Les avertissements d'inférence sont traités comme des ERREURS** dans ce
  projet : `var x := <expression Variant>` refuse de compiler. Deux cas
  rencontrés qui ne sautent pas aux yeux : `round()` (et les autres fonctions
  globales surchargées float/Vector) renvoie un `Variant`, et un appel de
  méthode statique via un `const Truc = preload(...)` aussi. Annoter
  explicitement (`var w: float = round(...)`) plutôt que de retirer le `:=`.
- **`PackedStringArray([...])` n'est pas une expression constante** : un
  `const X := PackedStringArray([...])` ne compile pas. Écrire
  `const X: PackedStringArray = ["a", "b"]` (littéral de tableau + type
  déclaré). Même famille de pièges que les `const` de tableaux, cf. plus haut.
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

## Écran de combat (`Scenes/Battle.tscn`, `Scripts/Battle/`)

- **Deux échelles cohabitent dans le projet.** Le worldmap est dessiné à
  l'échelle du viewport (1920×1080) ; les assets de combat, eux, sont dessinés
  pour un écran de **480×270** (= 1920/4). La scène de combat vit donc sous un
  nœud `Stage` à `scale = 4`, et **toutes ses coordonnées sont en unités de
  design 480×270**. Elles doivent rester ENTIÈRES : une position à virgule
  devient un demi-pixel flou une fois multipliée par 4 (d'où le
  `centered = false` + `offset` explicite de `UnitSprite`, plutôt que le
  centrage automatique qui casse sur une cellule de largeur impaire).
- Corollaire pour le texte : les `font_size` du combat sont eux aussi en
  unités de design (12 pour les libellés HP/AP, 15 pour les menus, 18 pour le
  compteur de PV). `BoldPixels1.4.ttf` a une hauteur de capitale qui vaut
  exactement **la moitié du corps** — c'est ce qui permet de déduire une
  taille depuis une mesure sur maquette.
- **Zoom de l'écran de combat** (`Scripts/UI/CanvasZoom.gd`, générique pour
  n'importe quel CanvasLayer) : mêmes gestes que la caméra du worldmap
  (molette, pincement, `0` pour revenir à la taille réelle). Une Camera2D
  n'agit pas sur un CanvasLayer — c'est justement sa raison d'être — donc le
  zoom passe par la transformation du calque : `offset = centre · (1 − zoom)`
  garde le centre de l'écran immobile. Deux écarts délibérés avec le
  worldmap : pas de dézoom sous la taille réelle (l'écran occupe exactement le
  cadre, réduire montrerait le vide), et les niveaux sont quantifiés au quart
  — un pixel de design occupe 4·zoom pixels d'écran, et ce produit doit rester
  entier pour que les blocs restent réguliers.
- **Quantifier une valeur accumulée : garder la valeur continue à part.** Le
  zoom stocke le niveau demandé (continu) ET le niveau appliqué (arrondi au
  quart) ; réinjecter l'arrondi dans le calcul suivant détruit les petits
  incréments. Symptôme rencontré : le pincement au trackpad ne faisait
  strictement rien, chacun de ses événements valant ~×1,02 et retombant sur le
  même palier — alors que la molette, qui avance par pas de 0,25, marchait.
- **`godot --path . -- --battle`** ouvre le combat par-dessus le worldmap, avec
  une vraie capture de fond. Même mécanique que `--map=` (`map_loader.gd`).
  C'est l'entrée de travail tant que le déclenchement d'un combat en jeu n'est
  pas conçu.
- `BattleLauncher` masque le HUD **avant** de capturer le fond, puis le décor
  **après** : masquer tout avant la capture ne donne qu'une image vide.
- **Le texte de combat est suréchantillonné, pas agrandi** (`BattleText.SUPERSAMPLE`) :
  les glyphes sont rasterisés ×4 puis le nœud est contre-échelonné d'autant.
  L'échelle cumulée vaut 1, donc la police sort nette à la résolution de
  l'écran, alors que le décor reste volontairement en blocs de 4×4. Sans ça,
  le texte hérite de l'agrandissement du Stage et sort en escaliers. Les
  coordonnées restent en unités de design : le décalage boîte → glyphe est une
  métrique de police, il suit la taille proportionnellement.
- **`get_viewport().get_texture()` rend la taille du FRAMEBUFFER, pas celle du
  canvas.** Avec `stretch/mode = canvas_items`, le canvas fait toujours
  1920×1080 mais la fenêtre peut faire autre chose (1676×942 dans la vue
  intégrée de l'éditeur). Une capture posée à l'échelle 1 ne couvre alors
  qu'un coin de l'écran. Toujours la remettre à l'échelle
  (`Vector2(canvas) / texture.get_size()`).
- **Une fenêtre de taille non multiple de 480×270 casse le pixel-art** : à
  1676 px de large le facteur vaut 3,49, donc les blocs alternent 3 et 4 px et
  tout paraît sale. Mesuré : à 1920×1080 les blocs font tous exactement 4 px et
  les pixels opaques d'un sprite sortent à la couleur source exacte. Pour juger
  du rendu, lancer en 1920×1080 (ou 960×540), pas dans la vue intégrée
  redimensionnée.
- **Les groupes d'interface du combat sont INCLINÉS** (menu −3°, HUD −4,2°,
  légende −5,5°), et les positions relevées sur la maquette contiennent déjà
  cette inclinaison. Les constantes du code sont donc les positions « à plat »,
  obtenues par rotation inverse — sinon l'inclinaison s'applique deux fois.
  `BattleScene._tilted_group()` fait pivoter un groupe autour d'un point tout
  en laissant écrire ses enfants en coordonnées absolues. Contrôle de
  cohérence : à plat, les deux blocs du HUD tombent sur la même ligne (y = 21)
  et les deux pastilles de touche de la légende aussi (y = 230).
- **Tous les assets ne sont pas du pixel-art — vérifier avant d'agrandir.**
  Beaucoup d'icônes d'interface du combat sont dessinées AVEC de
  l'anticrénelage : `ic_ap_on.png` avait la moitié de ses pixels en alpha
  partiel, `ic_ap_off.png` les deux tiers, `synergie_full.png` 40 %. Les
  agrandir au plus proche voisin transforme ce dégradé en escalier de blocs,
  c'est-à-dire détruit le travail de l'auteur. Test pour trancher sur un
  asset donné : compter ses pixels à alpha partiel. Les sprites de
  personnages et le décor, eux, sont bien du pixel-art et restent au plus
  proche voisin (`PixelScale.upscaled(texture)`, `smooth` par défaut à
  `false`).
- **Pour un PNG anticrénelé sans source vectorielle**, `PixelScale.upscaled(
  texture, smooth = true)` interpole en BILINÉAIRE — jamais Lanczos ni
  cubique : ces deux-là dépassent aux transitions et éclaircissent le halo,
  ce qui avait fait grossir les losanges d'AP au point de les souder entre
  eux (cœur mesuré à 7 px au lieu de 5, cf. asset ic_ap_on.png). Le
  bilinéaire n'invente aucune valeur plus vive que la source.
- **Quand l'asset EXISTE en vectoriel, préférer le SVG au PNG+interpolation**
  (toute la UI de combat est passée par là : pastilles, jauges, icônes,
  boutons de légende — cf. `UI/Battle/*.svg`) : net à l'écran, visiblement plus
  que le meilleur agrandissement d'un petit PNG (vérifié côte à côte, arêtes
  franches contre diffuses). Import : régler `svg/scale` sur
  `PixelScale.SCALE` (4) dans le `.import` — Godot rastérise le SVG une seule
  fois, AU MOMENT DE L'IMPORT, jamais au runtime ; sans ce réglage il
  rastérise à la taille nominale et perd tout l'intérêt du vectoriel. Un tel
  asset est déjà à la résolution de l'écran : le poser avec
  `PixelScale.upscaled()`/`sprite()` l'agrandirait une seconde fois pour
  rien — utiliser `PixelScale.sprite_native()` à la place.
- **Après un remplacement PNG → SVG natif, auditer CHAQUE usage de
  `texture.get_width()`/`get_height()`/`get_size()` sur cet asset** — pas
  seulement le `preload()`. Avant le remplacement, ces appels renvoyaient la
  taille de DESIGN (le PNG faisant cette taille-là) ; après, ils renvoient la
  taille RASTÉRISÉE (×4), silencieusement. Deux formes de bug rencontrées en
  généralisant le changement à `SynergyGauge`/`HpBar` :
  - un calcul qui servait à repasser en espace texture (`design * SCALE` pour
    un `region_rect`/`size` de `TextureProgressBar`) devient un double
    agrandissement (`SCALE` appliqué deux fois) — repérable : le calcul
    contenait déjà `* PixelScale.SCALE` quelque part ;
  - un calcul purement en espace DESIGN (centrer une icône dans une piste,
    calculer une largeur de remplissage proportionnelle à un ratio) devient
    4× trop grand, sans qu'aucun `SCALE` n'apparaisse nulle part dans le code
    à corriger — le bug est dans la valeur renvoyée par `get_width()`
    elle-même, pas dans une formule visible.
  Remède dans les deux cas : `PixelScale.design_size(texture)` plutôt que
  `Vector2(texture.get_width(), texture.get_height())` pour tout calcul en
  espace design. Vérifié après coup par introspection directe des nœuds en
  jeu (tailles/`region_rect` réels comparés à la valeur attendue), pas
  seulement par relecture — cf. `HpBar` à ratio 0,4/0,7 : régions attendues
  92×12 et 68×12, obtenues au pixel près.
- **ThorVG (le rendu SVG de Godot) ne rastérise pas une balise `<image>`
  (raster PNG/JPEG embarqué en base64 dans le SVG)** — rencontré sur les
  portraits (`battle_face_iris.svg`/`_noah.svg`, exportés avec la photo comme
  calque `<image>` sous un clip-path). Symptôme : un aplat de couleur uni, à
  la place du portrait — pas une erreur, pas un avertissement, un rendu
  silencieusement incomplet. Diagnostic sans ambiguïté : dumper
  `texture.get_image()` en PNG et comparer à un rendu de référence
  spec-compliant (`qlmanage -t` sur macOS suffit, WebKit rend les SVG
  correctement) — l'écart révèle immédiatement le calque manquant. Dans ce
  cas, revenir au PNG (`PixelScale.sprite(texture, offset, smooth=true)`) :
  ces portraits sont de l'illustration anticrénelée, pas du pixel-art, donc
  `smooth=true` (bilinéaire) reste la bonne interpolation même en PNG — c'est
  ce qui manquait déjà avant (défaut `smooth=false`), corrigé au passage.
  Un SVG dont TOUT le contenu est en formes vectorielles natives (paths,
  rects, circles, gradients — sans `<image>`) n'a pas ce problème ; vérifier
  par `grep -c '<image' fichier.svg` avant de se lancer dans un remplacement.
- **Ne pas déduire un espacement de la taille d'un asset** : l'icône « on »
  fait 11 px de large parce qu'elle porte un halo qui déborde, alors que les
  losanges sont espacés de 9 px sur la maquette (mesuré : 9,0 entre trois
  centres consécutifs) — ils se chevauchent donc légèrement. Un pas de 11
  étalait toute la rangée.
- **La jauge de synergie est une SPIRALE, pas un anneau** : mesuré angle par
  angle sur `synergie_underlayer.png`, plus aucune matière entre 200° et 260°.
  Sa bande utile ne fait donc que 300°, de 270° (extrémité épaisse et orange)
  à 200° (fine queue jaune) — le sens dans lequel court aussi le dégradé.
  D'où, dans `SynergyGauge`, un remplissage HORAIRE partant de 270° et une
  charge ramenée sur ces 300° : sur un balayage de 360°, la jauge paraîtrait
  pleine bien avant sa charge maximale.
- **Un élément TOURNÉ doit être amené à la résolution de l'écran avant la
  rotation** (`PixelScale`, même principe que le suréchantillonnage du texte) :
  sa texture est agrandie ×4 au plus proche voisin — les gros pixels d'origine
  sont donc préservés tels quels — puis le nœud est contre-échelonné d'autant
  et repasse en filtrage linéaire. Sans ça, le plus proche voisin n'a rien à
  interpoler et le bord descend par marches de 4 px au lieu de suivre la
  diagonale ; la maquette, elle, lisse ses bords tournés. Convention :
  `position` reste en unités de design (espace du parent), mais tout ce qui se
  mesure dans la TEXTURE — `offset`, `size`, `region_rect`, marges de 9-slice —
  est multiplié par `PixelScale.SCALE`.
  Deux corollaires : un `ColorRect` tourné garde des bords durs (Godot ne lisse
  pas les arêtes de quad) — passer par une texture unie ; et un enfant d'un
  nœud contre-échelonné hérite de cette échelle, d'où le libellé des pastilles
  de menu sorti de sa pastille (il a déjà la sienne).
- **Un gabarit horizontal recalé sur une maquette inclinée donne une position
  biaisée** : c'est ce qui avait décalé le menu de 2 px vers le haut. Mesurer
  l'angle d'abord (ajustement linéaire d'un bord franc, ou ACP sur les glyphes
  d'une ligne de texte), corriger les positions ensuite.
- **Style de texte de l'UI** : contour brun FIN + ombre portée de la même
  couleur, un seizième du corps chacun — c'est le compteur de hex du worldmap
  (`HexCounter/Count`), pas l'`ActionLabel` (contour d'un quart du corps, une
  exception pour un texte posé sur décor clair). C'est l'ombre qui donne son
  poids au texte ; épaissir le contour ne fait qu'empâter les petits corps.
  Les deux valeurs se calculent dans l'espace suréchantillonné, ce qui permet
  un contour plus fin qu'un pixel de design.
- **Ombre peinte et corps se séparent par l'alpha** : sur les trois planches de
  personnage, le corps est entièrement opaque et l'ombre portée est la seule
  zone semi-transparente. Un tri sur l'alpha suffit donc à les séparer, sans
  découpe manuelle ni asset supplémentaire — utile le jour où il faudra animer
  un personnage sans faire bouger son ombre. (Rien ne s'en sert aujourd'hui :
  les ennemis sont volontairement figés sur leur première frame, `frames: 1`
  dans units.json.)

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
- **Toujours `keycode`, jamais `physical_keycode`** pour une touche de clavier
  (c'est ce qu'utilisent toutes les actions existantes du projet).
  `physical_keycode` désigne une POSITION référencée sur un QWERTY US, alors
  que la machine de dev est en **AZERTY** : `physical_keycode = KEY_Z` y
  correspond à la touche marquée **W**, pas Z. Symptôme : l'action ne se
  déclenche jamais alors que tout le reste semble correct.
- **Corollaire pour les tests** : `Input.parse_input_event()` avec un
  `physical_keycode` fabriqué à la main NE teste PAS la disposition clavier —
  il court-circuite la traduction que fait l'OS. Pour vérifier une touche,
  injecter l'événement tel que le clavier réel l'enverrait (sur AZERTY, touche
  marquée Z = `keycode = KEY_Z` ET `physical_keycode = KEY_W`), sinon le test
  passe au vert sur un binding qui ne marche pas en vrai.
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
