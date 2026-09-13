extends CanvasLayer

## Écran de combat — phase de préparation. Le rendu est complet (Lot 1), le
## menu racine est navigable (Lot 2), « Attack » ouvre le choix d'une cible
## (Lot 3) et « Eko » / « Items » ouvrent leur sous-liste avec coût en PA,
## description et ciblage simple ou de groupe (Lot 4) ; valider une cible ne
## met encore aucune action en file, c'est la boucle de préparation (Lot 5)
## qui la consommera.
##
## RÉSOLUTION. Les assets de combat sont dessinés pour un écran de 480×270,
## soit exactement 1920/4 (démontré par dark_lines.png qui fait 480 de large,
## par les deux moitiés de barre de rythme en 239×2, et confirmé par le mockup
## fourni en 480×270 natif). Plutôt que de changer le stretch du projet — ce
## qui casserait le worldmap, dessiné à une autre échelle — toute la scène vit
## sous `Stage`, un Node2D à scale 4. Toutes les constantes ci-dessous sont
## donc en unités de design, et doivent rester ENTIÈRES : une position à
## virgule devient un demi-pixel flou une fois multipliée par 4.
##
## Les positions viennent d'un recalage automatique de chaque asset sur
## _assets/battle/mockup_preparation.png (erreur nulle sauf mention contraire,
## cf. docs/plan_systeme_combat.md §4). Ce ne sont pas des valeurs approchées :
## les modifier « à l'œil » ferait diverger l'écran du mockup.

const UnitSprite = preload("res://Scripts/Battle/Stage/UnitSprite.gd")
const UnitStatusPanel = preload("res://Scripts/Battle/UI/UnitStatusPanel.gd")
const SynergyGauge = preload("res://Scripts/Battle/UI/SynergyGauge.gd")
const CommandMenu = preload("res://Scripts/Battle/UI/CommandMenu.gd")
const TargetSelector = preload("res://Scripts/Battle/UI/TargetSelector.gd")
const DescriptionPanel = preload("res://Scripts/Battle/UI/DescriptionPanel.gd")
const BattleUnit = preload("res://Scripts/Battle/BattleUnit.gd")
const BattleAssault = preload("res://Scripts/Battle/BattleAssault.gd")
const RhythmBar = preload("res://Scripts/Battle/UI/RhythmBar.gd")
const SynergyMeter = preload("res://Scripts/Battle/SynergyMeter.gd")
const ActionBanner = preload("res://Scripts/Battle/UI/ActionBanner.gd")
const BattleData = preload("res://Scripts/Battle/BattleData.gd")
const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")
const CanvasZoom = preload("res://Scripts/UI/CanvasZoom.gd")
const SfxBank = preload("res://Scripts/Audio/SfxBank.gd")

const DARK_LINES := preload("res://Sprites/Battle/dark_lines.png")
const PLATFORM := preload("res://Sprites/Battle/platform_grass.png")
const MINI_CIRCLE := preload("res://UI/Battle/mini_btn_circle.svg")
const MINI_CROSS := preload("res://UI/Battle/mini_btn_cross.svg")

const SFX_MOVE := preload("res://Audio/move.wav")
const SFX_CONFIRM := preload("res://Audio/validation.ogg")
const SFX_CANCEL := preload("res://Audio/back.ogg")

## Bus de mixage. La musique et les voix sont séparées pour qu'un compresseur
## posé sur MUSIC et écouté depuis VOICE baisse le thème pendant une réplique
## (cf. Audio/default_bus_layout.tres). Mesuré sur les fichiers : le thème tient
## −15,5 dBFS RMS à 70 %, les voix −14 — 1,5 dB d'écart, où il en faut une
## dizaine pour qu'une phrase se détache. Monter les voix n'était pas possible,
## elles crêtent déjà à −3 dBFS ; c'est donc la musique qui s'efface, et
## seulement le temps de la réplique.
##
## Les sons de MENU restent sur Master : ils doivent pouvoir claquer par-dessus
## la musique sans la faire plonger à chaque mouvement de curseur.
## Les quatre moments de voix du menu racine, et celui du tour. Les valeurs
## appartiennent à BattleData.UNIT_SOUNDS ; les nommer ici évite de recopier des
## chaînes nues dans un `match` — une faute de frappe n'y lèverait rien, elle
## rendrait simplement le personnage muet.
const SOUND_TURN := "turn"
const SOUND_MENU_ATTACK := "menu_attack"
const SOUND_MENU_EKO := "menu_eko"
const SOUND_MENU_ITEMS := "menu_items"
const SOUND_MENU_GUARD := "menu_guard"
const SOUND_VICTORY := "victory"

const BUS_MUSIC := "Music"
const BUS_VOICE := "Voice"

const MUSIC_THEME := preload("res://Audio/battle_theme1.mp3")
## 70 % du volume nominal. `volume_linear` et pas `volume_db` : la consigne est
## une proportion, la convertir en −3,1 dB à la main la rendrait illisible.
const MUSIC_VOLUME := 0.70

const DESIGN_SIZE := Vector2i(480, 270)
const STAGE_SCALE := 4

## Bandes noires. La texture est la même pour les deux : celle du haut est
## retournée verticalement. Elle déborde volontairement de l'écran (en négatif
## en haut, sous 270 en bas) — seule la courbe compte, le reste est du noir
## plein.
const DARK_LINE_TOP := Vector2(0, -64)
const DARK_LINE_BOTTOM := Vector2(0, 224)

## DÉPLACEMENT DU TERRAIN PENDANT L'ASSAUT. Le décor, les combattants et le fond
## glissent vers le camp qui se fait attaquer, pendant que le HUD, la barre de
## rythme et les bandes noires restent en place. Mesuré entre les vignettes de
## `mockup_assault_allies.jpg` et `..._ennemies.jpg` : 60 px, purement
## horizontal (recalage du fond d'hexagones, écart moyen 0,3 ; confirmé par le
## bord de la plateforme, 54 → 114 d'un côté et 425 → 365 de l'autre).
##
## Le signe suit CELUI QUI AGIT : un allié frappe vers la gauche, le terrain part
## donc vers la DROITE — comme si la caméra se tournait vers les ennemis.
const FIELD_SHIFT := 60
const FIELD_SLIDE := 0.35

## CADRAGE DE PRÉPARATION. Choisir un Eko rapproche la vue sur celui qui le
## lance, puis sur ce qu'il vise. Même mécanique que le glissement d'assaut, et
## pour la même raison : ce n'est pas une Camera2D — une caméra n'agit pas sur un
## CanvasLayer (cf. CanvasZoom), et surtout elle emporterait le HUD, le menu et
## les bandes noires avec elle. Seul le TERRAIN se transforme.
const FOCUS_ZOOM := 1.25
const FOCUS_SLIDE := 0.3
## Point de l'écran où vient se poser l'unité regardée : le centre, dans les
## deux cas. La liste d'Ekos passe par-dessus le lanceur et le cadre de
## description mord sur le bas de l'écran — c'est assumé, l'auteur a tranché
## pour un cadrage franc plutôt que pour un compromis qui poussait l'allié dans
## la seule bande restée libre.
const FOCUS_CENTRE := Vector2(240, 135)
## Ce qu'on vise sur une unité : le centre de son DESSIN, pas son point au sol
## (qui mettrait la moitié de l'écran sous la plateforme) ni le centre de sa
## cellule (cf. UnitSprite.art_centre). Une cible désignée par le sélecteur, elle,
## n'est connue que par ses pieds : ce relèvement les remonte au buste.
const FOCUS_BODY_RISE := 40

## Débord du fond capturé. Il est cadré pile sur l'écran ; le déplacer
## découvrirait du noir sur un bord, d'où cet agrandissement qui couvre le
## décalage des deux côtés. Sur une photo floutée sous un voile sombre, le
## recadrage de 12 % ne se voit pas.
const BACKGROUND_OVERSCAN := (float(DESIGN_SIZE.x) + 2.0 * FIELD_SHIFT) / float(DESIGN_SIZE.x)

## PENDANT L'ASSAUT, les deux bandes se resserrent sur l'action.
##
## La basse REMONTE pour dégager la barre de rythme : 48 px, mesuré entre
## mockup_preparation.png et la première vignette de mockup_assault_allies, sur
## les 22 colonnes où aucun décor ne vient masquer le bord.
##
## La haute DESCEND. Ces 12 px-là ne sont PAS relevés : les deux maquettes
## posent la bande haute au même endroit, c'est une demande venue après elles.
## La valeur est donc un choix — le quart de la course de la bande basse, assez
## pour se voir (le noir passe de 21 à 33 px) sans atteindre les plaques d'état,
## qui commencent à y = 21 et se dessinent de toute façon PAR-DESSUS la bande
## (montées après elle, cf. _ready).
const DARK_LINE_ASSAULT_RISE := 48
const DARK_LINE_ASSAULT_DROP := 12
## Le temps que les bandes mettent à se déplacer. Rien ne le fixe sur les
## maquettes, qui ne montrent que les deux états ; assez court pour ne pas
## retarder l'assaut.
const DARK_LINE_SLIDE := 0.25

## Les deux moitiés se recouvrent de 2 px (41→240 et 239→438) : le
## chevauchement est voulu, il évite une couture visible au centre.
const PLATFORM_LEFT := Vector2(41, 130)
const PLATFORM_RIGHT := Vector2(239, 130)

## Emplacements de combat : point « pieds » de chaque unité (cf. UnitSprite).
## Décrire un emplacement par un point au sol plutôt que par le coin de la
## texture permet d'y placer n'importe quel personnage, quelle que soit la
## taille de sa cellule.
##
## Les emplacements ennemis sont rangés de DROITE À GAUCHE : le premier ennemi
## déclaré occupe celui qui est le plus près de l'équipe, le deuxième celui
## juste à sa gauche, et ainsi de suite. Les positions elles-mêmes sont celles
## de la maquette, seul leur ordre change — c'est lui qui décide sur qui le
## ciblage s'ouvre, et viser d'abord l'ennemi le plus proche est plus naturel
## que de partir du fond du terrain. Conséquence : l'ordre de la liste ne suit
## plus l'abscisse, et la navigation ←/→ trie par position (cf. TargetSelector).
const ENEMY_SLOTS: Array[Vector2i] = [
	Vector2i(195, 169), Vector2i(149, 150), Vector2i(103, 178)
]
const ALLY_SLOTS: Array[Vector2i] = [
	Vector2i(307, 170), Vector2i(365, 159)
]

const STATUS_PANEL_POS: Array[Vector2i] = [Vector2i(304, 21), Vector2i(372, 21)]
## Relevé sur le mockup : la piste (synergie_underlayer) est posée là, et
## l'icône éclair tombe alors pile à (450, 37) par simple centrage.
const SYNERGY_POS := Vector2(441, 41)
const SYNERGY_LABEL_POS := Vector2(446, 37)
const SYNERGY_LABEL_SIZE := 8
const SYNERGY_LABEL_COLOR := Color8(0xF0, 0x8C, 0x00)

