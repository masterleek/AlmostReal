extends ColorRect

## Fond d'eau (water_reflection.gdshader), affiché derrière tout le
## TileMapLayer grâce à son propre z_index, pas un ordre particulier dans
## l'arbre. Taille fixe réglable directement (pas de découpage en tuiles ni
## de marge à calculer) ; seule la POSITION est calculée, pour rester
## centrée sur la carte quelle que soit sa géométrie.
@export var width: float = 1536.0
@export var height: float = 1536.0

## Distance minimale (en pixels monde) parcourue par le curseur avant de
## semer un nouveau point de sillage : volontairement PETITE (contrairement à
## l'ancien ripple) pour que les points se chevauchent et forment une traînée
## CONTINUE plutôt que des anneaux espacés (cf wake_positions/
## wake_spawn_times ci-dessous), indépendamment du framerate.
@export var wake_min_spawn_distance: float = 8.0

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var cursor: Node2D = $"../WorldmapCursor"
const WorldmapCursor = preload("res://Scripts/Worldmap/WorldmapCursor.gd")

# Doit rester égal à la taille des tableaux "wake_positions"/
# "wake_spawn_times" déclarés dans water_reflection.gdshader (les tableaux
# de uniforms GLSL ont une taille fixe, pas de resize possible côté shader).
const WAKE_MAX := 16

# Horloge dédiée au sillage (plutôt que le TIME du shader) : sert à la fois
# à dater chaque semis (wake_spawn_times) et à calculer leur âge côté shader
# (wake_time), donc les deux restent forcément sur la même base.
var wake_time: float = 0.0
var wake_positions: PackedVector2Array = PackedVector2Array()
var wake_spawn_times: PackedFloat32Array = PackedFloat32Array()
var wake_next_index: int = 0
# Position du dernier point semé ; INF force un semis immédiat dès que le
# curseur retouche l'eau, plutôt que d'attendre qu'il ait parcouru
# wake_min_spawn_distance depuis une position déjà obsolète (ex. avant
# d'être repassé en mode grille).
var wake_last_spawn_pos: Vector2 = Vector2.INF

func _ready() -> void:
	z_index = -2
	mouse_filter = MOUSE_FILTER_IGNORE
	wake_positions.resize(WAKE_MAX)
	wake_spawn_times.resize(WAKE_MAX)
	wake_spawn_times.fill(-1000.0) # bien avant wake_time=0 : inactifs au départ
	# tile_layer peut ne pas encore avoir ses cellules au tout premier frame
	# (chargées dans Main._ready(), un frère déclaré avant celui-ci) :
	# call_deferred attend que ce chargement soit terminé.
	call_deferred("fit_to_map")

## Sillage sous le curseur : une traînée continue de points semés le long de
## son trajet (pas des anneaux d'impact ponctuels) — chaque point pousse
## localement les reflets (cf water_reflection.gdshader) puis s'éteint
## définitivement après un temps fixe (cf wake_lifetime côté shader), donc la
## traînée se dissipe d'elle-même si le curseur s'arrête ou quitte l'eau.
## Semis seulement en déplacement libre (cf WorldmapCursor.Mode.FREE — en
## mode grille, le curseur est toujours sur une vraie tuile, jamais sur
## l'eau) ET tant qu'il survole effectivement CE rect (Rect2.has_point plutôt
## qu'un simple "toujours actif en mode libre" — reste correct si jamais le
## curseur libre se retrouve hors de l'étendue d'eau).
func _process(delta: float) -> void:
	if not (material is ShaderMaterial):
		return
	var mat := material as ShaderMaterial
	wake_time += delta

	var is_free: bool = cursor.mode == WorldmapCursor.Mode.FREE
	var over_water: bool = Rect2(position, size).has_point(cursor.global_position)
	if is_free and over_water:
		if wake_last_spawn_pos == Vector2.INF or cursor.global_position.distance_to(wake_last_spawn_pos) >= wake_min_spawn_distance:
			_spawn_wake(cursor.global_position)
	else:
		wake_last_spawn_pos = Vector2.INF

	mat.set_shader_parameter("wake_time", wake_time)
	mat.set_shader_parameter("wake_positions", wake_positions)
	mat.set_shader_parameter("wake_spawn_times", wake_spawn_times)

## Ajoute un point de sillage à `pos` dans le tampon circulaire
## wake_positions/wake_spawn_times (écrase le plus ancien une fois plein).
func _spawn_wake(pos: Vector2) -> void:
	wake_positions[wake_next_index] = pos
	wake_spawn_times[wake_next_index] = wake_time
	wake_next_index = (wake_next_index + 1) % WAKE_MAX
	wake_last_spawn_pos = pos

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
