extends RefCounted

## Fabrique de libellés pour l'UI de combat.
##
## Elle existe pour une seule raison : RichTextLabel a quatre défauts par
## défaut qui cassent silencieusement un rendu pixel-art (cf. CLAUDE.md), et
## on ne veut pas les réparer à la main sur chaque nœud créé.
##   - autowrap_mode n'est pas désactivé par défaut (contrairement à Label) ;
##   - clip_contents vaut true par défaut : rogne outline et ombre ;
##   - [b] utilise bold_font_size, pas normal_font_size ;
##   - sans bold_font explicite, [b] retombe sur la police par défaut du
##     moteur, pas sur la nôtre.
## Tout passe par ici pour que ces quatre réglages soient posés au même
## endroit, une fois.
##
## On utilise RichTextLabel et non Label bien que les libellés de combat soient
## du texte simple : les traductions sont stockées en BBCode brut par le
## catalogue Localization (page « Textes » de MapEditor), donc n'importe quel
## libellé peut recevoir une mise en couleur ou un passage en gras posé depuis
## l'éditeur web, sans retoucher le code.

const FONT_PATH := "res://Fonts/BoldPixels1.4.ttf"

# Largeur de boîte volontairement généreuse : le texte est aligné à gauche et
# autowrap est désactivé, la boîte ne sert donc qu'à ne pas contraindre le
# rendu. La dimensionner au plus juste demanderait de mesurer chaque
# traduction, pour aucun gain visuel.
const BOX_WIDTH := 220.0

## Suréchantillonnage du texte, égal à l'échelle du Stage.
##
## Le décor de combat est de la pixel-art 480×270 agrandie ×4, et c'est voulu :
## un bloc de 4×4 par pixel d'origine. Le TEXTE, lui, n'a aucune raison de
## subir ça — rasterisé à sa taille de design puis étiré ×4, il sort en gros
## escaliers alors que la police est vectorielle et pourrait être nette.
##
## On rasterise donc les glyphes SUPERSAMPLE fois plus grands et on
## contre-échelle le nœud d'autant. L'échelle cumulée (4 × ¼) vaut 1 : la
## police est rendue à la résolution réelle de l'écran, tout en gardant une
## géométrie identique et des coordonnées exprimées en unités de design.
## Les tailles et positions calibrées sur la maquette restent donc valables :
## le décalage boîte → glyphe est une métrique de police, il suit la taille
## proportionnellement.
const SUPERSAMPLE := 4

# ══════════════════════════════════════════════════════════════════════════
#  STYLE DES TEXTES DE COMBAT — les quatre valeurs à régler sont ici
# ══════════════════════════════════════════════════════════════════════════
#
# Tout est exprimé en PIXELS DE DESIGN (l'écran de combat en fait 480×270).
# Les décimales sont permises et utiles : le texte étant suréchantillonné
# (cf. SUPERSAMPLE), 0.75 donne un contour réellement plus fin qu'un pixel —
# ce qu'un rendu pixel-art classique ne permettrait pas.
#
# Point de départ : le compteur de hex du worldmap (`HUD/HexCounter/Count`
# dans Scenes/Main.tscn), soit un contour fin qui épouse le glyphe plus une
# ombre portée de la même couleur vers le bas-droite. Dans cette scène-là le
# contour vaut 4 pour un corps 64 ; ramené aux corps du combat (12 à 18), ça
# tombe autour de 0,75 px de design.

## Épaisseur du contour. 0 = aucun contour.
const UI_OUTLINE_SIZE := 3.0
const UI_OUTLINE_COLOR := Color("#270400")

## Décalage de l'ombre portée. Vector2.ZERO = aucune ombre.
## Attention : une ombre de décalage nul reste dessinée, pile derrière le
## glyphe — c'est la transparence, pas le décalage, qui la supprime (cf.
## _apply_stroke).
const UI_SHADOW_OFFSET := Vector2(1.0, 1.0)
const UI_SHADOW_COLOR := Color("#270400")

# ══════════════════════════════════════════════════════════════════════════

static var _bold_font: FontVariation

## Police grasse dérivée de l'unique police du projet. Sans elle, le BBCode
## [b] afficherait la police par défaut du moteur au lieu de la nôtre — un
## défaut bien plus visible qu'un simple « pas d'effet gras ».
static func bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = load(FONT_PATH)
		_bold_font.variation_embolden = 1.0
	return _bold_font

