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

## APERÇU DU COUP. Quand une unité encaisse, la part de jauge mise en jeu
## s'allume d'abord d'un aplat — blanc pour une blessure, rouge pour un coup
## direct — avant que la jauge ne se résolve (cf. play_hit et
## `anim_jauge_hp` fourni par l'auteur). L'aperçu se pose SUR la queue du vert :
## il montre ce qui est sur le point d'être perdu, pas ce qui l'est déjà.
##
## Le rouge n'est pas choisi : c'est celui de l'éclair de `ic_type_action_2.svg`,
## l'icône qui annonce un coup direct dans les listes d'actions — les deux
## disent la même chose, ils doivent donc être de la même couleur. (Son pendant
## bleu, #007BFF, est déjà la couleur des rayures ci-dessus.) Le blanc, lui,
## vient de la référence d'animation, où il est franc.
const PREVIEW_INJURY_COLOR := Color(1, 1, 1)
const PREVIEW_DIRECT_COLOR := Color8(0xFF, 0x37, 0x00)

## Temps d'affichage de l'aperçu avant que la jauge ne bouge — il doit être vu
## avant d'être résolu, c'est toute sa raison d'être.
const PREVIEW_HOLD := 0.18
## Durée de la résolution : le bord vert recule, et avec lui ce qui le suit.
const SETTLE_DURATION := 0.35

## Seuls les coins arrondis sont préservés par le 9-slice ; le corps de la
## gouttière est uni sur toute sa longueur, 2 px suffisent donc largement.
const PATCH_MARGIN := 2

## Largeur voulue en unités de design, à poser AVANT d'ajouter le nœud à
## l'arbre. 0 = largeur naturelle de l'asset (59), celle du HUD.
var design_width: int = 0

var _fill: Sprite2D
var _injury: Sprite2D
var _preview: Sprite2D
## Largeur de la zone de blessure, en pixels d'écran. 0 = pas de blessure, donc
## rien à animer.
var _injury_width: float = 0.0
## État courant de la jauge. Gardé plutôt que recalculé : c'est `_acquired` que
## la résolution d'un coup anime, et il faut pouvoir redessiner à chaque pas.
var _acquired: float = 1.0
var _full: float = 1.0
var _hit_tween: Tween
## Bornes du coup en cours, gardées pour que la résolution puisse redessiner
## l'aperçu à chaque pas.
var _hit_from: float = 0.0
var _hit_to: float = 0.0
var _hit_injury: bool = false

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

	# ORDRE DE DESSIN, et il compte : l'aperçu passe SUR le vert (il en colore
	# la queue), et le bleu passe SUR l'aperçu (l'auteur demande qu'il s'affiche
	# « par dessus la partie blanche »). D'où vert, puis aperçu, puis bleu —
	# ce dernier est donc remonté en dernier enfant.
	var solid := Image.create_empty(
		int(PixelScale.design_size(FILL).x), int(PixelScale.design_size(FILL).y),
		false, Image.FORMAT_RGBA8,
	)
	solid.fill(Color(1, 1, 1))
	_preview = PixelScale.sprite(ImageTexture.create_from_image(solid))
	_preview.region_enabled = true
	_preview.region_rect = Rect2()
	_preview.position = FILL_INSET
	_preview.scale.x *= _track_width() / PixelScale.design_size(FILL).x
	add_child(_preview)
	move_child(_injury, get_child_count() - 1)

	# Étirement horizontal de la piste, en plus de la contre-échelle posée par
	# PixelScale. Vaut exactement 1 sur une jauge de largeur naturelle : le
	# HUD n'est pas rééchantillonné. Il ne s'applique qu'au dégradé : les
	# rayures, elles, sont dessinées à la période voulue et n'ont pas à être
	# déformées avec la piste.
	_fill.scale.x *= _track_width() / PixelScale.design_size(FILL).x

	set_process(false)
	set_ratio(1.0)

