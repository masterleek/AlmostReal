extends Node

## Zoom manuel d'un CanvasLayer : molette, pincement à deux doigts, et touche 0
## pour revenir à la taille réelle. Mêmes gestes que la caméra du worldmap
## (cf. CameraController), pour qu'un écran à l'autre la manipulation soit la
## même.
##
## POURQUOI UN SCRIPT À PART plutôt que de réutiliser CameraController : une
## Camera2D n'a aucun effet sur un CanvasLayer — c'est même la raison d'être
## d'un calque, se placer hors de la caméra. Le zoom passe donc par la
## transformation du calque lui-même, ce qui n'a rien à voir avec le code de
## suivi de la caméra. Le nœud est en revanche générique : à poser comme enfant
## de n'importe quel CanvasLayer à piloter.

## Sensibilité proche du worldmap (sa molette avance d'un huitième de la
## taille de base par cran), arrondie au quantum ci-dessous.
@export var zoom_step: float = 0.25

## Tous les niveaux de zoom sont des multiples de ce pas, y compris ceux
## atteints au pincement. Ce n'est pas un caprice : le décor est de la pixel-art
## agrandie ×4, donc un pixel de design occupe 4·zoom pixels d'écran. Tant que
## ce produit est entier, chaque pixel reste un bloc régulier ; sinon les blocs
## alternent (5 px, 6 px, 5 px…) et l'image paraît sale. Avec un quart, 4·zoom
## vaut toujours un entier. C'est le seul écart de comportement avec le zoom
## continu de la caméra du worldmap, et il est délibéré.
@export var zoom_quantum: float = 0.25
## Pas de dézoom sous la taille réelle : l'écran occupe exactement le cadre,
## réduire ne montrerait que du vide autour. C'est le seul écart avec le
## worldmap, qui lui peut s'éloigner de la carte.
@export var zoom_min: float = 1.0
## Même plafond relatif que le worldmap (12 pour une base de 4, soit ×3).
@export var zoom_max: float = 3.0

## Deux valeurs, et c'est indispensable : `_requested` est le zoom continu tel
## que l'utilisateur l'a demandé, `_zoom` est sa version quantifiée, seule
## affichée. Réinjecter la valeur quantifiée dans le calcul suivant détruirait
## les petits incréments — un pincement envoie une rafale d'événements à
## facteur ~1,02, chacun arrondi reviendrait au point de départ et le zoom ne
## bougerait jamais.
var _requested: float = 1.0
var _zoom: float = 1.0
var _layer: CanvasLayer

func _ready() -> void:
	_layer = get_parent() as CanvasLayer
	if _layer == null:
		push_warning("CanvasZoom : le parent doit être un CanvasLayer")

func get_zoom() -> float:
	return _zoom

func set_zoom(value: float) -> void:
	if _layer == null:
		return
	_requested = clampf(value, zoom_min, zoom_max)
	_zoom = clampf(snappedf(_requested, zoom_quantum), zoom_min, zoom_max)
	# Le zoom se fait autour du CENTRE de l'écran, comme la caméra du worldmap
	# qui zoome autour de sa propre position. Un point p du calque s'affiche en
	# `offset + scale · p` ; pour que le centre C reste immobile il faut donc
	# `offset = C · (1 − zoom)`.
	var center := get_viewport().get_visible_rect().size / 2.0
	_layer.scale = Vector2.ONE * _zoom
	_layer.offset = center * (1.0 - _zoom)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(_requested + zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(_requested - zoom_step)
	# Pincement à deux doigts (trackpad) : `factor` est un multiplicateur
	# relatif, à appliquer au zoom courant plutôt qu'à y ajouter un pas fixe.
	elif event is InputEventMagnifyGesture:
		set_zoom(_requested * event.factor)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_0 or event.keycode == KEY_KP_0:
			set_zoom(1.0)
