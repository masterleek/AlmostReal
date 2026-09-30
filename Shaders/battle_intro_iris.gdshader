shader_type canvas_item;

// Voile d'ouverture du combat (BackgroundDim) : au lieu d'apparaître d'un
// bloc, il se referme en HEXAGONE sur le point de focale du combat (le centre
// de la plateforme) — la même silhouette que les tuiles du worldmap (cf.
// Scripts/Worldmap/TileGeometry.gd, tile_art_hitzone() ; demandé, « similaire
// aux tiles hexagonales de la worldmap »), pointu en haut/bas, plat à gauche/
// droite — d'abord juste les coins de l'écran dans l'ombre, puis un hexagone
// qui rétrécit autour du combattant, jusqu'à avaler tout l'écran. `radius`
// s'anime en GDScript (cf BattleIntro._close_iris) du plus grand que la
// diagonale de l'écran (rien d'assombri) jusqu'à 0 (tout assombri — l'état de
// repos).
//
// `center`/`radius` sont en PIXELS DE DESIGN (ceux de `rect_size`, cf. plus
// bas) — PAS en FRAGCOORD (essayé, CASSÉ : constaté en jeu, hexagone décalé
// du Héros dès que la fenêtre réelle ne fait pas pile 1920×1080, typique du
// panneau de jeu intégré à l'éditeur). `canvas_transform` (utilisé par
// BattleLauncher pour calculer le focus) travaille dans l'espace VIRTUEL du
// projet (1920×1080, `window/size/viewport_*`), qui ne coïncide avec
// FRAGCOORD (pixels RÉELS de la fenêtre) que si la fenêtre fait justement
// cette taille — un CanvasLayer n'est pas remis à l'échelle comme le reste de
// la scène 2D. `UV * rect_size`, lui, reconstruit une coordonnée dans ce
// MÊME espace virtuel quelle que soit la taille réelle de la fenêtre, UV
// étant toujours relatif au rectangle du nœud, jamais à la fenêtre.
uniform vec2 center = vec2(960.0, 540.0);
uniform float radius = 2000.0;
// Bord NET (demandé, « enlève le blur ») : pas 0 pile — `smoothstep` avec des
// bornes égales est indéfini en GLSL (division par zéro dans son propre
// calcul) — mais assez petit pour ne laisser qu'un antialiasing d'un-deux
// pixels sur les arêtes obliques de l'hexagone, pas un halo visible.
uniform float feather = 1.5;
uniform vec4 dim_color = vec4(0.0, 0.0, 0.0, 0.5);
// Taille de BackgroundDim en pixels de design (cf. BattleScene._ready,
// `background_dim.size`) — posée depuis GDScript plutôt que supposée ici : ce
// shader n'a pas à connaître DESIGN_SIZE/STAGE_SCALE.
uniform vec2 rect_size = vec2(1920.0, 1080.0);

// Proportions de l'hexagone (PAS un hexagone régulier — même silhouette
// étirée verticalement que l'art du worldmap, « effet de bloc pseudo-3D »,
// cf. TileGeometry.tile_art_hitzone()) : à l'échelle HALF_WIDTH, le sommet
// haut/bas tombe à (0, ±HALF_WIDTH) et les arêtes verticales à x = ±HALF_WIDTH
// de y = -EDGE_HALF_HEIGHT à EDGE_HALF_HEIGHT.
const float HALF_WIDTH = 32.0;
const float EDGE_HALF_HEIGHT = 17.0;

void fragment() {
	vec2 pixel = UV * rect_size;
	vec2 p = abs(pixel - center);
	// « Distance » hexagonale homogène (degré 1, comme length() pour un
	// cercle) : le plus grand des deux termes vaut HALF_WIDTH exactement sur
	// le contour de l'hexagone à cette échelle — l'un porte la contrainte des
	// arêtes verticales, l'autre celle des arêtes obliques vers les sommets.
	// Mis à l'échelle de `radius` (qui remplace HALF_WIDTH), un fragment à
	// `dist` de `center` tombe donc pile sur le contour d'un hexagone
	// identique agrandi/réduit à cette taille.
	float dist = max(p.x, ((HALF_WIDTH - EDGE_HALF_HEIGHT) * p.x + HALF_WIDTH * p.y) / HALF_WIDTH);
	COLOR = dim_color;
	COLOR.a *= smoothstep(radius - feather, radius + feather, dist);
}
