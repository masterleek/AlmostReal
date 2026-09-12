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

### Page « Combat » (`public/battle.js`)

- **Un vocabulaire fermé partagé avec le moteur se LIT dans le `.gd`, il ne se
  recopie pas.** `/api/battle/vocabulary` extrait `SOUND_MOMENTS` de
  `BattleAssault.gd` et les clés de `NOTE_ACTIONS` de `RhythmBar.gd` — deux
  listes qui disent la même chose finissent par se contredire. Chaque lecture a
  un repli littéral : un refactor qui renomme la constante doit dégrader la
  page, pas la casser en silence. Les vocabulaires SANS déclaration unique côté
  moteur (ciblage, nature des dégâts, comportements — éparpillés dans des
  `match`) restent écrits côté serveur, et le code le dit.
- **Un champ de ce genre est une liste déroulante, jamais une saisie libre** :
  une faute de frappe n'y produit pas une erreur mais un silence (un son qui ne
  part jamais, un ennemi qui frappe au hasard), découvert seulement en lançant
  ce combat-là.
- **Un champ numérique FACULTATIF doit retirer sa clé à 0**, pas écrire `0` :
  sinon la première visite de la page ajoute des champs que personne n'a
  demandés à chaque entrée du catalogue. Ne s'applique QU'AUX champs dont le
  défaut moteur est 0 — `guard_below` vaut 0,35, y effacer un 0 changerait le
  sens.
- **`JSON.stringify` n'écrit pas de saut de ligne final** : ces catalogues
  s'éditent aussi à la main, et sans lui chaque sauvegarde depuis l'éditeur
  produit un diff git parasite sur un fichier par ailleurs inchangé.
- **Vérifier une page d'édition par un ALLER-RETOUR**, pas seulement par une
  écriture : modifier une valeur puis la remettre doit rendre le fichier
  identique au byte près (`git status` vide). C'est ce test qui a révélé le
  saut de ligne manquant et les clés facultatives écrites à 0.
