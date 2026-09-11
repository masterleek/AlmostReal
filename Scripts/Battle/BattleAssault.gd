extends Node

## Phase d'assaut : exécute, dans l'ordre d'agilité, les actions retenues
## pendant la préparation.
##
## CE QU'ELLE FAIT et ce qu'elle ne fait pas. Elle joue une liste d'actions et
## en applique les effets ; elle ne possède PAS la boucle de tour. Rendre les PA,
## effacer les actions, refermer les blessures — tout ce qui marque la fin d'un
## tour — reste à BattleScene, qui enchaîne les tours. Le partage suit la
## question « est-ce que ça a lieu PENDANT l'assaut ? » : les dégâts oui, la
## remise à zéro non.
##
## ELLE EST ASYNCHRONE. `run()` est une coroutine : chaque action joue son geste,
## attend l'instant où le coup porte, applique ses effets, puis laisse le geste
## se terminer avant de passer au suivant. C'est ce qui rend l'assaut lisible —
## on voit qui frappe qui — et c'est aussi ce qui laisse une place nette au
## Lot 7 : la barre de rythme s'insérera avant l'impact, entre le début du geste
## et son application.
##
## LES ATTENTES SONT EN SECONDES, pas en frames. La durée d'une planche se
## déduit de ses propres données (cf. UnitSprite.duration_of) et l'attente passe
## par un timer : l'environnement de debug tourne à une cadence irrégulière
## (cf. CLAUDE.md §workflow, point 4), un comptage de frames n'y serait pas
## reproductible.

const BattleUnit = preload("res://Scripts/Battle/BattleUnit.gd")
const BattleData = preload("res://Scripts/Battle/BattleData.gd")
const BattleRules = preload("res://Scripts/Battle/BattleRules.gd")
const UnitSprite = preload("res://Scripts/Battle/Stage/UnitSprite.gd")
const DamageNumber = preload("res://Scripts/Battle/UI/DamageNumber.gd")
const EnemyBehaviour = preload("res://Scripts/Battle/EnemyBehaviour.gd")

## Émis dès qu'une valeur affichée par le HUD a bougé (PV, blessure, mort).
## L'assaut ne connaît ni les blocs d'état ni les jauges : il annonce, la scène
## rafraîchit.
signal changed
## Fin de l'assaut, avec l'issue du combat.
signal finished(outcome: int)

## VICTORY / DEFEAT arrêtent le combat (Lot 9 en fera un écran) ; ONGOING rend
## la main à une nouvelle phase de préparation.
enum Outcome { ONGOING, VICTORY, DEFEAT }

## Geste de repli pour une unité sans planche d'attaque : un pas en avant puis
## un retour. Le cactoon n'a QUE des planches d'idle (sa page de rip n'en
## contient pas d'autre), et une action qui soigne n'a pas de geste d'attaque
## à jouer non plus. Un déplacement n'invente aucun dessin — contrairement à un
## sprite qu'on fabriquerait — et dit quand même « c'est mon tour ».
const LUNGE_DISTANCE := 7.0
const LUNGE_DURATION := 0.5

## Respiration entre deux actions. Sans elle, l'assaut s'enchaîne trop vite pour
## qu'on rattache un nombre à celui qui l'a infligé.
const BETWEEN_ACTIONS := 0.25

## Disparition d'une unité vaincue. PROVISOIRE : les planches `dying` et `dead`
## existent dans `_assets/battle/` mais relèvent du Lot 9 (cf. le lotissement) ;
## d'ici là, l'unité s'efface, ce qui la retire du terrain sans rien inventer.
const DEATH_FADE := 0.4

var _allies: Array[Dictionary] = []
var _enemies: Array[Dictionary] = []
## Nœud sous lequel jaillissent les nombres de dégâts — le conteneur d'unités,
## pour qu'ils soient triés en profondeur avec les combattants.
var _effects: Node2D

func setup(allies: Array[Dictionary], enemies: Array[Dictionary], effects: Node2D) -> void:
	_allies = allies
	_enemies = enemies
	_effects = effects

## ──────────────────────────────────────────────────────────────────────────
##  DÉROULEMENT
## ──────────────────────────────────────────────────────────────────────────

