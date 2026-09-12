extends Node2D

## Jauge de synergie : anneau qui se remplit dans le sens horaire, se vide en
## montant d'un niveau, jusqu'à MAX_LEVEL.
##
## Le remplissage passe par un TextureProgressBar en mode radial plutôt que par
## un shader : c'est exactement ce que ce nœud sait faire nativement, et ça
## évite d'introduire un .gdshader pour un seul élément d'UI.

const UNDERLAYER := preload("res://UI/Battle/synergie_underlayer.svg")
const FULL := preload("res://UI/Battle/synergie_full.svg")
const ICON := preload("res://UI/Battle/ic_synergie.svg")
## Plaque sombre derrière le chiffre du niveau. Le plan la listait depuis le
## Lot 1 (« pastille de niveau ») sans qu'elle serve : `synergy.jpg` montre bien
## le chiffre posé sur un fond, pas flottant sur la spirale.
const LEVEL_PLATE := preload("res://UI/Battle/round_synergie.svg")

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

## Quatre niveaux, 0 à 3 — c'est ce que montre `synergy.jpg`, dont la pastille
## va de « 0 » à « 3 ».
const MAX_LEVEL := 3

## La jauge n'est PAS un anneau complet : c'est une spirale dont la bouche est
## ouverte. Mesuré sur l'asset (couverture opaque angle par angle) : plus aucune
## matière entre 200° et 260°, soit une bande utile de 300° seulement, qui
## commence à 270° — l'extrémité épaisse et orange — et se termine à 200° sur la
## fine queue jaune. C'est aussi le sens dans lequel court le dégradé.
##
## Sans cette correspondance, un balayage de 360° gâcherait les 60° de la
## bouche : la jauge paraîtrait pleine bien avant d'atteindre sa charge
## maximale. On mappe donc la charge sur les 300° réellement dessinés.
const BAND_START_DEG := 270.0
const BAND_SWEEP_DEG := 300.0

## LA SPIRALE CHANGE DE COULEUR AVEC LE NIVEAU. Relevé sur `synergy.jpg`, dont
## les cinq vignettes montrent les états successifs : l'asset est recalé sur la
## troisième (celle qui porte « 1 »), et les extrémités du dégradé sont lues aux
## mêmes pixels sur les autres.
##
## Les niveaux 0 et 1 partagent le dégradé de l'asset — c'est bien ce que montre
## la référence, où la vignette partielle et la vignette « 1 » sont du même
## orangé. Seuls les niveaux 2 et 3 le recolorent.
##
## Le dégradé court le long de la spirale, de son extrémité ÉPAISSE (270°) à sa
## fine queue. On repère la position d'un pixel dedans par son canal VERT, seul
## à croître franchement et sans ambiguïté d'un bout à l'autre de l'asset
## (0x76 → 0xFE).
const FILL_GREEN_FROM := 0x76
const FILL_GREEN_TO := 0xFE
## Deux tableaux plats et non un tableau de paires : un `PackedColorArray(...)`
## imbriqué n'est pas une expression constante en GDScript (même famille de
## piège que `PackedStringArray`, cf. CLAUDE.md).
const LEVEL_FILL_FROM: PackedColorArray = [
	Color8(0xFD, 0x76, 0x1C), Color8(0xFD, 0x76, 0x1C),
	Color8(0xFF, 0x32, 0x1D), Color8(0xCE, 0x2C, 0xFB),
]
const LEVEL_FILL_TO: PackedColorArray = [
	Color8(0xEF, 0xFE, 0x00), Color8(0xEF, 0xFE, 0x00),
	Color8(0xFF, 0xB3, 0x01), Color8(0xFE, 0x8E, 0xE0),
]

## Chiffre du niveau, en bas à gauche du disque. Le corps est un dégradé, le
## contour le brun sombre commun à toute l'interface ; seul le LISERÉ suit le
## niveau, relevé lui aussi sur la référence — jaune jusqu'au niveau 1, puis or
## pâle, puis rose.
##
## La référence étant un JPEG, elle ne permet pas de séparer proprement le corps
## du liseré : ces trois teintes sont les couleurs claires dominantes de chaque
## pastille. À corriger si l'auteur fournit la planche sans perte.
const LEVEL_POS := Vector2(2, 17)
## La plaque est centrée sur l'encre du chiffre, qui commence un quart de corps
## sous le haut de sa boîte (cf. BattleText).
const LEVEL_PLATE_POS := Vector2(0, 17)
const LEVEL_SIZE := 12
const LEVEL_GRADIENT_FROM := Color8(0x42, 0x07, 0x01)
const LEVEL_GRADIENT_TO := Color8(0xFF, 0x73, 0x00)
const LEVEL_INLINE: PackedColorArray = [
	Color8(0xEE, 0xF8, 0x01), Color8(0xEE, 0xF8, 0x01),
	Color8(0xF8, 0xD0, 0x70), Color8(0xF8, 0xB8, 0xE8),
]
const LEVEL_OUTLINE := Color8(0x27, 0x04, 0x00)

