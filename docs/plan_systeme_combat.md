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
    (+ quatre AudioStreamPlayer montés en code : move / validation / error, et
     le thème de combat — cf. §1.4)
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

### 1.4 Son

**La musique.** `battle_theme1.mp3`, lancé par `_build_music()` à l'ouverture de l'écran, à
**75 % du volume** (`volume_linear = 0.75`, et non un `volume_db` converti à la
main). Deux points :

1. **Le bouclage est une propriété de la ressource**, pas du lecteur : il est
   forcé en code (`_music.stream.loop = true`), comme le fait déjà le thème du
   worldmap dans `map_loader._ready()`.
2. **Rien à faire côté worldmap.** `BattleLauncher` le passe en
   `PROCESS_MODE_DISABLED`, ce qui suspend son `AudioStreamPlayer` : vérifié en
   jeu, `playing` retombe à `false` et la position reste figée (0,33 s pendant
   tout le combat), puis la lecture **reprend à cette position** quand
   `close()` rend la main. Deux thèmes ne se superposent donc jamais, et la
   sortie de combat n'a pas plus à restaurer la musique que le reste.

**Les sons d'action.** Une action porte une LISTE de sons, chacun accroché à un
moment du déroulé de l'assaut. Elle vit au même endroit que sa puissance et sa
séquence : dans `basic_attack` pour une attaque, dans le catalogue pour un Eko
ou un objet.

```json
"sounds": [
  {"at": "rhythm", "sound": "res://Audio/Battle/noah_charge.wav"},
  {"at": "hit",    "sound": ["res://.../noah_att1.wav", "res://.../noah_att2.wav"]}
]
```

| Champ | Règle |
|---|---|
| `at` | le moment où le son part. `hit` par défaut |
| `sound` | **un** chemin `res://`, ou **plusieurs** — plusieurs chemins sont des VARIANTES du même son (`noah_att1/att2/att3`), tirées au hasard. Pour jouer deux sons au même moment, on met **deux entrées** |

Les six moments, qui sont des points réels de `BattleAssault._resolve` et non
une liste de souhaits (`SOUND_MOMENTS`) :

| `at` | Instant | Existe quand |
|---|---|---|
| `announce` | la pastille de l'action s'affiche | toujours |
| `rhythm` | la séquence de notes commence | l'action a une `sequence` |
| `approach` | l'attaquant s'élance vers sa cible | action offensive |
| `gesture` | le geste part | toujours |
| `hit` | l'effet s'applique — **le défaut** | toujours |
| `return` | l'attaquant repart vers son emplacement | action offensive |

Un son accroché à un moment que son action n'atteint pas ne se joue jamais :
c'est assumé, mais c'est le piège du champ. Un `at` inconnu est **ignoré avec un
avertissement**, comme un `kind` de comportement inconnu.

**`announce` et `rhythm` tombent aujourd'hui dans la MÊME frame** (mesuré :
t=7,14 pour les deux), parce que rien ne s'intercale entre l'affichage de la
pastille et la première note. Les deux ancres restent distinctes — elles se
sépareront dès que la pastille aura une animation d'entrée — mais il ne faut pas
attendre d'écart entre elles en l'état.

Trois décisions de découpage :

1. **Le son est de la donnée, pas du code.** Donner sa voix à un personnage —
   `noah_att1.wav` sur l'attaque de Noah — se fait dans `units.json`, jamais par
   un `if unit.id == "noah"`. Même règle que pour `animation`, `sequence` et
   `behaviour`, et c'est ce qui rend le champ éditable depuis la page
   « Combat » du Lot 10.
2. **Un déclenchement par ACTION, pas par cible.** Une attaque de groupe est un
   seul geste : trois exemplaires du même cri superposés ne feraient que
   saturer. Les `_cue()` sont donc hors de la boucle sur les cibles.
3. **Les lecteurs restent à la scène.** `BattleAssault` émet `sound_cue(path)`,
   il ne possède aucun `AudioStreamPlayer` — même partage que pour `impact` et
   `field_shift`. La scène en tient **quatre** (`SFX_ACTION_VOICES`), distincts
   des trois sons d'interface : deux sons accrochés au même moment partent dans
   la même frame, et un lecteur unique n'en jouerait qu'un. Les quatre occupés,
   le plus ancien est volé plutôt que de laisser tomber le son demandé. Les flux
   sont mis en cache par chemin, un chemin absent mémorisé comme `null` pour
   n'avertir qu'une fois.

Vérifié en jeu, les six moments accrochés d'un coup sur l'attaque de Noah :

```
t=7.14  cue announce        t=10.04  cue hit
t=7.14  cue rhythm          t=10.04  cue hit (2e entree)
t=9.55  cue approach        t=10.18  cue return
t=9.89  cue gesture
--> jusqu'a 3 voix simultanees, moment inconnu ignore avec avertissement,
    fichier absent signale une fois puis ignore
```

Le dossier `_assets/battle/_voices/` contient une trentaine de répliques
(`noah_att1..3`, `noah_hit1..3`, et des phrases de victoire, de défaite, de
soin). **Une seule est posée à ce jour**, sur `hit` : l'auteur n'a pas dit
quelle réplique va sur quelle action ni sur quel moment. Le champ est prêt, le
casting non — et c'est la page « Combat » du Lot 10 qui servira à le faire,
plutôt que de remplir les JSON à la main (cf. §7 bis).

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
| Musique | `battle_theme1.mp3` en boucle, `volume_linear = 0.75` (cf. §1.4) |
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
| 6 | Phase d'assaut : ordre par agilité, exécution des actions, dégâts, morts | **fait** |
| 7 | Barre de rythme : défilement des notes, fenêtres Perfect/Great/Good/Miss, bonus de dégâts | **fait** |
| 8 | Jauge de synergie (remplissage, 4 niveaux) | **fait**, sauf la compétence qu'elle débloque |
| 9 | Victoire / défaite, transition worldmap ↔ combat, animations `win` / `dying` / `dead` | **fait** pour la victoire, le retour au worldmap et le « Game Over » ; reste `dying`/`dead`, l'écran de récompense et le déclenchement d'un combat en jeu |
| 10 | Page « Combat » de MapEditor : unités (stats, comportement ennemi, Ekos connus), Ekos, objets | **fait** |

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

## 5 septies. Résultat du Lot 6

La boucle de combat est fermée : préparation → assaut → nouvelle préparation,
jusqu'à ce qu'un camp tombe.

### Découpage

`BattleAssault` **joue une liste d'actions**, rien de plus. Refermer le tour —
rendre les PA, effacer les actions, guérir les blessures épargnées, faire tomber
les gardes — reste à `BattleScene`, qui possède la boucle. Le partage suit la
question « est-ce que ça a lieu PENDANT l'assaut ? » : les dégâts oui, la remise
à zéro non.

`BattleRules` isole les seuls nombres que l'auteur voudra régler, pour qu'il
n'ait pas à lire la mécanique qui les emploie.

### Règles chiffrées (réponses de l'auteur)

| Règle | Valeur |
|---|---|
| Dégâts | `(puissance + force) − défense`, plancher à 1 |
| Garde | dégâts subis divisés par deux |
| Type de dégâts | champ `damage_type` par Eko / objet / attaque de base |
| Bonus de conversion blessure → direct | une addition, **nombre encore à fixer** |

La garde est posée AVANT le premier coup de l'assaut, pas au moment où l'unité
aurait agi : elle a été choisie pendant la préparation, elle vaut pour le tour
entier. Sinon une unité lente se ferait frapper à découvert par tous ceux qui la
devancent.

### Ordre et ciblage

Agilité décroissante sur tous les combattants vivants ; à égalité, les alliés
passent devant (il faut un départage stable, et l'avantage au joueur se défend
le mieux). L'ordre est calculé UNE FOIS par tour : une unité qui tombe en cours
d'assaut ne joue pas, mais l'ordre lui-même n'est pas recalculé — l'agilité
départage le tour, elle ne doit pas dépendre de qui vient de tomber.

