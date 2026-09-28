extends Node

## Ouverture du combat : chaque élément de l'écran entre à son tour, au lieu que
## tout apparaisse d'un bloc dans son état final.
##
## D'ABORD le voile (BackgroundDim) se referme en cercle sur la plateforme —
## cf. `_close_iris`, TERMINÉ avant la suite (pas de parallélisme avec le
## reste). PUIS, à t = 0 : bandes noires, plateforme, blocs du HUD (alliés +
## synergie) et menu de commandes démarrent TOUS ENSEMBLE. Les combattants
## n'ont AUCUNE animation propre (essayé : fondu, dépli+rotation, rebond sur
## l'échelle, apparition par groupes décalés — cf. l'historique git si l'un de
## ces essais est à ressortir ; demandé sans, au final : « simplement ancrés à
## la plateforme »). Ce script ne les reçoit donc même plus : ils sont enfants
## de `arena` (posés par BattleScene), et suivent son dépli pour rien de plus.
## Le joueur ne reçoit la main qu'à la toute fin (`finished`) — le plus tardif
## du HUD et du menu, pas simplement la fin du menu — c'est à l'appelant de
## garder le menu inactif jusque-là.
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
#  HUD_INTERVAL vient de la demande de l'auteur (0,5 s au départ, divisé par
#  deux pour accélérer TOUT globalement, puis reposé explicitement à 0,10 s).
#  Le rebond du HUD et le glissement des commandes du menu (cf.
#  CommandMenu.ROW_SLIDE) viennent aussi de demandes explicites. Les
#  combattants ont eu plusieurs essais d'animation propre (fondu seul, dépli +
#  rotation, rebond sur l'échelle, apparition par groupes décalés) : retirés à
#  la demande de l'auteur — cf. l'historique git si l'un est à ressortir.
# ──────────────────────────────────────────────────────────────────────────

## Plateforme : fondu + rotation X de −90° à 0° + échelle de 70 % à 100 %.
const FLIP_DURATION := 0.2
const FLIP_FROM_DEG := -90.0
const FLIP_FROM_SCALE := 0.7

## Blocs du HUD : fondu + chute avec un LÉGER rebond en fin de course (demandé :
## « plus naturel » qu'un arrêt sec, puis « trop fort » — cf. `_slide_in_bounce`,
## un dépassement CONTRÔLÉ plutôt que la courbe TRANS_BOUNCE de Godot, trop
## prononcée à cette échelle). Un bloc toutes les HUD_INTERVAL (demandé) — dès
## que l'animation d'un bloc démarre, le suivant démarre HUD_INTERVAL plus tard
## (pas après la FIN de son animation). Durée un peu plus longue que la chute
## d'origine (0,1 s) : un rebond a besoin d'un peu de place pour se voir, sinon
## il passe inaperçu (déjà constaté sur ce même genre d'animation, cf. le flip
## de la plateforme).
const HUD_FALL := 12.0
const HUD_FALL_DURATION := 0.25
const HUD_BOUNCE_OVERSHOOT := 3.0
const HUD_INTERVAL := 0.1

## Bandes noires : fondu, celle du haut descend à sa place, celle du bas monte.
const BANDS_SLIDE := 24.0
const BANDS_DURATION := 0.2

## Menu : une rangée toutes les MENU_ROW_INTERVAL, chacune en MENU_ROW_FADE.
## Chaque commande glisse aussi horizontalement en apparaissant (demandé) —
## géré dans CommandMenu.reveal() lui-même, pas ici : cf. CommandMenu.ROW_SLIDE.
const MENU_ROW_INTERVAL := 0.04
const MENU_ROW_FADE := 0.06

## Voile (BackgroundDim) : se referme en cercle sur la plateforme AVANT tout
## le reste (cf. battle_intro_iris.gdshader) — le monde se resserre sur le
## point de combat, qui n'apparaît qu'une fois le voile refermé. Le rayon de
## départ doit dépasser la diagonale de l'écran (rien d'assombri au repos) ;
## 1600 le fait largement pour un écran 1920x1080 recentré sur la plateforme.
const IRIS_START_RADIUS := 1600.0
const IRIS_DURATION := 0.5

## L'ouverture est jouée : le joueur peut prendre la main.
signal finished

var _tween: Tween

## Joue l'ouverture.
##
## - `veil` (BackgroundDim) se referme en cercle sur `focus` AVANT tout le
##   reste — cf. IRIS_START_RADIUS. Doit porter un ShaderMaterial sur
##   battle_intro_iris.gdshader (posé par BattleScene._ready), sinon
##   `set_shader_parameter` échoue silencieusement (pas d'assombrissement).
## - `focus` : le point ÉCRAN (pas monde — cf. battle_intro_iris.gdshader) sur
##   lequel l'iris se referme. En pratique le Hero du worldmap (BattleLauncher
##   le calcule), pas forcément le centre de `arena` : rien ici ne suppose
##   qu'ils coïncident.
## - `arena` porte la plateforme ET les combattants, pivot au centre de la
##   plateforme : c'est lui qui pivote en premier, et comme les combattants sont
##   ses enfants ils restent ANCRÉS au sol pendant qu'il se redresse — SANS
##   rien de plus : ce script ne les reçoit pas et ne leur applique aucune
##   animation propre (demandé, cf. l'entête du fichier), ils suivent le dépli
##   de `arena` pour toute leur apparition. `arena` doit être à l'identité au
##   repos — il y revient à la fin. PAS de fondu sur la plateforme elle-même :
##   elle reste opaque du début à la fin, seules son échelle et sa rotation
##   l'animent — sinon, tant qu'elle est semi-transparente, le worldmap dessiné
##   derrière (cf. BattleScene, "le worldmap reste affiché EN DIRECT derrière
##   le combat") transparaît au travers, ce qui a été pris à tort pour un
##   chevauchement entre ses deux moitiés (PLATFORM_LEFT/PLATFORM_RIGHT) alors
##   qu'il s'agit du hex du Hero, bien plus clair que le reste de la worldmap à
##   cet endroit.
## - `band_top` / `band_bottom` : les bandes noires, à leur position de repos.
## - `hud_blocks` : un tableau par bloc du HUD, dans l'ordre d'arrivée ; les
##   nœuds d'un même bloc tombent ensemble (la jauge de synergie et son libellé,
##   qui sont frères et pas parent/enfant).
## - `menu` et `legend` : le menu racine, et ce qui apparaît avec sa dernière
##   rangée.
func play(
	veil: ColorRect, focus: Vector2, arena: Node2D,
	band_top: CanvasItem, band_bottom: CanvasItem, hud_blocks: Array,
	menu: CommandMenu, legend: CanvasItem,
) -> void:
	# Caché AVANT la moindre attente — sinon, le temps que l'iris se referme,
	# ces éléments se montreraient dans leur état final par-dessus le voile
	# encore ouvert (constaté : ils sont sinon déjà tous là dès la première
	# image, l'iris se refermant sur un combat déjà entièrement monté). ALPHA
	# SEUL suffit ici (pas les positions/échelles de départ, posées plus bas
	# par `_flip_in`/`_slide_in` eux-mêmes) : à alpha 0, rien ne se voit, quelle
	# que soit la position — et la reposer ici la ferait lire à tort comme LA
	# position de repos par `_slide_in`, qui doublerait alors le décalage.
	band_top.modulate.a = 0.0
	band_bottom.modulate.a = 0.0
	arena.scale = flip_scale(0.0)
	for block in hud_blocks:
		for node: CanvasItem in block:
			node.modulate.a = 0.0
	# PAS un alpha de rangée à 0 (essayé, constaté cassé) : `reveal()` relève
	# l'alpha COURANT de chaque rangée comme cible à restaurer (cf. sa propre
	# doc) — le mettre à 0 ici le lui ferait lire comme la cible elle-même,
	# et l'animation irait de 0 à 0, silencieusement. Cacher le nœud entier ne
	# touche à aucun alpha, donc ne casse pas cette hypothèse.
	menu.visible = false
	legend.modulate.a = 0.0

	await _close_iris(veil, focus)

	_tween = create_tween().set_parallel(true)

	_slide_in(band_top, Vector2(0, -BANDS_SLIDE), BANDS_DURATION, 0.0)
	_slide_in(band_bottom, Vector2(0, BANDS_SLIDE), BANDS_DURATION, 0.0)

	_flip_in(arena, 0.0)

	for i in hud_blocks.size():
		for node: CanvasItem in hud_blocks[i]:
			_slide_in_bounce(
				node, Vector2(0, -HUD_FALL), HUD_FALL_DURATION, i * HUD_INTERVAL,
				HUD_BOUNCE_OVERSHOOT,
			)
	var hud_end := maxi(0, hud_blocks.size() - 1) * HUD_INTERVAL + HUD_FALL_DURATION

	menu.visible = true
	# Le glissement (horizontal, demandé) est sur CHAQUE commande, pas sur le
	# menu entier — cf. CommandMenu.reveal()/_fade_from_zero.
	var menu_end: float = menu.reveal(MENU_ROW_INTERVAL, MENU_ROW_FADE, 0.0)
	# Avec la DERNIÈRE rangée : la légende décrit ce menu, elle n'a rien à dire
	# tant qu'il n'est pas là.
	_fade_in(legend, MENU_ROW_FADE, menu_end - MENU_ROW_FADE)

	# Les combattants n'ont plus de timeline à eux (cf. entête du fichier) :
	# `finished` attend seulement le plus tardif du HUD et du menu.
	var end_time := maxf(hud_end, menu_end)
	_tween.tween_callback(finished.emit).set_delay(end_time)

