extends Node2D

## Curseur du Worldmap : déplacement case par case sur la grille hexagonale
## (façon Fire Emblem / Advance Wars) — toujours exactement centré sur une
## case, jamais entre deux au repos. Différent d'un futur système de
## déplacement de personnage classique (collisions, mouvement continu).
## Ne sait rien de l'apparence de la case survolée (cf TileHoverVisuals) ni de
## la révélation de tuile elle-même (cf TileRevealController) : se contente
## de les piloter.

# Préchargés plutôt que de compter sur la résolution globale de class_name
# (peu fiable au tout premier chargement headless du projet) : accès direct
# et garanti aux deux scripts.
const TileGeometry = preload("res://Scripts/Worldmap/TileGeometry.gd")
const TerrainTypes = preload("res://Scripts/Worldmap/TerrainTypes.gd")

## Durée de l'animation d'un pas d'une case à la voisine.
@export var move_duration: float = 0.12
## Délai minimum entre deux pas en maintenant une direction (l'animation du
## pas précédent compte en plus de ce délai).
@export var move_repeat_interval: float = 0.16
## Amplitude minimale de l'input (stick/clavier) pour déclencher un pas —
## évite qu'un stick pas parfaitement neutre ne fasse dériver le curseur.
@export var input_deadzone: float = 0.35

## Vitesse en déplacement libre (aucune tuile dans la direction pressée).
@export var free_speed: float = 350.0
## Produit scalaire minimal entre la direction pressée et la direction
## (monde réel) d'une voisine pour qu'elle compte comme "il y a une tuile
## dans cette direction" (1.0 = alignement parfait, 0.0 = perpendiculaire).
## En dessous, on considère qu'il n'y a rien par là et on passe en
## déplacement libre plutôt que de "glisser" vers une voisine mal alignée.
@export var direction_match_threshold: float = 0.5

enum Mode { GRID, FREE }
var mode: Mode = Mode.GRID

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var sprite: Sprite2D = $Sprite2D
@onready var hero: Node2D = $"../Hero"
@onready var move_sfx: AudioStreamPlayer = $MoveSFX
@onready var hover_visuals: Node2D = $"../TileHoverVisuals"
@onready var reveal_controller: Node = $"../TileRevealController"

var current_cell: Vector2i = Vector2i(-999999, -999999)
var current_terrain_type: String = ""

var is_moving: bool = false
var move_from: Vector2 = Vector2.ZERO
var move_to: Vector2 = Vector2.ZERO
var move_elapsed: float = 0.0
var repeat_timer: float = 0.0

# Court délai après l'entrée en mode libre pendant lequel on ignore toute
# détection : sans ça, avec la portée élargie de la silhouette + hitzone de
# secours, le curseur peut se faire "rattraper" par une case voisine dès la
# frame suivante (allers-retours sans fin). Passé ce délai, la détection
# reste active en continu SANS exclure la case de départ — sinon un joueur
# qui n'a en réalité jamais vraiment quitté sa case d'origine reste bloqué
# en mode libre indéfiniment dessus.
@export var free_mode_cooldown: float = 0.15
var free_mode_cooldown_timer: float = 0.0

## Durée du fondu (apparition/disparition) de cursor_worldmap.png quand il se
## masque (case du Héros ou case "Empty") ou réapparaît — cf set_sprite_faded_visible().
@export var sprite_fade_duration: float = 0.15
var _sprite_target_visible: bool = true
var _sprite_fade_tween: Tween

func _ready() -> void:
	# La case de départ est celle la plus proche de l'endroit où le nœud a
	# été placé dans la scène : pas besoin d'un @export dédié, on déplace
	# juste le nœud dans l'éditeur pour choisir le point de départ.
	current_cell = tile_layer.local_to_map(tile_layer.to_local(global_position))
	if tile_layer.get_cell_tile_data(current_cell) == null:
		current_cell = Vector2i.ZERO
	global_position = tile_layer.to_global(tile_layer.map_to_local(current_cell))
	# Pas un appel direct : update_tile_state() touche hover_visuals et
	# reveal_controller, deux frères déclarés après ce nœud dans la scène —
	# leurs propres @onready ne sont pas encore prêts au moment où _ready()
	# tourne ici. call_deferred attend que tout le monde (peu importe l'ordre
	# dans l'arbre) le soit.
	call_deferred("update_tile_state")