func run() -> void:
	_raise_guards()
	for entry in _order():
		var unit: BattleUnit = entry["unit"]
		if not unit.is_alive():
			# Mort depuis que l'ordre a été calculé : il n'agit pas, mais
			# l'ordre lui-même n'est pas recalculé — l'agilité départage le
			# tour entier, elle ne doit pas dépendre de qui vient de tomber.
			continue
		await _resolve(entry)
		if _outcome() != Outcome.ONGOING:
			break
		await _wait(BETWEEN_ACTIONS)
	finished.emit(_outcome())

## Les gardes sont posées AVANT le premier coup, pas au moment où l'unité
## aurait agi. Autrement, une unité lente se ferait frapper à découvert par tous
## ceux qui la devancent : la garde a été choisie pendant la préparation, elle
## vaut pour le tour entier.
func _raise_guards() -> void:
	for entry in _allies:
		var unit: BattleUnit = entry["unit"]
		if unit.is_alive() and String(unit.action.get("source", "")) == "guard":
			unit.guarding = true

## Ordre d'agilité décroissante sur tous les combattants vivants. À égalité, les
## alliés passent devant : il faut un départage stable, et l'avantage au joueur
## est le choix qui se défend le mieux.
func _order() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in _allies:
		if _unit_of(entry).is_alive():
			entries.append(entry)
	for entry in _enemies:
		if _unit_of(entry).is_alive():
			entries.append(entry)
	# Tri STABLE demandé : sort_custom ne l'est pas, d'où le départage explicite
	# par camp.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ua: BattleUnit = a["unit"]
		var ub: BattleUnit = b["unit"]
		if ua.agility != ub.agility:
			return ua.agility > ub.agility
		return _allies.has(a) and not _allies.has(b)
	)
	return entries

## ──────────────────────────────────────────────────────────────────────────
##  UNE ACTION
## ──────────────────────────────────────────────────────────────────────────

func _resolve(entry: Dictionary) -> void:
	var unit: BattleUnit = entry["unit"]
	var action := _action_of(entry)
	if action.is_empty():
		return
	var targets := _living_targets(entry, action)
	# La garde n'a rien à exécuter : son effet est déjà en place, et elle ne
	# vise personne. Elle ne coûte pas non plus de temps à l'assaut.
	if String(action.get("source", "")) == "guard" or targets.is_empty():
		return

	var effect := _effect_of(unit, action)
	var gesture: Dictionary = (
		BattleData.get_animation(unit.id, "atk") if effect["offensive"] else {}
	)
	await _play_gesture(entry, targets, gesture)
	for target in targets:
		_apply(unit, target, effect)
	changed.emit()
	await _finish_gesture(entry, gesture)
	await _bury_the_dead()

## Action de l'unité. Un allié joue celle qu'il a retenue ; un ennemi n'a pas de
## phase de préparation, il attaque.
##
## Le choix d'un ennemi n'est PAS pris ici : il est déduit de son bloc
## `behaviour` dans units.json (cf. EnemyBehaviour), pour que l'auteur puisse le
## régler en donnée plutôt qu'en code. L'action rendue a la même forme que celle
## qu'un allié retient au menu, et la suite de l'assaut ne distingue pas les
## deux.
##
## Elle est décidée MAINTENANT, pas au début du tour : l'ennemi voit donc l'état
## du terrain tel qu'il est quand il agit, coups déjà portés compris. C'est ce
## qui permet à un comportement « agressif » d'achever une cible que ses
## congénères viennent d'entamer.
func _action_of(entry: Dictionary) -> Dictionary:
	if _allies.has(entry):
		return _unit_of(entry).action
	return EnemyBehaviour.choose(_unit_of(entry), _standing(_enemies), _standing(_allies))

