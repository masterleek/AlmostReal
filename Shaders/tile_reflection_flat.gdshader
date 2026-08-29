shader_type canvas_item;

// Reflet plat de toutes les tuiles : ignore l'art d'origine, ne garde que sa
// silhouette (canal alpha de TEXTURE) — recolorée soit en flat_color, soit
// le long d'un dégradé vertical (flat_gradient) si use_gradient est actif.
// Le dégradé est échantillonné sur la position MONDE réelle (pas l'UV locale
// de la tuile, qui donnerait un dégradé répété tuile par tuile) : gradient_y_min/
// gradient_y_max (posés depuis TileReflectionFlat.gd, bornes réelles de la
// carte) normalisent cette position en 0..1 pour tenir sur tout le dégradé,
// une seule fois, quelle que soit la taille de la carte.

uniform vec4 flat_color : source_color = vec4(0.6, 0.75, 1.0, 1.0);
uniform sampler2D flat_gradient : source_color, filter_linear;
uniform bool use_gradient = false;
uniform float alpha : hint_range(0.0, 1.0) = 0.5;
uniform float gradient_y_min = 0.0;
uniform float gradient_y_max = 1000.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = flat_color.rgb;
	if (use_gradient) {
		float t = clamp((world_y - gradient_y_min) / max(gradient_y_max - gradient_y_min, 0.001), 0.0, 1.0);
		col = texture(flat_gradient, vec2(t, 0.5)).rgb;
	}
	COLOR = vec4(col, tex.a * alpha);
}
