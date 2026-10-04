shader_type canvas_item;

// Rendu "fond marin peint" (bandes de couleur + roches + taches de lumière)
// — reproduit un tutoriel de peinture numérique fourni par l'utilisateur.
// Validé au préalable via un mockup Canvas/JS (bruit fractal + normalisation
// en RANG statistique + seuils dépendant de la profondeur) avant d'être
// transposé ici : un tri/rang par pixel est impossible en temps réel sur
// GPU (pas de vue globale de l'image dans un fragment shader), donc les
// seuils sont réglés à l'oeil sur des textures de bruit dédiées (une par
// échelle utilisée : shore/rock/mid/reflect_big/reflect_small/reflect_hole),
// échantillonnées en UV (0..1) * un multiplicateur de répétition — même
// convention que l'ancien shader (uv * water_texture_scale). La taille des
// taches suit donc la taille du rect porteur plutôt que rester fixe en
// pixels ; un premier essai en pixels monde (world_px = UV * map_size_px)
// s'est révélé peu prévisible : la fréquence propre de la texture de bruit
// domine largement le multiplicateur, donnant un grain bien plus fin que
// prévu quel que soit le multiplicateur choisi.
//
// Placé derrière tout le TileMapLayer (cf WaterReflection.gd, z_index -2).

uniform float level : hint_range(0.0, 1.0) = 0.0;

// Dégradé de bandes de couleur (sombre/loin -> clair/proche), déformé
// verticalement par un bruit lent ("shore") pour un contour organique
// plutôt que des bandes horizontales figées.
uniform sampler2D water_albedo_gradient : source_color, filter_linear;
uniform sampler2D shore_noise : repeat_enable;
uniform float shore_tiles = 1.2;
uniform float shore_warp : hint_range(0.0, 1.0) = 0.55;
uniform float shore_speed = 0.01;

// Roches : assombrit localement la bande sous-jacente (jamais une couleur
// plaquée) là où le bruit dépasse rock_threshold.
uniform sampler2D rock_noise : repeat_enable;
uniform float rock_tiles = 3.5;
uniform float rock_threshold : hint_range(0.0, 1.0) = 0.6;

// Second niveau de contour, plus fin, qui éclaircit légèrement (façon
// courbe de niveau) — indépendant des roches ci-dessus.
uniform sampler2D mid_noise : repeat_enable;
uniform float mid_tiles = 2.5;
uniform float mid_threshold_low : hint_range(0.0, 1.0) = 0.58;
uniform float mid_threshold_high : hint_range(0.0, 1.0) = 0.68;

// Reflets blancs : deux échelles de taches (grandes + petites) combinées en
// "ou", chacune avec un seuil qui varie linéairement du haut de la surface
// (uv.y = 0, dense) au bas (uv.y = 1, clairsemé) — cf *_thresh_top/bottom.
// reflect_hole_* troue les grandes taches pour un contour moins plein/rond.
uniform vec4 reflection_color : source_color = vec4(0.969, 0.941, 0.816, 1.0);
uniform sampler2D reflect_big_noise : repeat_enable;
uniform float reflect_big_tiles = 1.0;
uniform float reflect_big_thresh_top : hint_range(0.0, 1.0) = 0.6;
uniform float reflect_big_thresh_bottom : hint_range(0.0, 1.0) = 0.85;
uniform sampler2D reflect_small_noise : repeat_enable;
uniform float reflect_small_tiles = 4.0;
uniform float reflect_small_thresh_top : hint_range(0.0, 1.0) = 0.56;
uniform float reflect_small_thresh_bottom : hint_range(0.0, 1.0) = 0.82;
uniform sampler2D reflect_hole_noise : repeat_enable;
uniform float reflect_hole_tiles = 4.5;
uniform float reflect_hole_threshold : hint_range(0.0, 1.0) = 0.6;

// Dérive lente des taches de lumière (scintillement) — hole dérive comme big
// pour rester visuellement "attaché" (les trous suivent les taches plutôt
// que de glisser indépendamment), small dérive un peu plus vite pour un
// mouvement moins synchronisé/plus organique entre les deux échelles.
uniform float reflect_speed = 0.015;
uniform vec2 reflect_direction = vec2(1.0, 0.3);