## Textures de remplissage recolorées, fabriquées une fois chacune au premier
## usage : quatre niveaux, quatre teintes, et rien à refaire ensuite. La clé −1
## est l'aperçu blanc.
static var _tinted: Dictionary = {}

## APERÇU DU GAIN, même grammaire que la jauge de PV : ce qui vient d'être gagné
## s'allume d'abord en blanc, puis la couleur du niveau le recouvre. Là-bas
## l'aperçu montre ce qu'on va PERDRE, ici ce qu'on vient de gagner — dans les
## deux cas c'est la part de jauge en jeu qui se signale avant de se résoudre.
const PREVIEW_LEVEL := -1
const PREVIEW_COLOR := Color(1, 1, 1)
## Temps d'affichage du blanc avant que la couleur ne parte, puis durée de sa
## montée. Repris de HpBar : c'est la même animation, elle doit avoir le même
## tempo d'un élément à l'autre.
const PREVIEW_HOLD := 0.18
const FILL_DURATION := 0.35

var _progress: TextureProgressBar
var _preview: TextureProgressBar
var _tween: Tween
## Remplissage AFFICHÉ, qui rattrape la charge réelle pendant l'animation.
var _shown: float = 0.0
var _level_node: Control
var _level: int = 0

func _ready() -> void:
	# Piste, remplissage et icône sont des SVG déjà à la résolution de l'écran
	# (cf. PixelScale.sprite_native) : rien à agrandir au runtime.
	add_child(PixelScale.sprite_native(UNDERLAYER))

	# L'aperçu est monté AVANT le remplissage coloré, donc dessous : la couleur
	# le recouvre en montant, elle ne passe pas derrière.
	_preview = _make_ring(_fill_texture(PREVIEW_LEVEL))
	add_child(_preview)

	_progress = _make_ring(_fill_texture(0))
	# Sens HORAIRE en partant de la bouche de la spirale (cf. BAND_START_DEG) :
	# c'est ce qui fait grandir un arc unique et continu, comme une vraie jauge
	# circulaire. En anti-horaire, le remplissage démarrait du mauvais côté et
	# laissait un secteur vide au milieu de la zone déjà remplie.
	add_child(_progress)

	_refresh_fill()

	var plate := PixelScale.sprite_native(LEVEL_PLATE)
	plate.position = LEVEL_PLATE_POS
	add_child(plate)

	var icon := PixelScale.sprite_native(ICON)
	# Centrage en unités de DESIGN : passer par design_size() pour les deux
	# textures plutôt que get_width()/get_height() directement, qui renvoient
	# désormais leur taille rastérisée ×4 — le rapport entre les deux resterait
	# juste (les deux sont ×4), mais le RÉSULTAT de la différence serait alors
	# lui aussi ×4 trop grand pour une position en unités de design.
	var underlayer_size := PixelScale.design_size(UNDERLAYER)
	var icon_size := PixelScale.design_size(ICON)
	icon.position = Vector2(
		int((underlayer_size.x - icon_size.x) / 2.0),
		int((underlayer_size.y - icon_size.y) / 2.0),
	)
	add_child(icon)

## Pose la charge SANS animation. Sert au montage et aux réglages directs ;
## c'est `gain_to()` qui anime un gain.
func set_charge(level: int, ratio: float) -> void:
	_stop()
	_level = clampi(level, 0, MAX_LEVEL)
	_shown = clampf(ratio, 0.0, 1.0)
	_preview.value = _to_value(_shown)
	_refresh_fill()
	_refresh_level()

## Anime un GAIN jusqu'à (`level`, `ratio`). L'aperçu blanc saute tout de suite
## à la cible, la couleur le rattrape.
##
## Un gain qui fait MONTER D'UN NIVEAU se joue en deux temps : la spirale finit
## de se remplir dans la couleur du niveau qu'elle quitte, puis repart de zéro
## dans celle du nouveau. C'est le seul découpage qui rende la couleur lisible —
## la faire changer en cours de montée effacerait l'information.
func gain_to(level: int, ratio: float) -> void:
	var target_level := clampi(level, 0, MAX_LEVEL)
	var target_ratio := clampf(ratio, 0.0, 1.0)
	if target_level == _level and is_equal_approx(target_ratio, _shown):
		return
	_stop()

	# L'aperçu saute TOUT DE SUITE, avant l'attente : c'est lui qu'on doit voir
	# pendant PREVIEW_HOLD. Le poser dans le premier pas de la file le retardait
	# d'autant, et le blanc n'apparaissait jamais seul.
	_preview.value = _to_value(1.0 if target_level > _level else target_ratio)

	_tween = create_tween()
	_tween.tween_interval(PREVIEW_HOLD)
	# `depart` suit la valeur d'un pas à l'autre. On ne peut pas lire `_shown`
	# au moment où le pas s'exécute : tween_method fige ses bornes à la
	# CONSTRUCTION, et la dernière montée repartait donc de l'ancienne charge
	# au lieu de zéro — elle redescendait au lieu de monter.
	var depart := _shown
	for step in range(_level, target_level):
		_queue_fill(step, depart, 1.0)
		_queue_level(step + 1, target_ratio if step + 1 == target_level else 1.0)
		depart = 0.0
	_queue_fill(target_level, depart, target_ratio)

