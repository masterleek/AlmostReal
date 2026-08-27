extends HBoxContainer

## Indice contextuel en bas à droite de l'écran (bouton "X" + texte) qui
## change selon ce que WorldmapCursor survole : "Reveal" sur une case Empty,
## "Go to" sur toute autre case. Même style visuel (police, ombre, contour)
## que le compteur de hex (cf HexCounterHUD). Masqué en entier quand le
## curseur survole la case du Héros — aucune action de ce type n'a de sens
## sur sa propre case.

@onready var cursor: Node2D = $"../../WorldmapCursor"
@onready var hero: Node2D = $"../../Hero"
@onready var action_label: Label = $ActionLabel

# Couleur du texte quand la case visée par "Go to" est inatteignable en
# pathfinding depuis le Héros (cf Hero.find_path) — le blanc normal
# (theme_override_colors/font_color dans la scène) reste utilisé partout
# ailleurs, y compris pour "Reveal" (pas de notion d'accessibilité).
const UNREACHABLE_COLOR := Color8(0xB6, 0xB6, 0xB6)
const NORMAL_COLOR := Color(1, 1, 1, 1)

func _process(_delta: float) -> void:
	visible = cursor.current_cell != hero.current_cell
	if not visible:
		return

	if cursor.current_terrain_type == "empty1":
		action_label.text = "Reveal"
		action_label.add_theme_color_override("font_color", NORMAL_COLOR)
		return

	action_label.text = "Go to"
	var reachable: bool = not hero.find_path(hero.current_cell, cursor.current_cell).is_empty()
	action_label.add_theme_color_override("font_color", NORMAL_COLOR if reachable else UNREACHABLE_COLOR)
