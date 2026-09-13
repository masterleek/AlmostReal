extends Node2D

## Curseur posé au-dessus de la tête de l'unité qui joue sa séquence de rythme.
##
## À QUOI IL SERT : pendant la séquence, le joueur regarde la barre, en bas de
## l'écran. Rien ne dit plus qui agit — l'unité ne s'est pas encore déplacée
## (elle ne part qu'une fois le dernier verdict tombé, cf. BattleAssault) et le
## HUD ne distingue que les alliés. Le curseur fait le lien entre les deux
## moitiés de l'écran.
##
## C'est CELUI DU WORLDMAP, repris tel quel : il désigne déjà « l'unité dont on
## parle » dans l'autre écran du jeu, et lui en donner un second vocabulaire
## coûterait un asset pour rien.

const PixelScale = preload("res://Scripts/Battle/UI/PixelScale.gd")

const CURSOR := preload("res://UI/cursor_worldmap.png")

## Décalage depuis le point « pieds » de l'unité, et inclinaison. CE NE SONT PAS
## DES VALEURS CHOISIES : ce sont exactement celles du curseur qui désigne une
## cible pendant la préparation, relevées en jeu. Là-bas elles résultent de la
## composition du menu réduit — `BattleScene.FOCUS_PILL_OFFSET` puis
## `CommandMenu.CURSOR_FOCUS_OFFSET`, dans le repère incliné du menu ; ici il n'y
## a pas de pastille à accompagner, le curseur se pose donc directement au
## résultat.
##
## Le décalage est CONSTANT, vérifié sur les trois emplacements d'ennemis : il
## sort à (9,703 79 ; −92,311 4) pour les trois, identique à la sixième
## décimale. Il ne dépend donc ni de la cible ni de l'inclinaison du menu.
##
## Position fractionnaire assumée : le curseur est TOURNÉ, donc déjà rendu par
## le chemin lissé de PixelScale — c'est justement le cas où le sous-pixel est
## correct, et l'arrondir le décalerait du curseur de ciblage.
const OFFSET := Vector2(9.7038, -92.3114)
const ROTATION_DEG := 33.0

const FADE_IN := 0.18
const FADE_OUT := 0.22

var _sprite: Sprite2D
var _tween: Tween

func _ready() -> void:
	# 100 % de pixels opaques : c'est du vrai pixel-art, il s'agrandit au plus
	# proche voisin — le défaut de PixelScale.sprite().
	_sprite = PixelScale.sprite(CURSOR)
	# Même composition que le curseur de ciblage : décalage de texture nul, la
	# rotation se faisant autour de l'origine du sprite (cf.
	# CommandMenu._place_cursor, branche `_focused`).
	_sprite.rotation_degrees = ROTATION_DEG
	add_child(_sprite)
	modulate.a = 0.0
	visible = false

## Pose le curseur sur `target` et le fait apparaître. Le décalage part du point
## « pieds » (`target.position`, cf. UnitSprite) et non de la cellule : c'est ce
## qui le rend indépendant de la façon dont chaque planche cadre son personnage.
func show_above(target: Node2D) -> void:
	position = target.position + OFFSET
	visible = true
	_fade(1.0, FADE_IN)

func hide_above() -> void:
	if not visible:
		return
	_fade(0.0, FADE_OUT)
	# Le nœud reste monté : il resservira à l'unité suivante.
	_tween.tween_callback(func() -> void: visible = false)

## Retire le curseur SANS fondu. Sert quand ce qui l'affichait disparaît d'un
## coup — un ciblage qu'on referme, un groupe qui laisse la place à une cible
## unique : le fondu de sortie le ferait survivre deux dixièmes de seconde à
## l'écran qu'il désignait.
func hide_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	visible = false

func _fade(to: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", to, duration)
