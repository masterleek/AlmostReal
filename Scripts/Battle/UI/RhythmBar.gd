extends Node2D

## Barre de rythme : les notes défilent vers l'anneau central, le joueur appuie
## quand elles y sont, et la justesse de son timing pèse sur les dégâts.
##
## DEUX SENS DE LECTURE. Sur un tour ALLIÉ la moitié droite s'allume en jaune et
## les notes viennent de la droite ; sur un tour ENNEMI c'est la moitié gauche
## en rouge, et elles viennent de la gauche. Le joueur attaque dans un cas, il
## se défend dans l'autre — la barre est le même objet, seule sa polarité change
## (cf. ui_rythmn_bar.jpg, qui montre les trois états : repos, allié, ennemi).
##
## CE QUI EST RELEVÉ et ce qui est réglé. Toute la GÉOMÉTRIE vient de
## `ui_rythmn_bar.jpg`, une planche de composants à l'échelle 1:1 du design —
## d'où des fenêtres de timing exprimées en PIXELS, pas en millisecondes : c'est
## ainsi que l'auteur les a dessinées, en bandes concentriques autour de
## l'anneau. La VITESSE des notes, elle, n'est nulle part : c'est le réglage de
## difficulté, et c'est lui qui convertit ces pixels en millisecondes.
##
## Le jugement se fait donc sur une DISTANCE, jamais sur une horloge : la note
## est jugée là où elle se trouve quand la touche tombe. Régler la vitesse
## resserre ou relâche les fenêtres sans toucher à la géométrie.

const BattleRules = preload("res://Scripts/Battle/BattleRules.gd")
const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")
const SfxBank = preload("res://Scripts/Audio/SfxBank.gd")

## EN PNG, ET C'EST MESURÉ. Ces trois-là sont les seuls assets de la barre à
## être restés en raster : leur SVG passe toute sa lueur par des `<filter>`
## (feGaussianBlur, feColorMatrix), que ThorVG — le rastériseur SVG de Godot —
## ignore silencieusement. Comparaison de l'intensité moyenne du rendu SVG à
## celle du PNG d'origine : 0,003 contre 0,039 pour la barre éteinte, 0,021
## contre 0,174 pour la jaune. Il ne restait qu'un dixième de la lueur.
##
## Étant de l'art anticrénelé (97 % de pixels à alpha partiel) et non du
## pixel-art, ils s'agrandissent en BILINÉAIRE — cf. PixelScale.sprite(smooth).
const LINE_EMPTY := preload("res://UI/Battle/rhythm_line_empty.png")
const LINE_ALLY := preload("res://UI/Battle/rhythm_line_yellow.png")
const LINE_ENEMY := preload("res://UI/Battle/rhythm_line_red.png")
const RING := preload("res://UI/Battle/rhythm_circle.svg")

## Lueur de frappe. En PNG pour la MÊME raison, et c'est le cas le plus net de
## tous : son SVG ne contient qu'un disque rempli à `fill-opacity="0.01"` —
## invisible — et TOUT son dessin tient dans deux ombres internes
## (feMorphology + feGaussianBlur + feComposite). Importé tel quel, Godot en
## rend un aplat à alpha 3/255 : 2,6 % de l'asset (alpha moyen 0,009 contre
## 0,354 pour un rendu qui applique les filtres). Le PNG est rastérisé à
## l'échelle du projet (256 px pour 64 de design), donc `sprite_native()`.
const GLOW := preload("res://UI/Battle/rhythm_glow.png")

