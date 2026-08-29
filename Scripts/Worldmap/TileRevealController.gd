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

## Échelle de l'ombre (reveal_shadow) au plus haut du saut — 1.0 au sol
## (début et atterrissage), rétrécit vers cette valeur pendant la montée puis
## regrandit pendant la chute (cf _process).
@export_range(0.0, 1.0) var shadow_min_scale: float = 0.85
## Hauteur de saut (valeur absolue, mêmes unités que "RevealAnchor/RevealLift:
## position:y" dans l'animation "tile_reveal") à laquelle l'ombre atteint
## shadow_min_scale — doit correspondre au point le plus haut de cette piste
## (actuellement -24, cf RevealAnimationPlayer). N'a besoin d'être changée
## que si la hauteur du saut est retouchée dans le panneau Animation.
@export var shadow_jump_height: float = 24.0

const TEXTURE_REGION_SIZE := 64
# Préchargé plutôt que de compter sur la résolution globale de class_name
# (peu fiable au tout premier chargement headless du projet) — même pattern
# que WorldmapCursor.gd/HeroShadow.gd.
const TileGeometry = preload("res://Scripts/Worldmap/TileGeometry.gd")
# Préchargé (résolu à la compilation du script, aucune lecture disque au
# runtime) plutôt que load() dans _ready() : le chemin est connu à l'édition,
# pas de raison de payer ce coût — même s'il est minime — à chaque lancement.
const RevealShadowMaskShader = preload("res://Shaders/reveal_shadow_mask.gdshader")

var is_revealing: bool = false
var revealing_cell: Vector2i = Vector2i.ZERO
# Position monde de revealing_cell, calculée une fois par reveal() : réutilisée
# par _on_reveal_swap() plutôt que recalculée (elle ne peut pas avoir changé
# entre les deux, la case ne bouge pas pendant sa propre révélation).
var revealing_cell_pos: Vector2 = Vector2.ZERO
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
@onready var reveal_shadow: Polygon2D = $"../RevealAnchor/RevealShadow"
@onready var reveal_lift: Node2D = $"../RevealAnchor/RevealLift"
@onready var reveal_tile: Sprite2D = $"../RevealAnchor/RevealLift/RevealTile"
@onready var reveal_animation_player: AnimationPlayer = $"../RevealAnimationPlayer"

