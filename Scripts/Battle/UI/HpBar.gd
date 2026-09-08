extends Node2D

## Jauge de vie d'une unité : gouttière + remplissage + segment « blessure ».
##
## Le remplissage est CLIPPÉ, pas étiré : hp_fill.png est un dégradé vert→jaune
## dont la couleur porte une information (l'extrémité jaune = jauge pleine).
## L'étirer ferait varier la couleur affichée avec les PV max de l'unité, ce
## qui n'a pas de sens. On coupe donc la texture à la fraction voulue via
## region_rect.
##
## Le segment bleu reproduit l'état « injury damage » du mockup ui_hp : la
## portion de vie qui vient d'être perdue, affichée le temps d'une transition.
## Il se dessine entre la fin du remplissage courant et l'ancienne valeur.

const UNDERLAYER := preload("res://UI/Battle/hp_underlayer.svg")
const FILL := preload("res://UI/Battle/hp_fill.svg")

const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

## Le remplissage est encastré de 1 px dans la gouttière (59×5 contre 57×3).
const FILL_INSET := Vector2(1, 1)
const INJURY_COLOR := Color8(0x42, 0x9E, 0xFF)

var _fill: Sprite2D
var _injury: Sprite2D

func _ready() -> void:
	# UNDERLAYER et FILL sont des SVG déjà à la résolution de l'écran
	# (cf. PixelScale.sprite_native) : rien à agrandir au runtime.
	add_child(PixelScale.sprite_native(UNDERLAYER))

	# Un Sprite2D sur une texture unie plutôt qu'un ColorRect : le bloc vit
	# dans un groupe incliné, et Godot ne lisse pas les bords d'un quad. Passer
	# par une texture le fait bénéficier du même traitement que le reste
	# (cf. PixelScale), donc d'un bord net une fois tourné.
	#
	# Cette texture-ci, elle, est fabriquée ici même (un aplat de couleur) —
	# elle n'a jamais existé « en grand » comme un SVG, donc on la construit
	# volontairement en unités de DESIGN (PixelScale.design_size(FILL), pas
	# FILL.get_width() qui renvoie désormais la taille rastérisée ×4) et on la
	# fait passer par le chemin d'agrandissement au runtime habituel
	# (PixelScale.sprite, pas sprite_native).
	var fill_size := PixelScale.design_size(FILL)
	var solid := Image.create_empty(int(fill_size.x), int(fill_size.y), false, Image.FORMAT_RGBA8)
	solid.fill(INJURY_COLOR)
	_injury = PixelScale.sprite(ImageTexture.create_from_image(solid))
	_injury.region_enabled = true
	_injury.region_rect = Rect2()
	_injury.position = FILL_INSET
	add_child(_injury)

	_fill = PixelScale.sprite_native(FILL)
	_fill.region_enabled = true
	_fill.position = FILL_INSET
	add_child(_fill)

## `ratio` = PV courants / PV max. `previous_ratio` (≥ ratio) fait apparaître
## le segment bleu de blessure ; l'omettre ne dessine que le remplissage.
func set_ratio(ratio: float, previous_ratio: float = -1.0) -> void:
	# `design_size()`, pas `Vector2(FILL.get_width(), FILL.get_height())` : FILL
	# est un SVG déjà rastérisé ×4, son get_width() renvoie la taille ÉCRAN
	# (228), pas la taille de DESIGN (57) sur laquelle tout le calcul qui suit
	# doit se faire.
	var full := PixelScale.design_size(FILL)
	var width: float = round(full.x * clampf(ratio, 0.0, 1.0))
	# region_rect se mesure dans la texture, donc dans l'espace agrandi.
	_fill.region_rect = Rect2(Vector2.ZERO, Vector2(width, full.y) * PixelScale.SCALE)

	if previous_ratio <= ratio:
		_injury.region_rect = Rect2()
		return
	var previous_width: float = round(full.x * clampf(previous_ratio, 0.0, 1.0))
	_injury.position = FILL_INSET + Vector2(width, 0)
	_injury.region_rect = Rect2(Vector2.ZERO, Vector2(previous_width - width, full.y) * PixelScale.SCALE)
