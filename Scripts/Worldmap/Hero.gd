extends Sprite2D

## Héros (character.png) : se déplace par pathfinding sur les tuiles dévoilées
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
## Vitesse du cycle de marche (jambes), en images par seconde — indépendante
## de move_duration (qui règle la vitesse de déplacement, pas l'animation).
@export var walk_fps: float = 8.0
## Délai d'inactivité (aucune entrée joueur : ni déplacement du curseur, ni
## validation) avant que le Héros joue son animation d'inactivité (cf
## IDLE_FIDGET_FRAMES) à la place de sa pose immobile habituelle.
@export var idle_timeout: float = 5.0
## Durée d'affichage de chaque frame de transition (6,4) de l'animation
## d'inactivité, à l'entrée comme à la sortie.
@export var idle_fidget_frame_duration: float = 0.2
## Durée de la tenue sur la frame finale (6,5) avant de rejouer 6,4 puis de
## revenir à la pose de repos normale.
@export var idle_fidget_hold_duration: float = 3.0

# 3 poses dessinées dans character.png (coordonnées "ligne,colonne" de la
# feuille, cellules de 44x44) : FRONT (case caméra), BACK (dos), LEFT (3/4
# gauche, en course). Pas de pose "droite" dédiée : LEFT + flip_h la couvre,
# comme un sprite de tactics-RPG classique.
enum Pose { FRONT, BACK, LEFT }

# Cycles de marche, mesurés au pixel près sur la feuille source.
const WALK_FRAMES := {
	Pose.FRONT: [ # 3,10 -> 4,5
		Rect2(409, 99, 20, 33),
		Rect2(14, 142, 18, 34),
		Rect2(57, 141, 18, 35),
		Rect2(99, 143, 20, 33),
		Rect2(145, 142, 17, 34),
		Rect2(189, 141, 18, 35),
	],
	Pose.BACK: [ # 4,6 -> 5,1
		Rect2(230, 142, 21, 33),
		Rect2(276, 141, 19, 35),
		Rect2(320, 140, 19, 36),
		Rect2(365, 142, 21, 33),
		Rect2(409, 141, 19, 35),
		Rect2(13, 184, 19, 36),
	],
	Pose.LEFT: [ # 3,4 -> 3,9
		Rect2(146, 98, 20, 34),
		Rect2(191, 97, 18, 35),
		Rect2(235, 96, 19, 36),
		Rect2(278, 98, 21, 33),
		Rect2(323, 97, 18, 34),
		Rect2(367, 96, 16, 35),
	],
}
# Poses au repos : 5,2 (face) / 5,6 (dos) / 5,10 (gauche).
const IDLE_FRAMES := {
	Pose.FRONT: Rect2(57, 185, 18, 35),
	Pose.BACK: Rect2(233, 186, 18, 34),
	Pose.LEFT: Rect2(411, 185, 18, 35),
}
# Animation d'inactivité (au bout de idle_timeout secondes sans entrée
# joueur) : 6,4 -> 6,5 (tenue idle_fidget_hold_duration secondes) -> 6,4 ->
# retour à la pose de repos normale (cf process_idle). Dessinée de face
# uniquement (pas une variante par Pose comme WALK_FRAMES/IDLE_FRAMES) : voir
# process_idle() pour le flip_h forcé à false pendant qu'elle joue.
const IDLE_FIDGET_FRAMES := [
	Rect2(142, 229, 22, 35), # 6,4
	Rect2(188, 229, 21, 35), # 6,5 (frame finale)
]
@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var cursor: Node2D = $"../WorldmapCursor"
@onready var footstep_sfx: AudioStreamPlayer = $FootstepSFX
@onready var validation_sfx: AudioStreamPlayer = $ValidationSFX
@onready var error_sfx: AudioStreamPlayer = $ErrorSFX

