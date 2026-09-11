extends RefCounted

## Décide l'action d'un ennemi au moment où son tour arrive dans l'assaut.
##
## POURQUOI UN FICHIER À PART. Un ennemi n'a pas de phase de préparation : il
## faut bien que quelqu'un choisisse à sa place. Mais ce choix est de la donnée
## de jeu, pas de la mécanique — l'auteur veut pouvoir dire « celui-ci est
## agressif, celui-là s'acharne sur Noah » depuis l'éditeur web, sans toucher au
## code. Ce fichier est donc la traduction du bloc `behaviour` de `units.json`
## en une action de la même forme que celle qu'un allié retient au menu ; le
## reste du combat ne voit aucune différence entre les deux.
##
## CE QU'IL NE FAIT PAS : exécuter. Il rend un bon de commande
## ({source, id, target, targets}), que BattleAssault joue comme n'importe quel
## autre.

const BattleData = preload("res://Scripts/Battle/BattleData.gd")
const BattleUnit = preload("res://Scripts/Battle/BattleUnit.gd")

## Comportements reconnus. Un `kind` inconnu retombe sur KIND_RANDOM avec un
## avertissement : une faute de frappe dans units.json ne doit pas faire
## planter un combat, mais elle ne doit pas passer inaperçue non plus.
const KIND_RANDOM := "random"
const KIND_AGGRESSIVE := "aggressive"
const KIND_DEFENSIVE := "defensive"
const KIND_FOCUSED := "focused"
const KINDS: PackedStringArray = [
	KIND_RANDOM, KIND_AGGRESSIVE, KIND_DEFENSIVE, KIND_FOCUSED,
]

## Valeurs par défaut, choisies pour qu'un ennemi SANS bloc `behaviour` se
## comporte exactement comme avant l'introduction de ce fichier : il frappe un
## adversaire au hasard. Ajouter le champ change le comportement, l'omettre ne
## change rien.
const DEFAULT_KIND := KIND_RANDOM
## Fraction de PV sous laquelle un ennemi « defensive » se met en garde.
const DEFAULT_GUARD_BELOW := 0.35
## Probabilité qu'un ennemi lance un Eko plutôt que de frapper, quand il en
## connaît un qu'il peut payer. À 0 par défaut : un ennemi sans `eko_chance`
## déclaré ne lance rien, même si on lui donne une liste d'Ekos.
const DEFAULT_EKO_CHANCE := 0.0

## Action à jouer pour `unit`. `allies` = les unités DEBOUT de son propre camp,
## `foes` = celles d'en face. Les deux listes sont déjà filtrées : le
## comportement n'a pas à connaître les règles de survie.
static func choose(
	unit: BattleUnit, allies: Array[BattleUnit], foes: Array[BattleUnit]
) -> Dictionary:
	var behaviour: Dictionary = BattleData.get_unit(unit.id).get("behaviour", {})
	var kind := _kind_of(behaviour, unit.id)

	if kind == KIND_DEFENSIVE and unit.hp_ratio() < _guard_below(behaviour):
		return {"source": "guard", "target": "self", "cost": 0, "targets": [unit]}

	var eko := _pick_eko(unit, behaviour)
	if not eko.is_empty():
		var mode := String(BattleData.get_eko(eko["id"]).get("target", "enemy"))
		return {
			"source": "eko",
			"id": eko["id"],
			"target": mode,
			"cost": int(eko["cost"]),
			"targets": _targets_for(mode, unit, allies, foes, kind, behaviour),
		}

	return {
		"source": "attack",
		"target": "enemy",
		"cost": 0,
		"targets": _targets_for("enemy", unit, allies, foes, kind, behaviour),
	}

## ──────────────────────────────────────────────────────────────────────────

static func _kind_of(behaviour: Dictionary, unit_id: String) -> String:
	var kind := String(behaviour.get("kind", DEFAULT_KIND))
	if kind in KINDS:
		return kind
	push_warning(
		"EnemyBehaviour: comportement '%s' inconnu pour '%s', repli sur '%s'"
		% [kind, unit_id, DEFAULT_KIND]
	)
	return DEFAULT_KIND

static func _guard_below(behaviour: Dictionary) -> float:
	return float(behaviour.get("guard_below", DEFAULT_GUARD_BELOW))

## Eko tiré au sort parmi ceux que l'unité connaît ET peut payer. Rend {} si
## elle n'en lance pas ce tour-ci — ce qui est le cas par défaut.
static func _pick_eko(unit: BattleUnit, behaviour: Dictionary) -> Dictionary:
	if randf() >= float(behaviour.get("eko_chance", DEFAULT_EKO_CHANCE)):
		return {}
	var affordable: Array[Dictionary] = []
	for id in BattleData.get_unit_ekos(unit.id):
		var cost := int(BattleData.get_eko(id).get("ap_cost", 0))
		if unit.can_pay(cost):
			affordable.append({"id": id, "cost": cost})
	if affordable.is_empty():
		return {}
	return affordable[randi() % affordable.size()]

## Unités visées, selon le mode de ciblage de l'action ET le comportement.
##
## Le mode est RELATIF À CELUI QUI AGIT (cf. BattleAssault._camp_for) : « ally »
## désigne son propre camp, « enemy » celui d'en face. C'est ce qui permet à un
## ennemi d'utiliser le même catalogue d'Ekos que l'équipe, soin compris, sans
## qu'un « rosée » lancé par un cactoon aille soigner Noah.
##
## Le comportement ne départage que les ciblages UNITAIRES : sur un « enemies »
## il n'y a rien à choisir, tout le camp est pris.
static func _targets_for(
	mode: String, unit: BattleUnit,
	allies: Array[BattleUnit], foes: Array[BattleUnit],
	kind: String, behaviour: Dictionary,
) -> Array[BattleUnit]:
	match mode:
		"self":
			return [unit]
		"allies":
			return allies
		"enemies":
			return foes
		"ally":
			return _one(allies, kind, behaviour)
	return _one(foes, kind, behaviour)

## Une cible parmi `candidates`, choisie selon le comportement.
static func _one(
	candidates: Array[BattleUnit], kind: String, behaviour: Dictionary
) -> Array[BattleUnit]:
	if candidates.is_empty():
		return []
	match kind:
		KIND_AGGRESSIVE:
			# Achève : la cible la plus entamée EN PROPORTION de ses PV max,
			# pas en valeur absolue — sinon un personnage à gros réservoir
			# passerait pour le plus faible en permanence.
			return [_weakest_first(candidates)[0]]
		KIND_FOCUSED:
			var focus := String(behaviour.get("focus", ""))
			for candidate in candidates:
				if candidate.id == focus:
					return [candidate]
			# Sa cible de prédilection est tombée (ou n'est pas de ce combat) :
			# il frappe quand même, plutôt que de perdre son tour.
	return [candidates[randi() % candidates.size()]]

## Copie triée du plus entamé au plus intact. Copie : le tableau appartient à
## l'appelant, et l'ordre des camps a un sens ailleurs (les emplacements).
static func _weakest_first(units: Array[BattleUnit]) -> Array[BattleUnit]:
	var sorted := units.duplicate()
	sorted.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		return a.hp_ratio() < b.hp_ratio()
	)
	return sorted
