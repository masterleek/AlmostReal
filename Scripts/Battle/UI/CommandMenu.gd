extends Node2D

## Liste de commandes en pastilles (Attack / Eko / Items / Guard, puis les
## listes d'Ekos et d'objets).
##
## Volontairement générique : c'est le même composant qui sert au menu racine
## et aux sous-listes, qui n'en diffèrent que par le nombre d'entrées, la
## présence d'un coût en PA et d'un défilement. Une seule implémentation
## paramétrée, pas trois copies.
##
## DEUX DISPOSITIONS, relevées sur deux maquettes différentes (cf. Layout) :
## le menu racine est une colonne en bas à droite, la liste d'Ekos et d'objets
## est un ESCALIER en haut à gauche — chaque rangée y est décalée vers la
## droite. Les entrées qui ne tiennent pas dans la fenêtre défilent.
##
## INCLINAISON — les deux dispositions ne l'obtiennent pas de la même façon.
## Le menu racine vit dans un groupe incliné en bloc (cf. BattleScene). La
## liste, elle, incline CHAQUE RANGÉE sur elle-même : sur la maquette, le bord
## supérieur d'une pastille descend bien de 3°, mais l'écart d'une rangée à la
## suivante vaut exactement (10, 15) — le décalage à plat — là où une rotation
## d'ensemble donnerait (10,77 ; 14,46). C'est ce qui explique que les icônes
## de type paraissaient dériver : elles suivaient une inclinaison de groupe que
## la maquette n'applique pas.
##
## Géométrie relevée sur mockup_preparation.png : pastilles de 78×18 empilées
## au pas de 16 — soit un chevauchement de 2 px, qui fait que les extrémités
## arrondies s'emboîtent au lieu de laisser un liseré. L'entrée sélectionnée
## est décalée de 17 px vers la GAUCHE, à largeur identique : c'est le seul
## effet de la sélection sur la géométrie.

## `selection_changed` ne part que sur un CHANGEMENT réel d'entrée : c'est lui
## qui déclenche le son de navigation, il ne doit donc pas sonner au montage de
## la liste ni sur une sélection déjà en place.
signal selection_changed(index: int)
signal confirmed(id: String)
signal cancelled

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")
const ApDots = preload("res://Scripts/Battle/UI/ApDots.gd")

const OFF := preload("res://UI/Battle/command_off.svg")
const ON := preload("res://UI/Battle/command_on.svg")

## Curseur de sélection : c'est le MÊME asset que le curseur du worldmap,
## pivoté d'un quart de tour pour pointer vers la gauche (vérifié par recalage
## sur le mockup : l'erreur tombe à 38 dans cette orientation, contre 86 à 96
## pour les trois autres). On le partage plutôt que d'en dupliquer une variante
## — le jeu n'a qu'un curseur, il doit rester cohérent d'un écran à l'autre.
const CURSOR := preload("res://UI/cursor_worldmap.png")
## Depuis le bord DROIT de la pastille, pour valoir quelle que soit sa largeur.
const CURSOR_OFFSET := Vector2(1, -1)

## CIBLAGE. Pendant le choix d'une cible, la liste se réduit à l'entrée
## retenue, qui va se poser près de la cible (cf. focus_selection). La maquette
## mockup_preparation_select_attack montre alors « Attack » seul, curseur à sa
## GAUCHE et incliné vers la cible — soit le même asset tourné autrement, pas
## une seconde version du curseur.
##
## Le décalage et l'angle sont relevés sur cette maquette : curseur ajusté à
## 30° dans le repère de l'écran (résidu minimal sur un balayage de 25° à 40°),
## donc 33° ici puisque le menu est déjà incliné de −3°.
const CURSOR_FOCUS_OFFSET := Vector2(-13, -6)
const CURSOR_FOCUS_ROTATION_DEG := 33.0