Les cibles sont retenues **comme des unités** à la validation, pas comme un
index : celui-ci désigne une place dans la liste des vivants au moment du choix,
et cette liste a changé quand l'assaut s'exécute. Une cible tombée entre-temps
est remplacée par une autre du même camp — le joueur a choisi une action, pas un
cadavre. Vérifié : l'attaque de Noah bascule sur le cactoon suivant quand Iris
abat le sien avant lui.

### Mise en scène

Référence : `_assets/battle/mockup_assault_allies.jpg`, cinq vignettes de
480×270 natif (extraites à `x = 140`, `y = 139 + 320k`). **C'est un JPEG** : on y
lit la composition et l'enchaînement, on n'y cale rien au pixel — les valeurs
reprises ci-dessous viennent toutes de relevés antérieurs sur PNG.

**Aller au contact, frapper, revenir.** L'attaquant quitte son emplacement,
s'arrête à `APPROACH_DISTANCE` (30 px) de sa cible **du côté d'où il vient**
— la règle vaut pour les deux camps, et reste juste si les emplacements
changent. Sur un ciblage de groupe il se poste au barycentre des cibles, comme
le fait déjà le ciblage (cf. `TargetSelector`). Une action qui SOIGNE ne se
déplace pas : elle n'a personne à aller chercher, et traverser le terrain pour
tendre une potion se lirait comme une charge.

**La planche est choisie par l'ACTION, pas figée dans le code.** Une attaque ou
un Eko nomme un geste (`"animation": "atk"`), cherché dans le bloc `animations`
de l'unité **qui agit** — pas dans le catalogue de l'action : un Eko est partagé
par plusieurs personnages, chacun le joue avec sa propre planche. La fourchette
de frames se règle donc sur la planche (`first_frame`, `frames`, `hit_frame`),
ce qui permet à un même fichier de servir plusieurs gestes. L'attaque de Noah
s'arrête ainsi aux frames 1 à 4 de `313000404_atk.png` (soit `first_frame: 0`,
`frames: 4`) alors que la planche en compte 20. Une planche absente n'est pas
une erreur : l'unité frappe sans geste. **L'édition depuis MapEditor est le
Lot 10** ; ce qui est livré ici est le modèle de données qu'elle pilotera.

**Le retour peut avoir sa propre planche**, `move_back`, jouée pendant que
l'unité regagne son emplacement (les deux durent le même temps, pour qu'elle ne
se termine pas en chemin). Personne n'en a aujourd'hui : le fichier livré sous
ce nom s'est révélé être **la première rangée de `313000404_limit_atk.png`**,
identique au pixel près — `move_back.png` = `limit_atk.png[3:132, 5:500]`, zéro
différence sur 63 855 pixels. Ce sont donc les trois premières images d'une
attaque spéciale (garde basse, garde haute, éclat), pas un retour. L'asset a été
retiré du projet ; la mécanique reste en place, déclarer l'animation suffira à la
faire jouer. D'ici là tout le monde revient sur sa planche de repos.

Chaque action s'interrompt à l'instant où le coup porte (`hit_frame`, relevé sur
la frame où la lame ou le tir part), applique ses effets, puis laisse le geste
s'achever. **C'est là que le Lot 7 s'insérera** : la barre de rythme prendra
place entre le début du geste et l'application, sans toucher au reste.

**Le coup se voit à trois choses** (`HitFeedback`, `BattleScene._shake`) :

- la silhouette touchée **s'embrase** un cinquième de seconde — même shader que
  la surbrillance de ciblage et que la tuile de révélation du worldmap, avec le
  même seuil de luminance qui épargne l'ombre au sol ;
- la **caméra tremble**, deux pixels de design amortis sur un quart de seconde.
  C'est le `Stage` qui bouge, pas le calque : celui-ci appartient déjà à
  `CanvasZoom`. Le fond capturé, qui vit hors du `Stage`, ne tremble donc pas —
  invisible à cette amplitude ;
- la **jauge de vie de la cible** apparaît sous ses pieds, **centrée** sur elle
  (décalage (−16, −1)). C'est le composant du ciblage à la même largeur
  (32 px), mais pas son décalage : là-bas la jauge se cale sous un nom de cible,
  ici elle est seule.

  Relevé sur `anim_jauge_hp.png`, dont les vignettes sont à ×2 du design. La
  correspondance verticale vient de la **frontière claire/sombre de la
  plateforme**, parfaitement horizontale et présente dans les deux images :
  y = 166 sur la référence, y = 179 en jeu, donc `design = référence/2 + 96`
  (vérifié sur dix colonnes). Le haut de la gouttière y tombe à 164 et le bas de
  l'ombre du personnage à 161 ; en remontant les 4 px qui séparent l'ombre du
  bas de sa cellule, le point « pieds » est à 165. **Le haut de la jauge est
  donc un pixel au-dessus des pieds**, pas dix en dessous comme au premier jet.

**L'encaissement s'anime en deux temps** (`HpBar.play_hit`), d'après la
référence `anim_jauge_hp` de l'auteur. Les deux cas partagent la même mécanique
— le bord du vert recule de l'acquis d'avant à l'acquis d'après — et ne
diffèrent que par la couleur de l'aperçu et par ce qu'il devient :

| | aperçu | résolution |
|---|---|---|
| **blessure** | aplat BLANC sur la part mise en jeu, FIXE | le bleu rayé le recouvre en suivant le bord du vert qui recule |
| **direct** | aplat ROUGE sur la part perdue | **seul le bord EXTÉRIEUR du rouge se rétracte**, jusqu'à disparaître dans le vert. Le vert visible, lui, est déjà à sa valeur finale et ne bouge plus |

L'aperçu se pose **sur la queue du vert**, pas après : il montre ce qui est sur
le point d'être perdu. D'où l'ordre de dessin — vert, aperçu, bleu — le bleu
passant bien « par dessus la partie blanche » comme demandé.

Le cas direct a demandé deux corrections, et la mesure colonne par colonne les
a tranchées toutes les deux. Relevé sur la piste de la référence (positions en
pixels de la planche, à ×2) :

```
vignette 2   vert ..124   rouge 125..139
vignette 3   vert ..118   rouge 119..127
vignette 4   vert ..118   rouge -
```

**Le bord du vert ne bouge pas** (à 3 px de design près, que le tracé à la main
explique), **seul le bord extérieur du rouge se déplace** : 139, puis 127, puis
plus rien. Deux premières versions se sont donc trompées — l'une laissait le
rouge immobile et le faisait s'effacer par transparence, l'autre faisait remonter
son bord gauche, ce qui faisait GRANDIR le vert visible en cours d'animation.
Une jauge de vie qui se remplit pendant qu'on encaisse : le genre de faute qu'on
ne voit qu'en mesurant, parce qu'à l'œil « ça bouge dans le bon sens ».

Le rouge de l'aperçu n'est pas choisi : c'est **#FF3700**, celui de l'éclair de
`ic_type_action_2.svg` — l'icône qui annonce un coup direct dans les listes.
Les deux disent la même chose, ils doivent être de la même couleur. Le blanc
vient de la référence d'animation, où il est franc.

### L'action retenue annonce sa nature pendant le ciblage

Quand « Attack » se réduit à sa pastille et va se poser près de la cible, elle
porte désormais **l'icône de nature des dégâts** de celui qui joue — rouge pour
Noah, bleue pour Iris. Au même endroit que dans une liste d'Ekos, à cheval sur
le bord gauche.

C'est un AJOUT de l'auteur, pas un rattrapage :
`mockup_preparation_select_attack.png` montre cette pastille sans icône. La
logique se tient — une fois réduite, la pastille ne dit plus « voici une
commande » mais « voici ce qui va être infligé ».

L'icône reste **cachée tant que le menu est déplié** (`mockup_preparation.png`
n'en a pas), et le libellé prend alors le retrait des listes (18 px au lieu de 6)
pour lui laisser la place : sans ça « Attack » perdait son A.

