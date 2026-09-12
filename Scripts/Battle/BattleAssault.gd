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
const RhythmBar = preload("res://Scripts/Battle/UI/RhythmBar.gd")
const ActionBanner = preload("res://Scripts/Battle/UI/ActionBanner.gd")
const ActorCursor = preload("res://Scripts/Battle/UI/ActorCursor.gd")
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
## L'action vient de faire effet et demande son son (chemin `res://`). Même
## partage que l'impact : l'assaut dit QUOI jouer, la scène possède les
## lecteurs. Rien n'est émis pour une action sans `sound`.
signal sound_cue(path: String)
## Une séquence de rythme vient d'être jugée. L'assaut ne connaît pas la jauge de
## synergie : il annonce les verdicts, la scène en fait ce qu'elle veut.
signal rhythm_resolved(judgements: Array)
## Le terrain doit glisser vers le camp attaqué : +1 quand un allié agit, −1
## quand c'est un ennemi, 0 pour revenir au centre. Même partage que ci-dessus —
## l'assaut dit ce qui se passe, la scène décide de ce que ça déplace.
signal field_shift(direction: int)

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
## Barre de rythme, montée par la scène et prêtée à l'assaut : c'est lui qui
## sait quand une action se joue, et de quel côté.
var _rhythm: RhythmBar
## Pastille qui nomme l'action en cours, au-dessus de la barre.
var _banner: ActionBanner
## Curseur au-dessus de l'unité qui joue sa séquence. Monté ici et non par la
## scène : il ne sert qu'à l'assaut, et sa profondeur est celle des effets.
var _cursor: ActorCursor
## Emplacement de départ de chaque unité, relevé au montage : c'est là qu'elle
## revient après avoir frappé. Gardé ici plutôt que lu sur le sprite, dont la
## position est justement ce qui bouge.
var _home: Dictionary = {}
## Un retour visuel par unité (éclat + jauge), monté une fois pour toutes.
var _feedback: Dictionary = {}

func setup(
	allies: Array[Dictionary], enemies: Array[Dictionary], effects: Node2D,
	rhythm: RhythmBar, banner: ActionBanner,
) -> void:
	_allies = allies
	_enemies = enemies
	_effects = effects
	_rhythm = rhythm
	_banner = banner
	for entry in _allies + _enemies:
		var unit := _unit_of(entry)
		_home[unit] = _node_of(entry).position
		var feedback: Node2D = HitFeedback.new()
		_effects.add_child(feedback)
		feedback.setup(_node_of(entry))
		_feedback[unit] = feedback
	_cursor = ActorCursor.new()
	_effects.add_child(_cursor)

## ──────────────────────────────────────────────────────────────────────────
##  DÉROULEMENT
## ──────────────────────────────────────────────────────────────────────────