// Déformation de domaine : distord la position d'échantillonnage des taches
// par un bruit indépendant AVANT de lire big/small/hole — casse les
// silhouettes trop rondes/lisses d'un simple bruit seuillé en formes plus
// torturées (façon côte/amibe, avec des tendons qui relient les taches),
// plutôt que des taches isolées bien circulaires. warp_strength = 0 revient
// au comportement d'avant (aucune distorsion).
uniform sampler2D reflect_warp_noise : repeat_enable;
uniform float reflect_warp_tiles = 1.4;
uniform float reflect_warp_strength = 0.35;

// Sillage sous le curseur en déplacement libre : une CHAÎNE D'ANNEAUX EMPILÉS
// le long de son trajet (cf WaterReflection.gd, qui sème un point dans
// wake_positions/wake_spawn_times tous les wake_min_spawn_distance px).
//
// Chaque anneau naît petit, grandit en vieillissant et se comporte comme un DISQUE
// posé au-dessus de ceux qui sont plus vieux : un anneau récent efface le trait
// des anciens qu'il recouvre, il ne reste visible que l'arc non recouvert de
// chacun (effet « ressort / bols empilés » de la référence). Les anneaux sont
// parcourus du plus ancien au plus récent (wake_head = indice du dernier semé
// dans le tampon circulaire) et chacun efface ce qui a déjà été dessiné sous son
// disque ; la bordure de l'effacement est douce et tombe sous son propre trait.
//
// Le trait est BLANC, de largeur IRRÉGULIÈRE (épaississements et zones fines le
// long de l'anneau, qui évoluent dans le temps) avec un rayon qui tremble, et une
// lueur de wake_color. Il reste blanc et net presque jusqu'au bout : la
// référence ne le fait ni pâlir ni scintiller. Un anneau vieux S'ÉRODE par ses
// extrémités : un masque FIXE le long de l'anneau (bruit lisse, propre à chaque
// anneau) est comparé à un seuil qui monte avec l'âge. Les arcs dont le masque
// reste au-dessus du seuil survivent, s'amincissent en pointe là où le seuil les
// rattrape (la largeur suit l'écart au seuil), s'effritent en quelques tirets,
// et le dernier à rester est un petit éclat : l'anneau se coupe en longs
// morceaux qui raccourcissent, il ne se pulvérise pas en points.
// wake_squash aplatit les cercles en ellipses (perspective en biais de l'eau).
const int WAKE_MAX = 32;
uniform vec2 wake_positions[WAKE_MAX];
uniform float wake_spawn_times[WAKE_MAX];
uniform int wake_head = 0;
uniform float wake_time = 0.0;
// Durée de vie d'un anneau, et rayon (px monde) à la naissance puis à la mort.
uniform float wake_lifetime = 0.7;
uniform float wake_radius_start = 15.0;
uniform float wake_radius = 27.0;
uniform float wake_squash : hint_range(0.1, 1.0) = 0.65;
// Épaisseur de base du trait (px monde) : l'épaisseur réelle varie de ~0,3 à
// ~1,5 fois cette valeur le long de l'anneau.
uniform float wake_line_width = 1.8;
// Lueur : couleur, largeur (px monde) et intensité.
uniform vec4 wake_color : source_color = vec4(0.3254902, 0.9764706, 1.0, 1.0);
uniform float wake_glow_width = 2.8;
uniform float wake_glow_strength : hint_range(0.0, 1.0) = 0.85;
// Distance (px monde) sur laquelle la lueur déborde le long de l'arc au-delà de
// l'endroit où le trait s'arrête : plus c'est grand, plus le bout est doux.
uniform float wake_glow_reach = 9.0;
// Part de la vie d'un anneau pendant laquelle il reste entier avant de s'éroder.
uniform float wake_erode_start : hint_range(0.0, 0.9) = 0.55;
// Nombre de bosses du masque d'érosion sur le tour : 2,5 donne 2 à 3 gros arcs
// qui survivent, plus donne des morceaux plus courts et plus nombreux.
uniform float wake_erode_scale = 2.5;
// Avancement de l'érosion (0..1) à partir duquel l'anneau s'éteint en fondu.
uniform float wake_fade_start : hint_range(0.0, 0.95) = 0.2;
// Amplitude du tremblement du rayon (px monde) et vitesse d'évolution du trait.
uniform float wake_jitter = 0.8;
uniform float wake_flicker_hz = 9.0;