### Nature des dégâts et type élémentaire : deux informations distinctes

Le champ `type` (1 ou 2) des catalogues **a été supprimé**. Il redisait
`damage_type` dans une autre notation, et les deux avaient fini par se
contredire : « fulgura » portait l'éclair BLEU tout en infligeant des dégâts
DIRECTS. Les fichiers d'icônes tranchent — `ic_type_action_1.svg` et `_2.svg`
sont identiques au `fill` près, et le bleu de la première est **#007BFF**,
exactement la couleur des rayures de blessure de la jauge de PV. L'icône dit
donc ce que l'action inflige, et se **déduit** désormais de `damage_type` :

| `damage_type` | icône |
|---|---|
| `injury` | éclair bleu #007BFF |
| `direct` | éclair rouge #FF3700 |
| absent (l'action n'inflige rien) | pas d'icône |

**Les attaques de base ont leur nature**, fixée par l'auteur : Noah frappe
DIRECT, Iris inflige des BLESSURES. (Le cactoon est resté en direct, faute de
consigne.)

**Le type élémentaire (foudre, feu…) reste à définir** et sera une information
SÉPARÉE : un même élément pourra infliger l'une ou l'autre nature de dégâts. Le
champ est réservé sous le nom `element` dans les `_champs` des catalogues, et
n'est pas encore lu. Il changera la FORME de l'éclair ; la couleur continuera
de dire la nature.

Les attentes sont en SECONDES, déduites du nombre de frames et de la cadence de
la planche — l'environnement de debug tourne à une cadence irrégulière
(cf. `CLAUDE.md` §workflow, point 4), un comptage de frames n'y serait pas
reproductible.

Deux cas n'ont pas de planche à jouer. Une unité **sans planche d'attaque** (le
cactoon n'a QUE des idles) marque un temps d'arrêt au contact : le déplacement
tient lieu de geste. Une action qui **soigne** fait un pas en avant depuis son
emplacement. Dans les deux cas un déplacement n'invente aucun dessin,
contrairement à un sprite qu'on fabriquerait, et dit quand même « c'est mon
tour ».

Les **nombres de dégâts n'ont aucune maquette** — c'est le seul élément de
l'écran qui ne soit pas relevé. Plutôt qu'inventer un style, `DamageNumber`
réutilise celui du chiffre de niveau de la jauge de synergie (contour sombre,
liseré clair, corps en dégradé) et n'en change que la palette, prise dans les
couleurs déjà en service : brun/orangé pour les dégâts directs, les deux bleus
de la zone rayée pour la blessure, le vert du libellé « HP » pour un soin.
C'est le premier fichier à retoucher le jour où l'auteur fournit une maquette.

### Comportement des ennemis — en donnée, pas en code

Un ennemi n'a pas de phase de préparation : quelqu'un doit choisir à sa place.
Ce choix est de la **donnée de jeu**, pas de la mécanique — l'auteur veut
pouvoir dire « celui-ci est agressif, celui-là s'acharne sur Noah » depuis
l'éditeur web. `Scripts/Battle/EnemyBehaviour.gd` traduit donc le bloc
`behaviour` de `units.json` en une action de la même forme que celle qu'un allié
retient au menu ; le reste de l'assaut ne distingue pas les deux.

| Champ | Effet |
|---|---|
| `kind: "random"` | frappe un adversaire debout au hasard — **le défaut**, et le comportement d'un ennemi sans bloc `behaviour` |
| `kind: "aggressive"` | achève : vise le plus entamé **en proportion** de ses PV max, pas en valeur absolue — sinon un gros réservoir passerait pour le plus faible en permanence |
| `kind: "defensive"` | se met en garde sous `guard_below` (0,35 par défaut), frappe sinon |
| `kind: "focused"` | s'acharne sur l'unité nommée par `focus` ; si elle est tombée, il frappe au hasard plutôt que de perdre son tour |
| `eko_chance` | probabilité de lancer un Eko de sa liste `ekos` qu'il peut payer, plutôt que de frapper. **0 par défaut** : déclarer des Ekos ne suffit pas, il faut aussi dire qu'il s'en sert |

Un `kind` inconnu retombe sur `random` **avec un avertissement** : une faute de
frappe ne doit pas faire planter un combat, mais elle ne doit pas passer
inaperçue non plus.

**L'action d'un ennemi est RETENUE, comme celle d'un allié.** Elle était
décidée à la volée, à l'instant où son tour arrivait, et n'était donc jamais
posée sur l'unité : tout ce qui se joue au moment de la rétention lui échappait.
Deux conséquences, corrigées ensemble en décidant les actions ennemies à
l'ouverture de l'assaut (`BattleAssault._commit_enemy_actions`) :

- un ennemi `defensive` **ne levait jamais sa garde** — `_raise_guards` ne
  parcourait que les alliés, et `_resolve` sort avant d'y toucher sur un
  commentaire (« son effet est déjà en place ») qui n'était vrai que pour un
  allié. Tout le comportement `defensive` était donc inerte ;
- un ennemi ne **payait pas ses PA** en lançant un Eko, faute de quoi
  `eko_chance` en aurait fait une source infinie dès qu'un ennemi aurait des PA.

Décider à l'ouverture du tour plutôt qu'à l'instant d'agir suit le même
principe que l'ordre d'agilité, calculé une fois et non recalculé : le tour se
décide quand il s'ouvre. Une cible tombée entre-temps était déjà gérée — cette
machinerie existait précisément pour les actions retenues à l'avance.

Conséquence sur le modèle de ciblage, et c'est le vrai changement : un mode de
ciblage est désormais lu **relativement à celui qui agit**. « ally » désigne son
propre camp, « enemy » celui d'en face. C'est ce qui permet aux deux camps de
partager **un seul catalogue d'Ekos** : un soin déclaré « ally » soigne le camp
de celui qui le lance, sans qu'il faille deux versions de chaque compétence.
Vérifié — « Rosée » lancée par un cactoon vise un cactoon, « Tempeste » lancée
par un cactoon touche Noah et Iris.

L'édition de tout ça depuis MapEditor est le **Lot 10** (cf. plus bas).

### Ce qui reste minimal, délibérément

- **Une unité vaincue s'efface** (fondu). Les planches `dying` et `dead`
  existent mais relèvent du Lot 9.
- **Le combat s'arrête sur place** à la victoire comme à la défaite, sur le
  signal `battle_finished`. L'écran de résultat est au Lot 9.

### Vérifié en jeu

Combat complet mené par injection de touches réelles, du premier tour à la
victoire, puis chaque règle isolément :

```
ordre d agilite : iris(ag13) > noah(ag11) > cactoon(ag8) ×3
Tempeste (zone, blessure)  cactoon 30/30+bl16 ×3      pv intacts, 2 PA debites
tour suivant, aucun degat  cactoon 30/30 ×3           la blessure a gueri
Tempeste puis Attack       cactoon 1/30               conversion 16+13, plancher tenu
garde                      degats 4 -> 2 et 5 -> 2    moitie, arrondie vers le bas
potion                     noah 20 -> 50              +30, nombre vert
cible morte                l attaque bascule sur le cactoon suivant
victoire / defaite         signal emis, ecran fige
```

Les quatre comportements, sur 40 tirages chacun, face à un Noah à 20/62 et une
Iris à 80/82 :

```
random                     noah 24, iris 16            reparti
aggressive                 noah 40                     le plus entame en proportion
focused: iris              iris 40
focused: absent            noah 22, iris 18            repli sur le hasard
defensive a 30/30          attaque
defensive a  5/30          garde, cible lui-meme
kind inconnu               repli sur random + avertissement
rosee (ally) par cactoon   cible un cactoon            ciblage relatif
tempeste (enemies) idem    touche noah ET iris
```

### Deux dettes ouvertes

0. **Trois éléments de la maquette d'assaut ne sont pas faits** et relèvent du
   Lot 7 : la barre de rythme, le libellé « PERFECT », et la **pastille du nom
   de l'action** (« Fulgura ») posée en bas au centre pendant toute l'action.
1. **Aucune planche de retour.** `_noah/move_back.png` est un export erroné
   (première rangée de `limit_atk`), à refaire.
2. ~~**La planche `atk` d'Iris la déporte hors de la plateforme.**~~ **Réglé**
   par la plage de frames et la venue au contact : l'auteur ne retient que les
   frames 4 à 10 (`first_frame: 3`, `frames: 7`), et l'ancre est relevée sur
   l'ombre de la frame 3 — la première de la PLAGE JOUÉE, pas de la planche.
   L'ombre dérive ensuite de 57 px vers la droite, ce qui est le recul du tir ;
   partie du point de contact (cible + 30) sa cellule occupe 25..249 au lieu de
   déborder à 473 sur un écran large de 480. `hit_frame: 0` : la lueur de bouche
   est sur la première frame de la plage, le coup porte donc là.
   L'auteur remplacera tout de même les assets de ce personnage.
3. **Les valeurs d'équilibrage sont provisoires** : `basic_attack.power` (6, 5,
   6), et le bonus de conversion blessure → direct toujours à 0.

