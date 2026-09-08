extends CanvasLayer

## Écran de combat — phase de préparation (Lot 1 : rendu seul, pas de logique).
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
const BattleData = preload("res://Scripts/Battle/BattleData.gd")
const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")
const CanvasZoom = preload("res://Scripts/UI/CanvasZoom.gd")

const DARK_LINES := preload("res://Sprites/Battle/dark_lines.png")
const PLATFORM := preload("res://Sprites/Battle/platform_grass.png")
const MINI_CIRCLE := preload("res://UI/Battle/mini_btn_circle.svg")
const MINI_CROSS := preload("res://UI/Battle/mini_btn_cross.svg")

const DESIGN_SIZE := Vector2i(480, 270)
const STAGE_SCALE := 4

## Bandes noires. La texture est la même pour les deux : celle du haut est
## retournée verticalement. Elle déborde volontairement de l'écran (en négatif
## en haut, sous 270 en bas) — seule la courbe compte, le reste est du noir
## plein.
const DARK_LINE_TOP := Vector2(0, -64)
const DARK_LINE_BOTTOM := Vector2(0, 224)

## Les deux moitiés se recouvrent de 2 px (41→240 et 239→438) : le
## chevauchement est voulu, il évite une couture visible au centre.
const PLATFORM_LEFT := Vector2(41, 130)
const PLATFORM_RIGHT := Vector2(239, 130)