## Notes jouables. La clé est ce qu'on écrit dans `sequence` (cf. ekos.json),
## la valeur l'action d'entrée à presser. Les quatre directions partagent un
## seul dessin, tourné : `btn_directions.svg` pointe vers le BAS.
const NOTE_TEXTURES := {
	"cross": preload("res://UI/Battle/btn_cross.svg"),
	"circle": preload("res://UI/Battle/btn_circle.svg"),
	"square": preload("res://UI/Battle/btn_square.svg"),
	"triangle": preload("res://UI/Battle/btn_triangle.svg"),
}
## En PNG pour la même raison que les barres : son SVG perd sa lueur (0,179
## contre 0,247). Les quatre autres notes n'ont pas de filtre et restent en
## vectoriel.
const ARROW := preload("res://UI/Battle/btn_directions.png")
const NOTE_ACTIONS := {
	"cross": "battle_confirm",
	"circle": "battle_cancel",
	"square": "battle_square",
	"triangle": "battle_triangle",
	"up": "ui_up",
	"down": "ui_down",
	"left": "ui_left",
	"right": "ui_right",
}
## Rotation du dessin de flèche, qui pointe vers le bas au repos.
const ARROW_ROTATION := {"down": 0.0, "left": 90.0, "up": 180.0, "right": 270.0}

## ──────────────────────────────────────────────────────────────────────────
##  GÉOMÉTRIE, relevée sur ui_rythmn_bar.jpg (échelle 1:1)
## ──────────────────────────────────────────────────────────────────────────

## Les deux moitiés font 239 px et se posent bord à bord, ce qui centre la barre
## sur un écran de 480 : 1..478. L'asset est dessiné COMME MOITIÉ GAUCHE — son
## dégradé s'éclaircit vers la droite, donc vers le centre de l'écran (mesuré :
## luminance 2 au bord, 29 à la 238ᵉ colonne). La moitié droite est donc le même
## asset retourné, exactement comme les deux moitiés de la plateforme.
const HALF_WIDTH := 239
const BAR_POS := Vector2(1, 209)

## Anneau : posé pour que son cercle blanc tombe en (239,5 ; 230,5), soit le
## centre de la barre. Relevé sur la vignette de repos de l'assaut — cercle
## blanc en x 221..258, et l'asset porte le sien en 2..39.
const RING_POS := Vector2(219, 210)
const CENTRE := Vector2(239.5, 230.5)

## Demi-largeur des fenêtres, en pixels de design depuis le centre de l'anneau.
## Relevées sur les bandes colorées de la planche, qui sont complémentaires au
## pixel près : vert 375..384, jaune 359..374 et 385..400, orange 348..358 et
## 401..411, rouge tout le reste — pour une barre en 140..619, donc centrée sur
## 379,5.
const WINDOW_PERFECT := 5.0
const WINDOW_GREAT := 21.0
const WINDOW_GOOD := 32.0

## Libellé du verdict, du côté OPPOSÉ à celui d'où viennent les notes — il ne
## doit pas se poser sur le chemin de ce qu'on est en train de lire. Corps 28,
## déduit de la largeur de « GOOD » (64 px relevés, 63 calculés) et confirmé par
## « PERFECT » (111 relevés, 110 calculés).
##
## Les deux relevés donnent 87,5 px à gauche et 94 à droite ; la maquette étant
## composée à la main et en JPEG, on prend une valeur SYMÉTRIQUE — le jeu, lui,
## n'a pas de raison de pencher d'un côté.
const JUDGEMENT_SIZE := 28
const JUDGEMENT_OFFSET := 90.0
const JUDGEMENT_BOX := 160.0
const JUDGEMENT_Y := 212
## Durée d'affichage d'un verdict. Assez court pour que deux notes proches ne se
## chevauchent pas à l'écran.
const JUDGEMENT_HOLD := 0.5

## Pulse de frappe. La lueur naît à la TAILLE DE LA NOTE (32 px de design pour
## 64 dessinés, soit 0,5) et s'ouvre au-delà en s'effaçant : le geste part du
## bouton qu'on vient de taper, il ne tombe pas dessus. Court — c'est un accusé
## de réception, pas une animation à regarder ; au-delà, deux frappes proches se
## superposeraient et on ne saurait plus laquelle a répondu.
const GLOW_FROM := 0.5
const GLOW_TO := 1.0
const GLOW_PULSE := 0.28

## Fondu de l'allumage. La barre ne s'allume pas d'un coup : elle monte quand
## l'unité prend la main et retombe quand elle a fini.
const GLOW_IN := 0.25
const GLOW_OUT := 0.3

