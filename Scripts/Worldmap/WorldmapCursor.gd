extends Node2D

## Curseur du Worldmap : déplacement case par case sur la grille hexagonale
## (façon Fire Emblem / Advance Wars) — toujours exactement centré sur une
## case, jamais entre deux au repos. Différent d'un futur système de
## déplacement de personnage classique (collisions, mouvement continu).

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

## Pulsation d'échelle idle du highlight ("cursor_worldmap2.png") — purement
## visuelle, n'affecte ni sa position ni le tri Y (contrairement à un
## bobbing, qui nécessiterait de refaire la compensation de tri appliquée
## plus bas pour la tuile "Empty").
@export var highlight_pulse_amplitude: float = 0.06
@export var highlight_pulse_speed: float = 6.0

## Décalage manuel du highlight ("cursor_worldmap2.png") par rapport à la
## position calculée de la case, pour corriger un désalignement visuel au
## pixel près directement depuis l'inspecteur Godot. `highlight_offset`
## s'applique par défaut à toutes les tuiles ; `empty_tile_highlight_offset`
## le remplace uniquement sur les tuiles "Empty" (terrain_type = "empty1"),
## dont l'art nécessite un calage différent.
@export var highlight_offset: Vector2 = Vector2.ZERO
@export var empty_tile_highlight_offset: Vector2 = Vector2(0, 10)

## Décalage manuel du glow (HoverGlow) par rapport à la case survolée, même
## logique de calage que highlight_offset.
@export var glow_offset: Vector2 = Vector2.ZERO
@export var glow_intensity: float = 0.0875
@export var glow_pulse_amplitude: float = 0.15

## Décalage manuel du sprite "highlight.png" (TileSelectHighlight) affiché
## sur la case sélectionnée, en plus du glow — même logique de calage que
## highlight_offset : tile_select_offset s'applique par défaut à toutes les
## tuiles, tile_select_empty_offset le remplace uniquement sur "Empty".
@export var tile_select_offset: Vector2 = Vector2.ZERO
@export var tile_select_empty_offset: Vector2 = Vector2.ZERO

## Anim de test : quand la tuile "Empty" est fraîchement sélectionnée, le
## sprite "highlight.png" (TileSelectHighlight) fait un wiggle (rotation
## amortie) une seule fois, pas en boucle.
@export var wiggle_duration: float = 0.4
@export var wiggle_amplitude_deg: float = 12.0
@export var wiggle_cycles: float = 3.0

var is_wiggling: bool = false
var wiggle_elapsed: float = 0.0

# La tuile "Empty" a un y_sort_origin de 10 (cf TileSetAtlasSource dans
# Main.tscn) : c'est de combien son point de tri Y est décalé sous sa
# position nominale. Sur cette tuile uniquement, TileHighlight participe au
# tri Y (z_index = -1, même bucket que TileMapLayer) pour pouvoir passer
# derrière la tuile voisine du bas — il doit donc être décalé d'un peu plus
# que 10 pour ne pas non plus passer derrière SA PROPRE tuile. Ce décalage
# est appliqué au nœud (qui pilote le tri) et compensé sur le sprite enfant
# (qui pilote le rendu), donc il ne change rien à l'écran. HoverGlow utilise
# le même mécanisme pour se laisser recouvrir par la tuile voisine du bas.
const HIGHLIGHT_SORT_NUDGE := Vector2(0, 11)
# Garantit que TileSelectHighlight se dessine toujours juste derrière
# TileHighlight (cursor_worldmap2.png), qu'ils soient dans le même bucket
# de tri (z_index) ou non, sans dépendre de l'ordre de déclaration dans la
# scène pour départager une éventuelle égalité de tri.
const TILE_SELECT_BEHIND_EPSILON := Vector2(0, 0.5)

@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var sprite: Sprite2D = $Sprite2D
@onready var hero: Node2D = $"../Hero"
@onready var highlight: Node2D = $"../TileHighlight"
@onready var highlight_sprite: Sprite2D = $"../TileHighlight/Sprite2D"
@onready var hover_glow: Sprite2D = $"../HoverGlow"
@onready var tile_select_highlight: Sprite2D = $"../TileSelectHighlight"
@onready var move_sfx: AudioStreamPlayer = $MoveSFX
@onready var reveal_sfx: AudioStreamPlayer = $RevealSFX
@onready var camera: Camera2D = $"../Camera2D"
@onready var tile_cost_bubble: Control = $"../HUD/TileCostBubble"

