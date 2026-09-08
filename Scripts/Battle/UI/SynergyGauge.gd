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

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

const MAX_LEVEL := 4

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

## Chiffre du niveau, en bas à gauche du disque. Couleurs fournies par
## l'auteur des maquettes ; le corps est un dégradé, le liseré intérieur est
## le jaune de l'UI, le contour le brun sombre commun à toute l'interface.
const LEVEL_POS := Vector2(2, 17)
const LEVEL_SIZE := 12
const LEVEL_GRADIENT_FROM := Color8(0x42, 0x07, 0x01)
const LEVEL_GRADIENT_TO := Color8(0xFF, 0x73, 0x00)
const LEVEL_INLINE := Color8(0xEE, 0xF8, 0x01)
const LEVEL_OUTLINE := Color8(0x27, 0x04, 0x00)

var _progress: TextureProgressBar
var _level_node: Control
var _level: int = 0

func _ready() -> void:
	# Piste, remplissage et icône sont des SVG déjà à la résolution de l'écran
	# (cf. PixelScale.sprite_native) : rien à agrandir au runtime.
	add_child(PixelScale.sprite_native(UNDERLAYER))

	_progress = TextureProgressBar.new()
	_progress.texture_progress = FULL
	# Sens HORAIRE en partant de la bouche de la spirale (cf. BAND_START_DEG) :
	# c'est ce qui fait grandir un arc unique et continu, comme une vraie jauge
	# circulaire. En anti-horaire, le remplissage démarrait du mauvais côté et
	# laissait un secteur vide au milieu de la zone déjà remplie.
	_progress.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_progress.radial_initial_angle = BAND_START_DEG
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.step = 0.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# L'anneau plein (28×28) est encastré de 1 px dans sa piste (30×31).
	_progress.position = Vector2(1, 1)
	# `size` se mesure dans la texture, donc dans l'espace agrandi ; `position`
	# reste en unités de design (cf. PixelScale). `design_size() * SCALE`
	# plutôt que `FULL.get_width() * SCALE` : FULL est un SVG déjà rastérisé
	# ×4, son get_width() EST déjà cette valeur — la multiplier une seconde
	# fois quadruplerait la taille de l'anneau.
	_progress.size = PixelScale.design_size(FULL) * PixelScale.SCALE
	PixelScale.apply(_progress)
	add_child(_progress)

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

## `ratio` = remplissage du niveau en cours, ∈ [0,1].
func set_charge(level: int, ratio: float) -> void:
	_level = clampi(level, 0, MAX_LEVEL)
	# `value` couvre 360° chez TextureProgressBar ; on le ramène à la portion
	# réellement occupée par la spirale.
	_progress.value = clampf(ratio, 0.0, 1.0) * BAND_SWEEP_DEG / 360.0
	_refresh_level()

func _refresh_level() -> void:
	if _level_node != null:
		_level_node.queue_free()
	_level_node = BattleText.make_styled_number(
		str(_level), LEVEL_SIZE,
		LEVEL_GRADIENT_FROM, LEVEL_GRADIENT_TO, LEVEL_INLINE, LEVEL_OUTLINE,
	)
	_level_node.position = LEVEL_POS
	add_child(_level_node)

func get_level() -> int:
	return _level