## Ajoute une montée de `from` à `to` dans la couleur de `level`.
func _queue_fill(level: int, from: float, to: float) -> void:
	_tween.tween_callback(func() -> void:
		_level = level
		_refresh_fill()
		_refresh_level())
	_tween.tween_method(func(value: float) -> void:
		_shown = value
		_progress.value = _to_value(value),
		from, to, FILL_DURATION)

## Passage de niveau : la spirale repart de zéro dans la nouvelle couleur, et
## l'aperçu se recale sur la cible du niveau qui commence.
func _queue_level(level: int, preview: float) -> void:
	_tween.tween_callback(func() -> void:
		_level = level
		_shown = 0.0
		_progress.value = 0.0
		_preview.value = _to_value(preview)
		_refresh_fill()
		_refresh_level())

func _stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

## `value` couvre 360° chez TextureProgressBar ; on le ramène à la portion
## réellement occupée par la spirale.
func _to_value(ratio: float) -> float:
	return clampf(ratio, 0.0, 1.0) * BAND_SWEEP_DEG / 360.0

func _refresh_fill() -> void:
	_progress.texture_progress = _fill_texture(_level)
	_progress.value = _to_value(_shown)

## Anneau de progression radial, commun à l'aperçu et au remplissage.
func _make_ring(texture: Texture2D) -> TextureProgressBar:
	var ring := TextureProgressBar.new()
	ring.texture_progress = texture
	# Sens HORAIRE en partant de la bouche de la spirale (cf. BAND_START_DEG) :
	# c'est ce qui fait grandir un arc unique et continu, comme une vraie jauge
	# circulaire. En anti-horaire, le remplissage démarrait du mauvais côté et
	# laissait un secteur vide au milieu de la zone déjà remplie.
	ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	ring.radial_initial_angle = BAND_START_DEG
	ring.min_value = 0.0
	ring.max_value = 1.0
	ring.step = 0.0
	ring.value = 0.0
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# L'anneau plein (28×28) est encastré de 1 px dans sa piste (30×31).
	ring.position = Vector2(1, 1)
	# `size` se mesure dans la texture, donc dans l'espace agrandi ; `position`
	# reste en unités de design (cf. PixelScale). `design_size() * SCALE`
	# plutôt que `FULL.get_width() * SCALE` : FULL est un SVG déjà rastérisé ×4,
	# son get_width() EST déjà cette valeur — la multiplier une seconde fois
	# quadruplerait la taille de l'anneau.
	ring.size = PixelScale.design_size(FULL) * PixelScale.SCALE
	PixelScale.apply(ring)
	return ring

func _refresh_level() -> void:
	if _level_node != null:
		_level_node.queue_free()
	_level_node = BattleText.make_styled_number(
		str(_level), LEVEL_SIZE,
		LEVEL_GRADIENT_FROM, LEVEL_GRADIENT_TO, LEVEL_INLINE[_level], LEVEL_OUTLINE,
	)
	_level_node.position = LEVEL_POS
	add_child(_level_node)

func get_level() -> int:
	return _level

## Spirale recolorée pour `level`. Chaque pixel garde son ALPHA — donc tout
## l'anticrénelage de l'asset — et ne change que de teinte, reportée sur le
## dégradé du niveau d'après sa position dans celui d'origine.
static func _fill_texture(level: int) -> Texture2D:
	if _tinted.has(level):
		return _tinted[level]
	var from := PREVIEW_COLOR
	var to := PREVIEW_COLOR
	if level != PREVIEW_LEVEL:
		var i := clampi(level, 0, LEVEL_FILL_FROM.size() - 1)
		from = LEVEL_FILL_FROM[i]
		to = LEVEL_FILL_TO[i]
	var image := FULL.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var span := float(FILL_GREEN_TO - FILL_GREEN_FROM)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var t := clampf((pixel.g * 255.0 - FILL_GREEN_FROM) / span, 0.0, 1.0)
			var tinted := from.lerp(to, t)
			tinted.a = pixel.a
			image.set_pixel(x, y, tinted)
	var texture := ImageTexture.create_from_image(image)
	_tinted[level] = texture
	return texture
