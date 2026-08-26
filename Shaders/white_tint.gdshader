shader_type canvas_item;

// Mélange la couleur du sprite vers du blanc pur (silhouette comprise) sans
// jamais toucher à sa transparence, pour teinter une tuile en blanc sans
// avoir besoin d'un calque superposé séparé (cf reveal_tile).
uniform float white_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex_color.rgb, vec3(1.0), white_amount), tex_color.a);
}