func _process(delta: float) -> void:
	if reveal_controller.is_revealing:
		return
	if mode == Mode.GRID:
		process_grid_mode(delta)
	else:
		process_free_mode(delta)

func process_grid_mode(delta: float) -> void:
	if is_moving:
		move_elapsed += delta
		var t: float = clamp(move_elapsed / move_duration, 0.0, 1.0)
		global_position = move_from.lerp(move_to, smoothstep(0.0, 1.0, t))
		if t >= 1.0:
			is_moving = false
			global_position = move_to
		update_tile_state()
		return

	if TerrainTypes.is_empty(current_terrain_type) and Input.is_action_just_pressed("ui_accept"):
		reveal_controller.try_reveal(current_cell)
		return

	repeat_timer -= delta
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() < input_deadzone:
		repeat_timer = 0.0
	elif repeat_timer <= 0.0:
		try_move(input_dir.normalized())
	# try_move() peut avoir basculé en mode libre (enter_free_mode) : dans ce
	# cas ne pas réafficher highlight/glow juste après qu'ils aient été masqués.
	if mode == Mode.GRID:
		update_tile_state()

# Compare l'angle de l'input à la direction (monde réel, pas une formule
# théorique) de chacune des 6 voisines hexagonales de la case actuelle —
# via l'API native get_surrounding_cells plutôt qu'une table codée en dur,
# pour rester correct quel que soit tile_shape/tile_layout — et se déplace
# vers celle qui correspond le mieux, si elle dépasse direction_match_threshold
# et contient bien une tuile. Sinon (aucune tuile dans cette direction),
# passe en déplacement libre plutôt que de glisser vers une voisine hors
# sujet.
func try_move(input_dir: Vector2) -> void:
	var current_pos := tile_layer.to_global(tile_layer.map_to_local(current_cell))
	var best_cell := current_cell
	var best_dot := direction_match_threshold
	for neighbor in tile_layer.get_surrounding_cells(current_cell):
		if tile_layer.get_cell_tile_data(neighbor) == null:
			continue
		var neighbor_pos := tile_layer.to_global(tile_layer.map_to_local(neighbor))
		var dot := (neighbor_pos - current_pos).normalized().dot(input_dir)
		if dot > best_dot:
			best_dot = dot
			best_cell = neighbor

	repeat_timer = move_repeat_interval
	if best_cell == current_cell:
		enter_free_mode()
		return

	current_cell = best_cell
	maybe_trigger_empty_wiggle(current_cell)
	move_from = global_position
	move_to = tile_layer.to_global(tile_layer.map_to_local(current_cell))
	move_elapsed = 0.0
	is_moving = true
	move_sfx.play()

# Aucune tuile dans la direction pressée : le curseur se détache de la
# grille et se déplace librement (seul cursor_worldmap.png reste affiché,
# ni highlight ni glow ni sélection puisqu'il ne survole plus de case connue).
func enter_free_mode() -> void:
	mode = Mode.FREE
	is_moving = false
	free_mode_cooldown_timer = free_mode_cooldown
	set_sprite_faded_visible(true)
	hover_visuals.hide_all()
	reveal_controller.hide_cost_bubble()

