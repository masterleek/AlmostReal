extends ColorRect

## Fond d'eau (water_reflection.gdshader), affiché derrière tout le
## TileMapLayer grâce à son propre z_index, pas un ordre particulier dans
## l'arbre. Taille fixe réglable directement (pas de découpage en tuiles ni
## de marge à calculer) ; seule la POSITION est calculée, pour rester
## centrée sur la carte quelle que soit sa géométrie.
@export var width: float = 1536.0
@export var height: float = 1536.0

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"

func _ready() -> void:
	z_index = -2
	mouse_filter = MOUSE_FILTER_IGNORE
	# tile_layer peut ne pas encore avoir ses cellules au tout premier frame
	# (chargées dans Main._ready(), un frère déclaré avant celui-ci) :
	# call_deferred attend que ce chargement soit terminé.
	call_deferred("fit_to_map")

## Centre le rect (taille fixe, cf width/height) sur les positions monde
## réelles de toutes les cellules chargées plutôt que sur min/max des
## coordonnées de cellule : reste correct quelle que soit la géométrie de la
## grille (hexagonale ici), où une cellule "extrême" en coordonnées n'est
## pas forcément celle la plus excentrée à l'écran.
func fit_to_map() -> void:
	var used := tile_layer.get_used_cells()
	if used.is_empty():
		return
	var min_pos: Vector2 = tile_layer.map_to_local(used[0])
	var max_pos: Vector2 = min_pos
	for cell: Vector2i in used:
		var p: Vector2 = tile_layer.map_to_local(cell)
		min_pos.x = minf(min_pos.x, p.x)
		min_pos.y = minf(min_pos.y, p.y)
		max_pos.x = maxf(max_pos.x, p.x)
		max_pos.y = maxf(max_pos.y, p.y)

	var center := (min_pos + max_pos) / 2.0
	size = Vector2(width, height)
	position = center - size / 2.0
