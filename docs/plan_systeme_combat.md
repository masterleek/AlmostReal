# Système de combat — plan d'implémentation

Combat au tour par tour inspiré de Golden Sun, greffé d'une mécanique de jeu
de rythme. Ce document est le plan de référence : il fixe les fondations
techniques (résolution, arborescence, modèle de données) **avant** d'écrire du
code, pour que le premier écran livré (la phase de préparation) ne condamne pas
les lots suivants.

**Périmètre du Lot 1 (ce qui sera réellement codé en premier)** : reconstitution
visuelle, au pixel près, de `mockup_preparation`. Pas de logique de combat, pas
de phase d'assaut, pas de rythme. Le reste du document existe pour cadrer ce
Lot 1, pas pour être implémenté maintenant.

---

## 1. Fondations techniques

### 1.1 Résolution de design : 480 × 270, affichée ×4

Les assets fournis ne sont pas à l'échelle du viewport (1920×1080) : ils sont
authored à **480×270**, soit exactement 1920/4. Trois mesures indépendantes le
confirment :

| Asset | Taille | Déduction |
|---|---|---|
| `dark_lines.png` | 480 × 100 | = largeur d'écran exacte |
| `rhythm_line_empty.png` | 239 × 43 | 239 × 2 = 478 ≈ largeur d'écran (deux moitiés) |
| `313000404_standby` (Noah) | sprite 49 × 62 | 62 / 270 = 23 % de hauteur d'écran, ce qu'on lit sur le mockup |

**Décision** : ne pas toucher au `stretch/mode` du projet (`canvas_items`,
1920×1080) — ça casserait le worldmap, dont l'art est authored à une autre
échelle. À la place, toute la scène de combat vit sous un nœud `Stage`
(`Node2D`) avec `scale = Vector2(4, 4)`, et **toutes les coordonnées enfants
sont exprimées en unités de design 480×270**.

Conséquences à assumer explicitement :

- `textures/canvas_textures/default_texture_filter=0` (nearest) est déjà réglé
  au niveau projet : l'upscale ×4 sort net, sans réglage supplémentaire.
- Les positions doivent rester **entières** en espace design, sinon l'upscale
  ×4 produit des demi-pixels et casse le rendu pixel-art.
- **Le texte est rendu à l'intérieur du `Stage`**, donc à une `font_size`
  exprimée en unités de design (~8 px), rasterisée petit puis agrandie ×4 →
  aspect « pixel » identique au mockup. C'est un choix délibéré et *différent*
  de la convention du HUD worldmap, qui rend sa police à sa taille native
  (`normal_font_size = 64` sur `ActionLabel`) pour un rendu lisse. Les deux
  conventions coexistent : le mockup de combat est explicitement pixelisé.
- La `font_size` exacte (candidats : 6, 7, 8) est à **calibrer** — cf. §7.

### 1.2 Arborescence de la scène

```
Battle.tscn
└── BattleScene (CanvasLayer, layer = 10)          BattleScene.gd
    ├── Background        (Sprite2D)   ← 1920×1080, capture du worldmap, échelle 1
    ├── BackgroundDim     (ColorRect)  ← noir + alpha, plein écran
    └── Stage             (Node2D, scale = 4)   ← tout ce qui suit en unités 480×270
        ├── DarkLineTop / DarkLineBottom  (Sprite2D)
        ├── Platform      (Node2D)      ← 2 moitiés de platform_grass
        ├── Units         (Node2D)      ← ennemis + alliés, tri Y
        ├── CommandMenu   (Node2D)      CommandMenu.gd
        ├── PartyStatus   (Node2D)      ← blocs portrait/HP/AP + synergie
        ├── InputLegend   (Node2D)      ← « Cancel / Confirm »
        └── RhythmBar     (Node2D)      ← lot ultérieur, absent en préparation
```

`Background` et `BackgroundDim` sont **hors** du `Stage` : la capture est une
texture 1920×1080 native, la remettre en espace design pour la re-scaler ×4
n'apporterait rien et dégraderait l'image.

### 1.3 Fond = capture du worldmap

`Sprite2D` alimenté par une `ImageTexture` construite au lancement du combat.
Points d'implémentation qui ne sont pas évidents :

