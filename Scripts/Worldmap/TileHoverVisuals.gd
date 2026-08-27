extends Node2D

## Highlight (cursor_worldmap2.png), glow additif (HoverGlow) et surbrillance
## de sélection (highlight.png) affichés sur la case survolée par
## WorldmapCursor — purement visuel : ne sait rien du déplacement ni de la
## révélation, pilotable depuis n'importe quel curseur/sélecteur qui sait
## juste "quelle case, est-elle vide, vient-elle d'être choisie".

## Pulsation d'échelle idle du highlight — purement visuelle, n'affecte ni sa
## position ni le tri Y (contrairement à un bobbing, qui nécessiterait de
## refaire la compensation de tri appliquée plus bas pour la tuile "Empty").
@export var highlight_pulse_amplitude: float = 0.06
@export var highlight_pulse_speed: float = 6.0

## Décalage manuel du highlight par rapport à la position calculée de la
## case, pour corriger un désalignement visuel au pixel près directement
## depuis l'inspecteur Godot. `highlight_offset` s'applique par défaut à
## toutes les tuiles ; `empty_tile_highlight_offset` le remplace uniquement
## sur les tuiles "Empty", dont l'art nécessite un calage différent.
@export var highlight_offset: Vector2 = Vector2.ZERO
@export var empty_tile_highlight_offset: Vector2 = Vector2(0, 10)

## Décalage manuel du glow (HoverGlow) par rapport à la case survolée, même
## logique de calage que highlight_offset.
@export var glow_offset: Vector2 = Vector2.ZERO
@export var glow_intensity: float = 0.0875
@export var glow_pulse_amplitude: float = 0.15

## Décalage manuel du sprite de sélection (highlight.png), en plus du glow —
## même logique de calage que highlight_offset : tile_select_offset
## s'applique par défaut à toutes les tuiles, tile_select_empty_offset le
## remplace uniquement sur "Empty".
@export var tile_select_offset: Vector2 = Vector2.ZERO
@export var tile_select_empty_offset: Vector2 = Vector2.ZERO

## Anim de test : quand une tuile "Empty" est fraîchement sélectionnée, la
## surbrillance fait un wiggle (rotation amortie) une seule fois, pas en boucle.
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
# Exposé : TileRevealController s'en sert pour positionner reveal_anchor
# avec le même calage.
const HIGHLIGHT_SORT_NUDGE := Vector2(0, 11)
# Garantit que TileSelectHighlight se dessine toujours juste derrière
# TileHighlight, qu'ils soient dans le même bucket de tri (z_index) ou non,
# sans dépendre de l'ordre de déclaration dans la scène pour départager une
# éventuelle égalité de tri.
const TILE_SELECT_BEHIND_EPSILON := Vector2(0, 0.5)

const TEXTURE_REGION_SIZE := 64

@onready var highlight: Node2D = $"../TileHighlight"
@onready var highlight_sprite: Sprite2D = $"../TileHighlight/Sprite2D"
@onready var hover_glow: Sprite2D = $"../HoverGlow"
@onready var tile_select_highlight: Sprite2D = $"../TileSelectHighlight"

func _ready() -> void:
	highlight.visible = false
	hover_glow.visible = false
	tile_select_highlight.visible = false

func _process(delta: float) -> void:
	update_pulses()
	update_wiggle(delta)

## Affiche/repositionne highlight, glow et sélection sur la case dont le
## centre monde est `cell_pos`, avec l'apparence de `atlas` pour le glow
## (même dessin que la vraie tuile, cf commentaire plus bas).
func show_at(cell_pos: Vector2, atlas: Vector2i, is_empty: bool) -> void:
	highlight.visible = true
	hover_glow.visible = true
	tile_select_highlight.visible = true
	position_highlight(cell_pos, is_empty)
	hover_glow.global_position = cell_pos + HIGHLIGHT_SORT_NUDGE
	hover_glow.offset = glow_offset - HIGHLIGHT_SORT_NUDGE
	# Reprend le même dessin (atlas + région) que la vraie tuile à cette case
	# : comme il vient de la même texture avec sa transparence, le glow
	# additif n'apparaît que sur les pixels réellement opaques du sprite,
	# jamais sur le fond transparent (cf tuile "Empty").
	hover_glow.region_rect = Rect2(
		atlas.x * TEXTURE_REGION_SIZE, atlas.y * TEXTURE_REGION_SIZE,
		TEXTURE_REGION_SIZE, TEXTURE_REGION_SIZE,
	)

