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

## Zoom MAINTENU : actions `camera_zoom_out` (L2 / D) et `camera_zoom_in` (R2 / E).
## La gâchette est analogique : plus on l'enfonce, plus le zoom est rapide.
## Facteur appliqué PAR SECONDE à pression pleine (2 = le zoom double en 1 s, 4 le
## quadruple) :
## multiplicatif plutôt qu'additif, pour que la vitesse ressentie soit la même à
## zoom 2 qu'à zoom 8.
@export var key_zoom_speed: float = 4.0
## Zoom maximal atteignable en MAINTENANT la touche (le plus rapproché). À régler en
## testant ; la molette et le pincement, eux, vont jusqu'à `zoom_max`.
@export var key_zoom_in_limit: float = 8.0
## Marge sur le zoom minimal « sans fond visible » : la secousse de caméra décale
## l'image de quelques pixels, qui ne doivent jamais découvrir le bord de l'eau.
@export var out_of_bounds_margin: float = 1.02

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

	_hold_zoom(delta)

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

## Zoom le plus éloigné qui ne montre JAMAIS le fond par défaut du viewport :
## celui où la vue (taille du viewport / zoom) tient exactement dans les limites de
## la caméra. Camera2D borne bien la POSITION par les limites, mais si la vue est plus
## grande que la zone qu'elles délimitent, elle déborde — d'où ce plancher, appliqué
## à tous les zooms (maintenu, molette, pincement). Sans limites définies (valeurs
## par défaut, immenses), il ne bride rien.
func min_zoom_without_backdrop() -> float:
	var area := Vector2(limit_right - limit_left, limit_bottom - limit_top)
	if area.x <= 0.0 or area.y <= 0.0:
		return zoom_min
	var view := get_viewport_rect().size
	return maxf(zoom_min, maxf(view.x / area.x, view.y / area.y) * out_of_bounds_margin)

## Zoom maintenu : pression nette de la gâchette/touche (zoom avant moins zoom arrière).
func _hold_zoom(delta: float) -> void:
	var pressure := Input.get_action_strength("camera_zoom_in") - Input.get_action_strength("camera_zoom_out")
	if pressure != 0.0:
		var wanted: float = zoom.x * pow(key_zoom_speed, pressure * delta)
		# Le plafond ne ramène pas de force un zoom déjà plus rapproché (molette) :
		# il empêche seulement de s'en approcher davantage.
		var ceiling: float = maxf(key_zoom_in_limit, zoom.x) if pressure > 0.0 else zoom_max
		zoom = Vector2.ONE * clampf(wanted, min_zoom_without_backdrop(), ceiling)
	# Les limites peuvent changer après coup (carte chargée, fond d'eau redimensionné) :
	# on remonte le zoom si la vue déborde désormais.
	var floor_zoom := min_zoom_without_backdrop()
	if zoom.x < floor_zoom:
		zoom = Vector2.ONE * floor_zoom

func set_zoom_clamped(new_zoom: Vector2) -> void:
	zoom = Vector2.ONE * clampf(new_zoom.x, min_zoom_without_backdrop(), zoom_max)
