extends Node2D

## Choix d'une cible parmi des unités posées sur le terrain.
##
## Rien ici ne suppose de quel camp est la cible : l'appelant fournit la liste
## des unités visables, qu'il s'agisse des ennemis pour une attaque ou des
## alliés pour un soin. Deux modes :
##
##   - UNITAIRE : une cible à la fois, changée avec ←/→, nom et jauge affichés ;
##   - GROUPE : toutes les cibles de la liste sont retenues d'un bloc. Elles
##     s'allument toutes, la navigation n'a plus de sens et la plaque est
##     masquée — elle ne pourrait nommer qu'une des cibles.
##
## Trois choses composent la sélection :
##   - la SILHOUETTE de la ou des cibles passe au blanc, par battement lent ;
##   - son NOM s'affiche à ses pieds ;
##   - sa JAUGE DE VIE s'affiche sous le nom (même composant que le HUD des
##     alliés — c'est la même information, elle doit se lire pareil).
##
## L'action retenue reste elle aussi affichée, mais elle n'est pas dessinée
## ici : c'est la liste de commandes qui se réduit à cette seule entrée et va
## se poser près de la cible (cf. CommandMenu.focus_selection). La pastille
## garde ainsi son balayage lumineux et son curseur sans qu'on en fabrique une
## deuxième version.
##
## Toutes les positions ci-dessous sont relevées sur la deuxième vignette de
## mockup_preparation_select_attack.png (480×270 natif), la cible y étant
## l'ennemi de l'emplacement 2, pieds en (195, 169).

## `selection_changed` ne part que sur un changement réel de cible : c'est lui
## qui déclenche le son de navigation.
signal selection_changed(index: int)
signal confirmed(index: int)
signal cancelled

const BattleUnit = preload("res://Scripts/Battle/BattleUnit.gd")
const UnitSprite = preload("res://Scripts/Battle/Stage/UnitSprite.gd")
const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")
const HpBar = preload("res://Scripts/Battle/UI/HpBar.gd")

## Le même shader que la tuile de révélation du worldmap : blanchir un sprite
## sans toucher à sa transparence est exactement le besoin ici, il n'y a pas
## lieu d'en écrire un second.
const WHITE_TINT := preload("res://Shaders/white_tint.gdshader")

## Un cran sous la légende de combat : sur la maquette, « Cactoon » couvre
## 43 px pour 39 px d'avance cumulée, contre 47 et 41,25 au corps 15 — soit un
## rapport de 0,94 dans les deux mesures.
const NAME_SIZE := 14
const NAME_COLOR := Color(1, 1, 1)

## La plaque est SOUS la cible, pas au-dessus : la maquette la pose sur le sol,
## nom puis jauge, centrée sur l'unité. Seule l'ORDONNÉE est une constante, et
## elle se compte depuis le point « pieds » ; l'abscisse, elle, se déduit des
## largeurs ci-dessous, les deux éléments étant centrés sur le dessin de la
## cible (cf. _plate_anchor).
const NAME_Y := -5
const BAR_Y := 10
## La jauge de la cible est plus courte que celles du HUD (32 contre 59).
const BAR_WIDTH := 32
## Le nom déborde de la jauge : sa boîte doit être plus large qu'elle, sans
## quoi le centrage n'a plus de marge où jouer et le texte se cale à gauche.
const NAME_BOX_WIDTH := 64

## Battement de la surbrillance. Le maximum vaut 1 (silhouette entièrement
## blanche) : la maquette du ciblage montre cet état-là, qui est donc le
## sommet du battement et non une valeur figée — une cible blanche en
## permanence se lirait comme un personnage à part plutôt que comme une
## sélection.
##
## Le minimum est haut (0,6) parce que les planches d'ennemis sont en NIVEAUX
## DE GRIS (le cactoon n'a que des pixels r = v = b) : un battement descendant
## près de zéro ramènerait la cible à la teinte exacte de ses voisines, et la
## sélection deviendrait illisible au creux du cycle. À 0,6, son gris médian
## reste au-dessus de 180 quand celui des autres est à 74.
const PULSE_PERIOD := 0.9
const PULSE_MIN := 0.6
const PULSE_MAX := 1.0