## Inclinaison des groupes d'interface. Les panneaux ne sont pas posés à
## l'horizontale sur la maquette : ils suivent la courbure générale de l'écran.
## Angles mesurés dessus, pas choisis à l'œil —
##   menu : ajustement linéaire du bord supérieur de la pastille « Attack »
##          (−3,19°, résidu max 0,5 px sur 56 colonnes), confirmé par recalage
##          du 9-slice à travers les angles (optimum à −3°) ;
##   HUD  : bord supérieur des jauges de PV (−2,7° à −2,9°) ;
##   légende : analyse en composantes principales des glyphes, cohérente sur
##          « Cancel », « Confirm » et les deux réunis (−4,6° / −5,7° / −5,5°),
##          recoupée par la droite qui joint les deux pastilles de touche.
## ATTENTION : les positions relevées sur la maquette contiennent DÉJÀ cette
## inclinaison. Les constantes ci-dessous sont donc les positions « à plat »,
## obtenues en leur appliquant la rotation inverse — sans quoi l'inclinaison
## s'appliquerait deux fois. Le résultat est d'ailleurs une confirmation : à
## plat, les deux blocs du HUD tombent exactement sur la même ligne (y = 21),
## de même que les deux pastilles de touche de la légende (y = 230).
## Chaque groupe pivote autour de son premier élément (cf. _tilted_group).
const MENU_TILT_DEG := -3.0
const MENU_PIVOT := Vector2(310, 196)

## LE MENU SUIT L'ALLIÉ DONT C'EST LE TOUR. Les positions du menu (X_NORMAL,
## Y_FIRST… dans CommandMenu) sont celles du PREMIER emplacement allié, relevées
## sur mockup_preparation.png ; pour les suivants, c'est le groupe incliné
## entier qui est translaté, inclinaison et géométrie inchangées.
##
## Le décalage du second emplacement est relevé sur la quatrième vignette de
## mockup_preparation_select_items.png (le tour d'Iris) : recalage de la
## pastille « Guard », identique dans les deux maquettes, minimum net à
## (51 ; −11) — résidu 6,0 contre 12,9 aux voisins immédiats.
##
## Ce n'est PAS la translation des emplacements de combat, qui vaut (58 ; −11) :
## l'auteur a rapproché le menu de 7 px. D'où une table relevée plutôt qu'un
## calcul à partir d'ALLY_SLOTS — avec, pour un emplacement qui n'y figurerait
## pas encore, ce même écart d'emplacements comme repli raisonnable.
const MENU_SLOT_OFFSET: Array[Vector2i] = [Vector2i(0, 0), Vector2i(51, -11)]
const HUD_TILT_DEG := -4.2
const HUD_PIVOT := Vector2(304, 21)
const LEGEND_TILT_DEG := -5.5
const LEGEND_PIVOT := Vector2(333, 232)

## Légende. Le groupe « cercle » est aligné à DROITE, pas posé à une abscisse
## fixe : sur les maquettes le libellé se termine toujours au même endroit,
## qu'il dise « Cancel » (40 px) ou « Back » (27 px), et c'est l'icône qui
## recule. LEGEND_CANCEL_RIGHT est ce bord droit commun — il redonne bien
## l'abscisse 333 relevée au Lot 1 pour « Cancel ».
const LEGEND_CANCEL_RIGHT := 393
const LEGEND_ICON_Y := 232
const LEGEND_CONFIRM_ICON := Vector2(401, 232)
const LEGEND_TEXT_OFFSET := Vector2(19, -1)
const LEGEND_TEXT_SIZE := 15

## Les quatre entrées sont nommées : le code doit reconnaître chaque id, trois
## pour ouvrir un écran et « Guard » pour retenir l'action sans rien ouvrir.
const MENU_ATTACK := "battle.menu.attack"
const MENU_EKO := "battle.menu.eko"
const MENU_ITEMS := "battle.menu.items"
const MENU_GUARD := "battle.menu.guard"
const MENU_ENTRIES: PackedStringArray = [
	MENU_ATTACK, MENU_EKO, MENU_ITEMS, MENU_GUARD,
]

## Objets portés par l'équipe : id → quantité, dans l'ordre d'affichage.
## PROVISOIRE, en attendant un véritable inventaire de partie. Un objet à zéro
## reste dans la liste — la maquette en montre un — mais ne peut pas être
## utilisé.
## Quantités choisies pour le test : un nombre à deux chiffres, un à un
## chiffre et un zéro, de quoi vérifier l'alignement à droite et le refus.
const DEFAULT_INVENTORY := {
	"potion": 13,
	"grand_baume": 10,
	"bombe": 2,
	"eclat": 0,
}

## Coin haut-gauche du cadre « INFO », relevé sur
## mockup_preparation_select_eko.jpg.
const DESCRIPTION_POS := Vector2(270, 145)

## Secousse d'impact. Amplitude en unités de design — deux pixels, « léger »
## comme demandé : à l'écran ça fait huit, assez pour marquer le coup sans
## rendre le HUD illisible.
##
## C'est le STAGE qui bouge, pas le calque : celui-ci appartient déjà à
## CanvasZoom, qui écrit son `offset` pour zoomer autour du curseur (deux
## systèmes sur la même propriété se marcheraient dessus). Conséquence assumée :
## le fond capturé du worldmap, qui vit HORS du Stage (cf. §1.2 du plan), ne
## tremble pas — à cette amplitude, c'est invisible.
const SHAKE_AMPLITUDE := 2.0
const SHAKE_DURATION := 0.25
## Nombre d'allers-retours sur la durée. Une oscillation déterministe plutôt
## qu'un tirage aléatoire : deux captures de la même frame doivent donner la
## même image, sans quoi rien n'est vérifiable.
const SHAKE_CYCLES := 3.0

## Opacité des combattants qu'on ne regarde pas. L'allié dont c'est le tour y
## échappe toujours ; pour les autres, cela dépend de l'écran :
##   - dans une liste d'actions, TOUT LE MONDE s'efface — elle descend jusqu'à
##     sept rangées et passe alors devant le terrain ;
##   - pendant le ciblage, seul le camp VISÉ garde son opacité, l'autre
##     s'efface : en visant un ennemi, les alliés passent à 30 %.
const INACTIVE_UNIT_ALPHA := 0.3

## Assombrissement du sprite d'un allié dont l'action est retenue. OPAQUE, sans
## alpha : le personnage ne devient pas translucide, il passe à l'ombre — c'est
## la demande de l'auteur, et c'est aussi ce que fait la maquette, où le sprite
## assombri reste plein.
##
## Ajusté par moindres carrés sur les 908 pixels opaques de la planche
## `standby` de Noah contre la quatrième vignette de
## mockup_preparation_select_items.png : écart moyen 8,7 sur 255, soit 3,4 %.
## Cette même mesure est ce qui a confirmé que la maquette utilise DÉJÀ la
## planche `standby` pour l'allié qui a joué (résidu 8,7 contre 45 avec `idle`).
const CONFIRMED_SPRITE_MODULATE := Color(0.565, 0.337, 0.308)

## Planches d'un allié selon où en est son tour, cf. _ally_animation().
const ANIM_IDLE := "idle"
## Pose de visée, tenue FIGÉE pendant qu'il choisit la cible d'une attaque ou
## d'un Eko (cf. le `frames: 1` de son bloc dans units.json).
const ANIM_AIMING := "atkeff"
## Pose d'attente, une fois son action retenue.
const ANIM_STANDBY := "standby"

## VICTOIRE. La célébration se joue UNE fois, puis la pose est tenue en boucle.
## Deux planches et pas une : `win_before` est un geste qui se termine, `win`
## une respiration qui ne se termine pas — les mélanger obligerait à figer le
## personnage sur la dernière image ou à lui faire rejouer son saut sans fin.
const ANIM_WIN_BEFORE := "win_before"
const ANIM_WIN := "win"

## Un allié tombé est RANIMÉ pour fêter la victoire : il est mort pendant le
## combat, pas après. 1 PV — de quoi être debout, pas de quoi être soigné
## gratuitement.
const REVIVE_HP := 1
## Son sprite est à alpha 0 (cf. BattleAssault._bury_the_dead) : il revient en
## fondu plutôt que d'apparaître d'un coup au milieu des autres.
const REVIVE_FADE := 0.4

## ÉCRAN DE DÉFAITE : voile noir plein écran et « Game Over » en blanc.
const GAME_OVER_SIZE := 24
## Ligne de base du libellé, en unités de design. Un peu au-dessus du milieu
## exact (135) : un texte centré optiquement se pose plus haut que le centre
## géométrique.
const GAME_OVER_Y := 124

## Libellés de la touche « cercle » de la légende : « Back » tant qu'on peut
## revenir en arrière dans le choix d'une action, « Cancel » au menu racine.
const PROMPT_BACK := "battle.prompt.back"
const PROMPT_CANCEL := "battle.prompt.cancel"

## Position de la pastille de l'action retenue pendant le ciblage, en décalage
## depuis le point « pieds » de la cible. Réglée par recalage du rendu sur la
## deuxième vignette de mockup_preparation_select_attack.png, la cible y étant
## l'ennemi de l'emplacement 2 (pieds en 195, 169).
##
## Ce décalage est en coordonnées d'ÉCRAN ; le menu étant incliné, il faut le
## repasser dans son repère (cf. _menu_local).
const FOCUS_PILL_OFFSET := Vector2(23, -107)
## Ce dont la pastille monte EN PLUS sur un ciblage de groupe. Elle se pose
## alors au barycentre des cibles, c'est-à-dire pile sur le curseur de celle du
## milieu — elle masquerait justement ce que le ciblage de groupe vient de
## montrer. Relevé à l'écran : 14 px — une hauteur de pastille — suffisent à la
## poser à côté du curseur du milieu plutôt que dessus, sans aller cogner le HUD.
const GROUP_PILL_RISE := 14

## Composition par défaut, utilisée quand la scène est lancée seule (F6) sans
## passer par setup(). Elle reproduit le mockup.
const DEFAULT_ENEMIES: PackedStringArray = ["cactoon", "cactoon", "cactoon"]
const DEFAULT_ALLIES: PackedStringArray = ["noah", "iris"]

@onready var background: Sprite2D = $Background
@onready var background_dim: ColorRect = $BackgroundDim
@onready var stage: Node2D = $Stage

## Qui a la main sur les entrées. Les listes restent montées derrière l'état
## courant — il faut pouvoir y revenir sur « Back », et la pastille de l'action
## retenue reste affichée à côté de la cible : c'est le drapeau `active` de
## chaque composant, arbitré ici, qui décide lequel écoute.
## FINISHED : le combat est joué. Plus aucun choix n'est offert — l'écran tient
## la célébration ou le « Game Over », et n'attend qu'une validation.
enum State { MENU, SUBLIST, TARGETING, ASSAULT, FINISHED }

