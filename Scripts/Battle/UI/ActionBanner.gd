extends Node2D

## Pastille qui nomme l'action en cours d'exécution, posée au-dessus de la barre
## de rythme et pointant vers l'anneau.
##
## C'est le MÊME objet qu'une entrée de menu — même asset de pastille, même
## 9-slice, même icône de nature des dégâts à cheval sur son bord gauche
## (cf. CommandMenu). La différence tient en trois points : elle est seule,
## centrée, et elle porte une petite pointe sous elle qui la relie à l'anneau.
##
## POURQUOI UN FICHIER À PART plutôt qu'un mode de CommandMenu : celui-ci gère
## une LISTE — sélection, défilement, fenêtre visible, inclinaison par rangée.
## Rien de tout ça ici. Les deux partagent des assets, pas un comportement.
##
## Relevée sur la troisième vignette de mockup_assault_allies.jpg (« Fulgura »)
## et sur celle de mockup_assault_ennemies.jpg (« Attack »).

const BattleText = preload("res://Scripts/Battle/UI/BattleText.gd")
const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

const PILL_ALLY := preload("res://UI/Battle/command_on.svg")
const PILL_ENEMY := preload("res://UI/Battle/command_red.svg")
const TAIL_ALLY := preload("res://UI/Battle/command_on_arrow.svg")
const TAIL_ENEMY := preload("res://UI/Battle/command_red_arrow.svg")
const ICON_INJURY := preload("res://UI/Battle/ic_type_action_1.svg")
const ICON_DIRECT := preload("res://UI/Battle/ic_type_action_2.svg")

## Reprises de CommandMenu : c'est le même asset, il se découpe pareil.
const HEIGHT := 18
const PATCH_MARGIN := 8
const TEXT_SIZE := 15
const TEXT_COLOR := Color8(0x27, 0x04, 0x00)
const TYPE_ICON_OFFSET := Vector2(4, 1)

## Bord supérieur de la pastille et abscisse de son centre. L'aplat jaune occupe
## x 186..291 et y 187..201 sur la maquette ; l'asset portant 2 px de contour à
## gauche et à droite et 1 px en haut, ça place le NŒUD en (184, 186), donc un
## centre à 239. Un demi-pixel à gauche du centre de la barre (239,5) — c'est la
## maquette qui est composée ainsi, on la suit.
const TOP := 186
const CENTRE_X := 239.0
## LARGEUR FIXE, et c'est une mesure, pas une simplification : « Fulgura » et
## « Attack » occupent exactement le même x 186..291 sur les deux maquettes.
## La pastille ne s'ajuste donc pas à son texte, contrairement à celles du menu.
## 110 = les 106 px d'aplat relevés, plus les 2 px de contour de chaque côté que
## porte l'asset.
const WIDTH := 110.0
## Le libellé est centré sur la partie LIBRE de la pastille, pas sur la pastille
## entière : l'icône de nature mange son bord gauche, et un centrage naïf
## faisait passer la première lettre dessous.
const LABEL_SHIFT := 7.0

## ROTATION Y (pseudo-3D) au changement d'action, relevée sur une planche de
## référence en trois temps : posée déjà DE PROFIL (90°), elle pivote à plat
## (0°) ; à la fin du tour elle repart de profil (-90°) puis change de contenu
## avant de repivoter à plat pour l'action suivante — le cycle recommence.
##
## Node2D n'a pas de troisième axe : cos(90°) = 0, donc le PROFIL d'une carte
## sans épaisseur est un simple TRAIT VERTICAL — l'échelle horizontale rend
## cette silhouette sans qu'il faille un vrai axe Y ni un shader de
## perspective. Le contenu ne change QUE pendant ce trait (largeur nulle),
## exactement comme sur la planche.
const FLIP_DURATION := 0.08

## La pointe (9×6) se pose sous la pastille, centrée. Son asset n'a que TROIS
## rangées d'aplat — 9 px de large, puis 4, puis 2 — et la PREMIÈRE est cachée
## dans le corps de la pastille : sur la maquette on ne voit que les rangées 1
## et 2, en x 237..240 puis 238..239, aux ordonnées 202 et 203. Le nœud se pose
## donc en (235, 201), soit 15 px sous le haut de la pastille et non 17.
const TAIL_OFFSET_Y := 15

