extends Node

## Ouverture du combat : chaque élément de l'écran entre à son tour, au lieu que
## tout apparaisse d'un bloc dans son état final.
##
## À t = 0 : bandes noires, plateforme, blocs du HUD (alliés + synergie) et
## menu de commandes démarrent TOUS ENSEMBLE. Seuls les combattants suivent,
## UNITS_DELAY plus tard, le temps que la plateforme les porte. Le joueur ne
## reçoit la main qu'à la toute fin (`finished`) — le plus tardif des trois
## (combattants, HUD, menu), pas simplement la fin du menu — c'est à l'appelant
## de garder le menu inactif jusque-là.
##
## TOUT L'ÉTAT DE DÉPART EST POSÉ PAR `play()`, DE FAÇON SYNCHRONE — alphas à
## zéro, échelles à plat, positions décalées — avant la moindre attente : appelée
## depuis un `_ready`, aucune image ne montre l'écran dans son état final avant
## que l'animation ne le fasse disparaître.
##
## Ce script ne connaît pas BattleScene : il reçoit des nœuds et les anime. Rien
## ne l'attache à CE combat-ci — il ne sait même pas combien il y a d'alliés.

const CommandMenu = preload("res://Scripts/Battle/UI/CommandMenu.gd")

# ──────────────────────────────────────────────────────────────────────────
#  DURÉES — des CHOIX, pas des mesures : aucune maquette ne montre l'ouverture.
#  Seuls les deux délais UNITS_DELAY et HUD_INTERVAL viennent de la demande de
#  l'auteur (0,5 s au départ) ; il a ensuite demandé que TOUT aille deux fois
#  plus vite, d'où les valeurs divisées par deux. Les distances ne changent pas :
#  même trajet, en deux fois moins de temps.
# ──────────────────────────────────────────────────────────────────────────

## Plateforme et combattants : fondu + rotation X de −90° à 0° + échelle de 70 %
## à 100 %, sur la même durée.
const FLIP_DURATION := 0.2
const FLIP_FROM_DEG := -90.0
const FLIP_FROM_SCALE := 0.7
## Écart entre le début de la plateforme et celui des combattants (demandé).
const UNITS_DELAY := 0.25

## Blocs du HUD : fondu + chute RAPIDE, un bloc toutes les HUD_INTERVAL (demandé).
const HUD_FALL := 12.0
const HUD_FALL_DURATION := 0.1
const HUD_INTERVAL := 0.25

## Bandes noires : fondu, celle du haut descend à sa place, celle du bas monte.
const BANDS_SLIDE := 24.0
const BANDS_DURATION := 0.2

## Menu : une rangée toutes les MENU_ROW_INTERVAL, chacune en MENU_ROW_FADE.
const MENU_ROW_INTERVAL := 0.04
const MENU_ROW_FADE := 0.06

## L'ouverture est jouée : le joueur peut prendre la main.
signal finished

var _tween: Tween

## Joue l'ouverture.
##
## - `arena` porte la plateforme ET les combattants, pivot au centre de la
##   plateforme : c'est lui qui pivote en premier, et comme les combattants sont
##   ses enfants ils restent ANCRÉS au sol pendant qu'il se redresse. Il doit
##   être à l'identité au repos — il y revient à la fin.
## - `ground` : ce qui s'efface avec la plateforme (ses deux moitiés). Le fondu
##   ne se pose PAS sur `arena`, qui emporterait les combattants avec lui.
## - `units` : les combattants, pivot à leurs pieds (cf. UnitSprite).
## - `band_top` / `band_bottom` : les bandes noires, à leur position de repos.
## - `hud_blocks` : un tableau par bloc du HUD, dans l'ordre d'arrivée ; les
##   nœuds d'un même bloc tombent ensemble (la jauge de synergie et son libellé,
##   qui sont frères et pas parent/enfant).
## - `menu` et `legend` : le menu racine, et ce qui apparaît avec sa dernière
##   rangée.
func play(
	arena: Node2D, ground: Array[CanvasItem], units: Array[Node2D],
	band_top: CanvasItem, band_bottom: CanvasItem, hud_blocks: Array,
	menu: CommandMenu, legend: CanvasItem,
) -> void:
	_tween = create_tween().set_parallel(true)

	_slide_in(band_top, Vector2(0, -BANDS_SLIDE), BANDS_DURATION, 0.0)
	_slide_in(band_bottom, Vector2(0, BANDS_SLIDE), BANDS_DURATION, 0.0)

	_flip_in(arena, 0.0, ground)
	for unit in units:
		_flip_in(unit, UNITS_DELAY, [unit])

	# HUD et menu démarrent AVEC la plateforme (t=0), pas après les combattants :
	# seuls ces derniers gardent UNITS_DELAY, le temps que la plateforme les
	# porte. `finished` doit donc attendre le plus lent des trois, pas
	# simplement la fin du menu (cf. plus bas).
	for i in hud_blocks.size():
		for node: CanvasItem in hud_blocks[i]:
			_slide_in(node, Vector2(0, -HUD_FALL), HUD_FALL_DURATION, i * HUD_INTERVAL)
	var hud_end := maxi(0, hud_blocks.size() - 1) * HUD_INTERVAL + HUD_FALL_DURATION

	var menu_end: float = menu.reveal(MENU_ROW_INTERVAL, MENU_ROW_FADE, 0.0)
	# Avec la DERNIÈRE rangée : la légende décrit ce menu, elle n'a rien à dire
	# tant qu'il n'est pas là.
	_fade_in(legend, MENU_ROW_FADE, menu_end - MENU_ROW_FADE)

	var units_end := UNITS_DELAY + FLIP_DURATION
	var end_time := maxf(units_end, maxf(hud_end, menu_end))
	_tween.tween_callback(finished.emit).set_delay(end_time)

## Rotation X simulée + échelle, en fonction de l'avancement `t` ∈ [0 ; 1].
##
## Node2D n'a pas d'axe X en profondeur : de profil, une surface plate se réduit
## à un trait — cos(−90°) = 0 — et c'est cette silhouette que l'échelle
## verticale reproduit, sans perspective ni shader. Même principe que la
## rotation Y de la pastille d'action (cf. ActionBanner, sur l'échelle
## horizontale).
static func flip_scale(t: float) -> Vector2:
	var s := lerpf(FLIP_FROM_SCALE, 1.0, t)
	return Vector2(s, s * cos(deg_to_rad(lerpf(FLIP_FROM_DEG, 0.0, t))))

## `fades` bascule EN MÊME TEMPS que l'échelle : `t` est DÉJÀ la valeur adoucie
## par le trans/ease ci-dessous (tween_method interpole l'argument passé au
## callback, pas seulement le temps), donc lier l'alpha à ce même `t` — plutôt
## qu'à un fondu séparé sur sa propre courbe — garantit qu'échelle et
## transparence avancent ENSEMBLE. Sans ça (essayé, constaté) l'échelle, en
## EASE_OUT, atteint sa quasi-taille finale bien avant que le fondu séparé ne
## rende l'objet assez opaque pour qu'on le voie : on ne perçoit alors qu'un
## fondu, jamais la bascule.
func _flip_in(node: Node2D, delay: float, fades: Array[CanvasItem] = []) -> void:
	node.scale = flip_scale(0.0)
	for item in fades:
		item.modulate.a = 0.0
	var step := func(t: float) -> void:
		node.scale = flip_scale(t)
		for item in fades:
			item.modulate.a = t
	_tween.tween_method(step, 0.0, 1.0, FLIP_DURATION) \
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _fade_in(item: CanvasItem, duration: float, delay: float) -> void:
	item.modulate.a = 0.0
	_tween.tween_property(item, "modulate:a", 1.0, duration).set_delay(delay)

## Arrive depuis `from_offset` jusqu'à sa position actuelle, en fondu. La
## position de départ est relevée sur le nœud lui-même : il doit être posé à sa
## place de repos au moment de l'appel.
##
## CanvasItem et pas Node2D : un bloc du HUD peut mêler les deux familles (la
## jauge de synergie est un Node2D, son libellé un RichTextLabel, donc un
## Control). Toutes deux ont une `position`, mais pas d'ancêtre commun qui la
## déclare — d'où l'accès par nom.
func _slide_in(node: CanvasItem, from_offset: Vector2, duration: float, delay: float) -> void:
	var rest: Vector2 = node.get("position")
	node.set("position", rest + from_offset)
	_tween.tween_property(node, "position", rest, duration) \
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_in(node, duration, delay)
