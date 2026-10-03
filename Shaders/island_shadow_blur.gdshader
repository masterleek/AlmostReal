shader_type canvas_item;

// Ombre portée douce des îlots : lit la silhouette (canal alpha) rendue par
// IslandShadow.gd dans un SubViewport, la floute en disque, puis la recolore en
// `shadow_color`. Seul l'alpha de la texture compte, sa couleur est ignorée.
//
// Pourquoi un flou ici et pas sur les tuiles elles-mêmes : chaque tuile n'est
// dessinée que dans sa case de 64×64, une ombre floue ne peut donc pas déborder
// de sa propre case. Flouter la SILHOUETTE ENTIÈRE de l'îlot, une fois, n'a pas
// cette limite et fond les tuiles voisines en une seule ombre continue.
//
// Spirale de Vogel plutôt qu'une grille : répartition régulière des taps sans
// motif visible, avec peu d'échantillons.

uniform float radius_px : hint_range(0.0, 32.0) = 8.0;
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.4;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.05, 0.15, 1.0);

const int TAPS = 28;

void fragment() {
	float a = 0.0;
	for (int i = 0; i < TAPS; i++) {
		float fi = float(i) + 0.5;
		float r = sqrt(fi / float(TAPS));
		float ang = fi * 2.399963;
		vec2 off = vec2(cos(ang), sin(ang)) * r * radius_px * TEXTURE_PIXEL_SIZE;
		a += texture(TEXTURE, UV + off).a;
	}
	a /= float(TAPS);
	COLOR = vec4(shadow_color.rgb, a * shadow_alpha);
}
