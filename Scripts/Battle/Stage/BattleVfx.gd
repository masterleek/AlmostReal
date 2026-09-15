extends AnimatedSprite2D

## Effet visuel d'impact : une planche jouée UNE SEULE FOIS là où le coup porte,
## puis retirée.
##
## POURQUOI UN NŒUD À PART, et pas un UnitSprite. Les deux affichent une planche
## en grille — et ils partagent d'ailleurs son découpage, `build_frames` étant
## statique et sans effet de bord, ce pour quoi elle a été écrite. Tout le reste
## diffère : un sprite d'unité VIT sur le terrain, il est posé sur un point au
## sol, son `anchor` aligne ses planches entre elles pour que le personnage ne
## saute pas en changeant d'état, et il change de planche des dizaines de fois
## par combat. Un effet d'impact naît, joue, meurt ; il n'a pas de point au sol,
## il se pose là où on le lui dit.
##
## L'EFFET APPARTIENT À L'ACTION, pas au personnage. C'est ce qui permet à une
## attaque normale et à un Eko de ne pas montrer le même impact, et c'est
## pourquoi sa planche se règle dans le catalogue de l'action (`impact_vfx`) et
## non dans le bloc `animations` d'une unité.
##
## IL SE LIBÈRE TOUT SEUL au bout de sa propre durée, et pas sur
## `animation_finished` : l'environnement de debug tourne à une cadence
## irrégulière et tout le combat se séquence en SECONDES (cf. CLAUDE.md).

const UnitSprite = preload("res://Scripts/Battle/Stage/UnitSprite.gd")

## Cadence par défaut d'un effet qui n'en déclare pas. La même que celle des
## planches de personnage (cf. UnitSprite.setup) : il n'y a pas de raison qu'un
## champ absent veuille dire deux choses différentes selon le nœud qui le lit.
const DEFAULT_FPS := 6.0

## Fusion ADDITIVE, pour les planches d'effet peintes SUR FOND NOIR plutôt que
## détourées en transparence. C'est une convention courante — et c'est celle de
## `vfx_hit.png` dans les assets du projet, opaque du premier au dernier pixel.
## Dessinée telle quelle, une planche pareille pose un carré noir sur le
## terrain ; dessinée en addition, son fond noir n'ajoute rien et seule la
## lumière de l'effet passe. L'alternative serait de détourer l'image, ce qui
## détruit les dégradés d'une lueur — l'addition, elle, les garde.
const BLEND_ADD := "add"

## Joue la planche décrite par `config` en posant le CENTRE de sa vignette sur
## `at` (repère du parent), puis se retire.
##
## Une planche introuvable ne lève rien : le nœud se libère et l'assaut continue.
## C'est le même parti pris que partout ici — un asset manquant ne produit rien,
## il n'invente pas un effet de remplacement et il n'interrompt pas un combat.
func play_once(config: Dictionary, at: Vector2) -> void:
	var sheet := String(config.get("sheet", ""))
	var texture: Texture2D = load(sheet) if sheet != "" else null
	if texture == null:
		queue_free()
		return
	var columns := maxi(1, int(config.get("columns", 1)))
	var rows := maxi(1, int(config.get("rows", 1)))
	# LA DURÉE EST DÉDUITE DES MÊMES NOMBRES QUE LE DÉCOUPAGE, ici et pas par
	# `UnitSprite.duration_of` : celle-ci lit `frames` avec 1 pour défaut, quand
	# le découpage, lui, prend la grille entière. Les deux valeurs ne peuvent pas
	# diverger si une seule lecture les sert toutes les deux.
	var count := int(config.get("frames", columns * rows))
	var fps := maxf(1.0, float(config.get("fps", DEFAULT_FPS)))
	sprite_frames = UnitSprite.build_frames(
		texture, columns, rows, count, fps, int(config.get("first_frame", 0)), false
	)
	# Même parti pris que UnitSprite : `centered = false` et un offset ENTIER.
	# Le centrage automatique d'une cellule de largeur impaire tombe sur un
	# demi-pixel, qui devient 2 px de flou une fois le Stage agrandi ×4.
	var cell := Vector2i(texture.get_width() / columns, texture.get_height() / rows)
	centered = false
	offset = -Vector2(int(cell.x / 2.0), int(cell.y / 2.0))
	position = at.round()
	if String(config.get("blend", "")) == BLEND_ADD:
		var mode := CanvasItemMaterial.new()
		mode.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mode
	play("default")
	await get_tree().create_timer(count / fps).timeout
	queue_free()
