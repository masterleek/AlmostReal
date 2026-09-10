extends Node2D

## Rangée de points d'action (losanges) d'une unité.
##
## Piège du jeu d'assets : « on » (11×11) et « off » (8×8) n'ont PAS la même
## taille — le losange allumé porte un halo qui déborde. Les aligner par leur
## coin haut-gauche décalerait visuellement un point sur deux. On les centre
## donc tous les deux sur la même case de largeur PITCH.
##
## EN SVG PLUTÔT QU'EN PNG (test) : ces deux icônes existent en vectoriel
## (`_assets/battle/ic_eko_*.svg`, mêmes dimensions nominales que les PNG
## qu'elles remplacent), importées avec `svg/scale = PixelScale.SCALE` — Godot
## les rastérise donc une fois pour toutes à la résolution de l'écran (44×44
## et 32×32), sans passer par l'agrandissement au runtime de `PixelScale`, qui
## n'a plus rien à faire ici. `design_size()` sert à retrouver leur taille en
## unités de design pour le centrage, puisque `get_width()` renvoie désormais
## la taille rastérisée (×4), pas la taille nominale.

const ON := preload("res://UI/Battle/ic_ap_on.svg")
const OFF := preload("res://UI/Battle/ic_ap_off.svg")

const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

## Pas horizontal entre deux points, en unités de design. Relevé sur la
## maquette (écart entre les centres de trois losanges consécutifs : 9,0 px à
## chaque fois), et NON déduit de la largeur nominale de l'icône « on »
## (11 px) : elle porte un halo qui déborde, les losanges se chevauchent donc
## légèrement.
const PITCH := 9

## Pas effectif, à poser avant set_points(). La colonne de coût d'une liste
## d'Ekos serre ses losanges davantage que la ligne de PA du HUD (6 px contre
## 9, relevés respectivement sur mockup_preparation_select_eko.jpg et
## mockup_preparation.png) : c'est le même asset, pas le même espacement.
var pitch: int = PITCH

## Redessine la rangée : `current` points allumés sur `maximum`.
func set_points(current: int, maximum: int) -> void:
	for child in get_children():
		child.queue_free()
	# Toujours calée sur « on », comme avant le passage en SVG : c'est elle
	# qui définit la hauteur de la case (son halo est le plus grand des deux).
	var on_size := PixelScale.design_size(ON)
	for i in maximum:
		var texture: Texture2D = ON if i < current else OFF
		var size := PixelScale.design_size(texture)
		var dot := PixelScale.sprite_native(texture)
		# Centrage dans la case : arrondi à l'entier, sinon le Stage ×4
		# rendrait la texture sur un demi-pixel.
		dot.position = Vector2(
			i * pitch + int((pitch - size.x) / 2.0),
			int((on_size.y - size.y) / 2.0),
		)
		add_child(dot)

## Largeur totale occupée par `count` points — utile pour aligner ce qui suit.
static func width_for(count: int, dot_pitch: int = PITCH) -> int:
	return count * dot_pitch