## MENU RACINE — relevé sur mockup_preparation.png (Lot 1).
##
## Y_FIRST est décalé de 2 px par rapport au recalage initial : celui-ci avait
## été fait avec un gabarit horizontal sur une maquette inclinée, ce qui
## biaisait le résultat vers le haut. Vérifié après coup en ajustant le bord
## supérieur de la pastille « Attack » sur les deux images.
const X_NORMAL := 280
const X_SELECTED := 263
const Y_FIRST := 165
const PITCH := 16
const WIDTH := 78
## Quatre rangées : la bande va de Y_FIRST (165) à 229, et la légende
## commence à 230.
const MAX_VISIBLE := 4

## LISTE D'EKOS / D'OBJETS — relevé sur mockup_preparation_select_eko.jpg.
##
## Rien de commun avec le menu racine sauf la hauteur de pastille et
## l'inclinaison : la liste est en haut à GAUCHE, ses pastilles font 123 px de
## large au lieu de 78, et chaque rangée descend de 15 px en se décalant de
## 10 px vers la droite — les trois entrées de la maquette forment un escalier
## dont les libellés commencent à 121, 131 et 141.
##
## L'entrée sélectionnée n'est PAS décalée horizontalement (contrairement au
## menu racine, où elle avance de 17 px) : sur la maquette, les trois bords
## gauches sont exactement sur la diagonale de l'escalier. Elle se distingue
## par sa seule couleur.
## L'ordonnée est calée sur le TEXTE (première ligne à 46 sur la maquette), pas
## sur le bord de la pastille : celle-ci est inclinée, son bout droit remonte
## de 6 px sur 123, et son contour flou par-dessus. Le texte, lui, se mesure
## sans ambiguïté.
const LIST_ORIGIN := Vector2(103, 45)
const LIST_STEP := Vector2(10, 15)
const LIST_WIDTH := 123
## Le libellé est retiré de 18 px et non de 6 : la place à gauche revient à
## l'icône d'élément de l'Eko (le petit disque bleu de la maquette), qui
## n'existe pas encore comme asset.
const LIST_TEXT_DX := 18
## Inclinaison appliquée à chaque rangée, autour de son propre coin.
const LIST_ROW_TILT_DEG := -3.0
## Sept rangées, relevé sur menu_long_list.png. La liste descend alors sur le
## terrain — c'est pour ça que les unités passent à 30 % d'opacité pendant le
## choix d'une action (cf. BattleScene).
const LIST_MAX_VISIBLE := 7

## Icône de type de l'action, à cheval sur le bord gauche de la pastille et
## présente sur CHAQUE rangée (cf. menu_long_list.png). Les deux variantes ne
## diffèrent que par la couleur de l'éclair — bleu pour le type 1, orange pour
## le type 2 : c'est le type de l'Eko ou de l'objet qui choisit.
const TYPE_ICONS: Array[Texture2D] = [
	preload("res://UI/Battle/ic_type_action_1.svg"),
	preload("res://UI/Battle/ic_type_action_2.svg"),
]
## Relevé sur menu_long_list.png, qui est en PNG et à l'échelle de design —
## contrairement aux maquettes de scène, en JPEG, dont la compression décale
## d'un pixel le bord des petits aplats. Rangée 0 : coin de pastille en
## (79 ; 134,1) par ajustement linéaire du bord supérieur sur vingt colonnes,
## disque de l'icône en x 83..94 et y 136..147.
const TYPE_ICON_OFFSET := Vector2(4, 1)

## Opacité des rangées de bord, de la plus extérieure vers l'intérieur. Le
## fondu ne s'applique QUE du côté où la liste continue : sur
## menu_long_list.png, la vignette « First » ne fond pas ses deux premières
## rangées et la vignette « Last » ne fond pas ses deux dernières.
const FADE: Array[float] = [0.25, 0.5]

const HEIGHT := 18

## Marges du 9-slice : seuls les deux bouts arrondis sont préservés, le centre
## s'étire. Aucune marge verticale — haut et bas de la texture couvrent déjà
## toute la hauteur, la pastille ne s'étire jamais verticalement.
const PATCH_MARGIN := 8

const TEXT_PADDING := Vector2(6, 1)
const TEXT_SIZE := 15

