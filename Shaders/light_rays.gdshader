shader_type canvas_item;
render_mode blend_add;

// UN rayon de lumière (+ particules près de son extrémité basse), en ESPACE
// MONDE — pensé pour être dupliqué autant de fois que voulu (chaque copie
// est un nœud LightRay indépendant, cf Scenes/LightRay.tscn) plutôt qu'un
// tableau de décalages dans un seul gros rect : pour en ajouter un, on
// duplique le nœud (Ctrl+D) et on le déplace où on veut (Transform >
// Position) — LightRay.gd rend le matériau unique par instance au
// démarrage, donc régler cette copie ne change pas les autres.
// blend_add (comme CanvasItemMaterial_glow ailleurs dans le projet) : la
// lumière s'AJOUTE à ce qu'il y a dessous.
//
// Utilise VERTEX (position locale du ColorRect, en pixels) plutôt que l'UV
// brut ou SCREEN_PIXEL_SIZE : VERTEX reste correct quelle que soit la
// taille du rect, et n'introduit aucune déformation d'aspect (contrairement
// à un calcul d'angle sur une UV 0..1 non carrée). Le rect doit rester
// nettement plus grand que ray_width_px/max_distance_px, sinon ses propres
// bords deviennent visibles comme une arête nette.
//
// origin_local (position LOCALE, pixels, dans le rect) : d'où part le
// rayon — PAS (0,0) par défaut : le rayon a une largeur (ray_width_px), donc
// une origine collée au coin du rect ferait déborder sa moitié hors du rect
// dès la source (coupé net) ; origin_local doit rester à distance de
// ray_width_px/2 au moins de chaque bord.


//
// Repère (along, across) : along = distance le long de la direction du
// rayon depuis origin_local (0 = source, grandit en s'éloignant) ; across =
// position perpendiculaire (distance au centre du rayon, pour son bord
// doux). Le fondu (falloff/max_distance_px) suit along, pas la distance
// radiale : le rayon "s'éteint" en s'éloignant de sa source, comme un vrai
// faisceau de lumière.
//
// Particules : près de particle_target_along (l'extrémité basse), une
// grille grossière (particle_cell_px) hachée en pseudo-aléatoire décide
// quelles cellules portent un point lumineux (particle_density), avec une
// position/scintillement propres à chaque cellule — même technique de hash
// que le scintillement de l'eau, pas un simple bruit continu.

uniform vec2 origin_local = vec2(100.0, 100.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float ray_angle_deg = 20.0;
uniform float ray_width_px : hint_range(10.0, 500.0) = 50.0;
uniform float falloff = 1.2;
uniform float max_distance_px = 225.0;
uniform float base_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float shimmer_speed = 1.2;
uniform float shimmer_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float shimmer_seed = 0.0;

uniform float particle_density : hint_range(0.0, 1.0) = 0.35;
uniform float particle_cell_px = 10.0;
uniform float particle_size_px = 1.75;
uniform float particle_zone_px = 75.0;
uniform float particle_target_along = 125.0;

varying vec2 local_pos;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos - origin_local;

	float ang = radians(ray_angle_deg);
	vec2 dir = vec2(sin(ang), cos(ang));
	vec2 perp = vec2(cos(ang), -sin(ang));
	float along = dot(p, dir);
	float across = dot(p, perp);

	float beam = 1.0 - smoothstep(ray_width_px * 0.5, ray_width_px, abs(across));
	float shimmer_phase = hash(shimmer_seed) * 100.0;
	float shimmer = base_intensity + (0.5 + 0.5 * sin(TIME * shimmer_speed + shimmer_phase)) * shimmer_intensity;
	float along_fade = pow(clamp(1.0 - along / max_distance_px, 0.0, 1.0), falloff);
	float ray_alpha = beam * shimmer * along_fade;

	vec2 local = vec2(along, across);
	vec2 cell = floor(local / particle_cell_px);
	float cell_hash = hash(cell.x * 12.9898 + cell.y * 78.233 + shimmer_seed);
	float zone = smoothstep(particle_zone_px, 0.0, abs(along - particle_target_along))
			* step(abs(across), ray_width_px);
	float particle_alpha = 0.0;
	if (cell_hash < particle_density && zone > 0.0) {
		vec2 jitter = (vec2(hash(cell_hash * 13.1), hash(cell_hash * 29.7)) - 0.5) * particle_cell_px;
		vec2 particle_center = (cell + 0.5) * particle_cell_px + jitter;
		float dp = length(local - particle_center);
		float twinkle = 0.5 + 0.5 * sin(TIME * shimmer_speed * 2.0 + cell_hash * 50.0);
		particle_alpha = smoothstep(particle_size_px, 0.0, dp) * twinkle * zone;
	}

	float total = max(ray_alpha, particle_alpha);
	COLOR = vec4(ray_color.rgb, total * ray_color.a);
}
