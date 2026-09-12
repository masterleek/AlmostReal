extends RefCounted

## Accès aux données de combat (res://Battle/*.json).
##
## Même parti pris que map_loader.gd pour tile_meta.json : la donnée reste en
## JSON lu au runtime plutôt qu'en ressources .tres, pour rester éditable
## depuis MapEditor sans passer par l'éditeur Godot. Chargé une fois puis mis
## en cache statique — les mêmes définitions servent à toutes les unités d'un
## combat, il n'y a aucune raison de relire le fichier par unité.
##
## Les trois catalogues (unités, Ekos, objets) suivent la même forme — un objet
## racine contenant un dictionnaire nommé — donc un seul chargeur paramétré les
## sert tous, plutôt que trois copies de la même lecture de fichier.

## SOURCES D'ACTION — le vocabulaire fermé du champ `source`, partagé par la
## préparation (qui le pose), l'assaut (qui l'exécute) et le comportement ennemi
## (qui en fabrique). Des constantes plutôt que des chaînes nues recopiées d'un
## fichier à l'autre : une faute de frappe ne lève aucune erreur, elle tombe
## dans la branche par défaut d'un `match` et l'action ne fait rien, en silence.
const SOURCE_ATTACK := "attack"
const SOURCE_EKO := "eko"
const SOURCE_ITEM := "item"
const SOURCE_GUARD := "guard"

const UNITS_PATH := "res://Battle/units.json"
const EKOS_PATH := "res://Battle/ekos.json"
const ITEMS_PATH := "res://Battle/items.json"

## Catalogues déjà lus, indexés par chemin de fichier.
static var _cache: Dictionary = {}

## Définition complète d'une unité (stats + animations + portrait + Ekos
## connus). Renvoie {} si l'id est inconnu : l'appelant décide quoi faire d'une
## unité manquante, plutôt que de recevoir une définition par défaut
## silencieuse qui masquerait une faute de frappe dans units.json.
static func get_unit(id: String) -> Dictionary:
	return _entry(UNITS_PATH, "units", id)

## Définition d'un Eko : coût en PA, mode de ciblage, puissance ou soin,
## séquence de touches du rythme.
static func get_eko(id: String) -> Dictionary:
	return _entry(EKOS_PATH, "ekos", id)

## Définition d'un objet utilisable en combat. Ce que l'équipe en PORTE n'est
## pas ici : c'est un état de partie, pas une définition.
static func get_item(id: String) -> Dictionary:
	return _entry(ITEMS_PATH, "items", id)

## Définition chiffrée d'une action, prise dans le catalogue qui la décrit.
## L'attaque de base n'a pas de catalogue : elle vit dans la fiche de l'unité
## (`basic_attack`), pour qu'un ennemi comme un allié frappe avec sa propre
## puissance.
##
## UN SEUL ENDROIT connaît cette règle. La préparation et l'assaut la lisaient
## chacun de leur côté ; deux copies d'une même règle finissent par diverger, et
## celle-ci décide d'où viennent la puissance, la séquence et les sons.
static func definition_of(unit_id: String, action: Dictionary) -> Dictionary:
	var id := String(action.get("id", ""))
	match String(action.get("source", SOURCE_ATTACK)):
		SOURCE_EKO:
			return get_eko(id)
		SOURCE_ITEM:
			return get_item(id)
	return get_unit(unit_id).get("basic_attack", {})

## MODES DE CIBLAGE. Deux prédicats plutôt que deux tableaux exposés : l'appelant
## pose une QUESTION (« est-ce que ça vise mon camp ? ») au lieu d'aller chercher
## une liste et d'écrire lui-même le `in`. La liste reste ainsi interne, et les
## deux lectures possibles du même mode tiennent dans la documentation d'un seul
## endroit.
##
## Le mode se lit RELATIVEMENT À CELUI QUI AGIT : « ally » désigne son propre
## camp, « enemy » celui d'en face. C'est ce qui permet aux deux camps de
## partager un seul catalogue d'Ekos — un soin déclaré « ally » soigne le camp
## de qui le lance, sans qu'il faille deux versions de chaque compétence.
static func targets_own_camp(mode: String) -> bool:
	return mode in ["ally", "allies", "self"]

## Modes qui prennent tout un camp d'un bloc, sans choix individuel. « self » en
## fait partie : il n'y a rien à choisir, mais la cible s'allume quand même pour
## dire sur qui ça porte.
static func targets_whole_camp(mode: String) -> bool:
	return mode in ["enemies", "allies", "self"]

## Config d'animation prête à passer à UnitSprite.setup().
static func get_animation(unit_id: String, anim: String) -> Dictionary:
	return get_unit(unit_id).get("animations", {}).get(anim, {})

## Ids des Ekos connus d'une unité, dans l'ordre où ils s'affichent.
static func get_unit_ekos(unit_id: String) -> PackedStringArray:
	var ekos := PackedStringArray()
	for id: String in get_unit(unit_id).get("ekos", []):
		ekos.append(id)
	return ekos

static func _entry(path: String, section: String, id: String) -> Dictionary:
	var catalogue := _catalogue(path, section)
	if not catalogue.has(id):
		push_warning("BattleData: '%s' absent de %s" % [id, path])
		return {}
	return catalogue[id]

static func _catalogue(path: String, section: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	# Mis en cache même en cas d'échec : sans ça, un fichier manquant ferait
	# relire le disque et réémettre l'avertissement à chaque accès.
	var catalogue: Dictionary = {}
	_cache[path] = catalogue
	if not FileAccess.file_exists(path):
		push_warning("BattleData: fichier introuvable (%s)" % path)
		return catalogue
	var file := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null:
		push_warning("BattleData: JSON invalide (%s)" % path)
		return catalogue
	catalogue.merge(data.get(section, {}))
	return catalogue
