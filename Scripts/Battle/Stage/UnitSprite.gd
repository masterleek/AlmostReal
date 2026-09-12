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

## Planche actuellement montée. Publique, et c'est délibéré : elle dit ce que le
## sprite joue VRAIMENT, ce qu'un état mis en cache ailleurs finirait par
## contredire — la phase d'assaut change de planche dans le dos de l'écran qui
## pilote les poses.
var sheet_path: String = ""

## Construit les SpriteFrames d'une planche en grille. Statique et sans effet
## de bord : réutilisable pour n'importe quelle planche du projet, y compris
## hors combat. `first_frame` saute le début de la planche.
static func build_frames(
	texture: Texture2D, columns: int, rows: int, frame_count: int, fps: float,
	first_frame: int = 0, loop: bool = true
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", fps)
	frames.set_animation_loop("default", loop)
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
func setup(config: Dictionary, feet: Vector2i, mirrored: bool = false, loop: bool = true) -> void:
	_feet = feet
	_mirrored = mirrored
	sheet_path = String(config["sheet"])
	var texture: Texture2D = load(sheet_path)
	var columns: int = int(config.get("columns", 1))
	var rows: int = int(config.get("rows", 1))
	sprite_frames = build_frames(
		texture, columns, rows,
		int(config.get("frames", columns * rows)),
		float(config.get("fps", 6)),
		int(config.get("first_frame", 0)),
		loop,
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
##
## `loop = false` sert aux planches qui se JOUENT une fois — un geste d'attaque
## n'est pas un repos. La durée d'une telle planche se déduit alors de ses
## propres données (`duration_of`), sans avoir à guetter un signal.
func play_sheet(config: Dictionary, loop: bool = true) -> void:
	if config.is_empty():
		return
	# La POSITION COURANTE survit au changement de planche. `setup()` repose
	# l'unité sur son emplacement, ce qui est juste au montage et faux partout
	# ailleurs : pendant l'assaut l'unité quitte son emplacement pour aller au
	# contact, et changer de planche en chemin la téléportait chez elle au
	# milieu du déplacement. Seul `offset` doit suivre la nouvelle planche —
	# c'est lui qui porte l'ancrage, et il change bien d'une planche à l'autre.
	var where := position
	setup(config, _feet, _mirrored, loop)
	position = where

## Durée d'une planche en secondes, déduite de son nombre de frames et de sa
## cadence. Sert à séquencer un geste sans dépendre de `animation_finished` :
## l'environnement de debug tourne à une cadence irrégulière (cf. CLAUDE.md
## §workflow, point 4), une attente en secondes est reproductible là où un
## comptage de frames ne l'est pas.
static func duration_of(config: Dictionary) -> float:
	var fps: float = maxf(1.0, float(config.get("fps", 6)))
	return float(config.get("frames", 1)) / fps

## Instant, dans cette même durée, où le coup PORTE — c'est là que les dégâts
## s'appliquent et que le nombre apparaît. Déclaré par planche (`hit_frame`,
## relevé sur la frame où la lame ou le tir part) ; à défaut, le milieu du
## geste, qui est le compromis le moins faux.
static func hit_time_of(config: Dictionary) -> float:
	var fps: float = maxf(1.0, float(config.get("fps", 6)))
	var frames: int = int(config.get("frames", 1))
	return float(config.get("hit_frame", frames / 2.0)) / fps

## Point de la cellule qui vient se poser sur `feet`, en unités de design.
## Défaut : centre-bas. `int()` plutôt qu'une division flottante — un
## demi-pixel de design devient 2 px de flou une fois le Stage agrandi ×4.
func _anchor(config: Dictionary, cell: Vector2i) -> Vector2:
	var declared: Array = config.get("anchor", [])
	if declared.size() == 2:
		return Vector2(int(declared[0]), int(declared[1]))
	return Vector2(int(cell.x / 2.0), cell.y)

## Centre du DESSIN, dans les coordonnées du parent.
##
## Ni `position`, qui est le point au SOL, ni le centre de la cellule : une
## planche peut être bien plus large que le personnage. Celle du geste d'attaque
## de Noah réserve la place de l'arc de lame, et la pose de visée qu'on en
## extrait y est décalée de 11 px — cadrer sur le milieu de la cellule mettrait
## le personnage à côté du centre de l'écran.
##
## Mesuré sur les pixels réellement dessinés, et mis en cache par planche : lire
## l'image d'une texture est cher, et une planche donnée a toujours le même
## cadrage utile.
static var _art_rects: Dictionary = {}

func art_centre() -> Vector2:
	var rect := _used_rect()
	var centre := Vector2(rect.position) + Vector2(rect.size) * 0.5
	# `flip_h` ne DÉPLACE pas le nœud : il miroite la texture à l'intérieur de
	# la cellule. Le rect utile, lui, est mesuré sur la planche telle qu'elle
	# est dessinée — donc du mauvais côté pour un ennemi, qui est retourné.
	# Sans ce repli, un personnage décentré dans sa cellule verrait son centre
	# calculé à l'opposé du dessin qu'on voit à l'écran.
	if flip_h:
		centre.x = _cell_size().x - centre.x
	return position + offset + centre

## Taille de cellule de la planche montée. Lue sur la RÉGION d'atlas d'une
## frame, pas sur son image : la région est une simple propriété, là où lire
## l'image coûte un transfert depuis la texture.
func _cell_size() -> Vector2:
	var frame: Texture2D = sprite_frames.get_frame_texture("default", 0)
	return frame.get_size() if frame != null else Vector2.ZERO

func _used_rect() -> Rect2i:
	if _art_rects.has(sheet_path):
		return _art_rects[sheet_path]
	var rect := Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var frame: Texture2D = sprite_frames.get_frame_texture("default", 0)
	if frame != null:
		var image := frame.get_image()
		if image != null:
			var used := image.get_used_rect()
			# Une planche entièrement transparente rendrait un rect vide : on
			# retombe alors sur la cellule entière plutôt que sur un point.
			rect = used if used.size.x > 0 and used.size.y > 0 else Rect2i(
				Vector2i.ZERO, image.get_size()
			)
	_art_rects[sheet_path] = rect
	return rect

## Décale la phase de l'animation pour que plusieurs unités partageant la même
## planche ne bougent pas à l'unisson. `ratio` ∈ [0,1[ = fraction du cycle.
func offset_phase(ratio: float) -> void:
	var count := sprite_frames.get_frame_count("default")
	if count <= 1:
		return
	set_frame_and_progress(int(ratio * count) % count, 0.0)
