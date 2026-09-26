extends Node2D

## Curseur posé au-dessus de la tête de l'unité ou de la cible désignée
## pendant la séquence de rythme.
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
const FADE_OUT := 0.11

## Le curseur TOMBE en place plutôt que de simplement apparaître : distance de
## chute en pixels de design. Plus RAPIDE que le fondu d'entrée (durée à part,
## pas alignée dessus) — une chute qui prend le même temps que le fondu se
## voit à peine, l'essentiel du trajet se jouant pendant que le curseur est
## encore quasi transparent.
const FALL_HEIGHT := 10.0
const FALL_DURATION := 0.09

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

## Pose le curseur au-dessus de `feet` (un point « pieds », cf. UnitSprite) et
## le fait apparaître EN CHUTE : parti de `FALL_HEIGHT` px plus haut, il tombe
## jusqu'à sa position finale pendant que le fondu d'entrée joue. Prend un
## POINT et non le nœud lui-même : la cible d'une action peut être plusieurs
## unités, et l'appelant fournit alors leur barycentre (cf.
## BattleAssault._centre_of).
func show_above(feet: Vector2) -> void:
	var target := feet + OFFSET
	position = target + Vector2(0, -FALL_HEIGHT)
	visible = true
	_stop_tween()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(self, "position", target, FALL_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func hide_above() -> void:
	if not visible:
		return
	_stop_tween()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	# Le nœud reste monté : il resservira à l'unité suivante.
	_tween.tween_callback(func() -> void: visible = false)

## Retire le curseur SANS fondu ni chute. Sert quand ce qui l'affichait
## disparaît d'un coup — un ciblage qu'on referme, un groupe qui laisse la
## place à une cible unique : l'animation de sortie le ferait survivre à
## l'écran qu'il désignait.
func hide_now() -> void:
	_stop_tween()
	modulate.a = 0.0
	visible = false

func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