func run() -> void:
	_rhythm.open()
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
	_rhythm.close()
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
	var ally_acts := _allies.has(entry)
	# Annoncée dès le départ : la maquette montre la pastille déjà en place
	# pendant que l'attaquant se déplace, avant même la première note.
	_banner.show_action(
		_text_id_of(unit, action), ally_acts, String(_definition_of(unit, action).get("damage_type", ""))
	)
	# Relevés une fois pour toute l'action : `_cue()` en sert plusieurs moments.
	var sounds := _sounds_of(unit, action)
	_cue(sounds, "announce")

	# LE RYTHME D'ABORD, ET L'UNITÉ NE BOUGE PAS ENCORE. Elle reste à son
	# emplacement le temps de la séquence : le joueur a les yeux sur la barre, un
	# personnage qui traverse le terrain au même moment lui dispute son
	# attention. Le déplacement ne part qu'une fois le dernier verdict tombé.
	#
	# Le geste, lui, vient APRÈS le rythme et pas pendant : il ne boucle pas, le
	# tenir le temps de trois notes figerait le personnage bras levé. Le verdict
	# restant affiché une demi-seconde, il se lit encore au moment de l'impact,
	# comme sur la maquette.
	var multiplier := await _run_rhythm(unit, action, ally_acts, sounds)
	effect["multiplier"] = multiplier

	# Aller au contact, frapper, revenir. Une action qui SOIGNE ne se déplace
	# pas : elle n'a personne à aller chercher, et traverser le terrain pour
	# tendre une potion se lirait comme une charge.
	if offensive:
		# Le terrain glisse VERS LA CIBLE en même temps que l'attaquant s'élance :
		# sur les maquettes, la vignette où il est au contact est aussi celle où
		# le décor a bougé.
		field_shift.emit(1 if ally_acts else -1)
		_cue(sounds, "approach")
		await _approach(entry, targets)

	_cue(sounds, "gesture")
	await _play_gesture(entry, targets, gesture, offensive)

	for target in targets:
		# Relevé AVANT le coup : c'est le point de départ de l'animation de
		# jauge, et il n'est plus lisible une fois les PV appliqués.
		var before := target.solid_ratio()
		_apply(unit, target, effect)
		if offensive:
			_feedback[target].hit(target, before, bool(effect["injury"]))
	changed.emit()
	# Une seule fois pour l'action, pas une par cible : une attaque de groupe
	# est UN geste, et trois exemplaires du même cri superposés ne feraient que
	# saturer. Hors du `if offensive` : un soin a droit au sien.
	_cue(sounds, "hit")
	if offensive:
		impact.emit()

	await _finish_gesture(entry, gesture)
	if offensive:
		field_shift.emit(0)
		_cue(sounds, "return")
		await _return_home(entry)
	else:
		_node_of(entry).play_sheet(BattleData.get_animation(unit.id, "idle"))
	_rhythm.rest()
	_banner.hide_action()
	await _bury_the_dead()

## Fait jouer la séquence de l'action et en tire le multiplicateur de dégâts.
##
## LE SENS S'INVERSE SELON LE CAMP, et c'est toute la mécanique : quand l'équipe
## frappe, un bon timing AUGMENTE ce qu'elle inflige ; quand elle encaisse, il
## RÉDUIT ce qu'elle subit. La barre est la même, la table de conversion non
## (cf. BattleRules).
func _run_rhythm(
	unit: BattleUnit, action: Dictionary, ally_acts: bool, sounds: Array
) -> float:
	var sequence := _sequence_of(unit, action)
	if sequence.is_empty():
		return 1.0
	# Le son du rythme est annoncé ICI et pas chez l'appelant : une action sans
	# séquence sort à la ligne précédente, et son « rhythm » ne doit pas sonner
	# sur une barre qui ne se joue jamais.
	_cue(sounds, "rhythm")
	# Le curseur dit QUI joue : pendant la séquence, le joueur a les yeux sur la
	# barre, et l'unité n'a pas encore bougé.
	_cursor.show_above(_sprite_of(unit))
	var judgements := await _rhythm.play(
		sequence, RhythmBar.Side.ALLY if ally_acts else RhythmBar.Side.ENEMY
	)
	_cursor.hide_above()
	rhythm_resolved.emit(judgements)
	return (
		BattleRules.rhythm_attack(judgements) if ally_acts
		else BattleRules.rhythm_defence(judgements)
	)

## Identifiant Localization du nom affiché. Une attaque de base n'a pas d'entrée
## propre : elle reprend celle du menu, « Attack » — ce que montre d'ailleurs la
## maquette du tour ennemi.
func _text_id_of(unit: BattleUnit, action: Dictionary) -> String:
	var id := String(action.get("id", ""))
	match String(action.get("source", "attack")):
		"eko":
			return "eko.%s.name" % id
		"item":
			return "item.%s.name" % id
	return "battle.menu.attack"