- Le serveur du MapEditor **ne se recharge pas tout seul** : après une
  modification de `server.js`, le relancer (les fichiers de `public/` sont
  servis depuis le disque et n'ont, eux, besoin que d'un rafraîchissement).

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
- **`const` de tableau partagé entre scripts : VÉRIFIÉ OK en 4.6.2.** La règle
  précédente (« toujours passer par une fonction statique ») venait d'une
  version plus ancienne et a été retestée : via `const X = preload(...)`, un
  `const SLOTS: Array[Vector2i]`, un `PackedStringArray` et un `Vector2` se
  lisent, s'indexent et se parcourent correctement depuis un autre script.
  `TileGeometry.gd` garde ses fonctions statiques pour une AUTRE raison, qui
  tient toujours (elle est documentée dans le fichier). Ne pas invoquer cette
  contre-indication sans la reteste : une règle périmée oriente les décisions
  aussi sûrement qu'une règle juste.
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
- **Entrées du combat** : navigation par les actions natives `ui_up`/`ui_down`
  (flèches + croix directionnelle), validation/annulation par `battle_confirm`
  et `battle_cancel` — des actions PROPRES au combat, volontairement distinctes
  du `ui_accept` que le worldmap utilise déjà pour ses propres actions, pour
  qu'un rebind d'un écran ne déplace pas l'autre. Une liste (`CommandMenu`) ne
  lit les entrées que si son drapeau `active` est vrai : plusieurs listes
  coexisteront (menu racine + liste d'Ekos), et c'est l'appelant qui arbitre
  laquelle a la main — une liste ne se donne jamais le focus d'elle-même.
- **`godot --path . -- --battle`** ouvre le combat par-dessus le worldmap, avec
  une vraie capture de fond. Même mécanique que `--map=` (`map_loader.gd`).
  C'est l'entrée de travail tant que le déclenchement d'un combat en jeu n'est
  pas conçu.
- `BattleLauncher` masque le HUD **avant** de capturer le fond, puis le décor
  **après** : masquer tout avant la capture ne donne qu'une image vide.
- **`PROCESS_MODE_DISABLED` suspend aussi un `AudioStreamPlayer`**, alors que
  la lecture audio ne passe pas par `_process`. Mesuré : le thème du worldmap
  voit `playing` retomber à `false` et sa position se figer dès l'ouverture du
  combat, puis la lecture **reprend à cette position** quand `close()` rend la
  main. Rien à couper ni à relancer à la main pour poser une musique de
  combat — et deux thèmes ne peuvent pas se superposer.
- **Le bouclage d'un flux audio est une propriété de la RESSOURCE, pas du
  lecteur** : `player.stream.loop = true`, et non un réglage sur le
  `AudioStreamPlayer`. Vaut pour le thème du worldmap comme pour celui du
  combat. Conséquence : c'est la ressource partagée qu'on modifie, deux
  lecteurs sur le même fichier ne peuvent pas boucler différemment.
- **Les sons d'une action vivent dans le JSON de l'action, pas dans le code.**
  `sounds` se lit au même endroit que `power`, `animation` et `sequence` :
  `basic_attack` pour une attaque, le catalogue pour un Eko ou un objet. Un
  `if unit.id == "noah"` dans `BattleAssault` reviendrait à écrire le casting
  dans le moteur, et fermerait la porte à l'édition depuis MapEditor (Lot 10).
  Chaque entrée porte son moment (`at`, cf. `SOUND_MOMENTS`) ; plusieurs
  chemins sur une entrée sont des VARIANTES tirées au hasard, pas des sons
  joués ensemble.
- **Un son d'action s'émet UNE fois par action, pas une par cible** : une
  attaque de groupe est un seul geste, et trois copies du même cri lancées dans
  la même frame se superposent en bouillie.
- **Un « moment » nommé dans de la donnée doit être un point RÉEL du code**, et
  la liste doit être fermée et vérifiée : un `at` inventé est ignoré avec un
  avertissement plutôt que de faire un son qui ne part jamais sans rien dire.
  Corollaire mesuré : deux ancres voisines peuvent tomber dans la même frame
  (`announce` et `rhythm` aujourd'hui) — les garder distinctes est juste, mais
  il faut le DIRE, sinon on croit à un bug de déclenchement.
- **Un lecteur audio unique ne joue qu'un son par frame.** Deux sons demandés
  dans la même frame, le second écrase le premier — silencieusement. D'où le
  petit pool de lecteurs (`SFX_ACTION_VOICES`) dès qu'une action peut accrocher
  plusieurs sons au même moment.
- **`volume_linear` existe depuis Godot 4.4** : une consigne exprimée en
  pourcentage s'écrit `volume_linear = 0.75`, pas un `volume_db = -2.499`
  converti à la main et illisible six mois plus tard.
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
- **Un 9-slice dont les marges dépassent la taille du rectangle ne préserve
  plus rien — il fait une tache.** Le cadre « INFO » réutilisait son asset en
  28×15 avec des marges de 20 px par côté (40 au total) : Godot écrase alors
  les quatre coins les uns sur les autres, et quatre coins de rayon 15 empilés
  donnent un disque noir. Règle : `2 × marge` doit rester nettement sous la
  plus petite dimension du rectangle. Symptôme trompeur — le MÊME asset dans le
  MÊME code rend correctement en grand format, seul le petit usage dégénère.
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
- **Les planches de personnage portent leur ombre au sol DANS la cellule** :
  sur celle du cactoon, les rangées 52 à 66 sont une ellipse noire. Toute
  teinte appliquée au sprite entier l'atteint donc aussi — une surbrillance
  blanche y allume un halo sous les pieds. `Shaders/white_tint.gdshader` a pour
  ça un seuil `dark_cutoff` : sous cette luminance, le pixel garde sa couleur.
  L'alpha ne sert à rien ici, l'ombre étant quasi opaque en son centre ; c'est
  la luminance qui sépare (l'ombre et les contours sont sous 0,05, le premier
  pixel de corps est au-dessus).
- **Les planches d'ennemis sont en NIVEAUX DE GRIS** (le cactoon n'a que des
  pixels r = v = b, du noir au blanc). Un effet qui repose sur la clarté —
  surbrillance blanche, flash de dégâts — y est donc bien moins lisible que sur
  un allié coloré : il faut mesurer le contraste obtenu contre les unités NON
  affectées, pas juger l'effet sur la seule cible.
- **Une UI « fantôme » dans l'écran de combat est presque toujours un double
  lancement, pas un bug de rendu.** Le fond du combat est une capture du
  viewport : si un combat est déjà ouvert au moment où un second se lance, la
  première interface se retrouve peinte dans le fond du second, assombrie par
  `background_dim` — d'où des textes figés qui résistent à `queue_redraw()` et
  réapparaissent dès qu'un libellé raccourcit. Vérifier le nombre d'enfants de
  `get_tree().root` avant de chercher plus loin.
- **Les maquettes de combat peuvent contenir PLUSIEURS vignettes empilées**
  (`mockup_preparation_select_attack.png` en aligne trois de 480×270 sur un
  fond gris semi-transparent). Les découper d'abord — chercher les lignes dont
  l'alpha vaut 255 — plutôt que de mesurer sur l'export entier.
- **Recaler un élément d'écran contre une maquette : corréler, pas comparer des
  boîtes englobantes.** Un seuil sur les pixels clairs donne une largeur qui
  varie avec l'anticrénelage (« Cactoon » mesure 43 px sur la maquette et 47 au
  rendu au même corps). Faire glisser une fenêtre du rendu sur la maquette et
  garder le décalage de moindre écart donne la position au pixel près, même
  quand les deux fonds diffèrent. Pour le CORPS d'un texte, ce sont les
  positions de départ des glyphes qui tranchent, pas la largeur d'encre.
