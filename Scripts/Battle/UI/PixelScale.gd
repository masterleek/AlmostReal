extends RefCounted

## Rend nets les bords des éléments d'interface qui subissent une ROTATION.
##
## LE PROBLÈME. Le décor de combat est de la pixel-art 480×270 agrandie ×4 par
## le Stage, échantillonnée au plus proche voisin — ce qui est exactement ce
## qu'on veut tant que tout est aligné sur la grille. Mais les groupes
## d'interface sont inclinés de quelques degrés (cf. BattleScene), et là le
## plus proche voisin n'a plus rien à interpoler : le bord d'une pastille
## descend par marches de 4 px au lieu de suivre la diagonale. La maquette, sa
## rotation ayant été faite avec interpolation, montre au contraire un bord
## lissé.
##
## LA SOLUTION, la même que pour le texte (cf. BattleText.SUPERSAMPLE) : on
## amène la texture à la résolution de l'écran AVANT de la faire tourner. La
## texture est agrandie ×4 au plus proche voisin — donc sans inventer de
## détail, les gros pixels d'origine sont préservés tels quels — puis le nœud
## est contre-échelonné d'autant et repasse en filtrage linéaire. L'échelle
## cumulée vaut 1 : un pixel de texture = un pixel d'écran, et l'interpolation
## ne joue plus que là où elle sert, sur la diagonale du bord.
##
## CONVENTION. `position` reste en unités de design (elle s'exprime dans
## l'espace du parent, que l'échelle du nœud n'affecte pas). En revanche tout
## ce qui se mesure dans l'espace de la TEXTURE — `offset`, `size`,
## `region_rect`, marges de 9-slice — doit être multiplié par SCALE.

const SCALE := 4

## Les textures agrandies sont mises en cache : une même vignette sert à
## plusieurs nœuds, et le redimensionnement est un travail d'image inutile à
## refaire.
static var _cache: Dictionary = {}

## `smooth` change la façon d'agrandir, et le choix dépend de la NATURE de
## l'asset, pas d'un goût :
##
##   false (défaut) — plus proche voisin. Pour du vrai pixel-art, dont chaque
##     pixel est posé à la main : on veut le préserver tel quel, en gros blocs.
##
##   true — interpolation BILINÉAIRE. Pas Lanczos ni cubique : ces deux-là
##     dépassent aux transitions (overshoot) et éclaircissent le halo, ce qui
##     avait fait grossir des losanges d'AP au point de les souder entre eux.
##     Le bilinéaire n'invente aucune valeur plus vive que la source. Pour les
##     assets dessinés AVEC de l'anticrénelage — la plupart des icônes
##     d'interface du jeu (`ic_ap_on.png` a la moitié de ses pixels en alpha
##     partiel, `ic_ap_off.png` les deux tiers) — le plus proche voisin
##     transformerait ce dégradé en escalier de blocs : ça détruirait le
##     travail de l'auteur au lieu de le préserver.
##
## Pour trancher sur un asset donné : compter ses pixels à alpha partiel. S'ils
## sont nombreux et qu'il n'existe QUE sous forme de PNG, il attend
## `smooth = true`. S'il existe en vectoriel (SVG), la bonne réponse est
## souvent de ne pas passer par ici du tout : cf. `sprite_native()` plus bas.
static func upscaled(texture: Texture2D, smooth: bool = false) -> ImageTexture:
	var key := texture.resource_path if texture.resource_path != "" else str(texture.get_instance_id())
	key += "|smooth" if smooth else "|nearest"
	if _cache.has(key):
		return _cache[key]
	var image := texture.get_image()
	image.resize(
		image.get_width() * SCALE, image.get_height() * SCALE,
		Image.INTERPOLATE_BILINEAR if smooth else Image.INTERPOLATE_NEAREST,
	)
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result

## Sprite2D prêt à être posé dans un groupe incliné. `design_offset` est en
## unités de design ; `position` se règle ensuite normalement.
static func sprite(texture: Texture2D, design_offset: Vector2 = Vector2.ZERO, smooth: bool = false) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = upscaled(texture, smooth)
	node.centered = false
	node.offset = design_offset * SCALE
	apply(node)
	return node

## Applique la contre-échelle et le filtrage à un nœud dont on a déjà posé la
## texture agrandie (NinePatchRect, TextureProgressBar…).
static func apply(node: CanvasItem) -> void:
	node.scale = Vector2.ONE / float(SCALE)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

## ──────────────────────────────────────────────────────────────────────────
## ASSETS NATIVEMENT À LA RÉSOLUTION DE L'ÉCRAN (vectoriels)
## ──────────────────────────────────────────────────────────────────────────
##
## Un SVG importé avec `svg/scale = SCALE` dans son .import est rastérisé une
## fois pour toutes à la bonne résolution — Godot ne le fait pas au runtime.
## Contrairement à un PNG, il n'y a donc RIEN à agrandir : passer un tel asset
## par `upscaled()` l'agrandirait une seconde fois et le flouterait pour rien.
## `sprite_native()` saute cette étape et pose directement la texture, avec la
## même contre-échelle que le reste (l'échelle cumulée avec le Stage ×4 reste
## 1 : un pixel de texture = un pixel d'écran).

## Sprite2D pour une texture déjà à la résolution de l'écran.
static func sprite_native(texture: Texture2D, design_offset: Vector2 = Vector2.ZERO) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = texture
	node.centered = false
	node.offset = design_offset * SCALE
	apply(node)
	return node

## Taille de `texture` en unités de DESIGN, déduite de sa taille réelle — soit
## l'inverse de ce que fait `upscaled()` : au lieu d'agrandir un petit raster,
## on réduit une mesure prise sur un grand raster. Utile pour tout calcul de
## position qui doit rester en unités de design (centrage, pas entre deux
## icônes…) sans se soucier de la résolution native de l'asset.
static func design_size(texture: Texture2D) -> Vector2:
	return texture.get_size() / float(SCALE)