var _pill: NinePatchRect
var _label: RichTextLabel
var _icon: Sprite2D
var _tail: Sprite2D
## Groupe pivot pour la rotation Y : ses enfants s'écrivent en coordonnées
## relatives à CENTRE_X (donc x = 0 en leur centre), pour que l'échelle
## horizontale les squeeze SUR PLACE plutôt que vers le bord gauche de l'écran
## — Node2D n'a pas de `pivot_offset` comme Control, ce nœud en tient lieu.
var _flip: Node2D
var _flip_tween: Tween

func _ready() -> void:
	_flip = Node2D.new()
	_flip.position = Vector2(CENTRE_X, 0)
	add_child(_flip)

	_pill = NinePatchRect.new()
	_pill.patch_margin_left = PATCH_MARGIN * PixelScale.SCALE
	_pill.patch_margin_right = PATCH_MARGIN * PixelScale.SCALE
	_pill.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelScale.apply(_pill)
	_flip.add_child(_pill)

	_tail = PixelScale.sprite_native(TAIL_ALLY)
	_flip.add_child(_tail)

	_label = BattleText.make("", TEXT_SIZE, TEXT_COLOR)
	# SANS contour, comme l'entrée SÉLECTIONNÉE d'un menu (cf. CommandMenu) :
	# le contour de l'interface est du #270400, exactement la couleur de ce
	# texte-ci. Sur fond clair il ne détache rien, il empâte — les lettres se
	# referment sur elles-mêmes. C'est pour la même raison que le menu le retire
	# sur sa pastille jaune.
	BattleText.set_outlined(_label, TEXT_SIZE, false)
	_flip.add_child(_label)

	_icon = PixelScale.sprite_native(ICON_DIRECT)
	# Au-dessus de la pastille, qu'elle déborde sur la gauche — comme dans une
	# liste d'actions.
	_icon.z_index = 2
	_flip.add_child(_icon)

	visible = false

## Affiche la pastille. `text_id` est un identifiant Localization ; `ally` choisit
## la couleur ; `damage_type` l'icône, vide pour une action qui n'inflige rien
## (elle n'en porte alors aucune, cf. CommandMenu).
func show_action(text_id: String, ally: bool, damage_type: String) -> void:
	var text := Localization.get_text(text_id)

	_pill.texture = PILL_ALLY if ally else PILL_ENEMY
	_pill.size = Vector2(WIDTH, HEIGHT) * PixelScale.SCALE
	# Coordonnées relatives à _flip, donc à CENTRE_X près de ce qu'elles étaient
	# quand ce nœud portait tout directement (cf. _flip ci-dessus).
	_pill.position = Vector2(roundf(-WIDTH / 2.0), TOP)

	_label.text = text
	# La largeur du texte est connue avant tout rendu (cf. BattleText.text_width),
	# inutile d'attendre une passe pour le centrer.
	_label.position = Vector2(
		roundf(LABEL_SHIFT - BattleText.text_width(text, TEXT_SIZE) / 2.0), TOP + 1
	)

	_tail.texture = TAIL_ALLY if ally else TAIL_ENEMY
	var tail_size := PixelScale.design_size(_tail.texture)
	_tail.position = Vector2(roundf(-tail_size.x / 2.0), TOP + TAIL_OFFSET_Y)

	_icon.visible = damage_type != ""
	if _icon.visible:
		_icon.texture = ICON_INJURY if damage_type == "injury" else ICON_DIRECT
		_icon.position = _pill.position + TYPE_ICON_OFFSET

	visible = true
	# DE PROFIL D'ABORD (cf. FLIP_DURATION) : le contenu qu'on vient de poser
	# n'est donc jamais vu à plat avant d'avoir pivoté, comme sur la planche —
	# à la différence d'un fondu, ici il n'y a rien à voir tant que l'échelle
	# n'a pas commencé à s'ouvrir.
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip.scale.x = 0.0
	_flip_tween = create_tween()
	_flip_tween.tween_property(_flip, "scale:x", 1.0, FLIP_DURATION)

func hide_action() -> void:
	if not visible:
		return
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_property(_flip, "scale:x", 0.0, FLIP_DURATION)
	# Le nœud reste monté, comme ActorCursor.hide_above : il resservira à
	# l'action suivante, qui repart de ce même profil (cf. show_action).
	_flip_tween.tween_callback(func() -> void: visible = false)