# Sons de pas par terrain_type : une paire par type, alternée à chaque pas
# (cf _footstep_next_index) plutôt que rejouée à l'identique. Rien ne se joue
# pour un terrain_type sans entrée ici (Empty n'est de toute façon jamais
# praticable, cf is_walkable).
const FOOTSTEP_SOUNDS := {
	"grass1": ["res://Audio/foot_grass1.wav", "res://Audio/foot_grass2.wav"],
	"grass2": ["res://Audio/foot_grass1.wav", "res://Audio/foot_grass2.wav"],
	"sand": ["res://Audio/foot_sand1.wav", "res://Audio/foot_sand2.wav"],
}
var _footstep_next_index: Dictionary = {}

var current_cell: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var is_moving: bool = false
var move_from: Vector2 = Vector2.ZERO
var move_to: Vector2 = Vector2.ZERO
var move_elapsed: float = 0.0
# Pose/orientation du dernier pas effectué (ou par défaut) : conservée à
# l'arrêt, pour que le Héros reste visuellement tourné vers la direction
# d'où il vient plutôt que de revenir face caméra à chaque halte.
var current_pose: Pose = Pose.FRONT

# Temps écoulé sans la moindre entrée joueur pendant que le Héros est
# immobile (remis à zéro dès qu'un pas démarre, cf start_next_step()) et état
# de l'animation d'inactivité qui en dépend — cf process_idle().
var _idle_elapsed: float = 0.0
var _is_idle_fidgeting: bool = false
var _idle_fidget_saved_flip_h: bool = false

func _ready() -> void:
	texture = load("res://Sprites/character.png")
	region_enabled = true
	region_rect = IDLE_FRAMES[current_pose]
	# Case de départ = la plus proche de l'endroit où le node a été placé dans
	# la scène (même logique que WorldmapCursor), pas de position codée en dur.
	current_cell = tile_layer.local_to_map(tile_layer.to_local(global_position))
	global_position = tile_layer.to_global(tile_layer.map_to_local(current_cell))

func _process(delta: float) -> void:
	if is_moving:
		process_movement(delta)
	else:
		process_idle(delta)
		handle_destination_input()

## Pose au repos : la pose statique de la dernière direction de marche
## (IDLE_FRAMES) tant que le joueur fait quoi que ce soit (déplace le
## curseur ou valide), remplacée par IDLE_FIDGET_FRAMES au bout de
## idle_timeout secondes sans la moindre entrée — remise à zéro dès qu'une
## entrée est de nouveau détectée.
func process_idle(delta: float) -> void:
	if has_player_input():
		_idle_elapsed = 0.0
		stop_idle_fidget()
		region_rect = IDLE_FRAMES[current_pose]
		return

	_idle_elapsed += delta
	if _idle_elapsed < idle_timeout:
		region_rect = IDLE_FRAMES[current_pose]
		return

	if not _is_idle_fidgeting:
		_is_idle_fidgeting = true
		_idle_fidget_saved_flip_h = flip_h
		flip_h = false # IDLE_FIDGET_FRAMES est dessinée de face, jamais à retourner.

	# Chronologie depuis le début de l'animation : 6,4 (entrée) -> 6,5 (tenue)
	# -> 6,4 (sortie) -> fin (retour à la pose de repos normale plus bas, avec
	# remise à zéro du minuteur pour permettre un nouveau cycle après un
	# nouvel idle_timeout).
	var t := _idle_elapsed - idle_timeout
	if t < idle_fidget_frame_duration:
		region_rect = IDLE_FIDGET_FRAMES[0] # 6,4
		return
	t -= idle_fidget_frame_duration
	if t < idle_fidget_hold_duration:
		region_rect = IDLE_FIDGET_FRAMES[1] # 6,5
		return
	t -= idle_fidget_hold_duration
	if t < idle_fidget_frame_duration:
		region_rect = IDLE_FIDGET_FRAMES[0] # 6,4
		return

	stop_idle_fidget()
	_idle_elapsed = 0.0
	region_rect = IDLE_FRAMES[current_pose]

