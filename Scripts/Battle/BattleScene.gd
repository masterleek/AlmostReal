extends CanvasLayer

## Écran de combat — phase de préparation. Le rendu est complet (Lot 1), le
## menu racine est navigable (Lot 2) et « Attack » ouvre le choix d'une cible
## (Lot 3) ; valider une cible ne met encore aucune action en file, c'est la
## boucle de préparation (Lot 5) qui la consommera.
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
const BattleUnit = preload("res://Scripts/Battle/BattleUnit.gd")
const BattleData = preload("res://Scripts/Battle/BattleData.gd")
const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")
const CanvasZoom = preload("res://Scripts/UI/CanvasZoom.gd")

const DARK_LINES := preload("res://Sprites/Battle/dark_lines.png")
const PLATFORM := preload("res://Sprites/Battle/platform_grass.png")
const MINI_CIRCLE := preload("res://UI/Battle/mini_btn_circle.svg")
const MINI_CROSS := preload("res://UI/Battle/mini_btn_cross.svg")

const SFX_MOVE := preload("res://Audio/move.wav")
const SFX_CONFIRM := preload("res://Audio/validation.wav")
const SFX_CANCEL := preload("res://Audio/error.wav")

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

## Seul « Attack » est nommé : c'est la seule entrée dont le code doit
## reconnaître l'id (elle ouvre le ciblage). Les trois autres n'ont pas encore
## d'action, les nommer d'avance ne servirait à rien.
const MENU_ATTACK := "battle.menu.attack"
const MENU_ENTRIES: PackedStringArray = [
	MENU_ATTACK, "battle.menu.eko", "battle.menu.items", "battle.menu.guard",
]

## Libellé de la touche « cercle » de la légende pendant le ciblage. Au menu
## racine l'invite est absente des maquettes (cf. _close_targeting).
const PROMPT_BACK := "battle.prompt.back"

## Position de la pastille de l'action retenue pendant le ciblage, en décalage
## depuis le point « pieds » de la cible. Réglée par recalage du rendu sur la
## deuxième vignette de mockup_preparation_select_attack.png, la cible y étant
## l'ennemi de l'emplacement 2 (pieds en 195, 169).
##
## Ce décalage est en coordonnées d'ÉCRAN ; le menu étant incliné, il faut le
## repasser dans son repère (cf. _menu_local).
const FOCUS_PILL_OFFSET := Vector2(23, -87)

## Composition par défaut, utilisée quand la scène est lancée seule (F6) sans
## passer par setup(). Elle reproduit le mockup.
const DEFAULT_ENEMIES: PackedStringArray = ["cactoon", "cactoon", "cactoon"]
const DEFAULT_ALLIES: PackedStringArray = ["noah", "iris"]

@onready var background: Sprite2D = $Background
@onready var background_dim: ColorRect = $BackgroundDim
@onready var stage: Node2D = $Stage

## Qui a la main sur les entrées. Le menu racine reste monté pendant le
## ciblage (il faut y revenir sur « Back », et sa pastille reste affichée à
## côté de la cible) : c'est le drapeau `active` de chaque composant, arbitré
## ici, qui décide lequel des deux écoute.
enum State { MENU, TARGETING }

var _enemies: PackedStringArray = DEFAULT_ENEMIES
var _allies: PackedStringArray = DEFAULT_ALLIES
var _status_panels: Array[Node2D] = []
var _menu: CommandMenu
var _state: State = State.MENU
## Les sprites d'ennemis sont CONSERVÉS : le ciblage les met en surbrillance
## et s'ancre sur eux (cf. TargetSelector). Les états de combat correspondants
## vivent en parallèle, dans le même ordre.
var _enemy_sprites: Array[AnimatedSprite2D] = []
var _enemy_units: Array[BattleUnit] = []
var _target_selector: TargetSelector
var _legend_cancel_icon: Sprite2D
var _legend_cancel_label: RichTextLabel
var _pending_background: Texture2D
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
	_build_decor()
	_build_units()
	_build_targeting()
	_build_sfx()
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
		var sprite := _spawn_unit(units, _enemies[i], ENEMY_SLOTS[i], true)
		if sprite == null:
			continue
		_enemy_sprites.append(sprite)
		_enemy_units.append(BattleUnit.new(_enemies[i]))
	for i in mini(_allies.size(), ALLY_SLOTS.size()):
		_spawn_unit(units, _allies[i], ALLY_SLOTS[i], false)

func _spawn_unit(
	parent: Node2D, unit_id: String, feet: Vector2i, mirrored: bool
) -> AnimatedSprite2D:
	var config: Dictionary = BattleData.get_animation(unit_id, "idle")
	if config.is_empty():
		return null
	var sprite: AnimatedSprite2D = UnitSprite.new()
	parent.add_child(sprite)
	sprite.setup(config, feet, mirrored)
	return sprite

## Le sélecteur est posé sur le Stage APRÈS le conteneur d'unités et AVANT les
## groupes d'interface : sa plaque passe donc au-dessus des combattants, et
## sous le menu et le HUD.
##
## Son ordre dans l'arbre compte aussi pour les entrées : `_unhandled_input`
## est distribué à l'envers de l'arbre, le menu — ajouté plus tard — voit donc
## chaque touche en premier. C'est ce qui fait que la validation qui OUVRE le
## ciblage n'est pas aussitôt reconsommée par celui-ci : le menu la marque
## traitée avant que le sélecteur ne soit interrogé.
func _build_targeting() -> void:
	_target_selector = TargetSelector.new()
	stage.add_child(_target_selector)
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

	_menu = CommandMenu.new()
	_tilted_group(MENU_PIVOT, MENU_TILT_DEG).add_child(_menu)
	# Sélection par défaut sur la PREMIÈRE entrée (Attack). Le mockup fige
	# « Eko » parce qu'il illustre un état de navigation, pas l'état d'entrée.
	_menu.setup(MENU_ENTRIES, 0)
	_menu.active = true
	_menu.selection_changed.connect(_on_menu_moved)
	_menu.confirmed.connect(_on_menu_confirmed)
	_menu.cancelled.connect(_on_menu_cancelled)

	_build_legend()