## Aucune tuile sous le curseur (mode libre, ou case hors grille) : tout masquer.
func hide_all() -> void:
	highlight.visible = false
	hover_glow.visible = false
	tile_select_highlight.visible = false

## Masque juste le glow, immédiatement — utilisé par TileRevealController au
## tout début d'une révélation, avant que la case ne soit effacée du
## TileMapLayer (hover_glow n'est piloté par aucune piste de l'animation,
## contrairement au highlight/à la sélection).
func hide_glow_only() -> void:
	hover_glow.visible = false

## Positionne highlight et tile_select_highlight sur la case dont le centre
## monde est `cell_pos` — `is_empty` choisit entre le calage normal et celui
## (décalé, autre bucket de tri) des tuiles "Empty". Public : aussi appelée
## par TileRevealController._on_reveal_swap(), qui doit repositionner ces
## deux sprites pour une tuile normale avant que la vraie case ne soit
## réécrite dans le TileMapLayer.
func position_highlight(cell_pos: Vector2, is_empty: bool) -> void:
	highlight.z_index = -1 if is_empty else 0
	if is_empty:
		highlight.global_position = cell_pos + HIGHLIGHT_SORT_NUDGE
		highlight_sprite.position = empty_tile_highlight_offset - HIGHLIGHT_SORT_NUDGE
	else:
		highlight.global_position = cell_pos + highlight_offset
		highlight_sprite.position = Vector2.ZERO
	# Reprend exactement la logique de TileHighlight (qui fonctionne sans
	# clipping) plutôt que le mécanisme de tri "profondeur réelle" du glow,
	# qui s'est avéré peu fiable pour cet asset. Un tout petit nudge négatif
	# garantit qu'il se dessine juste derrière TileHighlight dans les deux
	# cas (normal : même bucket z=0 ; Empty : même bucket z=-1), sans jamais
	# dépendre d'un ordre de déclaration ambigu en cas d'égalité de tri.
	tile_select_highlight.z_index = highlight.z_index
	var select_visual_offset := tile_select_empty_offset if is_empty else tile_select_offset
	var select_nudge := (HIGHLIGHT_SORT_NUDGE if is_empty else Vector2.ZERO) - TILE_SELECT_BEHIND_EPSILON
	tile_select_highlight.global_position = cell_pos + select_nudge
	tile_select_highlight.offset = select_visual_offset - select_nudge

## Démarre le wiggle une seule fois — à appeler par le curseur uniquement
## quand une case vient tout juste de devenir la case sélectionnée (pas à
## chaque frame), pour ne pas le redéclencher tant qu'on reste dessus.
func start_wiggle() -> void:
	is_wiggling = true
	wiggle_elapsed = 0.0

## Interrompt le wiggle en cours (s'il y en a un) et remet la sélection bien
## droite — utilisé par TileRevealController au début d'une révélation, pour
## ne pas laisser le wiggle continuer à tourner par-dessus l'animation.
func cancel_wiggle() -> void:
	is_wiggling = false
	tile_select_highlight.rotation = 0.0

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

func update_pulses() -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * highlight_pulse_speed) * highlight_pulse_amplitude
	highlight_sprite.scale = Vector2.ONE * pulse
	if hover_glow.visible:
		var glow_pulse := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * highlight_pulse_speed) * glow_pulse_amplitude
		hover_glow.modulate.a = glow_intensity * glow_pulse
