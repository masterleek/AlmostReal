extends Node2D

## Applique la mousse (tile_foam.gdshader) à TOUTES les tuiles de la carte,
## quel que soit leur type (grass, sand, "empty1" le brouillard, etc.) —
## contrairement au reflet (StartTileEffects.gd), resté scopé à la seule
## tuile de départ du Héros.
##
## Un ColorRect par tuile, tous partageant LA MÊME ShaderMaterial
## (foam_material, câblée dans l'Inspecteur, jamais dupliquée par tuile) : un
## seul point de réglage pour toute la carte dans l'Inspecteur, et le moteur
## les regroupe quand même en un seul batching de dessin (même matériau, pas
## de TEXTURE) malgré le nombre de nœuds. hex_verts/rect_size_px sont
## invariants d'une tuile à l'autre (même géométrie hexagonale partout) :
## réglés une fois pour toutes comme paramètres par défaut de ce matériau,
## jamais recalculés ici en script.
##
## La bande de mousse est volontairement dessinée EN DEHORS du contour hex
## (cf tile_foam.gdshader, hex_sdf > 0) : une TileMapLayer ne peut pas
## peindre hors des limites de sa propre case (chaque cellule y est limitée à
## son propre quad), d'où des ColorRect individuels plutôt qu'une seconde
## TileMapLayer ici.

@export var foam_material: ShaderMaterial

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"

func _ready() -> void:
	# tile_layer est peuplé par map_loader.gd (script du nœud Main, plus haut
	# dans l'arbre) dans son propre _ready() : on attend la fin de la passe
	# _ready pour être sûr que les cases existent déjà.
	call_deferred("setup")

func setup() -> void:
	for child in get_children():
		child.queue_free()
	if foam_material == null:
		return
	var foam_size: Vector2 = foam_material.get_shader_parameter("rect_size_px")
	for cell in tile_layer.get_used_cells():
		var tile_pos: Vector2 = tile_layer.map_to_local(cell)
		var foam := ColorRect.new()
		foam.size = foam_size
		foam.position = tile_pos - foam_size / 2.0
		foam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foam.color = Color(0, 0, 0, 0)
		foam.material = foam_material
		add_child(foam)