func _ready() -> void:
	# tile_empty_hitzone() (silhouette mesurée pixel par pixel sur la tuile
	# "Empty" précisément, cf TileGeometry) — PAS tile_art_hitzone(), plus
	# généreux/générique et qui déborde visiblement au-dessus du vrai sommet
	# peint de "Empty" une fois rempli entièrement par un hexagone plein.
	reveal_shadow.polygon = TileGeometry.tile_empty_hitzone()

	# Masque explicite (reveal_shadow_mask.gdshader, même technique que
	# HeroShadow) en plus de la forme du Polygon2D lui-même : garantit, pixel
	# par pixel et en position MONDE, qu'aucun pixel de l'ombre ne s'affiche
	# jamais hors du contour réel de SA tuile — à n'importe quel instant de
	# l'animation (repos, décollage, chute), quelle que soit son échelle du
	# moment. tile_center_world est posé une fois par reveal() (la case ne
	# change pas en cours de route).
	reveal_shadow.material = ShaderMaterial.new()
	reveal_shadow.material.shader = RevealShadowMaskShader
	reveal_shadow.material.set_shader_parameter("hitzone_verts", TileGeometry.tile_empty_hitzone())

	# _process() ne sert qu'à faire varier reveal_shadow.scale pendant le saut
	# (cf plus bas) : sans intérêt le reste du temps (partie très largement
	# majoritaire d'une session de jeu). set_process(false) ici, réactivé au
	# début de chaque reveal() et redésactivé à la fin, plutôt que de laisser
	# Godot appeler _process() à chaque frame pour un simple "if not
	# is_revealing: return".
	set_process(false)

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
## La vraie case "empty" du TileMapLayer n'est PAS effacée au début : elle
## reste affichée telle quelle pendant tout le début de la séquence (pause +
## montée en teinte blanche). reveal_tile (déjà la tuile CIBLE, jamais une
## apparence "empty" intermédiaire — cf region_rect ci-dessous) ne devient
## visible qu'au décollage (_on_reveal_liftoff, sur la Method Track de
## l'animation) : c'est elle qui saute, et son z_index (11 pendant le vol,
## remis à 0 à l'atterrissage par _on_reveal_landed) reste toujours au-dessus
## de celui du TileMapLayer (-1), donc pendant toute la chute elle s'affiche
## bien PAR-DESSUS la tuile "empty" encore présente en dessous. reveal_shadow
## (hexagone plein, cf TileGeometry.tile_empty_hitzone — silhouette mesurée
## précisément sur "Empty", pas tile_art_hitzone qui déborde visiblement au
## sommet pour cette tuile précise) est visible dès le tout
## début — avant même reveal_tile — pour suggérer que la nouvelle tuile plane
## déjà au-dessus de la tuile "empty" ; sa taille suit la hauteur réelle du
## saut en continu (cf _process plus bas), et elle disparaît à l'atterrissage
## (_on_reveal_landed). Contrairement à reveal_tile, reveal_shadow RESTE dans
## le même bucket de tri (z_index) que le TileMapLayer plutôt que d'être
## monté au-dessus : posée au sol, elle doit pouvoir se faire recouvrir par
## une tuile voisine "devant elle" (plus bas sur la carte) comme n'importe
## quelle tuile — même mécanisme de tri Y que TileHighlight/HoverGlow (cf
## HIGHLIGHT_SORT_NUDGE dans TileHoverVisuals.gd, déjà appliqué à la position
## de reveal_anchor). En plus de ça, reveal_shadow_mask.gdshader (posé une
## fois dans _ready(), même technique que hero_shadow_ellipse.gdshader)
## masque explicitement chaque pixel hors du contour réel de CETTE tuile
## (tile_center_world, posé ci-dessous) : garanti PENDANT TOUTE LA DURÉE de
## l'animation, indépendamment du tri Y ou de l'échelle du moment. La case réelle
## n'est réécrite avec la cible qu'une fois l'animation entièrement terminée,
## en même temps que reveal_tile redevient invisible — jamais de recouvrement
## non désiré entre la vraie tuile statique et la tuile animée.
func reveal(cell: Vector2i) -> void:
	is_revealing = true
	# _process() ne fait quelque chose que pendant le saut (cf _ready()) :
	# réactivé ici, redésactivé à la toute fin de reveal() ci-dessous.
	set_process(true)
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
	var tile_center: Vector2 = tile_layer.to_global(tile_layer.map_to_local(cell))
	# Mémorisée pour _on_reveal_swap() plus bas : la case ne bouge pas pendant
	# sa propre révélation, inutile de refaire ce calcul une seconde fois.
	revealing_cell_pos = tile_center
	reveal_anchor.global_position = tile_center + hover_visuals.HIGHLIGHT_SORT_NUDGE
	# La case ne change pas en cours de route : posé une fois ici plutôt que
	# recalculé chaque frame (contrairement à HeroShadow, qui doit re-détecter
	# sa case sous des pieds en mouvement).
	(reveal_shadow.material as ShaderMaterial).set_shader_parameter("tile_center_world", tile_center)

	reveal_tile.region_rect = Rect2(
		pending_reveal_target.x * TEXTURE_REGION_SIZE, pending_reveal_target.y * TEXTURE_REGION_SIZE,
		TEXTURE_REGION_SIZE, TEXTURE_REGION_SIZE,
	)
	reveal_lift.z_index = 0
	# Reste masquée jusqu'au décollage (cf _on_reveal_liftoff) : la tuile
	# "empty" réelle doit rester seule visible pendant la pause initiale.
	reveal_tile.visible = false

	# Ombre de la nouvelle tuile, visible dès le tout début (avant même que
	# reveal_tile n'apparaisse) : simule que la tuile "empty" est déjà sous
	# elle. Pleine taille au repos, rétrécie/regrandie en continu pendant le
	# saut par _process() (actif tant que is_revealing est vrai, cf
	# set_process() dans reveal()). Masquée à l'atterrissage (_on_reveal_landed).
	reveal_shadow.scale = Vector2.ONE
	reveal_shadow.visible = true

	# Props posés (dans l'éditeur de maps) sur cette case "empty" : reparentés
	# sous reveal_lift pour suivre le même saut/la même chute, et partagent le
	# matériau de reveal_tile (même ressource ShaderMaterial) pour se teinter
	# en blanc exactement en même temps, sans piste d'animation séparée.
	# Masqués jusqu'au décollage pour la même raison que reveal_tile ci-dessus.
	reveal_active_props = main.get_props_for_cell(cell)
	for prop in reveal_active_props:
		prop.reparent(reveal_lift, true)
		prop.material = reveal_tile.material
		prop.visible = false

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
	# Plus rien à faire à chaque frame jusqu'à la prochaine reveal() (cf _ready()).
	set_process(false)