## Referme le voile en cercle sur `center` (cf. battle_intro_iris.gdshader) :
## rayon de IRIS_START_RADIUS (rien d'assombri) jusqu'à 0 (tout assombri,
## l'état de repos que `veil` a déjà par sa propre couleur). Tween À PART,
## PAS `_tween` — cette étape est TERMINÉE avant que le reste ne commence
## (cf. `await` dans `play()`), donc rien à faire tourner en parallèle ici.
func _close_iris(veil: ColorRect, center: Vector2) -> void:
	var material: ShaderMaterial = veil.material
	material.set_shader_parameter("center", center)
	material.set_shader_parameter("radius", IRIS_START_RADIUS)
	# Le shader ne relève PAS `veil.color` tout seul (cf. battle_intro_iris.gdshader) :
	# une seule couleur à changer si `veil.color` change un jour.
	material.set_shader_parameter("dim_color", veil.color)
	var iris_tween := create_tween()
	iris_tween.tween_method(
		func(r: float) -> void: material.set_shader_parameter("radius", r),
		IRIS_START_RADIUS, 0.0, IRIS_DURATION,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await iris_tween.finished

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

func _flip_in(node: Node2D, delay: float) -> void:
	node.scale = flip_scale(0.0)
	var set_scale := func(t: float) -> void: node.scale = flip_scale(t)
	_tween.tween_method(set_scale, 0.0, 1.0, FLIP_DURATION) \
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

## Comme `_slide_in`, mais dépasse LÉGÈREMENT sa position de repos avant d'y
## revenir — un rebond, mais CONTRÔLÉ (`overshoot`, en pixels), pas la courbe
## TRANS_BOUNCE de Godot (essayée, jugée trop prononcée pour un si petit
## déplacement). Le dépassement se fait dans le sens du mouvement — pour une
## chute (`from_offset` vers le haut), ça continue un peu vers le bas avant de
## remonter à la position finale.
func _slide_in_bounce(
	node: CanvasItem, from_offset: Vector2, duration: float, delay: float, overshoot: float,
) -> void:
	var rest: Vector2 = node.get("position")
	node.set("position", rest + from_offset)
	_fade_in(node, duration, delay)

	var direction := -from_offset.normalized()
	var fall_duration := duration * 0.7
	var settle_duration := duration - fall_duration
	_tween.tween_property(node, "position", rest + direction * overshoot, fall_duration) \
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(node, "position", rest, settle_duration) \
		.set_delay(delay + fall_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