- **La pastille de menu a une largeur fixe (78 px)** : le libellé et la
  colonne de coût en PA doivent y tenir ensemble. `CommandMenu` avertit au
  montage quand un texte déborde, en donnant l'écart en pixels — c'est un
  problème de DONNÉE (le catalogue de textes), pas de mise en page, et la
  traduction la plus longue est celle qui compte.
- **Une maquette JPEG se recale sur le TEXTE, jamais sur un bord de cadre.**
  Les pastilles de l'écran de combat sont inclinées : leur bord supérieur
  remonte de 6 px sur 123 à −3°, et la compression étale encore le contour.
  L'encre d'un libellé, elle, se mesure sans ambiguïté, et l'écart
  texte/pastille est connu par un élément déjà calibré sur un PNG.
- **Ne pas supposer qu'un sous-menu réutilise la disposition de son parent.**
  La liste d'Ekos partage l'asset et l'inclinaison du menu racine, et rien
  d'autre : elle est à l'autre coin de l'écran, ses pastilles font 123 px au
  lieu de 78, et ses rangées descendent EN CASCADE (+10 px vers la droite à
  chaque rangée). Demander la maquette avant d'écrire la mise en page coûte
  moins cher que la refaire.
- **Un SVG exporté de Figma peut embarquer le fond de son cadre** — un `<rect>`
  plein couvrant tout le viewBox, sous le dessin (une première version des
  icônes de type en avait un rouge vif). Le repérer avant d'importer : sur une
  icône ronde, le disque couvre le centre et seuls les coins trahissent le
  problème.
- **Un décalage depuis le coin d'un élément incliné doit être appliqué DANS SON
  REPÈRE**, sinon l'erreur croît avec la distance : sur une pastille de combat
  penchée de 3°, un décalage à plat de 100 px tombe 6 px sous la surface réelle
  et l'élément sort du cadre. Invisible près du coin (l'icône de type, à 4 px,
  ne bougeait pas), flagrant à l'autre bout (la colonne de coût).
- **Calibrer sur la maquette SANS PERTE quand il y en a une.** Les planches
  d'UI livrées en PNG sont à l'échelle de design ; les maquettes de scène sont
  en JPEG, et leur compression déplace d'un pixel le bord des petits aplats —
  assez pour fausser le calage d'une icône de 12 px, et pour faire croire à un
  accord quand il n'y en a pas.
- **Distinguer une liste inclinée EN BLOC d'une liste dont chaque rangée est
  inclinée** : mesurer l'écart d'une rangée à la suivante. S'il vaut le
  décalage à plat, chaque rangée tourne sur elle-même ; s'il est tourné lui
  aussi, c'est le groupe entier. Les deux donnent des pastilles également
  penchées — seule cette mesure les sépare, et se tromper fait dériver d'un
  pixel par rangée tout ce qui est posé à côté du texte.
- **Un groupe d'interface pivote autour de SON coin, pas autour du pivot d'un
  autre groupe.** Réutiliser un pivot situé à l'autre bout de l'écran
  transforme une inclinaison de 3° en translation de plusieurs pixels.
