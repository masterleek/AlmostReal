extends CanvasLayer

## Passe de post-traitement « HD-2D » du worldmap (tilt-shift, bokeh, bloom,
## étalonnage, vignettage, lumière tachetée optionnelle). Tout le rendu vit dans
## `Shaders/hd2d_post.gdshader` et se règle sur le ShaderMaterial du ColorRect
## enfant (Inspecteur) : ce script ne fait QUE ce que le shader ne peut pas
## savoir seul — la caméra et la taille du canvas.
##
## Le calque doit rester ENTRE le monde (calque 0) et le HUD (calque 2) : plus
## bas il ne verrait rien, plus haut il floutrait aussi le compteur d'hex et les
## infobulles. Le combat (calque 10) est au-dessus de tout : il n'est pas touché.

## Caméra dont la position ancre la lumière tachetée au terrain. Sans elle, les
## plaques de lumière restent collées à l'écran au lieu de glisser avec le sol.
@export var camera: Camera2D

## Coupe toute la passe (comparaison avant/après, ou machine trop faible).
@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value

@onready var _material: ShaderMaterial = $Fx.material as ShaderMaterial

func _process(_delta: float) -> void:
	_material.set_shader_parameter("viewport_px", get_viewport().get_visible_rect().size)
	if camera != null:
		_material.set_shader_parameter("cam_pos", camera.get_screen_center_position())
		_material.set_shader_parameter("cam_zoom", camera.zoom.x)
