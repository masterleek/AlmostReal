extends Sprite2D

## Héros (lyn.png) : se déplace par pathfinding sur les tuiles dévoilées
## (terrain_type != "empty1"), jamais sur une case "Empty" non dévoilée. Le
## joueur choisit sa destination en amenant WorldmapCursor sur une case
## dévoilée puis en appuyant sur "ui_accept" (même touche que pour révéler
## une case Empty, mais l'action ne se déclenche jamais sur le même type de
## case que l'autre) ; si un chemin existe (BFS le long des voisines
## hexagonales réellement adjacentes, cf get_surrounding_cells), le Héros y
## marche pas à pas, sinon rien ne se passe.

## Durée de l'animation d'un pas d'une case à la voisine (même valeur que
## WorldmapCursor.move_duration, pour un rythme de marche cohérent).
@export var move_duration: float = 0.12

# Cadres de la ligne "marche" de lyn.png (4 premières cases sur 5 — la 5e a
# une pose différente, non utilisée ici), mesurés au pixel près sur la
# feuille source.
const FRAME_RECTS := [
	Rect2(9, 73, 14, 15),
	Rect2(42, 73, 18, 16),
	Rect2(75, 72, 18, 17),
	Rect2(107, 73, 16, 16),
]
const WALK_FPS := 8.0

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var cursor: Node2D = $"../WorldmapCursor"

var current_cell: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var is_moving: bool = false
var move_from: Vector2 = Vector2.ZERO
var move_to: Vector2 = Vector2.ZERO
var move_elapsed: float = 0.0
var last_x: float = 0.0

func _ready() -> void:
	texture = load("res://Sprites/lyn.png")
	region_enabled = true
	region_rect = FRAME_RECTS[0]
	# Case de départ = la plus proche de l'endroit où le node a été placé dans
	# la scène (même logique que WorldmapCursor), pas de position codée en dur.
	current_cell = tile_layer.local_to_map(tile_layer.to_local(global_position))
	global_position = tile_layer.to_global(tile_layer.map_to_local(current_cell))
	last_x = global_position.x

func _process(delta: float) -> void:
	if is_moving:
		process_movement(delta)
	else:
		region_rect = FRAME_RECTS[0]
		handle_destination_input()

## Dévoilée et marchable (custom_data "walkable" du TileSet, cf tile_meta.json
## — false uniquement pour "Empty" actuellement, mais piloté par la donnée
## plutôt qu'un test sur terrain_type, pour rester correct si un futur type de
## tuile non marchable est ajouté). L'adjacence est gérée par le parcours en
## BFS de find_path(), pas ici.
func is_walkable(cell: Vector2i) -> bool:
	var data := tile_layer.get_cell_tile_data(cell)
	if data == null:
		return false
	return data.get_custom_data("walkable")

func handle_destination_input() -> void:
	if cursor.mode != cursor.Mode.GRID:
		return
	if not Input.is_action_just_pressed("ui_accept"):
		return
	var destination: Vector2i = cursor.current_cell
	if destination == current_cell or not is_walkable(destination):
		return
	var new_path := find_path(current_cell, destination)
	if new_path.is_empty():
		return
	path = new_path
	start_next_step()

func start_next_step() -> void:
	if path.is_empty():
		is_moving = false
		return
	var next_cell: Vector2i = path.pop_front()
	move_from = global_position
	move_to = tile_layer.to_global(tile_layer.map_to_local(next_cell))
	move_elapsed = 0.0
	is_moving = true
	current_cell = next_cell

func process_movement(delta: float) -> void:
	move_elapsed += delta
	var t: float = clamp(move_elapsed / move_duration, 0.0, 1.0)
	global_position = move_from.lerp(move_to, smoothstep(0.0, 1.0, t))

	var dx := global_position.x - last_x
	if absf(dx) > 0.5:
		flip_h = dx > 0.0
		last_x = global_position.x

	var idx := int(floor(Time.get_ticks_msec() / 1000.0 * WALK_FPS)) % FRAME_RECTS.size()
	region_rect = FRAME_RECTS[idx]

	if t >= 1.0:
		global_position = move_to
		start_next_step()

## BFS sur les voisines hexagonales réellement adjacentes (get_surrounding_cells,
## même API que WorldmapCursor.try_move) plutôt qu'une formule de voisinage
## codée en dur : reste correct quel que soit tile_shape/tile_layout. Ne
## traverse que des cases dévoilées (is_walkable) ; renvoie un chemin vide si
## `to` est inatteignable (ou n'est pas praticable).
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_walkable(to):
		return []
	var frontier: Array[Vector2i] = [from]
	var came_from := { from: from }
	var found := from == to
	while not frontier.is_empty() and not found:
		var cell: Vector2i = frontier.pop_front()
		for neighbor in tile_layer.get_surrounding_cells(cell):
			if came_from.has(neighbor) or not is_walkable(neighbor):
				continue
			came_from[neighbor] = cell
			if neighbor == to:
				found = true
				break
			frontier.append(neighbor)
	if not found:
		return []
	var result: Array[Vector2i] = []
	var step := to
	while step != from:
		result.push_front(step)
		step = came_from[step]
	return result