## Coût en PA, aligné sur le bord DROIT de la pastille (marge symétrique de
## celle du texte). Les losanges sont ceux du HUD : un coût de 2 s'affiche en
## deux losanges pleins. Quand l'unité active ne peut pas payer, ils passent en
## losanges éteints — c'est exactement le sens que l'asset a déjà sur la ligne
## de PA, et ça évite d'inventer un état « désactivé » que la maquette ne
## montre pas.
## Quantité d'un objet, à la place du coût en PA — un objet ne consomme pas de
## PA, c'est le nombre en réserve qui compte. Le nombre prend exactement la
## place des losanges qu'il remplace : même bord droit, même centre vertical
## (relevés sur menu_long_list.png). L'ordonnée est celle de la BOÎTE du
## libellé ; l'encre descend d'environ 2 px de plus.
const QUANTITY_PADDING := Vector2(5, 2)

## Coût en PA, aligné sur le bord DROIT de la pastille.
##
## Le décalage est appliqué DANS LE REPÈRE DE LA RANGÉE, pas à plat : les
## losanges se posent à une centaine de pixels du coin, là où l'inclinaison de
## 3° a remonté la surface de la pastille de près de 6 px. Posés à plat, ils
## sortaient par le bas. Relevé sur menu_long_list.png : le centre du dernier
## losange tombe à (111,9 ; 7,7) dans le repère de la rangée.
const COST_PADDING := Vector2(8, 3)
## Les losanges de coût sont plus serrés que ceux du HUD (cf. ApDots.pitch).
const COST_PITCH := 6
const TEXT_COLOR := Color8(0xE3, 0x93, 0x5B)
const TEXT_COLOR_SELECTED := Color8(0x27, 0x04, 0x00)

## Balayage lumineux de la pastille sélectionnée : le mockup en fige un
## instant (jaune plein à gauche, blanc pur à droite), ce n'est pas un dégradé
## statique à reproduire tel quel.
const SHINE_WIDTH := 46.0
const SHINE_PERIOD := 1.6

## Ne réagit aux entrées que si `active`. Plusieurs listes coexisteront à
## l'écran (menu racine + liste d'Ekos ou d'objets, cf. Lot 4) et une seule
## doit avoir la main à un instant donné : c'est l'appelant qui arbitre, la
## liste ne se donne jamais le focus d'elle-même.
var active: bool = false

## Dispositions possibles, cf. les deux blocs de constantes plus haut.
enum Layout { ROOT, LIST }

var _entries: Array[Dictionary] = []
var _selected: int = 0
## Index de la première entrée affichée (défilement).
var _first_visible: int = 0

## Géométrie courante, remplie par set_layout(). Les valeurs par défaut sont
## celles du menu racine : une liste qui ne dit rien reste le menu racine.
var _origin := Vector2(X_NORMAL, Y_FIRST)
var _step := Vector2(0, PITCH)
var _selected_dx: float = X_SELECTED - X_NORMAL
var _width: int = WIDTH
var _text_dx: float = TEXT_PADDING.x
var _max_visible: int = MAX_VISIBLE
var _typed: bool = false
var _row_tilt_deg: float = 0.0

## Inclinaison du groupe qui porte cette liste, renseignée par l'appelant.
## Sert à convertir un point de l'ÉCRAN vers le repère interne (cf. to_flat) —
## les deux listes ne pivotent pas autour du même point, la conversion ne peut
## donc pas être une constante de la scène.
var tilt_pivot := Vector2.ZERO
var tilt_degrees := 0.0

## Position, dans le repère interne, qui rend le point `point` de l'écran. Sans
## cette conversion, une position lue sur le terrain subirait l'inclinaison une
## seconde fois.
func to_flat(point: Vector2) -> Vector2:
	return (point - tilt_pivot).rotated(-deg_to_rad(tilt_degrees)) + tilt_pivot

