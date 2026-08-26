extends Sprite2D

## Personnage statique posé sur la map (PNJ décoratif) : position fixe,
## réglable depuis l'éditeur Godot en déplaçant ce node dans la scène. Aucune
## logique de déplacement — contrairement à WorldmapCursor, qui répond au
## joueur.

# Pose "marche" de lyn.png (2e case sur 5 de la ligne marche), utilisée
# telle quelle comme pose statique.
const FRAME_RECT := Rect2(9, 73, 14, 15)

func _ready() -> void:
	texture = load("res://Sprites/lyn.png")
	region_enabled = true
	region_rect = FRAME_RECT
