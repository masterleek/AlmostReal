extends Node2D

## Ce qu'on voit quand une unité encaisse un coup : sa silhouette s'embrase une
## fraction de seconde, et sa jauge de vie apparaît sous ses pieds le temps
## qu'on lise la perte.
##
## UN OBJET PAR UNITÉ, monté une fois pour toutes plutôt que fabriqué à chaque
## coup : une jauge est un assemblage de trois nœuds (gouttière, remplissage,
## segment de blessure) et une unité peut être touchée plusieurs fois dans le
## même tour.
##
## LA JAUGE EST CELLE DU CIBLAGE, pas une nouvelle. Même composant, même largeur
## (32 px contre 59 pour le HUD), même décalage depuis le point « pieds » — ces
## valeurs-là ont été relevées sur un PNG sans perte au Lot 3, alors que le
## mockup d'assaut est un JPEG. Reprendre le réglage existant vaut mieux que le
## redériver d'une source dégradée, d'autant que la maquette montre bien la même
## jauge au même endroit.
##
## Le segment BLEU n'est pas un choix d'ici : c'est le comportement que HpBar
## porte depuis le Lot 1 — la portion de vie qui vient d'être perdue, affichée le
## temps d'une transition. La maquette d'assaut le confirme (jauge verte, puis
## bleu, puis gouttière).

const HpBar = preload("res://Scripts/Battle/UI/HpBar.gd")
const BattleUnit = preload("res://Scripts/Battle/BattleUnit.gd")

## Le même shader que la surbrillance de ciblage et que la tuile de révélation
## du worldmap : blanchir une silhouette sans toucher à sa transparence est
## exactement le besoin, il n'y a pas lieu d'en écrire un troisième.
const WHITE_TINT := preload("res://Shaders/white_tint.gdshader")

## La jauge est celle du ciblage, à la même largeur. Son décalage, en revanche,
## n'est PAS celui du ciblage : là-bas elle est posée sous un nom de cible et se
## cale sur lui, ici elle est seule.
##
## Relevé sur `anim_jauge_hp.png`, dont les vignettes sont à ×2 du design. La
## correspondance verticale vient de la frontière claire/sombre de la
## plateforme, parfaitement horizontale et présente dans les deux images :
## y = 166 sur la référence, y = 179 en jeu, donc `design = référence/2 + 96`
## (vérifié sur dix colonnes). Le haut de la gouttière y tombe à 164, et le bas
## de l'ombre du personnage à 161 — soit, en remontant les 4 px qui séparent
## l'ombre du bas de sa cellule, un point « pieds » à 165. Le haut de la jauge
## est donc UN PIXEL AU-DESSUS des pieds, et non dix en dessous.
const BAR_WIDTH := 32
const BAR_OFFSET := Vector2(-BAR_WIDTH / 2, -1)

## Voir TargetSelector.DARK_CUTOFF : les planches portent leur ombre au sol DANS
## la cellule, et sans ce seuil l'éclat allumerait un halo blanc sous les pieds.
const DARK_CUTOFF := 0.05

# LES QUATRE DURÉES DE CE QU'ON VOIT QUAND UNE UNITÉ ENCAISSE, regroupées ici
# pour se régler d'un seul endroit. Ce sont des valeurs de RESSENTI : elles ne
# se démontrent pas, elles s'essaient — on regarde le coup partir, on trouve que
# la jauge traîne, on reprend deux dixièmes. Les changer, relancer le combat.

## Durée de l'éclat. Court — c'est un impact, pas un état. La montée est
## instantanée (le blanc est posé d'un coup), seule la retombée est animée :
## un fondu sur l'aller émousserait le coup.
const FLASH_DURATION := 0.22

## Fondu d'APPARITION de la jauge. Zéro : elle s'allume d'un coup, comme elle
## l'a toujours fait. Monter à 0,1 - 0,15 l'adoucit si elle paraît surgir.
const BAR_APPEAR := 0.0