- **Une maquette de combat peut contenir une vignette qui répond à une question
  posée bien plus tard.** `mockup_preparation_select_items.png` en aligne
  quatre de 480×270 ; la quatrième montre le tour du SECOND allié — donc à la
  fois l'emplacement du menu pour cet allié, la planche de l'allié qui a déjà
  joué, et la présence de « Cancel ». Avant de mesurer sur une capture d'écran
  ou de déduire une position d'un calcul, chercher la vignette qui montre déjà
  l'état voulu : elle est sans perte et se recale au pixel.
- **Recaler un sprite de personnage sur une maquette dit AUSSI de quelle
  planche il vient.** Ajuster une teinte multiplicative par moindres carrés sur
  les pixels opaques donne un résidu qui sépare nettement les candidats (8,7
  sur 255 avec la bonne planche contre 45 avec la voisine). C'est ce test qui a
  corrigé une lecture fautive — l'allié qui a joué était sur `standby`, pas sur
  un `idle` assombri.
- **Les planches d'un même personnage ne cadrent pas leur cellule pareil** :
  entre `idle` et `standby`, l'ombre au sol de Noah se déplace de 11,5 px dans
  sa cellule. Ancrer une planche au centre-bas de sa cellule fait donc sauter
  le personnage en changeant d'état. Ancrer sur l'ELLIPSE D'OMBRE (champ
  `anchor` de `units.json`) : c'est le seul repère commun à toutes les
  planches, et la seule chose qui touche vraiment le sol.
- **Redéfinir une méthode d'un nœud Godot avec une autre signature est refusé
  au chargement.** `AnimatedSprite2D` a déjà un `set_animation(StringName)`
  (l'accesseur de sa propriété `animation`) : un `set_animation(Dictionary)`
  dans un script qui l'étend ne charge pas. Vérifier qu'un nom de méthode
  « naturel » n'est pas déjà une propriété du nœud parent.
- **Un motif animé sur une petite surface se dessine à la résolution de
  l'ÉCRAN, pas de design** (même raisonnement que le suréchantillonnage du
  texte) : la zone de blessure de la jauge de PV ne fait que 3 px de design de
  haut, où une diagonale n'a pas la place d'exister — elle en fait 12 à
  l'écran. Et un motif qui défile n'a pas besoin d'un shader : une tuile d'UNE
  période, `texture_repeat = TEXTURE_REPEAT_ENABLED`, et le défilement se
  réduit à déplacer `region_rect` (qui sort alors de la texture et boucle).
- **Ramener un point de l'écran dans le repère d'un groupe incliné : lire les
  transformations de l'arbre, pas reconstruire la formule.** Tant que le groupe
  ne bouge pas, un pivot + un angle passés à la main suffisent ; dès qu'il se
  déplace (le menu de combat suit l'allié actif), la formule doit suivre chacun
  de ces déplacements. `(frame.global_transform.affine_inverse() *
  global_transform).affine_inverse() * point` couvre tous les cas, y compris
  celui d'une liste posée à même le terrain (où il se réduit à l'identité).
- **Une planche d'attaque ripée peut faire SORTIR le personnage de l'écran.**
  Celle d'Iris la fait reculer de 108 px de design sous le recul du tir avant de
  la ramener à 4 px de son point de départ : à son emplacement (x = 365), le
  sommet du recul la met à 473 sur un écran large de 480. C'est l'animation
  telle qu'elle est dessinée, pas un défaut d'ancrage — mais l'amplitude est à
  vérifier contre la place réellement disponible avant d'adopter une planche.