## Pendant tout le saut, rétrécit/regrandit reveal_shadow en continu d'après
## la hauteur RÉELLE de reveal_lift (piloté par la piste "position:y" de
## l'animation) plutôt que par une seconde piste de keyframes séparée à
## maintenir manuellement en phase avec la première : 1.0 au sol (position.y
## == 0), shadow_min_scale au sommet du saut (position.y == -shadow_jump_height,
## négatif car "monter" réduit la coordonnée Y). max(0.0, ...) ignore le léger
## rebond sous le sol (position.y légèrement positif) en fin d'atterrissage,
## qui ne doit jamais faire grandir l'ombre au-delà de sa taille normale.
func _process(_delta: float) -> void:
	if not is_revealing:
		return
	var height: float = maxf(0.0, -reveal_lift.position.y)
	var t: float = clampf(height / shadow_jump_height, 0.0, 1.0)
	reveal_shadow.scale = Vector2.ONE * lerp(1.0, shadow_min_scale, t)

# Appelée par la Method Track de "tile_reveal" au sommet du saut : repositionne
# highlight/sélection pour une tuile normale (jamais "empty1" après une
# révélation), sans committer la vraie case tout de suite — ça doit être prêt
# avant leur fade-in en fin de timeline. La case réelle n'est écrite qu'à la
# fin de reveal(), qui rappelle cursor.update_tile_state() pour finaliser le
# reste (current_terrain_type, hover_glow, etc.).
func _on_reveal_swap() -> void:
	hide_cost_bubble()
	# revealing_cell_pos déjà calculée par reveal() pour cette même case : la
	# case ne bouge pas en cours d'animation, pas besoin de refaire
	# to_global(map_to_local(...)) une seconde fois pour la même valeur.
	hover_visuals.position_highlight(revealing_cell_pos, false)

# reveal_lift hérite de RevealAnchor (z_index=-1, la couche "sol", au même
# niveau que TileMapLayer) : au repos c'est correct, mais pendant le saut la
# tuile (et les props qui la suivent, cf reveal_active_props) doivent
# visuellement passer devant les props voisins (PropsLayer, z_index=0 par
# défaut) ET devant la vraie tuile "empty" restée affichée sur le TileMapLayer
# (cf reveal(), qui ne l'efface plus), comme n'importe quel élément en l'air.
# Le Y-sort seul ne peut pas régler ça : en Godot, z_index prime toujours sur
# le tri Y, donc rien à z=-1 ne peut jamais passer devant quelque chose à z=0,
# quelle que soit sa position Y. On monte donc temporairement reveal_lift (et
# tout ce qu'il porte, par cascade) au niveau de WorldmapCursor (z=10, le plus
# haut du gameplay) le temps du vol — et c'est ici, au moment précis où elle
# décolle, que reveal_tile (et les props qui l'accompagnent) deviennent
# visibles : jusque-là, seule la tuile "empty" réelle était affichée.
func _on_reveal_liftoff() -> void:
	reveal_lift.z_index = 11
	reveal_tile.visible = true
	for prop in reveal_active_props:
		prop.visible = true

## La tuile vient de toucher le sol : son ombre n'a plus lieu d'être (elle
## est redevenue plate, plus besoin de suggérer qu'elle plane au-dessus de
## la tuile "empty").
func _on_reveal_landed() -> void:
	reveal_lift.z_index = 0
	reveal_shadow.visible = false
