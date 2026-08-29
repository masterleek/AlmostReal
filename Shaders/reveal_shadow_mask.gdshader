shader_type canvas_item;

// Masque l'ombre de révélation de tuile (RevealShadow) pour qu'elle ne
// déborde JAMAIS, à aucun moment de l'animation (repos, décollage, chute),
// sur une case voisine — même technique que l'ombre du Héros
// (hero_shadow_ellipse.gdshader) : chaque pixel est testé (en position
// MONDE, donc indépendant de tout scale/position du nœud porteur) contre le
// contour hexagonal réel de LA tuile "empty" concernée (hitzone_verts,
// TileGeometry.tile_art_hitzone — source unique, cf TileRevealController.gd)
// autour de son centre fixe (tile_center_world, posé une fois par reveal()).
// Contrairement à HeroShadow, pas de forme d'ellipse à calculer ici : la
// forme du masque EST la forme visible de l'ombre (RevealShadow.polygon est
// déjà ce même contour) — ce shader garantit juste, en plus, qu'aucun pixel
// ne s'affiche jamais hors de ce contour, quoi qu'il arrive à l'échelle du
// nœud porteur.
uniform vec2 tile_center_world = vec2(0.0, 0.0);
uniform vec2 hitzone_verts[6];

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 local_pos = world_pos - tile_center_world;
	bool inside = true;
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

	// COLOR arrive déjà pré-rempli par Godot avec la couleur du Polygon2D
	// (cf RevealShadow.color) : on ne fait que moduler son alpha par le masque.
	COLOR.a *= inside ? 1.0 : 0.0;
}
