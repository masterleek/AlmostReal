extends Node2D

## Reflet de la tuile de départ du Héros — scopé à cette UNIQUE tuile
## (contrairement à la mousse, cf MapFoam.gd, appliquée à toute la carte).
## Un enfant pré-déclaré dans la scène : StartTileReflection (Sprite2D,
## copie retournée de l'art de la tuile) — ce script se contente de le
## positionner/dimensionner d'après la case réelle du Héros.

## Décalage manuel (pixels monde, + = vers le bas) de la position verticale
## du reflet — s'ajoute au calcul automatique (juste sous le bord réel de la
## tuile), pour ajuster à la main sans recalculer.
@export var reflection_y_offset: float = 0.0:
	set(value):
		reflection_y_offset = value
		if is_inside_tree():
			call_deferred("setup")

## Opacité (0..1) du reflet — indépendante de la teinte ci-dessous.
@export_range(0.0, 1.0) var reflection_opacity: float = 0.7:
	set(value):
		reflection_opacity = value
		if is_inside_tree():
			call_deferred("setup")

## Teinte du reflet et force du mélange — PAS un modulate (une simple
## multiplication avec l'art d'origine, terne/peu visible sur des couleurs
## déjà saturées comme le vert de la tuile) : un petit shader dédié
## (tile_reflection_tint.gdshader) MÉLANGE cette couleur par-dessus, avec
## cette force. 0 = art d'origine inchangé, 1 = silhouette entièrement de
## cette couleur.
@export var reflection_tint: Color = Color(0.6, 0.75, 1.0):
	set(value):
		reflection_tint = value
		if is_inside_tree():
			call_deferred("setup")
@export_range(0.0, 1.0) var reflection_tint_strength: float = 0.5:
	set(value):
		reflection_tint_strength = value
		if is_inside_tree():
			call_deferred("setup")

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var hero: Node2D = $"../Hero"
@onready var reflection_sprite: Sprite2D = $StartTileReflection

func _ready() -> void:
	# hero.current_cell n'est fixé que dans Hero._ready() (un frère déclaré
	# après celui-ci) : call_deferred attend que ce soit fait.
	call_deferred("setup")

func setup() -> void:
	var cell: Vector2i = hero.current_cell
	var tile_pos: Vector2 = tile_layer.map_to_local(cell)
	var source_id := tile_layer.get_cell_source_id(cell)
	var atlas_coords := tile_layer.get_cell_atlas_coords(cell)
	var atlas_source := tile_layer.tile_set.get_source(source_id) as TileSetAtlasSource
	var region: Rect2i = atlas_source.get_tile_texture_region(atlas_coords)

	# Reflet : même art que la tuile, retourné verticalement, positionné pour
	# que son propre haut (après flip_v, le bas réel de l'art d'origine)
	# démarre exactement où l'art de la tuile s'arrête — un miroir continu,
	# pas un décalage arbitraire.
	reflection_sprite.texture = atlas_source.texture
	reflection_sprite.region_enabled = true
	reflection_sprite.region_rect = Rect2(region)
	reflection_sprite.flip_v = true
	reflection_sprite.position = tile_pos + Vector2(0.0, float(region.size.y) + reflection_y_offset)
	reflection_sprite.z_index = -1
	if reflection_sprite.material is ShaderMaterial:
		var reflection_mat := reflection_sprite.material as ShaderMaterial
		reflection_mat.set_shader_parameter("tint_color", reflection_tint)
		reflection_mat.set_shader_parameter("tint_strength", reflection_tint_strength)
		reflection_mat.set_shader_parameter("reflection_opacity", reflection_opacity)
