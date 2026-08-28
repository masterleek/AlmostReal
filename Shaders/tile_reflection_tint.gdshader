shader_type canvas_item;

// Teinte + opacité du reflet d'une tuile (StartTileReflection, cf
// StartTileEffects.gd). Sprite2D.modulate ne fait qu'une MULTIPLICATION avec
// les couleurs de l'art d'origine : sur un art déjà saturé (vert/jaune de la
// tuile), ça donne un résultat terne, à peine visible — pas une vraie
// teinte. Ici on MÉLANGE (mix) la couleur choisie par-dessus le pixel
// d'origine, avec une force réglable (tint_strength) : à 1.0, le reflet
// devient entièrement la couleur choisie (silhouette pleine), visible sans
// ambiguïté quel que soit l'art sous-jacent.

uniform vec4 tint_color : source_color = vec4(0.6, 0.75, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.5;
uniform float reflection_opacity : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 tinted = mix(tex.rgb, tint_color.rgb, tint_strength);
	COLOR = vec4(tinted, tex.a * reflection_opacity);
}