## Décalage (espace monde, avant zoom caméra) entre le centre de la case et
## le point où la bulle de coût s'accroche (pointe de la flèche). Réglable
## en jeu (arbre "Remote") pour repositionner la bulle à la main.
@export var tile_cost_bubble_anchor: Vector2 = Vector2(0, 5)
## Décalage supplémentaire (pixels écran) du contenu (icône + coût) à
## l'intérieur de la bulle, indépendant de ses marges 9-slice.
@export var tile_cost_bubble_content_offset: Vector2 = Vector2.ZERO
## Décalage supplémentaire (pixels écran) de la flèche (bubble_arrow.png) par
## rapport à sa position calculée sous la bulle.
@export var tile_cost_bubble_arrow_offset: Vector2 = Vector2.ZERO

## Coût par défaut (en hex) pour révéler une tuile "Empty".
@export var reveal_cost: int = 1

## Secousse de caméra pendant l'animation de révélation (test à l'oeil, cf
## CameraController.shake) : amplitude en pixels et durée de décroissance.
@export var reveal_shake_amplitude: float = 3.0
@export var reveal_shake_duration: float = 0.3

var is_revealing: bool = false
# Atlas cible lu au début de run_reveal_sequence(), consommé par
# _on_reveal_swap() (appelée par la Method Track de l'animation "tile_reveal",
# éditable dans le panneau Animation de Godot, au sommet du saut) — c'est ce
# genre de décision dynamique (dépend de la case/de l'éditeur de maps) qui
# reste du code plutôt qu'une valeur de keyframe.
var pending_reveal_target: Vector2i = Vector2i.ZERO

# Props posés (dans l'éditeur de maps) sur la case en cours de révélation :
# reparentés sous reveal_lift pour la durée de l'animation (cf
# run_reveal_sequence()), afin de suivre le même saut/la même chute/le même
# teinte que reveal_tile, puis rendus à PropsLayer une fois l'animation finie.
var reveal_active_props: Array[Sprite2D] = []

@onready var main: Node = get_parent()
@onready var reveal_anchor: Node2D = $"../RevealAnchor"
@onready var reveal_lift: Node2D = $"../RevealAnchor/RevealLift"
@onready var reveal_tile: Sprite2D = $"../RevealAnchor/RevealLift/RevealTile"
@onready var reveal_animation_player: AnimationPlayer = $"../RevealAnimationPlayer"

const TEXTURE_REGION_SIZE := 64

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

func _ready() -> void:
	highlight.visible = false
	hover_glow.visible = false
	tile_select_highlight.visible = false
	# La case de départ est celle la plus proche de l'endroit où le nœud a
	# été placé dans la scène : pas besoin d'un @export dédié, on déplace
	# juste le nœud dans l'éditeur pour choisir le point de départ.
	current_cell = tile_layer.local_to_map(tile_layer.to_local(global_position))
	if tile_layer.get_cell_tile_data(current_cell) == null:
		current_cell = Vector2i.ZERO
	global_position = tile_layer.to_global(tile_layer.map_to_local(current_cell))
	update_tile_state()

func _process(delta: float) -> void:
	if is_revealing:
		return
	if mode == Mode.GRID:
		process_grid_mode(delta)
	else:
		process_free_mode(delta)
	update_pulses()
	update_wiggle(delta)

# Démarre le wiggle une seule fois quand `cell` (qui vient tout juste de
# devenir la case sélectionnée) est une tuile "Empty" — appelé uniquement
# aux deux endroits où current_cell change réellement (pas à chaque frame),
# donc ne se redéclenche pas tant qu'on reste sur la même case.
func maybe_trigger_empty_wiggle(cell: Vector2i) -> void:
	var tile_data := tile_layer.get_cell_tile_data(cell)
	if tile_data != null and tile_data.get_custom_data("terrain_type") == "empty1":
		is_wiggling = true
		wiggle_elapsed = 0.0

