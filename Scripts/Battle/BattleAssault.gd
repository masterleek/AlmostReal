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
const HitFeedback = preload("res://Scripts/Battle/UI/HitFeedback.gd")
const EnemyBehaviour = preload("res://Scripts/Battle/EnemyBehaviour.gd")

## Émis dès qu'une valeur affichée par le HUD a bougé (PV, blessure, mort).
## L'assaut ne connaît ni les blocs d'état ni les jauges : il annonce, la scène
## rafraîchit.
signal changed
## Fin de l'assaut, avec l'issue du combat.
signal finished(outcome: int)
## Un coup vient de porter. L'assaut ne connaît pas la caméra : il annonce
## l'impact, la scène le traduit en secousse.
signal impact

## VICTORY / DEFEAT arrêtent le combat (Lot 9 en fera un écran) ; ONGOING rend
## la main à une nouvelle phase de préparation.
enum Outcome { ONGOING, VICTORY, DEFEAT }

## VENIR AU CONTACT. La maquette d'assaut montre l'attaquant quitter son
## emplacement, frapper au corps à corps, puis revenir : il s'arrête à
## APPROACH_DISTANCE de sa cible, du côté d'où il vient. La distance est lue sur
## la maquette (une trentaine de pixels entre les deux silhouettes) — approchée,
## puisque cette maquette est un JPEG et qu'on ne cale rien au pixel dessus.
const APPROACH_DISTANCE := 30.0
const APPROACH_DURATION := 0.35
const RETURN_DURATION := 0.35

## Planche jouée en revenant, quand l'unité en a une (`move_back`). Sinon le
## déplacement se fait seul, sur la planche de repos — ce qui est le cas de TOUT
## LE MONDE aujourd'hui : aucun personnage n'a encore de planche de retour. Le
## fichier livré sous ce nom s'est révélé être la première rangée de
## `313000404_limit_atk.png` (identique au pixel près, cf. le plan), donc le
## début d'une attaque spéciale, pas un retour. La mécanique reste en place :
## déclarer l'animation suffira à la faire jouer.
const ANIM_RETURN := "move_back"

## Temps passé au contact quand l'unité n'a PAS de planche d'attaque — le
## cactoon n'a que des idles, sa page de rip n'en contient pas d'autre. Le
## déplacement tient alors lieu de geste : il n'invente aucun dessin, et dit
## quand même d'où vient le coup.
const CONTACT_PAUSE := 0.25

## Geste de repli d'une action qui ne frappe pas (un soin) : un pas en avant
## puis un retour, sans quitter son emplacement. Elle n'a personne à aller
## chercher.
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
## Emplacement de départ de chaque unité, relevé au montage : c'est là qu'elle
## revient après avoir frappé. Gardé ici plutôt que lu sur le sprite, dont la
## position est justement ce qui bouge.
var _home: Dictionary = {}
## Un retour visuel par unité (éclat + jauge), monté une fois pour toutes.
var _feedback: Dictionary = {}

func setup(allies: Array[Dictionary], enemies: Array[Dictionary], effects: Node2D) -> void:
	_allies = allies
	_enemies = enemies
	_effects = effects
	for entry in _allies + _enemies:
		var unit := _unit_of(entry)
		_home[unit] = _node_of(entry).position
		var feedback: Node2D = HitFeedback.new()
		_effects.add_child(feedback)
		feedback.setup(_node_of(entry))
		_feedback[unit] = feedback

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
	var offensive := bool(effect["offensive"])
	var gesture := _gesture_for(unit, action)

	# Aller au contact, frapper, revenir. Une action qui SOIGNE ne se déplace
	# pas : elle n'a personne à aller chercher, et traverser le terrain pour
	# tendre une potion se lirait comme une charge.
	if offensive:
		await _approach(entry, targets)
	await _play_gesture(entry, targets, gesture, offensive)

	for target in targets:
		# Relevé AVANT le coup : c'est le point de départ de l'animation de
		# jauge, et il n'est plus lisible une fois les PV appliqués.
		var before := target.solid_ratio()
		_apply(unit, target, effect)
		if offensive:
			_feedback[target].hit(target, before, bool(effect["injury"]))
	changed.emit()
	if offensive:
		impact.emit()

	await _finish_gesture(entry, gesture)
	if offensive:
		await _return_home(entry)
	else:
		_node_of(entry).play_sheet(BattleData.get_animation(unit.id, "idle"))
	await _bury_the_dead()