## À appeler AVANT setup() : la disposition détermine la taille des pastilles,
## donc leur construction.
func set_layout(layout: Layout) -> void:
	match layout:
		Layout.LIST:
			_origin = LIST_ORIGIN
			_step = LIST_STEP
			_selected_dx = 0.0
			_width = LIST_WIDTH
			_text_dx = LIST_TEXT_DX
			_max_visible = LIST_MAX_VISIBLE
			_typed = true
			_row_tilt_deg = LIST_ROW_TILT_DEG
		_:
			_origin = Vector2(X_NORMAL, Y_FIRST)
			_step = Vector2(0, PITCH)
			_selected_dx = X_SELECTED - X_NORMAL
			_width = WIDTH
			_text_dx = TEXT_PADDING.x
			_max_visible = MAX_VISIBLE
			_typed = false
			_row_tilt_deg = 0.0
## Mode « réduit » : voir focus_selection().
var _focused: bool = false
var _focus_position: Vector2 = Vector2.ZERO
var _shine: TextureRect
var _cursor: Sprite2D

## `entries` = un dictionnaire par ligne, dans l'ordre d'affichage :
##   id          identifiant rendu par get_selected_id() ;
##   text_id     id Localization du libellé ;
##   cost        coût en PA (facultatif, 0 = pas de losanges) ;
##   affordable  false pour afficher le coût en losanges éteints (facultatif) ;
##   quantity    quantité en réserve, affichée en nombre À LA PLACE du coût
##               (facultatif, -1 = rien). Les deux ne coexistent jamais : un
##               objet ne coûte pas de PA, un Eko n'a pas de réserve.
func setup(entries: Array[Dictionary], selected: int = 0) -> void:
	# remove_child AVANT queue_free : la libération est différée à la fin de
	# la frame, et les anciens nœuds resteraient donc affichés par-dessus les
	# nouveaux le temps d'une image quand on rouvre une liste.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_entries.clear()
	_selected = selected
	_first_visible = 0

	# Les pastilles d'abord, les libellés ensuite : dans un même niveau de
	# z_index, c'est l'ordre de l'arbre qui décide, et il faut qu'un libellé
	# passe au-dessus de sa propre pastille.
	#
	# Le libellé n'est PAS enfant de sa pastille : celle-ci est contre-
	# échelonnée pour rester nette une fois inclinée (cf. PixelScale), et le
	# texte, déjà suréchantillonné de son côté, hériterait de cette échelle en
	# plus de la sienne.
	for i in entries.size():
		var pill := NinePatchRect.new()
		# Marges et taille se mesurent dans la texture, donc dans l'espace
		# agrandi ; la position, elle, reste en unités de design.
		pill.patch_margin_left = PATCH_MARGIN * PixelScale.SCALE
		pill.patch_margin_right = PATCH_MARGIN * PixelScale.SCALE
		pill.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		pill.size = Vector2(_width, HEIGHT) * PixelScale.SCALE
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Le balayage est un enfant de la pastille et se fait découper par
		# l'alpha de celle-ci : la lumière épouse ainsi les bouts arrondis
		# sans qu'on ait à dessiner un masque séparé.
		pill.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		PixelScale.apply(pill)
		pill.rotation_degrees = _row_tilt_deg
		add_child(pill)
		var entry := entries[i].duplicate()
		entry["pill"] = pill
		_entries.append(entry)

	for i in entries.size():
		var label: RichTextLabel = BattleText.make(
			Localization.get_text(String(_entries[i].get("text_id", _entries[i].get("id", "")))),
			TEXT_SIZE, TEXT_COLOR,
		)
		label.rotation_degrees = _row_tilt_deg
		add_child(label)
		_entries[i]["label"] = label
		if _typed:
			# SVG déjà à la résolution de l'écran : rien à agrandir.
			var icon := PixelScale.sprite_native(_type_texture(int(_entries[i].get("type", 1))))
			# Au-dessus de la pastille, qu'elle déborde sur la gauche.
			icon.z_index = 2
			icon.rotation_degrees = _row_tilt_deg
			add_child(icon)
			_entries[i]["icon"] = icon
		var quantity := int(_entries[i].get("quantity", -1))
		if quantity >= 0:
			var amount: RichTextLabel = BattleText.make(
				Localization.get_text("battle.item.quantity") % quantity,
				TEXT_SIZE, TEXT_COLOR,
			)
			amount.rotation_degrees = _row_tilt_deg
			add_child(amount)
			_entries[i]["amount"] = amount
			# La largeur ne dépend que du nombre : mesurée une fois, pas à
			# chaque redessin.
			_entries[i]["amount_width"] = BattleText.text_width(
				amount.get_parsed_text(), TEXT_SIZE
			)
		var cost := int(_entries[i].get("cost", 0))
		if cost > 0:
			var dots: Node2D = ApDots.new()
			dots.pitch = COST_PITCH
			dots.rotation_degrees = _row_tilt_deg
			add_child(dots)
			dots.set_points(cost if bool(_entries[i].get("affordable", true)) else 0, cost)
			_entries[i]["dots"] = dots
		_warn_if_too_long(label, cost)

	_shine = TextureRect.new()
	_shine.texture = _make_shine_texture()
	_shine.size = Vector2(SHINE_WIDTH, HEIGHT) * PixelScale.SCALE
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Le curseur vit au niveau du menu, pas dans une pastille : les pastilles
	# ont clip_children activé pour le balayage, et il s'y ferait rogner.
	# La rotation se fait autour de l'origine du sprite : après un quart de
	# tour horaire, la texture part vers la gauche et vers le bas, il faut
	# donc décaler de sa largeur pour la ramener dans le cadre.
	_cursor = PixelScale.sprite(CURSOR, Vector2(0, -CURSOR.get_width()))
	_cursor.rotation = PI / 2.0
	_cursor.z_index = 3
	add_child(_cursor)
	_refresh()

