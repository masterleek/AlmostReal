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

## Les trois entrées qui ouvrent quelque chose sont nommées, parce que le code
## doit reconnaître leur id. « Guard » ne l'est pas : elle n'a pas encore
## d'action (Lot 5), la nommer d'avance ne servirait à rien.
const MENU_ATTACK := "battle.menu.attack"
const MENU_EKO := "battle.menu.eko"
const MENU_ITEMS := "battle.menu.items"
const MENU_ENTRIES: PackedStringArray = [
	MENU_ATTACK, MENU_EKO, MENU_ITEMS, "battle.menu.guard",
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
const DESCRIPTION_POS := Vector2(213, 159)

## Opacité des combattants qu'on ne regarde pas. L'allié dont c'est le tour y
## échappe toujours ; pour les autres, cela dépend de l'écran :
##   - dans une liste d'actions, TOUT LE MONDE s'efface — elle descend jusqu'à
##     sept rangées et passe alors devant le terrain ;
##   - pendant le ciblage, seul le camp VISÉ garde son opacité, l'autre
##     s'efface : en visant un ennemi, les alliés passent à 30 %.
const INACTIVE_UNIT_ALPHA := 0.3

## Modes de ciblage qui retiennent tout un camp d'un bloc, sans choix
## individuel (cf. TargetSelector). « self » en fait partie : il n'y a rien à
## choisir, mais la cible s'allume quand même pour dire sur qui ça porte.
const GROUP_TARGETS: PackedStringArray = ["enemies", "allies", "self"]

## Modes de ciblage qui désignent le camp allié.
const ALLY_TARGETS: PackedStringArray = ["ally", "allies", "self"]

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
const FOCUS_PILL_OFFSET := Vector2(23, -87)

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
enum State { MENU, SUBLIST, TARGETING }

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
var _ally_sprites: Array[AnimatedSprite2D] = []
var _ally_units: Array[BattleUnit] = []
## Allié dont c'est le tour. Figé sur le premier tant que la boucle de tour
## (Lot 5) n'existe pas.
var _active_ally: int = 0
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
		var ally := _spawn_unit(units, _allies[i], ALLY_SLOTS[i], false)
		if ally == null:
			continue
		_ally_sprites.append(ally)
		_ally_units.append(BattleUnit.new(_allies[i]))

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
		panel.set_active(i == _active_ally)
		# Les PA affichés sont désormais les PA RÉELS de l'unité (Lot 4), plus
		# la valeur de présentation calquée sur le mockup. L'écart est voulu :
		# la maquette montre un tour déjà entamé, alors qu'un combat commence
		# avec les jauges pleines.
		_status_panels.append(panel)
	_refresh_ap()

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
	_menu.tilt_pivot = MENU_PIVOT
	_menu.tilt_degrees = MENU_TILT_DEG
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

## Le menu racine n'a ni coût ni description : ses entrées se réduisent à leur
## id, qui sert aussi de libellé.
func _root_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id in MENU_ENTRIES:
		entries.append({"id": id, "text_id": id})
	return entries

func _refresh_ap() -> void:
	for i in mini(_status_panels.size(), _ally_units.size()):
		_status_panels[i].set_ap(_ally_units[i].ap, _ally_units[i].ap_max)

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

## « Attack » vise directement un ennemi ; « Eko » et « Items » passent d'abord
## par leur sous-liste. « Guard » n'a pas encore d'action (Lot 5), elle se
## contente du son de validation.
func _on_menu_confirmed(id: String) -> void:
	match id:
		MENU_ATTACK:
			_start_action({"source": "attack", "target": "enemy"}, _menu)
		MENU_EKO:
			_open_sublist("eko", _eko_entries())
		MENU_ITEMS:
			_open_sublist("item", _item_entries())
		_:
			_sfx_confirm.play()

## Au menu racine il n'y a rien à annuler. Le Lot 5 y branchera le retour au
## tour de l'allié précédent ; d'ici là le son d'erreur signale simplement que
## l'entrée n'a pas d'effet.
func _on_menu_cancelled() -> void:
	_sfx_cancel.play()

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
			"type": int(eko.get("type", 1)),
		})
	return entries

## Un objet ne coûte pas de PA : la colonne de droite y affiche la QUANTITÉ en
## réserve à la place des losanges.
func _item_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in DEFAULT_INVENTORY:
		entries.append({
			"id": id,
			"text_id": "item.%s.name" % id,
			"quantity": int(DEFAULT_INVENTORY[id]),
			"type": int(BattleData.get_item(id).get("type", 1)),
		})
	return entries

