shader_type canvas_item;

// Adapté de "2D water with reflections" (LaithNasa, CC0) :
// https://godotshaders.com/shader/2d-water-with-reflections/
// Le reflet des tuiles (SubViewport miroir échantillonné par case) a été
// retiré (résultat jugé insatisfaisant) — ce qui reste ici est uniquement
// l'eau animée : distorsion + silhouette de vaguelettes + teinte/opacité.
// Placé derrière tout le TileMapLayer (cf WaterReflection.gd, z_index sous
// le TileMapLayer).

uniform float level : hint_range(0.0, 1.0) = 0.0;
// Dégradé de couleur de l'eau (remplace l'ancienne teinte plate unique) :
// une ressource Gradient/GradientTexture1D, éditable visuellement dans
// l'inspecteur (points de couleur qu'on glisse). Échantillonné via
// gradient_noise ci-dessous pour varier la couleur sur la surface — pas un
// dégradé figé dans une direction donnée.
uniform sampler2D water_albedo_gradient : source_color, filter_linear;
uniform float gradient_scale = 0.4;
uniform float gradient_speed = 0.015;
uniform float water_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float water_speed = 0.05;
uniform float wave_distortion = 0.2;
uniform int wave_multiplyer = 3;
uniform bool water_texture_on = true;
// Échelle UV de la texture d'eau (uv * water_texture_scale) : un facteur Y
// élevé multiplie les bandes de vaguelettes visibles à l'écran — trop haut,
// ça devient un grain fin façon parasites TV plutôt que des vaguelettes.
uniform vec2 water_texture_scale = vec2(0.5, 1.5);
uniform float water_texture_limit : hint_range(0.0, 1.0) = 0.35;
// Largeur (0..1) de la transition douce autour de water_texture_limit — 0 =
// silhouette dure (noir/blanc net, un aspect plus "bruyant").
uniform float water_texture_softness : hint_range(0.001, 0.3) = 0.08;
uniform sampler2D noise_texture : repeat_enable;
uniform sampler2D noise_texture2 : repeat_enable;

// Taille réelle (en pixels) du rect porteur, posée depuis GDScript : world_px
// est calculé à l'échelle du pixel monde plutôt que de l'UV (0..1).
uniform vec2 map_size_px = vec2(1000.0, 1000.0);

void fragment() {
	vec2 uv = UV;
	vec2 world_px = uv * map_size_px;
	COLOR = vec4(0.0);

	if (uv.y >= level) {
		COLOR.a = 1.0;

		// Distorsion animée de la texture d'eau (silhouette de vaguelettes).
		vec2 water_uv = vec2(uv.x, uv.y * float(wave_multiplyer));
		float noise = texture(noise_texture, vec2(water_uv.x + TIME * water_speed, water_uv.y)).x * wave_distortion;
		noise -= (0.5 * wave_distortion);

		if (water_texture_on) {
			vec4 water_texture = texture(noise_texture2, uv * water_texture_scale + vec2(noise, 0.0));
			float water_texture_value = 1.0 - smoothstep(water_texture_limit - water_texture_softness, water_texture_limit + water_texture_softness, water_texture.x);
			COLOR.xyz = vec3(water_texture_value);
		}

		// Motif lent et indépendant de la distorsion des vaguelettes (bruit,
		// pas TIME * water_speed) : sert de position (0..1) dans le dégradé,
		// pour une variation de couleur organique sur la surface plutôt qu'une
		// bande figée.
		float gradient_t = texture(noise_texture, uv * gradient_scale + vec2(TIME * gradient_speed, 0.0)).x;
		vec4 water_albedo = texture(water_albedo_gradient, vec2(gradient_t, 0.5));
		COLOR = mix(COLOR, water_albedo, water_opacity);
	}
}