func update_wiggle(delta: float) -> void:
	if not is_wiggling:
		return
	wiggle_elapsed += delta
	var t := wiggle_elapsed / wiggle_duration
	if t >= 1.0:
		is_wiggling = false
		tile_select_highlight.rotation = 0.0
		return
	var damped := 1.0 - t
	tile_select_highlight.rotation = deg_to_rad(wiggle_amplitude_deg) * sin(t * wiggle_cycles * TAU) * damped

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

	if current_terrain_type == "empty1" and Input.is_action_just_pressed("ui_accept"):
		try_reveal_tile()
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
	sprite.visible = true
	highlight.visible = false
	hover_glow.visible = false
	tile_select_highlight.visible = false
	tile_cost_bubble.hide_bubble()

func process_free_mode(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	global_position += input_dir * free_speed * delta

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

# Forme réelle du dessin des tuiles (pas la hitzone logique de la grille,
# tile_size=64x44) : extraite pixel par pixel de hex_tiles.png. L'art est
# dessiné en 64x64 (plus haut que la grille) pour l'effet de bloc pseudo-3D
# — c'est le même contour que HoverGlow.
static var TILE_ART_HITZONE := PackedVector2Array([
	Vector2(0, -32), Vector2(32, -17), Vector2(32, 17),
	Vector2(0, 32), Vector2(-32, 17), Vector2(-32, -17),
])

# Détecte quelle case est survolée par `point`, en se basant d'abord sur la
# grille logique, puis (si celle-ci ne trouve rien) sur le dessin réel
# d'une case voisine : un point peut tomber dans un "creux" entre deux
# sommets de la grille logique alors que le dessin réel (plus haut) d'une
# tuile voisine le recouvre déjà visuellement.
func find_hovered_cell(point: Vector2) -> Vector2i:
	var grid_cell := tile_layer.local_to_map(tile_layer.to_local(point))
	if tile_layer.get_cell_tile_data(grid_cell) != null:
		return grid_cell
	for neighbor in tile_layer.get_surrounding_cells(grid_cell):
		if tile_layer.get_cell_tile_data(neighbor) == null:
			continue
		var cell_pos := tile_layer.to_global(tile_layer.map_to_local(neighbor))
		if Geometry2D.is_point_in_polygon(point - cell_pos, TILE_ART_HITZONE):
			return neighbor
	return grid_cell

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

## Déclenchée par ui_accept sur une tuile "Empty" : si le joueur a assez de
## hex, les débite et lance l'animation de révélation. Sinon, ne fait rien —
## la bulle affiche déjà le coût en rouge (cf update_tile_state) pour prévenir
## le joueur avant même qu'il n'appuie.
func try_reveal_tile() -> void:
	if PlayerCurrency.hex < reveal_cost:
		return
	PlayerCurrency.hex -= reveal_cost
	run_reveal_sequence()

## Séquence complète de révélation : fige la caméra/les contrôles, masque le
## wiggle de test, puis laisse l'AnimationPlayer ("tile_reveal", éditable
## directement dans le panneau Animation de Godot en sélectionnant
## RevealAnimationPlayer) jouer tout l'enchaînement visuel (fade de la bulle/
## highlight/sélection, teinte blanche, saut, rebond). reveal_tile affiche
## directement la tuile cible dès le tout début de la séquence (plus
## d'apparence "empty" intermédiaire) et reste la SEULE tuile visible/animée
## du début à la fin — la vraie case du TileMapLayer reste effacée pendant
## toute la séquence pour qu'il n'y ait jamais deux tuiles à l'écran en même
## temps, et n'est réécrite qu'une fois l'animation entièrement terminée.
func run_reveal_sequence() -> void:
	is_revealing = true
	is_wiggling = false
	tile_select_highlight.rotation = 0.0
	camera.frozen = true
	camera.shake(reveal_shake_amplitude, reveal_shake_duration)
	reveal_sfx.play()
	# hover_glow n'est piloté par aucune piste de l'animation (contrairement à
	# la bulle/au highlight/à la sélection) : sans ce masquage explicite, il
	# reste figé, visible, à la position et la forme de la tuile "empty"
	# pendant toute la séquence. update_tile_state() le restaure à la fin.
	hover_glow.visible = false

	pending_reveal_target = main.get_reveal_target(current_cell)
	reveal_anchor.global_position = tile_layer.to_global(tile_layer.map_to_local(current_cell)) + HIGHLIGHT_SORT_NUDGE

	reveal_tile.region_rect = Rect2(
		pending_reveal_target.x * TEXTURE_REGION_SIZE, pending_reveal_target.y * TEXTURE_REGION_SIZE,
		TEXTURE_REGION_SIZE, TEXTURE_REGION_SIZE,
	)
	reveal_lift.z_index = 0
	reveal_tile.visible = true
	tile_layer.set_cell(current_cell, -1)

	# Props posés (dans l'éditeur de maps) sur cette case "empty" : reparentés
	# sous reveal_lift pour suivre le même saut/la même chute, et partagent le
	# matériau de reveal_tile (même ressource ShaderMaterial) pour se teinter
	# en blanc exactement en même temps, sans piste d'animation séparée.
	reveal_active_props = main.get_props_for_cell(current_cell)
	for prop in reveal_active_props:
		prop.reparent(reveal_lift, true)
		prop.material = reveal_tile.material
		prop.visible = true

	reveal_animation_player.play("tile_reveal")
	await reveal_animation_player.animation_finished

	# La case réelle n'est réécrite qu'à la toute fin (une fois reveal_tile
	# totalement immobile et redevenu invisible) : jamais de recouvrement
	# entre la vraie tuile statique et la tuile animée.
	tile_layer.set_cell(current_cell, 0, pending_reveal_target)
	reveal_tile.visible = false
	update_tile_state()

	# Les props reprennent leur place définitive dans PropsLayer (position
	# préservée) et perdent le matériau partagé — ils restent visibles pour de
	# bon à partir de maintenant, comme n'importe quel prop normal.
	for prop in reveal_active_props:
		prop.reparent(main.props_layer, true)
		prop.material = null
	reveal_active_props.clear()

	camera.frozen = false
	is_revealing = false

# Appelée par la Method Track de "tile_reveal" au sommet du saut : repositionne
# highlight/sélection pour une tuile normale (jamais "empty1" après une
# révélation), sans committer la vraie case tout de suite — ça doit être prêt
# avant leur fade-in en fin de timeline. La case réelle n'est écrite qu'à la
# fin de run_reveal_sequence(), qui rappelle update_tile_state() pour
# finaliser le reste (current_terrain_type, hover_glow, etc.).
func _on_reveal_swap() -> void:
	tile_cost_bubble.hide_bubble()

	var cell_pos := tile_layer.to_global(tile_layer.map_to_local(current_cell))
	highlight.global_position = cell_pos + highlight_offset
	highlight_sprite.position = Vector2.ZERO
	highlight.z_index = 0
	tile_select_highlight.z_index = 0
	var select_nudge := -TILE_SELECT_BEHIND_EPSILON
	tile_select_highlight.global_position = cell_pos + select_nudge
	tile_select_highlight.offset = tile_select_offset - select_nudge

# reveal_lift hérite de RevealAnchor (z_index=-1, la couche "sol", au même
# niveau que TileMapLayer) : au repos c'est correct, mais pendant le saut la
# tuile (et les props qui la suivent, cf reveal_active_props) doivent
# visuellement passer devant les props voisins (PropsLayer, z_index=0 par
# défaut), comme n'importe quel élément en l'air. Le Y-sort seul ne peut pas
# régler ça : en Godot, z_index prime toujours sur le tri Y, donc rien à z=-1
# ne peut jamais passer devant quelque chose à z=0, quelle que soit sa
# position Y. On monte donc temporairement reveal_lift (et tout ce qu'il
# porte, par cascade) au niveau de WorldmapCursor (z=10, le plus haut du
# gameplay) le temps du vol.
func _on_reveal_liftoff() -> void:
	reveal_lift.z_index = 11

func _on_reveal_landed() -> void:
	reveal_lift.z_index = 0

func update_pulses() -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * highlight_pulse_speed) * highlight_pulse_amplitude
	highlight_sprite.scale = Vector2.ONE * pulse
	if hover_glow.visible:
		var glow_pulse := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * highlight_pulse_speed) * glow_pulse_amplitude
		hover_glow.modulate.a = glow_intensity * glow_pulse

