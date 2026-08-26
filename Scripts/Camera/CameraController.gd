extends Camera2D

## Caméra générique et réutilisable : suit n'importe quelle cible, sans rien
## savoir de ce qu'elle est (curseur libre, futur personnage, etc.).
@export var target: Node2D

## Suivi en ressort amorti (masse-ressort-amortisseur) plutôt qu'un simple
## lissage exponentiel : la caméra accélère et décélère progressivement au
## lieu de réagir à vitesse max dès que la cible bouge, pour un mouvement
## plus organique/non-linéaire.
## Réactivité du ressort : plus haut = rattrape plus vite.
@export var follow_frequency: float = 6.0
## 1.0 = pile critique (pas de dépassement) ; < 1.0 = léger rebond élastique
## avant de se stabiliser (plus "vivant") ; > 1.0 = plus mou/amorti.
@export var follow_damping_ratio: float = 0.8

## Zoom à la molette (utile pour vérifier des assets en jeu). Bornes en
## multiplicateur du zoom de base défini sur le nœud (4 par défaut).
@export var zoom_step: float = 0.5
@export var zoom_min: float = 1.0
@export var zoom_max: float = 12.0

var velocity: Vector2 = Vector2.ZERO
## Zoom "taille réelle" du jeu (celui défini sur le nœud dans l'éditeur),
## restauré en appuyant sur 0.
var default_zoom: Vector2

## Fige la caméra (ex. pendant l'animation de révélation d'une tuile) : plus
## aucun suivi de la cible tant que c'est activé, le zoom manuel reste actif.
var frozen: bool = false

# Secousse : passe uniquement par `offset` (décalage purement visuel de
# Camera2D, jamais la position réelle) pour ne jamais interférer avec le
# suivi ni le gel — revient toujours pile à zéro une fois la durée écoulée.
var shake_amplitude: float = 0.0
var shake_duration: float = 0.0
var shake_time_left: float = 0.0

func _ready() -> void:
	default_zoom = zoom

## Déclenche une secousse de `amplitude` pixels qui décroît linéairement sur
## `duration` secondes. Un nouvel appel remplace la secousse en cours.
func shake(amplitude: float, duration: float) -> void:
	shake_amplitude = amplitude
	shake_duration = duration
	shake_time_left = duration

func _process(delta: float) -> void:
	if not frozen and target:
		var stiffness := follow_frequency * follow_frequency
		var damping := 2.0 * follow_damping_ratio * follow_frequency
		var displacement := target.global_position - global_position
		var acceleration := displacement * stiffness - velocity * damping
		velocity += acceleration * delta
		global_position += velocity * delta

	if shake_time_left > 0.0:
		shake_time_left -= delta
		var falloff := shake_time_left / shake_duration
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amplitude * falloff
	else:
		offset = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_clamped(zoom + Vector2.ONE * zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_clamped(zoom - Vector2.ONE * zoom_step)
	# Pincement à deux doigts sur trackpad (macOS/Windows précision) : `factor`
	# est un multiplicateur relatif (>1 = écarter les doigts/zoom avant,
	# <1 = pincer/zoom arrière), à appliquer au zoom actuel plutôt qu'à y
	# ajouter un pas fixe comme pour la molette.
	elif event is InputEventMagnifyGesture:
		set_zoom_clamped(zoom * event.factor)
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_0 or event.keycode == KEY_KP_0):
		set_zoom_clamped(default_zoom)

func set_zoom_clamped(new_zoom: Vector2) -> void:
	zoom = Vector2.ONE * clampf(new_zoom.x, zoom_min, zoom_max)
