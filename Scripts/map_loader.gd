extends Node2D

## Charge une map depuis res://maps/<id>.json au runtime (tuiles + props) et
## fait le lien entre les données du MapEditor et la scène Godot.
@export var map_id: String = "Test"

@onready var tile_layer: TileMapLayer = $TileMapLayer
@onready var props_layer: Node2D = $PropsLayer
@onready var worldmap_cursor: Node2D = $WorldmapCursor
@onready var camera: Camera2D = $Camera2D
@onready var music: AudioStreamPlayer = $WorldmapMusic

var props_texture: Texture2D = load("res://Sprites/props.png")
var tile_defs: Dictionary = {} # "x,y" (atlas) -> tuile complète de tile_meta.json
var animated_cells: Array = [] # cases posées dont la tuile a plusieurs frames
var animated_props: Array = [] # props posés dont le prop a plusieurs frames
var reveal_targets: Dictionary = {} # Vector2i (case) -> Vector2i (atlas de la tuile qu'elle révèle)
# Vector2i (case "empty") -> Array[Sprite2D] : props posés (dans l'éditeur de
# maps) sur une case pas encore révélée, cachés jusqu'à la révélation de
# cette case (cf get_props_for_cell(), consommé par run_reveal_sequence()).
var props_by_reveal_cell: Dictionary = {}

## Tuile révélée par défaut (Grass1) quand une case "Empty" n'a pas de cible
## explicitement choisie dans l'éditeur de maps.
const DEFAULT_REVEAL_ATLAS := Vector2i(0, 0)

## Atlas de la tuile que doit devenir `cell` une fois révélée (choisi dans
## l'éditeur de maps, ou Grass1 par défaut si non configuré).
func get_reveal_target(cell: Vector2i) -> Vector2i:
	return reveal_targets.get(cell, DEFAULT_REVEAL_ATLAS)

## Props posés sur `cell` tant qu'elle est "empty", à faire suivre l'animation
## de révélation (cf run_reveal_sequence()). Retire l'entrée : une case ne se
## révèle qu'une fois.
func get_props_for_cell(cell: Vector2i) -> Array[Sprite2D]:
	var props: Array[Sprite2D] = []
	for prop: Sprite2D in props_by_reveal_cell.get(cell, []):
		props.append(prop)
	props_by_reveal_cell.erase(cell)
	return props

func _ready() -> void:
	load_tile_defs()
	var override_id := get_map_id_override()
	if override_id != "":
		map_id = override_id
	load_map(map_id)
	# La caméra ne connaît rien de sa cible (générique/réutilisable) : c'est
	# ici, au niveau de la scène, qu'on la branche sur le curseur du Worldmap.
	camera.target = worldmap_cursor

	# Le "loop" d'un AudioStreamMP3 est une propriété de la ressource, pas du
	# lecteur : on la force ici plutôt que de dépendre du réglage d'import.
	music.stream.loop = true
	music.play()

# Permet au bouton "Play" de MapEditor de lancer le jeu directement sur la
# map en cours d'édition : `godot --path <projet> -- --map=<id>`. Les args
# après "--" ne sont pas interprétés par le moteur, donc on les lit ici.
func get_map_id_override() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			return arg.substr(6)
	return ""

# Lu directement depuis le même fichier que MapEditor : pas de duplication de
# la config d'animation à maintenir des deux côtés. Les frames peuvent être
# n'importe quelles cases de l'atlas (pas forcément des colonnes consécutives),
# donc on anime "à la main" plutôt que d'utiliser le système d'animation natif
# de TileSet, qui exige des cases contiguës.
func load_tile_defs() -> void:
	var path := "res://Sprites/tile_meta.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null:
		return
	for tile: Dictionary in data:
		var atlas: Array = tile.get("atlas", [0, 0])
		tile_defs["%d,%d" % [int(atlas[0]), int(atlas[1])]] = tile