func _open_sublist(kind: String, entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		# Aucun Eko connu, ou sac vide : mieux vaut le son d'erreur qu'une
		# liste vide où la touche « Back » serait la seule issue.
		_sfx_cancel.play()
		return
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

func _close_sublist() -> void:
	_set_units_dimmed(false, false)
	_sublist.active = false
	_sublist.visible = false
	_sublist.restore()
	_description.visible = false
	_menu.visible = true
	_menu.active = true
	_state = State.MENU
	_set_legend_cancel(PROMPT_CANCEL)

func _show_description(id: String) -> void:
	if id == "":
		_description.visible = false
		return
	_description.show_text("%s.%s.desc" % [_sublist_kind, id])

func _on_sublist_moved(_index: int) -> void:
	_sfx_move.play()
	_show_description(_sublist.get_selected_id())

func _on_sublist_confirmed(id: String) -> void:
	var definition: Dictionary = (
		BattleData.get_eko(id) if _sublist_kind == "eko" else BattleData.get_item(id)
	)
	var cost: int = int(definition.get("ap_cost", 0))
	var unit := _active_unit()
	# Deux refus différents selon la liste : un Eko demande des PA, un objet
	# demande d'en avoir encore en réserve. Dans les deux cas la ligne le disait
	# déjà — losanges éteints ou « x0 » — le son ne fait que confirmer.
	var available := (
		int(DEFAULT_INVENTORY.get(id, 0)) > 0 if _sublist_kind == "item"
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

func _start_action(pending: Dictionary, list: CommandMenu) -> void:
	if not _open_targeting(pending, list):
		# Plus rien à viser : le son d'erreur vaut mieux qu'un écran de ciblage
		# vide.
		_sfx_cancel.play()

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
	var aims_at_allies := kind in ALLY_TARGETS
	_set_units_dimmed(aims_at_allies, not aims_at_allies)
	# Première cible vivante par défaut, comme les listes s'ouvrent sur leur
	# première entrée : une sélection par défaut stable vaut mieux qu'une
	# sélection « intelligente » qui changerait d'un tour à l'autre.
	_target_selector.open(targets, kind in GROUP_TARGETS)
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
func _follow_target() -> void:
	_focus_list.focus_selection(
		_focus_list.to_flat(_target_selector.get_selected_feet() + FOCUS_PILL_OFFSET)
	)

func _on_target_moved(_index: int) -> void:
	_sfx_move.play()
	_follow_target()

## Lot 4 : valider une cible ne fait toujours que confirmer le choix — il n'y a
## pas encore de file d'actions où le déposer, c'est le Lot 5 qui l'introduira.
## On remonte donc jusqu'au menu racine, ce qui laisse vérifier tout le trajet.
func _on_target_confirmed(_index: int) -> void:
	_sfx_confirm.play()
	_target_selector.close()
	_focus_list.restore()
	_pending = {}
	_close_sublist()

## « Back » ramène d'où l'on vient : au menu racine pour une attaque, à la
## sous-liste pour un Eko ou un objet.
func _on_target_cancelled() -> void:
	_sfx_cancel.play()
	_target_selector.close()
	_focus_list.restore()
	var from_sublist := String(_pending.get("source", "attack")) != "attack"
	_pending = {}
	if not from_sublist:
		_close_sublist()
		return
	_state = State.SUBLIST
	_sublist.active = true
	_description.visible = true
	_set_units_dimmed(true, true)
	_set_legend_cancel(PROMPT_BACK)

## Estompe chaque camp indépendamment. L'allié dont c'est le tour n'est jamais
## estompé : c'est lui qui agit, il doit rester lisible.
func _set_units_dimmed(dim_enemies: bool, dim_allies: bool) -> void:
	for sprite in _enemy_sprites:
		sprite.modulate.a = INACTIVE_UNIT_ALPHA if dim_enemies else 1.0
	for i in _ally_sprites.size():
		var faded := dim_allies and i != _active_ally
		_ally_sprites[i].modulate.a = INACTIVE_UNIT_ALPHA if faded else 1.0

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

	# SVG déjà à la résolution de l'écran : pas d'agrandissement à faire.
	# L'invite « cercle » est posée par _set_legend_cancel, qui l'aligne à
	# droite sur son libellé ; celle de « croix » ne bouge jamais.
	_legend_cancel_icon = PixelScale.sprite_native(MINI_CIRCLE)
	legend.add_child(_legend_cancel_icon)
	_legend_cancel_label = BattleText.make("", LEGEND_TEXT_SIZE, Color(1, 1, 1))
	legend.add_child(_legend_cancel_label)
	_set_legend_cancel(PROMPT_CANCEL)

	var confirm_icon: Sprite2D = PixelScale.sprite_native(MINI_CROSS)
	confirm_icon.position = LEGEND_CONFIRM_ICON
	legend.add_child(confirm_icon)
	var confirm_label: RichTextLabel = BattleText.make(
		Localization.get_text("battle.prompt.confirm"), LEGEND_TEXT_SIZE, Color(1, 1, 1)
	)
	confirm_label.position = LEGEND_CONFIRM_ICON + LEGEND_TEXT_OFFSET
	legend.add_child(confirm_label)