func process_free_mode(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	global_position += input_dir * free_speed * delta
	global_position = clamp_to_screen(global_position)

	# Court délai avant de réactiver la détection (cf commentaire sur
	# free_mode_cooldown) — passé ce délai, elle reste active en continu.
	# Contrairement à avant, on NE EXCLUT PLUS la case de départ : si le
	# joueur n'a en réalité jamais vraiment quitté sa case d'origine (juste
	# dérivé de quelques pixels dedans avant de relâcher les touches), elle
	# doit quand même être re-détectée une fois le délai passé, sinon le
	# curseur reste bloqué en mode libre indéfiniment sur sa propre case.
	if free_mode_cooldown_timer > 0.0:
		free_mode_cooldown_timer -= delta
		return

	var detected_cell := find_hovered_cell_near_sprite()
	if tile_layer.get_cell_tile_data(detected_cell) != null:
		enter_grid_mode(detected_cell)

# En déplacement libre, rien n'empêche autrement le curseur de s'éloigner
# indéfiniment (aucune tuile pour le "rattraper") : la caméra (qui le suit
# avec un délai, cf CameraController) est elle-même bornée à l'étendue de la
# carte (cf map_loader.gd), donc sans ce clamp le curseur peut sortir de
# l'écran pendant qu'elle reste bloquée à son bord — un curseur invisible.
# get_screen_center_position() (pas global_position) reflète le centre RÉEL
# affiché par la caméra (lissage/limites/décalage de secousse déjà
# appliqués), pas sa position logique brute.
#
# sprite.offset (ex. (0, -34), purement cosmétique — cf commentaire sur
# find_hovered_cell_near_sprite) décale l'image AFFICHÉE par rapport à `pos` :
# sans en tenir compte ici, on borne la position logique, pas le sprite
# réellement visible à l'écran — d'où un bord qui coupe trop tôt et l'autre
# pas assez (l'offset ajoute la même erreur des deux côtés, dans le même
# sens, au lieu de s'annuler).
func clamp_to_screen(pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return pos
	var half_sprite := sprite.texture.get_size() / 2.0
	var half_screen := get_viewport().get_visible_rect().size / (2.0 * cam.zoom)
	var center := cam.get_screen_center_position()
	var min_pos := center - half_screen - sprite.offset + half_sprite
	var max_pos := center + half_screen - sprite.offset - half_sprite
	return pos.clamp(min_pos, max_pos)

# Teste plusieurs points autour du centre logique du curseur (global_position),
# pas seulement ce point unique : le joueur juge "je survole la tuile" par
# rapport à toute la forme du curseur, pas un unique pixel. Le contour utilisé
# est centré sur global_position (taille du sprite, sans son `offset` visuel
# — ex. -34 en Y, purement cosmétique) : un contour basé sur sprite.get_rect()
# (qui inclut cet offset) reste décalé côté nord en permanence, ce qui
# ré-attirait sans fin le curseur vers sa case d'origine quand on en sortait
# par le sud (aucune résistance équivalente côté nord, où le décalage va dans
# le même sens que la sortie) — un curseur bloqué en boucle libre/grille sans
# jamais progresser. Le centre est testé en premier (cas courant), puis le
# contour.
func find_hovered_cell_near_sprite() -> Vector2i:
	var half_size := sprite.texture.get_size() / 2.0
	var rect := Rect2(-half_size, sprite.texture.get_size())
	var sample_offsets := [
		Vector2.ZERO,
		Vector2(0, rect.position.y), Vector2(0, rect.end.y),
		Vector2(rect.position.x, 0), Vector2(rect.end.x, 0),
		Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y),
	]
	for offset in sample_offsets:
		var cell := find_hovered_cell(global_position + offset)
		if tile_layer.get_cell_tile_data(cell) != null:
			return cell
	return find_hovered_cell(global_position)

# Détecte quelle case est survolée par `point`, en se basant d'abord sur la
# grille logique, puis (si celle-ci ne trouve rien) sur le dessin réel
# d'une case voisine (cf TileGeometry.tile_art_hitzone()) : un point peut
# tomber dans un "creux" entre deux sommets de la grille logique alors que le
# dessin réel (plus haut) d'une tuile voisine le recouvre déjà visuellement.
func find_hovered_cell(point: Vector2) -> Vector2i:
	var grid_cell := tile_layer.local_to_map(tile_layer.to_local(point))
	if tile_layer.get_cell_tile_data(grid_cell) != null:
		return grid_cell
	for neighbor in tile_layer.get_surrounding_cells(grid_cell):
		if tile_layer.get_cell_tile_data(neighbor) == null:
			continue
		var cell_pos := tile_layer.to_global(tile_layer.map_to_local(neighbor))
		if Geometry2D.is_point_in_polygon(point - cell_pos, TileGeometry.tile_art_hitzone()):
			return neighbor
	return grid_cell

## Anime l'apparition/disparition de cursor_worldmap.png (fondu sur son alpha
## via un Tween, pas un basculement instantané de `visible`) : `sprite.visible`
## reste toujours true, seul modulate.a change, pour pouvoir l'animer dans les
## deux sens. No-op si l'état cible demandé est déjà celui en cours/en train
## de s'animer, pour ne pas relancer un tween à chaque frame sans changement
## réel (update_tile_state() appelle ceci à chaque frame en mode grille).
func set_sprite_faded_visible(should_be_visible: bool) -> void:
	if should_be_visible == _sprite_target_visible:
		return
	_sprite_target_visible = should_be_visible
	if _sprite_fade_tween != null and _sprite_fade_tween.is_running():
		_sprite_fade_tween.kill()
	_sprite_fade_tween = create_tween()
	_sprite_fade_tween.tween_property(sprite, "modulate:a", 1.0 if should_be_visible else 0.0, sprite_fade_duration)

# Le curseur libre vient de survoler une tuile : on rebascule en mode grille
# en s'y laissant "aimanter" (même animation que pour un pas normal) plutôt
# que de sauter instantanément dessus.
func enter_grid_mode(cell: Vector2i) -> void:
	mode = Mode.GRID
	current_cell = cell
	maybe_trigger_empty_wiggle(current_cell)
	move_from = global_position
	move_to = tile_layer.to_global(tile_layer.map_to_local(current_cell))
	move_elapsed = 0.0
	is_moving = true
	repeat_timer = move_repeat_interval
	update_tile_state()

# Démarre le wiggle une seule fois quand `cell` (qui vient tout juste de
# devenir la case sélectionnée) est une tuile "Empty" — appelé uniquement
# aux deux endroits où current_cell change réellement (pas à chaque frame),
# donc ne se redéclenche pas tant qu'on reste sur la même case.
func maybe_trigger_empty_wiggle(cell: Vector2i) -> void:
	var tile_data := tile_layer.get_cell_tile_data(cell)
	if tile_data != null and TerrainTypes.is_empty(tile_data.get_custom_data("terrain_type")):
		hover_visuals.start_wiggle()

## Recalcule tout ce qui dépend de `current_cell` : son terrain_type (état
## public que Hero/ActionHintHUD/TileRevealController lisent), la visibilité
## du curseur lui-même, les visuels de survol (délégués à hover_visuals) et
## la bulle de coût (déléguée à reveal_controller).
func update_tile_state() -> void:
	var tile_data := tile_layer.get_cell_tile_data(current_cell)
	current_terrain_type = tile_data.get_custom_data("terrain_type") if tile_data != null else ""
	# Sur la tuile "Empty", le curseur (cursor_worldmap.png) est masqué : ne
	# garder que le highlight/la sélection, pour ne pas surcharger visuellement
	# une case qui n'a elle-même pas de tuile visible. Masqué aussi sur la
	# case du Héros — inutile de superposer le pointeur au personnage lui-même.
	var should_show_sprite: bool = not TerrainTypes.is_empty(current_terrain_type) and current_cell != hero.current_cell
	set_sprite_faded_visible(should_show_sprite)

	if tile_data == null:
		hover_visuals.hide_all()
		reveal_controller.hide_cost_bubble()
		return

	var cell_pos := tile_layer.to_global(tile_layer.map_to_local(current_cell))
	var is_empty := TerrainTypes.is_empty(current_terrain_type)
	hover_visuals.show_at(cell_pos, tile_layer.get_cell_atlas_coords(current_cell), is_empty)

	# Bulle de coût : uniquement pour les tuiles "Empty".
	if is_empty:
		reveal_controller.update_cost_bubble(cell_pos)
	else:
		reveal_controller.hide_cost_bubble()

# Camera2D n'a pas d'équivalent 2D d'unproject_position (réservé à Camera3D) :
# on reconstruit la conversion monde -> écran à partir de la transformation
# de canevas du viewport, qui reflète la caméra 2D active (position, zoom).
# Exposée : TileRevealController s'en sert pour placer la bulle de coût.
func world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos
