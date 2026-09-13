extends Node2D

## Bloc d'état d'un allié en haut de l'écran : portrait, PV (libellé, nombre,
## jauge) et points d'action.
##
## Un seul script pour les deux alliés — les blocs ne diffèrent que par leurs
## données et leur position, pas par leur structure. Toutes les coordonnées
## ci-dessous sont locales au bloc et en unités de design (480×270).
##
## ⚠ Ce bloc est le seul de l'écran qui ne peut pas être reproduit au pixel
## près : les vignettes livrées (battle_face_*.png) ne sont pas celles du
## mockup — même illustration, cadrage différent (cf. docs/plan_systeme_combat.md
## §7). La composition suit le mockup, les pixels ne peuvent pas y coller.

const HpBar = preload("res://Scripts/Battle/UI/HpBar.gd")
const ApDots = preload("res://Scripts/Battle/UI/ApDots.gd")
const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const BattleData = preload("res://Scripts/Battle/BattleData.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

const HIGHLIGHT := preload("res://UI/Battle/battle_face_highlight.svg")
## Coche verte de l'allié dont l'action est déjà retenue.
const CHECK := preload("res://UI/Battle/ic_checkmark.svg")

## Tailles relevées sur le mockup : les libellés « HP »/« AP » ont une hauteur
## de capitale de 6 px et le compteur de PV de 9 px. Avec BoldPixels, dont la
## capitale vaut exactement la moitié du corps, ça donne 12 et 18.
const LABEL_SIZE := 12
const NUMBER_SIZE := 18

## Positions locales, origine du bloc en haut à gauche. Les valeurs des
## libellés visent la BOÎTE du RichTextLabel, pas le premier glyphe : le texte
## est décalé d'environ un quart du corps vers le bas dans sa boîte (mesuré :
## +2 px à 12, +3 px à 15, +4 px à 18).
const HP_LABEL_POS := Vector2(2, -2)
const HP_NUMBER_POS := Vector2(28, -6)
const HP_BAR_POS := Vector2(2, 8)
const PORTRAIT_POS := Vector2(1, 14)
const AP_LABEL_POS := Vector2(4, 34)
const AP_DOTS_POS := Vector2(16, 34)
## Coche posée dans le haut de la vignette, relevée par corrélation de l'asset
## sur la quatrième vignette de mockup_preparation_select_items.png : origine
## écran (327, 32), soit (22, 13) une fois ramenée dans le repère du bloc, que
## l'inclinaison de −4,2° fait tourner autour de son coin.
const CHECK_POS := Vector2(22, 13)

## Teinte du PORTRAIT de l'allié dont l'action est retenue : il s'efface
## derrière ceux qui choisissent encore. Ajustée sur la maquette (moindres
## carrés sur 749 pixels de portrait).
##
## Elle garde son alpha : le portrait est posé sur le fond de la vignette, et
## c'est bien un voile que la maquette montre. Le SPRITE sur le terrain, lui,
## est traité autrement — un assombrissement OPAQUE, cf.
## BattleScene.CONFIRMED_SPRITE_MODULATE.
const CONFIRMED_PORTRAIT_MODULATE := Color(0.45, 0.15, 0.22, 0.45)

const HP_LABEL_COLOR := Color8(0x4A, 0xFF, 0x01)
const AP_LABEL_COLOR := Color8(0xEE, 0xFF, 0x00)
## Zéros non significatifs du compteur de PV : atténués, pour que l'œil lise
## la valeur réelle et pas le gabarit à 3 chiffres.
const HP_PADDING_COLOR := Color8(0x95, 0x73, 0x60)
## Le compteur de PV passe au bleu tant que l'unité porte des dégâts de
## BLESSURE — des PV encore acquis mais mis en jeu (cf. BattleUnit) — de la
## même famille de bleus que le segment rayé de sa jauge.
##
## Le Lot 1 l'avait rattaché à l'allié ACTIF, d'après une maquette où les deux
## coïncidaient. Les maquettes de la boucle de tour les séparent : Noah garde
## son compteur bleu après avoir joué, alors que le cadre jaune est passé à
## Iris — c'est bien la blessure, pas le tour, que la couleur signale.
const HP_NUMBER_COLOR := Color(1, 1, 1, 1)
const HP_NUMBER_INJURED_COLOR := Color8(0x42, 0x9E, 0xFF)

var _highlight: Sprite2D
var _check: Sprite2D
var _portrait: Sprite2D
var _hp_number: RichTextLabel
var _hp_bar: Node2D
var _ap_dots: Node2D

func setup(unit_id: String) -> void:
	var unit: Dictionary = BattleData.get_unit(unit_id)

	# Le cadre de sélection est posé AVANT le portrait (donc dessous) et
	# déborde de 1 px sur chaque bord — il encadre la vignette, il ne la
	# recouvre pas.
	_highlight = PixelScale.sprite_native(HIGHLIGHT)
	_highlight.position = PORTRAIT_POS - Vector2.ONE
	_highlight.visible = false
	add_child(_highlight)

	var portrait_path: String = unit.get("portrait", "")
	if portrait_path != "":
		# PNG + bilinéaire, PAS de SVG : `battle_face_iris.svg`/`_noah.svg`
		# encapsulent en fait un raster (photo/illustration) via une balise
		# <image> — Godot ne la rastérise pas (ThorVG). Vérifié par un dump
		# direct de la texture importée : un simple aplat de couleur, sans le
		# portrait, là où QuickLook (WebKit, conforme au spec) affiche
		# correctement la photo. `smooth = true` corrige au passage un vrai
		# défaut préexistant : ce portrait est une illustration anticrénelée,
		# pas du pixel-art, et n'avait jamais explicitement demandé le
		# bilinéaire (défaut = plus proche voisin, cf. PixelScale.sprite()).
		_portrait = PixelScale.sprite(load(portrait_path), Vector2.ZERO, true)
		_portrait.position = PORTRAIT_POS
		add_child(_portrait)

	# Par-dessus le portrait, qu'elle remplace visuellement une fois l'action
	# retenue — le portrait n'est pas masqué mais assombri, on l'aperçoit
	# derrière (cf. la maquette).
	_check = PixelScale.sprite_native(CHECK)
	_check.position = CHECK_POS
	_check.visible = false
	add_child(_check)

	var hp_label: RichTextLabel = BattleText.make("HP", LABEL_SIZE, HP_LABEL_COLOR)
	hp_label.position = HP_LABEL_POS
	add_child(hp_label)

	_hp_number = BattleText.make("", NUMBER_SIZE, HP_NUMBER_COLOR)
	_hp_number.position = HP_NUMBER_POS
	add_child(_hp_number)

	_hp_bar = HpBar.new() as Node2D
	_hp_bar.position = HP_BAR_POS
	add_child(_hp_bar)

	var ap_label: RichTextLabel = BattleText.make("AP", LABEL_SIZE, AP_LABEL_COLOR)
	ap_label.position = AP_LABEL_POS
	add_child(ap_label)

	_ap_dots = ApDots.new() as Node2D
	_ap_dots.position = AP_DOTS_POS
	add_child(_ap_dots)

	var stats: Dictionary = unit.get("stats", {})
	set_hp(int(stats.get("hp_max", 1)), int(stats.get("hp_max", 1)))
	set_ap(int(stats.get("ap_max", 0)), int(stats.get("ap_max", 0)))

## `injury` = dégâts de blessure en attente. Le compteur affiche les PV RÉELS
## (la blessure n'a encore rien retiré) ; c'est sa couleur, et le segment rayé
## au bout de la jauge, qui disent qu'une part est en jeu.
func set_hp(current: int, maximum: int, injury: int = 0) -> void:
	_hp_number.text = _format_hp(current)
	var full := maxf(1.0, float(maximum))
	_hp_bar.set_ratio(float(current - injury) / full, float(current) / full)
	set_injured(injury > 0)

func set_ap(current: int, maximum: int) -> void:
	_ap_dots.set_points(current, maximum)

## Marque l'allié dont c'est le tour : cadre jaune autour de son portrait.
func set_active(active: bool) -> void:
	_highlight.visible = active

## Marque l'allié dont l'action est déjà retenue : portrait assombri et coche
## verte par-dessus.
func set_confirmed(confirmed: bool) -> void:
	_check.visible = confirmed
	if _portrait != null:
		_portrait.modulate = CONFIRMED_PORTRAIT_MODULATE if confirmed else Color.WHITE

## Piloté par set_hp() : la couleur suit la blessure, elle ne se règle pas à
## part.
func set_injured(injured: bool) -> void:
	_hp_number.add_theme_color_override(
		"default_color", HP_NUMBER_INJURED_COLOR if injured else HP_NUMBER_COLOR
	)

## Gabarit à 3 chiffres, zéros de tête atténués via BBCode — c'est justement le
## genre de mise en forme que le catalogue Localization sait déjà transporter.
func _format_hp(value: int) -> String:
	var digits: String = "%03d" % clampi(value, 0, 999)
	var significant := 0
	while significant < 2 and digits[significant] == "0":
		significant += 1
	if significant == 0:
		return digits
	return "[color=#%s]%s[/color]%s" % [
		HP_PADDING_COLOR.to_html(false), digits.substr(0, significant), digits.substr(significant)
	]