## Luminance en dessous de laquelle un pixel reste à sa couleur (cf.
## white_tint.gdshader) : les planches portent l'ombre au sol DANS la cellule,
## et sans ce seuil la sélection allumerait un halo blanc sous les pieds de la
## cible. Mesuré sur les trois planches du jeu : leurs pixels d'ombre et de
## contour sont tous sous 0,05 de luminance, le premier pixel de corps est à
## 0,05 et au-delà.
const DARK_CUTOFF := 0.05

## Ne réagit aux entrées que si `active`, comme CommandMenu : le menu racine
## reste monté pendant le ciblage, une seule des deux listes doit avoir la
## main.
var active: bool = false

## Entrées `{"unit": BattleUnit, "sprite": Node2D}`. Le sprite sert à deux
## choses : recevoir la surbrillance, et donner l'ancrage de la plaque — sa
## `position` est le point « pieds » et son `offset.y` la hauteur de cellule
## (cf. UnitSprite), donc son sommet se déduit sans relire units.json.
var _targets: Array[Dictionary] = []
var _selected: int = 0
var _name_label: RichTextLabel
var _bar: HpBar
var _material: ShaderMaterial
## Sprites actuellement blanchis. Un seul en mode unitaire, toute la liste en
## mode groupe — le matériau, lui, reste unique et partagé.
var _tinted: Array[CanvasItem] = []
## Ciblage de groupe : voir l'en-tête.
var _group: bool = false
## Indices de `_targets` rangés de GAUCHE À DROITE à l'écran. L'ordre de la
## liste, lui, est celui de la donnée : depuis que les emplacements ennemis sont
## numérotés de droite à gauche (cf. BattleScene.ENEMY_SLOTS), les deux ne
## coïncident plus, et ←/→ doivent suivre l'écran — c'est ce que le joueur
## regarde. Calculé à l'ouverture : les cibles ne se déplacent pas pendant la
## préparation.
var _visual_order: PackedInt32Array = PackedInt32Array()
## Origine du battement, remise à zéro à chaque changement de cible pour que
## la nouvelle cible s'allume franchement à l'instant où on la désigne. Lue
## sur l'horloge absolue, le battement partirait d'une phase quelconque.
var _pulse_origin_msec: int = 0
## Porte le nom et la jauge de la cible, à l'échelle de design (cf. _ready).
var _plate: Node2D
## Échelle globale du sélecteur au montage, avant tout cadrage.
var _design_scale := Vector2.ONE

func _ready() -> void:
	# La plaque est un nœud À PART, et c'est tout son intérêt : elle suit la
	# cible dans l'espace du TERRAIN (donc le glissement et le cadrage la
	# déplacent avec le personnage) mais son contenu reste à l'échelle de
	# DESIGN. Ses décalages sont mesurés à l'écran sur la maquette, et son texte
	# comme sa jauge sont calibrés pour cette échelle-là : les laisser grossir
	# avec le zoom les éloignait de la cible et rendait le texte flou, son
	# suréchantillonnage tombant sur un facteur non entier.
	_plate = Node2D.new()
	add_child(_plate)
	# Relevée au montage, avant tout cadrage : c'est l'échelle du Stage, la
	# seule que la plaque doit conserver. La lire plutôt que d'écrire 4 en dur
	# évite d'avoir à connaître ici la composition de l'arbre au-dessus.
	_design_scale = get_global_transform().get_scale()

	# Les deux éléments se posent par leur coin haut-gauche : les centrer sur
	# l'origine de la plaque revient à reculer chacun de la moitié de SA
	# largeur. Division entière — les deux largeurs sont paires, et un
	# demi-pixel de design devient 2 px de flou une fois le Stage agrandi ×4.
	_name_label = BattleText.make_centered("", NAME_BOX_WIDTH, NAME_SIZE, NAME_COLOR)
	_name_label.position = Vector2(-NAME_BOX_WIDTH / 2, NAME_Y)
	_plate.add_child(_name_label)

	_bar = HpBar.new()
	_bar.design_width = BAR_WIDTH
	_bar.position = Vector2(-BAR_WIDTH / 2, BAR_Y)
	_plate.add_child(_bar)

	_material = ShaderMaterial.new()
	_material.shader = WHITE_TINT
	_material.set_shader_parameter("dark_cutoff", DARK_CUTOFF)

	visible = false
	set_process(false)