## Un type hors catalogue retombe sur le premier plutôt que de faire planter
## l'affichage : une donnée fautive doit se voir, pas casser l'écran.
func _type_texture(type_index: int) -> Texture2D:
	return TYPE_ICONS[clampi(type_index - 1, 0, TYPE_ICONS.size() - 1)]

## Réduit la liste à sa seule entrée sélectionnée, posée à `at`. Les autres
## entrées disparaissent : pendant le ciblage, la maquette ne garde que
## l'action retenue, affichée à côté de la cible.
##
## `at` s'exprime dans le repère du menu, comme les positions de pastilles —
## c'est-à-dire AVANT l'inclinaison du groupe. Convertir un point de l'écran
## (la position d'une unité, par exemple) est le travail de l'appelant, qui
## seul connaît le pivot.
func focus_selection(at: Vector2) -> void:
	_focused = true
	_focus_position = at
	_refresh()

func restore() -> void:
	if not _focused:
		return
	_focused = false
	_refresh()

## `index` peut déborder des deux côtés : la liste boucle (descendre depuis la
## dernière entrée revient à la première).
func select(index: int) -> void:
	if _entries.is_empty():
		return
	var next := posmod(index, _entries.size())
	if next == _selected:
		return
	_selected = next
	_refresh()
	selection_changed.emit(_selected)

func get_selected_id() -> String:
	return _entries[_selected]["id"] if _entries.size() > 0 else ""

## Navigation au clavier/manette. `ui_up`/`ui_down` sont les actions natives de
## Godot (flèches + croix directionnelle) ; `battle_confirm`/`battle_cancel`
## sont propres au combat, pour rester indépendantes du `ui_accept` que le
## worldmap utilise déjà pour ses propres actions.
func _unhandled_input(event: InputEvent) -> void:
	if not active or _entries.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		select(_selected + 1)
	elif event.is_action_pressed("ui_up"):
		select(_selected - 1)
	elif event.is_action_pressed("battle_confirm"):
		confirmed.emit(get_selected_id())
	elif event.is_action_pressed("battle_cancel"):
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()

