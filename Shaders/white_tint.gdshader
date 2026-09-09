shader_type canvas_item;

// Mélange la couleur du sprite vers du blanc pur (silhouette comprise) sans
// jamais toucher à sa transparence, pour teinter une tuile en blanc sans
// avoir besoin d'un calque superposé séparé (cf reveal_tile).
uniform float white_amount : hint_range(0.0, 1.0) = 0.0;

// Luminance en dessous de laquelle un pixel N'EST PAS blanchi.
//
// Les sprites de combat portent leur ombre au sol DANS leur cellule (sur la
// planche du cactoon, les rangées 52 à 66 sont une ellipse noire opaque) :
// blanchir la cellule entière transformerait cette ombre en halo lumineux
// sous les pieds de l'unité. Le seuil laisse donc les pixels quasi noirs —
// l'ombre et le contour du personnage — à leur couleur, ce qui donne une
// silhouette blanche cernée de sombre au lieu d'un aplat.
//
// La valeur par défaut 0.0 blanchit tout, y compris le noir pur
// (step(0.0, luma) vaut 1 pour toute luminance) : le comportement d'origine
// est inchangé pour les appelants qui ne règlent pas cet uniform.
uniform float dark_cutoff : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float luma = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	float amount = white_amount * step(dark_cutoff, luma);
	COLOR = vec4(mix(tex_color.rgb, vec3(1.0), amount), tex_color.a);
}
