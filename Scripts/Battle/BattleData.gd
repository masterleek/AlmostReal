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
