class_name TileGeometry
extends RefCounted

## Géométrie liée au dessin réel des tuiles hexagonales (hex_tiles.png) —
## source unique partagée entre tout ce qui doit savoir "quelle est la vraie
## silhouette visuelle d'une tuile", indépendamment de qui s'en sert
## (détection de survol du curseur, découpe de l'ombre du Héros...). Avant
## l'extraction ici, ce polygone était recopié à la main dans WorldmapCursor.gd
## et dans chaque shader qui en avait besoin.
##
## Fonction plutôt que const : un const de type tableau ne se résout pas de
## façon fiable en accès inter-scripts (`TileGeometry.CONST`) sur cette
## version de Godot — la fonction, elle, fonctionne toujours. Le tableau est
## petit (6 points) et rarement demandé (survol de la souris, pas chaque
## frame), donc la réallouer à chaque appel est un coût négligeable.

## Forme réelle du dessin des tuiles (pas la hitzone logique de la grille,
## tile_size=64x44) : extraite pixel par pixel de hex_tiles.png. L'art est
## dessiné en 64x64 (plus haut que la grille) pour l'effet de bloc pseudo-3D.
static func tile_art_hitzone() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -32), Vector2(32, -17), Vector2(32, 17),
		Vector2(0, 32), Vector2(-32, 17), Vector2(-32, -17),
	])