## `font_size` est exprimé en unités de design (480×270) : le nœud est destiné
## à vivre sous le Stage agrandi ×4.
##
## Sans `outline_size`, le libellé reçoit le contour ET l'ombre standard de
## l'UI (cf. UI_OUTLINE_*), ce qui est le cas de tous les textes du combat.
## Le passer explicitement sert aux chiffres « chromés » de
## make_styled_number(), qui empilent leurs propres contours.
static func make(
	bbcode: String,
	font_size: int,
	color: Color,
	outline_size: int = -1,
	outline_color: Color = UI_OUTLINE_COLOR,
	shadow: bool = true,
) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_contents = false
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Tout l'intérieur du nœud vit en unités suréchantillonnées ; seule sa
	# transformation le ramène aux unités de design (cf. SUPERSAMPLE).
	label.scale = Vector2.ONE / float(SUPERSAMPLE)
	label.size = Vector2(BOX_WIDTH, font_size) * SUPERSAMPLE

	var font: Font = load(FONT_PATH)
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_override("bold_font", bold_font())
	label.add_theme_font_size_override("normal_font_size", font_size * SUPERSAMPLE)
	label.add_theme_font_size_override("bold_font_size", font_size * SUPERSAMPLE)
	label.add_theme_color_override("default_color", color)

	# `outline_size` est converti dans l'espace suréchantillonné du nœud. Ce
	# n'est PAS une épaisseur en pixels de design pour autant : Godot rend un
	# contour environ quatre fois plus fin que le `outline_size` qu'il reçoit.
	# Mesuré en jeu sur un chiffre de dégâts : 2 donne 0,5 px de design, 8 en
	# donne 2,0. C'est ce rapport qui explique l'UI_OUTLINE_SIZE de 3,0
	# ci-dessus et les 0,75 px que son commentaire annonce.
	if outline_size < 0:
		set_outlined(label, font_size, true)
	else:
		_apply_stroke(
			label, outline_size * SUPERSAMPLE, outline_color,
			to_supersampled_offset(UI_SHADOW_OFFSET) if shadow else Vector2i.ZERO,
			UI_SHADOW_COLOR,
		)

	label.text = bbcode
	return label

## Libellé CENTRÉ dans une boîte de `design_width` pixels de design, à poser
## par son coin haut-gauche comme les autres.
##
## Sert à caler un texte sur un point (le nom d'une cible au-dessus de sa
## tête, par exemple) sans avoir à mesurer sa largeur rendue : celle-ci n'est
## connue qu'après une passe de rendu, alors que la boîte, elle, est fixée
## d'avance. On resserre donc la boîte à la largeur voulue et on laisse le
## moteur centrer le texte dedans.
static func make_centered(
	bbcode: String, design_width: float, font_size: int, color: Color
) -> RichTextLabel:
	var label := make("", font_size, color)
	label.size.x = design_width * SUPERSAMPLE
	set_centered_text(label, bbcode)
	return label

## Change le contenu d'un libellé construit par `make_centered`. Passe par ici
## plutôt que par `label.text` : le centrage est porté par une balise BBCode,
## qu'une écriture directe effacerait.
static func set_centered_text(label: RichTextLabel, bbcode: String) -> void:
	label.text = "[center]%s[/center]" % bbcode

## Libellé qui REVIENT À LA LIGNE dans une boîte de `design_width` pixels de
## design. C'est l'exception au réglage par défaut de `make()` : le panneau de
## description affiche une phrase, pas une étiquette, et sa largeur est fixée
## par le cadre qui l'entoure.
static func make_wrapped(
	bbcode: String, design_width: float, font_size: int, color: Color
) -> RichTextLabel:
	var label := make(bbcode, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size.x = design_width * SUPERSAMPLE
	return label

## Largeur qu'occupera `text` en pixels de design, connue AVANT tout rendu.
##
## Sert aux mises en page alignées à droite — la légende de combat cale le bord
## droit du libellé « Cancel »/« Back » sur un point fixe, ce qui demande sa
## largeur au moment où on pose l'icône. La mesurer sur la police évite d'avoir
## à attendre une passe de rendu pour lire `get_content_width()`.
##
## Le BBCode n'est pas interprété ici : passer une chaîne balisée compterait
## les balises comme des caractères.
static func text_width(text: String, font_size: int) -> float:
	var font: Font = load(FONT_PATH)
	return font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size * SUPERSAMPLE
	).x / float(SUPERSAMPLE)