// Paillettes spéculaires : points qui s'allument et s'éteignent, posés sur une
// grille en espace MONDE (elles restent donc attachées à l'eau quand la caméra
// bouge, contrairement à un motif en UV d'écran). Deux couches : une dense et
// fine, une rare et plus grosse. C'est cette seconde qui compte pour la passe
// HD-2D (hd2d_post.gdshader) : hors de la bande nette, un point brillant
// devient un disque de bokeh d'autant plus lisible qu'il est gros au départ.
// glint_strength = 0 coupe tout (aucun coût, rendu identique à avant).
// glint_bottom_fade : multiplicateur de densité au bas de la surface (uv.y = 1),
// 1 = uniforme ; < 1 concentre les paillettes vers le haut/loin, là où le
// soleil se reflète le plus (cf. captures d'Octopath Traveler 2).
uniform float glint_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glint_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
uniform float glint_speed = 1.6;
uniform float glint_bottom_fade : hint_range(0.0, 1.0) = 0.5;
uniform float glint_cell_small = 12.0;
uniform float glint_density_small : hint_range(0.0, 1.0) = 0.12;
uniform float glint_size_small = 1.0;
uniform float glint_cell_big = 36.0;
uniform float glint_density_big : hint_range(0.0, 1.0) = 0.07;
uniform float glint_size_big = 2.3;

varying vec2 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Bruit de valeur lisse (0..1). Échantillonné sur le CERCLE (cos, sin) pour que le
// trait d'un anneau soit continu en faisant le tour, sans raccord à 360°.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

