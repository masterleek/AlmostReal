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
## LE SEGMENT BLEU = LES DÉGÂTS DE BLESSURE (cf. BattleUnit). Ce sont des PV
## encore acquis mais mis en jeu : ils occupent le bout du remplissage, entre
## le vert (ce qui est sûr) et la gouttière vide. Ils ne sont donc PAS une
## animation de transition — ils restent affichés tant que la blessure n'est
## ni guérie ni convertie, et c'est bien pour ça qu'ils bougent : la zone est
## rayée, et les rayures défilent en boucle pour signaler un état instable
## plutôt qu'une part de jauge acquise (cf. _assets/battle/hp_progress_bar.jpg).

const UNDERLAYER := preload("res://UI/Battle/hp_underlayer.svg")
const FILL := preload("res://UI/Battle/hp_fill.svg")

const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

## Le remplissage est encastré de 1 px dans la gouttière (59×5 contre 57×3).
const FILL_INSET := Vector2(1, 1)

## Couleurs de la zone de blessure, données par l'auteur : fond bleu profond,
## rayures bleu vif par-dessus.
const INJURY_COLOR := Color8(0x15, 0x3F, 0xE4)
const INJURY_STRIPE_COLOR := Color8(0x00, 0x7B, 0xFF)

## Motif de rayures. Il est fabriqué à la résolution de l'ÉCRAN et non de
## design : la zone ne fait que 3 px de design de haut, où une diagonale n'a
## pas la place d'exister. À l'écran elle en fait 12, et les rayures s'y
## lisent. C'est le même raisonnement que le suréchantillonnage du texte
## (cf. BattleText) — on dessine à la finesse de l'écran ce qui n'est pas de la
## pixel-art d'origine.
##
## Période en pixels d'ÉCRAN, moitié pleine / moitié vide. À 45°, une période
## de 8 donne une rayure de 4 px pour une zone haute de 12 : trois bandes
## visibles en permanence, quelle que soit la largeur de la blessure.
const STRIPE_PERIOD := 8
## Vitesse de défilement, en pixels d'écran par seconde. Une période toutes les
## demi-secondes : assez pour que l'œil accroche, assez lent pour ne pas
## clignoter à côté du reste du HUD.
const STRIPE_SPEED := 16.0

## Seuls les coins arrondis sont préservés par le 9-slice ; le corps de la
## gouttière est uni sur toute sa longueur, 2 px suffisent donc largement.
const PATCH_MARGIN := 2

## Largeur voulue en unités de design, à poser AVANT d'ajouter le nœud à
## l'arbre. 0 = largeur naturelle de l'asset (59), celle du HUD.
var design_width: int = 0

var _fill: Sprite2D
var _injury: Sprite2D
## Largeur de la zone de blessure, en pixels d'écran. 0 = pas de blessure, donc
## rien à animer.
var _injury_width: float = 0.0

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

	# Le motif est déjà à la résolution de l'écran : sprite_native, comme un
	# SVG importé — surtout pas sprite(), qui l'agrandirait une seconde fois.
	# `region_rect` sort de la texture et le mode « repeat » la fait boucler :
	# c'est ce qui permet de couvrir n'importe quelle largeur de blessure avec
	# une seule tuile, et de la faire défiler en déplaçant simplement la
	# région (cf. _process) — sans shader ni texture redessinée à chaque image.
	_injury = PixelScale.sprite_native(_stripes_texture())
	_injury.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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
	# HUD n'est pas rééchantillonné. Il ne s'applique qu'au dégradé : les
	# rayures, elles, sont dessinées à la période voulue et n'ont pas à être
	# déformées avec la piste.
	_fill.scale.x *= _track_width() / PixelScale.design_size(FILL).x

	set_process(false)
	set_ratio(1.0)

## Motif de rayures diagonales, en pixels d'écran. Une seule tuile de la
## largeur d'une période : le mode « repeat » se charge du reste.
func _stripes_texture() -> ImageTexture:
	var height := int(PixelScale.design_size(FILL).y) * PixelScale.SCALE
	var image := Image.create_empty(STRIPE_PERIOD, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in STRIPE_PERIOD:
			# (x + y) plutôt que x seul : c'est ce qui penche la rayure à 45°.
			# La tuile ne boucle qu'horizontalement (sa hauteur est exactement
			# celle de la zone), la diagonale n'a donc pas à retomber sur ses
			# pieds verticalement.
			var striped := (x + y) % STRIPE_PERIOD < STRIPE_PERIOD / 2
			image.set_pixel(x, y, INJURY_STRIPE_COLOR if striped else INJURY_COLOR)
	return ImageTexture.create_from_image(image)

## Longueur utile, à l'intérieur de la gouttière.
func _track_width() -> float:
	return float(design_width) - 2.0 * FILL_INSET.x

## `ratio` = part de jauge ACQUISE (PV moins blessure) ; `full_ratio` = PV
## courants, blessure comprise. C'est entre les deux que se dessine le segment
## bleu. `full_ratio` omis (ou inférieur) = pas de blessure.
func set_ratio(ratio: float, full_ratio: float = -1.0) -> void:
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

	if full_ratio <= ratio:
		_injury_width = 0.0
		_injury.region_rect = Rect2()
		set_process(false)
		return
	var full_width: float = round(track * clampf(full_ratio, 0.0, 1.0))
	# La zone de blessure est mesurée directement en pixels d'écran : son motif
	# n'est pas étiré avec la piste, il est dessiné à sa période.
	_injury_width = (full_width - width) * PixelScale.SCALE
	_injury.position = FILL_INSET + Vector2(width, 0)
	set_process(true)
	_scroll_stripes()

func _process(_delta: float) -> void:
	_scroll_stripes()

## Fait avancer les rayures en déplaçant la fenêtre de lecture dans la texture,
## qui boucle. L'origine est l'horloge absolue : la zone peut changer de
## largeur d'un tour à l'autre sans que les rayures sautent.
func _scroll_stripes() -> void:
	var offset := fmod(Time.get_ticks_msec() / 1000.0 * STRIPE_SPEED, float(STRIPE_PERIOD))
	var height := PixelScale.design_size(FILL).y * PixelScale.SCALE
	_injury.region_rect = Rect2(Vector2(-offset, 0), Vector2(_injury_width, height))

## Région de texture donnant `design_width` pixels de design une fois
## l'étirement de piste appliqué. region_rect se mesure dans la texture, donc
## dans l'espace agrandi.
func _region(width: float, full: Vector2, track: float) -> Rect2:
	if width <= 0.0:
		return Rect2()
	return Rect2(
		Vector2.ZERO, Vector2(width * full.x / track, full.y) * PixelScale.SCALE
	)
