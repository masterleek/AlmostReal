shader_type canvas_item;

// Écume de rivage (cf IslandFoam.gd). Tout est fonction de UNE donnée, la
// distance `d` (px monde) du pixel à la silhouette des tuiles, lue dans une carte
// précalculée. Quatre couches, de l'eau vers le rivage :
//   1. une teinte turquoise d'eau peu profonde, en dégradé continu qui s'estompe
//      vers le large ;
//   2. les REFLETS de l'eau (water_reflection.gdshader), redessinés par-dessus la
//      teinte : mêmes textures de bruit, même couleur, mêmes coordonnées, donc
//      les mêmes traits que l'eau alentour, qui restent nets au lieu d'être
//      voilés par le turquoise. Les seuils y sont abaissés près du rivage pour
//      qu'il y en ait là aussi ;
//   3. une frange claire et 4. une frange blanche, dont la largeur « respire »
//      et varie le long du bord — c'est l'écume qui monte et redescend.
// Les distances sont perturbées par du bruit : sans cela, tout serait des
// bandes d'épaisseur constante qui recopient le contour.
//
// Rendu LISSE, calculé à la résolution de l'écran : la carte de distance est lue
// en filtrage linéaire et les bords sont antialiasés (fwidth). Rien n'est
// quantifié au pixel monde, contrairement à l'art des tuiles.

uniform sampler2D distance_field : filter_linear, repeat_disable;
// Coin haut-gauche et taille de la carte, en px monde.
uniform vec2 origin_px = vec2(0.0);
uniform vec2 size_px = vec2(1.0);
uniform float band_px = 28.0;

uniform vec4 color_foam : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform vec4 color_fringe : source_color = vec4(0.72, 0.93, 0.95, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.16, 0.84, 0.78, 1.0);
// Opacité maximale de la teinte d'eau peu profonde, au contact du rivage.
uniform float shallow_strength : hint_range(0.0, 1.0) = 0.7;
// Largeur de la frange blanche (px) : minimum, et amplitude de sa « respiration ».
uniform float foam_width_min = 1.4;
uniform float foam_width_breath = 1.3;
// Vitesse de la frange blanche : multiplie le temps de sa respiration et de la
// dérive de son bord (pas celui des reflets, qui suivent l'eau).
uniform float foam_speed = 1.7;

// Reflets de l'eau : ces paramètres sont COPIÉS du matériau de WaterReflection par
// IslandFoam.gd (mêmes noms), jamais réglés ici. water_origin et water_size donnent
// le rectangle de l'eau, dont les coordonnées UV pilotent les textures de bruit.
uniform vec2 water_origin = vec2(0.0);
uniform vec2 water_size = vec2(1.0);
uniform vec4 reflection_color : source_color = vec4(0.969, 0.941, 0.816, 1.0);
uniform sampler2D reflect_big_noise : repeat_enable;
uniform float reflect_big_tiles = 1.0;
uniform float reflect_big_thresh_top = 0.6;
uniform float reflect_big_thresh_bottom = 0.85;
uniform sampler2D reflect_small_noise : repeat_enable;
uniform float reflect_small_tiles = 4.0;
uniform float reflect_small_thresh_top = 0.56;
uniform float reflect_small_thresh_bottom = 0.82;
uniform sampler2D reflect_hole_noise : repeat_enable;
uniform float reflect_hole_tiles = 4.5;
uniform float reflect_hole_threshold = 0.6;
uniform float reflect_speed = 0.015;
uniform vec2 reflect_direction = vec2(1.0, 0.3);
uniform sampler2D reflect_warp_noise : repeat_enable;
uniform float reflect_warp_tiles = 1.4;
uniform float reflect_warp_strength = 0.35;
// Reflets dans la bande : seuil de la petite couche (plus bas = plus de traits)
// au contact du rivage puis au large de la bande.
uniform float wave_threshold_near : hint_range(0.0, 1.0) = 0.7;
uniform float wave_threshold_far : hint_range(0.0, 1.0) = 0.82;

// Côté NORD des tuiles (rivage tourné vers le haut de l'écran) : l'écume y est
// plus discrète et en partie cachée par la tuile. top_foam_scale multiplie la
// largeur de la frange blanche, top_water_scale l'opacité de la teinte et des
// reflets, top_hide_px recule le tout sous la tuile (en px).
uniform float top_foam_scale : hint_range(0.0, 1.0) = 0.4;
uniform float top_water_scale : hint_range(0.0, 1.0) = 0.5;
uniform float top_hide_px = 2.0;
// Côté SUD : l'écume déborde de ce nombre de px de plus vers le bas, et sa frange
// blanche est multipliée par bottom_foam_scale (le bas des tuiles est vu de face,
// elle y paraissait deux fois plus épaisse qu'ailleurs).
uniform float bottom_extend_px = 1.0;
uniform float bottom_foam_scale : hint_range(0.0, 1.0) = 0.5;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

// Direction (unitaire) du gradient de la distance en `uv` : vers le large.
vec2 shore_direction(vec2 uv, vec2 px) {
	vec2 g = vec2(
		texture(distance_field, uv + vec2(2.0, 0.0) * px).r - texture(distance_field, uv - vec2(2.0, 0.0) * px).r,
		texture(distance_field, uv + vec2(0.0, 2.0) * px).r - texture(distance_field, uv - vec2(0.0, 2.0) * px).r);
	return g / max(length(g), 0.001);
}