## Émis quand tous les alliés vivants ont retenu une action : la phase de
## préparation est finie et l'assaut commence. Porte les actions dans l'ordre
## des alliés.
signal preparation_finished(actions: Array)
## Fin du combat, `victory` disant de quel côté. Le Lot 9 en fera un écran de
## résultat ; d'ici là l'écran reste en place, figé sur la dernière image.
signal battle_finished(victory: bool)
## Le joueur a fermé l'écran de fin et demande à rendre la main au worldmap.
## Le combat ne connaît pas ce qui l'a ouvert : c'est `BattleLauncher` qui y
## branche sa fermeture. Lancée seule (F6), la scène reste simplement en place.
signal exit_requested

var _enemies: PackedStringArray = DEFAULT_ENEMIES
var _allies: PackedStringArray = DEFAULT_ALLIES
var _status_panels: Array[UnitStatusPanel] = []
var _menu: CommandMenu
var _state: State = State.MENU
## Les sprites d'ennemis sont CONSERVÉS : le ciblage les met en surbrillance
## et s'ancre sur eux (cf. TargetSelector). Les états de combat correspondants
## vivent en parallèle, dans le même ordre.
var _enemy_sprites: Array[AnimatedSprite2D] = []
var _enemy_units: Array[BattleUnit] = []
var _ally_sprites: Array[AnimatedSprite2D] = []
var _ally_units: Array[BattleUnit] = []
## Phase d'assaut, montée une fois et rejouée à chaque tour.
var _assault: BattleAssault
## Calque des nombres de dégâts, au-dessus des combattants (cf. _build_units).
var _effects: Node2D
var _rhythm: RhythmBar
var _banner: ActionBanner
## Charge de synergie de l'équipe, et son affichage.
var _synergy := SynergyMeter.new()
var _synergy_gauge: SynergyGauge
## Terrain déplaçable : décor, combattants et effets (cf. _build_field).
var _field: Node2D
## Vrai tant que le cadrage de préparation est en place. Sert à savoir si un
## déplacement du curseur de ciblage doit refaire suivre la vue : une attaque
## ordinaire ne cadre rien, seul le choix d'un Eko ouvre cette séquence.
## Allié dont le tour a déjà été annoncé à haute voix (cf. _announce_turn).
var _announced_ally := -1
var _framing := false
## Pose d'origine du fond capturé, relevée au montage plutôt que recalculée :
## `_shift_field` la reprend pour le faire glisser avec le terrain.
var _background_home := Vector2.ZERO
var _field_tween: Tween
## Bande noire du bas, gardée sous la main : elle remonte pendant l'assaut.
var _dark_bottom: Sprite2D
var _dark_top: Sprite2D
var _dark_tween: Tween
var _shake_tween: Tween
## Allié dont c'est le tour. Vaut le nombre d'alliés quand ils ont tous choisi
## (état DONE) : `_previous_acted_ally` remonte alors depuis le dernier.
var _active_ally: int = 0
## Copie de travail de l'inventaire : un objet retenu est décompté tout de
## suite, et rendu si le joueur revient en arrière.
var _inventory: Dictionary = DEFAULT_INVENTORY.duplicate()
## Camps actuellement estompés (cf. _set_units_dimmed).
var _dim_enemies: bool = false
var _dim_allies: bool = false
var _target_selector: TargetSelector
## Liste des Ekos ou des objets, montée à la demande par-dessus le menu racine.
var _sublist: CommandMenu
## "eko" ou "item" : dit dans quel catalogue chercher l'entrée choisie, et
## quel préfixe d'id Localization donne sa description.
var _sublist_kind: String = ""
var _description: DescriptionPanel
## Action en cours de composition : {source, id, target, cost}. `source` vaut
## "attack", "eko" ou "item" — c'est lui qui dit vers quel écran « Back »
## ramène.
var _pending: Dictionary = {}
## Liste qui porte la pastille de l'action pendant le ciblage : le menu racine
## pour une attaque, la sous-liste pour un Eko ou un objet.
var _focus_list: CommandMenu
## Groupe incliné qui porte le menu racine — celui qui tient le pivot. Il est
## translaté d'un allié à l'autre (cf. MENU_SLOT_OFFSET).
var _menu_frame: Node2D
var _legend_cancel_icon: Sprite2D
var _legend_cancel_label: RichTextLabel
## Le groupe incliné de la légende. Masqué en bloc pendant l'assaut : aucune
## touche n'y répond, une invite affichée serait un mensonge.
var _legend: Node2D
var _pending_background: Texture2D
## Groupe incliné du HUD (blocs d'état + synergie), gardé pour le masquer d'un
## bloc à la fin du combat.
var _hud: Node2D
## La validation ne rend la main au worldmap que sur une VICTOIRE : l'écran de
## défaite n'a pas encore de suite (cf. docs/plan_systeme_combat.md).
var _can_exit := false
## Tout l'audio de l'écran (cf. Scripts/Audio/SfxBank.gd) : les trois sons
## d'interface gardent un lecteur dédié, les sons portés par les actions
## passent par son pool.
var _audio: SfxBank
var _sfx_move: AudioStreamPlayer
var _sfx_confirm: AudioStreamPlayer
var _sfx_cancel: AudioStreamPlayer

## Point d'entrée depuis le worldmap. Appeler AVANT d'ajouter la scène à
## l'arbre : _ready() monte l'écran avec ce qui a été fourni ici, ou avec la
## composition par défaut sinon — c'est ce qui rend la scène lançable seule
## pour itérer dessus, sans scaffolding de debug à retirer ensuite.
func setup(context: Dictionary) -> void:
	if context.has("background"):
		_pending_background = context["background"]
	if context.has("enemies"):
		_enemies = context["enemies"]
	if context.has("allies"):
		_allies = context["allies"]

func _ready() -> void:
	stage.scale = Vector2(STAGE_SCALE, STAGE_SCALE)
	# Zoom manuel du calque entier (fond compris), mêmes gestes que sur le
	# worldmap. Posé sur la scène plutôt que sur le Stage pour que le fond
	# capturé suive : c'est l'écran qu'on grossit, pas seulement le décor.
	add_child(CanvasZoom.new())
	_setup_background()
	_build_field()
	_build_decor()
	_build_units()
	_build_dark_lines()
	_build_assault()
	_build_targeting()
	_build_audio()
	_build_hud()
	# Le premier allié n'entre pas par `_open_root_menu` : son menu est monté
	# avec le HUD. Son tour s'annonce donc ici, une fois l'audio en place.
	_announce_turn()

func _setup_background() -> void:
	background_dim.size = Vector2(DESIGN_SIZE * STAGE_SCALE)
	if _pending_background == null:
		# Lancement autonome : pas de worldmap derrière, on assume un fond uni
		# plutôt que d'afficher un cadre vide.
		background.visible = false
		return
	background.texture = _pending_background
	background.visible = true
	# La capture fait la taille du FRAMEBUFFER (la fenêtre), pas celle de
	# l'espace de dessin : avec `stretch/mode = canvas_items`, le canvas fait
	# toujours 1920×1080 alors que la fenêtre peut faire n'importe quoi (1676×942
	# dans la vue intégrée de l'éditeur, par exemple). Posée à l'échelle 1, la
	# capture ne couvrait donc qu'un coin du canvas — le fond paraissait cadré
	# trop serré. On la remet à l'échelle du canvas.
	# Agrandi au-delà du cadre (cf. BACKGROUND_OVERSCAN) et recentré, pour que le
	# déplacement de terrain ne découvre jamais son bord.
	background.scale = (
		Vector2(DESIGN_SIZE * STAGE_SCALE) / _pending_background.get_size()
		* BACKGROUND_OVERSCAN
	)
	background.position = -Vector2(DESIGN_SIZE * STAGE_SCALE) * (BACKGROUND_OVERSCAN - 1.0) / 2.0
	# Relevée ici et pas recalculée ailleurs : `_shift_field` la reprend telle
	# quelle pour faire glisser le fond avec le terrain.
	_background_home = background.position
	# Rééchantillonnage non entier (1676 → 1920) : le filtrage linéaire donne un
	# fond propre, là où le "nearest" hérité du projet doublerait irrégulièrement
	# une colonne sur sept. C'est une photo floutée derrière un voile noir, pas
	# de la pixel-art à préserver.
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

## TERRAIN : tout ce qui se déplace pendant l'assaut. Le sol, les combattants,
## les nombres de dégâts, le ciblage — mais ni le HUD, ni la barre de rythme, ni
## les bandes noires, qui restent posés sur l'écran (cf. FIELD_SHIFT et les
## maquettes d'assaut, où le HUD ne bouge pas d'un pixel).
##
## Premier enfant du Stage : tout ce qui est monté après le recouvre.
func _build_field() -> void:
	_field = Node2D.new()
	stage.add_child(_field)

## Le SOL seulement. Les bandes noires, elles, sont montées après les
## combattants (cf. _build_dark_lines) : elles passent DEVANT eux.
func _build_decor() -> void:
	for entry in [[PLATFORM_LEFT, false], [PLATFORM_RIGHT, true]]:
		var half := Sprite2D.new()
		half.texture = PLATFORM
		half.centered = false
		half.flip_h = entry[1]
		half.position = entry[0]
		_field.add_child(half)

func _build_units() -> void:
	# Un conteneur en Y-sort plutôt que des z_index posés à la main : la
	# profondeur découle alors du point « pieds » de chaque unité, donc des
	# données d'emplacement, et reste juste si on ajoute ou déplace une unité.
	var units := Node2D.new()
	units.y_sort_enabled = true
	_field.add_child(units)

	# Les nombres de dégâts vivent DANS leur propre nœud, posé après le
	# conteneur d'unités : celui-ci trie ses enfants par ordonnée, et un nombre
	# — qui jaillit au-dessus des têtes, donc haut à l'écran — s'y retrouverait
	# systématiquement derrière les combattants.
	_effects = Node2D.new()
	_field.add_child(_effects)

	for i in mini(_enemies.size(), ENEMY_SLOTS.size()):
		# Les ennemis sont retournés horizontalement : la planche les dessine
		# tournés dans l'autre sens (vérifié au pixel près sur le mockup).
		#
		# Aucun décalage de phase entre eux : sur le mockup les trois cactoons
		# sont exactement sur la même frame. UnitSprite.offset_phase() reste
		# disponible si on décide plus tard de les désynchroniser.
		var sprite := _spawn_unit(units, _enemies[i], ENEMY_SLOTS[i], true)
		if sprite == null:
			continue
		_enemy_sprites.append(sprite)
		_enemy_units.append(BattleUnit.new(_enemies[i]))
	for i in mini(_allies.size(), ALLY_SLOTS.size()):
		var ally := _spawn_unit(units, _allies[i], ALLY_SLOTS[i], false)
		if ally == null:
			continue
		_ally_sprites.append(ally)
		_ally_units.append(BattleUnit.new(_allies[i]))