## Emplacements de combat : point « pieds » de chaque unité (cf. UnitSprite).
## Décrire un emplacement par un point au sol plutôt que par le coin de la
## texture permet d'y placer n'importe quel personnage, quelle que soit la
## taille de sa cellule.
const ENEMY_SLOTS: Array[Vector2i] = [
	Vector2i(103, 178), Vector2i(149, 150), Vector2i(195, 169)
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
const HUD_TILT_DEG := -4.2
const HUD_PIVOT := Vector2(304, 21)
const LEGEND_TILT_DEG := -5.5
const LEGEND_PIVOT := Vector2(333, 232)

const LEGEND_CANCEL_ICON := Vector2(333, 232)
const LEGEND_CONFIRM_ICON := Vector2(401, 232)
const LEGEND_TEXT_OFFSET := Vector2(19, -1)
const LEGEND_TEXT_SIZE := 15

const MENU_ENTRIES: PackedStringArray = [
	"battle.menu.attack", "battle.menu.eko", "battle.menu.items", "battle.menu.guard",
]

## Composition par défaut, utilisée quand la scène est lancée seule (F6) sans
## passer par setup(). Elle reproduit le mockup.
const DEFAULT_ENEMIES: PackedStringArray = ["cactoon", "cactoon", "cactoon"]
const DEFAULT_ALLIES: PackedStringArray = ["noah", "iris"]

@onready var background: Sprite2D = $Background
@onready var background_dim: ColorRect = $BackgroundDim
@onready var stage: Node2D = $Stage

var _enemies: PackedStringArray = DEFAULT_ENEMIES
var _allies: PackedStringArray = DEFAULT_ALLIES
var _status_panels: Array[Node2D] = []
var _menu: Node2D
var _pending_background: Texture2D

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
	_build_decor()
	_build_units()
	_build_hud()

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
	background.scale = Vector2(DESIGN_SIZE * STAGE_SCALE) / _pending_background.get_size()
	# Rééchantillonnage non entier (1676 → 1920) : le filtrage linéaire donne un
	# fond propre, là où le "nearest" hérité du projet doublerait irrégulièrement
	# une colonne sur sept. C'est une photo floutée derrière un voile noir, pas
	# de la pixel-art à préserver.
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _build_decor() -> void:
	var bottom := Sprite2D.new()
	bottom.texture = DARK_LINES
	bottom.centered = false
	bottom.position = DARK_LINE_BOTTOM
	stage.add_child(bottom)

	var top := Sprite2D.new()
	top.texture = DARK_LINES
	top.centered = false
	top.flip_v = true
	top.position = DARK_LINE_TOP
	stage.add_child(top)

	for entry in [[PLATFORM_LEFT, false], [PLATFORM_RIGHT, true]]:
		var half := Sprite2D.new()
		half.texture = PLATFORM
		half.centered = false
		half.flip_h = entry[1]
		half.position = entry[0]
		stage.add_child(half)

func _build_units() -> void:
	# Un conteneur en Y-sort plutôt que des z_index posés à la main : la
	# profondeur découle alors du point « pieds » de chaque unité, donc des
	# données d'emplacement, et reste juste si on ajoute ou déplace une unité.
	var units := Node2D.new()
	units.y_sort_enabled = true
	stage.add_child(units)

	for i in mini(_enemies.size(), ENEMY_SLOTS.size()):
		# Les ennemis sont retournés horizontalement : la planche les dessine
		# tournés dans l'autre sens (vérifié au pixel près sur le mockup).
		#
		# Aucun décalage de phase entre eux : sur le mockup les trois cactoons
		# sont exactement sur la même frame. UnitSprite.offset_phase() reste
		# disponible si on décide plus tard de les désynchroniser.
		_spawn_unit(units, _enemies[i], ENEMY_SLOTS[i], true)
	for i in mini(_allies.size(), ALLY_SLOTS.size()):
		_spawn_unit(units, _allies[i], ALLY_SLOTS[i], false)

func _spawn_unit(parent: Node2D, unit_id: String, feet: Vector2i, mirrored: bool) -> void:
	var config: Dictionary = BattleData.get_animation(unit_id, "idle")
	if config.is_empty():
		return
	var sprite: AnimatedSprite2D = UnitSprite.new()
	parent.add_child(sprite)
	sprite.setup(config, feet, mirrored)

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
	for i in mini(_allies.size(), STATUS_PANEL_POS.size()):
		var panel: Node2D = UnitStatusPanel.new()
		panel.position = Vector2(STATUS_PANEL_POS[i])
		hud.add_child(panel)
		panel.setup(_allies[i])
		# Lot 1 : le premier allié est arbitrairement l'allié actif, comme sur
		# le mockup. C'est la boucle de préparation (Lot 5) qui pilotera ça.
		panel.set_active(i == 0)
		# Idem : les PA courants reproduisent l'état du mockup (un point
		# dépensé chacun) pour pouvoir comparer les deux images. Ce sont des
		# valeurs de présentation, pas une règle de jeu.
		var ap_max: int = int(BattleData.get_unit(_allies[i]).get("stats", {}).get("ap_max", 0))
		panel.set_ap(maxi(0, ap_max - 1), ap_max)
		_status_panels.append(panel)

	var synergy: Node2D = SynergyGauge.new()
	synergy.position = SYNERGY_POS
	hud.add_child(synergy)
	# Charge de présentation, alignée sur le mockup (Lot 8 pilotera la vraie).
	synergy.set_charge(0, 0.72)

	var synergy_label: RichTextLabel = BattleText.make(
		"SYN", SYNERGY_LABEL_SIZE, SYNERGY_LABEL_COLOR
	)
	synergy_label.position = SYNERGY_LABEL_POS
	hud.add_child(synergy_label)

	_menu = CommandMenu.new() as Node2D
	_tilted_group(MENU_PIVOT, MENU_TILT_DEG).add_child(_menu)
	_menu.setup(MENU_ENTRIES, 1)

	_build_legend()

func _build_legend() -> void:
	var legend := _tilted_group(LEGEND_PIVOT, LEGEND_TILT_DEG)
	for entry in [
		[MINI_CIRCLE, LEGEND_CANCEL_ICON, "battle.prompt.cancel"],
		[MINI_CROSS, LEGEND_CONFIRM_ICON, "battle.prompt.confirm"],
	]:
		# SVG déjà à la résolution de l'écran : pas d'agrandissement à faire.
		var icon: Sprite2D = PixelScale.sprite_native(entry[0])
		icon.position = entry[1]
		legend.add_child(icon)

		var label: RichTextLabel = BattleText.make(
			Localization.get_text(entry[2]), LEGEND_TEXT_SIZE, Color(1, 1, 1)
		)
		label.position = entry[1] + LEGEND_TEXT_OFFSET
		legend.add_child(label)
