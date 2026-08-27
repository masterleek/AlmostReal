extends HBoxContainer

## Indice contextuel en bas à droite de l'écran (bouton "X" + texte) qui
## change selon ce que WorldmapCursor survole : "Reveal" sur une case Empty,
## "Go to" sur toute autre case. Même style visuel (police, ombre, contour)
## que le compteur de hex (cf HexCounterHUD). Masqué en entier quand le
## curseur survole la case du Héros — aucune action de ce type n'a de sens
## sur sa propre case.

const TerrainTypes = preload("res://Scripts/Worldmap/TerrainTypes.gd")

@onready var cursor: Node2D = $"../../WorldmapCursor"
@onready var hero: Node2D = $"../../Hero"
@onready var action_label: Label = $ActionLabel

# Couleur du texte quand la case visée par "Go to" est inatteignable en
# pathfinding depuis le Héros (cf Hero.find_path) — le blanc normal
# (theme_override_colors/font_color dans la scène) reste utilisé partout
# ailleurs, y compris pour "Reveal" (pas de notion d'accessibilité).
const UNREACHABLE_COLOR := Color8(0xB6, 0xB6, 0xB6)
const NORMAL_COLOR := Color(1, 1, 1, 1)

# hero.find_path() est un BFS complet : ne le relancer que quand la case du
# Héros ou celle visée par "Go to" changent réellement, pas à chaque frame
# (son résultat est strictement le même tant que ni l'une ni l'autre ne bouge).
var _cached_hero_cell: Vector2i = Vector2i(-999999, -999999)
var _cached_target_cell: Vector2i = Vector2i(-999999, -999999)
var _cached_reachable: bool = false

func _process(_delta: float) -> void:
	visible = cursor.current_cell != hero.current_cell
	if not visible:
		return

	if TerrainTypes.is_empty(cursor.current_terrain_type):
		action_label.text = "Reveal"
		action_label.add_theme_color_override("font_color", NORMAL_COLOR)
		return

	action_label.text = "Go to"
	if hero.current_cell != _cached_hero_cell or cursor.current_cell != _cached_target_cell:
		_cached_hero_cell = hero.current_cell
		_cached_target_cell = cursor.current_cell
		_cached_reachable = not hero.find_path(hero.current_cell, cursor.current_cell).is_empty()
	action_label.add_theme_color_override("font_color", NORMAL_COLOR if _cached_reachable else UNREACHABLE_COLOR)