## « PERFECT » est peint lettre par lettre sur la maquette — jaune, blanc, cyan,
## magenta. C'est le seul verdict à ce traitement, et il le mérite : c'est celui
## qu'on cherche. Les autres sont d'une seule couleur.
const PERFECT_LETTER_COLORS: PackedStringArray = [
	"#FFE800", "#FFFFFF", "#7FE7FF", "#FF5CD6", "#FFE800", "#FF5CD6", "#7FE7FF",
]
const GREAT_COLOR := Color8(0xFF, 0xE8, 0x00)
const GOOD_COLOR := Color8(0x5C, 0xFF, 0x2D)
const MISS_COLOR := Color8(0xFF, 0x3A, 0x1F)

## Un son par verdict, indexé par le verdict lui-même : la barre n'a alors
## aucune correspondance à tenir à jour, et ajouter un cran de jugement ne peut
## pas laisser un son derrière lui.
##
## Ils partent sur MASTER, avec les sons de menu et non avec les voix : ce sont
## des accusés de réception, ils doivent claquer par-dessus la musique sans la
## faire plonger à chaque note (cf. BattleScene._build_audio).
const JUDGEMENT_SOUNDS := {
	BattleRules.Judgement.PERFECT: preload("res://Audio/Battle/rhythm_perfect.wav"),
	BattleRules.Judgement.GREAT: preload("res://Audio/Battle/rhythm_great.wav"),
	BattleRules.Judgement.GOOD: preload("res://Audio/Battle/rhythm_good.wav"),
	BattleRules.Judgement.MISS: preload("res://Audio/Battle/rhythm_miss.wav"),
}

## ──────────────────────────────────────────────────────────────────────────
##  RÉGLAGE DE DIFFICULTÉ (rien de relevé : c'est ici qu'on dose)
## ──────────────────────────────────────────────────────────────────────────

## Vitesse de défilement, en pixels de design par seconde. C'est elle qui
## convertit les fenêtres en durées : à 170, Perfect vaut ±29 ms, Great ±124 ms
## et Good ±188 ms. L'augmenter durcit tout d'un coup.
const NOTE_SPEED := 170.0
## Temps entre deux ARRIVÉES sur l'anneau. À 170 px/s, les notes sont donc
## espacées de 94 px sur la barre — assez pour qu'on les distingue.
const NOTE_INTERVAL := 0.55
## Temps laissé après la dernière note, pour qu'on la voie sortir et que son
## verdict reste lisible.
const TAIL := 0.45

## Passé et stocké en `int`, jamais annoté `Side` : GDScript refuse l'enum d'un
## script sans `class_name` comme type (« Cannot assign a value of type
## RhythmBar.gd.Side as Side »). Même convention que BattleAssault.Outcome.
enum Side { NONE, ALLY, ENEMY }

## Émis quand la séquence est finie, avec un verdict par note (cf.
## BattleRules.Judgement). L'appelant en tire son multiplicateur.
signal finished(judgements: Array)

## Les deux moitiés éteintes, toujours affichées, et par-dessus les deux
## moitiés ALLUMÉES, dont l'opacité seule change. C'est ce qui permet un fondu :
## échanger la texture d'un seul sprite allumerait la barre d'un coup.
var _left: Sprite2D
var _right: Sprite2D
var _glow_left: Sprite2D
var _glow_right: Sprite2D
var _glow_tween: Tween
var _ring: Sprite2D
## UN seul nœud, réutilisé, comme le libellé de verdict : un martèlement en
## sèmerait autrement une dizaine à l'écran, et c'est toujours la DERNIÈRE
## frappe qui intéresse le joueur.
var _glow: Sprite2D
var _glow_pulse: Tween
var _judgement: RichTextLabel
var _judgement_tween: Tween
## Un lecteur DÉDIÉ par verdict — leur flux ne change jamais, et les prendre
## dans le pool les exposerait à se faire voler leur tour par une voix (cf.
## SfxBank). Vide tant que `setup_audio` n'a pas été appelé : la barre reste
## alors muette au lieu de planter, ce qui la garde utilisable hors combat.
var _judgement_players: Dictionary = {}
var _side: int = Side.NONE