## Ouvre la sélection sur `targets` (déjà filtrée par l'appelant : le sélecteur
## n'a pas à connaître les règles qui rendent une unité ciblable ou non).
## `group` retient toute la liste d'un bloc plutôt qu'une entrée à la fois.
func open(targets: Array[Dictionary], group: bool = false, index: int = 0) -> void:
	_targets = targets
	_group = group
	if _targets.is_empty():
		return
	_selected = clampi(index, 0, _targets.size() - 1)
	_rebuild_visual_order()
	visible = true
	active = true
	set_process(true)
	_refresh()

func close() -> void:
	active = false
	visible = false
	set_process(false)
	_group = false
	_clear_tint()
	# Réassignation plutôt que `clear()` : le tableau appartient à l'appelant,
	# le sélecteur n'a fait que le garder sous la main.
	_targets = []
	_visual_order = PackedInt32Array()

## Point « pieds » de la cible courante, dans le repère du terrain. Sert à
## l'appelant pour aligner ce qu'il affiche lui-même sur la cible — la pastille
## de l'action retenue, notamment.
##
## En mode groupe il n'y a pas de cible courante : on renvoie le barycentre des
## cibles, pour que la pastille se pose au milieu de ce qui est visé plutôt
## qu'au-dessus d'un membre arbitraire du groupe.
func get_selected_feet() -> Vector2:
	if _targets.is_empty():
		return Vector2.ZERO
	if not _group:
		var sprite: AnimatedSprite2D = _targets[_selected]["sprite"]
		return sprite.position
	var sum := Vector2.ZERO
	for entry in _targets:
		sum += (entry["sprite"] as AnimatedSprite2D).position
	return (sum / float(_targets.size())).round()

## Navigation gauche/droite uniquement, DANS L'ORDRE DE L'ÉCRAN : l'ordre de la
## liste est celui des emplacements, qui ne suit plus l'abscisse depuis que les
## ennemis sont numérotés de droite à gauche (cf. _step, et
## BattleScene.ENEMY_SLOTS). Réserver haut/bas évite qu'ils ne veuillent dire deux
## choses différentes quand le ciblage cohabitera avec les listes verticales
## d'Ekos et d'objets (Lot 4).
func _unhandled_input(event: InputEvent) -> void:
	if not active or _targets.is_empty():
		return
	if event.is_action_pressed("ui_right") and not _group:
		_step(1)
	elif event.is_action_pressed("ui_left") and not _group:
		_step(-1)
	elif event.is_action_pressed("battle_confirm"):
		confirmed.emit(_selected)
	elif event.is_action_pressed("battle_cancel"):
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()

## Cible suivante DANS L'ORDRE DE L'ÉCRAN (`step` = +1 vers la droite). La
## navigation ne passe pas par l'ordre de la liste : celui-ci est l'ordre de
## numérotation des emplacements, qui n'a aucune raison de suivre l'abscisse.
func _step(step: int) -> void:
	var rank := _visual_order.find(_selected)
	if rank < 0:
		return
	select(_visual_order[posmod(rank + step, _visual_order.size())])

## Indices de `_targets` triés par abscisse croissante. Sur l'abscisse des
## PIEDS, pas sur celle du dessin : c'est l'emplacement au sol qui range les
## combattants, et deux planches de largeurs très différentes pourraient
## s'inverser sur leur centre de dessin.
func _rebuild_visual_order() -> void:
	var order: Array[int] = []
	for i in _targets.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _feet_of(a).x < _feet_of(b).x
	)
	_visual_order = PackedInt32Array(order)

