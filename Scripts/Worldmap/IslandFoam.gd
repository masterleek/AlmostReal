extends Node2D

## Écume de rivage des îlots : une frange blanche irrégulière contre le bord, une
## eau peu profonde turquoise en dégradé, et les reflets de l'eau (les mêmes
## traits que WaterReflection) qui restent nets par-dessus.
##
## Tout part d'UNE donnée : la distance de chaque pixel d'eau à la silhouette
## réelle des tuiles. Elle est tirée du masque que IslandShadow construit déjà
## (même copie des cases, même TileSet), puis transformée en carte de distance
## EXACTE une seule fois (transformation de Felzenszwalb, deux passes 1D). Le
## shader n'a plus qu'à lire un nombre de pixels : frange, teinte et reflets sont
## des fonctions de cette distance, d'où un motif qui épouse n'importe quel
## contour — sans rien tester par tuile et sans superposer les bandes de deux
## tuiles voisines.
##
## À placer APRÈS IslandShadow dans l'arbre, avec un z_index de -1 : un cran AU-
## DESSUS de l'ombre et du reflet des tuiles (z_index -2), qu'elle doit recouvrir
## quel que soit leur ordre dans l'arbre, et dans le même plan que les tuiles
## (placée avant elles dans l'arbre, elles recouvrent la partie intérieure ; seule
## la bande côté eau reste visible).
##
## Même limite que IslandShadow : la carte est calculée une fois. Une case
## révélée ensuite change un peu de silhouette ; appeler setup() sur
## IslandShadow la recalcule (ce nœud écoute son signal).

## L'ombre dont on réutilise le masque (nœud IslandShadow).
@export var shadow: Node2D
## Le fond d'eau (nœud WaterReflection) : ses reflets sont redessinés dans la
## bande d'écume avec ses textures de bruit et ses seuils.
@export var water: ColorRect
## Largeur (px monde) de la zone d'eau couverte. Doit rester sous la marge laissée
## autour du masque (~38 px).
@export_range(8.0, 36.0) var band_px: float = 28.0

const FOAM_SHADER := preload("res://Shaders/island_foam.gdshader")
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

func _ready() -> void:
	if shadow == null:
		return
	shadow.connect("mask_changed", _on_mask_changed)
	# Si IslandShadow a déjà construit son masque avant notre _ready.
	if shadow.get("mask_texture") != null:
		_on_mask_changed()

func _on_mask_changed() -> void:
	# Le SubViewport n'est rempli qu'après un rendu : on attend deux images avant
	# de relire ses pixels.
	await get_tree().process_frame
	await get_tree().process_frame
	# Sans rendu (--headless), le SubViewport n'a pas de pixels à relire.
	if DisplayServer.get_name() == "headless":
		return
	var texture: Texture2D = shadow.get("mask_texture")
	var mask_rect: Rect2 = shadow.get("mask_rect")
	if texture == null:
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var width: int = image.get_width()
	var height: int = image.get_height()
	var distance := _distance_field(image.get_data(), width, height)
	var field := Image.create_from_data(width, height, false, Image.FORMAT_RF, distance.to_byte_array())
	var field_texture := ImageTexture.create_from_image(field)

	if _rect == null:
		_rect = ColorRect.new()
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.color = Color(0, 0, 0, 0)
		_rect.material = ShaderMaterial.new()
		(_rect.material as ShaderMaterial).shader = FOAM_SHADER
		add_child(_rect)
	_rect.position = mask_rect.position
	_rect.size = Vector2(width, height)
	var material := _rect.material as ShaderMaterial
	material.set_shader_parameter("distance_field", field_texture)
	material.set_shader_parameter("origin_px", mask_rect.position)
	material.set_shader_parameter("size_px", Vector2(width, height))
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
	material.set_shader_parameter("water_origin", water.position)
	material.set_shader_parameter("water_size", water.size)

## Distance (en px) de chaque pixel au pixel opaque le plus proche, rangée ligne
## par ligne. `data` est une image RGBA8 : l'alpha (4e octet) dit « dans une tuile ».
func _distance_field(data: PackedByteArray, width: int, height: int) -> PackedFloat32Array:
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
func _transform_1d(f: PackedFloat32Array, n: int, out: PackedFloat32Array, v: PackedInt32Array, z: PackedFloat32Array) -> void:
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