## Notes en vol : {"id", "action", "node", "time"} — `time` étant l'instant
## d'arrivée sur l'anneau, en secondes depuis le début de la séquence.
var _notes: Array[Dictionary] = []
## Index de la prochaine note à juger. Les notes sont jugées DANS L'ORDRE : une
## touche ne peut pas valider une note plus lointaine en sautant la précédente.
var _pending: int = 0
var _judgements: Array = []
var _elapsed: float = 0.0
var _running: bool = false

func _ready() -> void:
	_left = PixelScale.sprite(LINE_EMPTY, Vector2.ZERO, true)
	_left.position = BAR_POS
	add_child(_left)


	# Retournée : l'asset est une moitié GAUCHE, son dégradé doit rester tourné
	# vers le centre.
	#
	# `flip_h` ne DÉPLACE PAS le sprite : avec `centered = false`, son rectangle
	# part toujours de `position` et le retournement ne fait que miroiter la
	# texture dedans. La moitié droite se pose donc simplement une largeur plus
	# loin — la décaler de deux largeurs, comme le ferait un retournement autour
	# de l'origine, l'envoyait hors de l'écran.
	_right = PixelScale.sprite(LINE_EMPTY, Vector2.ZERO, true)
	_right.flip_h = true
	_right.position = BAR_POS + Vector2(HALF_WIDTH, 0)
	add_child(_right)

	_glow_left = PixelScale.sprite(LINE_ENEMY, Vector2.ZERO, true)
	_glow_left.position = BAR_POS
	_glow_left.modulate.a = 0.0
	add_child(_glow_left)

	_glow_right = PixelScale.sprite(LINE_ALLY, Vector2.ZERO, true)
	_glow_right.flip_h = true
	_glow_right.position = BAR_POS + Vector2(HALF_WIDTH, 0)
	_glow_right.modulate.a = 0.0
	add_child(_glow_right)

	_ring = PixelScale.sprite_native(RING)
	_ring.position = RING_POS
	add_child(_ring)

	# Posée AVANT les notes — qui sont ajoutées à chaque séquence, donc toujours
	# après — pour que la lueur passe DERRIÈRE la note : un halo se lit comme ce
	# qui entoure le bouton, pas comme ce qui le recouvre.
	#
	# Décalée d'une demi-largeur, elle se centre sur `position` — et l'échelle du
	# pulse s'applique alors autour de ce centre. La demi-largeur se DÉDUIT de la
	# texture (`design_size`, pas `get_size`) : l'asset est natif ×4, une mesure
	# brute donnerait 128 au lieu de 32.
	_glow = PixelScale.sprite_native(GLOW, -PixelScale.design_size(GLOW) / 2.0)
	_glow.visible = false
	add_child(_glow)

	_judgement = BattleText.make_centered("", JUDGEMENT_BOX, JUDGEMENT_SIZE, Color(1, 1, 1))
	_judgement.visible = false
	add_child(_judgement)

	visible = false
	set_process(false)

## Branche la barre sur la banque de sons de l'écran. Séparé de la construction
## parce que la banque n'existe pas encore quand la barre est montée (cf.
## BattleScene._ready : l'assaut est bâti avant l'audio).
func setup_audio(bank: SfxBank) -> void:
	for judgement: int in JUDGEMENT_SOUNDS:
		_judgement_players[judgement] = bank.player(JUDGEMENT_SOUNDS[judgement])

## Allume la barre du côté de celui qui agit. À NONE elle reste montée mais
## éteinte : c'est l'état « début / fin de tour » de la planche de référence.
func set_side(side: int) -> void:
	# Rien à faire si le camp ne change pas — c'est ce qui évite le
	# clignotement entre deux unités du MÊME camp qui jouent l'une après
	# l'autre : la barre reste allumée, elle ne retombe pas pour remonter.
	if side == _side:
		return
	_side = side
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	var on := side != Side.NONE
	_glow_tween = create_tween()
	_glow_tween.set_parallel(true)
	_glow_tween.tween_property(
		_glow_left, "modulate:a", 1.0 if side == Side.ENEMY else 0.0,
		GLOW_IN if on else GLOW_OUT,
	)
	_glow_tween.tween_property(
		_glow_right, "modulate:a", 1.0 if side == Side.ALLY else 0.0,
		GLOW_IN if on else GLOW_OUT,
	)

