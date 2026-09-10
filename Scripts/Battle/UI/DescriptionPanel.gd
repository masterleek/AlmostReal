extends Node2D

## Cadre « INFO » : description de l'Eko ou de l'objet survolé dans une liste.
##
## Le fond est `bkg_description.svg` : un rectangle sombre à coins arrondis et
## bord flou, dessiné en 60×60 mais destiné à être étiré — d'où le 9-slice, qui
## préserve les quatre coins et n'étire que le centre uni. Le même asset sert
## deux fois : une fois pour le cadre, une fois en petit pour l'onglet du
## titre.
##
## Géométrie relevée sur la deuxième vignette de
## mockup_preparation_select_eko.jpg. Le contour du cadre a été isolé en
## comparant cette vignette à la suivante, qui montre le même décor SANS le
## cadre : la différence donne son emprise exacte, ce qu'aucun seuil ne
## donnerait sur un fond aussi contrasté.

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

const BACKGROUND := preload("res://UI/Battle/bkg_description.svg")

## Le bord flou occupe 5 px sur chaque côté de l'asset et le rayon des coins
## vaut 15 : 20 px de marge préservent les deux, et il reste 20 px de centre
## uni à étirer.
const PATCH_MARGIN := 20

## Emprise du cadre, bord flou compris — le rectangle plein qu'on voit est
## donc encastré de 5 px.
const SIZE := Vector2(203, 71)

## Onglet du titre, en haut à gauche du cadre.
const TAB_OFFSET := Vector2(15, 9)
const TAB_SIZE := Vector2(28, 15)
const TITLE_OFFSET := Vector2(17, 12)
const TITLE_SIZE := 10
const TITLE_COLOR := Color8(0xE3, 0x93, 0x5B)

const TEXT_OFFSET := Vector2(21, 23)
const TEXT_SIZE := 12
const TEXT_COLOR := Color(1, 1, 1)
## Interligne relevé sur la maquette : 12 px entre deux débuts de ligne.
const LINE_HEIGHT := 12

var _label: RichTextLabel

func _ready() -> void:
	add_child(_frame(SIZE, Vector2.ZERO))
	add_child(_frame(TAB_SIZE, TAB_OFFSET))

	var title: RichTextLabel = BattleText.make(
		Localization.get_text("battle.info.title"), TITLE_SIZE, TITLE_COLOR
	)
	title.position = TITLE_OFFSET
	add_child(title)

	_label = BattleText.make_wrapped(
		"", SIZE.x - TEXT_OFFSET.x - 12.0, TEXT_SIZE, TEXT_COLOR
	)
	# L'interligne naturel de la police dépasse celui de la maquette : on le
	# ramène par la constante de thème plutôt qu'en réduisant le corps, qui est
	# mesuré lui aussi.
	_label.add_theme_constant_override(
		"line_separation",
		BattleText.to_supersampled(LINE_HEIGHT - TEXT_SIZE),
	)
	_label.position = TEXT_OFFSET
	add_child(_label)

## Un 9-slice du fond, aux dimensions voulues. Marges et taille se mesurent
## dans la texture, donc dans l'espace agrandi ; la position, elle, reste en
## unités de design (cf. PixelScale).
func _frame(size: Vector2, offset: Vector2) -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.texture = BACKGROUND
	for side in ["left", "right", "top", "bottom"]:
		frame.set("patch_margin_" + side, PATCH_MARGIN * PixelScale.SCALE)
	frame.size = size * PixelScale.SCALE
	frame.position = offset
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelScale.apply(frame)
	return frame

## `text_id` vide masque le cadre entier : une entrée sans description ne doit
## pas laisser un cadre vide à l'écran.
func show_text(text_id: String) -> void:
	visible = text_id != ""
	if visible:
		_label.text = Localization.get_text(text_id)