## Temps pendant lequel la jauge reste lisible après le dernier coup encaissé.
##
## COMPTÉ DEPUIS L'IMPACT, pas depuis la fin de la résolution : le bord vert
## met encore 0,53 s à reculer (HpBar.PREVIEW_HOLD + SETTLE_DURATION), il ne
## reste donc ici que 0,57 s où la jauge est stabilisée et lisible. C'est ce
## qu'il faut avoir en tête si elle paraît trop courte alors que 1,1 s semble
## confortable.
const BAR_HOLD := 0.75

## Durée de l'effacement de la jauge, une fois l'attente écoulée.
const BAR_FADE := 0.1

var _sprite: CanvasItem
var _bar: HpBar
var _material: ShaderMaterial
## Un seul tween de jauge à la fois : un second coup pendant que la précédente
## s'efface doit relancer l'attente, pas superposer deux fondus.
var _bar_tween: Tween
var _flash_tween: Tween

## `sprite` est celui de l'unité suivie : il reçoit l'éclat, et sa `position`
## (le point « pieds », cf. UnitSprite) donne l'ancrage de la jauge.
func setup(sprite: CanvasItem) -> void:
	_sprite = sprite

	_material = ShaderMaterial.new()
	_material.shader = WHITE_TINT
	_material.set_shader_parameter("dark_cutoff", DARK_CUTOFF)

	_bar = HpBar.new()
	_bar.design_width = BAR_WIDTH
	_bar.visible = false
	add_child(_bar)

## Montre le coup. `unit` porte déjà ses PV D'APRÈS ; `before_acquired` est la
## part de jauge acquise AVANT, celle que le coup vient de mettre en jeu.
## `injury` décide de la couleur de l'aperçu et de ce qu'il devient.
func hit(unit: BattleUnit, before_acquired: float, injury: bool) -> void:
	_flash()
	_show_bar(unit, before_acquired, injury)

## Éclat blanc, puis retour. Le matériau est retiré à la fin plutôt que laissé
## à zéro : les sprites d'unité n'en ont pas en temps normal (cf. UnitSprite),
## et le ciblage en pose un autre — laisser le nôtre en place le ferait
## silencieusement gagner.
func _flash() -> void:
	if _sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_sprite.material = _material
	_material.set_shader_parameter("white_amount", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(
		func(amount: float) -> void:
			_material.set_shader_parameter("white_amount", amount),
		1.0, 0.0, FLASH_DURATION,
	)
	_flash_tween.tween_callback(_clear_tint)

func _clear_tint() -> void:
	# Seulement si c'est encore LE NÔTRE : entre-temps un autre système a pu
	# poser le sien.
	if _sprite != null and _sprite.material == _material:
		_sprite.material = null

func _show_bar(unit: BattleUnit, before_acquired: float, injury: bool) -> void:
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	# Position relue à chaque coup : l'unité se déplace pendant l'assaut (elle
	# va au contact), la jauge doit la suivre là où elle est touchée.
	_bar.position = (_sprite.position + BAR_OFFSET).round()
	_bar.play_hit(before_acquired, unit.solid_ratio(), unit.hp_ratio(), injury)
	_bar.visible = true
	_bar_tween = create_tween()
	if BAR_APPEAR <= 0.0:
		_bar.modulate.a = 1.0
	elif _bar.modulate.a < 1.0:
		# UN SECOND COUP PENDANT LE FONDU D'ENTRÉE ne repart pas de zéro : la
		# jauge est déjà là, la rallumer depuis l'invisible la ferait clignoter.
		# On reprend l'opacité où elle en est, et la durée restante avec.
		_bar_tween.tween_property(
			_bar, "modulate:a", 1.0, BAR_APPEAR * (1.0 - _bar.modulate.a)
		)
	else:
		_bar.modulate.a = 0.0
		_bar_tween.tween_property(_bar, "modulate:a", 1.0, BAR_APPEAR)
	_bar_tween.tween_interval(BAR_HOLD)
	_bar_tween.tween_property(_bar, "modulate:a", 0.0, BAR_FADE)
	_bar_tween.tween_callback(func() -> void: _bar.visible = false)
