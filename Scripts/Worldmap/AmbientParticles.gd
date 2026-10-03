extends CPUParticles2D

## Particules d'ambiance du worldmap (poussière, pollen) : petits disques doux
## qui dérivent lentement dans l'air. Elles servent surtout la passe HD-2D : hors
## de la bande nette, chaque point lumineux devient un disque de bokeh, ce qui
## donne de la profondeur sans un seul asset. Texture générée procéduralement,
## comme HeroDustVFX.
##
## Les particules vivent en coordonnées MONDE (`local_coords = false`) : quand la
## caméra avance, elles restent où elles sont au lieu de se coller à l'écran. Le
## nœud, lui, suit la caméra pour n'émettre que là où on regarde. Naissance et
## mort passent par un fondu (alpha 0 aux deux bouts du `color_ramp`) : aucune
## particule n'apparaît ni ne disparaît d'un coup, même quand la caméra découvre
## une nouvelle zone.

## Caméra dont on suit le centre et le zoom.
@export var camera: Camera2D
@export var particle_color: Color = Color(1.0, 0.88, 0.55, 1.0)
## Particules par 1000 px² de MONDE visible (marge comprise). C'est une densité
## et non un nombre : le zoom (1 à 12) change l'aire visible, et un nombre fixe
## donnerait un brouillard à zoom 1 et presque rien à zoom 12.
@export_range(0.05, 3.0) var density: float = 0.12
## Diamètre des particules, en px monde (x4 à l'écran au zoom de base).
@export var size_px_min: float = 5.0
@export var size_px_max: float = 12.0
@export_range(2.0, 30.0) var particle_lifetime: float = 9.0

## Au-delà de l'écran : une particule née juste hors cadre a le temps de dériver
## dans le champ en fondu plutôt que d'y naître.
const MARGIN_PX := 40.0
const TEXTURE_SIZE := 16
## En-dessous de cet écart relatif, on ne touche pas à l'aire d'émission :
## changer `amount` relance tout le champ de particules, ce qui se verrait à
## chaque cran de molette si on le faisait au moindre changement.
const RESIZE_TOLERANCE := 0.25

var _applied_extents := Vector2.ZERO

func _ready() -> void:
	texture = _make_soft_disc()
	local_coords = false
	z_index = 11

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	emission_shape = EMISSION_SHAPE_RECTANGLE
	lifetime = particle_lifetime
	# Le champ est déjà rempli au lancement : sans ça, le monde démarre vide et
	# les particules mettent toute une durée de vie à s'installer.
	preprocess = particle_lifetime
	randomness = 1.0
	direction = Vector2(0.4, -1.0)
	spread = 180.0
	gravity = Vector2.ZERO
	initial_velocity_min = 1.5
	initial_velocity_max = 5.0
	tangential_accel_min = -2.0
	tangential_accel_max = 2.0
	scale_amount_min = size_px_min / TEXTURE_SIZE
	scale_amount_max = size_px_max / TEXTURE_SIZE

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(particle_color.r, particle_color.g, particle_color.b, 0.0),
		particle_color,
		particle_color,
		Color(particle_color.r, particle_color.g, particle_color.b, 0.0),
	])
	color_ramp = ramp
	_sync_to_camera()

func _process(_delta: float) -> void:
	_sync_to_camera()

# Appelé AUSSI depuis _ready : le pré-remplissage (`preprocess`) s'exécute dans
# la première mise à jour interne du nœud, AVANT le premier _process. Sans cette
# synchro, le champ est rempli autour de l'origine du monde, pas autour de la
# caméra, et l'écran démarre quasi vide.
func _sync_to_camera() -> void:
	if camera == null:
		return
	global_position = camera.get_screen_center_position()
	var visible_world := get_viewport().get_visible_rect().size / camera.zoom
	var extents := visible_world * 0.5 + Vector2(MARGIN_PX, MARGIN_PX)
	var ratio := extents / _applied_extents.max(Vector2.ONE)
	if absf(ratio.x - 1.0) > RESIZE_TOLERANCE or absf(ratio.y - 1.0) > RESIZE_TOLERANCE:
		_apply_extents(extents)

func _apply_extents(extents: Vector2) -> void:
	_applied_extents = extents
	emission_rect_extents = extents
	var area_k: float = extents.x * extents.y * 4.0 / 1000.0
	amount = maxi(1, ceili(area_k * density))

# Cœur net + halo doux : un simple disque en cloche paraît gris et minuscule
# dès qu'il est petit. Le cœur (alpha 1) donne le point lumineux, le halo en
# cloche donne la lueur que la passe HD-2D étirera en bokeh hors du plan net.
func _make_soft_disc() -> ImageTexture:
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEXTURE_SIZE, TEXTURE_SIZE) * 0.5
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var dist := (Vector2(x + 0.5, y + 0.5)).distance_to(center) / (TEXTURE_SIZE * 0.5)
			var halo: float = clampf(1.0 - dist, 0.0, 1.0)
			var core: float = 1.0 - smoothstep(0.12, 0.38, dist)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, maxf(core, halo * halo * 0.5)))
	return ImageTexture.create_from_image(img)