## Planche que cette action fait jouer, cherchée dans le bloc `animations` de
## l'unité QUI AGIT — pas dans le catalogue de l'action. Un Eko est partagé par
## plusieurs personnages : il nomme un geste (`animation`), chacun le joue avec
## sa propre planche et sa propre fourchette de frames. Une planche absente
## n'est pas une erreur : l'unité frappe sans geste (cf. _play_gesture).
func _gesture_for(unit: BattleUnit, action: Dictionary) -> Dictionary:
	var name := String(_definition_of(unit, action).get("animation", "atk"))
	return BattleData.get_animation(unit.id, name)

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

## Amène l'unité devant sa cible. Elle s'arrête à APPROACH_DISTANCE, DU CÔTÉ
## D'OÙ ELLE VIENT — pas systématiquement à droite : la règle vaut pour les deux
## camps, et reste juste si les emplacements changent un jour.
##
## Sur un ciblage de groupe, le point visé est le barycentre des cibles : se
## poster devant un membre arbitraire donnerait l'impression de n'attaquer que
## celui-là. C'est déjà la règle du ciblage (cf. TargetSelector).
func _approach(entry: Dictionary, targets: Array[BattleUnit]) -> void:
	var sprite := _node_of(entry)
	var home: Vector2 = _home[_unit_of(entry)]
	var focus := _centre_of(targets)
	if focus == Vector2.ZERO:
		return
	var side := signf(home.x - focus.x)
	if side == 0.0:
		side = 1.0
	# Arrondi : une position à virgule devient un demi-pixel flou une fois le
	# Stage agrandi ×4.
	var stop := Vector2(focus.x + side * APPROACH_DISTANCE, focus.y).round()
	var tween := create_tween()
	tween.tween_property(sprite, "position", stop, APPROACH_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(APPROACH_DURATION)

## Ramène l'unité à son emplacement, sur sa planche de retour si elle en a une.
## Les deux durent le même temps : le déplacement dure au moins la planche, pour
## qu'elle ne se termine pas en chemin.
func _return_home(entry: Dictionary) -> void:
	var unit := _unit_of(entry)
	var sprite := _node_of(entry)
	var gesture := BattleData.get_animation(unit.id, ANIM_RETURN)
	var duration := RETURN_DURATION
	if not gesture.is_empty():
		duration = maxf(duration, UnitSprite.duration_of(gesture))
		sprite.play_sheet(gesture, false)
	else:
		# Sans planche de retour, on repasse au repos DÈS LE DÉPART plutôt qu'à
		# l'arrivée : le geste d'attaque ne boucle pas, l'unité resterait figée
		# sur sa dernière image — bras tendu — pendant tout le trajet du retour.
		sprite.play_sheet(BattleData.get_animation(unit.id, "idle"))
	var tween := create_tween()
	tween.tween_property(sprite, "position", _home[unit], duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(duration)
	sprite.play_sheet(BattleData.get_animation(unit.id, "idle"))

## Barycentre des pieds des cibles, arrondi. Vector2.ZERO quand il n'y a
## personne — aucune cible ne se tient à l'origine de l'écran.
func _centre_of(targets: Array[BattleUnit]) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for target in targets:
		var sprite := _sprite_of(target)
		if sprite != null:
			sum += sprite.position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return (sum / float(count)).round()

## Joue le geste jusqu'à l'instant où le coup PORTE, et rend la main là — c'est
## l'appelant qui applique les effets, pour que le Lot 7 puisse insérer sa barre
## de rythme entre les deux sans toucher à cette fonction.
##
## Sans planche, deux cas distincts : une unité venue au contact marque un temps
## d'arrêt (le déplacement tient lieu de geste), une unité qui soigne fait un pas
## en avant depuis son emplacement.
func _play_gesture(
	entry: Dictionary, targets: Array[BattleUnit], gesture: Dictionary, offensive: bool
) -> void:
	if not gesture.is_empty():
		_node_of(entry).play_sheet(gesture, false)
		await _wait(UnitSprite.hit_time_of(gesture))
		return
	if offensive:
		await _wait(CONTACT_PAUSE)
		return
	await _lunge(entry, targets)

## Laisse le geste s'achever. Ne remet PAS l'unité au repos : ce qui suit — le
## retour à l'emplacement — a sa propre planche, et la lui reprendre ici la
## ferait clignoter.
func _finish_gesture(_entry: Dictionary, gesture: Dictionary) -> void:
	if gesture.is_empty():
		return
	await _wait(UnitSprite.duration_of(gesture) - UnitSprite.hit_time_of(gesture))

## Pas en avant puis retour, vers la cible, sans quitter son emplacement.
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
