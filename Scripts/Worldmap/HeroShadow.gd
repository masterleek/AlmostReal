extends Sprite2D

## Ombre dynamique du Héros : simple ellipse sombre semi-transparente sous ses
## pieds (dessinée procéduralement par hero_shadow_ellipse.gdshader, aucun
## asset nécessaire), pas la silhouette du personnage. Découpée par ce même
## shader pour ne jamais dépasser le contour réel (pas la hitzone logique) de
## la tuile visuellement sous elle — recalculée chaque frame d'après sa
## propre position à l'écran (pas Hero.current_cell, qui bascule sur la case
## de destination dès le début d'un pas, avant l'arrivée visuelle du Héros).

@export_range(0.0, 1.0) var shadow_alpha: float = 0.45
## Taille de l'ellipse en pixels (largeur, hauteur).
@export var shadow_size: Vector2 = Vector2(22, 10)
## Décalage vertical local additionnel (pixels), pour caler l'ombre pile aux
## pieds à l'oeil une fois en jeu.
@export var feet_offset: float = 0.0

@onready var hero: Sprite2D = get_parent()
@onready var cursor := $"../../WorldmapCursor"
@onready var tile_layer: TileMapLayer = $"../../TileMapLayer"

func _ready() -> void:
	# Pixel blanc 1x1 : la forme réelle de l'ellipse vient entièrement du
	# shader (calculée depuis l'UV), pas besoin d'asset dédié.
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	modulate = Color(0.0, 0.0, 0.0, shadow_alpha)
	material = ShaderMaterial.new()
	material.shader = load("res://Shaders/hero_shadow_ellipse.gdshader")
	z_as_relative = true
	z_index = -1 # toujours juste derrière le Héros (jamais devant)

func _process(_delta: float) -> void:
	scale = shadow_size
	# hero.offset décale le rendu du Héros sans bouger son origine logique
	# (ex. Vector2(0,-16) réglé dans l'éditeur) : l'ombre, enfant séparé, doit
	# le reprendre pour rester alignée avec les pieds réellement affichés.
	position.y = hero.offset.y + hero.region_rect.size.y * 0.5 + feet_offset

	var cell: Vector2i = cursor.find_hovered_cell(global_position)
	var has_tile := tile_layer.get_cell_tile_data(cell) != null
	material.set_shader_parameter("has_tile", has_tile)
	if has_tile:
		var tile_center := tile_layer.to_global(tile_layer.map_to_local(cell))
		material.set_shader_parameter("tile_center_world", tile_center)