func load_map(id: String) -> void:
	tile_layer.clear()
	for child in props_layer.get_children():
		child.queue_free()
	animated_cells.clear()
	animated_props.clear()
	reveal_targets.clear()
	props_by_reveal_cell.clear()

	var path := "res://maps/%s.json" % id
	if not FileAccess.file_exists(path):
		push_warning("Map not found: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null or not data.has("cells"):
		push_warning("Invalid map JSON: %s" % path)
		return

	for key: String in data["cells"].keys():
		var parts := key.split(",")
		var coords := Vector2i(int(parts[0]), int(parts[1]))
		var tile: Dictionary = data["cells"][key]
		var source_id: int = tile.get("source_id", 0)
		var atlas: Array = tile.get("atlas", [0, 0])
		tile_layer.set_cell(coords, source_id, Vector2i(int(atlas[0]), int(atlas[1])))

		if tile.has("reveal_atlas"):
			var reveal_atlas: Array = tile["reveal_atlas"]
			reveal_targets[coords] = Vector2i(int(reveal_atlas[0]), int(reveal_atlas[1]))

		var def: Dictionary = tile_defs.get("%d,%d" % [int(atlas[0]), int(atlas[1])], {})
		var frames: Array = def.get("frames", [])
		if frames.size() > 1:
			animated_cells.append({
				"coords": coords,
				"source_id": source_id,
				"frames": frames,
				"fps": float(def.get("fps", 4)),
				"last_idx": -1,
			})

	for prop: Dictionary in data.get("props", []):
		var frames: Array = prop.get("frames", [])
		var rect: Array = prop.get("rect", [0, 0, 0, 0])
		if frames.is_empty():
			frames = [rect]

		var sprite := Sprite2D.new()
		sprite.texture = props_texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(frames[0][0], frames[0][1], frames[0][2], frames[0][3])
		sprite.position = Vector2(prop.get("x", 0), prop.get("y", 0))
		sprite.z_index = prop.get("z_index", 0)
		props_layer.add_child(sprite)

		# Posé (dans l'éditeur de maps) sur une case encore "empty" au moment du
		# placement : reste caché jusqu'à ce que run_reveal_sequence() la révèle
		# (cf get_props_for_cell()).
		if prop.has("reveal_cell"):
			var reveal_cell: Array = prop["reveal_cell"]
			var cell := Vector2i(int(reveal_cell[0]), int(reveal_cell[1]))
			sprite.visible = false
			if not props_by_reveal_cell.has(cell):
				props_by_reveal_cell[cell] = []
			props_by_reveal_cell[cell].append(sprite)

		if frames.size() > 1:
			animated_props.append({
				"sprite": sprite,
				"frames": frames,
				"fps": float(prop.get("fps", 4)),
				"last_idx": -1,
			})

# Horloge globale (comme côté MapEditor) : les tuiles/props qui partagent le
# même fps restent animés en phase entre eux. On ne réécrit une case ou un
# region_rect que quand l'index de frame a réellement changé.
func _process(_delta: float) -> void:
	if animated_cells.is_empty() and animated_props.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0

	for anim: Dictionary in animated_cells:
		var frames: Array = anim["frames"]
		var idx := int(floor(now * anim["fps"])) % frames.size()
		if idx == anim["last_idx"]:
			continue
		anim["last_idx"] = idx
		var frame: Array = frames[idx]
		tile_layer.set_cell(anim["coords"], anim["source_id"], Vector2i(int(frame[0]), int(frame[1])))

	for anim: Dictionary in animated_props:
		var frames: Array = anim["frames"]
		var idx := int(floor(now * anim["fps"])) % frames.size()
		if idx == anim["last_idx"]:
			continue
		anim["last_idx"] = idx
		var frame: Array = frames[idx]
		(anim["sprite"] as Sprite2D).region_rect = Rect2(frame[0], frame[1], frame[2], frame[3])
