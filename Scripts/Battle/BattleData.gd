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

## MOMENTS DE VOIX D'UNE UNITÉ — le pendant de `SOUND_MOMENTS`
## (BattleAssault.gd) pour les sons qui appartiennent au PERSONNAGE et non à
## l'action qu'il joue.
##
## POURQUOI DEUX LISTES ET PAS UNE. Un son d'action se lit sur la définition de
## l'action (`basic_attack`, un Eko, un objet) et se déclenche pendant l'assaut :
## c'est l'attaquant qui parle, aux six points de son geste. Ceux-ci se lisent
## sur l'UNITÉ, et certains n'ont aucun geste derrière eux — encaisser un coup,
## prendre la main au menu. Les mélanger obligerait chaque liste déroulante de
## l'éditeur à proposer des moments que son entrée ne peut pas atteindre, et le
## moteur à chercher une voix de blessé dans la fiche de celui qui frappe.
##
## Les commentaires de fin de ligne sont LUS par la page « Combat » du
## MapEditor, qui en fait ses infobulles : les écrire ici, c'est les tenir à
## jour là-bas.
const UNIT_SOUNDS: PackedStringArray = [
	"turn",         # l'unité prend la main : son menu s'ouvre
	"menu_attack",  # elle retient « Attack » et passe au ciblage
	"menu_eko",     # elle ouvre sa liste d'Ekos
	"menu_items",   # elle ouvre le sac
	"menu_guard",   # elle se met en garde — retenu sans ciblage
	"hurt",         # elle ENCAISSE des dégâts, quel que soit qui frappe
	"victory",      # le dernier ennemi est tombé : elle commente la victoire
]

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

## SONS — normalisation commune aux deux familles. `allowed` est le vocabulaire
## qui s'applique (SOUND_MOMENTS pour une action, UNIT_SOUNDS pour une unité), et
## `owner` ne sert qu'aux avertissements.
##
## Rend des entrées `{at: String, paths: PackedStringArray}`. Le champ `sound`
## accepte UN chemin ou PLUSIEURS : plusieurs chemins sont des variantes du même
## son (noah_att1/att2/att3) tirées au hasard, pas des sons joués ensemble —
## pour ça, on met deux entrées.
##
## Un moment hors vocabulaire est ÉCARTÉ AVEC UN AVERTISSEMENT plutôt qu'accepté
## en silence : un `at` inventé donnerait un son qui ne part jamais, découvert
## seulement le jour où quelqu'un joue ce combat-là.
## `fallback` est le moment retenu quand l'entrée n'en déclare pas. Il est
## EXPLICITE et non déduit de `allowed` : celui des actions est « hit » (le coup
## qui porte), qui n'est pas le premier de sa liste, et le déduire changerait en
## silence le sens des entrées déjà écrites. Vide = pas de défaut, l'entrée est
## alors écartée avec un avertissement.
static func sounds_of(
	definition: Dictionary, allowed: PackedStringArray, owner: String,
	fallback: String = "",
) -> Array:
	var sounds: Array = []
	for raw: Variant in definition.get("sounds", []):
		if typeof(raw) != TYPE_DICTIONARY:
			push_warning("Entrée de son mal formée sur %s : %s" % [owner, str(raw)])
			continue
		var entry: Dictionary = raw
		var moment := String(entry.get("at", fallback))
		if moment == "":
			push_warning("Entrée de son sans « at » sur %s : %s" % [owner, str(entry)])
			continue
		if not allowed.has(moment):
			push_warning("Moment de son inconnu « %s » sur %s" % [moment, owner])
			continue
		var paths := PackedStringArray()
		var declared: Variant = entry.get("sound", "")
		for path: Variant in (declared if typeof(declared) == TYPE_ARRAY else [declared]):
			if String(path) != "":
				paths.append(String(path))
		if paths.is_empty():
			continue
		sounds.append({"at": moment, "paths": paths})
	return sounds

## Les sons propres à une unité, par opposition à ceux de ses actions.
static func unit_sounds(unit_id: String) -> Array:
	return sounds_of(get_unit(unit_id), UNIT_SOUNDS, unit_id)

## Un chemin tiré au sort parmi les variantes accrochées à `moment`, ou "" s'il
## n'y en a pas. Le tirage vit ici, avec la règle qu'il applique, plutôt que
## recopié chez chaque appelant.
static func pick(sounds: Array, moment: String) -> String:
	for entry: Dictionary in sounds:
		if String(entry["at"]) != moment:
			continue
		var paths: PackedStringArray = entry["paths"]
		return paths[randi() % paths.size()]
	return ""

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