- **Ancrer une planche de déplacement sur sa PREMIÈRE frame.** L'ombre y bouge
  d'une frame à l'autre (c'est le mouvement encodé dans la cellule) : la caler
  sur une frame quelconque déplacerait le personnage au lancement de
  l'animation. Sur frame 0, il part de son emplacement et le geste l'emmène.
- **Un `const … = preload(…)` chez l'appelant permet `Truc.new()` ; une
  fonction STATIQUE dans un script sans `class_name` ne peut pas s'instancier
  elle-même** (`new()` seul n'existe pas). Un « constructeur statique de
  confort » (`Machin.pop(parent, …)`) est donc à écrire chez l'appelant, pas
  dans le script instancié.
- **`AnimatedSprite2D.animation_finished` ne suffit pas à séquencer un combat.**
  Les durées se déduisent des données de la planche (frames / fps) et les
  attentes passent par un timer en SECONDES : l'environnement de debug tourne à
  une cadence irrégulière, un comptage de frames n'y est pas reproductible.
- **Un état d'affichage mis en cache finit par mentir dès qu'un second système
  écrit dessus.** Les poses des alliés étaient suivies par un tableau de noms
  d'animation dans `BattleScene` ; la phase d'assaut change de planche sans
  passer par là, et le tableau devenait faux. Remède : publier ce que le nœud
  joue VRAIMENT (`UnitSprite.sheet_path`) et comparer à ça. Corollaire du même
  incident : une fonction de rafraîchissement doit s'abstenir sur ce qu'un autre
  système anime à cet instant (unité en train de tomber, geste en cours),
  sinon elle le réécrit à chaque passage.
- **Poser l'état AVANT d'appeler ce qui le lit.** `_close_sublist` rafraîchissait
  les combattants puis passait l'état à « menu » : le rafraîchissement voyait
  encore la liste ouverte et laissait l'allié dégainé. Dans une fonction de
  transition, l'affectation d'état vient en premier.
- **Changer la planche d'un AnimatedSprite2D ne doit pas le repositionner.**
  `UnitSprite.setup()` repose l'unité sur son emplacement, ce qui est juste au
  montage et faux partout ailleurs : pendant l'assaut l'unité quitte son
  emplacement pour aller au contact, et changer de planche en chemin la
  téléportait chez elle au milieu du déplacement. `play_sheet()` sauve donc la
  position et la restaure ; seul `offset`, qui porte l'ancrage, suit la nouvelle
  planche.
- **Caler une vignette de maquette sans repère absolu : chercher une ARÊTE
  HORIZONTALE de décor présente dans les deux images.** Les vignettes
  d'`anim_jauge_hp.png` sont des recadrages à ×2, sans origine connue, et un
  recalage par corrélation échouait (fond capturé différent, personnage qui
  clignote). La frontière claire/sombre de la plateforme, elle, est parfaitement
  horizontale et identique : y = 166 sur la référence, y = 179 en jeu, donc
  `design = référence/2 + 96`, vérifié sur dix colonnes. Un seul repère de ce
  genre suffit à convertir toutes les mesures verticales.
- **Une maquette d'animation faite à la main n'est pas numériquement
  cohérente** — ses vignettes ne décrivent pas forcément un même état qui
  évolue. Y lire la GRAMMAIRE (quelles zones existent, laquelle bouge, dans quel
  sens) et pas des valeurs : sur `anim_jauge_hp`, le vert de la première
  vignette ne correspond à aucune des trois suivantes, mais la forme — un
  capuchon rouge de plus en plus court au bout d'un vert de plus en plus court —
  est sans ambiguïté.
- **Deux champs qui encodent la même chose finissent par se contredire.** Les
  catalogues de combat portaient un `type` (1 ou 2) choisissant l'icône de
  rangée, ET un `damage_type` (direct/injury). Les fichiers d'icônes ont montré
  que c'était la même information : `ic_type_action_1/2.svg` ne diffèrent que
  par le `fill` de l'éclair, et le bleu de la première est #007BFF — exactement
  la couleur des rayures de blessure de la jauge. Les deux champs s'étaient déjà
  désynchronisés. Remède : supprimer le champ redondant et DÉDUIRE l'affichage.
  Méthode générale : quand deux champs semblent parler du même sujet, ouvrir les
  assets et comparer les valeurs — une couleur partagée au chiffre près n'est
  jamais une coïncidence.
- **ThorVG ignore les `<filter>` SVG — mesurer avant de choisir SVG ou PNG.**
  Même famille que la balise `<image>` non rastérisée : le rendu est
  silencieusement incomplet, pas en erreur. Les barres de rythme portent toute
  leur lueur dans des `feGaussianBlur`/`feColorMatrix` et sortaient à un dixième
  de leur intensité (0,021 contre 0,174 en luminance moyenne pondérée par
  l'alpha). Test systématique avant d'adopter un SVG : `grep -c '<filter'`, puis
  comparer l'intensité moyenne du rendu importé à celle du PNG d'origine. Un
  asset qui perd plus d'un quart revient au PNG — en bilinéaire s'il est
  anticrénelé.
  **`bkg_description.svg` est dans ce cas et n'est PAS encore corrigé** : tout
  son bord flou tient dans un `feGaussianBlur stdDeviation="2.5"`, et Godot en
  fait un rectangle à bord dur — l'alpha de sa ligne médiane saute de 0 à 153
  d'une colonne à l'autre là où l'asset veut une montée progressive. Le PNG
  existe dans `_assets/battle/`. Test rapide et sans ambiguïté : dumper
  `texture.get_image()` et lire le profil d'alpha en travers d'un bord — un
  bord flou monte par paliers, un bord dur saute en une colonne. (Ne PAS
  comparer à un rendu `qlmanage`, qui aplatit l'alpha sur du blanc et fausse
  toute mesure d'intensité.)
- **Pour faire un FONDU entre deux états d'un même élément, superposer deux
  nœuds plutôt que d'échanger une texture.** La barre de rythme montrait sa
  moitié allumée en remplaçant la texture du sprite éteint : aucune place pour
  une transition. Un calque allumé posé par-dessus, dont seule l'opacité bouge,
  donne le fondu sans toucher au reste.
- **« La caméra bouge » ne veut pas dire qu'il faut bouger la caméra.** Sur les
  maquettes d'assaut, le décor, les combattants et le fond se déplacent de 60 px
  — mais le HUD, lui, ne bouge pas d'un pixel sur les dix vignettes. Une
  transformation du calque (ou une Camera2D) aurait tout emporté. La bonne
  réponse était un nœud intermédiaire ne contenant QUE ce qui doit glisser.
  Vérifier ce qui reste immobile est aussi instructif que mesurer ce qui bouge.
- **Déplacer un fond cadré pile sur l'écran découvre son bord.** Le fond de
  combat est une capture 1920×1080 posée au pixel : le faire glisser laissait du
  noir d'un côté. Remède : l'agrandir du décalage maximal (ici 12 %) et le
  recentrer — invisible sur une photo floutée sous un voile, et sans quoi il
  faudrait renoncer au mouvement.
- **`tween_method` fige ses bornes à la CONSTRUCTION du tween, pas à son
  exécution.** Une file de plusieurs montées ne peut donc pas lire l'état courant
  pour son point de départ : il faut le suivre dans une variable locale au moment
  où on bâtit la file. Symptôme rencontré : après un passage de niveau, la jauge
  de synergie redescendait au lieu de repartir de zéro.
- **Un aperçu qui précède une animation se pose AVANT l'attente**, jamais dans le
  premier pas de la file : sinon il apparaît en même temps que ce qu'il devait
  annoncer, et ne se voit jamais seul.
- **Une entrée qui « ne fait rien » est un bug, même quand c'est délibéré.**
  La barre de rythme ignorait les touches pressées avant que la note n'entre
  dans sa fenêtre, au nom d'une règle défendable — ne pas consommer une note qui
  n'est pas encore là. Résultat : une manette morte pendant la moitié de la
  séquence, sans aucun retour. Une action du joueur doit toujours produire un
  effet visible, quitte à ce que ce soit un échec.
- **Avant d'inventer une position, chercher si l'écran en contient déjà une
  équivalente — et la MESURER en jeu.** Le curseur du rythme devait se poser
  au-dessus de l'unité qui joue ; deux tentatives dérivées de la planche sont
  tombées à côté (le sommet de cellule rate dès qu'une arme levée ou un familier
  volant élargit le cadre ; aucun seuil de largeur ne trouve une tête, qui est
  plus étroite qu'un corps — 51, 62 et 49 px au lieu de 69, 66 et 67). La bonne
  réponse était le curseur de CIBLAGE, déjà calibré : relevé en jeu à
  `pieds + (9,703 79 ; −92,311 4)` et 33°, constant à la sixième décimale sur
  les trois emplacements. Lire une position existante par introspection coûte
  moins cher que d'en dériver une, et garantit que les deux écrans concordent.
- **Un asset dont les premières rangées sont cachées se cale sur la première
  rangée VISIBLE, pas sur son bord.** La pointe de la pastille d'action a trois
  rangées d'aplat (9 px, puis 4, puis 2) dont la première disparaît sous le
  corps de la pastille : la caler sur sa rangée 0 la décrochait de deux pixels.
  Mesurer l'asset rangée par rangée avant de le positionner, puis identifier
  quelle rangée correspond à ce qu'on voit sur la maquette.
- **`flip_h` ne DÉPLACE PAS un Sprite2D.** Avec `centered = false`, son rectangle
  part toujours de `position` ; le retournement ne fait que miroiter la texture
  dedans. Poser une moitié droite en la décalant de DEUX largeurs, comme le
  ferait un retournement autour de l'origine, l'envoie hors de l'écran — et
  silencieusement, puisque rien n'est dessiné.
- **L'enum d'un script sans `class_name` ne s'utilise pas comme ANNOTATION de
  type** dans ce même script (« Cannot assign a value of type X.gd.Side as
  Side »). Déclarer l'enum pour les noms, et typer les variables et paramètres
  en `int` — c'est déjà la convention de `BattleAssault.Outcome`.
- **Pour capturer un instant précis en jeu, s'accrocher au SIGNAL, pas à une
  horloge.** Viser « 2,70 s après le lancement » rate l'instant une fois sur
  deux — la cadence du debug est irrégulière. Un `signal impact` connecté à la
  capture tombe juste à tous les coups.
- **Une grille de spritesheet se MESURE, elle ne se devine pas par division.**
  Les bords de cellule tombent dans une bande d'alpha nul : lister les colonnes
  et les lignes entièrement transparentes, puis retenir le découpage dont tous
  les bords y tombent. Corollaire rencontré sur `iris_win_before` : une cellule
  peut être 5× plus large que le personnage (339 px pour 70) parce qu'un
  familier traverse le cadre — une largeur « aberrante » n'est pas une erreur
  d'export.
- **Valider une méthode de relevé sur les valeurs DÉJÀ dans le fichier avant de
  s'en servir.** Les ancres des planches de victoire ont été déduites du
  décalage ombre → ancre d'`idle` ; la méthode a d'abord été rejouée sur les
  quatre ancres existantes, qu'elle redonne au pixel (seule exception :
  `noah/standby`, que son commentaire annonce comme délibérément remonté d'un
  pixel). Sans ce contrôle, une méthode fausse pose une valeur plausible.
- **Ancrer une planche sur la frame qui ENCHAÎNE, pas systématiquement sur la
  première.** `iris_win_before` se termine sur la pose que `win` tient en
  boucle : c'est là que l'ancrage doit coïncider, sinon le personnage saute à la
  transition — que le joueur regarde. Et sur ses premières frames, l'ombre du
  personnage FUSIONNE avec celle de son familier : le centre de la boîte est
  alors décalé de 17 px, et le relevé silencieusement faux.
- **Deux planches enchaînées se vérifient par leur OMBRE, pas à l'œil** : celle
  de la dernière frame de `win_before` et celle de la frame 0 de `win` doivent
  avoir la même taille et le même nombre de pixels. Sur Iris : 36×12 et 298
  pixels des deux côtés — la transition ne peut pas sauter.
- **Une phase qui pose ses propres planches doit faire taire les
  rafraîchissements**, et l'état qui le dit se pose AVANT de l'appeler.
  `_refresh_ally_poses` et `_refresh_unit_visuals` s'abstiennent sur `ASSAULT`
  et sur `FINISHED` : sans ça la célébration de victoire est écrasée par la
  planche de repos, et le fondu de retour d'un allié ranimé par un `modulate`
  remis à blanc d'un coup.
- **Un commentaire qui n'est vrai que pour UN de ses appelants est un bug qui
  attend.** « La garde n'a rien à exécuter : son effet est déjà en place » était
  juste pour un allié (posé pendant la préparation) et faux pour un ennemi
  (dont l'action n'existait pas encore) — et le `return` qui suivait rendait
  tout le comportement `defensive` inerte. Quand deux camps passent par le même
  code, relire chaque justification en se demandant *pour lequel* elle tient.
- **Corriger à la profondeur de la cause, pas du symptôme.** Le vrai défaut
  n'était pas « il manque une ligne dans `_raise_guards` » mais « rien n'est
  jamais RETENU pour un ennemi » : son action se décidait à la volée. La poser
  sur l'unité à l'ouverture de l'assaut, comme celle d'un allié, corrige d'un
  coup la garde ET les PA jamais débités — et supprime un cas particulier dans
  `_action_of` au lieu d'en ajouter un.
- **Un vocabulaire fermé porté par de la donnée mérite des constantes**, même
  côté moteur : les valeurs de `source` d'une action (`attack`/`eko`/`item`/
  `guard`) traînaient en chaînes nues dans trois fichiers. Une faute de frappe
  n'y lève aucune erreur, elle tombe dans la branche par défaut d'un `match`.
- **Ce qui est posé à partir d'une transformation animée doit être reposé à
  chaque image.** La pastille d'action se calcule depuis la transformation du
  terrain ; lue une seule fois au changement de cible, elle lisait une valeur
  que le tween allait changer pendant 0,3 s — elle restait accrochée au point de
  départ et n'y revenait jamais. Symptôme trompeur : elle atterrissait sur le
  HUD pour certaines cibles seulement (celles dont le mouvement était le plus
  grand), ce qui fait chercher un problème de position, pas de temps.
- **Dès qu'un nœud intermédiaire se transforme, tout ce qui lit des coordonnées
  « dedans » doit passer par sa transformation.** Tant que `_field` restait à
  l'identité pendant la préparation, espace terrain et espace Stage se
  confondaient et le code mélangeait les deux sans conséquence. Le premier zoom
  a révélé la confusion. Corollaire : un décalage qui se mesure À L'ÉCRAN
  (position d'une pastille à côté d'une cible) s'applique APRÈS la
  transformation, sinon il grossit avec le zoom.
- **Un fond cadré pile sur l'écran ne peut suivre qu'un mouvement borné.** Le
  débord du fond de combat est dimensionné pour les 60 px de l'assaut ; à 111 px
  de translation son bord entre dans l'image. L'élargir dégraderait le rendu au
  REPOS pour un mouvement passager — le laisser immobile est à la fois plus sûr
  et plus juste (un plan lointain bouge moins, c'est du parallaxe).
- **Le point « pieds » d'une unité n'est PAS le milieu de son dessin.** Les
  ancres de `units.json` alignent les planches d'un même personnage entre elles
  (sur l'ombre), pas sur le centre du corps : mesuré, le dessin de Noah est
  centré à +0,5 px de ses pieds sur `idle` mais à +11,5 px sur `standby` (l'épée
  tenue de côté élargit la silhouette vers la droite). Tout ce qui doit être
  CENTRÉ SUR LE PERSONNAGE — le nom et la jauge de la cible — se pose donc sur
  `UnitSprite.art_centre()` en abscisse, et sur les pieds en ordonnée seulement.
  Symptôme qui l'a révélé : la plaque paraissait juste sur Iris (dessin centré à
  0,0 sur `idle`) et franchement décalée sur Noah, selon la seule planche que
  chacun tenait à cet instant.
- **`flip_h` miroite la texture DANS la cellule** : un rect utile mesuré sur la
  planche décrit donc le dessin du mauvais côté pour une unité retournée (tous
  les ennemis le sont). Invisible tant que les planches sont symétriques dans
  leur cellule — le cactoon l'est à un demi-pixel près — et faux du double de
  l'excentrement dès qu'une ne l'est pas.
- **L'ordre d'une liste de cibles n'est pas forcément l'ordre de l'écran.** Les
  emplacements ennemis sont numérotés de droite à gauche (le ciblage s'ouvre sur
  le plus proche de l'équipe) ; ←/→ doivent, eux, suivre l'abscisse, sinon la
  flèche droite déplace le curseur vers la gauche. `TargetSelector` garde donc un
  ordre visuel à part, trié sur l'abscisse des PIEDS — pas sur celle du dessin,
  que deux planches de largeurs très différentes pourraient inverser.
- **Reconstruire une liste de nœuds : `remove_child()` AVANT `queue_free()`.**
  La libération est différée à la fin de la frame, donc les anciens nœuds
  restent enfants — et donc affichés par-dessus les nouveaux — le temps d'une
  image. Visible seulement en rouvrant une liste, ce qui en fait un bug facile
  à ne pas voir en test manuel.

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
