extends HBoxContainer

## Compteur de monnaie "hex" affiché en haut à droite de l'écran.
@onready var count_label: Label = $Count

func _ready() -> void:
	count_label.text = str(PlayerCurrency.hex)
	PlayerCurrency.hex_changed.connect(_on_hex_changed)
	# La boîte est ancrée par son coin haut-droit (grow_horizontal = BEGIN) :
	# il faut recalculer sa taille pour qu'elle s'ajuste au texte au lieu de
	# garder une taille de zéro/placeholder.
	size = get_combined_minimum_size()

func _on_hex_changed(new_value: int) -> void:
	count_label.text = str(new_value)
	size = get_combined_minimum_size()