## Joue `sequence` et rend la main quand tout est jugé. Coroutine : l'appelant
## `await`.
##
## Une séquence vide n'ouvre rien — pas de barre qui clignote pour rien — et
## rend un tableau vide, que BattleRules traduit en multiplicateur neutre.
func play(sequence: PackedStringArray, side: int) -> Array:
	# Le camp est annoncé même sans note à jouer : la barre dit QUI agit, pas
	# seulement ce qu'il y a à taper.
	set_side(side)
	visible = true
	if sequence.is_empty():
		return []
	# L'ÉTAT D'ABORD, LES NOTES ENSUITE : `_build_notes` les pose désormais à
	# leur place, et cette place se calcule depuis `_elapsed` et `_pending`.
	# Les remettre à zéro après aurait fait bâtir la séquence sur les valeurs de
	# la précédente.
	_judgements = []
	_pending = 0
	_elapsed = 0.0
	_build_notes(sequence)
	_running = true
	set_process(true)
	await finished
	return _judgements

## Fin d'une action : la séquence est effacée, mais LA BARRE RESTE ALLUMÉE.
## Deux alliés qui jouent l'un après l'autre ne doivent pas la voir clignoter
## entre eux — c'est le camp qui décide de son allumage, pas l'unité. Le fondu
## ne joue donc qu'aux changements de camp (c'est `play()` qui les annonce) et à
## la fin de l'assaut (`close()`).
func rest() -> void:
	_running = false
	set_process(false)
	_judgement.visible = false
	if _glow_pulse != null and _glow_pulse.is_valid():
		_glow_pulse.kill()
	_glow.visible = false
	_clear_notes()

## Monte et démonte la barre, aux bornes de l'assaut. Elle n'existe pas pendant
## la préparation : le menu occupe déjà le bas de l'écran.
func open() -> void:
	rest()
	set_side(Side.NONE)
	visible = true

## Éteint puis retire. La barre disparaît APRÈS son fondu, sinon la dernière
## action de l'assaut la verrait se couper net.
func close() -> void:
	rest()
	set_side(Side.NONE)
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.set_parallel(false)
		_glow_tween.tween_callback(func() -> void: visible = false)
	else:
		visible = false

## ──────────────────────────────────────────────────────────────────────────

func _build_notes(sequence: PackedStringArray) -> void:
	_clear_notes()
	# La première note part du bord de l'écran : son temps d'arrivée est
	# exactement le temps qu'il lui faut pour parcourir une demi-barre.
	var lead_in := CENTRE.x / NOTE_SPEED
	for i in sequence.size():
		var id := String(sequence[i])
		var node := _make_note(id)
		add_child(node)
		_notes.append({
			"id": id,
			"action": String(NOTE_ACTIONS.get(id, "")),
			"node": node,
			"time": lead_in + i * NOTE_INTERVAL,
		})
	# POSÉES TOUT DE SUITE, et pas à la première image de `_process`.
	#
	# Un Sprite2D ajouté sans position est dessiné à l'ORIGINE de son parent, et
	# la barre écrit ses enfants en coordonnées de design absolues : son origine
	# est donc le coin HAUT-GAUCHE de l'écran. Le temps d'une image, à chaque
	# action, une touche apparaissait là-haut — loin de la barre, au milieu du
	# décor. Un nœud doit naître à sa place ; le faire placer par la boucle qui
	# suit, c'est accepter une image fausse à chaque fois.
	_place_notes()

## Retire les notes AVANT de les libérer. `queue_free()` est différé à la fin de
## l'image : sans le retrait, les notes de la séquence précédente restent
## enfants — donc dessinées — le temps d'une image par-dessus les nouvelles.
func _clear_notes() -> void:
	for note in _notes:
		var node := note["node"] as Node
		remove_child(node)
		node.queue_free()
	_notes.clear()

