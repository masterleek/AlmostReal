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
| 2 | Navigation du menu racine (haut/bas, confirm/cancel), sons | **fait** |
| 3 | Ciblage : Attack → 1 ennemi ; surbrillance, nom + jauge de vie de la cible | **fait** |
| 4 | Ekos / Items : listes défilantes, coût AP, panneau de description, ciblage multiple | **fait** |
| 5 | Garde, fin de tour, enchaînement des alliés, boucle préparation complète | **fait** |
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

## 5 ter. Résultat du Lot 3

Le ciblage est un composant à part, `TargetSelector`, écrit pour servir aussi
au ciblage d'un allié (objet, Eko de soin) au Lot 4 : rien dedans ne suppose de
quel camp est la cible, l'appelant fournit la liste des unités visables. Il
suit le même contrat que `CommandMenu` — drapeau `active` arbitré par la scène,
signaux `selection_changed` / `confirmed` / `cancelled` — pour que les deux
listes ne se disputent jamais les entrées.

Trajet câblé : `Attack` → première cible vivante, `←`/`→` pour changer de
cible, `Confirm` ou `Back` pour revenir au menu. Valider une cible ne met
encore rien en file : la file d'actions arrive au Lot 5.

### Ce que montre `mockup_preparation_select_attack.png`

Le fichier contient **trois vignettes de 480×270 natif** empilées
(y = 140, 460 et 780 dans l'export) : menu du premier allié, ciblage, puis menu
du second allié. La deuxième est la référence du Lot 3 ; les deux autres
documentent la boucle de tour et servent au Lot 5.

Le ciblage y change quatre choses en plus de la cible elle-même :

1. **Le menu se réduit à l'action retenue.** Eko / Items / Guard disparaissent,
   et la pastille « Attack » va se poser près de la cible, curseur à sa gauche
   et incliné vers elle. C'est `CommandMenu` qui gère ce mode réduit
   (`focus_selection`) plutôt qu'une seconde pastille dessinée ailleurs : la
   pastille garde ainsi son balayage lumineux et son curseur.
2. **La plaque « nom + jauge » est SOUS la cible**, pas au-dessus, posée au
   sol. Le nom est au corps 14 — un cran sous la légende de combat, mesuré sur
   les avances de glyphes (39 px cumulés contre 41,25 au corps 15).
3. **La jauge de la cible fait 32 px, contre 59 au HUD.** Même asset :
   `HpBar` accepte désormais une largeur, la gouttière est découpée en 9
   tranches et le dégradé ramené à la longueur de la piste.
4. **L'invite « cercle » de la légende est alignée à DROITE**, pas posée à une
   abscisse fixe : « Cancel » (40 px) et « Back » (27 px) se terminent au même
   endroit, c'est l'icône qui recule. La règle redonne exactement l'abscisse
   333 relevée au Lot 1 pour « Cancel ». Sur la première vignette, l'invite est
   d'ailleurs **absente** : au tour du premier allié il n'y a rien à annuler.

Recalage du rendu contre la vignette, par corrélation sur chaque élément :
pastille, curseur, nom, jauge et libellé « Back » tombent tous à (0, 0) — écart
nul. Le bord gauche du texte « Back » est à 365 dans les deux images, et les
sept glyphes de « Cactoon » à moins de 0,5 px de leurs positions relevées.

### Points relevés en cours de route

1. **Les planches d'ennemis sont en niveaux de gris** (le cactoon n'a que des
   pixels r = v = b). Une surbrillance blanche y est donc bien moins lisible
   que sur un sprite coloré : le battement ne descend pas sous 0,6, ce qui
   maintient le gris médian de la cible à ~180 quand celui de ses voisines est
   à 74.