## Cibles encore debout. Une cible tombée entre la validation et l'exécution est
## remplacée par une autre du même camp plutôt que de faire perdre son tour à
## l'unité : le joueur a choisi une action, pas un cadavre.
##
## Une action SANS cible retenue est celle d'un ennemi, qui n'a pas de phase de
## préparation : elle est tirée au hasard parmi les alliés debout, ce qui
## répartit les coups sur l'équipe au lieu de s'acharner sur le premier de la
## liste. C'est aussi le repli quand toutes les cibles choisies sont tombées.
func _living_targets(entry: Dictionary, action: Dictionary) -> Array[BattleUnit]:
	var alive: Array[BattleUnit] = []
	for target: BattleUnit in action.get("targets", []):
		if target.is_alive():
			alive.append(target)
	if not alive.is_empty():
		return alive
	var standing := _standing(_camp_for(entry, String(action.get("target", "enemy"))))
	if not standing.is_empty():
		alive.append(standing[randi() % standing.size()])
	return alive

## Unités encore debout d'un camp.
func _standing(camp: Array[Dictionary]) -> Array[BattleUnit]:
	var units: Array[BattleUnit] = []
	for entry in camp:
		var unit: BattleUnit = _unit_of(entry)
		if unit.is_alive():
			units.append(unit)
	return units

## Modes de ciblage qui désignent le PROPRE CAMP de celui qui agit. Même liste
## que BattleScene.ALLY_TARGETS, mais lue en relatif : pour l'équipe « ally »
## veut dire l'équipe, pour un cactoon il veut dire les cactoons.
##
## C'est ce qui permet aux deux camps de partager UN SEUL catalogue d'Ekos : un
## soin déclaré « ally » soigne le camp de celui qui le lance, sans qu'il faille
## deux versions de chaque compétence.
const OWN_CAMP_TARGETS: PackedStringArray = ["ally", "allies", "self"]

## Camp visé par un mode de ciblage, du point de vue de `entry`.
func _camp_for(entry: Dictionary, kind: String) -> Array[Dictionary]:
	var caster_is_ally := _allies.has(entry)
	var aims_at_own_camp := kind in OWN_CAMP_TARGETS
	return _allies if caster_is_ally == aims_at_own_camp else _enemies

## Ce que l'action inflige ou rend : {offensive, power, heal, damage_type}.
## Le tableau de bord de l'action, lu une fois pour toutes ses cibles.
func _effect_of(unit: BattleUnit, action: Dictionary) -> Dictionary:
	var definition := _definition_of(unit, action)
	var heal := int(definition.get("heal", 0))
	return {
		"offensive": heal <= 0,
		"power": int(definition.get("power", 0)),
		"heal": heal,
		"injury": String(definition.get("damage_type", "direct")) == "injury",
	}

## Définition chiffrée de l'action, prise dans le catalogue qui la décrit.
## L'attaque de base n'a pas de catalogue : elle vit dans la fiche de l'unité
## (`basic_attack`), pour qu'un ennemi comme un allié puisse frapper avec sa
## propre puissance.
func _definition_of(unit: BattleUnit, action: Dictionary) -> Dictionary:
	var id := String(action.get("id", ""))
	match String(action.get("source", "attack")):
		"eko":
			return BattleData.get_eko(id)
		"item":
			return BattleData.get_item(id)
	return BattleData.get_unit(unit.id).get("basic_attack", {})

func _apply(actor: BattleUnit, target: BattleUnit, effect: Dictionary) -> void:
	var anchor := _head_of(target)
	if not bool(effect["offensive"]):
		var healed := int(effect["heal"])
		target.heal(healed)
		_pop_number(anchor, healed, DamageNumber.Kind.HEAL)
		return
	var amount := BattleRules.guarded(
		BattleRules.damage(int(effect["power"]), actor.force, target.defense),
		target.guarding,
	)
	if bool(effect["injury"]):
		target.take_injury_damage(amount)
		_pop_number(anchor, amount, DamageNumber.Kind.INJURY)
	else:
		target.take_direct_damage(amount)
		_pop_number(anchor, amount, DamageNumber.Kind.DIRECT)

## Le nombre est instancié ICI et non par DamageNumber : un script sans
## `class_name` ne peut pas se référencer lui-même dans une fonction statique,
## alors qu'un `const … = preload(…)` chez l'appelant le peut.
func _pop_number(anchor: Vector2, amount: int, kind: int) -> void:
	if amount <= 0:
		return
	var node: Node2D = DamageNumber.new()
	node.position = anchor.round()
	_effects.add_child(node)
	node.show_amount(amount, kind)

