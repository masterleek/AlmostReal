shader_type canvas_item;

// Découpe le sprite pour qu'il ne dépasse jamais le contour hexagonal réel
// d'une tuile, extrait du dessin de hex_tiles.png — pensé à l'origine pour
// l'ombre du Héros (remplacé depuis par hero_shadow_ellipse.gdshader, gardé
// ici au cas où). `tile_center_world` (à poser depuis GDScript chaque frame)
// est le centre de la tuile actuellement sous le sprite ; `has_tile` le
// désactive entièrement s'il n'y en a aucune sous lui. `hitzone_verts` (à
// poser une fois, cf TileGeometry.TILE_ART_HITZONE — source unique, pas une
// copie codée en dur ici) est ce contour.
uniform vec2 tile_center_world = vec2(0.0, 0.0);
uniform bool has_tile = true;
uniform vec2 hitzone_verts[6];

// MODEL_MATRIX n'est disponible qu'au stade vertex pour un canvas_item :
// la position monde est calculée là puis transmise en varying.
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// COLOR arrive déjà pré-rempli par Godot avec texture(TEXTURE, UV) *
	// modulate : ne pas le réécrire à partir d'un nouvel échantillon de
	// TEXTURE, sinon la teinte (modulate, posée depuis HeroShadow.gd) est
	// perdue. On se contente de couper l'alpha hors de l'hexagone.
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

	if (!inside) {
		COLOR.a = 0.0;
	}
}