2. **L'ombre au sol fait partie de la cellule du sprite** (rangées 52 à 66 de
   la planche du cactoon : une ellipse noire opaque). Blanchir la cellule
   entière allumait un halo sous les pieds de la cible. `white_tint.gdshader`
   reçoit donc un seuil de luminance (`dark_cutoff`) sous lequel un pixel garde
   sa couleur — l'ombre et le contour du personnage restent sombres, la
   silhouette est blanche. Valeur par défaut 0.0 : la tuile de révélation du
   worldmap, seul autre usage du shader, est inchangée.

### Vu sur la maquette, PAS implémenté (relève du Lot 5)

Ces éléments appartiennent à la boucle de tour, pas au ciblage :

- l'allié dont c'est le tour prend une **pose d'attaque** pendant qu'il vise ;
- l'autre allié est rendu en **fantôme vert translucide** ;
- une fois son action validée, l'allié passe en **silhouette sombre** et son
  panneau de HUD affiche une **coche verte** à la place du portrait
  (`ic_checkmark.svg`, déjà présent dans `_assets/battle/`) ;
- l'invite « Cancel » réapparaît alors, pour revenir au tour précédent.

---

## 5 quater. Résultat du Lot 4

« Eko » et « Items » ouvrent une sous-liste, qui mène au ciblage déjà écrit au
Lot 3. Rien de neuf n'a été créé là où un composant existait :

- **`CommandMenu` sert les trois listes.** Ses entrées sont passées en
  dictionnaires (`id`, `text_id`, `cost`, `affordable`), et sa géométrie est
  choisie par `set_layout()` — voir plus bas, les deux dispositions n'ont
  presque rien en commun.
- **Le coût est rendu avec `ApDots`**, l'asset du HUD. Un coût que l'allié ne
  peut pas payer s'affiche en losanges ÉTEINTS : c'est déjà le sens que ces
  deux icônes portent sur la ligne de PA, il n'y avait pas à inventer un état
  « désactivé ».
- **`TargetSelector` gagne un mode GROUPE.** Les Ekos et objets qui visent un
  camp entier allument toutes leurs cibles d'un coup ; la plaque nom + jauge
  est alors masquée (elle ne pourrait en nommer qu'une), et la pastille de
  l'action se pose au barycentre des cibles.
- **`BattleData` sert les trois catalogues** (unités, Ekos, objets) par un seul
  chargeur paramétré, les trois fichiers ayant la même forme.

### Ce que montre `mockup_preparation_select_eko.jpg`

Quatre vignettes de 480×270 natif : menu du premier allié, liste d'Ekos,
ciblage, menu du second allié. Une première intégration avait supposé que la
sous-liste remplaçait le menu racine dans sa bande ; la maquette dit tout
autre chose.

- **La liste est en haut à GAUCHE, en escalier.** Ses pastilles font 123 px de
  large (contre 78 au menu racine), chaque rangée descend de 15 px en se
  décalant de 10 px vers la droite, et l'entrée sélectionnée n'est PAS avancée
  horizontalement — elle se distingue par sa seule couleur. Les libellés des
  trois entrées commencent à 121, 131 et 141 : la cascade est nette.
- **Chaque RANGÉE est inclinée sur elle-même**, la liste ne l'est pas. Le bord
  supérieur d'une pastille descend bien de 3° (relevé : y = 45, 43, 42, 40 pour
  x = 110, 140, 170, 200), mais l'écart d'une rangée à la suivante vaut
  exactement (10, 15) — le décalage à plat — là où une rotation d'ensemble
  donnerait (10,77 ; 14,46). C'est la différence qui faisait dériver les icônes
  de type : posées dans un groupe incliné en bloc, elles s'écartaient d'un pixel
  de plus à chaque rangée. La liste est donc posée à même le Stage, et ce sont
  la pastille, le libellé, le coût et l'icône qui portent chacun l'inclinaison.