1. La capture doit se faire **après** le rendu : `await
   RenderingServer.frame_post_draw`, puis
   `get_viewport().get_texture().get_image()`. Sans ça, la texture lue est
   celle de la frame précédente (piège déjà rencontré sur ce projet, cf.
   `CLAUDE.md` §workflow, point 5).
2. **Masquer le HUD worldmap avant la capture** (`HexCounter`, `ActionHint`,
   `TileCostBubble`) : sinon le compteur de hex et l'indice d'action se
   retrouvent gravés dans le fond du combat.
3. Le worldmap n'est **pas déchargé** : il reste dans l'arbre, `visible = false`
   et `process_mode = DISABLED`. La sortie de combat n'a alors rien à
   restaurer. C'est ce qui motive le choix « scène de combat instanciée en
   enfant » plutôt que `change_scene_to_file()`.

`BattleScene.setup(context)` reçoit ce fond. **Si `setup()` n'est pas appelé**
(lancement direct de `Battle.tscn` en F6, ce qui sera le mode d'itération du
Lot 1), la scène retombe sur un fond de secours uni. La scène est donc
jouable seule *et* embarquable — pas de scaffolding de debug à retirer ensuite.

---

## 2. Inventaire et préparation des assets

Tous les fichiers viennent de `../_assets/battle/` et doivent être copiés dans
le projet avant usage (`CLAUDE.md` §Assets) :
`Sprites/Battle/` pour les personnages et le décor, `UI/Battle/` pour le HUD.

### 2.1 Décor

| Asset | Taille | Usage |
|---|---|---|
| `dark_lines.png` | 480×100 | Bande basse telle quelle ; bande haute = **même texture retournée verticalement** (`flip_v`) |
| `platform_grass.png` | 200×66 | **Moitié gauche** de la plateforme ; moitié droite = même texture en `flip_h` → 400×66 assemblés |

Profils mesurés (utiles pour le placement) :

- `dark_lines.png` : le noir commence à `y=0` sur les bords et à `y=16` au
  centre → la bande est **plus épaisse aux coins**, comme sur le mockup.
- `platform_grass.png` : bord supérieur en biseau (`y=64` à `x=0`, `y=0` à
  partir de `x=75`), bord inférieur plat à `y=65`. Le miroir horizontal donne
  bien la lentille symétrique du mockup.

### 2.2 Personnages alliés — planches en grille 3 colonnes

Les planches `_iris/` et `_noah/` suivent toutes la même structure : **grille
uniforme de 3 colonnes**, lecture ligne par ligne, dernière ligne
éventuellement incomplète. Vérifié par détection des lignes entièrement
transparentes :

| Planche | Taille | Grille | Cellule | Frames |
|---|---|---|---|---|
| `_noah/313000404_idle` | 204×148 | 3×2 | 68×74 | 4 |
| `_noah/313000404_standby` | 177×144 | 3×2 | 59×72 | 4 |
| `_noah/313000404_atk` | 354×576 | 3×6 | 118×96 | 17 |
| `_noah/313000404_atkeff` | 225×658 | 3×7 | 75×94 | 20 |
| `_noah/313000404_win` | 156×140 | 3×2 | 52×70 | 4 |
| `_iris/100022805_idle` | 276×160 | 3×2 | 92×80 | 4 |
| `_iris/100022805_standby` | 246×186 | 3×2 | 82×93 | 4 |
| `_iris/100022805_magic_standby` | 192×186 | 3×2 | 64×93 | 4 |
| `_iris/100022805_atk` | 672×972 | 3×9 | 224×108 | 26 |
| `_iris/100022805_win` | 138×136 | 3×2 | 46×68 | 6 |

Deux propriétés importantes de ces planches :

- **Le mouvement est encodé dans la cellule** : sur `_iris/…_atk`, le
  personnage se déplace franchement d'une cellule à l'autre. Il ne faut donc
  **pas** recadrer les frames sur leur silhouette — on garde la cellule
  entière et un ancrage unique (centre-bas de cellule), sinon l'animation
  perd son déplacement.
- **L'ombre est déjà peinte dans chaque frame.** Aucun nœud d'ombre à ajouter
  (contrairement au worldmap, cf. `HeroShadow.gd`).