## Chaque note à sa distance de l'anneau, et masquée dès qu'elle est jugée.
##
## Appelée à la CONSTRUCTION et à chaque image : c'est la même vérité, et la
## première image n'a aucune raison d'y échapper. Une note déjà jugée s'efface
## plutôt que de continuer sa route — elle n'a plus rien à dire, et deux notes
## visibles à la fois embrouillent.
func _place_notes() -> void:
	for i in _notes.size():
		var node := _notes[i]["node"] as Sprite2D
		node.position = Vector2(CENTRE.x + _offset_of(i), CENTRE.y)
		node.visible = i >= _pending

func _make_note(id: String) -> Sprite2D:
	var texture: Texture2D = (
		NOTE_TEXTURES[id] if NOTE_TEXTURES.has(id) else PixelScale.upscaled(ARROW, true)
	)
	# `centered` reste vrai ici, contrairement au reste du projet : une note est
	# posée par son CENTRE sur une ligne, jamais par son coin, et sa texture est
	# de côté pair (32) — aucun demi-pixel à craindre.
	var node := Sprite2D.new()
	node.texture = texture
	node.rotation_degrees = float(ARROW_ROTATION.get(id, 0.0)) if not NOTE_TEXTURES.has(id) else 0.0
	PixelScale.apply(node)
	return node

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_place_notes()
	# La note en tête a-t-elle dépassé la dernière fenêtre sans être touchée ?
	while _pending < _notes.size() and _offset_of(_pending) * _direction() < -WINDOW_GOOD:
		_resolve(BattleRules.Judgement.MISS)
	if _pending >= _notes.size() and _elapsed >= _notes[-1]["time"] + TAIL:
		_running = false
		set_process(false)
		finished.emit(_judgements)

## Position d'une note par rapport au centre de l'anneau, en pixels de design.
## Positive du côté d'où elle vient.
func _offset_of(index: int) -> float:
	return (float(_notes[index]["time"]) - _elapsed) * NOTE_SPEED * _direction()

## +1 quand les notes viennent de la droite (tour allié), −1 sinon.
func _direction() -> float:
	return -1.0 if _side == Side.ENEMY else 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not _running or _pending >= _notes.size():
		return
	if not _is_note_input(event):
		return
	get_viewport().set_input_as_handled()
	# La lueur part AVANT le jugement, et quel que soit ce jugement : elle dit
	# « la touche est passée », pas « c'était bon ». Un raté a d'autant plus
	# besoin de cette réponse — c'est elle qui montre au joueur de combien il
	# s'est trompé, en se posant là où il a tapé plutôt que sur l'anneau.
	_pulse_glow()
	var note := _notes[_pending]
	var distance: float = absf(_offset_of(_pending))
	# TOUTE touche compte, dès l'instant où les notes défilent — y compris bien
	# avant que la prochaine n'arrive. Elle tombe alors hors de la dernière
	# fenêtre, donc en raté.
	#
	# Un premier jet ignorait les touches trop précoces, pour ne pas « consommer
	# une note qui n'est pas encore là ». C'était une erreur de deux façons : ça
	# rendait le martèlement gratuit, et surtout ça donnait au joueur une
	# manette morte pendant la moitié de la séquence, sans rien lui dire.
	if not event.is_action_pressed(String(note["action"])) or distance > WINDOW_GOOD:
		_resolve(BattleRules.Judgement.MISS)
		return
	if distance <= WINDOW_PERFECT:
		_resolve(BattleRules.Judgement.PERFECT)
	elif distance <= WINDOW_GREAT:
		_resolve(BattleRules.Judgement.GREAT)
	else:
		_resolve(BattleRules.Judgement.GOOD)

## Vrai si l'événement est l'une des touches de note — sans ça, n'importe quelle
## entrée (un clic, une touche sans rapport) compterait comme une tentative.
func _is_note_input(event: InputEvent) -> bool:
	for action: String in NOTE_ACTIONS.values():
		if event.is_action_pressed(action):
			return true
	return false

