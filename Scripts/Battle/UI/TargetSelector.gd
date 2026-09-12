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
## nom puis jauge, centrée sur l'unité. Décalages depuis le point « pieds ».
const NAME_OFFSET := Vector2(-34, -5)
const BAR_OFFSET := Vector2(-18, 10)
## La jauge de la cible est plus courte que celles du HUD (32 contre 59).
const BAR_WIDTH := 32
## Le nom déborde de la jauge : sa boîte doit être plus large qu'elle, sans
## quoi le centrage n'a plus de marge où jouer et le texte se cale à gauche.
## Elle reste centrée sur le même axe (cf. NAME_OFFSET).
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
## Origine du battement, remise à zéro à chaque changement de cible pour que
## la nouvelle cible s'allume franchement à l'instant où on la désigne. Lue
## sur l'horloge absolue, le battement partirait d'une phase quelconque.
var _pulse_origin_msec: int = 0

func _ready() -> void:
	_name_label = BattleText.make_centered("", NAME_BOX_WIDTH, NAME_SIZE, NAME_COLOR)
	add_child(_name_label)

	_bar = HpBar.new()
	_bar.design_width = BAR_WIDTH
	add_child(_bar)

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

## Navigation gauche/droite uniquement : les emplacements d'un camp sont rangés
## de gauche à droite (cf. BattleScene.ENEMY_SLOTS), l'ordre de la liste est
## donc l'ordre visuel. Réserver haut/bas évite qu'ils ne veuillent dire deux
## choses différentes quand le ciblage cohabitera avec les listes verticales
## d'Ekos et d'objets (Lot 4).
func _unhandled_input(event: InputEvent) -> void:
	if not active or _targets.is_empty():
		return
	if event.is_action_pressed("ui_right") and not _group:
		select(_selected + 1)
	elif event.is_action_pressed("ui_left") and not _group:
		select(_selected - 1)
	elif event.is_action_pressed("battle_confirm"):
		confirmed.emit(_selected)
	elif event.is_action_pressed("battle_cancel"):
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()

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
	_name_label.visible = not _group
	_bar.visible = not _group
	if _group:
		return

	var entry: Dictionary = _targets[_selected]
	var unit: BattleUnit = entry["unit"]
	var sprite: AnimatedSprite2D = entry["sprite"]
	BattleText.set_centered_text(_name_label, Localization.get_text(unit.name_text_id()))
	# Même lecture que le HUD : le vert s'arrête aux PV acquis, le segment rayé
	# occupe la part mise en jeu par une blessure (cf. BattleUnit, HpBar).
	_bar.set_ratio(unit.solid_ratio(), unit.hp_ratio())

	# Ancrage sur le point « pieds » de la cible (cf. UnitSprite) : c'est le
	# seul repère indépendant de la taille de cellule du personnage. Les
	# décalages restent entiers — un demi-pixel de design devient un flou de
	# 2 px à l'écran une fois le Stage agrandi ×4.
	var feet := sprite.position
	_name_label.position = feet + NAME_OFFSET
	_bar.position = feet + BAR_OFFSET

func _process(_delta: float) -> void:
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
func _clear_tint() -> void:
	for sprite in _tinted:
		sprite.material = null
	_tinted.clear()
