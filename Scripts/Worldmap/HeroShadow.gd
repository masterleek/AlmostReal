extends Sprite2D

## Ombre dynamique du Héros : silhouette aplatie au sol et inclinée
## (shadow_skew) façon ombre portée par une lumière fixe, teintée en noir
## semi-transparent. Toujours dans l'orientation "gauche" (profil, cf
## Hero.Pose.LEFT) quelle que soit la pose réelle du Héros — un profil se lit
## naturellement comme une ombre projetée une fois aplati, contrairement à une
## pose face/dos ; jamais retournée (flip_h) non plus, pour rester un repère
## visuel stable. Toujours animée (cycle de marche du Héros pendant qu'il se
## déplace, pose statique à l'arrêt). Découpée par hex_tile_clip.gdshader pour
## ne jamais dépasser le contour réel (pas la hitzone logique) de la tuile
## visuellement sous elle — recalculée chaque frame d'après sa propre position
## à l'écran (pas Hero.current_cell, qui bascule sur la case de destination dès
## le début d'un pas, avant l'arrivée visuelle du Héros).

@export_range(0.0, 1.0) var shadow_alpha: float = 0.45
@export_range(0.1, 1.0) var squash: float = 0.45
## Décalage vertical local additionnel (pixels), pour caler l'ombre pile aux
## pieds à l'oeil une fois en jeu.
@export var feet_offset: float = 0.0
## Inclinaison (radians) façon "ombre portée" par une lumière fixe en
## haut-gauche : l'ombre s'étire vers le bas-droite au lieu de tomber pile à
## la verticale sous les pieds. 0 = pas d'inclinaison.
@export_range(-1.5, 1.5) var shadow_skew: float = 0.5

@onready var hero: Sprite2D = get_parent()
@onready var cursor := $"../../WorldmapCursor"
@onready var tile_layer: TileMapLayer = $"../../TileMapLayer"

func _ready() -> void:
	region_enabled = true
	modulate = Color(0.0, 0.0, 0.0, shadow_alpha)
	flip_h = false
	material = ShaderMaterial.new()
	material.shader = load("res://Shaders/hex_tile_clip.gdshader")
	z_as_relative = true
	z_index = -1 # toujours juste derrière le Héros (jamais devant)

func _process(_delta: float) -> void:
	# Pas dans _ready() : les enfants sont initialisés avant leur parent en
	# Godot, donc hero.texture (posé dans Hero._ready()) n'existerait pas
	# encore à ce moment-là.
	texture = hero.texture
	if hero.is_moving:
		var frames: Array = hero.WALK_FRAMES[hero.Pose.LEFT]
		var idx := int(floor(Time.get_ticks_msec() / 1000.0 * hero.WALK_FPS)) % frames.size()
		region_rect = frames[idx]
	else:
		region_rect = hero.IDLE_FRAMES[hero.Pose.LEFT]

	scale.y = squash
	skew = shadow_skew
	# hero.offset décale le rendu du Héros sans bouger son origine logique
	# (ex. Vector2(0,-16) réglé dans l'éditeur) : l'ombre, enfant séparé, doit
	# le reprendre pour rester alignée avec les pieds réellement affichés.
	position.y = hero.offset.y + region_rect.size.y * (1.0 - squash) * 0.5 + feet_offset

	var cell: Vector2i = cursor.find_hovered_cell(global_position)
	var has_tile := tile_layer.get_cell_tile_data(cell) != null
	material.set_shader_parameter("has_tile", has_tile)
	if has_tile:
		var tile_center := tile_layer.to_global(tile_layer.map_to_local(cell))
		material.set_shader_parameter("tile_center_world", tile_center)
