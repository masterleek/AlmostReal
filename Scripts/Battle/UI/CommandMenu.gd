extends Node2D

## Liste de commandes en pastilles (Attack / Eko / Items / Guard).
##
## Volontairement générique : c'est le même composant qui servira aux listes
## d'Ekos et d'objets, qui n'en diffèrent que par le nombre d'entrées, la
## présence d'un coût en AP et d'un défilement. Une seule implémentation
## paramétrée, pas trois copies.
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

const OFF := preload("res://UI/Battle/command_off.svg")
const ON := preload("res://UI/Battle/command_on.svg")

## Curseur de sélection : c'est le MÊME asset que le curseur du worldmap,
## pivoté d'un quart de tour pour pointer vers la gauche (vérifié par recalage
## sur le mockup : l'erreur tombe à 38 dans cette orientation, contre 86 à 96
## pour les trois autres). On le partage plutôt que d'en dupliquer une variante
## — le jeu n'a qu'un curseur, il doit rester cohérent d'un écran à l'autre.
const CURSOR := preload("res://UI/cursor_worldmap.png")
const CURSOR_OFFSET := Vector2(79, -1)

const X_NORMAL := 280
const X_SELECTED := 263
## Décalé de 2 px par rapport au recalage initial : celui-ci avait été fait
## avec un gabarit horizontal sur une maquette inclinée, ce qui biaisait le
## résultat vers le haut. Vérifié après coup en ajustant le bord supérieur de
## la pastille « Attack » sur les deux images.
const Y_FIRST := 165
const PITCH := 16
const WIDTH := 78
const HEIGHT := 18

## Marges du 9-slice : seuls les deux bouts arrondis sont préservés, le centre
## s'étire. Aucune marge verticale — haut et bas de la texture couvrent déjà
## toute la hauteur, la pastille ne s'étire jamais verticalement.
const PATCH_MARGIN := 8

const TEXT_PADDING := Vector2(6, 1)
const TEXT_SIZE := 15
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

var _entries: Array[Dictionary] = []
var _selected: int = 0
var _shine: TextureRect
var _cursor: Sprite2D

## `labels` = ids Localization, dans l'ordre d'affichage.
func setup(labels: PackedStringArray, selected: int = 0) -> void:
	for child in get_children():
		child.queue_free()
	_entries.clear()
	_selected = selected

	# Les pastilles d'abord, les libellés ensuite : dans un même niveau de
	# z_index, c'est l'ordre de l'arbre qui décide, et il faut qu'un libellé
	# passe au-dessus de sa propre pastille.
	#
	# Le libellé n'est PAS enfant de sa pastille : celle-ci est contre-
	# échelonnée pour rester nette une fois inclinée (cf. PixelScale), et le
	# texte, déjà suréchantillonné de son côté, hériterait de cette échelle en
	# plus de la sienne.
	for i in labels.size():
		var pill := NinePatchRect.new()
		# Marges et taille se mesurent dans la texture, donc dans l'espace
		# agrandi ; la position, elle, reste en unités de design.
		pill.patch_margin_left = PATCH_MARGIN * PixelScale.SCALE
		pill.patch_margin_right = PATCH_MARGIN * PixelScale.SCALE
		pill.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		pill.size = Vector2(WIDTH, HEIGHT) * PixelScale.SCALE
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Le balayage est un enfant de la pastille et se fait découper par
		# l'alpha de celle-ci : la lumière épouse ainsi les bouts arrondis
		# sans qu'on ait à dessiner un masque séparé.
		pill.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		PixelScale.apply(pill)
		add_child(pill)
		_entries.append({"pill": pill, "id": labels[i]})

	for i in labels.size():
		var label: RichTextLabel = BattleText.make(Localization.get_text(labels[i]), TEXT_SIZE, TEXT_COLOR)
		add_child(label)
		_entries[i]["label"] = label

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
	for i in _entries.size():
		var selected := i == _selected
		var pill: NinePatchRect = _entries[i]["pill"]
		# Déjà à la résolution de l'écran (SVG, cf. PixelScale.sprite_native) :
		# poser directement, pas d'agrandissement au runtime à faire ici.
		pill.texture = ON if selected else OFF
		pill.position = Vector2(X_SELECTED if selected else X_NORMAL, Y_FIRST + i * PITCH)
		# L'entrée sélectionnée passe au-dessus de ses voisines : avec un pas
		# inférieur à la hauteur des pastilles, celle du dessous la
		# recouvrirait sinon partiellement.
		pill.z_index = 1 if selected else 0
		var label: RichTextLabel = _entries[i]["label"]
		label.position = pill.position + TEXT_PADDING
		label.z_index = pill.z_index
		label.add_theme_color_override(
			"default_color", TEXT_COLOR_SELECTED if selected else TEXT_COLOR
		)
		# Pas de contour sur l'entrée sélectionnée : le texte sombre se détache
		# déjà seul sur la pastille jaune, et un contour de la même famille de
		# bruns ne ferait qu'empâter les glyphes.
		BattleText.set_outlined(label, TEXT_SIZE, not selected)
		if selected:
			_cursor.position = pill.position + CURSOR_OFFSET
			if _shine.get_parent() != pill:
				if _shine.get_parent() != null:
					_shine.get_parent().remove_child(_shine)
				pill.add_child(_shine)
				# Sous le texte : la lumière traverse la pastille, elle ne
				# passe pas par-dessus les glyphes.
				pill.move_child(_shine, 0)

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