func _refresh() -> void:
	_scroll_to_selection()
	for i in _entries.size():
		var selected := i == _selected
		var pill: NinePatchRect = _entries[i]["pill"]
		var label: RichTextLabel = _entries[i]["label"]
		var dots: Node2D = _entries[i].get("dots")
		var icon: Sprite2D = _entries[i].get("icon")
		var amount: RichTextLabel = _entries[i].get("amount")
		# En mode réduit, seule l'entrée retenue reste visible ; sinon, seules
		# les rangées de la fenêtre de défilement le sont.
		var shown := selected if _focused else _is_visible_row(i)
		pill.visible = shown
		label.visible = shown
		if dots != null:
			dots.visible = shown
		if icon != null:
			icon.visible = shown
		if amount != null:
			amount.visible = shown
		if not shown:
			continue
		# Les rangées de bord s'estompent pour dire que la liste continue.
		var alpha := 1.0 if _focused else _row_alpha(i)
		pill.modulate.a = alpha
		label.modulate.a = alpha
		if dots != null:
			dots.modulate.a = alpha
		if icon != null:
			icon.modulate.a = alpha
		if amount != null:
			amount.modulate.a = alpha
		# Déjà à la résolution de l'écran (SVG, cf. PixelScale.sprite_native) :
		# poser directement, pas d'agrandissement au runtime à faire ici.
		pill.texture = ON if selected else OFF
		pill.position = _focus_position if _focused else _row_position(i, selected)
		# L'entrée sélectionnée passe au-dessus de ses voisines : avec un pas
		# inférieur à la hauteur des pastilles, celle du dessous la
		# recouvrirait sinon partiellement.
		pill.z_index = 1 if selected else 0
		label.position = pill.position + Vector2(_text_dx, TEXT_PADDING.y)
		label.z_index = pill.z_index
		label.add_theme_color_override(
			"default_color", TEXT_COLOR_SELECTED if selected else TEXT_COLOR
		)
		# Pas de contour sur l'entrée sélectionnée : le texte sombre se détache
		# déjà seul sur la pastille jaune, et un contour de la même famille de
		# bruns ne ferait qu'empâter les glyphes.
		BattleText.set_outlined(label, TEXT_SIZE, not selected)
		if dots != null:
			var span: int = ApDots.width_for(int(_entries[i].get("cost", 0)), COST_PITCH)
			dots.position = pill.position + Vector2(
				_width - COST_PADDING.x - span, COST_PADDING.y
			).rotated(deg_to_rad(_row_tilt_deg))
			dots.z_index = pill.z_index
		if amount != null:
			# Aligné à droite : c'est la largeur du nombre qui décide, et elle
			# change avec lui (« x1 » contre « x13 »).
			var span_q: float = _entries[i].get("amount_width", 0.0)
			amount.position = pill.position + Vector2(
				_width - QUANTITY_PADDING.x - span_q, QUANTITY_PADDING.y
			).rotated(deg_to_rad(_row_tilt_deg))
			amount.z_index = pill.z_index
			amount.add_theme_color_override(
				"default_color", TEXT_COLOR_SELECTED if selected else TEXT_COLOR
			)
			BattleText.set_outlined(amount, TEXT_SIZE, not selected)
		if icon != null:
			icon.position = pill.position + TYPE_ICON_OFFSET
			# Au-dessus de sa propre pastille, et de celle du dessous : l'icône
			# déborde à gauche, là où les pastilles se chevauchent.
			icon.z_index = pill.z_index + 2
		if selected:
			_place_cursor(pill.position)
			if _shine.get_parent() != pill:
				if _shine.get_parent() != null:
					_shine.get_parent().remove_child(_shine)
				pill.add_child(_shine)
				# Sous le texte : la lumière traverse la pastille, elle ne
				# passe pas par-dessus les glyphes.
				pill.move_child(_shine, 0)

## La pastille a une largeur fixe relevée sur la maquette : un libellé trop
## long viendrait chevaucher sa colonne de coût. Plutôt que d'inventer une
## troncature qu'aucune maquette ne montre, on le signale — c'est la donnée
## (le catalogue de textes) qui doit tenir dans le cadre, et le message dit de
## combien elle déborde.
func _warn_if_too_long(label: RichTextLabel, cost: int) -> void:
	var plain := label.get_parsed_text()
	if plain == "":
		return
	var room: float = _width - _text_dx - COST_PADDING.x - ApDots.width_for(cost, COST_PITCH)
	var used := BattleText.text_width(plain, TEXT_SIZE)
	if used > room:
		push_warning(
			"CommandMenu: « %s » déborde de %.1f px (place : %.0f px pour un coût de %d)"
			% [plain, used - room, room, cost]
		)