## Joue l'encaissement d'un coup, en deux temps : l'aperçu de ce qui est mis en
## jeu, puis sa résolution.
##
## Les deux cas ne diffèrent que par la COULEUR de l'aperçu et par ce qui reste
## après — la mécanique est la même, et c'est voulu : dans les deux cas le bord
## du vert recule de `before_acquired` à `after_acquired`.
##
##   - BLESSURE : l'aperçu est blanc, et le bleu le recouvre en suivant le bord
##     qui recule. Les PV ne bougent pas, seul ce qui est acquis diminue.
##   - DIRECT : l'aperçu est rouge, le vert se vide sous lui, puis le rouge
##     s'efface et découvre la gouttière.
func play_hit(
	before_acquired: float, after_acquired: float, after_full: float, injury: bool
) -> void:
	_kill_hit()
	_hit_injury = injury
	_hit_from = clampf(before_acquired, 0.0, 1.0)
	_hit_to = clampf(after_acquired, 0.0, 1.0)

	_preview.modulate = PREVIEW_INJURY_COLOR if injury else PREVIEW_DIRECT_COLOR

	# L'état d'ARRIVÉE est posé tout de suite pour les PV ; seul le bord acquis
	# part de l'ancienne valeur, puisque c'est lui qu'on anime.
	_full = clampf(after_full, 0.0, 1.0)
	_acquired = _hit_from
	_redraw()
	_draw_preview(0.0)

	_hit_tween = create_tween()
	_hit_tween.tween_interval(PREVIEW_HOLD)
	_hit_tween.tween_method(_settle, 0.0, 1.0, SETTLE_DURATION)
	_hit_tween.tween_callback(func() -> void: _preview.region_rect = Rect2())

## Un pas de résolution. `t` va de 0 (l'aperçu vient d'être vu) à 1 (c'est
## réglé).
func _settle(t: float) -> void:
	_acquired = lerpf(_hit_from, _hit_to, t)
	_redraw()
	_draw_preview(t)

## Pose l'aperçu. Les deux cas divergent ICI, et nulle part ailleurs :
##
##   - BLESSURE : il ne bouge pas. Il marque la part mise en jeu, et c'est le
##     bleu qui vient le recouvrir en suivant le bord du vert.
##   - DIRECT : son bord gauche reste sur la valeur d'arrivée, son bord DROIT
##     suit le bord du vert qui recule. Le rouge se vide donc par la droite
##     jusqu'à disparaître, et le vert VISIBLE — celui qui dépasse à gauche du
##     rouge — ne bouge pas : il est déjà à sa valeur finale.
##
##     C'est le point que le premier jet ratait. En faisant remonter le bord
##     gauche du rouge vers le bord du vert, il faisait GRANDIR le vert visible
##     en cours d'animation avant de le ramener — une jauge de vie qui se
##     remplit pendant qu'on encaisse. Relevé sur la référence, colonne par
##     colonne : le vert s'arrête au même pixel sur les trois vignettes, seul
##     le bord extérieur du rouge se déplace (139 → 127 → disparu).
func _draw_preview(_t: float) -> void:
	var left := _hit_to
	var right := _hit_from
	if not _hit_injury:
		right = _acquired
	var track := _track_width()
	var lx: float = round(track * left)
	var rx: float = round(track * right)
	_preview.position = FILL_INSET + Vector2(lx, 0)
	_preview.region_rect = _region(rx - lx, PixelScale.design_size(FILL), track)

func _kill_hit() -> void:
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_preview.region_rect = Rect2()

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
	_kill_hit()
	_acquired = clampf(ratio, 0.0, 1.0)
	_full = maxf(_acquired, clampf(full_ratio, 0.0, 1.0))
	_redraw()

## Repose les trois segments d'après `_acquired` et `_full`. Séparé de
## set_ratio parce que la résolution d'un coup le rappelle à chaque pas sans
## vouloir, elle, réinitialiser l'aperçu.
func _redraw() -> void:
	# `design_size()`, pas `Vector2(FILL.get_width(), FILL.get_height())` : FILL
	# est un SVG déjà rastérisé ×4, son get_width() renvoie la taille ÉCRAN
	# (228), pas la taille de DESIGN (57) sur laquelle tout le calcul qui suit
	# doit se faire.
	var full := PixelScale.design_size(FILL)
	var track := _track_width()
	# On arrondit la largeur AFFICHÉE, pas la largeur de texture : c'est elle
	# qui doit tomber sur un pixel de design entier.
	var width: float = round(track * _acquired)
	_fill.region_rect = _region(width, full, track)

	if _full <= _acquired:
		_injury_width = 0.0
		_injury.region_rect = Rect2()
		set_process(false)
		return
	var full_width: float = round(track * _full)
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