- **Chaque entrée porte une icône de type**, encastrée dans le bord gauche de
  la pastille (décalage (4, 1)). Deux variantes, `ic_type_action_1.svg` et
  `_2.svg`, qui ne diffèrent que par la couleur de l'éclair — bleu ou orange ;
  c'est le champ `type` du catalogue qui choisit. Ce décalage est relevé sur
  `menu_long_list.png`, PAS sur les maquettes de scène : voir plus bas.
- **Le libellé est retiré de 18 px**, pas de 6 : la place à gauche revient à
  l'icône d'élément de l'Eko.
- **Le coût est aligné à droite**, à 8 px du bord, et ses losanges sont plus
  serrés que ceux du HUD (pas de 6 contre 9) — même asset, espacement propre à
  la colonne. Son décalage est appliqué DANS LE REPÈRE DE LA RANGÉE : posé à
  une centaine de pixels du coin, là où l'inclinaison a remonté la surface de
  près de 6 px, un décalage à plat le faisait sortir par le bas de la
  pastille. Le libellé, lui, reste à plat — à 18 px du coin l'écart ne vaut
  qu'un pixel, et la mesure penche de ce côté.
- **Le cadre de description est un cadre « INFO »** posé au milieu à droite
  (213, 159), de 203×71, avec un onglet de titre en haut à gauche et un corps
  de trois lignes au pas de 12.
- **L'invite « Cancel » est présente au menu racine**, sur les deux vignettes
  qui le montrent. Elle avait été masquée au Lot 3 d'après la première
  vignette de la maquette d'attaque, qui ne l'affichait pas ; cette maquette-ci
  est plus récente et la montre deux fois, elle fait donc foi.

Recalage du rendu contre la deuxième vignette : pastilles et libellés des trois
rangées tombent aux abscisses relevées (121 / 131 / 141), le bord droit de
chaque groupe de losanges aussi (217 pour un coût de 1, 237 pour un coût de 2),
et le cadre INFO à un demi-pixel près (titre à 230/172, corps à 234/183). Les
positions calibrées au Lot 3 sont inchangées au centième de pixel.

### La liste longue (`menu_long_list.png`)

Trois vignettes — « First », « Mid », « Last » — sur une liste de vingt
entrées, à l'échelle de design. Elles fixent deux règles :

- **Sept rangées visibles**, et la sélection est maintenue sur celle du
  MILIEU, la fenêtre butant aux deux extrémités : `Txt 6` sur la fenêtre 3–9 et
  `Txt 17` sur 14–20 tombent tous deux en quatrième position, tandis que
  `Txt 2` reste en deuxième parce que la fenêtre ne peut pas remonter plus
  haut.
- **Les rangées de bord s'estompent, mais seulement du côté où la liste
  continue** : opacité 0,25 pour la rangée extérieure, 0,50 pour la suivante.
  Mesuré par démélange sur le gris de la planche (0,246 et 0,492 sur deux
  canaux indépendants). La vignette « First » ne fond donc pas ses deux
  premières rangées, et « Last » pas ses deux dernières.

Les trois vignettes sont rejouées à l'identique par la liste d'Ekos de Noah,
portée à quinze entrées pour le test : fenêtres et opacités correspondent
exactement. Les entrées `test_N` d'`ekos.json` n'existent que pour ça et
peuvent être supprimées sans rien casser.

Sept rangées font descendre la liste jusque sur le terrain — c'est pourquoi
**tous les combattants passent à 30 % d'opacité pendant le choix d'une
action**, sauf l'allié dont c'est le tour.

Pendant le CIBLAGE, l'estompage se fait par camp : celui qui est visé garde son
opacité, l'autre passe à 30 %. Viser un ennemi efface donc les autres alliés,
et un Eko de soin fait l'inverse. L'allié qui agit n'est jamais estompé.

### Calibrer sur le PNG, pas sur le JPEG

`menu_long_list.png` est la seule maquette de liste livrée **sans perte** et à
l'échelle de design. Les maquettes de scène, elles, sont en JPEG : leur
compression déplace d'un pixel le bord des petits aplats, ce qui suffit à
fausser le calage d'une icône de 12 px. Deux corrections sont venues de là :