func update_tile_state() -> void:
	var tile_data := tile_layer.get_cell_tile_data(current_cell)
	highlight.visible = tile_data != null
	current_terrain_type = tile_data.get_custom_data("terrain_type") if tile_data != null else ""
	highlight.z_index = -1 if current_terrain_type == "empty1" else 0
	# Sur la tuile "Empty", le curseur (cursor_worldmap.png) est masqué : ne
	# garder que le highlight/la sélection, pour ne pas surcharger visuellement
	# une case qui n'a elle-même pas de tuile visible. Masqué aussi sur la
	# case du Héros — inutile de superposer le pointeur au personnage lui-même.
	sprite.visible = current_terrain_type != "empty1" and current_cell != hero.current_cell
	hover_glow.visible = tile_data != null
	tile_select_highlight.visible = tile_data != null

	if not highlight.visible:
		tile_cost_bubble.hide_bubble()
		return

	var cell_pos := tile_layer.to_global(tile_layer.map_to_local(current_cell))
	if current_terrain_type == "empty1":
		highlight.global_position = cell_pos + HIGHLIGHT_SORT_NUDGE
		highlight_sprite.position = empty_tile_highlight_offset - HIGHLIGHT_SORT_NUDGE
	else:
		highlight.global_position = cell_pos + highlight_offset
		highlight_sprite.position = Vector2.ZERO
	hover_glow.global_position = cell_pos + HIGHLIGHT_SORT_NUDGE
	hover_glow.offset = glow_offset - HIGHLIGHT_SORT_NUDGE
	# Reprend exactement la logique de TileHighlight (qui fonctionne sans
	# clipping) plutôt que le mécanisme de tri "profondeur réelle" du glow,
	# qui s'est avéré peu fiable pour cet asset. Un tout petit nudge négatif
	# garantit qu'il se dessine juste derrière TileHighlight dans les deux
	# cas (normal : même bucket z=0 ; Empty : même bucket z=-1), sans jamais
	# dépendre d'un ordre de déclaration ambigu en cas d'égalité de tri.
	tile_select_highlight.z_index = highlight.z_index
	var select_visual_offset := tile_select_empty_offset if current_terrain_type == "empty1" else tile_select_offset
	var select_nudge := (HIGHLIGHT_SORT_NUDGE if current_terrain_type == "empty1" else Vector2.ZERO) - TILE_SELECT_BEHIND_EPSILON
	tile_select_highlight.global_position = cell_pos + select_nudge
	tile_select_highlight.offset = select_visual_offset - select_nudge
	# Reprend le même dessin (atlas + région) que la vraie tuile à cette case
	# : comme il vient de la même texture avec sa transparence, le glow
	# additif n'apparaît que sur les pixels réellement opaques du sprite,
	# jamais sur le fond transparent (cf tuile "Empty").
	var atlas := tile_layer.get_cell_atlas_coords(current_cell)
	hover_glow.region_rect = Rect2(
		atlas.x * TEXTURE_REGION_SIZE, atlas.y * TEXTURE_REGION_SIZE,
		TEXTURE_REGION_SIZE, TEXTURE_REGION_SIZE,
	)

	# Bulle de coût : uniquement pour les tuiles "Empty", en espace écran
	# (comme le compteur HUD) pour que le texte garde la même taille visible
	# quel que soit le zoom de la caméra.
	if current_terrain_type == "empty1":
		tile_cost_bubble.show_above(
			world_to_screen(cell_pos + tile_cost_bubble_anchor),
			tile_cost_bubble_content_offset, tile_cost_bubble_arrow_offset,
			reveal_cost, PlayerCurrency.hex >= reveal_cost,
		)
	else:
		tile_cost_bubble.hide_bubble()

# Camera2D n'a pas d'équivalent 2D d'unproject_position (réservé à Camera3D) :
# on reconstruit la conversion monde -> écran à partir de la transformation
# de canevas du viewport, qui reflète la caméra 2D active (position, zoom).
func world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos
