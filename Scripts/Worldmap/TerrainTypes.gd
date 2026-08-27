class_name TerrainTypes
extends RefCounted

## Noms de terrain_type (custom_data du TileSet, cf tile_meta.json côté
## MapEditor) que du code de gameplay a besoin de reconnaître spécifiquement
## — "empty1" pour l'instant. Seul point à mettre à jour si ce nom change ou
## si un synonyme (ex. un futur "empty2") doit être traité pareil.

static func is_empty(terrain_type: String) -> bool:
	return terrain_type == "empty1"