func _spawn_unit(
	parent: Node2D, unit_id: String, feet: Vector2i, mirrored: bool
) -> AnimatedSprite2D:
	var config: Dictionary = BattleData.get_animation(unit_id, ANIM_IDLE)
	if config.is_empty():
		return null
	var sprite: AnimatedSprite2D = UnitSprite.new()
	parent.add_child(sprite)
	sprite.setup(config, feet, mirrored)
	return sprite

## Les deux bandes noires, montées APRÈS la plateforme et les combattants pour
## passer devant eux. Ce n'est pas un détail de goût : pendant l'assaut elles se
## resserrent sur l'action (cf. DARK_LINE_ASSAULT_RISE et _DROP) et viennent
## alors recouvrir le haut et le bas du terrain — derrière les unités, la bande
## basse se glisserait sous leurs pieds au lieu de les masquer, et le cadrage de
## l'écran se déchirerait.
func _build_dark_lines() -> void:
	_dark_bottom = Sprite2D.new()
	_dark_bottom.texture = DARK_LINES
	_dark_bottom.centered = false
	_dark_bottom.position = DARK_LINE_BOTTOM
	stage.add_child(_dark_bottom)

	_dark_top = Sprite2D.new()
	_dark_top.texture = DARK_LINES
	_dark_top.centered = false
	_dark_top.flip_v = true
	_dark_top.position = DARK_LINE_TOP
	stage.add_child(_dark_top)

## L'assaut est un nœud comme un autre : il a besoin de l'arbre pour ses
## attentes (cf. BattleAssault._wait). Monté une fois, relancé à chaque tour.
func _build_assault() -> void:
	_assault = BattleAssault.new()
	add_child(_assault)
	# Montée à même le Stage, après les unités : elle occupe le bas de l'écran,
	# par-dessus le décor et les combattants.
	_rhythm = RhythmBar.new()
	stage.add_child(_rhythm)
	_banner = ActionBanner.new()
	stage.add_child(_banner)
	_assault.setup(
		_combatants(_ally_units, _ally_sprites),
		_combatants(_enemy_units, _enemy_sprites),
		_effects, _rhythm, _banner,
	)
	_assault.changed.connect(_refresh_allies)
	_assault.finished.connect(_on_assault_finished)
	_assault.impact.connect(_shake)
	_assault.field_shift.connect(_shift_field)
	_assault.rhythm_resolved.connect(_gain_synergy)
	_assault.sound_cue.connect(_play_action_sound)

## Secousse d'impact : une oscillation amortie autour de la position de repos du
## Stage. Les deux axes ont des fréquences différentes (l'un en sinus, l'autre en
## cosinus plus lent) — sur la même, le tremblement se réduirait à un
## va-et-vient en diagonale.
func _shake() -> void:
	var base := Vector2.ZERO
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		stage.position = base
	_shake_tween = create_tween()
	_shake_tween.tween_method(
		func(t: float) -> void:
			var decay := 1.0 - t
			stage.position = base + Vector2(
				sin(t * TAU * SHAKE_CYCLES),
				cos(t * TAU * SHAKE_CYCLES * 0.7),
			) * SHAKE_AMPLITUDE * STAGE_SCALE * decay,
		0.0, 1.0, SHAKE_DURATION,
	)
	_shake_tween.tween_callback(func() -> void: stage.position = base)

## La qualité du rythme alimente la synergie de l'équipe (cf. SynergyMeter). Le
## gain est ANIMÉ — aperçu blanc puis remplissage — contrairement au réglage
## direct de `_refresh_synergy`, qui sert au montage.
func _gain_synergy(judgements: Array) -> void:
	_synergy.add(judgements)
	if _synergy_gauge != null:
		_synergy_gauge.gain_to(_synergy.level, _synergy.progress)

func _refresh_synergy() -> void:
	if _synergy_gauge != null:
		_synergy_gauge.set_charge(_synergy.level, _synergy.progress)

## Fait glisser le terrain vers le camp attaqué. `direction` vaut +1 quand un
## allié agit (le terrain part à droite, la caméra se tourne vers les ennemis),
## −1 quand c'est un ennemi, 0 pour revenir au centre.
##
## Le fond capturé suit le mouvement : sur les maquettes, les hexagones se
## déplacent avec le décor. Il est agrandi d'autant (cf. BACKGROUND_OVERSCAN)
## pour ne jamais découvrir son bord.
func _shift_field(direction: int) -> void:
	var x := float(direction * FIELD_SHIFT)
	_move_field(1.0, Vector2(x, 0.0), FIELD_SLIDE)
	if background.visible:
		# Le fond suit CE mouvement-là : 60 px, c'est ce pour quoi son débord a
		# été calculé (cf. BACKGROUND_OVERSCAN). Un point d'écran va en `p + 4·x`.
		_field_tween.tween_property(
			background, "position:x", _background_home.x + x * STAGE_SCALE, FIELD_SLIDE
		)

## Cadre la vue sur `point` (en unités de terrain), agrandie de FOCUS_ZOOM.
func _focus_field(point: Vector2) -> void:
	_framing = true
	_move_field(FOCUS_ZOOM, FOCUS_CENTRE - point * FOCUS_ZOOM, FOCUS_SLIDE)

## Remet le terrain à plat. Sans effet s'il y était déjà : la remise à zéro est
## appelée depuis plusieurs sorties (annulation, changement d'allié, fin de
## préparation) et relancer un tween à l'identique ferait sauter l'écran.
func _reset_framing() -> void:
	if not _framing:
		return
	_framing = false
	_move_field(1.0, Vector2.ZERO, FOCUS_SLIDE)

## Transforme le TERRAIN — décor, combattants, effets, ciblage — sans toucher au
## HUD, au menu ni aux bandes noires.
##
## LE FOND CAPTURÉ NE SUIT PAS. Il est cadré pile sur l'écran, et son débord
## (BACKGROUND_OVERSCAN) a été calculé pour les 60 px du glissement d'assaut, pas
## pour les 250 que peut demander un cadrage. Mesuré : à zoom 1,25 et 111 px de
## translation, son bord gauche entre dans l'image et laisse une bande noire.
## L'élargir assez couvrirait le cas, au prix d'un fond deux fois plus agrandi
## EN PERMANENCE, donc plus flou au repos — un dégât durable pour un mouvement
## passager. Le laisser immobile se lit d'ailleurs comme du parallaxe : un plan
## lointain bouge moins que le premier plan. C'est `_shift_field` qui le fait
## suivre, lui, et il reste dans le budget du débord.
func _move_field(zoom: float, at: Vector2, duration: float) -> void:
	if _field_tween != null and _field_tween.is_valid():
		_field_tween.kill()
	_field_tween = create_tween()
	_field_tween.set_parallel(true)
	_field_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_field_tween.tween_property(_field, "scale", Vector2(zoom, zoom), duration)
	_field_tween.tween_property(_field, "position", at, duration)