## Pose la lueur LÀ OÙ SE TROUVE LA NOTE À CET INSTANT, et non sur l'anneau :
## l'écart entre les deux EST le retard ou l'avance du joueur, rendu visible.
## Les entrées sont traitées APRÈS `_process` dans la même image : `_elapsed`
## vaut donc déjà ce qui vient d'être dessiné, et la lueur tombe exactement sur
## la note telle qu'elle est à l'écran (mesuré : 443,59 contre 443,59).
func _pulse_glow() -> void:
	if _glow_pulse != null and _glow_pulse.is_valid():
		_glow_pulse.kill()
	_glow.position = Vector2(CENTRE.x + _offset_of(_pending), CENTRE.y)
	_glow.visible = true
	_glow.modulate.a = 1.0
	# L'échelle de base n'est pas 1 : `PixelScale.apply()` contre-échelonne le
	# nœud de SCALE pour que la texture native retombe à sa taille de design.
	# Le pulse se multiplie donc à cette base, il ne la remplace pas.
	var base := Vector2.ONE / float(PixelScale.SCALE)
	_glow.scale = base * GLOW_FROM
	_glow_pulse = create_tween()
	_glow_pulse.set_parallel(true)
	_glow_pulse.tween_property(_glow, "scale", base * GLOW_TO, GLOW_PULSE)
	_glow_pulse.tween_property(_glow, "modulate:a", 0.0, GLOW_PULSE)
	_glow_pulse.chain().tween_callback(func() -> void: _glow.visible = false)

func _resolve(judgement: int) -> void:
	_judgements.append(judgement)
	_pending += 1
	_show_judgement(judgement)
	_play_judgement(judgement)

## Le son accompagne le VERDICT, d'où qu'il vienne — une touche tombée à côté
## comme une note laissée passer. Le libellé MISS s'affiche déjà dans les deux
## cas ; le laisser muet dans le second ferait croire à un bug de la manette
## plutôt qu'à une note manquée.
func _play_judgement(judgement: int) -> void:
	var player: AudioStreamPlayer = _judgement_players.get(judgement)
	if player == null:
		return
	# `play()` REJOUE depuis le début, il n'empile pas : deux verdicts identiques
	# coup sur coup se remplacent. C'est voulu — un son de verdict dure jusqu'à
	# 1,9 s pour des notes espacées de 0,55, et les laisser se superposer
	# transformerait une série de Perfect en bouillie.
	player.play()

func _show_judgement(judgement: int) -> void:
	if _judgement_tween != null and _judgement_tween.is_valid():
		_judgement_tween.kill()
	BattleText.set_centered_text(_judgement, _judgement_text(judgement))
	# Du côté opposé aux notes : à gauche quand elles viennent de la droite.
	var x := CENTRE.x - _direction() * JUDGEMENT_OFFSET - JUDGEMENT_BOX / 2.0
	_judgement.position = Vector2(roundf(x), JUDGEMENT_Y)
	_judgement.visible = true
	_judgement.modulate.a = 1.0
	_judgement_tween = create_tween()
	_judgement_tween.tween_interval(JUDGEMENT_HOLD)
	_judgement_tween.tween_property(_judgement, "modulate:a", 0.0, 0.2)
	_judgement_tween.tween_callback(func() -> void: _judgement.visible = false)

func _judgement_text(judgement: int) -> String:
	match judgement:
		BattleRules.Judgement.PERFECT:
			var text := ""
			var letters := "PERFECT"
			for i in letters.length():
				text += "[color=%s]%s[/color]" % [PERFECT_LETTER_COLORS[i], letters[i]]
			return text
		BattleRules.Judgement.GREAT:
			return "[color=#%s]GREAT[/color]" % GREAT_COLOR.to_html(false)
		BattleRules.Judgement.GOOD:
			return "[color=#%s]GOOD[/color]" % GOOD_COLOR.to_html(false)
	return "[color=#%s]MISS[/color]" % MISS_COLOR.to_html(false)
