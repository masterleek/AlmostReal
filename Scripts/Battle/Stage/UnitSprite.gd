extends AnimatedSprite2D

## Sprite animé d'une unité de combat, construit à partir d'une planche en
## grille uniforme (N colonnes × M lignes, lecture ligne par ligne, dernière
## ligne éventuellement incomplète) décrite dans Battle/units.json.
##
## Pourquoi construire les SpriteFrames au runtime plutôt que de maintenir des
## .tres : les planches fournies vont de 4 à 26 frames et il y en a une par
## animation et par personnage. Les décrire en ressources sérialisées ferait
## des centaines de lignes de .tres à maintenir à la main pour une information
## qui tient en cinq nombres. Même raisonnement que map_loader.gd, qui lit ses
## animations de tuiles depuis tile_meta.json au lieu du système natif de
## TileSet.
##
## Une unité peut n'avoir qu'UNE frame (`frames: 1`) : elle est alors
## simplement figée dessus. C'est le cas des cactoons, dont la planche
## d'origine est une course — pas un repos — et qui doivent rester immobiles
## sur leur emplacement. Une animation peut aussi ne retenir qu'un EXTRAIT de
## sa planche (`first_frame`) : les planches d'attaque contiennent le geste
## entier, et l'écran de préparation n'en garde que la pose d'apprêt.
##
## ANCRAGE : `position` désigne le point « pieds » de l'unité, et `anchor` dit
## quel point de la CELLULE vient s'y poser — par défaut le centre-bas. C'est
## ce qui permet de décrire un emplacement de combat par un simple point au
## sol, indépendamment de la taille de cellule du personnage qui l'occupe — et
## de trier la profondeur sur ce même `position.y` via le Y-sort du parent.
##
## POURQUOI `anchor` EST PARFOIS EXPLICITE. Les planches d'un même personnage
## ne cadrent pas leur cellule pareil : entre `idle` et `standby`, l'ombre au
## sol de Noah se déplace de 11,5 px dans sa cellule. Laissées au centre-bas,
## les deux planches feraient sauter le personnage sur place en changeant
## d'état. `anchor` est donc relevé sur l'ELLIPSE D'OMBRE — le seul repère
## commun à toutes les planches, et la seule chose qui touche vraiment le sol
## — pour que le personnage reste immobile d'une planche à l'autre.
##
## IMPORTANT : on n'ajuste jamais le cadrage FRAME PAR FRAME sur la silhouette
## réelle. Le déplacement est encodé DANS la cellule (sur la planche d'atk
## d'Iris, le personnage traverse franchement sa cellule d'une frame à
## l'autre) : recadrer frame par frame supprimerait ce mouvement. L'ancrage
## ci-dessus est celui de la PLANCHE entière, il ne touche pas à ça — vérifié :
## sur les cinq planches en service, l'ombre ne bouge pas d'un pixel d'une
## frame à l'autre.

## Emplacement au sol et orientation, retenus pour pouvoir changer de planche
## sans les redemander (cf. set_animation).
var _feet := Vector2i.ZERO
var _mirrored := false

## Construit les SpriteFrames d'une planche en grille. Statique et sans effet
## de bord : réutilisable pour n'importe quelle planche du projet, y compris
## hors combat. `first_frame` saute le début de la planche.
static func build_frames(
	texture: Texture2D, columns: int, rows: int, frame_count: int, fps: float,
	first_frame: int = 0
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", fps)
	frames.set_animation_loop("default", true)
	var cell := Vector2i(texture.get_width() / columns, texture.get_height() / rows)
	for i in range(first_frame, first_frame + frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(i % columns, i / columns) * Vector2(cell), Vector2(cell))
		frames.add_frame("default", atlas)
	return frames

## `config` = bloc "animations.<nom>" de units.json.
## `feet` = point au sol en unités de design ; `mirrored` retourne le sprite
## horizontalement (les ennemis regardent l'équipe, cf. plan §4).
func setup(config: Dictionary, feet: Vector2i, mirrored: bool = false) -> void:
	_feet = feet
	_mirrored = mirrored
	var texture: Texture2D = load(config["sheet"])
	var columns: int = int(config.get("columns", 1))
	var rows: int = int(config.get("rows", 1))
	sprite_frames = build_frames(
		texture, columns, rows,
		int(config.get("frames", columns * rows)),
		float(config.get("fps", 6)),
		int(config.get("first_frame", 0)),
	)
	# centered = false + offset explicite plutôt que centered = true : la
	# cellule peut avoir une largeur impaire, et le centrage automatique
	# placerait alors la texture sur un demi-pixel — ce qui, une fois le Stage
	# agrandi ×4, produit une texture floue décalée de 2 px à l'écran.
	var cell := Vector2i(texture.get_width() / columns, texture.get_height() / rows)
	centered = false
	offset = -_anchor(config, cell)
	position = Vector2(feet)
	flip_h = mirrored
	play("default")

## Change de planche sans toucher à l'emplacement ni à l'orientation. C'est ce
## qui permet à l'écran de combat de faire passer un allié de `idle` à
## `atkeff` ou `standby` sans rejouer le placement.
##
## Surtout PAS `set_animation` : AnimatedSprite2D a déjà une méthode de ce nom
## (l'accesseur de sa propriété `animation`, qui prend un StringName), et la
## redéfinir avec une autre signature est refusé au chargement du script.
func play_sheet(config: Dictionary) -> void:
	if config.is_empty():
		return
	setup(config, _feet, _mirrored)

## Point de la cellule qui vient se poser sur `feet`, en unités de design.
## Défaut : centre-bas. `int()` plutôt qu'une division flottante — un
## demi-pixel de design devient 2 px de flou une fois le Stage agrandi ×4.
func _anchor(config: Dictionary, cell: Vector2i) -> Vector2:
	var declared: Array = config.get("anchor", [])
	if declared.size() == 2:
		return Vector2(int(declared[0]), int(declared[1]))
	return Vector2(int(cell.x / 2.0), cell.y)

## Décale la phase de l'animation pour que plusieurs unités partageant la même
## planche ne bougent pas à l'unisson. `ratio` ∈ [0,1[ = fraction du cycle.
func offset_phase(ratio: float) -> void:
	var count := sprite_frames.get_frame_count("default")
	if count <= 1:
		return
	set_frame_and_progress(int(ratio * count) % count, 0.0)
