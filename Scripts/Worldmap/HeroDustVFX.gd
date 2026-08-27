extends CPUParticles2D

## Petit nuage de poussière déclenché à chaque case franchie par le Héros (un
## burst par pas, pas en continu) — détecté en observant les changements de
## Hero.current_cell plutôt que via un signal dédié, pour ne rien changer à
## Hero.gd. Texture (petit disque flou) générée procéduralement, aucun asset
## nécessaire.

@export var particle_color: Color = Color(0.75, 0.68, 0.55, 0.6)
@export_range(1, 30) var particle_amount: int = 8
@export_range(0.1, 1.0) var particle_lifetime: float = 0.35

@onready var hero: Sprite2D = get_parent()

var last_cell: Vector2i

func _ready() -> void:
	last_cell = hero.current_cell
	texture = _make_dust_texture()
	z_as_relative = true
	z_index = -1 # même couche que l'ombre, toujours derrière le Héros

	emitting = false
	one_shot = true
	explosiveness = 1.0
	amount = particle_amount
	lifetime = particle_lifetime
	direction = Vector2.UP
	spread = 150.0
	gravity = Vector2(0, 40)
	initial_velocity_min = 10.0
	initial_velocity_max = 22.0
	scale_amount_min = 0.5
	scale_amount_max = 1.0

	var ramp := Gradient.new()
	ramp.set_color(0, particle_color)
	ramp.set_color(1, Color(particle_color.r, particle_color.g, particle_color.b, 0.0))
	color_ramp = ramp

func _process(_delta: float) -> void:
	# Même repère que HeroShadow : suit les pieds réellement affichés (donc
	# hero.offset), pas le centre du sprite.
	position.y = hero.offset.y + hero.region_rect.size.y * 0.5

	if hero.is_moving and hero.current_cell != last_cell:
		restart()
	last_cell = hero.current_cell

# Petit disque au dégradé doux (alpha en cloche) : pas besoin d'asset dédié,
# les particules sont ensuite teintées par `color_ramp`.
func _make_dust_texture() -> ImageTexture:
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center) / (size * 0.5)
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