- l'ordonnée de l'icône, mesurée à +1 sur le PNG (coin de pastille en
  (79 ; 134,1) par ajustement linéaire du bord supérieur sur vingt colonnes,
  disque en y 136..147) alors que le JPEG donnait +0 ;
- l'inclinaison par rangée (ci-dessus), que seul l'écart exact de (10, 15)
  entre deux rangées permettait de trancher.

Vérification finale par corrélation du disque seul, sur une rangée non
sélectionnée des deux côtés : minimum net à (0, 0), l'écart doublant au
moindre pixel de décalage. Pour les losanges, comparaison des centroïdes
(insensibles au seuil) : la maquette donne 105,86 et 112,10 depuis le coin de
la rangée, le rendu 105,87 et 112,12.

### Le piège de cette maquette

Elle est fournie en **JPEG**, et ses pastilles sont inclinées. Caler la liste
sur le bord supérieur de la première pastille donnait 6 px d'erreur : ce bord
n'est jamais horizontal (le bout droit remonte de 6 px sur 123 à −3°) et le
contour flou l'étale encore. **La bonne référence est le TEXTE** — son encre se
mesure sans ambiguïté, et l'écart texte/pastille est connu par le menu racine,
déjà calibré au pixel près sur un PNG.

### La colonne de droite : coût pour un Eko, QUANTITÉ pour un objet

Un objet ne consomme pas de points d'action ; sa colonne de droite affiche donc
le nombre en réserve (« x13 ») à la place des losanges. Les deux ne coexistent
jamais, et le nombre reprend exactement la place qu'occupaient les losanges :
même bord droit, même centre vertical, mêmes couleurs que le libellé de la
rangée (sombre sur la pastille sélectionnée, saumon ailleurs). Il est aligné à
DROITE, sa largeur variant avec le nombre de chiffres.

Un objet à zéro reste affiché — la maquette en montre un — mais le valider est
refusé : le « x0 » de la ligne le disait déjà, le son d'erreur ne fait que le
confirmer. Symétrique du refus d'un Eko trop cher.

L'inventaire (id → quantité) est pour l'instant une constante de `BattleScene`,
en attendant un véritable inventaire de partie.

### Non implémenté, faute de spécification

- La **dépense** effective des PA et la **consommation** d'un objet : choisir
  ne débite rien encore, cela n'arrive qu'au moment où l'action entre en file
  (Lot 5).
- La teinte des ennemis pendant le choix et les poses d'alliés — cf. « Reste à
  spécifier ».

---

## 5 quinquies. Résultat du Lot 5

La boucle de préparation est fermée : chaque allié vivant choisit à son tour,
et la phase se termine quand ils ont tous choisi.

- **L'action est retenue sur l'unité** (`BattleUnit.action`) et son coût est
  débité À CE MOMENT-LÀ, pas à l'exécution : PA pour un Eko, un exemplaire pour
  un objet. C'est ce qui rend le retour en arrière exact — ce qui est rendu est
  exactement ce qui avait été pris.
- **« Guard » ne vise personne** : elle est retenue sans passer par le ciblage,
  et ne coûte rien. Ce qu'elle FERA relève du Lot 6.
- **« Cancel » au menu racine revient au tour de l'allié précédent** en défaisant
  son choix. Au premier allié il n'y a rien à défaire : son d'erreur.
- **Fin de préparation** : le signal `preparation_finished` porte les actions
  dans l'ordre des alliés. L'écran reste alors en place, « Cancel » permettant
  encore de revenir sur le dernier choix ; c'est là que le Lot 6 branchera
  l'assaut.

### Présentation d'un allié qui a choisi

Relevée sur la quatrième vignette de `mockup_preparation_select_items.png`,
en PNG donc sans perte :

- **son sprite et son portrait s'assombrissent** (valeurs ajustées par moindres
  carrés sur la maquette ; corrigées depuis, cf. § 5 sexies — le sprite est
  assombri SANS alpha et change de planche) ;
- **une coche verte se pose sur son portrait**, dont l'origine tombe à (327, 32)
  à l'écran dans le rendu comme dans la maquette ;
- le cadre jaune, lui, suit l'allié ACTIF et n'a rien à voir avec le choix.

Trois écritures concurrentes visaient la modulation des sprites (estompage par
camp, teinte « action retenue »). Elles sont désormais centralisées dans
`_refresh_unit_visuals`, seul endroit qui décide : action retenue > camp non
regardé > pleine opacité.

### Une lecture du Lot 1 corrigée au passage

Le compteur de PV bleu avait été rattaché à l'allié ACTIF, d'après une maquette
où les deux coïncidaient. Les maquettes de la boucle de tour les séparent :
Noah garde son compteur bleu après avoir joué, alors que le cadre jaune est
passé à Iris. C'est donc la BLESSURE que la couleur signale, pas le tour —
la même que le segment bleu de la jauge de PV. `set_active()` ne touche plus à
la couleur ; c'est `set_hp()` qui la pilote depuis la blessure en attente
(cf. § 5 sexies). Conséquence visible : les deux compteurs sont blancs au
repos, là où la maquette montre un Noah déjà blessé.

### Ce que la maquette montre

L'allié ACTIF y est dessiné avec sa planche `idle`, frame 0 — vérifié par
recalage, erreur nulle. Pour l'allié qui a DÉJÀ CHOISI, la première lecture
(« `idle` assombri ») s'est révélée fausse : c'est sa planche `standby`, cf.
§ 5 sexies.

---

## 5 sexies. Blessures, poses et emplacement du menu

Quatre demandes de l'auteur, traitées ensemble parce qu'elles se recoupent —
deux d'entre elles se relèvent sur la même maquette.

### 1. Deux sortes de dégâts

Une attaque « directe » retire les PV tout de suite. Une attaque « de
blessure » ne les retire pas : elle les met EN ATTENTE, affichés en bleu au
bout de la jauge. Ce qui décide de leur sort est ce qui arrive ensuite :

| événement | effet |
|---|---|
| un tour sans le moindre dégât | la blessure s'efface — l'unité guérit de ce qu'elle aurait dû subir |
| une nouvelle blessure | elle s'ajoute à celle en attente |
| un dégât direct | tout part des PV d'un coup : direct + blessure + **bonus de conversion** |

Le modèle vit dans `BattleUnit` (`injury`, `take_direct_damage`,
`take_injury_damage`, `end_turn`) ; personne ne l'appelle encore, c'est la
phase d'assaut (Lot 6) qui infligera les dégâts et refermera les tours.

**Deux points restent à l'auteur.** Le **bonus de conversion** est bien une
simple addition au total (confirmé), mais son NOMBRE n'est pas fixé :
`INJURY_CONVERSION_BONUS` vaut 0 en attendant. Et « pendant le même tour ou au
tour suivant » a été lu ainsi : la blessure s'efface à la fin du premier tour
qui se passe sans aucun dégât — donc jamais celui où elle vient d'être
infligée.

**Le rendu** (`HpBar`) : le segment occupe l'espace entre les PV acquis et les
PV courants, en fond `#153FE4` rayé de `#007BFF` à 45°, les rayures défilant en
boucle. Le motif est fabriqué à la résolution de l'ÉCRAN et non de design —
la zone ne fait que 3 px de design de haut, une diagonale n'y tiendrait pas,
alors qu'à l'écran elle en fait 12. Il tient en UNE tuile de 8 px de large :
`texture_repeat` la fait boucler, et le défilement n'est qu'un déplacement de
`region_rect`, sans shader ni texture redessinée par image. Le compteur de PV
du HUD passe au bleu tant qu'une blessure est en attente — c'est la lecture
corrigée au Lot 5 qui trouve enfin son déclencheur.

### 2. Les alliés changent de planche

- **il a VALIDÉ une attaque ou « Eko »** → pose de visée FIGÉE. Pour Noah,
  `313000404_atkeff.png`, frame 6 comptée à partir de 1 (index 5), posée en
  `frames: 1` — une image tenue, pas une boucle, même mécanique que le cactoon.
  Iris n'a pas encore de planche d'attaque : elle reste au repos, ce qui est
  exactement ce qu'on veut d'un asset manquant — rien, pas un état inventé.
- **il a validé son action** → pose d'attente (`313000404_standby.png`,
  `100022805_standby.png`), animée, avec un assombrissement **opaque**,
  `Color(0.565, 0.337, 0.308)`. Sans alpha : le personnage ne devient pas
  translucide, il passe à l'ombre.

Le déclencheur est la VALIDATION, jamais le survol : au menu racine l'allié n'a
encore rien décidé, et sa silhouette changerait à chaque mouvement du curseur.
Les deux commandes ne dégainent donc pas au même écran, parce qu'elles ne sont
pas validées au même moment — « Attack » ouvre directement le ciblage, « Eko »
ouvre d'abord sa liste, et c'est déjà là que Noah dégaine. « Items » et
« Guard » ne font dégainer nulle part, ciblage compris.

**L'ancrage des planches ne va pas de soi.** Elles ne cadrent pas leur cellule
pareil : entre `idle` et `standby`, l'ombre au sol de Noah se déplace de
11,5 px dans sa cellule. Laissées au centre-bas, les deux planches feraient
sauter le personnage sur place. D'où un champ `anchor` par animation dans
`units.json`, relevé sur l'ELLIPSE D'OMBRE — le seul repère commun à toutes les
planches, et la seule chose qui touche vraiment le sol.

Celui de la planche `standby` de Noah est en plus recalé sur la maquette
(minimum net à résidu 8,7 contre 21 au voisin), qui le place 1 px plus haut que
l'alignement des ombres seul. **Et c'est ce recalage qui a montré que la
maquette utilise DÉJÀ la planche `standby`** pour l'allié qui a joué : résidu
8,7 avec `standby` contre 45 avec `idle`. La demande de l'auteur ne faisait
donc que corriger une lecture fautive du Lot 5. Aucune maquette ne montre Iris
en `standby` : son ancre est déduite de l'ombre seule, à un pixel près.

### 3. Le menu suit l'allié dont c'est le tour

Les positions du menu sont celles du PREMIER emplacement allié ; pour les
suivants, c'est le groupe incliné entier qui est translaté, inclinaison et
géométrie inchangées. Le décalage du second est relevé sur la quatrième
vignette de `mockup_preparation_select_items.png` par recalage de la pastille
« Guard », identique dans les deux maquettes : minimum net à **(51 ; −11)**,
résidu 6,0 contre 12,9 aux voisins immédiats.

Ce n'est PAS la translation des emplacements de combat, qui vaut (58 ; −11) :
l'auteur a rapproché le menu de 7 px. D'où une table relevée
(`MENU_SLOT_OFFSET`) plutôt qu'un calcul à partir d'`ALLY_SLOTS`.

Conséquence sur `CommandMenu.to_flat()`, qui ramène un point du terrain dans le
repère d'une liste : il ne peut plus être reconstruit à partir d'un pivot et
d'un angle posés à la main, puisque le groupe porteur se déplace. Il est
désormais déduit des transformations réelles de l'arbre, ce qui couvre du même
coup la sous-liste, posée à même le terrain. Vérifié sans régression : les
positions du Lot 3 sortent identiques au dix-millième
(`pastille=(224.0923 ; 77.34132)`, `nom=(161 ; 164)`, `jauge=(177 ; 179)`,
`légende=(346 ; 232)`).

### 4. « Cancel » masqué au premier allié

Le premier à jouer n'a rien à défaire : l'invite est masquée plutôt
qu'affichée sans effet. C'est ce que montrait déjà `mockup_preparation.png`,
dont la légende ne porte que « Confirm » — l'écart n'avait pas été relevé au
Lot 1. La touche continue de répondre par le son d'erreur.

---

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

### Règles tranchées (réponses de l'auteur, à appliquer dans les lots concernés)

1. **Tour ennemi + rythme** (Lot 7) : un bon timing pendant le tour d'un ennemi
   RÉDUIT les dégâts subis, sans jamais les annuler. Trois paliers :
   Perfect → réduction forte, Great → moyenne, Good → faible. (Miss = aucune
   réduction.) Les coefficients restent à chiffrer.
2. **Effet de la synergie** (Lot 8) : la jauge débloque une **compétence
   spéciale**, utilisable uniquement pendant la phase d'assaut et seulement si
   la jauge est au moins au niveau 1. La compétence elle-même n'est pas encore
   définie — à spécifier avant le Lot 8.
3. **Fin de combat** (Lot 9) : victoire quand tous les ennemis sont à 0 PV ou
   moins, défaite quand tous les alliés le sont. Le joueur gagne de l'argent
   et de l'expérience ; l'écran de récompense n'a pas encore de maquette.
4. **Déclenchement du combat** (Lot 9) : rencontre **aléatoire** sur le
   worldmap. La touche Z reste l'entrée de test (déjà en place).
5. **Composition de l'équipe** : **2 alliés fixes**, Noah et Iris. Le HUD à
   deux blocs est donc définitif, pas un provisoire.
6. **PA maximum : 5** — c'est le plafond du SYSTÈME (la rangée de losanges ne
   dépasse jamais 5), pas la valeur de chaque unité : Noah en a 3 et Iris 2
   dans `Battle/units.json`, conformément au mockup.

### Reste à spécifier

- **Le contenu réel des Ekos et des objets.** `Battle/ekos.json` et
  `Battle/items.json` sont livrés avec six compétences et quatre objets
  PROVISOIRES, choisis pour exercer chaque mode de ciblage et faire défiler la
  liste. Le schéma est stable ; seul le contenu est à remplacer.
- **Le type réel de chaque Eko et de chaque objet.** Deux variantes d'icône
  existent (`ic_type_action_1/2.svg`, éclair bleu ou orange) ; le champ `type`
  du catalogue choisit laquelle, et les valeurs actuelles sont arbitraires.
- **Le bonus de dégâts de la conversion blessure → direct** (`BattleUnit.
  INJURY_CONVERSION_BONUS`, aujourd'hui 0 : simple addition).
- **Une planche d'apprêt pour Iris** : elle n'a pas d'équivalent de
  `313000404_atkeff.png`, et reste donc au repos pendant qu'elle prépare une
  attaque ou un Eko.
- La compétence spéciale débloquée par la synergie (bloque le Lot 8).
- Les coefficients de réduction de dégâts Perfect/Great/Good (bloque le Lot 7).
- L'écran de récompense argent/expérience (bloque la fin du Lot 9).
- **Le comportement de la pastille d'action quand la cible change** : la
  maquette ne montre qu'une cible (l'ennemi de droite). La pastille est
  actuellement ANCRÉE SUR LA CIBLE, donc elle suit la sélection ; une position
  fixe à l'écran est l'autre lecture possible de la même image.

---

## 8. Ce que ce plan ne fait pas

- Aucune modification du worldmap existant, hors masquage du HUD pendant la
  capture de fond.
- Aucun système de dialogue (la catégorie `dialogue` du catalogue de textes
  reste vide, comme décidé au chantier localisation).
- Aucune page MapEditor nouvelle avant le Lot 10.
