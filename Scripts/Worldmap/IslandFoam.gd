extends Node2D

## Écume de rivage des îlots : une frange blanche irrégulière contre le bord, une
## eau peu profonde turquoise en dégradé, et les reflets de l'eau (les mêmes
## traits que WaterReflection) qui restent nets par-dessus.
##
## Tout part d'UNE donnée : la distance de chaque pixel d'eau à la silhouette
## réelle des tuiles. La silhouette est reconstruite SUR LE PROCESSEUR, en collant
## l'alpha de chaque tuile (région de l'atlas) à sa place dans une image : pas de
## SubViewport à rendre ni de relecture GPU, donc rien à attendre — une première
## version relisait le masque d'IslandShadow et perdait ~300 ms avant que l'écume
## n'apparaisse au lancement. Elle est ensuite transformée en carte de distance
## EXACTE (transformation de Felzenszwalb, deux passes 1D) dans un fil de travail :
## ~130 ms de calcul qui, sur le fil principal, gelaient le jeu — sauf au lancement,
## où il vaut mieux les payer AVANT le premier rendu que de voir l'écume apparaître
## après coup. Le shader n'a plus
## qu'à lire un nombre de pixels : frange, teinte et reflets sont des fonctions de
## cette distance, d'où un motif qui épouse n'importe quel contour — sans rien
## tester par tuile et sans superposer les bandes de deux tuiles voisines.
##
## À placer avant les tuiles dans l'arbre, avec un z_index de -1 : un cran AU-DESSUS
## de l'ombre et du reflet des tuiles (z_index -2), qu'elle doit recouvrir quel que
## soit leur ordre dans l'arbre, et dans le même plan que les tuiles (placée avant
## elles, elles recouvrent la partie intérieure ; seule la bande côté eau reste
## visible).
##
## Limite : la silhouette est calculée une fois. Une case révélée ensuite change un
## peu de silhouette ; appeler setup() la recalcule (dans un fil de travail).

## La couche de tuiles dont on suit la silhouette.
@export var tile_layer: TileMapLayer
## Le fond d'eau (nœud WaterReflection) : ses reflets sont redessinés dans la
## bande d'écume avec ses textures de bruit et ses seuils.
@export var water: ColorRect
## Largeur (px monde) de la zone d'eau couverte.
@export_range(8.0, 36.0) var band_px: float = 28.0

const FOAM_SHADER := preload("res://Shaders/island_foam.gdshader")
# L'art d'une tuile occupe sa case de 64×64, centrée sur map_to_local().
const CELL_HALF := 32.0
# Paramètres du matériau de l'eau recopiés tels quels dans celui de l'écume : les
# deux shaders déclarent les mêmes noms, donc un réglage de l'eau se retrouve ici.
const WATER_PARAMS: PackedStringArray = [
	"reflection_color",
	"reflect_big_noise", "reflect_big_tiles", "reflect_big_thresh_top", "reflect_big_thresh_bottom",
	"reflect_small_noise", "reflect_small_tiles", "reflect_small_thresh_top", "reflect_small_thresh_bottom",
	"reflect_hole_noise", "reflect_hole_tiles", "reflect_hole_threshold",
	"reflect_speed", "reflect_direction",
	"reflect_warp_noise", "reflect_warp_tiles", "reflect_warp_strength",
]
# Valeur « infiniment loin » pour les pixels sans source : assez grande pour que
# les paraboles ne s'en approchent jamais, assez petite pour rester exacte en flottant.
const FAR := 1.0e9

var _rect: ColorRect
# Numéro du dernier calcul lancé : un résultat plus ancien que lui est jeté.
var _generation := 0
# Tâche de calcul en cours (-1 : aucune), pour l'attendre avant de quitter.
var _task_id := -1

