extends Node2D

## Séquence complète de révélation d'une case "Empty" : débite la monnaie
## (PlayerCurrency), joue l'animation "tile_reveal" (AnimationPlayer, saut +
## teinte blanche + atterrissage, éditable directement dans le panneau
## Animation de Godot en sélectionnant RevealAnimationPlayer), fait suivre ce
## saut aux props posés sur la case le temps du vol, et affiche la bulle de
## coût pendant qu'une case "Empty" est survolée. Extrait de WorldmapCursor
## (qui reste un curseur générique de déplacement/survol) : rien ici ne
## dépend de la façon dont la case a été sélectionnée, juste de laquelle
## c'est (`cell`, passé par l'appelant).

## Coût par défaut (en hex) pour révéler une tuile "Empty".
@export var reveal_cost: int = 1

## Secousse de caméra pendant l'animation de révélation (test à l'oeil, cf
## CameraController.shake) : amplitude en pixels et durée de décroissance.
@export var reveal_shake_amplitude: float = 3.0
@export var reveal_shake_duration: float = 0.3

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

const TEXTURE_REGION_SIZE := 64

var is_revealing: bool = false
var revealing_cell: Vector2i = Vector2i.ZERO
# Atlas cible lu au début de reveal(), consommé par _on_reveal_swap() (appelée
# par la Method Track de l'animation "tile_reveal", au sommet du saut) — ce
# genre de décision dynamique (dépend de la case/de l'éditeur de maps) reste
# du code plutôt qu'une valeur de keyframe.
var pending_reveal_target: Vector2i = Vector2i.ZERO

# Props posés (dans l'éditeur de maps) sur la case en cours de révélation :
# reparentés sous reveal_lift pour la durée de l'animation (cf reveal()),
# afin de suivre le même saut/la même chute/la même teinte que reveal_tile,
# puis rendus à PropsLayer une fois l'animation finie.
var reveal_active_props: Array[Sprite2D] = []

@onready var cursor: Node2D = $"../WorldmapCursor"
@onready var hover_visuals: Node2D = $"../TileHoverVisuals"
@onready var tile_layer: TileMapLayer = $"../TileMapLayer"
@onready var camera: Camera2D = $"../Camera2D"
@onready var tile_cost_bubble: Control = $"../HUD/TileCostBubble"
@onready var reveal_sfx: AudioStreamPlayer = $RevealSFX
@onready var main: Node = get_parent()
@onready var reveal_anchor: Node2D = $"../RevealAnchor"
@onready var reveal_lift: Node2D = $"../RevealAnchor/RevealLift"
@onready var reveal_tile: Sprite2D = $"../RevealAnchor/RevealLift/RevealTile"
@onready var reveal_animation_player: AnimationPlayer = $"../RevealAnimationPlayer"

## À appeler par WorldmapCursor pendant qu'une case "Empty" est survolée ;
## hide_cost_bubble() le reste du temps. Le curseur n'a pas besoin de
## connaître reveal_cost ni la mise en page de la bulle pour ça.
func update_cost_bubble(cell_pos: Vector2) -> void:
	tile_cost_bubble.show_above(
		cursor.world_to_screen(cell_pos + tile_cost_bubble_anchor),
		tile_cost_bubble_content_offset, tile_cost_bubble_arrow_offset,
		reveal_cost, PlayerCurrency.hex >= reveal_cost,
	)

func hide_cost_bubble() -> void:
	tile_cost_bubble.hide_bubble()

## Déclenchée par WorldmapCursor sur ui_accept au-dessus d'une case "Empty" :
## si le joueur a assez de hex, les débite et lance l'animation de
## révélation. Sinon, ne fait rien — la bulle affiche déjà le coût en rouge
## (cf update_cost_bubble) pour prévenir le joueur avant même qu'il n'appuie.
func try_reveal(cell: Vector2i) -> void:
	if PlayerCurrency.hex < reveal_cost:
		return
	PlayerCurrency.hex -= reveal_cost
	reveal(cell)

## Séquence complète de révélation : fige la caméra et les contrôles du
## curseur, puis laisse l'AnimationPlayer jouer tout l'enchaînement visuel
## (fade de la bulle/highlight/sélection, teinte blanche, saut, rebond).
## reveal_tile affiche directement la tuile cible dès le tout début de la
## séquence (plus d'apparence "empty" intermédiaire) et reste la SEULE tuile
## visible/animée du début à la fin — la vraie case du TileMapLayer reste
## effacée pendant toute la séquence pour qu'il n'y ait jamais deux tuiles à
## l'écran en même temps, et n'est réécrite qu'une fois l'animation
## entièrement terminée.
func reveal(cell: Vector2i) -> void:
	is_revealing = true
	revealing_cell = cell
	hover_visuals.cancel_wiggle()
	camera.frozen = true
	camera.shake(reveal_shake_amplitude, reveal_shake_duration)
	reveal_sfx.play()
	# hover_glow n'est piloté par aucune piste de l'animation (contrairement à
	# la bulle/au highlight/à la sélection) : sans ce masquage explicite, il
	# reste figé, visible, à la position et la forme de la tuile "empty"
	# pendant toute la séquence. cursor.update_tile_state() le restaure à la fin.
	hover_visuals.hide_glow_only()

	pending_reveal_target = main.get_reveal_target(cell)
	reveal_anchor.global_position = tile_layer.to_global(tile_layer.map_to_local(cell)) + hover_visuals.HIGHLIGHT_SORT_NUDGE

	reveal_tile.region_rect = Rect2(
		pending_reveal_target.x * TEXTURE_REGION_SIZE, pending_reveal_target.y * TEXTURE_REGION_SIZE,
		TEXTURE_REGION_SIZE, TEXTURE_REGION_SIZE,
	)
	reveal_lift.z_index = 0
	reveal_tile.visible = true
	tile_layer.set_cell(cell, -1)

	# Props posés (dans l'éditeur de maps) sur cette case "empty" : reparentés
	# sous reveal_lift pour suivre le même saut/la même chute, et partagent le
	# matériau de reveal_tile (même ressource ShaderMaterial) pour se teinter
	# en blanc exactement en même temps, sans piste d'animation séparée.
	reveal_active_props = main.get_props_for_cell(cell)
	for prop in reveal_active_props:
		prop.reparent(reveal_lift, true)
		prop.material = reveal_tile.material
		prop.visible = true

	reveal_animation_player.play("tile_reveal")
	await reveal_animation_player.animation_finished

	# La case réelle n'est réécrite qu'à la toute fin (une fois reveal_tile
	# totalement immobile et redevenu invisible) : jamais de recouvrement
	# entre la vraie tuile statique et la tuile animée.
	tile_layer.set_cell(cell, 0, pending_reveal_target)
	reveal_tile.visible = false
	cursor.update_tile_state()

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
# fin de reveal(), qui rappelle cursor.update_tile_state() pour finaliser le
# reste (current_terrain_type, hover_glow, etc.).
func _on_reveal_swap() -> void:
	hide_cost_bubble()
	var cell_pos := tile_layer.to_global(tile_layer.map_to_local(revealing_cell))
	hover_visuals.position_highlight(cell_pos, false)

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