---

## 5 octies. Résultat du Lot 7 — la barre de rythme

### Découpage

| Fichier | Rôle |
|---|---|
| `UI/RhythmBar.gd` | la barre : moitiés, anneau, notes, fenêtres, verdicts |
| `UI/ActionBanner.gd` | la pastille qui nomme l'action, au-dessus de la barre |
| `BattleRules` | les deux tables de conversion verdict → multiplicateur |

### Géométrie, relevée sur `ui_rythmn_bar.jpg`

Cette planche de composants est **à l'échelle 1:1 du design** (ses barres font
480 px de large), ce qui en fait une source exacte malgré le JPEG — les bandes
de fenêtres y sont des aplats francs, pas des bords flous.

```
Perfect   |dx| <=  5 px      Great  <= 21      Good  <= 32      Miss  au-dela
barre     2 moities de 239x43, en x=1 et x=240, y=209
anneau    rhythm_circle en (219, 210) -> cercle blanc centre sur (239,5 ; 230,5)
verdict   corps 28, centre a 90 px de l anneau, du cote OPPOSE aux notes
pastille  noeud en (184, 186), largeur FIXE de 110 -> aplat en x 186..291, y 187..201
```

Les bandes de la planche sont **complémentaires au pixel près** (vert 375..384,
jaune 359..374 et 385..400, orange 348..358 et 401..411, rouge tout le reste,
pour une barre en 140..619) : c'est ce qui rend la lecture sûre.

**Les fenêtres sont en PIXELS, pas en millisecondes** — c'est ainsi que l'auteur
les a dessinées, en bandes concentriques. Le jugement se fait donc sur la
DISTANCE de la note à l'anneau au moment où la touche tombe. La vitesse de
défilement (`NOTE_SPEED`, 170 px/s) est le seul réglage de difficulté : c'est
elle qui convertit ces pixels en durées — Perfect ±29 ms, Great ±124 ms,
Good ±188 ms. Rien ne la fixe sur les maquettes.

**La pastille est à largeur fixe**, et c'est une mesure : « Fulgura » et
« Attack » occupent exactement le même `x 186..291` sur les deux maquettes.
Elle ne s'ajuste donc pas à son texte, contrairement à celles du menu.

Sa **pointe** n'a que trois rangées d'aplat — 9 px de large, puis 4, puis 2 — et
la première est CACHÉE dans le corps de la pastille : la maquette n'en montre
que les rangées 1 et 2, en `x 237..240` puis `238..239`, aux ordonnées 202 et
203. Le nœud se pose donc 15 px sous le haut de la pastille, pas 17 : la caler
sur sa rangée 0 la décrochait de deux pixels.

### Le terrain glisse vers le camp attaqué

Les deux maquettes d'assaut le montrent, et c'est mesurable : entre la vignette
au repos et celle où l'attaquant est au contact, **tout le terrain s'est déplacé
de 60 px, purement à l'horizontale**. Relevé par recalage du fond d'hexagones
(écart moyen 0,3), confirmé par le bord de la plateforme — 54 → 114 au tour
allié, 425 → 365 au tour ennemi.

**Ce n'est PAS la caméra.** Le HUD ne bouge pas d'un pixel sur les dix vignettes
des deux maquettes ; la barre de rythme et les bandes noires non plus. Ce qui
glisse, c'est le décor, les combattants et le fond capturé — et rien d'autre.
D'où un nœud `_field` intercalé sous le Stage, premier de ses enfants : tout ce
qui est monté après le recouvre sans bouger avec lui.

Le signe suit CELUI QUI AGIT : un allié frappe vers la gauche, le terrain part
donc vers la DROITE, comme si l'on se tournait vers les ennemis. Le mouvement
accompagne l'APPROCHE — sur les maquettes, la vignette où l'attaquant est au
contact est aussi celle où le décor a bougé — et se défait au retour.

Le fond capturé suit, et il a fallu l'**agrandir de 12 %** pour ça : cadré pile
sur l'écran, le déplacer découvrait du noir sur un bord. Sur une photo floutée
sous un voile sombre, le recadrage ne se voit pas.

```
 2.69  terrain +60   HUD 165   Iris attaque
 3.62  terrain   0   HUD 165   elle rentre
 6.62  terrain +60   HUD 165   Noah attaque
10.10  terrain -60   HUD 165   un cactoon attaque
13.86  terrain   0   HUD 165
```

### Les bandes noires passent DEVANT les combattants

Elles étaient montées en premier, donc derrière tout le reste. Ce n'est pas un
détail de goût : la bande du bas remonte de 48 px pendant l'assaut et vient
recouvrir le bas du terrain — derrière les unités elle se glissait sous leurs
pieds au lieu de les masquer, et le cadrage de l'écran se déchirait. Elles sont
désormais montées **après la plateforme et les unités**.

### La bande noire du bas remonte de 48 px pendant l'assaut

Comparaison de `mockup_preparation.png` et de la première vignette de
`mockup_assault_allies` : **48 px exactement**, sur les 22 colonnes où aucun
décor ne masque le bord. La bande HAUTE ne bouge pas — le HUD reste dégagé sur
les deux maquettes. L'écran se décale donc pour faire place à la barre, et
revient à la préparation suivante.

### ThorVG ignore les `<filter>` SVG

Les trois `rhythm_line_*` et `btn_directions` passent toute leur lueur par des
filtres SVG (`feGaussianBlur`, `feColorMatrix`), que le rastériseur de Godot
ignore **silencieusement**. Mesuré en comparant l'intensité moyenne du rendu SVG
à celle du PNG d'origine :

```
rhythm_line_empty   0,003 contre 0,039      btn_cross       0,093 contre 0,092  ok
rhythm_line_yellow  0,021 contre 0,174      rhythm_circle   0,259 contre 0,261  ok
rhythm_line_red     0,011 contre 0,098      command_red     0,347 contre 0,353  ok
```

Il ne restait qu'un dixième de la lueur. Ces quatre assets sont donc restés en
**PNG**, agrandis en bilinéaire (97 % de leurs pixels sont à alpha partiel, donc
de l'art anticrénelé et pas du pixel-art). Les huit autres n'ont pas de filtre
et restent en vectoriel. Après correction, la barre tombe sur la maquette :
2/3/6/9 à gauche contre 2/3/6/9, 49/32/17 à droite contre 49/33/18.

### Ce que le rythme change au combat

| verdict | l'équipe frappe | l'équipe encaisse |
|---|---|---|
| Perfect | ×1,5 | −50 % |
| Great | ×1,25 | −30 % |
| Good | ×1,1 | −15 % |
| Miss | ×1 | aucune réduction |

Valeurs données par l'auteur. Un Miss ne PUNIT pas : les deux tables valent 1, et
le combat se joue alors sur les seules stats. Le multiplicateur d'une séquence
est la **moyenne** de ses verdicts — quatre notes doivent valoir plus qu'une, et
rater la moitié d'un Eko doit se voir.

**Toutes les actions passent par la barre**, objets compris (choix de l'auteur) :
`sequence` existe désormais sur les Ekos, sur les objets et sur `basic_attack`.
Un soin bien joué rend donc davantage — et un soin lancé par un ENNEMI passe par
la table de défense, si bien que bien jouer l'en prive.

### Le rythme se joue AVANT tout mouvement

L'ordre d'une action est : pastille → **rythme** → approche → geste → effets →
retour.

**L'unité ne quitte pas son emplacement tant que la séquence n'est pas finie** :
le joueur a les yeux sur la barre, un personnage qui traverse le terrain au même
moment lui dispute son attention. Le déplacement ne part qu'une fois le dernier
verdict tombé.

Le geste, lui, vient après le rythme et non pendant, comme le Lot 6 l'avait
prévu : il ne boucle pas, le tenir le temps de trois notes figerait le
personnage bras levé. Le verdict restant affiché une demi-seconde, il se lit
encore au moment de l'impact — comme sur la maquette.

### Fondus, et un curseur sur celui qui joue

La barre **ne s'allume plus d'un coup** : la moitié colorée est un calque posé
par-dessus la moitié éteinte, dont seule l'opacité bouge (0,25 s à la montée,
0,3 s à la descente). Échanger la texture d'un sprite unique, comme au premier
jet, ne laissait aucune place à un fondu.

**Le fondu suit le CAMP, pas l'unité.** Deux alliés qui jouent l'un après
l'autre ne font pas clignoter la barre : elle reste allumée d'un bout à l'autre,
et ne bascule qu'au changement de camp — en fondu croisé, la moitié rouge
montant pendant que la jaune descend. Elle ne s'éteint qu'à la fin de l'assaut,
et disparaît APRÈS son fondu. Tracé sur un tour complet :

```
 0.23 -> 3.53   ALLIEE pleine     Iris
 3.79           ALLIEE pleine     Noah enchaine, aucune extinction
 7.81 -> 8.04   fondu             changement de camp
 8.04 -> 10.60  ENNEMIE pleine    premier cactoon
10.86           ENNEMIE pleine    deuxieme cactoon, aucune extinction
13.93 -> 14.21  fondu puis retrait
```

Pendant la séquence, un **curseur** — celui du worldmap, repris tel quel — se
pose au-dessus de l'unité qui joue, avec le même fondu. Il répond à un vrai
problème : le joueur a les yeux sur la barre, en bas, et l'unité ne s'est pas
encore déplacée ; plus rien ne dit qui agit.

**Il reprend la place exacte du curseur de CIBLAGE**, celui qui désigne une
cible pendant la préparation : `pieds + (9,703 79 ; −92,311 4)`, incliné de 33°.
Ce ne sont pas des valeurs choisies — elles ont été relevées en jeu, et vérifiées
constantes à la sixième décimale sur les trois emplacements d'ennemis. Là-bas
elles résultent de la composition du menu réduit (`FOCUS_PILL_OFFSET` puis
`CURSOR_FOCUS_OFFSET`, dans le repère incliné du menu) ; ici il n'y a pas de
pastille à accompagner, le curseur se pose donc directement au résultat.

Deux essais précédents sont tombés à côté et méritent d'être consignés. Se caler
sur le **sommet de la cellule** convient à Noah et au cactoon mais pas à Iris,
dont la planche monte jusqu'à la bouche de sa carabine — 14 px au-dessus de son
chapeau. Et **aucune règle tirée de la silhouette** ne s'en sort : une tête est
plus étroite qu'un corps, donc un seuil de largeur descend DANS le personnage
(mesuré : 51, 62 et 49 px au-dessus des pieds au lieu de 69, 66 et 67). La
bonne réponse n'était pas une heuristique mais une position DÉJÀ CALIBRÉE
ailleurs dans l'écran.

La position est fractionnaire, et c'est voulu : le curseur est tourné, donc déjà
rendu par le chemin lissé de `PixelScale` — l'arrondir le décalerait de son
jumeau du ciblage.

### Vérifié en jeu

Séquence complète jouée par injection de vraies touches, en visant le centre :

```
circle -> PERFECT (dx +3,2)    Iris, attaque de base
circle -> PERFECT (dx +2,9)
cross  -> PERFECT (dx +2,8)    Noah
cross  -> PERFECT (dx +2,8)
right  -> PERFECT (dx -2,9)    cactoon : dx negatif, les notes viennent de gauche
```

Effets mesurés : Noah encaisse 2 au lieu de 4 (−50 %), et le premier cactoon
tombe sous les coups majorés. Iris reste en `x = 365` — son emplacement —
pendant toute la séquence, et ne part qu'après. Pastille et pointe recalées au
pixel sur la maquette : corps en x 186..291 / y 187..201, pointe en 237..240
puis 238..239, identiques dans les deux.

### Les quatre verdicts, éprouvés

```
PERFECT   touche juste, dx +2,8      -> cactoon 30 -> 0 PV   (35 de degats)
GREAT     touche juste, dx +16,7     -> libelle jaune a gauche de l anneau
MISS      mauvaise touche dans la fenetre
MISS      aucune touche, la note depasse la fenetre
          les deux -> cactoon 30 -> 7 PV, soit les 23 de base sans bonus
```

Le multiplicateur retombe donc bien à 1 sur un raté — il ne punit pas. Et la
note DIRECTIONNELLE du cactoon sort à 270° : la flèche pointe vers la droite,
donc vers l'anneau qu'elle rejoint depuis la gauche, comme sur la maquette du
tour ennemi.

### Reste ouvert

- **Aucun son.** C'est le vrai manque du lot : le retour de timing est
  entièrement visuel, alors qu'une mécanique de rythme se joue d'abord à
  l'oreille. Le combat a déjà trois effets (`move`, `validation`, `error`) mais
  aucun ne convient à une note réussie ou ratée — il faut des sons dédiés.
- **La vitesse des notes** est un réglage, pas un relevé : à ajuster en jouant.
- **Les séquences sont provisoires**, comme le reste du contenu.
- Le verdict **GREAT** n'apparaît sur aucune maquette : sa couleur (jaune) est
  choisie, les trois autres sont relevées.
- **Toute touche compte dès que les notes défilent.** Mauvaise touche, ou bonne
  touche hors de la dernière fenêtre : c'est un raté dans les deux cas. Un
  premier jet ignorait les touches trop précoces — pour ne pas « consommer une
  note qui n'est pas encore là » — mais ça rendait le martèlement gratuit et,
  surtout, ça donnait au joueur une manette morte pendant la moitié de la
  séquence sans rien lui dire. Vérifié :

```
touche a dx=+237  ->  MISS      la note vient d entrer, l appui compte quand meme
touche a dx= +30  ->  GOOD
touche a dx=  +6  ->  PERFECT
```

---

## 5 nonies. Résultat du Lot 8 — la jauge de synergie

### Ce qui la remplit

**La qualité du rythme**, décidé par l'auteur : un Perfect vaut 0,25 de niveau,
un Great 0,15, un Good 0,07, un Miss rien. Il faut donc quatre notes parfaites
pour gagner un niveau, une douzaine de Good. La synergie récompense ainsi la
maîtrise de la mécanique centrale du jeu, et se construit **autant en attaque
qu'en défense** — la barre tourne dans les deux sens.

Chaque note compte séparément : une séquence de quatre notes vaut quatre fois
une note seule, ce qui récompense les Ekos longs. Les valeurs elles-mêmes ne sont
PAS relevées — `synergy.jpg` ne montre que les états de la jauge, pas ce qui la
remplit. C'est un réglage de rythme de progression, à sentir en jouant.

La charge appartient à l'ÉQUIPE, pas à une unité : c'est ce qui la distingue des
PV et des PA, et c'est le sens du mot. D'où `SynergyMeter`, à part de
`BattleUnit`.

### Les couleurs, relevées sur `synergy.jpg`

La spirale change de teinte avec le niveau. L'asset `synergie_full` a été recalé
sur la troisième vignette — celle qui porte « 1 » — et les extrémités du dégradé
lues aux mêmes pixels sur les autres :

| niveau | dégradé de la spirale | liseré du chiffre |
|---|---|---|
| 0 | #FD761C → #EFFE00 | #EEF801 |
| 1 | #FD761C → #EFFE00 | #EEF801 |
| 2 | #FF321D → #FFB301 | #F8D070 |
| 3 | #CE2CFB → #FE8EE0 | #F8B8E8 |

Les niveaux 0 et 1 partagent le dégradé de l'asset : c'est bien ce que montre la
référence, où la vignette partielle et la vignette « 1 » sont du même orangé.

La recoloration garde l'ALPHA de chaque pixel — donc tout l'anticrénelage — et ne
reporte que la teinte, d'après la position du pixel dans le dégradé d'origine.
Celle-ci se lit sur le canal VERT, seul à croître franchement et sans ambiguïté
d'un bout à l'autre de l'asset (0x76 → 0xFE).

**MAX_LEVEL passe de 4 à 3** : la référence montre une pastille qui va de « 0 »
à « 3 », soit bien quatre niveaux.

**La plaque du chiffre** (`round_synergie`) était listée depuis le Lot 1 sans
servir : la référence montre le chiffre posé sur un fond, pas flottant sur la
spirale. Elle est maintenant affichée.

### Le gain s'anime comme la jauge de PV

Même grammaire que l'encaissement d'un coup : **la part gagnée s'allume d'abord
en BLANC**, puis la couleur du niveau la recouvre. Là-bas l'aperçu montre ce
qu'on va perdre, ici ce qu'on vient de gagner — dans les deux cas c'est la part
de jauge en jeu qui se signale avant de se résoudre. Les temps sont repris de
`HpBar` (0,18 s d'aperçu, 0,35 s de montée) : c'est la même animation, elle doit
avoir le même tempo d'un élément à l'autre.

Un gain qui fait **monter d'un niveau** se joue en deux temps : la spirale finit
de se remplir dans la couleur du niveau qu'elle quitte, puis repart de zéro dans
celle du nouveau. C'est le seul découpage qui rende la couleur lisible — la faire
changer en cours de montée effacerait l'information.

```
gain simple 0,20 -> 0,75
  t=0.05  apercu 0.625   couleur 0.167   le blanc devance
  t=0.35  apercu 0.625   couleur 0.391
  t=0.60  apercu 0.625   couleur 0.625   rattrape

passage de niveau 0,80 -> niveau 1 a 0,30
  t=0.05  apercu 0.833   couleur 0.667   niveau 0
  t=0.35  apercu 0.833   couleur 0.750   niveau 0
  t=0.60  apercu 0.250   couleur 0.055   niveau 1, la spirale repart
```

Deux pièges rencontrés là-dessus, tous deux invisibles à la lecture du code :

- **L'aperçu doit être posé AVANT l'attente**, pas dans le premier pas de la
  file : sinon il apparaît en même temps que la couleur part, et le blanc ne se
  voit jamais seul.
- **`tween_method` fige ses bornes à la CONSTRUCTION.** Lire `_shown` dans le
  dernier pas donnait l'ancienne charge, pas zéro : après un passage de niveau la
  spirale redescendait au lieu de monter. Il faut suivre la valeur de départ
  d'un pas à l'autre dans une variable locale.

### Ce qui reste à l'auteur

- **La compétence spéciale** n'est toujours pas définie. Le niveau est exposé
  (`SynergyMeter.level`, `is_ready()`) pour qu'elle s'y branche sans que rien
  d'autre bouge, et `spend()` est déjà écrit — l'auteur a tranché ce point-là :
  l'utiliser VIDE la jauge entièrement, ce qui met le joueur devant un vrai
  arbitrage entre frapper au niveau 1 ou attendre le niveau 3. Rien ne l'appelle
  encore.
- **Le liseré du chiffre** est approché : `synergy.jpg` étant un JPEG, il ne
  permet pas de séparer proprement le corps du chiffre de son liseré. Les trois
  teintes ci-dessus sont les couleurs claires dominantes de chaque pastille.

### Vérifié en jeu

Remplissage réel par le rythme, toutes notes jouées en Perfect :

```
 0.01  niveau 0, 0.00
 2.37  niveau 0, 0.50    Iris, 2 notes
 6.17  niveau 1, 0.00    Noah, 2 notes -> le niveau monte
 9.66  niveau 1, 0.25    un cactoon, 1 note
12.71  niveau 1, 0.50    l autre cactoon
```

---

## 5 decies. Résultat du Lot 9 — fin de combat

### Victoire

Tous les ennemis à terre : le HUD, les menus, la légende, la barre de rythme et
la pastille d'action disparaissent — ils proposent des choix qu'on ne peut plus
faire — et chaque allié joue sa célébration. **Un allié tombé est ranimé à
1 PV** et revient en fondu de 0,4 s : son sprite est à alpha 0, hérité de
`BattleAssault._bury_the_dead`.

**Deux planches par personnage, pas une.** `win_before` est un geste qui se
termine (Noah saute et retombe mains sur les hanches, 17 frames ; Iris fête avec
sa mascotte qui s'en va, 34 frames), `win` est une respiration qui ne se termine
pas (4 et 6 frames, en boucle). Les fondre en une seule obligerait soit à figer
le personnage sur sa dernière image, soit à lui faire rejouer son saut sans fin.

**La séquence est PAR PERSONNAGE**, pas globale : les deux célébrations n'ont
pas la même longueur (1,13 s contre 2,27 s à 15 fps), les attendre ensemble
ferait patienter le premier arrivé sur sa dernière image. Mesuré en jeu : Noah
bascule sur `win` à t≈4,8 s, Iris à t≈5,6 s.

Une validation (`battle_confirm`) rend la main au worldmap. Le combat ne sait
pas ce qui l'a ouvert : il émet `exit_requested`, et c'est `BattleLauncher` qui
y branche son `close()`. Lancée seule (F6), la scène reste simplement en place.

### Grilles et ancrages des planches de victoire

| Planche | Grille | Cellule | Frames | `anchor` |
|---|---|---|---|---|
| `noah_win_before` | 3×6 | 53×89 | 17 / 18 | (19, 89) |
| `noah_win` | 3×2 | 52×70 | 4 / 6 | (18, 70) |
| `iris_win_before` | 3×12 | 339×103 | 34 / 36 | (273, 94) |
| `iris_win` | 3×2 | 46×68 | 6 / 6 | (14, 68) |

Les grilles sont relevées sur les gouttières transparentes, pas devinées : tous
les bords de cellule tombent dans une bande d'alpha nul.

**Les ancres viennent de l'ellipse d'ombre**, comme toutes les autres
(cf. `CLAUDE.md`). Le décalage ombre → ancre est celui d'`idle` : (−7,5 / +13,5)
pour Noah, vérifié identique sur `atkeff` et `atk`, et (−8,5 / +12) pour Iris.
La méthode a été validée AVANT de s'en servir, en recalculant les quatre ancres
déjà dans le fichier — elle les redonne au pixel, à l'exception connue de
`noah/standby`, que l'auteur du champ avait délibérément remonté d'un pixel.

**Deux pièges sur ces planches précises :**

1. **La cellule d'`iris_win_before` fait 339 px de large** pour un personnage
   qui en occupe 70. Ce n'est pas une erreur d'export : la mascotte traverse
   tout le cadre aux frames 24-26.
2. **Son ancre se relève sur les frames 31-33, pas sur la frame 0.** Au début de
   la planche, l'ombre d'Iris et celle de la mascotte fusionnent en une seule
   boîte, dont le centre est décalé de 17 px. Les dernières frames donnent une
   ombre solitaire de 36×12 px, au pixel identique à celle de la frame 0 de
   `win` — c'est ce qui garantit que la transition entre les deux planches ne
   saute pas. Écart résiduel assumé : Iris démarre 3 px à droite de son
   emplacement et s'y recale en marchant.

### Défaite

Voile noir plein écran et « Game Over » en blanc, monté DANS le `Stage` et après
tout le reste : un CanvasItem se dessine dans l'ordre de l'arbre, le voile
recouvre donc décor, combattants et bandes noires sans toucher au `z_index` de
qui que ce soit, et le fond capturé — posé hors du `Stage` — passe dessous pour
la même raison. Mesuré sur la capture : **99,50 % de noir pur, 0,50 % de blanc
pur, zéro pixel d'une autre couleur**. Le libellé est le seul texte de combat
SANS contour ni ombre : les deux servent à détacher un texte d'un décor chargé,
et il n'y a ici que du noir.

### État `FINISHED`, et pourquoi il vient en premier

`_finish_battle()` pose l'état AVANT de masquer quoi que ce soit : `_hide_interface`
et la célébration passent tous deux par des rafraîchissements qui lisent `_state`
pour décider s'ils ont le droit de reposer une planche ou une teinte. Les appeler
avant le basculement leur ferait écraser ce qu'on vient de mettre en place — c'est
exactement l'incident `_close_sublist` du Lot 4, et `_refresh_ally_poses` /
`_refresh_unit_visuals` s'abstiennent désormais sur `FINISHED` comme sur `ASSAULT`.

### Ce que le Lot 9 n'a pas

- **L'écran de récompense** (argent, expérience) : toujours sans maquette.
- **Les planches `dying` et `dead`** existent dans `_assets` et ne sont pas
  branchées : une unité tombée disparaît encore en fondu.
- **Le déclenchement d'un combat en jeu** (rencontre aléatoire) : la touche Z
  reste l'entrée de test.
- **La suite du « Game Over »** : l'écran s'affiche et ne mène nulle part, la
  validation n'y répond pas. C'est conforme à ce qui a été demandé, mais il faut
  trancher — recommencer le combat ? revenir au worldmap ? un écran-titre ?

---

## 5 undecies. Résultat du Lot 10 — la page « Combat »

Une entrée « Combat » dans la barre de menus, trois sections (Unités / Ekos /
Objets) dans une seule modale. Côté serveur, trois `metaRoutes` de plus et deux
routes de service ; côté client, `public/battle.js`.

### Ce que la page édite

| Section | Champs |
|---|---|
| Unités | les six statistiques, l'attaque de base, les Ekos connus (cases à cocher sur le catalogue réel), et pour un ennemi le bloc `behaviour` complet |
| Ekos | coût en PA, ciblage, puissance, soin, nature des dégâts, planche, séquence, sons |
| Objets | les mêmes, sans coût en PA |

### Rien ne se saisit à la main

C'est le principe de toute la page : **chaque champ dont le vocabulaire est
fermé est une liste déroulante**, jamais une saisie libre. Un mode de ciblage,
une nature de dégâts, une note de rythme, un moment de son, un comportement
ennemi, la cible d'un `focus`, un identifiant d'Eko connu, un fichier audio —
tout vient d'une liste. La raison est toujours la même : une faute de frappe
dans ces champs ne produit pas une erreur mais un SILENCE (un son qui ne part
jamais, une note qui ne s'affiche pas, un ennemi qui frappe au hasard), et ce
silence ne se découvre qu'en lançant ce combat précis.

**Les vocabulaires sont LUS DANS LE CODE GODOT**, pas recopiés : `/api/battle/
vocabulary` extrait `SOUND_MOMENTS` de `BattleAssault.gd` et les clés de
`NOTE_ACTIONS` de `RhythmBar.gd`. Deux listes qui disent la même chose finissent
par se contredire (cf. l'incident `type`/`damage_type` au §5 septies), et la
liste des moments est précisément celle où la divergence coûte le plus cher. Un
repli littéral est prévu pour chacune : si un refactor renomme la constante, la
page continue de fonctionner sur la dernière valeur connue plutôt que de tomber
en panne muette, et le champ `parsed` de la réponse dit ce qui a réellement été
lu. Les vocabulaires SANS déclaration unique côté moteur (ciblage, nature,
comportements — éparpillés dans des `match`) restent écrits côté serveur, et
c'est dit dans le code.

### Les sons, et les moments hors d'atteinte

Une liste répétable : par entrée un moment, et un ou plusieurs fichiers —
plusieurs fichiers étant des VARIANTES tirées au hasard, ce que le bouton dit en
toutes lettres (« + variante ») pour qu'on ne le confonde pas avec deux sons
joués ensemble.

**La page signale les moments que l'action n'atteindra jamais** : `approach` et
`return` sur une action qui soigne (elle ne traverse pas le terrain), `rhythm`
sur une action sans séquence. Le moteur, lui, se contente de ne rien jouer.
Vérifié en jeu : un son posé sur `return` ne dit rien tant que l'attaque de Noah
est offensive, et l'avertissement apparaît à la seconde où son champ « Soin »
passe à 5.

### Ce qui reste en lecture seule, délibérément

- **Les libellés.** Les noms viennent de `Localization` : la page affiche le
  texte résolu et l'id, avec un renvoi vers la page « Textes ». Une entrée sans
  texte est signalée — elle n'aurait pas de nom en jeu.
- **Les planches d'animation.** Leur grille, leur fourchette de frames et leur
  ancrage se relèvent au pixel sur l'image (cf. `CLAUDE.md`), ce qu'un
  formulaire web ne sait pas faire. Proposer de les saisir inviterait à poser
  des valeurs plausibles et fausses. Seul le CHOIX d'une planche existante est
  offert, par son nom.

### Deux détails qui auraient sali les fichiers

1. **Un champ numérique facultatif retire sa clé quand il retombe à 0**, au lieu
   d'écrire `heal: 0` là où le catalogue n'avait rien. Le moteur lit ces champs
   avec un défaut, donc absent et 0 disent la même chose — mais les écrire
   ferait gonfler chaque entrée à la première visite de la page. À ne surtout
   pas appliquer à `guard_below`, dont le défaut est 0,35 : y effacer un 0
   changerait « ne se garde jamais » en « se garde sous 35 % ».
2. **Le serveur écrit un saut de ligne final.** `JSON.stringify` n'en met pas,
   et ces fichiers s'éditent aussi à la main : sans lui, chaque sauvegarde
   produisait un diff git parasite sur un fichier par ailleurs inchangé. Corrigé
   pour les cinq catalogues, pas seulement ceux du combat.

Vérifié en jeu : un aller-retour complet par l'interface (puissance 6 → 7 → 6)
laisse `Battle/units.json` **identique au byte près** — `git status` vide.

### Ce que la page ne fait pas

- Les **neuf Ekos `test_N`** sont toujours là. Ils sont du décor de test (faire
  défiler une liste de quinze rangées) et c'est à l'auteur de dire quand ils
  disparaissent — la page permet maintenant de les supprimer d'un clic.
- **Pas de verrou optimiste** (`_rev`) sur ces trois catalogues, comme pour
  `texts`/`tiles`/`props` : mono-utilisateur. Le mécanisme des maps est
  rétrofitable si l'édition concurrente devient un vrai problème.

---

## 5 duodecies. Cadrage de la préparation

Ouvrir une liste rapproche la vue sur celui qui agit ; choisir une cible la
déplace sur la cible. Annuler pour revenir au menu racine remet tout à plat.

**Ce n'est toujours pas une caméra.** Une Camera2D n'agit pas sur un CanvasLayer
(cf. `CanvasZoom`), et surtout elle emporterait le HUD, le menu et les bandes
noires. Comme pour le glissement d'assaut, seul le nœud `_field` se transforme —
zoom 1,25 plus translation — et `_shift_field` comme `_focus_field` passent
désormais par la même fonction.

| Moment | Cadrage |
|---|---|
| Menu racine | à plat |
| Liste d'Ekos, liste d'objets | ×1,25 sur celui qui agit |
| Ciblage d'un ennemi | ×1,25 sur la cible, suit le curseur |
| Ciblage d'un allié | **aucun mouvement** — la vue reste sur celui qui agit |
| « Back » vers la liste | retour sur celui qui agit |
| « Back » vers le menu racine | remise à plat |

**« Attack » n'a pas de liste où cadrer d'abord** : sa séquence commence
directement sur la cible, il n'existe aucun autre moment où la poser. Les trois
commandes qui visent partagent donc le même `_frame_target`, et c'est le mode de
ciblage — pas la commande — qui décide si la vue bouge.

On cadre sur la planche RÉELLEMENT montée à cet instant : un allié qui ouvre sa
liste d'Ekos est déjà passé sur sa pose de visée, celui qui ouvre son sac est
resté au repos, et les deux planches n'ont pas le même centre. C'est ce qui
explique que le cadrage du lanceur ne donne pas la même translation dans les
deux cas (−153,75 contre −144,375 sur Noah).

### On cadre sur le CENTRE DU DESSIN, pas sur la cellule ni sur les pieds

Le point visé est le centre des pixels réellement peints
(`UnitSprite.art_centre`), relevé une fois par planche et mis en cache.

Ni `position`, qui est le point au SOL — viser dessus mettrait la moitié de
l'écran sous la plateforme. Ni le centre de la CELLULE : mesuré, l'écart est
nul sur `idle` et `standby` (moins d'un pixel) mais vaut **11 px** sur la pose
de visée de Noah, dont la planche réserve la place de l'arc de lame et n'occupe
donc pas toute sa cellule. Un ciblage de groupe, lui, ne rend qu'un barycentre
de pieds : il est relevé de `FOCUS_BODY_RISE` faute de sprite unique à mesurer.

**L'unité va au centre de l'écran (240, 135), dans les deux cas.** Une première
version la poussait dans la seule bande restée libre (370, 120), la liste
d'Ekos occupant toute la moitié gauche et le cadre de description tout le bas.
L'auteur a tranché pour un cadrage franc : la liste passe par-dessus le lanceur,
c'est assumé.

### Le fond capturé ne suit PAS le cadrage

Son débord (`BACKGROUND_OVERSCAN`) a été calculé pour les 60 px du glissement
d'assaut, pas pour les 250 qu'un cadrage peut demander. Mesuré : à ×1,25 et
111 px de translation, son bord gauche entre dans l'image et laisse une bande
noire sur un tiers de l'écran. L'élargir assez le rendrait deux fois plus
agrandi **en permanence**, donc plus flou au repos — un dégât durable pour un
mouvement passager. Le laisser immobile se lit d'ailleurs comme du parallaxe.
C'est `_shift_field` qui le fait suivre, lui, et il reste dans son budget.

### La pastille d'action doit être reposée à chaque image

Elle se place à partir de la transformation du terrain. Calculée une seule fois
au changement de cible, elle lisait une transformation que le tween était
justement en train de changer : elle restait accrochée au point de départ et
atterrissait sur le HUD en visant l'ennemi du fond. Un `_process` la repose tant
que le cadrage s'anime.

Deuxième conséquence du même changement : les pieds d'une cible sont en espace
TERRAIN alors que la liste se place en espace Stage. Tant que le terrain restait
à l'identité pendant la préparation les deux se confondaient — d'où un
`_field.transform *` ajouté dans `_follow_target`. Le décalage de la pastille,
lui, s'applique APRÈS la transformation : il se mesure à l'écran et n'a aucune
raison de grossir avec le zoom.

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
  INJURY_CONVERSION_BONUS`, aujourd'hui 0 : simple addition). L'auteur a
  confirmé la forme, pas le nombre.
- **L'équilibrage** : `basic_attack.power` de chaque unité (6 / 5 / 6) est
  provisoire, choisi pour qu'un combat se résolve en quelques tours.
- **La répartition direct / blessure** : `damage_type` existe sur chaque Eko et
  chaque objet, mais seul `tempeste` est en `injury`, pour que le système soit
  exerçable.
- **Le comportement des ennemis** : ils se contentent de frapper au hasard.
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

## 7 bis. Lot 10 — page « Combat » de MapEditor

Les trois catalogues du combat (`Battle/units.json`, `ekos.json`, `items.json`)
n'ont aujourd'hui **aucun éditeur** : ils se modifient à la main. Ils suivent
pourtant exactement le modèle que l'outil web sait déjà servir — un objet
racine, un dictionnaire nommé, des ids `Localization` pour tout libellé.

**Une page dédiée, pas une de plus par fichier.** Les trois catalogues se
renvoient l'un à l'autre — une unité connaît des Ekos, un comportement ennemi
nomme une unité — et les éditer dans trois onglets séparés obligerait à jongler.
Une page « Combat » à trois sections (Unités / Ekos / Objets) garde ces
renvois sous les yeux, et permet de proposer les listes déroulantes qui vont
avec (choisir un Eko dans le catalogue, choisir la cible d'un `focus` parmi les
alliés) plutôt que de laisser saisir un id à la main.

Ce qu'elle doit couvrir :

- **Unités** — stats (PV, PA, force, défense, agilité, chance), `basic_attack`,
  liste des Ekos connus, et pour un ennemi le bloc `behaviour` (`kind`, `focus`,
  `guard_below`, `eko_chance`) décrit au §5 septies.
- **Ekos** — coût en PA, mode de ciblage, puissance ou soin, `damage_type`,
  `type` d'icône, séquence de rythme (Lot 7), et les **sons** (ci-dessous).
- **Objets** — mêmes champs, sans coût en PA.

**Les sons d'une action** (`sounds`, cf. §1.4) sont le morceau le moins trivial
de cette page, parce que c'est une liste d'entrées et pas un champ simple. Ce
qu'il faut :

- une **liste répétable** : ajouter / retirer / réordonner des entrées ;
- par entrée, `at` en **liste déroulante** — les six moments sont un vocabulaire
  fermé (`SOUND_MOMENTS`), jamais une saisie libre : une faute de frappe donne
  un son qui ne part jamais, et l'avertissement runtime n'arrive que le jour où
  quelqu'un lance ce combat ;
- par entrée, **un ou plusieurs fichiers**. Un chemin `res://` se saisit mal à
  la main : il faut lister ce que contient `Audio/Battle/`, comme la page
  « Tuiles » liste déjà son atlas. Plusieurs fichiers sur une entrée = des
  variantes tirées au hasard, à présenter comme telles et non comme une
  seconde liste de sons ;
- **signaler les moments hors d'atteinte** : un `approach` ou un `return` sur
  une action de soin, un `rhythm` sur une action sans séquence. L'éditeur a
  toute l'information pour le dire, le moteur se contente de ne rien jouer.

Cette page est aussi l'endroit où poser le reste de `_assets/battle/_voices/` —
une trentaine de répliques dont seule `noah_att1` est aujourd'hui branchée.

Côté serveur, rien de neuf à inventer : `metaRoutes` sert déjà ce genre de
fichier pour `tiles` et `props`, il suffit de l'appeler trois fois de plus.
Côté client, le gabarit `.crud-modal` de `tiles.js` / `props.js` / `systems.js` /
`texts.js` s'applique tel quel.

Deux points à ne pas perdre de vue :

- **Aucun libellé ne vit dans ces fichiers.** Les noms et descriptions sont des
  ids `Localization` : la page « Combat » doit donc renvoyer vers la page
  « Textes » pour les éditer, ou afficher le texte résolu en lecture seule —
  surtout pas ouvrir une deuxième porte d'écriture sur le même texte.
- **Les entrées `test_N` d'`ekos.json` sont du décor de test** (défilement d'une
  liste de 15 rangées) et doivent disparaître avant que la page serve
  réellement.

---

## 8. Ce que ce plan ne fait pas

- Aucune modification du worldmap existant, hors masquage du HUD pendant la
  capture de fond.
- Aucun système de dialogue (la catégorie `dialogue` du catalogue de textes
  reste vide, comme décidé au chantier localisation).
- Aucune page MapEditor nouvelle avant le Lot 10.