func _ready() -> void:
	# tile_layer est peuplé par map_loader.gd dans son propre _ready() : on
	# attend que la passe soit finie pour que les cases existent déjà.
	# Calcul SYNCHRONE au lancement : il s'exécute avant le tout premier rendu, donc
	# la frange est déjà là à la première image au lieu d'apparaître ~140 ms après.
	call_deferred("setup", false)

func _exit_tree() -> void:
	# Le fil de travail rappelle ce nœud à la fin de son calcul : on l'attend pour
	# ne jamais l'appeler une fois le nœud libéré (fermeture du jeu en plein calcul).
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

## `threaded` : calcule la carte de distance dans un fil de travail (la frange se
## met à jour quand il a fini, sans geler le jeu) plutôt que tout de suite. À
## vrai pour un recalcul en cours de partie, à faux au lancement.
func setup(threaded: bool = true) -> void:
	if tile_layer == null:
		return
	var used := tile_layer.get_used_cells()
	if used.is_empty():
		return

	# Cadre de l'image : toutes les cases, plus la bande d'écume tout autour.
	var first: Vector2 = tile_layer.position + tile_layer.map_to_local(used[0])
	var bounds := Rect2(first - Vector2(CELL_HALF, CELL_HALF), Vector2(CELL_HALF, CELL_HALF) * 2.0)
	for cell: Vector2i in used:
		var centre: Vector2 = tile_layer.position + tile_layer.map_to_local(cell)
		bounds = bounds.expand(centre - Vector2(CELL_HALF, CELL_HALF))
		bounds = bounds.expand(centre + Vector2(CELL_HALF, CELL_HALF))
	var margin := Vector2.ONE * (ceilf(band_px) + 4.0)
	var origin: Vector2 = (bounds.position - margin).floor()
	var size := Vector2i((bounds.end + margin - origin).ceil())

	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_stamp_tiles(mask, used, origin)

	_generation += 1
	var generation := _generation
	var data := mask.get_data()
	if not threaded:
		_apply(_distance_field(data, size.x, size.y), size, origin, generation)
		return
	# Le calcul tourne dans un fil de travail ; seul son résultat revient ici.
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var distance := _distance_field(data, size.x, size.y)
		_apply.call_deferred(distance, size, origin, generation)
	)

## Colle l'alpha de chaque tuile à sa place : même géométrie que le TileMapLayer
## (centre de la case, moins la moitié de la région et le décalage de texture).
func _stamp_tiles(mask: Image, used: Array[Vector2i], origin: Vector2) -> void:
	var tile_set := tile_layer.tile_set
	var atlases := {}
	for cell: Vector2i in used:
		var source_id: int = tile_layer.get_cell_source_id(cell)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		if not atlases.has(source_id):
			var atlas := source.texture.get_image()
			if atlas.is_compressed():
				atlas.decompress()
			atlas.convert(Image.FORMAT_RGBA8)
			atlases[source_id] = atlas
		var coords: Vector2i = tile_layer.get_cell_atlas_coords(cell)
		var region: Rect2i = source.get_tile_texture_region(coords)
		var tile_data := source.get_tile_data(coords, 0)
		var centre: Vector2 = tile_layer.position + tile_layer.map_to_local(cell)
		var top_left: Vector2 = centre - Vector2(region.size) / 2.0 - Vector2(tile_data.texture_origin) - origin
		mask.blend_rect(atlases[source_id], region, Vector2i(top_left.round()))

## Reçoit la carte de distance calculée en fil de travail et la branche sur le shader.
func _apply(distance: PackedFloat32Array, size: Vector2i, origin: Vector2, generation: int) -> void:
	# Un setup() plus récent est déjà parti : ce résultat est périmé.
	if generation != _generation:
		return
	var field := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, distance.to_byte_array())
	var field_texture := ImageTexture.create_from_image(field)

	if _rect == null:
		_rect = ColorRect.new()
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.color = Color(0, 0, 0, 0)
		_rect.material = ShaderMaterial.new()
		(_rect.material as ShaderMaterial).shader = FOAM_SHADER
		add_child(_rect)
	_rect.position = origin
	_rect.size = Vector2(size)
	var material := _rect.material as ShaderMaterial
	material.set_shader_parameter("distance_field", field_texture)
	material.set_shader_parameter("origin_px", origin)
	material.set_shader_parameter("size_px", Vector2(size))
	material.set_shader_parameter("band_px", band_px)
	_copy_water_params(material)

## Recopie les paramètres de reflet du matériau de l'eau, et le rectangle qu'elle
## occupe. Les paramètres absents (nouveau réglage jamais touché) gardent le
## défaut du shader de l'écume.
func _copy_water_params(material: ShaderMaterial) -> void:
	if water == null or not (water.material is ShaderMaterial):
		return
	var water_material := water.material as ShaderMaterial
	for param_name in WATER_PARAMS:
		var value: Variant = water_material.get_shader_parameter(param_name)
		if value != null:
			material.set_shader_parameter(param_name, value)
	# Un Control est dessiné à une position ENTIÈRE (gui/common/snap_controls_to_pixels) :
	# la position fractionnaire de l'eau (ici y = -112,5, centre d'une carte à
	# nombre pair de rangées) est arrondie vers le haut à l'écran. Utiliser la valeur
	# brute décalait nos reflets d'un demi-pixel par rapport aux siens, et chaque
	# trait se doublait d'un fantôme.
	material.set_shader_parameter("water_origin", (water.position + Vector2(0.5, 0.5)).floor())
	material.set_shader_parameter("water_size", water.size)

## Distance (en px) de chaque pixel au pixel opaque le plus proche, rangée ligne
## par ligne. `data` est une image RGBA8 : l'alpha (4e octet) dit « dans une tuile ».
## Statique et sans nœud : appelée depuis un fil de travail, où l'instance du nœud
## n'a pas à être touchée.
static func _distance_field(data: PackedByteArray, width: int, height: int) -> PackedFloat32Array:
	var cells := PackedFloat32Array()
	cells.resize(width * height)
	for i in width * height:
		cells[i] = 0.0 if data[i * 4 + 3] > 127 else FAR

	var longest: int = maxi(width, height)
	var line := PackedFloat32Array()
	line.resize(longest)
	var result := PackedFloat32Array()
	result.resize(longest)
	var parabola := PackedInt32Array()
	parabola.resize(longest)
	var bounds := PackedFloat32Array()
	bounds.resize(longest + 1)

	for x in width:
		for y in height:
			line[y] = cells[y * width + x]
		_transform_1d(line, height, result, parabola, bounds)
		for y in height:
			cells[y * width + x] = result[y]
	for y in height:
		var row: int = y * width
		for x in width:
			line[x] = cells[row + x]
		_transform_1d(line, width, result, parabola, bounds)
		for x in width:
			cells[row + x] = sqrt(result[x])
	return cells

## Une passe 1D de la transformation de distance : enveloppe inférieure des
## paraboles y = f[q] + (x - q)², puis lecture de cette enveloppe en chaque x.
static func _transform_1d(f: PackedFloat32Array, n: int, out: PackedFloat32Array, v: PackedInt32Array, z: PackedFloat32Array) -> void:
	var k := 0
	v[0] = 0
	z[0] = -FAR
	z[1] = FAR
	for q in range(1, n):
		var fq: float = f[q] + float(q * q)
		var s: float = (fq - (f[v[k]] + float(v[k] * v[k]))) / float(2 * q - 2 * v[k])
		while s <= z[k]:
			k -= 1
			s = (fq - (f[v[k]] + float(v[k] * v[k]))) / float(2 * q - 2 * v[k])
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = FAR
	k = 0
	for q in n:
		while z[k + 1] < float(q):
			k += 1
		var dq: float = float(q - v[k])
		out[q] = dq * dq + f[v[k]]