## Sons repris tels quels du worldmap plutôt que dupliqués : c'est le même
## vocabulaire sonore d'un écran à l'autre (déplacement, validation, action
## impossible), cf. WorldmapCursor.move_sfx et Hero.validation_sfx/error_sfx.
func _build_sfx() -> void:
	_sfx_move = _add_sfx(SFX_MOVE)
	_sfx_confirm = _add_sfx(SFX_CONFIRM)
	_sfx_cancel = _add_sfx(SFX_CANCEL)

func _add_sfx(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player

func _on_menu_moved(_index: int) -> void:
	_sfx_move.play()

## « Attack » ouvre le choix de la cible (Lot 3). Les listes d'Ekos et
## d'objets (Lot 4) et la garde (Lot 5) viendront se brancher ici de la même
## façon ; d'ici là elles se contentent du son de validation.
func _on_menu_confirmed(id: String) -> void:
	if id == MENU_ATTACK:
		if not _open_targeting():
			# Plus rien à viser : le son d'erreur vaut mieux qu'un écran de
			# ciblage vide.
			_sfx_cancel.play()
		return
	_sfx_confirm.play()

## Au menu racine il n'y a rien à annuler. Le Lot 5 y branchera le retour au
## tour de l'allié précédent ; d'ici là le son d'erreur signale simplement que
## l'entrée n'a pas d'effet.
func _on_menu_cancelled() -> void:
	_sfx_cancel.play()

## Renvoie false si aucun ennemi n'est ciblable, auquel cas rien n'a changé.
func _open_targeting() -> bool:
	var targets: Array[Dictionary] = []
	for i in _enemy_units.size():
		if _enemy_units[i].is_alive():
			targets.append({"unit": _enemy_units[i], "sprite": _enemy_sprites[i]})
	if targets.is_empty():
		return false
	_sfx_confirm.play()
	_state = State.TARGETING
	_menu.active = false
	# Première cible vivante par défaut, comme le menu s'ouvre sur sa première
	# entrée : une sélection par défaut stable vaut mieux qu'une sélection
	# « intelligente » qui changerait d'un tour à l'autre.
	_target_selector.open(targets)
	_follow_target()
	_set_legend_cancel(PROMPT_BACK)
	return true

func _close_targeting() -> void:
	_target_selector.close()
	_menu.restore()
	_state = State.MENU
	_menu.active = true
	# Rien à annuler au menu racine tant qu'un seul allié y passe : la maquette
	# n'y affiche aucune invite « cercle ». Le Lot 5 la fera réapparaître avec
	# le libellé `battle.prompt.cancel`, pour revenir au tour de l'allié
	# précédent.
	_set_legend_cancel("")

## Réduit le menu à l'action retenue et la pose près de la cible courante.
func _follow_target() -> void:
	_menu.focus_selection(
		_menu_local(_target_selector.get_selected_feet() + FOCUS_PILL_OFFSET)
	)

## Convertit un point de l'écran vers le repère interne du menu, qui est
## incliné. Les positions de pastilles y sont exprimées « à plat » (cf. la note
## sur l'inclinaison plus haut) : sans cette conversion, une position lue sur
## le terrain subirait l'inclinaison une seconde fois.
func _menu_local(point: Vector2) -> Vector2:
	return (point - MENU_PIVOT).rotated(-deg_to_rad(MENU_TILT_DEG)) + MENU_PIVOT

func _on_target_moved(_index: int) -> void:
	_sfx_move.play()
	_follow_target()

## Lot 3 : valider une cible ne fait que confirmer le choix — il n'y a pas
## encore de file d'actions où le déposer, c'est le Lot 5 qui l'introduira. On
## revient donc au menu, ce qui laisse quand même vérifier tout le trajet
## aller-retour.
func _on_target_confirmed(_index: int) -> void:
	_sfx_confirm.play()
	_close_targeting()

func _on_target_cancelled() -> void:
	_sfx_cancel.play()
	_close_targeting()

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

	# SVG déjà à la résolution de l'écran : pas d'agrandissement à faire.
	# L'invite « cercle » est posée par _set_legend_cancel, qui l'aligne à
	# droite sur son libellé ; celle de « croix » ne bouge jamais.
	_legend_cancel_icon = PixelScale.sprite_native(MINI_CIRCLE)
	legend.add_child(_legend_cancel_icon)
	_legend_cancel_label = BattleText.make("", LEGEND_TEXT_SIZE, Color(1, 1, 1))
	legend.add_child(_legend_cancel_label)
	_set_legend_cancel("")

	var confirm_icon: Sprite2D = PixelScale.sprite_native(MINI_CROSS)
	confirm_icon.position = LEGEND_CONFIRM_ICON
	legend.add_child(confirm_icon)
	var confirm_label: RichTextLabel = BattleText.make(
		Localization.get_text("battle.prompt.confirm"), LEGEND_TEXT_SIZE, Color(1, 1, 1)
	)
	confirm_label.position = LEGEND_CONFIRM_ICON + LEGEND_TEXT_OFFSET
	legend.add_child(confirm_label)