// Une couche de paillettes. Le centre est jitteré dans la moitié centrale de sa
// cellule : le rayon (size_px) reste ainsi toujours à l'intérieur de la cellule,
// sans qu'il faille lire les 8 voisines. La forme est une ellipse aplatie
// (même perspective en biais que le reste de l'eau).
float glint_layer(vec2 wp, float cell_px, float density, float size_px, float seed) {
	vec2 cell = floor(wp / cell_px);
	float h = hash12(cell + seed);
	if (h > density) {
		return 0.0;
	}
	vec2 jitter = vec2(hash12(cell + seed + 17.0), hash12(cell + seed + 53.0));
	vec2 center = (cell + 0.25 + 0.5 * jitter) * cell_px;
	vec2 d = (wp - center) * vec2(1.0, 1.8);
	float tw = sin(TIME * glint_speed * (0.5 + h / density) + h * 40.0) * 0.5 + 0.5;
	tw = tw * tw * tw;
	return (1.0 - smoothstep(size_px * 0.6, size_px, length(d))) * tw;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = UV;
	if (uv.y >= level) {
		float shore = texture(shore_noise, uv * shore_tiles + vec2(TIME * shore_speed, 0.0)).x;
		float adjusted = clamp(uv.y + (shore - 0.5) * shore_warp, 0.0, 1.0);
		vec3 col = texture(water_albedo_gradient, vec2(adjusted, 0.5)).rgb;

		float rock = texture(rock_noise, uv * rock_tiles).x;
		if (rock > rock_threshold) {
			float d = clamp((rock - rock_threshold) / max(1.0 - rock_threshold, 0.001), 0.0, 1.0);
			col *= vec3(1.0 - 0.3 * d, 1.0 - 0.25 * d, 1.0 - 0.2 * d);
		}

		float mid = texture(mid_noise, uv * mid_tiles).x;
		if (mid > mid_threshold_low && mid < mid_threshold_high) {
			col *= vec3(0.88, 0.94, 0.96);
		}

		float wake_core = 0.0;
		float wake_glow = 0.0;
		float flick = TIME * wake_flicker_hz;
		// Du plus ancien au plus récent : chaque anneau efface ce qu'il recouvre.
		for (int k = 1; k <= WAKE_MAX; k++) {
			int i = (wake_head + k) % WAKE_MAX;
			float age = wake_time - wake_spawn_times[i];
			if (age < 0.0 || age > wake_lifetime) {
				continue;
			}
			vec2 diff = world_pos - wake_positions[i];
			diff.y /= wake_squash;
			float dist = length(diff);
			float u = age / wake_lifetime;
			// Croissance rapide puis qui ralentit (ease-out) : l'anneau « éclate »
			// à la naissance au lieu de grossir à vitesse constante.
			float r = mix(wake_radius_start, wake_radius, 1.0 - (1.0 - u) * (1.0 - u));
			if (dist > r + wake_glow_width * 5.0) {
				continue;
			}
			float seed = float(i);
			vec2 circ = dist > 0.001 ? diff / dist : vec2(1.0, 0.0);

			// Rayon qui tremble, lisse le long de l'anneau.
			float tremble = (value_noise(circ * 4.0 + seed * 1.9 + vec2(flick * 0.35, 0.0)) - 0.5) * wake_jitter;
			float rim = r + tremble;

			// Érosion : seuil qui monte de -0,2 (tout est visible) à 1,1 (tout a disparu).
			// Le masque d'érosion est fixe dans le temps (ni scintillement ni points qui
			// s'éteignent au hasard), seul le seuil bouge.
			float erode = clamp((u - wake_erode_start) / (0.98 - wake_erode_start), 0.0, 1.0);
			float threshold = -0.2 + 1.3 * erode;
			float mask = 0.85 * value_noise(circ * wake_erode_scale + seed * 5.7)
				+ 0.15 * value_noise(circ * 7.0 + seed * 2.3);
			mask = smoothstep(0.25, 0.75, mask);
			// Largeur résiduelle : pleine loin du seuil, nulle dessus, ce qui taille les
			// extrémités des arcs en pointe.
			float vis = clamp((mask - threshold) / 0.22, 0.0, 1.0);
			// La lueur ne suit que cette version LISSE et large : elle rayonne vers
			// l'extérieur, et toute variation fine de vis y dessinerait des rayons.
			float vis_glow = clamp((mask - threshold + 0.2) / 0.6, 0.0, 1.0);
			// Effritement : près des extrémités (vis < 1), un bruit fin perce le trait de
			// trous qui se referment en pointe. TOUT passe par des bruits lisses et des
			// smoothstep : un masque par secteurs d'angle (step/hash) laissait des arêtes
			// radiales droites, visibles dans la lueur comme des « parts de tarte ».
			float fine = smoothstep(0.2, 0.6, value_noise(circ * 18.0 + seed * 1.3));
			vis *= mix(1.0, fine, 1.0 - vis);
			// Micro-coupures du trait entier : quelques creux lisses qui s'effacent avec
			// l'érosion (renouvelés ~2,5 fois par seconde).
			float gaps = smoothstep(0.17, 0.4, value_noise(circ * 9.0 + seed * 4.1 + vec2(flick * 0.05, 0.0)));
			vis *= mix(gaps, 1.0, erode);
			// Le disque de cet anneau occulte le TRAIT des plus vieux (bord de 2 px, caché
			// sous son propre trait), seulement là où l'anneau est encore présent : un
			// anneau érodé n'a plus de bord. La LUEUR n'est jamais effacée selon l'angle
			// (présence) : combiné au rayon du disque, cela découpait des polygones à
			// bords droits dans le halo, surtout visibles sur l'eau sombre.
			float present = smoothstep(0.0, 0.25, mask - threshold);
			float inside = 1.0 - smoothstep(rim - 1.0, rim + 1.0, dist);
			wake_core *= 1.0 - inside * present;
			// Les lueurs des anciens sont seulement ATTÉNUÉES sous le disque (aucune
			// dépendance à l'angle, transition de ~14 px) : assez pour ne pas laisser de
			// cercles fantômes derrière chaque anneau, trop douce pour dessiner un bord.
			wake_glow *= 1.0 - 0.7 * (1.0 - smoothstep(rim - 13.0, rim + 1.0, dist));
			// Fondu de fin de vie : sur la dernière part de l'érosion, trait ET lueur
			// perdent leur intensité (les derniers éclats s'éteignent au lieu de
			// disparaître d'un coup).
			float fade = 1.0 - smoothstep(wake_fade_start, 1.0, erode);
			float energy = smoothstep(0.0, 0.03, u) * mix(1.0, 0.85, erode) * fade;

			// Épaisseur irrégulière : deux échelles de bruit (grosses variations lentes
			// + crépitement fin) qui évoluent dans le temps.
			float n_slow = value_noise(circ * 2.2 + seed * 7.1 + vec2(flick * 0.12, -flick * 0.09));
			float n_fast = value_noise(circ * 7.0 + seed * 3.3 + vec2(-flick * 0.5, flick * 0.4));
			float variation = smoothstep(0.25, 0.75, mix(n_slow, n_fast, 0.4));
			float thickness = wake_line_width * mix(0.3, 1.5, variation) * vis;

			float d = abs(dist - rim);
			float core = (1.0 - smoothstep(thickness * 0.5, max(thickness, 0.001), d)) * smoothstep(0.0, 0.15, vis);
			// La lueur suit le trait mais SE FOND au lieu de s'arrêter : là où l'arc
			// s'érode, la distance à la partie encore visible grandit (« gap », en px),
			// et la lueur décroît avec la distance euclidienne radiale + le long de
			// l'arc. Le bout de l'arc reçoit un halo arrondi qui s'estompe, au lieu
			// d'un bord radial net. C'est l'équivalent d'un flou de la lueur, sans
			// passe supplémentaire.
			float gap = (1.0 - vis_glow) * wake_glow_reach;
			float glow = exp(-sqrt(d * d + gap * gap) / wake_glow_width) * smoothstep(0.0, 0.5, vis_glow);
			wake_core = max(wake_core, core * energy);
			wake_glow = max(wake_glow, glow * energy);
		}

		vec2 drift = TIME * reflect_speed * reflect_direction;
		vec2 warp_uv = uv * reflect_warp_tiles;
		vec2 warp = vec2(
			texture(reflect_warp_noise, warp_uv).x,
			texture(reflect_warp_noise, warp_uv + vec2(5.2, 1.7)).x
		) - 0.5;
		vec2 warped_uv = uv + warp * reflect_warp_strength;

		float big = texture(reflect_big_noise, warped_uv * reflect_big_tiles + drift).x;
		float small_n = texture(reflect_small_noise, warped_uv * reflect_small_tiles + drift * 1.6).x;
		float hole = texture(reflect_hole_noise, warped_uv * reflect_hole_tiles + drift).x;

		float big_thresh = mix(reflect_big_thresh_top, reflect_big_thresh_bottom, uv.y);
		float small_thresh = mix(reflect_small_thresh_top, reflect_small_thresh_bottom, uv.y);

		bool big_hit = big > big_thresh && hole < reflect_hole_threshold;
		bool small_hit = small_n > small_thresh;
		if (big_hit || small_hit) {
			col = reflection_color.rgb;
		}

		if (glint_strength > 0.0) {
			float g = glint_layer(world_pos, glint_cell_small, glint_density_small, glint_size_small, 0.0)
				+ glint_layer(world_pos, glint_cell_big, glint_density_big, glint_size_big, 7.0);
			float depth_k = mix(1.0, glint_bottom_fade, uv.y);
			col = mix(col, glint_color.rgb, clamp(g * glint_strength * depth_k, 0.0, 1.0));
		}

		col = mix(col, wake_color.rgb, wake_glow * wake_glow_strength * wake_color.a);
		col = mix(col, vec3(1.0), wake_core);

		COLOR = vec4(col, 1.0);
	} else {
		COLOR = vec4(0.0);
	}
}
