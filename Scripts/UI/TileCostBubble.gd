extends Control

## Bulle affichée au-dessus d'une tuile "Empty" survolée, indiquant le coût
## (en hex) pour changer sa nature. Reste en espace écran (comme le compteur
## HUD) plutôt qu'en espace monde, pour garder le même rendu du texte quel
## que soit le zoom de la caméra.
@onready var bubble: PanelContainer = $Bubble
@onready var content: HBoxContainer = $Bubble/Content
@onready var cost_label: Label = $Bubble/Content/Cost
@onready var arrow: TextureRect = $Arrow

const AFFORDABLE_COLOR := Color(1, 1, 1, 1)
const INSUFFICIENT_COLOR := Color(0.99609375, 0.203921568, 0.203921568, 1) # #FE3434

func _ready() -> void:
	visible = false

# `anchor_screen_pos` : point (espace écran) juste au-dessus de la tuile, où
# la pointe de la flèche doit toucher. `content_offset` : décalage manuel
# supplémentaire de l'icône+coût à l'intérieur de la bulle. `arrow_offset` :
# décalage manuel supplémentaire de la flèche. `affordable` : si le joueur
# n'a pas assez de hex, le coût s'affiche en rouge plutôt qu'en blanc.
func show_above(anchor_screen_pos: Vector2, content_offset: Vector2 = Vector2.ZERO, arrow_offset: Vector2 = Vector2.ZERO, cost: int = 1, affordable: bool = true) -> void:
	visible = true
	cost_label.text = str(cost)
	cost_label.add_theme_color_override("font_color", AFFORDABLE_COLOR if affordable else INSUFFICIENT_COLOR)
	bubble.size = bubble.get_combined_minimum_size()
	bubble.position = Vector2(-bubble.size.x / 2.0, -bubble.size.y - arrow.size.y)
	arrow.position = Vector2(-arrow.size.x / 2.0, -arrow.size.y) + arrow_offset
	position = anchor_screen_pos
	# PanelContainer ne décale pas son enfant unique par les marges du
	# StyleBoxTexture (seule sa taille en tient compte) : on reproduit ce
	# placement nous-mêmes pour garder le contenu centré, puis on ajoute le
	# décalage manuel par-dessus au lieu de l'écraser.
	var panel_style := bubble.get_theme_stylebox("panel")
	content.position = Vector2(panel_style.content_margin_left, panel_style.content_margin_top) + content_offset

func hide_bubble() -> void:
	visible = false