func _feet_of(index: int) -> Vector2:
	return (_targets[index]["sprite"] as Node2D).position

## `index` peut déborder des deux côtés : la liste boucle.
func select(index: int) -> void:
	if _targets.is_empty():
		return
	var next := posmod(index, _targets.size())
	if next == _selected:
		return
	_selected = next
	_refresh()
	selection_changed.emit(_selected)

func _refresh() -> void:
	_pulse_origin_msec = Time.get_ticks_msec()
	_clear_tint()
	for i in _targets.size():
		if _group or i == _selected:
			var target: CanvasItem = _targets[i]["sprite"]
			target.material = _material
			_tinted.append(target)

	# La plaque nomme UNE cible : elle n'a pas de sens sur un groupe.
	_plate.visible = not _group
	if _group:
		return

	var entry: Dictionary = _targets[_selected]
	var unit: BattleUnit = entry["unit"]
	var sprite: UnitSprite = entry["sprite"]
	BattleText.set_centered_text(_name_label, Localization.get_text(unit.name_text_id()))
	# Même lecture que le HUD : le vert s'arrête aux PV acquis, le segment rayé
	# occupe la part mise en jeu par une blessure (cf. BattleUnit, HpBar).
	_bar.set_ratio(unit.solid_ratio(), unit.hp_ratio())

	_plate.position = _plate_anchor(sprite)
	_hold_plate_scale()

## Point sur lequel la plaque vient se poser, dans le repère du terrain.
##
## DEUX repères différents, et c'est voulu. En ORDONNÉE, le point « pieds » :
## c'est le seul repère indépendant de la taille de cellule du personnage, et
## la maquette pose bien la plaque au sol. En ABSCISSE, le centre de l'OMBRE
## (cf. UnitSprite.ground_centre) : ni le point « pieds », qui est le milieu de
## la cellule de repos et tombe 7 px à gauche de Noah, ni le centre du DESSIN,
## qui part avec l'épée qu'il dégaine sur son `standby`.
##
## Relevé sur la troisième vignette de `mockup_preparation_select_items.png`,
## où Noah est justement la cible d'un objet : ombre centrée en 454,5, nom en
## 455,0, jauge en 455,5 — et silhouette, épée comprise, en 461,5. La plaque
## suit l'ombre.
##
## Arrondi : la plaque porte du texte, et une abscisse à virgule devient 2 px
## de flou une fois le Stage agrandi ×4.
func _plate_anchor(sprite: UnitSprite) -> Vector2:
	return Vector2(roundi(sprite.ground_centre().x), sprite.position.y)

func _process(_delta: float) -> void:
	_hold_plate_scale()
	if _material == null:
		return
	var elapsed := (Time.get_ticks_msec() - _pulse_origin_msec) / 1000.0
	var phase := fmod(elapsed, PULSE_PERIOD) / PULSE_PERIOD
	# Cosinus plutôt que sinus : le battement part du maximum, la cible est
	# donc entièrement blanche à l'instant où on la sélectionne.
	var wave := (cos(phase * TAU) + 1.0) / 2.0
	_material.set_shader_parameter(
		"white_amount", PULSE_MIN + (PULSE_MAX - PULSE_MIN) * wave
	)

## Les sprites d'unité n'ont pas de matériau propre (cf. UnitSprite) : rendre
## la main revient donc à remettre `null`, pas à restaurer un état sauvegardé.
## Annule, à chaque image, l'échelle que le cadrage ajoute au-dessus du
## sélecteur. À chaque image et pas une fois pour toutes : le cadrage est un
## tween, l'échelle du terrain change pendant toute sa durée.
func _hold_plate_scale() -> void:
	if _plate == null:
		return
	var current := get_global_transform().get_scale()
	if is_zero_approx(current.x) or is_zero_approx(current.y):
		return
	_plate.scale = _design_scale / current

func _clear_tint() -> void:
	for sprite in _tinted:
		sprite.material = null
	_tinted.clear()