## Position de la rangée `index` : la disposition en escalier de la liste
## d'Ekos vient de `_step.x`, nul pour le menu racine.
func _row_position(index: int, selected: bool) -> Vector2:
	var row := index - _first_visible
	return _origin + _step * row + Vector2(_selected_dx if selected else 0.0, 0.0)

func _is_visible_row(index: int) -> bool:
	return index >= _first_visible and index < _first_visible + _max_visible

## La sélection est maintenue sur la rangée du MILIEU, la fenêtre butant aux
## deux extrémités de la liste. C'est ce que montrent les trois vignettes de
## menu_long_list.png : « Txt 6 » sur 3..9 et « Txt 17 » sur 14..20 tombent
## tous deux en quatrième position, et « Txt 2 » reste en deuxième parce que la
## fenêtre ne peut pas remonter plus haut.
func _scroll_to_selection() -> void:
	_first_visible = clampi(
		_selected - _max_visible / 2, 0, maxi(0, _entries.size() - _max_visible)
	)

## Opacité de la rangée `index`, cf. FADE.
func _row_alpha(index: int) -> float:
	var row := index - _first_visible
	var alpha := 1.0
	if _first_visible > 0:
		alpha = minf(alpha, _edge_alpha(row))
	if _first_visible + _max_visible < _entries.size():
		alpha = minf(alpha, _edge_alpha(_max_visible - 1 - row))
	return alpha

func _edge_alpha(distance: int) -> float:
	if distance < 0 or distance >= FADE.size():
		return 1.0
	var alpha: float = FADE[distance]
	return alpha

## Le curseur change d'orientation avec le mode : à droite de la pastille et
## tourné vers elle dans la liste, à sa gauche et incliné vers la cible pendant
## le ciblage. La rotation se faisant autour de l'origine du sprite, chaque
## orientation a son propre décalage de texture — d'où le réglage conjoint des
## deux, plutôt qu'un décalage unique qui ne vaudrait que pour un angle.
func _place_cursor(pill_position: Vector2) -> void:
	if _focused:
		_cursor.offset = Vector2.ZERO
		_cursor.rotation = deg_to_rad(CURSOR_FOCUS_ROTATION_DEG + _row_tilt_deg)
		_cursor.position = pill_position + CURSOR_FOCUS_OFFSET
	else:
		_cursor.offset = Vector2(0, -CURSOR.get_width()) * PixelScale.SCALE
		_cursor.rotation = PI / 2.0 + deg_to_rad(_row_tilt_deg)
		# Le bord droit de la pastille a suivi l'inclinaison de la rangée.
		_cursor.position = (
			pill_position
			+ Vector2(_width, 0).rotated(deg_to_rad(_row_tilt_deg))
			+ CURSOR_OFFSET
		)

func _process(_delta: float) -> void:
	if _shine == null or _shine.get_parent() == null:
		return
	var phase := fmod(Time.get_ticks_msec() / 1000.0, SHINE_PERIOD) / SHINE_PERIOD
	# Enfant d'une pastille agrandie : coordonnées dans l'espace de celle-ci.
	_shine.position = Vector2(-SHINE_WIDTH + phase * (WIDTH + SHINE_WIDTH), 0) * PixelScale.SCALE

## Dégradé transparent → blanc → transparent, généré plutôt que stocké : c'est
## deux valeurs de couleur, un PNG dédié serait un asset de plus à gérer pour
## rien.
func _make_shine_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_offset(1, 0.55)
	gradient.set_color(1, Color(1, 1, 1, 0.95))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = int(SHINE_WIDTH) * PixelScale.SCALE
	texture.height = HEIGHT * PixelScale.SCALE
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	return texture