## ──────────────────────────────────────────────────────────────────────────
##  GESTES
## ──────────────────────────────────────────────────────────────────────────

## Joue le geste jusqu'à l'instant où le coup PORTE, et rend la main là — c'est
## l'appelant qui applique les effets, pour que le Lot 7 puisse insérer sa barre
## de rythme entre les deux sans toucher à cette fonction.
func _play_gesture(entry: Dictionary, targets: Array[BattleUnit], gesture: Dictionary) -> void:
	var sprite := _node_of(entry)
	if gesture.is_empty():
		await _lunge(entry, targets)
		return
	sprite.play_sheet(gesture, false)
	await _wait(UnitSprite.hit_time_of(gesture))

## Laisse le geste s'achever, puis remet l'unité dans sa planche de repos.
func _finish_gesture(entry: Dictionary, gesture: Dictionary) -> void:
	if gesture.is_empty():
		return
	var sprite := _node_of(entry)
	await _wait(UnitSprite.duration_of(gesture) - UnitSprite.hit_time_of(gesture))
	sprite.play_sheet(BattleData.get_animation(_unit_of(entry).id, "idle"))

## Pas en avant puis retour, vers la cible. La direction se déduit de la
## position de celle-ci plutôt que du camp : c'est la même règle pour tout le
## monde, et elle reste juste si les emplacements changent un jour.
func _lunge(entry: Dictionary, targets: Array[BattleUnit]) -> void:
	var sprite := _node_of(entry)
	var toward := _sprite_of(targets[0])
	var direction := 1.0 if toward != null and toward.position.x > sprite.position.x else -1.0
	var start := sprite.position
	var tween := create_tween()
	tween.tween_property(sprite, "position:x", start.x + direction * LUNGE_DISTANCE, LUNGE_DURATION * 0.5)
	tween.tween_property(sprite, "position:x", start.x, LUNGE_DURATION * 0.5)
	await _wait(LUNGE_DURATION * 0.5)

## Efface les unités tombées pendant l'action qui vient de se jouer. Groupé
## plutôt que fait cible par cible : une attaque de zone peut en coucher
## plusieurs, et elles doivent disparaître ensemble.
func _bury_the_dead() -> void:
	var falling: Array[Node2D] = []
	for entry in _allies + _enemies:
		var unit: BattleUnit = entry["unit"]
		var sprite := _node_of(entry)
		if not unit.is_alive() and sprite.modulate.a > 0.0:
			falling.append(sprite)
	if falling.is_empty():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	for sprite in falling:
		tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE)
	await _wait(DEATH_FADE)

## ──────────────────────────────────────────────────────────────────────────
##  OUTILS
## ──────────────────────────────────────────────────────────────────────────

## Sommet de la cellule d'une unité : le point d'où part son nombre de dégâts.
## Déduit du sprite (`position` = les pieds, `offset` = le haut de la cellule),
## donc juste quelle que soit la taille du personnage.
func _head_of(unit: BattleUnit) -> Vector2:
	var sprite := _sprite_of(unit)
	if sprite == null:
		return Vector2.ZERO
	return sprite.position + Vector2(0, sprite.offset.y)

func _sprite_of(unit: BattleUnit) -> AnimatedSprite2D:
	for entry in _allies + _enemies:
		if entry["unit"] == unit:
			return entry["sprite"]
	return null

## Les entrées sont des dictionnaires, donc du Variant : on les retype ici une
## fois pour toutes plutôt que d'annoter chaque accès.
func _unit_of(entry: Dictionary) -> BattleUnit:
	var unit: BattleUnit = entry["unit"]
	return unit

func _node_of(entry: Dictionary) -> UnitSprite:
	var sprite: UnitSprite = entry["sprite"]
	return sprite

func _outcome() -> int:
	if not _any_alive(_enemies):
		return Outcome.VICTORY
	if not _any_alive(_allies):
		return Outcome.DEFEAT
	return Outcome.ONGOING

func _any_alive(entries: Array[Dictionary]) -> bool:
	for entry in entries:
		if _unit_of(entry).is_alive():
			return true
	return false

func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(seconds).timeout
