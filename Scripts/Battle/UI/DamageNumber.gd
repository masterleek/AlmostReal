extends Node2D

## Nombre qui jaillit au-dessus d'une unité au moment où le coup porte, puis
## monte et s'efface.
##
## RELEVÉ SUR mockup_degats_chiffres.jpg, qui montre les trois cas côte à côte
## à l'échelle 1:1 du design (vérifié sur la jauge de la plaque de ciblage :
## 31 px mesurés pour 32 déclarés). Le style y est PLAT — ni dégradé, ni liseré
## clair, contrairement au chiffre de niveau de la jauge de synergie dont ces
## nombres reprenaient le traitement faute de maquette : un aplat de couleur,
## posé dans un contour sombre épais.
##
## Ce que dit la maquette, mesuré :
##
##   - le chiffre fait 9 px de haut — soit exactement la hauteur de capitale de
##     BoldPixels à SIZE 18 (la moitié du corps), qui ne change donc pas ;
##   - le corps est UNI sur toute sa hauteur (relevé colonne par colonne :
##     255,85,88 de la première à la dernière ligne du « 5 » rouge) ;
##   - le contour fait 2 px et vaut le même bleu nuit pour les trois couleurs
##     (médianes #081741, #0E1641, #0D1840 relevées autour des trois chiffres —
##     il ne suit donc pas la teinte du chiffre).

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")

const SIZE := 18

## Couleurs données par l'auteur, et retrouvées au pixel près dans la maquette
## (médianes relevées sur les chiffres : 255,85,88 — 66,158,255 — 129,255,1).
const DIRECT_COLOR := Color("#FF5558")
const INJURY_COLOR := Color("#429EFF")
const HEAL_COLOR := Color("#81FF01")

## Le contour est le MÊME pour les trois : un bleu nuit, et non le brun
## (#270400) que porte le reste de l'interface — c'est ce que montre la
## maquette, et c'est ce qui détache le nombre du décor sans lui emprunter sa
## teinte.
const OUTLINE := Color("#0D1741")

## Épaisseur voulue : 2 px de design, relevés sur la maquette. La valeur passée
## n'est PAS cette épaisseur — `BattleText.make` multiplie déjà son paramètre
## par SUPERSAMPLE, et Godot rend ensuite un contour quatre fois plus fin que le
## `outline_size` qu'il reçoit. Mesuré en jeu : 2 donnait 0,5 px, 8 en donne 2.
## Le même rapport explique le `UI_OUTLINE_SIZE = 3.0` de BattleText, qui rend
## les 0,75 px que son commentaire annonce.
const OUTLINE_SIZE := 8

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
	# Sans ombre portée : la maquette n'en montre aucune, et le contour de 2 px
	# suffit largement à décoller le nombre du décor.
	var number: Control = BattleText.make(text, SIZE, _color(kind), OUTLINE_SIZE, OUTLINE, false)
	# `make` rend une boîte large, alignée à gauche : on la recentre sur l'ancre
	# en mesurant le texte plutôt qu'en attendant une passe de rendu (cf.
	# BattleText.text_width).
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

func _color(kind: Kind) -> Color:
	match kind:
		Kind.INJURY:
			return INJURY_COLOR
		Kind.HEAL:
			return HEAL_COLOR
	return DIRECT_COLOR