## Resserre ou rouvre le cadrage. `raised` = pendant l'assaut.
##
## Les deux bandes bougent ENSEMBLE, d'un seul tween : elles forment un cadre,
## et deux animations séparées finiraient par se décaler le jour où l'une des
## deux durées changerait.
func _slide_dark_bands(raised: bool) -> void:
	if _dark_tween != null and _dark_tween.is_valid():
		_dark_tween.kill()
	var rise := DARK_LINE_ASSAULT_RISE if raised else 0
	var drop := DARK_LINE_ASSAULT_DROP if raised else 0
	_dark_tween = create_tween()
	_dark_tween.set_parallel(true)
	_dark_tween.tween_property(
		_dark_bottom, "position", DARK_LINE_BOTTOM - Vector2(0, rise), DARK_LINE_SLIDE
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_dark_tween.tween_property(
		_dark_top, "position", DARK_LINE_TOP + Vector2(0, drop), DARK_LINE_SLIDE
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _combatants(units: Array[BattleUnit], sprites: Array[AnimatedSprite2D]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in mini(units.size(), sprites.size()):
		entries.append({"unit": units[i], "sprite": sprites[i]})
	return entries

## Le sélecteur est posé sur le TERRAIN, après le conteneur d'unités et avant
## les groupes d'interface : sa plaque passe donc au-dessus des combattants, et
## sous le menu et le HUD. Sur le terrain et non sur le Stage, pour qu'il suive
## le glissement de l'assaut comme les unités qu'il désigne (cf. _build_field).
##
## Son ordre dans l'arbre compte aussi pour les entrées : `_unhandled_input`
## est distribué à l'envers de l'arbre, le menu — ajouté plus tard — voit donc
## chaque touche en premier. C'est ce qui fait que la validation qui OUVRE le
## ciblage n'est pas aussitôt reconsommée par celui-ci : le menu la marque
## traitée avant que le sélecteur ne soit interrogé.
func _build_targeting() -> void:
	_target_selector = TargetSelector.new()
	_field.add_child(_target_selector)
	_target_selector.selection_changed.connect(_on_target_moved)
	_target_selector.confirmed.connect(_on_target_confirmed)
	_target_selector.cancelled.connect(_on_target_cancelled)

## Renvoie le nœud auquel ajouter des enfants EN COORDONNÉES ABSOLUES pour
## qu'ils se retrouvent inclinés de `degrees` autour de `pivot`.
##
## Le double nœud (un parent posé sur le pivot, un enfant décalé de l'inverse)
## évite de devoir réécrire en relatif toutes les positions relevées sur la
## maquette : elles restent lisibles telles quelles, et l'inclinaison se règle
## à un seul endroit.
func _tilted_group(pivot: Vector2, degrees: float) -> Node2D:
	var group := Node2D.new()
	group.position = pivot
	group.rotation_degrees = degrees
	stage.add_child(group)
	var holder := Node2D.new()
	holder.position = -pivot
	group.add_child(holder)
	return holder

func _build_hud() -> void:
	var hud := _tilted_group(HUD_PIVOT, HUD_TILT_DEG)
	_hud = hud
	for i in mini(_allies.size(), STATUS_PANEL_POS.size()):
		var panel: UnitStatusPanel = UnitStatusPanel.new()
		panel.position = Vector2(STATUS_PANEL_POS[i])
		hud.add_child(panel)
		panel.setup(_allies[i])
		# Lot 1 : le premier allié est arbitrairement l'allié actif, comme sur
		# le mockup. C'est la boucle de préparation (Lot 5) qui pilotera ça.
		_status_panels.append(panel)

	_synergy_gauge = SynergyGauge.new()
	_synergy_gauge.position = SYNERGY_POS
	hud.add_child(_synergy_gauge)
	_refresh_synergy()

	var synergy_label: RichTextLabel = BattleText.make(
		"SYN", SYNERGY_LABEL_SIZE, SYNERGY_LABEL_COLOR
	)
	synergy_label.position = SYNERGY_LABEL_POS
	hud.add_child(synergy_label)

	_menu = CommandMenu.new()
	var menu_holder := _tilted_group(MENU_PIVOT, MENU_TILT_DEG)
	menu_holder.add_child(_menu)
	# Le parent du porteur est le nœud posé SUR le pivot (cf. _tilted_group) :
	# c'est lui qu'on translate pour faire suivre le menu à l'allié actif,
	# puisque déplacer le porteur ferait aussi bouger le centre de rotation.
	_menu_frame = menu_holder.get_parent()
	_menu_frame.position = MENU_PIVOT + Vector2(_menu_offset(_active_ally))
	_menu.reference_frame = stage
	# Sélection par défaut sur la PREMIÈRE entrée (Attack). Le mockup fige
	# « Eko » parce qu'il illustre un état de navigation, pas l'état d'entrée.
	_menu.setup(_root_entries(), 0)
	_menu.active = true
	_menu.selection_changed.connect(_on_menu_moved)
	_menu.confirmed.connect(_on_menu_confirmed)
	_menu.cancelled.connect(_on_menu_cancelled)

	# La sous-liste occupe la MÊME bande que le menu racine, qu'elle remplace :
	# même groupe incliné, mêmes positions de pastilles. Montée après le menu
	# pour que `_unhandled_input`, distribué à l'envers de l'arbre, la
	# consulte en premier — la validation qui la ferme n'est ainsi jamais
	# reconsommée par le menu qui réapparaît derrière.
	# Posée à même le Stage, sans groupe incliné : la liste incline chaque
	# rangée sur elle-même (cf. CommandMenu). Ses coordonnées sont donc déjà
	# celles de l'écran, et `to_flat()` s'y réduit à l'identité.
	_sublist = CommandMenu.new()
	stage.add_child(_sublist)
	_sublist.reference_frame = stage
	_sublist.set_layout(CommandMenu.Layout.LIST)
	_sublist.visible = false
	_sublist.selection_changed.connect(_on_sublist_moved)
	_sublist.confirmed.connect(_on_sublist_confirmed)
	_sublist.cancelled.connect(_on_sublist_cancelled)

	_description = DescriptionPanel.new()
	_description.position = DESCRIPTION_POS
	_description.visible = false
	stage.add_child(_description)

	_build_legend()
	# Après le menu : les planches des alliés dépendent de l'entrée survolée
	# (cf. _ally_animation), donc d'une liste déjà montée. Les PA affichés sont
	# les PA RÉELS de l'unité, pas la valeur de présentation du mockup : la
	# maquette montre un tour déjà entamé, un combat commence jauges pleines.
	_refresh_allies()

## Décalage du groupe de menu pour l'allié `index`, cf. MENU_SLOT_OFFSET.
## Hors table (fin de préparation, ou un troisième emplacement qui n'aurait pas
## encore été relevé sur maquette), on retombe sur l'écart des emplacements de
## combat : approché, mais toujours du bon côté de l'écran.
## Sprite de l'allié dont c'est le tour, ou null hors préparation.
func _active_sprite() -> UnitSprite:
	if _active_ally < 0 or _active_ally >= _ally_sprites.size():
		return null
	return _ally_sprites[_active_ally]

## Point à regarder sur une unité dont on a le sprite : le centre de son dessin,
## relevé sur les pixels réellement peints.
func _focus_point_of(sprite: UnitSprite) -> Vector2:
	if sprite == null:
		return FOCUS_CENTRE
	return sprite.art_centre()

## Idem pour une cible que le sélecteur ne connaît que par ses pieds — un
## ciblage de groupe rend un barycentre, pas un sprite.
func _focus_point_of_feet(feet: Vector2) -> Vector2:
	return feet - Vector2(0, FOCUS_BODY_RISE)

func _menu_offset(index: int) -> Vector2i:
	if index >= 0 and index < MENU_SLOT_OFFSET.size():
		return MENU_SLOT_OFFSET[index]
	if index >= 0 and index < ALLY_SLOTS.size():
		return ALLY_SLOTS[index] - ALLY_SLOTS[0]
	return Vector2i.ZERO

## Le menu racine n'a ni coût ni description : ses entrées se réduisent à leur
## id, qui sert aussi de libellé.
func _root_entries() -> Array[Dictionary]:
	var unit := _active_unit()
	# « Attack » porte la nature des dégâts de CELUI QUI JOUE — direct pour Noah,
	# blessure pour Iris. L'icône reste cachée tant que le menu est déplié ; elle
	# n'apparaît qu'une fois l'entrée réduite et posée près de la cible
	# (cf. CommandMenu._shows_type_icon).
	var attack_type := ""
	if unit != null:
		attack_type = String(
			BattleData.get_unit(unit.id).get("basic_attack", {}).get("damage_type", "")
		)
	var entries: Array[Dictionary] = []
	for id in MENU_ENTRIES:
		var entry := {"id": id, "text_id": id}
		if id == MENU_ATTACK:
			entry["damage_type"] = attack_type
		entries.append(entry)
	return entries

## Remet les trois marqueurs d'état de chaque bloc d'allié en accord avec les
## données : à qui le tour, qui a déjà choisi, et combien de PA il reste.
func _refresh_allies() -> void:
	for i in mini(_status_panels.size(), _ally_units.size()):
		var unit := _ally_units[i]
		_status_panels[i].set_active(i == _active_ally)
		# Pendant l'assaut, plus personne n'est « en attente » : l'action n'est
		# plus un choix retenu, elle est en train de se jouer. La coche et la
		# teinte du portrait tomberaient sinon en contradiction avec le sprite,
		# qui a déjà repris ses couleurs sur le terrain.
		_status_panels[i].set_confirmed(_state != State.ASSAULT and unit.has_action())
		_status_panels[i].set_ap(unit.ap, unit.ap_max)
		_status_panels[i].set_hp(unit.hp, unit.hp_max, unit.injury)
	_refresh_unit_visuals()

## Sons d'interface repris tels quels du worldmap plutôt que dupliqués : c'est
## le même vocabulaire sonore d'un écran à l'autre (déplacement, validation,
## action impossible), cf. WorldmapCursor.move_sfx et Hero.validation_sfx.
##
## Le thème de combat part ici aussi. Rien à faire du côté du worldmap :
## `BattleLauncher` le passe en `PROCESS_MODE_DISABLED`, ce qui suspend son
## `AudioStreamPlayer` (vérifié en jeu : `playing` retombe à false et la
## position reste figée) et le reprend là où il en était à la sortie.
func _build_audio() -> void:
	_audio = SfxBank.new()
	add_child(_audio)
	_sfx_move = _audio.player(SFX_MOVE)
	_sfx_confirm = _audio.player(SFX_CONFIRM)
	_sfx_cancel = _audio.player(SFX_CANCEL)
	# La barre de rythme prend ici ses quatre sons de verdict, et pas à sa
	# construction : elle est montée avec l'assaut, donc avant que la banque
	# existe (cf. _ready). Ils restent sur Master, comme les sons de menu.
	_rhythm.setup_audio(_audio)
	# Le pool sert les sons portés par les ACTIONS, qui sont des voix aujourd'hui
	# (cf. units.json). Un bruitage non vocal — un impact, un sort — devra avoir
	# son propre bus le jour où il arrivera : il n'a pas de raison d'effacer la
	# musique.
	_audio.bus = BUS_VOICE
	_audio.music(MUSIC_THEME, MUSIC_VOLUME, BUS_MUSIC)

## Joue le son qu'une action porte dans sa définition (cf. BattleAssault.
## _sounds_of). La scène ne sait pas de QUELLE action il s'agit — c'est voulu :
## donner sa voix à un personnage se fait dans `units.json`, pas ici.
func _play_action_sound(path: String) -> void:
	_audio.play_path(path)

func _on_menu_moved(_index: int) -> void:
	_sfx_move.play()

## « Attack » vise directement un ennemi ; « Eko » et « Items » passent d'abord
## par leur sous-liste. « Guard » n'a pas encore d'action (Lot 5), elle se
## contente du son de validation.
## La voix ne part QUE si la commande a abouti : « Eko » sur une unité qui n'en
## connaît aucun, ou « Attack » sans cible debout, sonnent l'erreur — y ajouter
## une réplique enjouée donnerait deux messages contradictoires dans la même
## frame.
func _on_menu_confirmed(id: String) -> void:
	# Relevé AVANT le dispatch : la garde fait passer le tour dans la foulée, et
	# `_active_unit()` désignerait alors l'allié SUIVANT.
	var actor := _active_unit()
	match id:
		MENU_ATTACK:
			if _start_action({"source": BattleData.SOURCE_ATTACK, "target": "enemy"}, _menu):
				_play_unit_sound(actor, SOUND_MENU_ATTACK)
		MENU_EKO:
			if _open_sublist(BattleData.SOURCE_EKO, _eko_entries()):
				_play_unit_sound(actor, SOUND_MENU_EKO)
		MENU_ITEMS:
			if _open_sublist(BattleData.SOURCE_ITEM, _item_entries()):
				_play_unit_sound(actor, SOUND_MENU_ITEMS)
		MENU_GUARD:
			# La garde ne vise personne et ne coûte rien : elle est retenue
			# immédiatement, sans passer par le ciblage.
			_sfx_confirm.play()
			# AVANT `_queue_action`, qui enchaîne sur le tour de l'allié suivant :
			# posée après, la réplique de la garde passerait derrière celle du
			# tour, et on entendrait les deux personnages dans le désordre.
			_play_unit_sound(actor, SOUND_MENU_GUARD)
			_queue_action({"source": BattleData.SOURCE_GUARD, "target": "self", "cost": 0}, -1)
		_:
			_sfx_confirm.play()

## Au menu racine, annuler revient au tour de l'allié PRÉCÉDENT et défait son
## choix. S'il n'y en a pas, le son d'erreur signale que l'entrée n'a pas
## d'effet.
func _on_menu_cancelled() -> void:
	_step_back()

## ──────────────────────────────────────────────────────────────────────────
##  SOUS-LISTES (Ekos, objets)
## ──────────────────────────────────────────────────────────────────────────

## Entrées d'Ekos de l'allié actif. Le coût est affiché en losanges, et passe
## en losanges ÉTEINTS quand l'allié n'a plus assez de PA — c'est déjà le sens
## que cet asset porte sur la ligne de PA du HUD.
func _eko_entries() -> Array[Dictionary]:
	var unit := _active_unit()
	var entries: Array[Dictionary] = []
	if unit == null:
		return entries
	for id in BattleData.get_unit_ekos(unit.id):
		var eko: Dictionary = BattleData.get_eko(id)
		var cost: int = int(eko.get("ap_cost", 0))
		entries.append({
			"id": id,
			"text_id": "eko.%s.name" % id,
			"cost": cost,
			"affordable": unit.can_pay(cost),
			"damage_type": String(eko.get("damage_type", "")),
		})
	return entries

## Un objet ne coûte pas de PA : la colonne de droite y affiche la QUANTITÉ en
## réserve à la place des losanges.
func _item_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in _inventory:
		entries.append({
			"id": id,
			"text_id": "item.%s.name" % id,
			"quantity": int(_inventory[id]),
			"damage_type": String(BattleData.get_item(id).get("damage_type", "")),
		})
	return entries

## Renvoie false si la liste est vide, donc si rien ne s'est ouvert (cf.
## _start_action pour la même convention).
func _open_sublist(kind: String, entries: Array[Dictionary]) -> bool:
	if entries.is_empty():
		# Aucun Eko connu, ou sac vide : mieux vaut le son d'erreur qu'une
		# liste vide où la touche « Back » serait la seule issue.
		_sfx_cancel.play()
		return false
	_sfx_confirm.play()
	_sublist_kind = kind
	_state = State.SUBLIST
	_menu.active = false
	_menu.visible = false
	_sublist.setup(entries, 0)
	_sublist.visible = true
	_sublist.active = true
	_set_units_dimmed(true, true)
	_show_description(_sublist.get_selected_id())
	_set_legend_cancel(PROMPT_BACK)
	# Ekos ET objets : les deux listes se choisissent en regardant celui qui
	# agit. `kind` ne sert plus à trancher ici — il reste le sujet de la liste,
	# et c'est le ciblage qui décide ensuite où la vue se déplace.
	_focus_field(_focus_point_of(_active_sprite()))
	return true

func _close_sublist() -> void:
	# L'état AVANT tout le reste : _set_units_dimmed rafraîchit les combattants,
	# et ce rafraîchissement lit l'état courant pour choisir leur planche
	# (cf. _is_aiming). Posé après, il voyait encore « liste d'Ekos ouverte » et
	# laissait l'allié dégainé sur le menu racine.
	_state = State.MENU
	_reset_framing()
	_set_units_dimmed(false, false)
	_sublist.active = false
	_sublist.visible = false
	_sublist.restore()
	_description.visible = false
	_menu.visible = true
	_menu.active = true
	_set_legend_cancel(_root_cancel_prompt())

## Joue le son que l'UNITÉ porte pour `moment` (cf. BattleData.UNIT_SOUNDS).
## Silencieux si l'unité n'en déclare pas : toutes n'ont pas de voix, et c'est
## l'état normal du catalogue aujourd'hui.
func _play_unit_sound(unit: BattleUnit, moment: String) -> void:
	if unit == null or moment == "":
		return
	_audio.play_path(BattleData.pick(BattleData.unit_sounds(unit.id), moment))

## Annonce le tour de l'allié actif — UNE fois par changement d'allié.
##
## Le garde-fou est nécessaire : le menu racine se rouvre aussi sans que le tour
## change (retour d'une sous-liste, nouvelle manche), et la réplique se
## répéterait. Il couvre du même coup les trois appelants de `_open_root_menu`
## sans qu'aucun ait à savoir dans quel cas il se trouve.
func _announce_turn() -> void:
	if _active_ally == _announced_ally:
		return
	_announced_ally = _active_ally
	_play_unit_sound(_active_unit(), SOUND_TURN)

func _show_description(id: String) -> void:
	if id == "":
		_description.visible = false
		return
	_description.show_text("%s.%s.desc" % [_sublist_kind, id])

func _on_sublist_moved(_index: int) -> void:
	_sfx_move.play()
	_show_description(_sublist.get_selected_id())

func _on_sublist_confirmed(id: String) -> void:
	var unit := _active_unit()
	# Même lecture que l'assaut : la règle « où vit la définition d'une action »
	# n'existe qu'à un seul endroit. L'id de l'unité ne sert qu'à l'attaque de
	# base, qui ne passe jamais par une sous-liste — il est passé quand même,
	# pour que l'appel reste juste si un troisième type de liste apparaît.
	var definition := BattleData.definition_of(
		unit.id if unit != null else "", {"source": _sublist_kind, "id": id}
	)
	var cost: int = int(definition.get("ap_cost", 0))
	# Deux refus différents selon la liste : un Eko demande des PA, un objet
	# demande d'en avoir encore en réserve. Dans les deux cas la ligne le disait
	# déjà — losanges éteints ou « x0 » — le son ne fait que confirmer.
	var available := (
		int(_inventory.get(id, 0)) > 0 if _sublist_kind == BattleData.SOURCE_ITEM
		else unit != null and unit.can_pay(cost)
	)
	if unit == null or not available:
		_sfx_cancel.play()
		return
	_start_action({
		"source": _sublist_kind,
		"id": id,
		"target": String(definition.get("target", "enemy")),
		"cost": cost,
	}, _sublist)

func _on_sublist_cancelled() -> void:
	_sfx_cancel.play()
	_close_sublist()

## ──────────────────────────────────────────────────────────────────────────
##  CIBLAGE
## ──────────────────────────────────────────────────────────────────────────

## Renvoie false si l'action n'a pas pu s'engager — c'est ce qui distingue un
## choix RETENU d'un clic sans effet, et la voix du personnage ne doit partir que
## dans le premier cas.
func _start_action(pending: Dictionary, list: CommandMenu) -> bool:
	if not _open_targeting(pending, list):
		# Plus rien à viser : le son d'erreur vaut mieux qu'un écran de ciblage
		# vide.
		_sfx_cancel.play()
		return false
	return true

## `list` est la liste qui porte l'action retenue : c'est elle qui se réduit à
## sa seule entrée pour aller se poser à côté de la cible.
## Renvoie false si le mode de ciblage ne désigne personne, auquel cas rien n'a
## changé.
func _open_targeting(pending: Dictionary, list: CommandMenu) -> bool:
	var kind := String(pending.get("target", "enemy"))
	var targets := _targets_for(kind)
	if targets.is_empty():
		return false
	_sfx_confirm.play()
	_pending = pending
	_focus_list = list
	_state = State.TARGETING
	_menu.active = false
	_sublist.active = false
	# La description a fait son office : l'action est choisie, le cadre n'a
	# plus rien à apporter et il encombrerait le terrain qu'on vise.
	_description.visible = false
	# Le camp visé garde son opacité, l'autre s'efface.
	# Le mode se lit relativement à celui qui agit ; ici c'est toujours un allié,
	# « son camp » désigne donc l'équipe (cf. BattleData.targets_own_camp).
	var aims_at_allies := BattleData.targets_own_camp(kind)
	_set_units_dimmed(aims_at_allies, not aims_at_allies)
	# Première cible vivante par défaut, comme les listes s'ouvrent sur leur
	# première entrée : une sélection par défaut stable vaut mieux qu'une
	# sélection « intelligente » qui changerait d'un tour à l'autre.
	# Le curseur de la pastille se tait sur un ciblage de GROUPE : là-bas chaque
	# cible porte le sien (cf. TargetSelector), et celui-ci se poserait au
	# barycentre, c'est-à-dire au-dessus d'un ennemi qui n'est pas plus visé que
	# ses voisins. `CommandMenu.restore()` le rallume en sortant.
	var group := BattleData.targets_whole_camp(kind)
	list.cursor_visible = not group
	_target_selector.open(targets, group)
	# APRÈS l'ouverture, jamais avant : c'est elle qui fixe la cible courante, et
	# la lire plus tôt cadrerait sur la sélection du ciblage PRÉCÉDENT — ou sur
	# l'origine de l'écran au tout premier.
	_frame_target(kind)
	_follow_target()
	_set_legend_cancel(PROMPT_BACK)
	return true

## Cibles possibles d'un mode de ciblage. Les morts sont écartés ici plutôt que
## dans le sélecteur : c'est une règle de jeu, pas une affaire d'affichage.
func _targets_for(kind: String) -> Array[Dictionary]:
	match kind:
		"enemy", "enemies":
			return _living(_enemy_units, _enemy_sprites)
		"ally", "allies":
			return _living(_ally_units, _ally_sprites)
		"self":
			var alone: Array[Dictionary] = []
			if _active_ally < mini(_ally_units.size(), _ally_sprites.size()):
				alone.append({
					"unit": _ally_units[_active_ally],
					"sprite": _ally_sprites[_active_ally],
				})
			return alone
	push_warning("BattleScene: mode de ciblage inconnu '%s'" % kind)
	return []

func _living(
	units: Array[BattleUnit], sprites: Array[AnimatedSprite2D]
) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for i in mini(units.size(), sprites.size()):
		if units[i].is_alive():
			targets.append({"unit": units[i], "sprite": sprites[i]})
	return targets

## Réduit la liste active à l'action retenue et la pose près de la cible. La
## conversion vers le repère interne est demandée à la liste elle-même : les
## deux ne pivotent pas autour du même point.
## Les pieds de la cible sont en espace TERRAIN, la liste se place en espace
## Stage. Tant que le terrain restait à l'identité pendant la préparation, les
## deux se confondaient — plus depuis le cadrage. Le décalage de la pastille,
## lui, s'applique APRÈS la transformation : il se mesure à l'écran et n'a aucune
## raison de grossir avec le zoom.
func _follow_target() -> void:
	var feet := _field.transform * _target_selector.get_selected_feet()
	var rise := Vector2.ZERO
	if BattleData.targets_whole_camp(String(_pending.get("target", "enemy"))):
		rise = Vector2(0, -GROUP_PILL_RISE)
	_focus_list.focus_selection(_focus_list.to_flat(feet + FOCUS_PILL_OFFSET + rise))

func _on_target_moved(_index: int) -> void:
	_sfx_move.play()
	_frame_target(String(_pending.get("target", "enemy")))
	_follow_target()

## Recadre la vue sur la cible courante, pour les trois commandes qui visent.
##
## NE BOUGE PAS quand l'action désigne le camp allié : la vue est déjà sur celui
## qui lance, et la déplacer d'un allié à l'autre pour un soin ne montrerait rien
## de plus. Conséquence pour « Attack », qui n'a pas de liste où cadrer d'abord :
## sa séquence commence directement sur la cible, il n'y a aucun autre moment où
## la poser.
func _frame_target(kind: String) -> void:
	if BattleData.targets_own_camp(kind):
		return
	_focus_field(_focus_point_of_feet(_target_selector.get_selected_feet()))

## Valider une cible retient l'action pour l'allié courant et passe au suivant.
func _on_target_confirmed(index: int) -> void:
	_sfx_confirm.play()
	var pending := _pending.duplicate()
	_target_selector.close()
	_focus_list.restore()
	_pending = {}
	# Une attaque vient du menu racine : il n'y a aucune sous-liste à refermer.
	# Ce qui suit — le tour de l'allié suivant, ou l'assaut — repose de toute
	# façon l'écran en entier.
	if _focus_list == _sublist:
		_close_sublist()
	_queue_action(pending, index)

## « Back » ramène d'où l'on vient : au menu racine pour une attaque, à la
## sous-liste pour un Eko ou un objet.
func _on_target_cancelled() -> void:
	_sfx_cancel.play()
	_target_selector.close()
	_focus_list.restore()
	var from_sublist := String(_pending.get("source", BattleData.SOURCE_ATTACK)) != BattleData.SOURCE_ATTACK
	_pending = {}
	if not from_sublist:
		_close_sublist()
		return
	_state = State.SUBLIST
	# La vue revient sur celui qui lance : on retourne à sa liste, c'est lui que
	# le joueur regarde à nouveau. Sans effet si rien n'était cadré (un objet).
	if _framing:
		_focus_field(_focus_point_of(_active_sprite()))
	_sublist.active = true
	_description.visible = true
	_set_units_dimmed(true, true)
	_set_legend_cancel(PROMPT_BACK)

## Note quels camps sont estompés ; le rendu passe par _refresh_unit_visuals,
## seul endroit qui écrit la modulation des sprites — sans quoi l'estompage et
## la teinte « action retenue » se marcheraient dessus.
func _set_units_dimmed(dim_enemies: bool, dim_allies: bool) -> void:
	_dim_enemies = dim_enemies
	_dim_allies = dim_allies
	_refresh_unit_visuals()

## Trois états possibles pour un combattant, du plus fort au plus faible :
## action déjà retenue (assombrissement opaque), camp non regardé (simple
## transparence), sinon pleine opacité. L'allié dont c'est le tour n'est jamais
## estompé.
##
## Les deux traitements ne se confondent pas : l'estompage dit « ce n'est pas ce
## qu'on regarde en ce moment » et rend translucide ; l'assombrissement dit
## « celui-là a fini de choisir » et reste plein. Un allié qui a joué garde donc
## sa présence sur le terrain, même pendant qu'un autre parcourt une liste.
##
## UNE UNITÉ TOMBÉE N'EST PAS TOUCHÉE ICI : sa disparition est une animation en
## cours, portée par la phase d'assaut (cf. BattleAssault._bury_the_dead). La
## réécrire à chaque rafraîchissement la ferait ressusciter en plein fondu.
func _refresh_unit_visuals() -> void:
	var faded := Color(1.0, 1.0, 1.0, INACTIVE_UNIT_ALPHA)
	for i in mini(_enemy_sprites.size(), _enemy_units.size()):
		if not _enemy_units[i].is_alive():
			continue
		_enemy_sprites[i].modulate = faded if _dim_enemies else Color.WHITE
	# Combat joué : la célébration pose elle-même les teintes des alliés, fondu
	# de retour d'un ranimé compris. Les réécrire ici le ferait réapparaître d'un
	# coup au milieu de son propre fondu. Les ennemis, eux, sont tous à terre.
	if _state == State.FINISHED:
		return
	for i in mini(_ally_sprites.size(), _ally_units.size()):
		if not _ally_units[i].is_alive():
			continue
		if _state != State.ASSAULT and _ally_units[i].has_action():
			_ally_sprites[i].modulate = CONFIRMED_SPRITE_MODULATE
		elif _dim_allies and i != _active_ally:
			_ally_sprites[i].modulate = faded
		else:
			_ally_sprites[i].modulate = Color.WHITE
	_refresh_ally_poses()

## Planche que doit jouer chaque allié :
##   - action retenue → la pose d'attente, il ne choisit plus rien ;
##   - en train de préparer une attaque ou un Eko → la pose d'apprêt ;
##   - sinon le repos.
func _ally_animation(index: int) -> String:
	if _ally_units[index].has_action():
		return ANIM_STANDBY
	if index == _active_ally and _is_aiming():
		return ANIM_AIMING
	return ANIM_IDLE

## Vrai quand l'allié actif a VALIDÉ une attaque ou « Eko ». Le déclencheur est
## la validation, jamais le survol : au menu racine il n'a encore rien décidé,
## et sa silhouette changerait à chaque mouvement du curseur.
##
## Les deux commandes ne dégainent donc pas au même écran, parce qu'elles ne
## sont pas validées au même moment : « Attack » ouvre directement le ciblage,
## « Eko » ouvre d'abord sa liste — et c'est bien là que Noah dégaine, pas
## seulement une fois la compétence choisie. « Items » et « Guard » ne font
## dégainer nulle part.
func _is_aiming() -> bool:
	match _state:
		State.SUBLIST:
			return _sublist_kind == BattleData.SOURCE_EKO
		State.TARGETING:
			var source := String(_pending.get("source", ""))
			return source == BattleData.SOURCE_ATTACK or source == BattleData.SOURCE_EKO
	return false

## Met chaque allié sur la planche que son état demande. On ne rejoue que les
## changements : construire des SpriteFrames relit la texture, et cette
## fonction passe à chaque rafraîchissement d'écran.
##
## Une planche absente laisse l'allié sur la sienne plutôt que de le renvoyer au
## repos — Iris n'a pas encore d'`atkeff`, elle garde donc son idle pendant
## qu'elle prépare une attaque, ce qui est exactement ce qu'on veut d'un asset
## manquant : rien, pas un état inventé.
##
## PENDANT L'ASSAUT, cette fonction s'abstient : c'est la phase d'assaut qui
## pilote les planches (geste d'attaque, retour au repos), et elle a besoin de
## les tenir plus longtemps qu'un rafraîchissement d'écran.
func _refresh_ally_poses() -> void:
	# Deux phases posent leurs planches elles-mêmes : l'assaut (gestes) et la
	# fin de combat (célébration). Repasser derrière elles rendrait les alliés
	# à leur planche de repos au milieu du mouvement.
	if _state == State.ASSAULT or _state == State.FINISHED:
		return
	for i in mini(_ally_sprites.size(), _ally_units.size()):
		var config: Dictionary = BattleData.get_animation(_allies[i], _ally_animation(i))
		if config.is_empty():
			continue
		var sprite: UnitSprite = _ally_sprites[i]
		# Comparée à la planche RÉELLEMENT montée, pas à un état gardé de côté :
		# la phase d'assaut change de planche sans passer par ici, et un cache
		# finirait par mentir. Reconstruire des SpriteFrames relit la texture, il
		# ne faut donc le faire que sur un vrai changement.
		if sprite.sheet_path == String(config.get("sheet", "")):
			continue
		sprite.play_sheet(config)

## ──────────────────────────────────────────────────────────────────────────
##  BOUCLE DE PRÉPARATION
## ──────────────────────────────────────────────────────────────────────────

## Retient `pending` pour l'allié courant, en débite le coût, puis passe la
## main. `target` est l'index de la cible dans la liste proposée, ou -1 quand
## l'action ne vise personne (la garde).
##
## Le débit se fait ICI, à la validation, et non au moment où l'action
## s'exécutera : c'est ce qui rend le retour en arrière possible et honnête —
## les PA et les objets rendus sont exactement ceux qui ont été pris.
func _queue_action(pending: Dictionary, target: int) -> void:
	var unit := _active_unit()
	if unit == null:
		return
	var action := pending.duplicate()
	var kind := String(pending.get("target", "self"))
	action["target"] = kind
	action["target_index"] = target
	# Les cibles sont retenues comme des UNITÉS, pas seulement comme un index :
	# celui-ci désigne une place dans la liste des vivants au moment du choix, et
	# cette liste aura changé quand l'assaut exécutera l'action.
	action["targets"] = _resolve_targets(kind, target)
	unit.action = action
	if String(pending.get("source", "")) == BattleData.SOURCE_ITEM:
		var id := String(pending.get("id", ""))
		_inventory[id] = maxi(0, int(_inventory.get(id, 0)) - 1)
	else:
		unit.spend_ap(int(pending.get("cost", 0)))
	_advance_turn()

## Unités effectivement visées par une action, résolues à la validation.
## `index` est l'index dans la liste proposée par _targets_for ; il est ignoré
## pour un ciblage de groupe, qui retient tout le camp.
func _resolve_targets(kind: String, index: int) -> Array[BattleUnit]:
	var offered := _targets_for(kind)
	var chosen: Array[BattleUnit] = []
	if BattleData.targets_whole_camp(kind):
		for entry in offered:
			chosen.append(entry["unit"])
	elif index >= 0 and index < offered.size():
		chosen.append(offered[index]["unit"])
	return chosen

## Rend ce que l'action de `unit` avait pris, puis l'oublie.
func _undo_action(unit: BattleUnit) -> void:
	if not unit.has_action():
		return
	if String(unit.action.get("source", "")) == BattleData.SOURCE_ITEM:
		var id := String(unit.action.get("id", ""))
		_inventory[id] = int(_inventory.get(id, 0)) + 1
	else:
		unit.refund_ap(int(unit.action.get("cost", 0)))
	unit.clear_action()

func _advance_turn() -> void:
	var next := _next_ally_to_play(_active_ally + 1)
	if next < 0:
		_finish_preparation()
		return
	_active_ally = next
	_open_root_menu()

## Premier allié vivant à partir de `from` qui n'a pas encore choisi.
func _next_ally_to_play(from: int) -> int:
	for i in range(maxi(0, from), _ally_units.size()):
		if _ally_units[i].is_alive() and not _ally_units[i].has_action():
			return i
	return -1

## Dernier allié, avant le courant, dont on peut défaire le choix.
func _previous_acted_ally() -> int:
	for i in range(mini(_active_ally, _ally_units.size()) - 1, -1, -1):
		if _ally_units[i].is_alive() and _ally_units[i].has_action():
			return i
	return -1

## Revient au tour de l'allié précédent en défaisant son choix. Sans allié
## précédent, il n'y a rien à annuler : le son d'erreur le dit.
func _step_back() -> void:
	var previous := _previous_acted_ally()
	_sfx_cancel.play()
	if previous < 0:
		return
	_undo_action(_ally_units[previous])
	_active_ally = previous
	_open_root_menu()

func _open_root_menu() -> void:
	_state = State.MENU
	_reset_framing()
	# Reconstruite plutôt que réactivée : la sélection repart sur « Attack »,
	# comme sur la maquette du tour du second allié, et les coûts d'Ekos sont
	# recalculés pour le nouvel allié.
	_menu.setup(_root_entries(), 0)
	_menu.visible = true
	_menu.active = true
	# Le bloc entier se pose sous l'allié dont c'est le tour.
	_menu_frame.position = MENU_PIVOT + Vector2(_menu_offset(_active_ally))
	_set_units_dimmed(false, false)
	_refresh_allies()
	_set_legend_cancel(_root_cancel_prompt())
	_announce_turn()

## Tous les alliés vivants ont choisi : la préparation est finie, l'assaut
## commence. L'écran se vide de tout ce qui appelle une entrée — plus de menu,
## plus de légende : pendant l'assaut le joueur regarde, il ne décide plus.
func _finish_preparation() -> void:
	_state = State.ASSAULT
	# L'assaut a son propre glissement de terrain : il doit partir de l'identité.
	_reset_framing()
	_active_ally = _ally_units.size()
	_menu.active = false
	_menu.visible = false
	_set_units_dimmed(false, false)
	_refresh_allies()
	_legend.visible = false
	_slide_dark_bands(true)
	preparation_finished.emit(_planned_actions())
	_assault.run()

## Fin de l'assaut : le tour se referme pour tout le monde — c'est là que les
## blessures épargnées guérissent et que les gardes tombent (cf.
## BattleUnit.end_turn) — puis un nouveau tour s'ouvre, ou le combat s'arrête.
func _on_assault_finished(outcome: int) -> void:
	for unit in _ally_units + _enemy_units:
		unit.end_turn()
	if outcome != BattleAssault.Outcome.ONGOING:
		_refresh_allies()
		var victory := outcome == BattleAssault.Outcome.VICTORY
		battle_finished.emit(victory)
		_finish_battle(victory)
		return
	_start_round()

## Nouveau tour de préparation. Les PA repartent au maximum et les actions du
## tour précédent sont oubliées : elles ont été jouées, elles ne doivent pas
## reparaître comme des choix déjà pris.
func _start_round() -> void:
	# LES DEUX CAMPS : depuis que l'action d'un ennemi est retenue et payée comme
	# celle d'un allié (cf. BattleAssault._commit_enemy_actions), ses PA doivent
	# repartir au maximum comme les siens — sans quoi un ennemi qui lance un Eko
	# n'en relancerait plus jamais.
	for unit in _ally_units + _enemy_units:
		unit.clear_action()
		unit.restore_ap()
	var first := _next_ally_to_play(0)
	if first < 0:
		# Plus un allié debout pour jouer : l'assaut l'aurait déjà vu, mais on
		# ne rouvre pas un menu sur personne.
		battle_finished.emit(false)
		_finish_battle(false)
		return
	_active_ally = first
	_legend.visible = true
	_slide_dark_bands(false)
	_open_root_menu()

## ──────────────────────────────────────────────────────────────────────────
##  FIN DE COMBAT
## ──────────────────────────────────────────────────────────────────────────

## L'ÉTAT EST POSÉ EN PREMIER : `_hide_interface` et la célébration passent tous
## deux par des rafraîchissements qui lisent `_state` pour décider s'ils ont le
## droit de reposer une planche ou une teinte. Les appeler avant le basculement
## reviendrait à leur faire écraser ce qu'on vient de mettre en place.
func _finish_battle(victory: bool) -> void:
	_state = State.FINISHED
	_can_exit = victory
	_hide_interface()
	if victory:
		_play_victory()
	else:
		_show_game_over()

## HUD et menus disparaissent dans LES DEUX cas : ils proposent des choix qu'on
## ne peut plus faire. Désactivés autant que masqués — un composant invisible
## qui écoute encore les touches consommerait la validation de sortie.
func _hide_interface() -> void:
	_menu.active = false
	_menu.visible = false
	_sublist.active = false
	_sublist.visible = false
	_target_selector.close()
	_description.visible = false
	_hud.visible = false
	_menu_frame.visible = false
	_legend.visible = false
	_rhythm.rest()
	_banner.hide_action()

## Célébration : chaque allié joue sa planche de victoire, les tombés étant
## d'abord ranimés. La séquence est PAR PERSONNAGE et non globale — les deux
## planches n'ont pas la même longueur (17 frames pour Noah, 34 pour Iris), les
## attendre ensemble ferait patienter le premier arrivé sur sa dernière image.
func _play_victory() -> void:
	# La voix part AVANT la boucle, qui ranime les tombés : un allié qu'on vient
	# de ramasser n'a pas à lancer « c'était facile ».
	_play_unit_sound(_victory_speaker(), SOUND_VICTORY)
	for i in mini(_ally_sprites.size(), _ally_units.size()):
		var unit := _ally_units[i]
		var sprite: UnitSprite = _ally_sprites[i]
		if unit.is_alive():
			sprite.modulate = Color.WHITE
		else:
			unit.heal(REVIVE_HP)
			create_tween().tween_property(sprite, "modulate", Color.WHITE, REVIVE_FADE)
			# Un allié qui tient une planche de MORT ne s'est pas effacé : il
			# faut le relever explicitement, sinon il fêterait la victoire
			# couché — et resterait ainsi s'il n'a pas de planche de victoire.
			sprite.play_sheet(BattleData.get_animation(_allies[i], ANIM_IDLE))
		_play_win(sprite, _allies[i])
	_refresh_allies()

## L'allié qui commente la victoire, ou null si l'équipe l'a emportée à terre.
##
## UN SEUL PARLE, tiré au sort parmi ceux qui tiennent encore debout. Les faire
## tous crier ensemble superposerait deux voix sur la même seconde — c'est déjà
## la raison pour laquelle une attaque de groupe ne joue qu'UN cri et non un par
## cible (cf. le `_cue` unique de BattleAssault). Le tirage, lui, évite la même
## réplique à chaque combat gagné, comme pour les variantes de `hurt`.
##
## Personne debout et pourtant la victoire : le cas existe, une blessure peut
## emporter le dernier ennemi et le dernier allié dans le même souffle. On se
## tait plutôt que de choisir un mort.
func _victory_speaker() -> BattleUnit:
	var standing: Array[BattleUnit] = []
	for unit: BattleUnit in _ally_units:
		if unit.is_alive():
			standing.append(unit)
	if standing.is_empty():
		return null
	return standing[randi() % standing.size()]

## `win_before` une fois, puis `win` en boucle. L'attente se déduit de la
## planche (`duration_of`) plutôt que d'un `animation_finished` : l'écran de
## debug tourne à une cadence irrégulière, une attente en secondes est
## reproductible là où un comptage de frames ne l'est pas.
func _play_win(sprite: UnitSprite, unit_id: String) -> void:
	var intro := BattleData.get_animation(unit_id, ANIM_WIN_BEFORE)
	var hold := BattleData.get_animation(unit_id, ANIM_WIN)
	if not intro.is_empty():
		sprite.play_sheet(intro)
		await get_tree().create_timer(UnitSprite.duration_of(intro)).timeout
	if not hold.is_empty():
		sprite.play_sheet(hold)

## Écran de défaite. Le voile et le libellé sont montés DANS le Stage et après
## tout le reste : un CanvasItem se dessine dans l'ordre de l'arbre, ils
## recouvrent donc décor, combattants et bandes noires sans avoir à toucher au
## z-index de qui que ce soit. Le fond capturé, posé hors du Stage, passe
## dessous pour la même raison.
func _show_game_over() -> void:
	var veil := ColorRect.new()
	veil.color = Color.BLACK
	veil.size = Vector2(DESIGN_SIZE)
	stage.add_child(veil)
	# Sans contour ni ombre, contrairement au reste du texte de combat : les deux
	# servent à détacher un libellé d'un décor chargé, et il n'y a ici que du
	# noir. Le brun du contour ne ferait que salir le blanc demandé.
	var label := BattleText.make(
		"", GAME_OVER_SIZE, Color.WHITE, 0, BattleText.UI_OUTLINE_COLOR, false
	)
	label.size.x = DESIGN_SIZE.x * BattleText.SUPERSAMPLE
	BattleText.set_centered_text(label, Localization.get_text("battle.game_over"))
	label.position = Vector2(0, GAME_OVER_Y)
	stage.add_child(label)

## La pastille de l'action retenue est posée à partir de la transformation du
## TERRAIN. Tant que le cadrage l'anime, elle doit donc être reposée à chaque
## image : calculée une seule fois au changement de cible, elle se fige sur la
## position d'où la cible vient de partir et n'y revient jamais — c'est ce qui
## l'envoyait sur le HUD en visant l'ennemi du fond.
func _process(_delta: float) -> void:
	if _state != State.TARGETING:
		return
	if _field_tween != null and _field_tween.is_valid():
		_follow_target()

## Seule touche encore écoutée une fois le combat joué. Les composants de
## préparation sont désactivés plus haut, la validation arrive donc bien ici.
func _unhandled_input(event: InputEvent) -> void:
	if _state != State.FINISHED or not _can_exit:
		return
	if event.is_action_pressed("battle_confirm"):
		get_viewport().set_input_as_handled()
		exit_requested.emit()

func _planned_actions() -> Array:
	var actions: Array = []
	for unit in _ally_units:
		if unit.has_action():
			actions.append(unit.action)
	return actions

## Libellé de la touche « cercle » au menu racine. Le premier allié à jouer n'a
## rien à défaire : l'invite est alors MASQUÉE plutôt qu'affichée sans effet —
## c'est ce que montre déjà mockup_preparation.png, où la légende du tour de
## Noah ne porte que « Confirm ».
func _root_cancel_prompt() -> String:
	return PROMPT_CANCEL if _previous_acted_ally() >= 0 else ""

func _active_unit() -> BattleUnit:
	if _active_ally >= _ally_units.size():
		return null
	return _ally_units[_active_ally]

## `text_id` vide masque l'invite entière (icône comprise). Sinon le groupe est
## reconstruit aligné à droite sur LEGEND_CANCEL_RIGHT.
func _set_legend_cancel(text_id: String) -> void:
	var shown := text_id != ""
	_legend_cancel_icon.visible = shown
	_legend_cancel_label.visible = shown
	if not shown:
		return
	var text := Localization.get_text(text_id)
	var icon_x := LEGEND_CANCEL_RIGHT - BattleText.text_width(text, LEGEND_TEXT_SIZE) - LEGEND_TEXT_OFFSET.x
	_legend_cancel_icon.position = Vector2(roundf(icon_x), LEGEND_ICON_Y)
	_legend_cancel_label.text = text
	_legend_cancel_label.position = _legend_cancel_icon.position + LEGEND_TEXT_OFFSET

func _build_legend() -> void:
	var legend := _tilted_group(LEGEND_PIVOT, LEGEND_TILT_DEG)
	_legend = legend

	# SVG déjà à la résolution de l'écran : pas d'agrandissement à faire.
	# L'invite « cercle » est posée par _set_legend_cancel, qui l'aligne à
	# droite sur son libellé ; celle de « croix » ne bouge jamais.
	_legend_cancel_icon = PixelScale.sprite_native(MINI_CIRCLE)
	legend.add_child(_legend_cancel_icon)
	_legend_cancel_label = BattleText.make("", LEGEND_TEXT_SIZE, Color(1, 1, 1))
	legend.add_child(_legend_cancel_label)
	_set_legend_cancel(_root_cancel_prompt())

	var confirm_icon: Sprite2D = PixelScale.sprite_native(MINI_CROSS)
	confirm_icon.position = LEGEND_CONFIRM_ICON
	legend.add_child(confirm_icon)
	var confirm_label: RichTextLabel = BattleText.make(
		Localization.get_text("battle.prompt.confirm"), LEGEND_TEXT_SIZE, Color(1, 1, 1)
	)
	confirm_label.position = LEGEND_CONFIRM_ICON + LEGEND_TEXT_OFFSET
	legend.add_child(confirm_label)
