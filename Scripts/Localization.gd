extends Node

## Catalogue de textes localisés (Localization/texts.json), édité depuis la
## page "Textes" de l'outil MapEditor. Autoload : état global indépendant de
## la scène affichée, comme PlayerCurrency/AudioMute — n'importe quel script
## UI a besoin d'y accéder.
##
## Chaque traduction stockée est du BBCode brut, consommé tel quel par un
## RichTextLabel (bbcode_enabled = true) : pas de couche d'abstraction
## séparée entre l'éditeur web (qui écrit le BBCode dans la textarea) et le
## rendu en jeu.

signal language_changed(new_language: String)

const TEXTS_PATH := "res://Localization/texts.json"

var current_language: String = "en"
var _default_language: String = "en"
var _entries: Dictionary = {} # id (String) -> entrée complète (Dictionary)

func _ready() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(TEXTS_PATH):
		push_warning("Localization: fichier introuvable (%s)" % TEXTS_PATH)
		return
	var file := FileAccess.open(TEXTS_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null:
		push_warning("Localization: JSON invalide (%s)" % TEXTS_PATH)
		return
	_default_language = data.get("default_language", "en")
	current_language = _default_language
	_entries.clear()
	for entry: Dictionary in data.get("texts", []):
		_entries[entry["id"]] = entry

## Traduction (BBCode brut) de `id` dans la langue courante, avec repli sur
## default_language si absente — puis sur "[id]" si l'id lui-même est
## introuvable (erreur visible plutôt que texte vide silencieux).
func get_text(id: String) -> String:
	var entry: Dictionary = _entries.get(id, {})
	var translations: Dictionary = entry.get("translations", {})
	if translations.has(current_language):
		return translations[current_language]
	if translations.has(_default_language):
		return translations[_default_language]
	return "[%s]" % id

func get_font_size(id: String) -> int:
	var entry: Dictionary = _entries.get(id, {})
	return int(entry.get("style", {}).get("font_size", 16))

func set_language(lang: String) -> void:
	if lang == current_language:
		return
	current_language = lang
	language_changed.emit(lang)