void fragment() {
	float d = texture(distance_field, UV).r;
	if (d <= 0.0 || d >= band_px) {
		COLOR = vec4(0.0);
	} else {
		vec2 wp = origin_px + UV * size_px;

		// Orientation du rivage, MOYENNÉE sur un cercle de 8 points à 6 px : la
		// direction du gradient bascule d'un coup le long de l'axe médian entre deux
		// bords (dans un angle rentrant de la silhouette). Prise en un seul point,
		// elle y faisait sauter `top` de 0 à 1 et laissait une arête droite dans la
		// teinte ; moyennée, les directions opposées s'annulent et `top` varie
		// progressivement. `ny` vaut ainsi entre -1 (face au nord) et 1 (face au sud).
		vec2 px = 1.0 / size_px;
		vec2 mean_dir = vec2(0.0);
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.7853982;
			mean_dir += shore_direction(UV + vec2(cos(a), sin(a)) * 6.0 * px, px);
		}
		float ny = mean_dir.y / 8.0;
		float top = smoothstep(0.2, -0.4, ny);
		float bottom = smoothstep(0.0, 0.5, ny);

		// Bruits ancrés dans le monde : un très lent (grandes taches), un moyen (le
		// bord ondule).
		float foam_t = TIME * foam_speed;
		float n_slow = value_noise(wp / 23.0 + vec2(foam_t * 0.02, 0.0));
		float n_mid = value_noise(wp / 8.0 + vec2(0.0, foam_t * 0.05));
		float dd = d + (n_mid - 0.5) * 4.5 + (n_slow - 0.5) * 5.0 + top_hide_px * top - bottom_extend_px * bottom;

		// 2. Reflets de l'eau, recalculés comme dans water_reflection.gdshader (même
		// déformation de domaine, même dérive, mêmes textures, même échantillonnage),
		// pour REDESSINER par-dessus la teinte (et l'ombre des îlots, qui les grisait)
		// les traits que l'eau dessine déjà. L'origine de l'eau reçue (water_origin)
		// est celle réellement affichée, arrondie comme un Control : sans cela, le
		// tracé tombait un demi-pixel à côté et laissait un fantôme sous chaque trait.
		vec2 water_uv = (wp - water_origin) / water_size;
		vec2 warp_uv = water_uv * reflect_warp_tiles;
		vec2 warp = vec2(
			texture(reflect_warp_noise, warp_uv).x,
			texture(reflect_warp_noise, warp_uv + vec2(5.2, 1.7)).x
		) - 0.5;
		vec2 warped_uv = water_uv + warp * reflect_warp_strength;
		vec2 drift = TIME * reflect_speed * reflect_direction;
		float big = texture(reflect_big_noise, warped_uv * reflect_big_tiles + drift).x;
		float small_n = texture(reflect_small_noise, warped_uv * reflect_small_tiles + drift * 1.6).x;
		float hole = texture(reflect_hole_noise, warped_uv * reflect_hole_tiles + drift).x;
		float big_thresh = mix(reflect_big_thresh_top, reflect_big_thresh_bottom, water_uv.y);
		float small_thresh = mix(reflect_small_thresh_top, reflect_small_thresh_bottom, water_uv.y);
		bool big_hit = big > big_thresh && hole < reflect_hole_threshold;
		bool water_hit = big_hit || small_n > small_thresh;
		// Traits EN PLUS : seuil de la petite couche abaissé près du rivage (jamais
		// relevé : l'eau du haut de la carte, presque sans reflets, n'en donnerait
		// aucun). Ils ne s'ajoutent que là où l'eau n'en a pas.
		small_thresh = min(small_thresh, mix(wave_threshold_near, wave_threshold_far, d / band_px));
		bool extra_hit = !water_hit && (big_hit || small_n > small_thresh);

		// 1. Teinte d'eau peu profonde : dégradé lisse.
		float depth_k = clamp(1.0 - dd / band_px, 0.0, 1.0);
		vec3 col = color_shallow.rgb;
		float alpha = smoothstep(0.0, 1.0, depth_k) * shallow_strength * mix(1.0, top_water_scale, top);
		if (water_hit) {
			col = reflection_color.rgb;
			alpha = 1.0;
		}
		// Opacité pleine aussi : atténués (top_water_scale), ces traits en plus
		// devenaient des taches grises à moitié transparentes.
		if (extra_hit) {
			col = reflection_color.rgb;
			alpha = 1.0;
		}

		// 3 + 4. Frange : sa largeur respire au rythme d'une houle lente, déphasée
		// d'un point à l'autre du rivage par le bruit lent. Bords antialiasés sur la
		// largeur d'un pixel d'écran.
		float breath = 0.5 + 0.5 * sin(foam_t * 0.9 + n_slow * 12.0);
		float foam_w = (foam_width_min + foam_width_breath * breath + 1.6 * n_mid)
			* mix(1.0, top_foam_scale, top) * mix(1.0, bottom_foam_scale, bottom);
		float aa = max(fwidth(dd), 0.02);
		float fringe_a = 1.0 - smoothstep(foam_w + 1.2 - aa, foam_w + 1.2 + aa, dd);
		col = mix(col, color_fringe.rgb, fringe_a);
		alpha = mix(alpha, 1.0, fringe_a);
		float foam_a = 1.0 - smoothstep(foam_w - aa, foam_w + aa, dd);
		col = mix(col, color_foam.rgb, foam_a);
		alpha = mix(alpha, 1.0, foam_a);

		COLOR = vec4(col, alpha);
	}
}
