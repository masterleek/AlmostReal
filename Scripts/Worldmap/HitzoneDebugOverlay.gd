extends Node2D

## Contour de debug de la hitzone de chaque tuile posée sur la map (même
## forme que HITZONE_POLY côté MapEditor, cf tools/MapEditor/public/canvas.js)
## — affiché/masqué avec la touche A, pour vérifier en jeu l'alignement de la
## zone de pose sûre des props avec le rendu réel des tuiles.

const CELL := 64.0
const HITZONE_W := 64.0
const HITZONE_H := 50.0
const HITZONE_SHOULDER_Y := HITZONE_H / 3.0

@onready var tile_layer: TileMapLayer = get_parent().get_node("TileMapLayer")

func _ready() -> void:
	visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_A:
		visible = not visible
		if visible:
			queue_redraw()

func _draw() -> void:
	for cell: Vector2i in tile_layer.get_used_cells():
		draw_hitzone(tile_layer.map_to_local(cell))

# Identique à drawHitzone() côté MapEditor : sommets ancrés sur le haut du
# sprite (center.y - CELL/2), pas sur son centre — la face du dessus d'une
# tuile commence en haut du sprite, le reste étant son relief/épaisseur.
func draw_hitzone(center: Vector2) -> void:
	var sprite_top := center.y - CELL / 2.0
	var points := PackedVector2Array([
		Vector2(center.x, sprite_top),
		Vector2(center.x + HITZONE_W / 2.0, sprite_top + HITZONE_SHOULDER_Y),
		Vector2(center.x + HITZONE_W / 2.0, sprite_top + HITZONE_H - HITZONE_SHOULDER_Y),
		Vector2(center.x, sprite_top + HITZONE_H),
		Vector2(center.x - HITZONE_W / 2.0, sprite_top + HITZONE_H - HITZONE_SHOULDER_Y),
		Vector2(center.x - HITZONE_W / 2.0, sprite_top + HITZONE_SHOULDER_Y),
		Vector2(center.x, sprite_top),
	])
	draw_polyline(points, Color(1, 0.32, 0.32), 1.5)