func stop_idle_fidget() -> void:
	if not _is_idle_fidgeting:
		return
	_is_idle_fidgeting = false
	flip_h = _idle_fidget_saved_flip_h

## Mêmes actions que celles que WorldmapCursor traite lui-même (déplacement
## + validation) : le Héros n'a pas accès à son état interne, donc on relit
## les mêmes entrées brutes plutôt que de coupler les deux nœuds.
func has_player_input() -> bool:
	return (
		Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() > 0.0
		or Input.is_action_pressed("ui_accept")
	)

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
	# is_walkable() exclut déjà les cases "Empty" (jamais dévoilées) : pas
	# besoin d'un test de terrain_type séparé pour "tuile déjà dévoilée".
	if destination == current_cell or not is_walkable(destination):
		return
	# Sélection confirmée (case dévoilée, différente de celle du Héros) : le
	# son joué dépend de l'atteignabilité du chemin, jamais les deux à la fois.
	var new_path := find_path(current_cell, destination)
	if new_path.is_empty():
		error_sfx.play()
		return
	validation_sfx.play()
	path = new_path
	start_next_step()

func start_next_step() -> void:
	# Chaque pas (départ comme arrivée) compte comme une activité : le délai
	# avant l'animation d'inactivité repart de zéro à partir d'ici, pas depuis
	# la validation initiale.
	_idle_elapsed = 0.0
	stop_idle_fidget()
	if path.is_empty():
		is_moving = false
		return
	var next_cell: Vector2i = path.pop_front()
	move_from = global_position
	move_to = tile_layer.to_global(tile_layer.map_to_local(next_cell))
	move_elapsed = 0.0
	is_moving = true
	current_cell = next_cell

	# Pose choisie une fois par pas (pas par frame) d'après le déplacement
	# réel à l'écran : vers le bas -> FRONT, vers le haut -> BACK, purement
	# horizontal -> LEFT (+ flip_h si le pas va vers la droite). Couvre les 6
	# directions hexagonales avec seulement 3 poses dessinées.
	var step_delta := move_to - move_from
	if step_delta.y > 0.0:
		current_pose = Pose.FRONT
	elif step_delta.y < 0.0:
		current_pose = Pose.BACK
	else:
		current_pose = Pose.LEFT
	flip_h = step_delta.x > 0.0

	play_footstep_sound(next_cell)

## Joue le son de pas correspondant au terrain_type de `cell` (rien si le
## type n'a pas d'entrée dans FOOTSTEP_SOUNDS), en alternant entre les 2
## variantes à chaque pas plutôt que de rejouer toujours la même.
func play_footstep_sound(cell: Vector2i) -> void:
	var data := tile_layer.get_cell_tile_data(cell)
	if data == null:
		return
	var terrain_type: String = data.get_custom_data("terrain_type")
	var sounds: Array = FOOTSTEP_SOUNDS.get(terrain_type, [])
	if sounds.is_empty():
		return
	var idx: int = _footstep_next_index.get(terrain_type, 0)
	footstep_sfx.stream = load(sounds[idx])
	footstep_sfx.play()
	_footstep_next_index[terrain_type] = (idx + 1) % sounds.size()

func process_movement(delta: float) -> void:
	move_elapsed += delta
	var t: float = clamp(move_elapsed / move_duration, 0.0, 1.0)
	# Interpolation linéaire (pas smoothstep) : sur un chemin de plusieurs
	# cases, un easing qui revient à vitesse nulle à chaque frontière de case
	# crée une micro-pause à chaque changement de tuile au lieu d'une marche à
	# vitesse constante.
	global_position = move_from.lerp(move_to, t)

	var frames: Array = WALK_FRAMES[current_pose]
	var idx := int(floor(Time.get_ticks_msec() / 1000.0 * walk_fps)) % frames.size()
	region_rect = frames[idx]

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
