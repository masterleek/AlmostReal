extends TileMapLayer

## Reflet plat de TOUTES les tuiles de la carte, quel que soit leur type
## (grass/sand/empty1/...) : copie non retournée des mêmes cases (même
## TileSet, donc même art, aucune ressource dupliquée), recolorée en une
## couleur/dégradé unique par tile_reflection_flat.gdshader — seul le canal
## alpha de l'art d'origine sert de silhouette, sa couleur réelle est
## ignorée. Pas de flip (TRANSFORM_FLIP_V posait problème sur l'art "bloc"
## pseudo-3D des tuiles, cf l'historique de CoastalWaterEffects.gd — la face
## haute et les flancs du bloc finissaient mal alignés) : juste un décalage
## vertical (position.y, réglable directement dans l'Inspecteur — Transform)
## et une opacité réglable (shader_parameter/alpha sur le matériau). Un seul
## nœud TileMapLayer batché nativement par le moteur quel que soit le nombre
## de tuiles — la solution la plus performante ici, sans nœud par tuile.

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"

func _ready() -> void:
	# tile_layer est peuplé par map_loader.gd (script du nœud Main, plus haut
	# dans l'arbre) dans son propre _ready() : on attend la fin de la passe
	# _ready pour être sûr que les cases existent déjà.
	call_deferred("setup")

func setup() -> void:
	clear()
	var used := tile_layer.get_used_cells()
	for cell: Vector2i in used:
		set_cell(cell, tile_layer.get_cell_source_id(cell), tile_layer.get_cell_atlas_coords(cell))

	# Bornes réelles de la carte (mêmes positions monde que le TileMapLayer
	# d'origine, sans le décalage vertical du reflet) : le dégradé du shader
	# s'étend sur toute la carte plutôt que de se répéter tuile par tuile.
	if used.is_empty() or not (material is ShaderMaterial):
		return
	var min_y: float = tile_layer.map_to_local(used[0]).y
	var max_y: float = min_y
	for cell: Vector2i in used:
		var y: float = tile_layer.map_to_local(cell).y
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("gradient_y_min", min_y)
	mat.set_shader_parameter("gradient_y_max", max_y)
