extends Node

## Monnaie du joueur ("hex"), utilisée pour changer la nature des tuiles
## "Empty". Autoload : état global du joueur, indépendant de la scène/map
## affichée à l'écran.
signal hex_changed(new_value: int)

var hex: int = 20:
	set(value):
		hex = value
		hex_changed.emit(hex)