`_iris/100022805_win_before.png` (1017×1236) ne se divise pas en 3×7 : sa
grille réelle est à redéterminer le jour où cette animation servira. Hors
périmètre.

> Note : `_iris` = personnage bleu au fusil (accompagné d'un familier flottant),
> `_noah` = personnage rouge à l'épée. À reconfirmer contre le mockup
> `select_items`, où l'étiquette « Noah » désigne bien le personnage à l'épée.

### 2.3 Ennemi — `_cactoon/cactoon.png` est une planche de rip

C'est une **page de ripping** (586×767) sur fond turquoise opaque `(0,128,128)`,
avec des libellés (« Idle 1 »…« Unit Illustrations ») et des cadres noirs de
1 px autour de chaque frame. Elle n'est **pas** utilisable telle quelle.

Bonne nouvelle vérifiée : le PNG a un **vrai canal alpha**, et l'intérieur des
cadres est déjà transparent autour du sprite. L'extraction est donc un simple
recadrage — pas de dékeyage, pas de reconstruction d'alpha, pas de retouche.
(Le RGB stocké sous les pixels transparents est blanc, ce qui donne l'illusion
de « cadres blancs » quand on aplatit la page — c'est un faux problème.)

`Idle 1` / `Idle 2` / `Idle 3` sont **la même animation à trois échelles**.
Celle qui correspond au mockup est **Idle 2** :

| Rangée | Cadre | Cellule utile | Sprite réel | Comparaison |
|---|---|---|---|---|
| Idle 1 | 42×53 | 40×51 | ~34×45 | trop petit |
| **Idle 2** | **57×73** | **55×71** | **47×63** | ≈ Noah (49×62) ✔ |
| Idle 3 | 84×103 | 82×101 | ~76×95 | trop grand |

**Coordonnées d'extraction (Idle 2, 5 frames)** : rangée `y = 119`, cadres de
57×73 aux `x = 10, 77, 144, 211, 278` (pas de 67) ; recadrer l'intérieur, soit
`(x+1, y+1, 55, 71)`. Livrable : `Sprites/Battle/cactoon_idle.png`, planche de
5 frames de 55×71 (275×71), alpha conservé tel quel.

Choix confirmé par le recalage sur le mockup : les 3 ennemis sont bien la
frame 0 de cette rangée, **retournée horizontalement**, à l'octet près (§4).
On stocke la planche telle qu'extraite et on applique `flip_h` à l'affichage,
plutôt que de livrer une planche déjà miroir — les alliés et les ennemis
partagent ainsi le même pipeline, seul le sens de regard change.

### 2.4 Interface

| Asset | Taille | Rôle | Traitement |
|---|---|---|---|
| `command_off/on/red.png` | 27×18 | Pastille de menu (normal / sélectionné / ennemi) | **9-slice horizontal uniquement** : marges G/D ≈ 8, H/B = 0. Hauteur figée à 18 (haut+bas couvrent déjà toute la hauteur, pas d'étirement vertical possible) |
| `command_on_arrow.png`, `command_red_arrow.png` | 9×6 | Pointe/chevron de la pastille active | à confirmer visuellement |
| `bkg_description.png` | 60×60 | Fond du panneau de description (Eko / Item) | 9-slice, marges ≈ 12 |
| `battle_face_iris/noah.png` | 59×19 | Portrait (bandeau des yeux) | — |
| `battle_face_highlight.png` | 61×21 | Cadre jaune du personnage actif | dessiné **derrière** le portrait, débord de 1 px sur chaque bord |
| `hp_underlayer.png` | 59×5 | Gouttière de la jauge de vie | — |
| `hp_fill.png` | 57×3 | Remplissage (dégradé vert→jaune) | `TextureProgressBar`, `FILL_LEFT_TO_RIGHT`, inset de 1 px |
| `ic_ap_on/off.png` | 11×11 / 8×8 | Points d'action | **tailles différentes** (le « on » a un halo) : centrer les deux sur un même pas de 11 px, ne pas aligner par le coin |
| `ic_green_check.png` | 13×12 | Action de l'allié validée | affiché sur la ligne d'AP |
| `synergie_underlayer.png` | 30×31 | Piste de la jauge de synergie | — |
| `synergie_full.png` | 28×28 | Remplissage de la synergie | `TextureProgressBar`, `FILL_CLOCKWISE` |
| `ic_synergie.png` | 14×18 | Icône éclair | — |
| `round_synergie.png` | 12×12 | Pastille de niveau (0→4) | — |
| `mini_btn_cross/circle.png` | 16×16 | Légende « Confirm » / « Cancel » | — |
| `btn_cross/circle/square/triangle/directions.png` | 32×32 | **Notes du rythme** | lot ultérieur |
| `rhythm_line_empty/red/yellow.png` | 239×43 | Moitiés de la barre de rythme | gauche = ennemi (rouge), droite = allié (jaune) |
| `rhythm_circle.png` | 42×42 | Anneau cible au centre | lot ultérieur |

Deux lectures du mockup à souligner, parce qu'elles changent l'implémentation :

- **Les losanges à droite d'une entrée de menu sont des coûts en AP**
  (`ic_ap_on/off`), pas une décoration. Le menu doit donc savoir afficher un
  coût par entrée.
- **Les pastilles du menu se chevauchent verticalement.** Sur `ui_menu`
  (`menu_long_list`), les pastilles s'imbriquent nettement. Le pas vertical est
  donc **inférieur** à la hauteur de l'asset (18 px) — de l'ordre de 10–12 px —
  et chaque entrée est dessinée au-dessus de la précédente. C'est ce qui permet
  aux 4 commandes de tenir dans ~48 px de haut alors que 4 × 18 = 72.

---

## 3. Architecture logicielle

### 3.1 Découpage des fichiers

Conforme à `CLAUDE.md` §Qualité de code (fichiers et méthodes découpés,
réutilisables) et §Conventions (`preload()` plutôt que `class_name`,
commentaires en français orientés « pourquoi »).

```
Scripts/Battle/
  BattleScene.gd          Montage de la scène, point d'entrée setup()
  BattleState.gd          Machine à états préparation ↔ assaut
  BattleUnit.gd           Unité runtime : hp, ap, garde, action planifiée
  BattleData.gd           Chargement des JSON (unités, ekos, items)
  TurnOrder.gd            Tri par agilité, gestion des morts en cours de phase
  Stage/
    BattleStage.gd        Bandes noires, plateforme, ancrage des slots
    UnitSprite.gd         AnimatedSprite2D construit depuis une grille N colonnes
  UI/
    CommandMenu.gd        Liste de pastilles navigable (générique)
    UnitStatusPanel.gd    Portrait + HP + AP d'une unité
    HpBar.gd              Jauge 2 textures
    ApDots.gd             Points d'action
    SynergyGauge.gd       Jauge radiale + niveau
    RhythmBar.gd          (lot ultérieur)
```

**`UnitSprite.gd` est la brique clé** : il construit les frames à l'exécution
par `AtlasTexture` depuis `(texture, colonnes, lignes, nb_frames, fps)` lus
dans le JSON, plutôt que de maintenir à la main d'énormes ressources
`SpriteFrames` en `.tres`. Même logique que `map_loader.gd`, qui lit ses
animations depuis `tile_meta.json` plutôt que d'utiliser le système natif de
`TileSet` — cohérent avec le projet, et ça rend l'ajout d'un personnage
purement déclaratif.

**`CommandMenu.gd` doit rester générique** : il sert au menu racine
(Attack/Eko/Guard/Items), à la liste des Ekos et à la liste des objets — qui
diffèrent seulement par le nombre d'entrées, la présence d'un coût en AP, d'une
description, et d'un défilement (cf. `menu_long_list`). Une seule
implémentation paramétrée, pas trois.

### 3.2 Données

Suivre le modèle déjà en place dans le projet (`tile_meta.json`,
`props_meta.json`, `Localization/texts.json`) : **du JSON lu au runtime,
éditable plus tard depuis MapEditor**, plutôt que des ressources `.tres`.

```
Battle/
  units.json    Noah, Iris, Cactoon : stats, planches d'animation, portrait
  ekos.json     compétences : type, coût AP, séquence de touches, ciblage
  items.json    objets : idem
```

Les **stats** sont Force, Défense, Agilité, Chance (+ HP max, AP max). Aucun
nom ni description n'est stocké dans ces fichiers : ce sont des **identifiants
`Localization`** (`unit.noah.name`, `eko.fulgura.name`, `eko.fulgura.desc`…),
résolus par l'autoload existant. Le système de localisation livré au chantier
précédent devient ainsi la source unique de tout texte affiché.

### 3.3 Textes à ajouter au catalogue

`battle.menu.attack` / `.eko` / `.items` / `.guard`,
`battle.prompt.confirm` / `.cancel` / `.back`,
`battle.timing.perfect` / `.great` / `.good` / `.miss`,
plus les noms/descriptions d'unités, d'Ekos et d'objets.

⚠️ La page « Textes » de MapEditor **désactive aujourd'hui le bouton
« + Ajouter un texte » pour la catégorie `ui`** (un texte UI a besoin d'un
câblage code, il ne peut pas naître de l'outil seul). Ces entrées seront donc
écrites directement dans `texts.json` au moment du câblage ; l'outil sert
ensuite à les **traduire et les mettre en forme**, ce qui est son rôle. Les
blocs `usage`/`preview_image` (aperçu positionnel) de ces textes sont un lot
ultérieur, pas le Lot 1.

### 3.4 Entrées

Nouvelles actions nécessaires : `battle_confirm` (croix), `battle_cancel`
(rond), `battle_square`, `battle_triangle`, plus les directions (les
`ui_up/down/left/right` natifs suffisent pour la navigation de menu).

`CLAUDE.md` §project.godot : **ne jamais taper un bloc `[input]` à la main**.
Passer par un script temporaire (`ProjectSettings.set_setting()` +
`save()`, exécuté une fois en headless) pour que Godot sérialise lui-même. Et
si un test en direct ne voit pas les nouvelles actions, vérifier d'abord un
redémarrage de l'éditeur avant de suspecter le code.

---

## 4. Écran de préparation — intégration (Lot 1)

Coordonnées **en unités de design (480×270), origine en haut à gauche**,
**relevées sur `_assets/battle/mockup_preparation.png`** (480×270 natif) par
recalage automatique de chaque asset sur le mockup. Sauf mention contraire,
la position est celle du **coin haut-gauche de la cellule/texture**, et
l'erreur de recalage est **nulle** (correspondance pixel pour pixel).

| Élément | Asset | Position | Recalage |
|---|---|---|---|
| `DarkLineTop` | `dark_lines.png` **en `flip_v`** | (0, **−64**) → visible 0..35 aux bords, 0..20 au centre | exact |
| `DarkLineBottom` | `dark_lines.png` | (0, **224**) → dépasse sous l'écran, sans conséquence | exact |
| `Platform` gauche | `platform_grass.png` | (**41, 130**) | exact |
| `Platform` droite | `platform_grass.png` **en `flip_h`** | (**239, 130**) | exact |
| Cactoon 1 | `cactoon` Idle 2 **f0, en `flip_h`** (cellule 55×71) | (**76, 107**) | exact |
| Cactoon 2 | idem | (**122, 79**) | exact |
| Cactoon 3 | idem | (**168, 98**) | exact |
| Noah | `_noah/313000404_**idle**.png` **f0** (cellule 68×74) | (**273, 96**) | exact |
| Iris | `_iris/100022805_**idle**.png` **f0** (cellule 92×80) | (**319, 79**) | exact (hors familier, cf. §7) |

Constats issus du recalage, qui corrigent des hypothèses du premier jet :

- **Les deux moitiés de plateforme se recouvrent de 2 px** (41→240 et
  239→438) : le chevauchement est volontaire, il évite une couture visible.
  Emprise totale 41..438, soit 398 px et non 400.
- **Les ennemis sont en miroir horizontal.** Aucune frame de `cactoon.png`
  ne correspondait tant qu'on ne testait pas le `flip_h` — c'est ce qui les
  fait regarder vers l'équipe. Les 3 utilisent **la même frame (f0)** ; le
  décalage d'animation entre eux reste à décider (probablement un offset de
  phase, sinon les 3 bougent à l'unisson).
- **Le mockup utilise les planches `idle`, pas `standby`.** `standby` est une
  pose arme levée, visiblement réservée à un autre moment du combat.

Menu de commandes (`CommandMenu`) — 9-slice de `command_off.png` / `command_on.png`,
**marges gauche/droite = 8, hauteur figée à 18** :

| Pastille | Coin haut-gauche | Largeur |
|---|---|---|
| Attack | (280, 163) | ~78 |
| **Eko (sélectionnée)** | (**263**, 181) | ~78 |
| Items | (280, 196) | ~78 |
| Guard | (280, 211) | ~78 |

- Le fond des pastilles est **exactement** le 9-slice de l'asset (vérifié
  ligne par ligne : erreur nulle partout sauf sur les lignes portant les
  glyphes). Le pas vertical réel est de **~15–16 px** pour une pastille de
  18 → un chevauchement de 2–3 px, bien moindre que les 10–12 px supposés au
  premier jet.
- **La pastille sélectionnée est décalée de 17 px vers la gauche**, à largeur
  identique. C'est le seul effet de sélection sur la géométrie.
- Elle porte en plus un **dégradé blanc sur sa portion droite** (jaune plein
  jusqu'à x≈320, puis blanc pur) qui **n'existe dans aucun asset fourni** —
  cf. §7.
- Les losanges de coût AP sont posés **par-dessus l'extrémité droite** de la
  pastille sélectionnée, pas à côté.

| Élément | Position / règle |
|---|---|
| `Background` | capture 1920×1080, échelle 1, hors `Stage` |
| `BackgroundDim` | plein écran, noir, alpha à calibrer |
| `PartyStatus` | en haut à droite : 2 blocs portrait/HP/AP + jauge de synergie à l'extrême droite (géométrie fine à relever pendant le Lot 1 — cf. §7, les portraits ne correspondent pas aux assets) |
| `InputLegend` | `mini_btn_circle` + « Cancel » vers (333, 230), `mini_btn_cross` + « Confirm » vers (401, 223) |

**Les slots sont des données, pas des positions codées en dur** : un tableau
d'ancres (point « pieds ») en espace design, dont l'`y` sert aussi de clé de
tri pour la profondeur. C'est ce qui permettra plus tard de gérer 1 à 3
ennemis, un 3ᵉ allié, ou une autre disposition, sans retoucher le code de
placement.

⚠️ `CLAUDE.md` §Tri Y vs `z_index` : le `z_index` prime toujours sur le tri Y.
Garder toutes les unités dans **le même bucket `z_index`** et laisser leur `y`
faire le tri, plutôt que de monter le `z_index` d'une unité pour la faire
passer devant.

**Le Lot 1 s'arrête au rendu.** Le menu est affiché dans son état par défaut
(« Attack » sélectionné) ; la navigation vient au Lot 2.

---

## 5. Lotissement

| Lot | Contenu | État |
|---|---|---|
| **1** | Écran de préparation, rendu statique au pixel près (assets préparés, `Stage` ×4, fond capturé, plateforme, unités animées, HUD, menu au repos) | **fait** |
| 2 | Navigation du menu racine (haut/bas, confirm/cancel), sons | |
| 3 | Ciblage : Attack → 1 ennemi ; surbrillance, nom + jauge de vie de la cible | |
| 4 | Ekos / Items : listes défilantes, coût AP, panneau de description, ciblage multiple | |
| 5 | Garde, fin de tour, enchaînement des alliés, boucle préparation complète | |
| 6 | Phase d'assaut : ordre par agilité, exécution des actions, dégâts, morts | |
| 7 | Barre de rythme : défilement des notes, fenêtres Perfect/Great/Good/Miss, bonus de dégâts | |
| 8 | Jauge de synergie (remplissage, 4 niveaux) | |
| 9 | Victoire / défaite, transition worldmap ↔ combat, animations `win` / `dying` / `dead` | |
| 10 | Édition des Ekos / objets / stats depuis MapEditor | |

---

## 5 bis. Résultat du Lot 1

Vérifié par recalage automatique du rendu en jeu contre le mockup, à la même
résolution :

| Élément | Écart au mockup |
|---|---|
| Plateforme (2 moitiés) | **nul** (41..438 × 130..195, identique) |
| 3 cactoons | **nul** (erreur ≤ 0,35 sur 255) |
| Noah, Iris | **nul** (erreur ≤ 0,70) |
| Bandes noires | nul en position ; le pixel de bord diffère selon le fond (alpha partiel) |
| Pastilles du menu | fond identique à l'asset (86 % de pixels exacts, le reste = les glyphes) |
| Compteur de PV | **nul** (« 62 » bleu à x 342..360, y 16..24 dans les deux) |
| Reste du HUD | à ±1–2 px — non réductible, les vignettes livrées ne sont pas celles du mockup |

Valeurs calibrées au passage, qui n'étaient pas déductibles des assets :

- **Tailles de police** (en unités de design) : 12 pour les libellés HP/AP,
  15 pour les entrées de menu et la légende, 18 pour le compteur de PV. La
  hauteur de capitale de `BoldPixels1.4.ttf` vaut exactement la moitié du
  corps, ce qui permet de déduire la taille d'une mesure sur maquette.
- **Décalage boîte → glyphe** d'un `RichTextLabel` : environ un quart du
  corps vers le bas (+2 px à 12, +3 à 15, +4 à 18). Les constantes de
  position visent la boîte, pas le premier glyphe.
- **Jauge de synergie** : la piste se pose à (442, 31) et l'icône éclair
  tombe alors pile à sa place par simple centrage.
- **Pas des pastilles** : 16 px pour une hauteur de 18 (chevauchement de 2),
  et non les 10–12 supposés au premier jet.

Trois éléments d'abord jugés « non reproductibles » l'étaient en fait, après
précision de l'auteur des maquettes :

1. Le **badge de niveau** de la jauge de synergie n'est pas un asset : c'est le
   chiffre du niveau, empilé en trois copies (contour sombre `#270400`, liseré
   intérieur `#EEF801`, corps en dégradé `#420701` → `#FF7300`). Godot ne sait
   remplir un texte ni d'un dégradé ni d'un liseré intérieur ; le procédé est
   dans `BattleText.make_styled_number()`.
2. La « gemme » au bout de la pastille sélectionnée est le **curseur du
   worldmap** (`UI/cursor_worldmap.png`) pivoté d'un quart de tour. Vérifié :
   l'erreur de recalage tombe à 38 dans cette orientation contre 86 à 96 pour
   les trois autres, et la gemme se pose ensuite exactement aux mêmes pixels
   que sur le mockup (x 337..346, y 182..189).
3. Les **vignettes de portrait** livrées sont les bonnes. L'écart de pixels
   avec le mockup vient de la composition de ce dernier, pas des assets.

Reste non reproduit : l'**ombre portée douce** sous les pastilles du menu
(effet de calque du mockup, pas un asset).

## 6. Vérification (Lot 1)

Conforme au workflow de `CLAUDE.md` :

1. Check de syntaxe headless (`--quit-after 3`).
2. Lancement de `Battle.tscn` seule, capture d'écran, **comparaison
   superposée** avec le mockup source à l'échelle 1:1 — c'est la seule façon de
   valider « au pixel près ».
3. Vérifier le rendu du texte : la police doit sortir pixelisée et nette, sans
   demi-pixels (symptôme d'une position non entière en espace design).
4. Vérifier l'animation `standby` des 5 unités (pas de frame vide, pas de
   décalage d'ancrage).
5. Retirer tout scaffolding de debug et supprimer les PNG temporaires —
   `git diff --stat Scripts/map_loader.gd` doit revenir vide.

---

## 7. Prérequis, risques et questions ouvertes

### Résolu

Le mockup a été fourni en 480×270 natif (`_assets/battle/mockup_preparation.png`),
ce qui a permis de relever toutes les positions du §4 par recalage exact. Le
prérequis bloquant du premier jet est levé, et il confirme au passage la
résolution de design.

### Écarts entre le mockup et les assets fournis (à trancher avant le Lot 1)

Trois éléments du mockup **ne se retrouvent pas dans les assets livrés**. Tout
le reste est reproductible au pixel près.

1. ~~**Les portraits ne correspondent pas.**~~ **Tranché : les fichiers livrés
   sont les bons**, l'écart vient de la composition du mockup. Le constat
   d'origine est conservé ci-dessous parce qu'il documente ce qui a été
   réellement testé — utile si l'écart resurgit ailleurs.

   `battle_face_noah.png` et
   `battle_face_iris.png` (les fichiers effectivement testés) atteignent au
   mieux 22 % et 0 % de pixels identiques, contre 100 % pour tous les sprites
   de personnage. Ce n'est ni un décalage, ni un miroir, ni un
   redimensionnement (testé de 52×14 à 69×23), ni un simple réglage de
   luminosité (l'écart n'est pas uniforme : σ ≈ 40 par canal). Visuellement,
   ce sont **les mêmes illustrations à un cadrage/zoom différent** — flagrant
   sur Iris, dont la version du mockup est nettement plus zoomée sur les yeux.
   → **Décision : on intègre les fichiers livrés tels quels.** Le HUD
   s'écartera donc du mockup sur ces deux vignettes ; tout le reste reste
   conforme au pixel près.
2. **Le familier d'Iris est absent du mockup**, alors qu'il est peint dans la
   même cellule `idle` (92×80) que le personnage.
   → **Décision : on l'affiche.** On garde donc la cellule entière, et la
   règle §2.2 (« ne jamais recadrer une cellule ») reste sans exception. C'est
   le mockup qui s'écarte du rendu attendu, pas l'inverse.
3. **Le dégradé blanc de la pastille sélectionnée n'existe pas dans les
   assets** : `command_on.png` est un jaune uni (238,255,0), alors que le
   mockup montre du jaune plein jusqu'à x≈320 puis du blanc pur. Le même
   effet apparaît sur toutes les entrées sélectionnées de `ui_menu`.
   → **Décision : c'est une brillance animée (balayage).** Le mockup en
   capture un instant. À implémenter comme une passe lumineuse qui traverse
   la pastille en boucle — donc la position du front blanc dans le mockup
   n'est **pas** une valeur à reproduire.

### Risques identifiés

- **Taille de police** : `BoldPixels1.4.ttf` est une police pixel avec une
  taille native ; rendue à une taille non multiple, elle bave. À calibrer (6,
  7 ou 8 px de design) dès le premier écran, parce que tout le layout du menu
  en dépend. Le mockup sert de référence : le fond des pastilles est déjà
  validé au pixel près, seuls les glyphes restent à faire coïncider.
- **Géométrie fine du bloc `PartyStatus`** (HP/AP/synergie) : non relevée,
  parce que le désaccord sur les portraits (point 1 ci-dessus) rend le
  recalage de tout le bloc peu fiable tant qu'il n'est pas tranché.
- **Décalage de phase entre les 3 cactoons** : ils partagent la même frame
  dans le mockup, donc rien ne dit s'ils doivent s'animer en phase ou non.

### Questions ouvertes (non spécifiées, à trancher avant les lots concernés)

1. **Tour ennemi + rythme** : le joueur appuie aussi pendant le tour d'un
   ennemi. Un bon timing réduit-il les dégâts subis ? les annule-t-il ?
   (`mockup_assault_ennemies` montre un « GOOD » et Iris perd quand même 5 HP,
   donc la mitigation n'est pas totale.) — Lot 7.
2. **Effet de la synergie** : la jauge monte jusqu'au niveau 4, mais son effet
   n'est pas décrit. — Lot 8.
3. **Fin de combat** : conditions de victoire/défaite, récompenses, retour au
   worldmap. — Lot 9.
4. **Déclenchement du combat** depuis le worldmap : rencontre aléatoire ?
   ennemi posé sur une case dans MapEditor ? — Lot 9.
5. **Composition de l'équipe** : 2 alliés fixes (Noah, Iris) ou jusqu'à 3 ?
   Le HUD du mockup n'en montre que 2.
6. **Nombre de PA max** : le mockup « Action Points » montre 6 états (5 → 0),
   donc 5 AP max — à confirmer.

---

## 8. Ce que ce plan ne fait pas

- Aucune modification du worldmap existant, hors masquage du HUD pendant la
  capture de fond.
- Aucun système de dialogue (la catégorie `dialogue` du catalogue de textes
  reste vide, comme décidé au chantier localisation).
- Aucune page MapEditor nouvelle avant le Lot 10.