## Suite de notes de l'action, prise là où sa définition vit — catalogue pour un
## Eko ou un objet, fiche de l'unité pour une attaque de base.
func _sequence_of(unit: BattleUnit, action: Dictionary) -> PackedStringArray:
	var sequence := PackedStringArray()
	for note in _definition_of(unit, action).get("sequence", []):
		sequence.append(String(note))
	return sequence

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
## MOMENTS DE L'ASSAUT auxquels un son peut s'accrocher (champ `at`). Ce sont
## des points RÉELS de `_resolve`, pas une liste de souhaits : chacun est un
## `_cue()` posé dans le déroulé ci-dessus.
##
## Deux d'entre eux sont CONDITIONNELS, et c'est assumé : « approach » et
## « return » n'existent que pour une action offensive (un soin ne traverse pas
## le terrain), « rhythm » que pour une action qui a une séquence. Un son
## accroché à un moment que son action n'atteint pas ne se joue jamais.
const SOUND_MOMENTS: PackedStringArray = [
	"announce",  # la pastille s'affiche, avant tout le reste
	"rhythm",    # la séquence de notes commence
	"approach",  # l'attaquant s'élance vers sa cible
	"gesture",   # le geste part
	"hit",       # l'effet s'applique — le DÉFAUT
	"return",    # l'attaquant repart vers son emplacement
]
const SOUND_DEFAULT_MOMENT := "hit"

const OWN_CAMP_TARGETS: PackedStringArray = ["ally", "allies", "self"]

## Camp visé par un mode de ciblage, du point de vue de `entry`.
func _camp_for(entry: Dictionary, kind: String) -> Array[Dictionary]:
	var caster_is_ally := _allies.has(entry)
	var aims_at_own_camp := kind in OWN_CAMP_TARGETS
	return _allies if caster_is_ally == aims_at_own_camp else _enemies

## Ce que l'action inflige ou rend : {offensive, power, heal, damage_type}.
## Le tableau de bord de l'action, lu une fois pour toutes ses cibles.
## Sons de l'action, pris au même endroit que sa séquence et sa puissance : sur
## l'Eko ou l'objet pour une compétence, dans `basic_attack` pour une attaque.
## C'est ce qui permet de donner sa voix à un personnage sans écrire son nom
## dans le code.
##
## Renvoie une liste normalisée d'entrées `{at: String, paths: PackedStringArray}`.
## Le champ `sound` d'une entrée accepte UN chemin ou PLUSIEURS : plusieurs
## chemins sont des variantes du même son (`noah_att1/att2/att3`), tirées au
## hasard, pas des sons à jouer ensemble — pour ça, on met deux entrées.
func _sounds_of(unit: BattleUnit, action: Dictionary) -> Array:
	var sounds: Array = []
	for raw: Variant in _definition_of(unit, action).get("sounds", []):
		if typeof(raw) != TYPE_DICTIONARY:
			push_warning("Entrée de son mal formée sur %s : %s" % [unit.id, str(raw)])
			continue
		var entry: Dictionary = raw
		var moment := String(entry.get("at", SOUND_DEFAULT_MOMENT))
		if not SOUND_MOMENTS.has(moment):
			push_warning("Moment de son inconnu « %s » sur %s (cf. SOUND_MOMENTS)"
				% [moment, unit.id])
			continue
		var paths := PackedStringArray()
		var declared: Variant = entry.get("sound", "")
		# Un seul chemin ou une liste : l'auteur écrit le cas simple sans
		# crochets, l'éditeur web écrira des listes.
		for path: Variant in (declared if typeof(declared) == TYPE_ARRAY else [declared]):
			if String(path) != "":
				paths.append(String(path))
		if paths.is_empty():
			continue
		sounds.append({"at": moment, "paths": paths})
	return sounds

## Déclenche les sons accrochés à `moment`. Une entrée à plusieurs chemins tire
## une variante au hasard.
func _cue(sounds: Array, moment: String) -> void:
	for entry: Dictionary in sounds:
		if String(entry["at"]) != moment:
			continue
		var paths: PackedStringArray = entry["paths"]
		sound_cue.emit(paths[randi() % paths.size()])

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
		# Le timing pèse aussi sur les soins : l'auteur a voulu la barre sur
		# TOUTES les actions, objets compris, et un soin bien joué doit rendre
		# davantage. Un soin lancé par un ennemi passe, lui, par la table de
		# défense — bien jouer le prive donc d'une partie de ce qu'il se rend.
		var healed := roundi(int(effect["heal"]) * float(effect.get("multiplier", 1.0)))
		target.heal(healed)
		_pop_number(anchor, healed, DamageNumber.Kind.HEAL)
		return
	var amount := BattleRules.guarded(
		roundi(BattleRules.damage(int(effect["power"]), actor.force, target.defense)
			* float(effect.get("multiplier", 1.0))),
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
