extends Node2D

## Nombre qui jaillit au-dessus d'une unité au moment où le coup porte, puis
## monte et s'efface.
##
## AUCUNE MAQUETTE ne montre ces nombres : c'est le seul élément de l'écran de
## combat qui n'est pas relevé. Plutôt que d'inventer un style, on réutilise
## celui qui existe déjà dans le jeu — le chiffre de niveau de la jauge de
## synergie (cf. BattleText.make_styled_number) : contour sombre, liseré clair,
## corps en dégradé vertical. Seule la palette change selon ce qui est annoncé,
## et elle est prise dans les couleurs déjà en service ailleurs à l'écran, pour
## que le nombre se lise sans légende :
##
##   - dégâts DIRECTS : le brun/orangé de l'interface, comme la jauge de
##     synergie ;
##   - dégâts de BLESSURE : les deux bleus de la zone rayée de la jauge de PV ;
##   - SOIN : le vert du libellé « HP ».
##
## Ce fichier est donc le premier candidat à retoucher le jour où l'auteur
## fournit une maquette de dégâts.

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")

const SIZE := 18

## Palettes, dans l'ordre attendu par make_styled_number : dégradé (haut, bas),
## liseré, contour.
const OUTLINE := Color8(0x27, 0x04, 0x00)
const DIRECT_GRADIENT_FROM := Color8(0x42, 0x07, 0x01)
const DIRECT_GRADIENT_TO := Color8(0xFF, 0xD8, 0x00)
const DIRECT_INLINE := Color8(0xEE, 0xF8, 0x01)
const INJURY_GRADIENT_FROM := Color8(0x15, 0x3F, 0xE4)
const INJURY_GRADIENT_TO := Color8(0x9E, 0xD8, 0xFF)
const INJURY_INLINE := Color8(0x00, 0x7B, 0xFF)
const HEAL_GRADIENT_FROM := Color8(0x0B, 0x5E, 0x00)
const HEAL_GRADIENT_TO := Color8(0xC8, 0xFF, 0x8C)
const HEAL_INLINE := Color8(0x4A, 0xFF, 0x01)

## Course verticale et durée du jaillissement, en unités de design et en
## secondes. Assez court pour ne pas retarder l'enchaînement des actions
## (cf. BattleAssault, qui n'attend pas la fin du nombre), assez long pour
## rester lisible pendant que la jauge de la cible se vide.
const RISE := 14.0
const DURATION := 0.7
## Fraction de la durée passée à pleine opacité avant que le fondu commence.
const HOLD := 0.45

enum Kind { DIRECT, INJURY, HEAL }

func show_amount(amount: int, kind: Kind) -> void:
	var text := str(amount)
	var palette := _palette(kind)
	var number: Control = BattleText.make_styled_number(
		text, SIZE, palette[0], palette[1], palette[2], OUTLINE
	)
	# make_styled_number rend une boîte large, alignée à gauche : on la recentre
	# sur l'ancre en mesurant le texte plutôt qu'en attendant une passe de rendu
	# (cf. BattleText.text_width).
	number.position = Vector2(-roundf(BattleText.text_width(text, SIZE) / 2.0), 0)
	add_child(number)

	# Un seul tween pour les deux effets : la montée court sur toute la durée,
	# le fondu ne démarre qu'après HOLD — sans quoi le nombre serait déjà pâle
	# à l'instant où l'œil le cherche.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE, DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, DURATION * (1.0 - HOLD)) \
		.set_delay(DURATION * HOLD)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)

func _palette(kind: Kind) -> Array[Color]:
	match kind:
		Kind.INJURY:
			return [INJURY_GRADIENT_FROM, INJURY_GRADIENT_TO, INJURY_INLINE]
		Kind.HEAL:
			return [HEAL_GRADIENT_FROM, HEAL_GRADIENT_TO, HEAL_INLINE]
	return [DIRECT_GRADIENT_FROM, DIRECT_GRADIENT_TO, DIRECT_INLINE]
