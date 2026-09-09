extends Node2D

## Jauge de vie d'une unité : gouttière + remplissage + segment « blessure ».
##
## Le remplissage est CLIPPÉ, pas étiré : hp_fill.png est un dégradé vert→jaune
## dont la couleur porte une information (l'extrémité jaune = jauge pleine).
## L'étirer en fonction des PV ferait varier la couleur affichée avec les PV
## max de l'unité, ce qui n'a pas de sens. On coupe donc la texture à la
## fraction voulue via region_rect.
##
## LARGEUR. La jauge existe à deux tailles sur les maquettes : 59 px pour les
## alliés du HUD, 32 px pour la cible visée pendant le ciblage. C'est le même
## asset : la gouttière est un rectangle uni à coins arrondis, un 9-slice la
## rétrécit donc sans déformer ses extrémités. Le dégradé, lui, est ramené à la
## largeur de la PISTE — pas des PV courants : il continue de représenter le
## remplissage de 0 à 100 %, à la taille de la jauge sur laquelle il est posé.
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

## Seuls les coins arrondis sont préservés par le 9-slice ; le corps de la
## gouttière est uni sur toute sa longueur, 2 px suffisent donc largement.
const PATCH_MARGIN := 2

## Largeur voulue en unités de design, à poser AVANT d'ajouter le nœud à
## l'arbre. 0 = largeur naturelle de l'asset (59), celle du HUD.
var design_width: int = 0

var _fill: Sprite2D
var _injury: Sprite2D

func _ready() -> void:
	var natural := PixelScale.design_size(UNDERLAYER)
	if design_width <= 0:
		design_width = int(natural.x)

	# UNDERLAYER et FILL sont des SVG déjà à la résolution de l'écran
	# (cf. PixelScale.sprite_native) : rien à agrandir au runtime, seulement à
	# retailler. Un NinePatchRect plutôt qu'un Sprite2D pour que la largeur
	# soit réglable sans écraser les extrémités arrondies.
	var gutter := NinePatchRect.new()
	gutter.texture = UNDERLAYER
	gutter.patch_margin_left = PATCH_MARGIN * PixelScale.SCALE
	gutter.patch_margin_right = PATCH_MARGIN * PixelScale.SCALE
	gutter.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	gutter.size = Vector2(design_width, natural.y) * PixelScale.SCALE
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelScale.apply(gutter)
	add_child(gutter)

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

	# Étirement horizontal de la piste, en plus de la contre-échelle posée par
	# PixelScale. Vaut exactement 1 sur une jauge de largeur naturelle : le
	# HUD n'est pas rééchantillonné.
	var stretch := _track_width() / PixelScale.design_size(FILL).x
	_fill.scale.x *= stretch
	_injury.scale.x *= stretch

	set_ratio(1.0)

## Longueur utile, à l'intérieur de la gouttière.
func _track_width() -> float:
	return float(design_width) - 2.0 * FILL_INSET.x

## `ratio` = PV courants / PV max. `previous_ratio` (≥ ratio) fait apparaître
## le segment bleu de blessure ; l'omettre ne dessine que le remplissage.
func set_ratio(ratio: float, previous_ratio: float = -1.0) -> void:
	# `design_size()`, pas `Vector2(FILL.get_width(), FILL.get_height())` : FILL
	# est un SVG déjà rastérisé ×4, son get_width() renvoie la taille ÉCRAN
	# (228), pas la taille de DESIGN (57) sur laquelle tout le calcul qui suit
	# doit se faire.
	var full := PixelScale.design_size(FILL)
	var track := _track_width()
	# On arrondit la largeur AFFICHÉE, pas la largeur de texture : c'est elle
	# qui doit tomber sur un pixel de design entier.
	var width: float = round(track * clampf(ratio, 0.0, 1.0))
	_fill.region_rect = _region(width, full, track)

	if previous_ratio <= ratio:
		_injury.region_rect = Rect2()
		return
	var previous_width: float = round(track * clampf(previous_ratio, 0.0, 1.0))
	_injury.position = FILL_INSET + Vector2(width, 0)
	_injury.region_rect = _region(previous_width - width, full, track)

## Région de texture donnant `design_width` pixels de design une fois
## l'étirement de piste appliqué. region_rect se mesure dans la texture, donc
## dans l'espace agrandi.
func _region(width: float, full: Vector2, track: float) -> Rect2:
	if width <= 0.0:
		return Rect2()
	return Rect2(
		Vector2.ZERO, Vector2(width * full.x / track, full.y) * PixelScale.SCALE
	)
