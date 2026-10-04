extends Node2D

## Ombre portée douce des îlots sur l'eau. La silhouette de toutes les tuiles
## est dessinée en noir dans un SubViewport (copie des mêmes cases, même TileSet :
## aucun asset), puis affichée floutée par island_shadow_blur.gdshader et
## décalée vers le bas-droite (lumière venue du haut-gauche, comme l'arête
## éclairée des tuiles).
##
## À placer dans l'arbre APRÈS le fond d'eau et AVANT les tuiles, avec un
## z_index sous celui des tuiles : l'ordre d'affichage vient du z_index et de
## la place dans l'arbre, pas de ce script.
##
## Limite connue : la copie est faite une fois (comme TileReflectionFlat). Une
## case révélée pendant la partie change un peu de silhouette (le dessus de
## « Empty » est 11 px plus bas) sans que l'ombre ne suive. L'écart est de
## l'ordre de la pénombre ; si ça se voit, appeler setup() après la révélation.

@export var tile_layer: TileMapLayer
## Décalage de l'ombre en px monde (x vers la droite, y vers le bas).
@export var shadow_offset: Vector2 = Vector2(6.0, 13.0)
@export_range(0.0, 24.0) var blur_radius_px: float = 9.0
@export_range(0.0, 1.0) var shadow_alpha: float = 0.42
@export var shadow_color: Color = Color(0.0, 0.05, 0.15)

const FLAT_SHADER := preload("res://Shaders/tile_reflection_flat.gdshader")
const BLUR_SHADER := preload("res://Shaders/island_shadow_blur.gdshader")
# L'art d'une tuile occupe sa case de 64×64, centrée sur map_to_local().
const CELL_HALF := 32.0
# Marge en plus du flou : une case en cours de révélation se soulève de ~24 px
# et ne doit pas être rognée par le bord du viewport.
const LIFT_MARGIN := 24.0

## Émis quand le masque (silhouette noire des tuiles) vient d'être (re)construit.
## IslandFoam.gd s'en sert pour recalculer sa distance au rivage.
signal mask_changed

## Texture du masque et rectangle qu'elle occupe en pixels MONDE (1 px de
## texture = 1 px monde). Valides après le premier setup().
var mask_texture: Texture2D
var mask_rect: Rect2

var _viewport: SubViewport
var _mask_layer: TileMapLayer
var _sprite: Sprite2D

func _ready() -> void:
	# tile_layer est peuplé par map_loader.gd dans son propre _ready() : on
	# attend que la passe soit finie pour que les cases existent déjà.
	call_deferred("setup")

func setup() -> void:
	if tile_layer == null:
		return
	var used := tile_layer.get_used_cells()
	if used.is_empty():
		return

	var first: Vector2 = tile_layer.position + tile_layer.map_to_local(used[0])
	var bounds := Rect2(first - Vector2(CELL_HALF, CELL_HALF), Vector2(CELL_HALF, CELL_HALF) * 2.0)
	for cell: Vector2i in used:
		var centre: Vector2 = tile_layer.position + tile_layer.map_to_local(cell)
		bounds = bounds.expand(centre - Vector2(CELL_HALF, CELL_HALF))
		bounds = bounds.expand(centre + Vector2(CELL_HALF, CELL_HALF))
	var margin := Vector2.ONE * (ceilf(blur_radius_px * 1.5) + LIFT_MARGIN)

	_clear()

	_viewport = SubViewport.new()
	_viewport.size = Vector2i((bounds.size + margin * 2.0).ceil())
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var flat := ShaderMaterial.new()
	flat.shader = FLAT_SHADER
	flat.set_shader_parameter("flat_color", Color(0.0, 0.0, 0.0, 1.0))
	flat.set_shader_parameter("use_gradient", false)
	flat.set_shader_parameter("alpha", 1.0)
	_mask_layer = TileMapLayer.new()
	_mask_layer.tile_set = tile_layer.tile_set
	_mask_layer.material = flat
	_mask_layer.position = margin - bounds.position
	_viewport.add_child(_mask_layer)
	for cell: Vector2i in used:
		_mask_layer.set_cell(cell, tile_layer.get_cell_source_id(cell), tile_layer.get_cell_atlas_coords(cell))

	var blur := ShaderMaterial.new()
	blur.shader = BLUR_SHADER
	blur.set_shader_parameter("radius_px", blur_radius_px)
	blur.set_shader_parameter("shadow_alpha", shadow_alpha)
	blur.set_shader_parameter("shadow_color", shadow_color)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = _viewport.get_texture()
	# Le projet est en nearest par défaut : le flou doit être interpolé.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.material = blur
	_sprite.position = bounds.position - margin + shadow_offset
	add_child(_sprite)

	mask_texture = _viewport.get_texture()
	mask_rect = Rect2(bounds.position - margin, Vector2(_viewport.size))
	mask_changed.emit()

func _clear() -> void:
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null
