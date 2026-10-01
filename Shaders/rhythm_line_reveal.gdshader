shader_type canvas_item;

// Balayage d'une moitié de la jauge de rythme à l'ouverture/fermeture de
// l'assaut (cf. RhythmBar._reveal_lines/_close_rig) : au lieu d'un fondu
// uniforme OU d'un sprite de lueur séparé qui voyage à côté (essayé, CASSÉ :
// constaté en jeu, un cercle flou posé par-dessus la carte ne se lit pas
// comme « la ligne qui brille », juste comme un objet étranger qui flotte),
// la ligne elle-même se révèle depuis l'anneau (progress = 0) vers le bord
// de l'écran (progress = 1), avec une BRILLANCE qui marque la pointe du
// balayage, DANS la silhouette réelle de l'asset.
//
// `_right` est posée SANS `flip_h` (contrairement au reste de la barre,
// cf. RhythmBar._ready) : `flip_h` retourne aussi l'UV fourni au shader, ce
// qui aurait rendu la direction du balayage ambiguë ici. Le mirroir du
// dégradé se fait donc À LA MAIN (uniform `flip`), et `UV.x` reste toujours
// l'espace ÉCRAN du rectangle dessiné (0 = bord gauche, 1 = bord droit),
// quelle que soit la moitié.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 0.0 : le bord proche de l'anneau est à UV.x = 0 (`_right`).
// 1.0 : le bord proche de l'anneau est à UV.x = 1 (`_left`).
uniform float near_edge_uv = 0.0;
uniform bool flip = false;

// Position de la BRILLANCE, SÉPARÉE de `progress` (qui reste 0..1 et ne pilote
// que le remplissage/`discard`) : au-delà de 1, la ligne est déjà pleinement
// révélée (plus rien à discard), mais la pointe lumineuse continue sa course
// et sort ENTIÈREMENT du cadre plutôt que de s'arrêter pile au bord (demandé
// — constaté en jeu : à pointe=bord, la bosse plafonnait là, visible en
// permanence tant que `shine_strength` ne la coupait pas). `RhythmBar` anime
// cette valeur de 0 à `1 + marge` (ouverture) ou l'inverse (fermeture,
// entrée symétrique depuis hors cadre).
uniform float shine_travel = 0.0;

// Largeur de la pointe lumineuse, en fraction de la largeur de la moitié
// (donc indépendante de la résolution) — assez large pour lire comme un
// dégradé diffus, pas comme un bord dur qui avance.
uniform float shine_width : hint_range(0.01, 0.6) = 0.28;
uniform vec4 shine_color : source_color = vec4(1.0, 0.95, 0.82, 0.6);
// Coupure générale de la brillance (0 = éteinte) : `_reveal_lines`/`_close_rig`
// la mettent à 1 pendant le balayage et la coupent une fois la jauge posée à
// son état de repos (pleinement révélée ou pleinement rétractée) — sinon la
// pointe resterait figée, allumée en permanence, au bord de l'écran tant que
// la jauge reste ouverte.
uniform float shine_strength = 0.0;

void fragment() {
	vec2 uv = flip ? vec2(1.0 - UV.x, UV.y) : UV;
	vec4 tex = texture(TEXTURE, uv);

	float local = abs(UV.x - near_edge_uv);
	if (local > progress) {
		discard;
	}

	// Enveloppe verticale LISSE, PAS un masque sur `tex.a` (essayé, CASSÉ :
	// LINE_EMPTY est un asset presque invisible — alpha moyen 0,003 à 0,04,
	// cf. RhythmBar.gd — et un simple seuil (`step`) sur un alpha aussi bas
	// et aussi bruité tombait des deux côtés du seuil presque au hasard d'un
	// pixel à l'autre, ce qui coupait la brillance en plein milieu de sa
	// propre tache, constaté en jeu). Une enveloppe géométrique, indépendante
	// de ce bruit, centrée sur la hauteur du sprite et qui s'éteint en
	// douceur vers le haut/bas plutôt que d'y être tranchée.
	float vertical = 1.0 - smoothstep(0.25, 0.5, abs(uv.y - 0.5));

	// Distance (en UV) entre ce pixel et la POSITION de la brillance
	// (`shine_travel`, pas `progress`, cf. plus haut) : 0 pile sur la pointe,
	// croît de part et d'autre.
	//
	// BOSSE SYMÉTRIQUE, pas un plateau qui monte jusqu'à `dist_to_edge = 0`
	// (essayé, CASSÉ : constaté en jeu, la pointe touchait alors tout de
	// suite son maximum pile au bord de l'écran — un à-pic net contre le bord
	// de l'image, alors que le même dégradé, côté anneau, avait toute la
	// place pour s'éteindre en douceur). Le sommet est reculé d'une demi-
	// largeur : la brillance monte ET redescend à zéro des DEUX côtés — et
	// comme `shine_travel` continue au-delà de 1, ce second flanc tombe à
	// zéro AVANT le bord, puis la pointe elle-même quitte le cadre.
	float dist_to_edge = shine_travel - local;
	float peak = shine_width * 0.5;
	float shine = (1.0 - smoothstep(0.0, peak, abs(dist_to_edge - peak))) * vertical * shine_strength;

	vec3 rgb = mix(tex.rgb, shine_color.rgb, clamp(shine, 0.0, 1.0));
	float alpha = max(tex.a, shine * shine_color.a);
	COLOR = vec4(rgb, alpha);
}
