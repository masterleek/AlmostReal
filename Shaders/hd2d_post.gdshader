shader_type canvas_item;
render_mode unshaded;

// Passe plein écran « HD-2D » (tilt-shift, bokeh, bloom, lumière tachetée,
// étalonnage, vignettage), posée par-dessus le monde et SOUS le HUD.
//
// Pourquoi une passe écran plutôt que des effets par sprite : le pixel art est
// affiché en blocs de 4×4 (caméra x4, filtre nearest). Flouter les sprites
// eux-mêmes n'a aucun sens ; c'est le framebuffer final qu'il faut traiter,
// comme le fait le moteur d'Octopath Traveler 2 sur sa scène 3D.
//
// `filter_linear_mipmap` est explicite : le projet est en nearest par défaut
// (`default_texture_filter=0`), ce qui rendrait le flou en blocs. Les mipmaps
// de l'écran servent de flou gratuit : un tap à un LOD élevé vaut des dizaines
// de taps à pleine résolution.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// --- Tilt-shift -------------------------------------------------------------
// Tout est exprimé en FRACTION de la hauteur d'écran : le zoom caméra (1 à 12)
// ne doit pas changer la composition de l'effet, qui est une affaire de cadrage
// de l'image et non de distance dans le monde.
uniform float focus_center : hint_range(0.0, 1.0) = 0.5;
uniform float focus_half_height : hint_range(0.0, 0.5) = 0.17;
uniform float blur_ramp : hint_range(0.05, 0.6) = 0.30;
uniform float blur_max : hint_range(0.0, 0.05) = 0.016;
uniform float blur_top_scale : hint_range(0.0, 2.0) = 1.0;
uniform float blur_bottom_scale : hint_range(0.0, 2.0) = 1.2;

// Bokeh : un point très brillant, une fois flou, devient un DISQUE lumineux et
// non une tache grise. Pondérer les taps par leur luminance reproduit ça.
uniform float bokeh_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float bokeh_boost : hint_range(0.0, 10.0) = 1.8;

// --- Bloom ------------------------------------------------------------------
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.70;
uniform float bloom_strength : hint_range(0.0, 2.0) = 0.22;

// --- Lumière tachetée (ancrée au MONDE, pas à l'écran) -----------------------
// `cam_pos`/`cam_zoom`/`viewport_px` sont posés chaque image par le script :
// c'est ce qui fait glisser les plaques avec le terrain quand la caméra bouge.
uniform vec2 cam_pos = vec2(0.0);
uniform float cam_zoom = 4.0;
uniform vec2 viewport_px = vec2(1920.0, 1080.0);
uniform float dapple_strength : hint_range(0.0, 1.0) = 0.0;
uniform float dapple_scale : hint_range(0.001, 0.05) = 0.011;
uniform float dapple_lo : hint_range(0.0, 1.0) = 0.42;
uniform float dapple_hi : hint_range(0.0, 1.0) = 0.62;
uniform vec3 dapple_light_mul = vec3(1.08, 1.04, 0.93);
uniform vec3 dapple_shadow_mul = vec3(0.84, 0.89, 0.97);
uniform vec2 dapple_drift = vec2(0.018, 0.010);

// --- Étalonnage -------------------------------------------------------------
// Ombres froides, hautes lumières chaudes : c'est le contraste de TEINTE, plus
// que de luminosité, qui donne le côté « soleil rasant » des captures.
uniform vec3 shadow_tint = vec3(0.99, 0.99, 1.01);
uniform vec3 highlight_tint = vec3(1.05, 1.02, 0.95);
uniform float contrast : hint_range(0.5, 1.6) = 1.02;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float exposure : hint_range(0.5, 1.6) = 1.0;

// --- Vignettage -------------------------------------------------------------
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.38;
uniform float vignette_inner : hint_range(0.0, 1.2) = 0.45;
uniform float vignette_outer : hint_range(0.0, 1.5) = 1.05;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);
const int BLUR_TAPS = 28;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// Flou en disque (spirale de Vogel : répartition régulière sans motif de
// grille). Le LOD suit le rayon pour que l'espacement entre taps reste ~ un
// texel du mip lu : pas de crénelage même avec peu de taps.
vec3 disk_blur(vec2 uv, float radius_y, float aspect, vec2 pixel_size) {
	if (radius_y < 0.0004) {
		return textureLod(screen_tex, uv, 0.0).rgb;
	}
	float px_per_unit_y = 1.0 / pixel_size.y;
	float lod = max(log2(radius_y * px_per_unit_y / 5.0), 0.0);
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < BLUR_TAPS; i++) {
		float fi = float(i) + 0.5;
		float r = sqrt(fi / float(BLUR_TAPS));
		float a = fi * 2.399963;
		vec2 off = vec2(cos(a), sin(a)) * r * radius_y * vec2(1.0 / aspect, 1.0);
		vec3 c = textureLod(screen_tex, uv + off, lod).rgb;
		float l = dot(c, LUMA);
		float w = 1.0 + bokeh_boost * smoothstep(bokeh_threshold, 1.0, l);
		acc += c * w;
		wsum += w;
	}
	return acc / wsum;
}

// Bloom : seuil sur des mips déjà flous (3 largeurs), additionnés. Seuiller
// APRÈS le downsample évite le scintillement d'un pixel isolé très clair.
vec3 bloom_at(vec2 uv) {
	vec3 b = max(textureLod(screen_tex, uv, 3.0).rgb - bloom_threshold, 0.0) * 0.5;
	b += max(textureLod(screen_tex, uv, 5.0).rgb - bloom_threshold, 0.0) * 0.8;
	b += max(textureLod(screen_tex, uv, 7.0).rgb - bloom_threshold, 0.0) * 1.0;
	return b;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	float dy = uv.y - focus_center;
	float side_scale = dy < 0.0 ? blur_top_scale : blur_bottom_scale;
	float amount = clamp((abs(dy) - focus_half_height) / blur_ramp, 0.0, 1.0);
	amount = amount * amount * (3.0 - 2.0 * amount);
	float radius_y = blur_max * amount * side_scale;

	vec3 col = disk_blur(uv, radius_y, aspect, SCREEN_PIXEL_SIZE);

	if (dapple_strength > 0.0) {
		vec2 world = cam_pos + (uv - 0.5) * viewport_px / cam_zoom;
		float n = fbm(world * dapple_scale + dapple_drift * TIME);
		float m = smoothstep(dapple_lo, dapple_hi, n);
		vec3 patch = mix(dapple_shadow_mul, dapple_light_mul, m);
		col *= mix(vec3(1.0), patch, dapple_strength);
	}

	col += bloom_at(uv) * bloom_strength;
	col *= exposure;

	float l = dot(col, LUMA);
	col = mix(col * shadow_tint, col * highlight_tint, smoothstep(0.15, 0.75, l));
	col = (col - 0.5) * contrast + 0.5;
	col = mix(vec3(dot(col, LUMA)), col, saturation);

	vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
	float v = smoothstep(vignette_inner, vignette_outer, length(d));
	col *= 1.0 - v * vignette_strength;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