## Convertit une valeur en pixels de design vers l'espace suréchantillonné du
## libellé, où sont exprimés les items de thème de Godot.
static func to_supersampled(design_pixels: float) -> int:
	return int(round(design_pixels * SUPERSAMPLE))

## Pose ou retire le contour ET l'ombre standard sur un libellé déjà construit.
##
## Sert aux libellés dont le style change à l'exécution : l'entrée de menu
## sélectionnée, par exemple, passe en texte sombre sur pastille jaune et se
## passe alors de contour — celui-ci n'aurait plus rien à détacher et
## empâterait les glyphes (cf. la maquette, où ce texte-là est parfaitement
## net).
static func set_outlined(label: RichTextLabel, font_size: int, outlined: bool) -> void:
	if outlined:
		_apply_stroke(
			label, to_supersampled(UI_OUTLINE_SIZE), UI_OUTLINE_COLOR,
			to_supersampled_offset(UI_SHADOW_OFFSET), UI_SHADOW_COLOR,
		)
	else:
		_apply_stroke(label, 0, UI_OUTLINE_COLOR, Vector2i.ZERO, UI_SHADOW_COLOR)

static func to_supersampled_offset(design_pixels: Vector2) -> Vector2i:
	return Vector2i(to_supersampled(design_pixels.x), to_supersampled(design_pixels.y))

static func _apply_stroke(
	label: RichTextLabel, outline: int, outline_color: Color,
	shadow_offset: Vector2i, shadow_color: Color,
) -> void:
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("shadow_offset_x", shadow_offset.x)
	label.add_theme_constant_override("shadow_offset_y", shadow_offset.y)
	# Une ombre de décalage nul reste dessinée, pile derrière le glyphe : c'est
	# la transparence, pas le décalage, qui la supprime vraiment.
	label.add_theme_color_override(
		"font_shadow_color",
		shadow_color if shadow_offset != Vector2i.ZERO else Color(0, 0, 0, 0),
	)

## Chiffre « chromé » du jeu : corps en dégradé vertical, liseré intérieur
## clair, contour sombre (cf. le niveau de la jauge de synergie).
##
## Godot ne sait remplir un texte ni avec un dégradé ni avec un liseré
## INTÉRIEUR. On empile donc trois copies du même texte, de la plus large à la
## plus étroite, et ce sont leurs contours de tailles décroissantes qui
## dessinent les anneaux :
##   1. contour sombre le plus épais → le liseré extérieur ;
##   2. contour clair plus fin → le liseré intérieur, qui dépasse du corps ;
##   3. le corps, dont la silhouette découpe un rectangle en dégradé
##      (`clip_children`, même procédé que le balayage des pastilles de menu).
static func make_styled_number(
	text: String,
	font_size: int,
	gradient_from: Color,
	gradient_to: Color,
	inline_color: Color,
	outline_color: Color,
) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(BOX_WIDTH, font_size)

	# Épaisseurs proportionnelles au corps : à 12 px le contour sombre fait
	# 2 px et le liseré clair 1, ce qui donne les deux anneaux du mockup sans
	# les épaissir quand le chiffre grandit.
	var outer := maxi(2, font_size / 6)
	root.add_child(make(text, font_size, outline_color, outer, outline_color, false))
	root.add_child(make(text, font_size, inline_color, maxi(1, outer - 1), inline_color, false))

	var body := make(text, font_size, Color(1, 1, 1), 0, outline_color, false)
	body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	body.add_child(_vertical_gradient(gradient_from, gradient_to, font_size))
	root.add_child(body)
	return root

## Rectangle en dégradé vertical calé sur la hauteur de capitale de la police
## (exactement la moitié du corps sur BoldPixels) : c'est la zone réellement
## occupée par un chiffre, donc celle sur laquelle le dégradé doit se déployer
## en entier.
static func _vertical_gradient(from: Color, to: Color, font_size: int) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1
	texture.height = maxi(2, font_size / 2)
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)

	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ce rectangle est enfant d'un libellé, donc exprimé dans l'espace
	# suréchantillonné de celui-ci (cf. SUPERSAMPLE) — d'où le facteur, absent
	# des autres coordonnées du projet qui sont toutes en unités de design.
	rect.position = Vector2(0, font_size / 4.0) * SUPERSAMPLE
	rect.size = Vector2(BOX_WIDTH, font_size / 2.0) * SUPERSAMPLE
	return rect
