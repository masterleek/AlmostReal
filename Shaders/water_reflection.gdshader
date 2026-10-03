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

// Sillage continu sous le curseur en déplacement libre (cf WaterReflection.gd
// qui sème un point de sillage dans wake_positions/wake_spawn_times à chaque
// PETIT déplacement du curseur au-dessus de l'eau — contrairement à l'ancien
// ripple, la distance de semis est volontairement petite pour que les points
// se chevauchent et forment une traînée CONTINUE plutôt que des anneaux
// espacés). Chaque point pousse localement la position d'échantillonnage des
// reflets (cf warped_uv plus bas) — comme si la surface était repoussée par
// le passage du curseur, façon sillage de bateau — plutôt que de dessiner un
// anneau dessus : effet plus discret/physique, visible via la distorsion des
// taches de lumière existantes + un léger éclaircissement là où la poussée
// est la plus forte. wake_squash aplatit la distance verticale (même
// perspective en biais que le reste du rendu). Chaque point s'efface
// définitivement après wake_lifetime secondes (pas de boucle infinie).
uniform vec2 wake_positions[16];
uniform float wake_spawn_times[16];
uniform float wake_time = 0.0;
uniform float wake_lifetime = 0.6;
uniform float wake_radius = 44.0;
uniform float wake_squash : hint_range(0.1, 1.0) = 0.45;
uniform float wake_warp_strength = 0.1;
// wake_color.a sert directement de multiplicateur d'opacité (cf fragment()) —
// pas seulement sa teinte : le canal alpha du sélecteur de couleur dans
// l'éditeur contrôle donc réellement la transparence du sillage, en plus de
// wake_highlight_strength (les deux se multiplient).
uniform vec4 wake_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wake_highlight_strength : hint_range(0.0, 1.0) = 0.4;

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

		vec2 wake_push = vec2(0.0);
		float wake_highlight = 0.0;
		for (int i = 0; i < 16; i++) {
			float age = wake_time - wake_spawn_times[i];
			if (age < 0.0 || age > wake_lifetime) {
				continue;
			}
			vec2 diff = world_pos - wake_positions[i];
			diff.y /= wake_squash;
			float dist = length(diff);
			if (dist > wake_radius) {
				continue;
			}
			float falloff = 1.0 - smoothstep(0.0, wake_radius, dist);
			float life_fade = 1.0 - age / wake_lifetime;
			float amount = falloff * life_fade;
			vec2 dir = dist > 0.001 ? diff / dist : vec2(0.0);
			wake_push += dir * amount;
			wake_highlight = max(wake_highlight, amount);
		}

		vec2 drift = TIME * reflect_speed * reflect_direction;
		vec2 warp_uv = uv * reflect_warp_tiles;
		vec2 warp = vec2(
			texture(reflect_warp_noise, warp_uv).x,
			texture(reflect_warp_noise, warp_uv + vec2(5.2, 1.7)).x
		) - 0.5;
		vec2 warped_uv = uv + warp * reflect_warp_strength + wake_push * wake_warp_strength;

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

		col = mix(col, wake_color.rgb, wake_highlight * wake_highlight_strength * wake_color.a);

		COLOR = vec4(col, 1.0);
	} else {
		COLOR = vec4(0.0);
	}
}
