shader_type canvas_item;

// Découpe le sprite pour qu'il ne dépasse jamais le contour hexagonal réel
// d'une tuile (même forme que WorldmapCursor.TILE_ART_HITZONE, extraite du
// dessin de hex_tiles.png) — sert à l'ombre du Héros, qui ne doit jamais
// déborder sur une case voisine. `tile_center_world` (mis à jour depuis
// GDScript chaque frame, cf HeroShadow.gd) est le centre de la tuile
// actuellement sous le sprite ; `has_tile` le désactive entièrement s'il n'y
// en a aucune sous lui.
uniform vec2 tile_center_world = vec2(0.0, 0.0);
uniform bool has_tile = true;

const float HALF_W = 32.0;
const float TIP_Y = 32.0;
const float SHOULDER_Y = 17.0;

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

	vec2 verts[6] = vec2[](
		vec2(0.0, -TIP_Y), vec2(HALF_W, -SHOULDER_Y), vec2(HALF_W, SHOULDER_Y),
		vec2(0.0, TIP_Y), vec2(-HALF_W, SHOULDER_Y), vec2(-HALF_W, -SHOULDER_Y)
	);

	bool inside = has_tile;
	float ref_sign = 0.0;
	for (int i = 0; i < 6 && inside; i++) {
		vec2 a = verts[i];
		vec2 b = verts[(i + 1) % 6];
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
