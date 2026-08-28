shader_type canvas_item;

// Mousse blanche "cartoon" qui épouse le bas de la silhouette hexagonale
// réelle d'UNE tuile (test scopé à la tuile de départ du Héros — cf
// StartTileEffects.gd). Même technique hex_sdf (distance signée au vrai
// contour à 6 côtés) que hex_tile_clip.gdshader pour hitzone_verts.
//
// Rendu PIXEL ART : la position est alignée sur une grille (pixel_size_px)
// avant tout calcul de distance/angle — contours en escalier, pas lissés —
// et le fondu angulaire passe par un tramage ordonné (matrice de Bayer 4x4,
// motif de points classique du pixel art) plutôt qu'un dégradé d'alpha
// continu : chaque pixel du rendu est soit pleinement opaque, soit
// pleinement transparent, jamais entre les deux.
//
// tilt_x_deg/tilt_y_deg simulent une bascule 3D (rotation autour des axes
// X/Y, comme un plan qu'on incline) via un écrasement non-uniforme de la
// position locale autour de tilt_pivot_px — une approximation simple
// (facteur cosinus), pas une vraie projection en perspective, suffisante
// pour faire "poser" la mousse à plat sur l'eau plutôt qu'un décalque plan
// face caméra.

uniform vec2 hex_verts[6];
uniform vec2 rect_size_px = vec2(128.0, 128.0);
uniform float foam_width_px = 8.0;
uniform vec4 color_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_outline : source_color = vec4(0.16, 0.28, 0.52, 1.0);
uniform float outline_width_px = 2.5;
// Vacillement de la largeur de la bande : trois sinusoïdes superposées
// (fréquence/vitesse/phase propres à chacune) plutôt qu'une seule — irrégulier
// et organique, mais toujours lisse/déterministe (pas de bruit).
uniform float wobble_amplitude_px = 1.8;
uniform float wobble_speed = 1.2;
uniform float wobble_frequency = 0.15;
// Étendue angulaire (degrés) de l'arc de mousse autour du bas de la tuile
// (0° = pointe du bas, 180° = tout le contour), et largeur du fondu (tramé,
// pas lissé) à ses deux extrémités.
uniform float foam_arc_deg = 130.0;
uniform float foam_arc_fade_deg = 45.0;

// Taille (en pixels monde) d'un "pixel" du rendu — aligne les contours sur
// cette grille pour un aspect pixel art cohérent avec l'art des tuiles.
uniform float pixel_size_px = 2.0;

// Bascule pseudo-3D autour de tilt_pivot_px : X (avant/arrière, écrase Y) et
// Y (gauche/droite, écrase X) simulent une inclinaison ; Z est une vraie
// rotation dans le plan (aucun écrasement, l'axe Z pointe vers la caméra) —
// appliquée en premier, avant l'écrasement X/Y.
uniform float tilt_x_deg = 0.0;
uniform float tilt_y_deg = 0.0;
uniform float tilt_z_deg = 0.0;
uniform vec2 tilt_pivot_px = vec2(0.0, 0.0);

// Distance signée de `p` (relatif au centre de l'hexagone) au polygone
// hex_verts : négative à l'intérieur, positive à l'extérieur, 0 sur le bord.
float hex_sdf(vec2 p, vec2 verts[6]) {
	float dist = 1e9;
	bool inside = false;
	for (int i = 0; i < 6; i++) {
		vec2 a = verts[i];
		vec2 b = verts[(i + 1) % 6];
		vec2 edge = b - a;
		vec2 to_p = p - a;
		float t = clamp(dot(to_p, edge) / dot(edge, edge), 0.0, 1.0);
		dist = min(dist, length(to_p - edge * t));

		if ((a.y > p.y) != (b.y > p.y)) {
			float x_at_p_y = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x);
			if (p.x < x_at_p_y) {
				inside = !inside;
			}
		}
	}
	return inside ? -dist : dist;
}

// Matrice de Bayer 4x4 (tramage ordonné) : seuil 0..1 propre à chaque pixel
// de la grille pixel_size_px — remplace un smoothstep par un motif de points
// classique du pixel art pour les zones de transition (fondu, contour).
float bayer4x4(vec2 cell) {
	int x = int(mod(cell.x, 4.0));
	int y = int(mod(cell.y, 4.0));
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (m[x + y * 4] + 0.5) / 16.0;
}

void fragment() {
	vec2 raw_local = (UV - vec2(0.5)) * rect_size_px;

	// Bascule pseudo-3D avant toute autre chose : tout le reste (distance,
	// angle, grille pixel) travaille déjà sur la forme "posée à plat". Z
	// (rotation pure, dans le plan) d'abord, puis l'écrasement X/Y.
	vec2 tilted = raw_local - tilt_pivot_px;
	float z_rad = radians(tilt_z_deg);
	float cz = cos(z_rad);
	float sz = sin(z_rad);
	tilted = vec2(tilted.x * cz - tilted.y * sz, tilted.x * sz + tilted.y * cz);
	tilted.y *= cos(radians(tilt_x_deg));
	tilted.x *= cos(radians(tilt_y_deg));
	tilted += tilt_pivot_px;

	// Grille pixel art : tout calcul ci-dessous se fait sur cette position
	// alignée, pas la position continue — d'où les contours en escalier.
	vec2 cell = floor(tilted / pixel_size_px);
	vec2 local = (cell + 0.5) * pixel_size_px;

	float dist_to_shore = hex_sdf(local, hex_verts);

	float wobble_raw = sin(local.x * wobble_frequency + TIME * wobble_speed) * wobble_amplitude_px
			+ sin(local.x * wobble_frequency * 2.3 + TIME * wobble_speed * 1.7 + 1.5) * wobble_amplitude_px * 0.5
			+ sin(local.x * wobble_frequency * 0.55 - TIME * wobble_speed * 0.8 + 4.0) * wobble_amplitude_px * 0.35;
	// Le vacillement lui-même est quantifié sur la grille pixel (pas de
	// glissement sous-pixel) : l'animation "saute" par pas entiers, comme
	// une animation de sprite pixel art plutôt qu'une interpolation lisse.
	float wobble = round(wobble_raw / pixel_size_px) * pixel_size_px;
	float edge = foam_width_px + wobble;
	float outer_edge = edge + outline_width_px;

	// Bords nets (aucun smoothstep) : chaque pixel est entièrement dedans ou
	// dehors, la seule "douceur" vient du tramage plus bas.
	float outside = step(0.0, dist_to_shore);
	float body_mask = step(dist_to_shore, edge) * outside;
	float total_mask = step(dist_to_shore, outer_edge) * outside;
	float outline_mask = clamp(total_mask - body_mask, 0.0, 1.0);

	// Fondu angulaire tramé (Bayer), pas un dégradé d'alpha continu : dans la
	// bande de transition, chaque pixel est décidé pleinement visible ou
	// pleinement invisible selon le motif de points, pas une valeur d'alpha
	// intermédiaire.
	float angle_deg = degrees(atan(local.x, local.y));
	float arc_t = clamp((foam_arc_deg * 0.5 - abs(angle_deg)) / max(foam_arc_fade_deg, 0.001), 0.0, 1.0);
	float arc_mask = step(bayer4x4(cell), arc_t);

	vec3 col = mix(color_outline.rgb, color_foam.rgb, body_mask);
	float alpha = clamp(body_mask + outline_mask, 0.0, 1.0) * arc_mask;

	COLOR = vec4(col, alpha);
}
