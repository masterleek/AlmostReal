extends RefCounted

## Accès aux données de combat (res://Battle/*.json).
##
## Même parti pris que map_loader.gd pour tile_meta.json : la donnée reste en
## JSON lu au runtime plutôt qu'en ressources .tres, pour rester éditable
## depuis MapEditor sans passer par l'éditeur Godot. Chargé une fois puis mis
## en cache statique — les mêmes définitions servent à toutes les unités d'un
## combat, il n'y a aucune raison de relire le fichier par unité.

const UNITS_PATH := "res://Battle/units.json"

static var _units: Dictionary = {}
static var _loaded: bool = false

## Définition complète d'une unité (stats + animations + portrait).
## Renvoie {} si l'id est inconnu : l'appelant décide quoi faire d'une unité
## manquante, plutôt que de recevoir une définition par défaut silencieuse qui
## masquerait une faute de frappe dans units.json.
static func get_unit(id: String) -> Dictionary:
	_ensure_loaded()
	if not _units.has(id):
		push_warning("BattleData: unité inconnue '%s'" % id)
		return {}
	return _units[id]

## Config d'animation prête à passer à UnitSprite.setup().
static func get_animation(unit_id: String, anim: String) -> Dictionary:
	return get_unit(unit_id).get("animations", {}).get(anim, {})

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(UNITS_PATH):
		push_warning("BattleData: fichier introuvable (%s)" % UNITS_PATH)
		return
	var file := FileAccess.open(UNITS_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null:
		push_warning("BattleData: JSON invalide (%s)" % UNITS_PATH)
		return
	_units = data.get("units", {})
