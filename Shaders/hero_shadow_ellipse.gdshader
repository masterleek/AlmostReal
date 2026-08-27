shader_type canvas_item;

// Ellipse douce (calculée depuis l'UV, aucune texture nécessaire — le sprite
// qui porte ce shader utilise un pixel blanc 1x1, redimensionné) découpée
// par le contour hexagonal réel d'une tuile, pour l'ombre du Héros : elle ne
// doit jamais déborder sur une case voisine. `hitzone_verts` (posé une fois
// depuis GDScript, cf HeroShadow.gd) est ce contour — source unique
// TileGeometry.TILE_ART_HITZONE, pas une copie codée en dur ici. `tile_center_world`
// (mis à jour chaque frame) est le centre de la tuile actuellement sous
// l'ombre ; `has_tile` la masque entièrement s'il n'y en a aucune sous elle.
uniform vec2 tile_center_world = vec2(0.0, 0.0);
uniform bool has_tile = true;
uniform vec2 hitzone_verts[6];

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// UV (0..1) -> centré (-1..1) : ellipse pleine à distance 1, fondu doux
	// entre 0.7 et 1.0 pour un bord adouci plutôt qu'un cercle dur.
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(centered);
	float ellipse_alpha = 1.0 - smoothstep(0.7, 1.0, dist);

	vec2 local_pos = world_pos - tile_center_world;
	bool inside = has_tile;
	float ref_sign = 0.0;
	for (int i = 0; i < 6 && inside; i++) {
		vec2 a = hitzone_verts[i];
		vec2 b = hitzone_verts[(i + 1) % 6];
		vec2 edge = b - a;
		vec2 to_p = local_pos - a;
		float cross_z = edge.x * to_p.y - edge.y * to_p.x;
		if (i == 0) {
			ref_sign = sign(cross_z);
		} else if (cross_z != 0.0 && sign(cross_z) != ref_sign) {
			inside = false;
		}
	}

	// COLOR arrive déjà pré-rempli par Godot avec texture(TEXTURE, UV) *
	// modulate (donc déjà noir + shadow_alpha, cf HeroShadow.gd) : on ne fait
	// que moduler son alpha par la forme de l'ellipse et la découpe hexagonale.
	COLOR.a *= ellipse_alpha * (inside ? 1.0 : 0.0);
}
