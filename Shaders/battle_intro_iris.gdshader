shader_type canvas_item;

// Voile d'ouverture du combat (BackgroundDim) : au lieu d'apparaître d'un
// bloc, il se referme en cercle sur le point de focale du combat (le centre
// de la plateforme), comme un iris qui se ferme — d'abord juste les coins de
// l'écran dans l'ombre, puis un cercle qui rétrécit autour du combattant,
// jusqu'à avaler tout l'écran. `center` et `radius` sont en PIXELS ÉCRAN
// (FRAGCOORD), pas en coordonnées locales du ColorRect porteur : ça reste
// valable quel que soit son propre repère, et `radius` s'anime en GDScript
// (cf BattleIntro._close_iris) du plus grand que la diagonale de l'écran
// (rien d'assombri) jusqu'à 0 (tout assombri — l'état de repos).
//
// `dim_color` DOIT reprendre la couleur du ColorRect (cf BackgroundDim.color) :
// CONTRAIREMENT À UN Polygon2D, COLOR n'arrive PAS pré-rempli avec la couleur
// d'un ColorRect quand un shader lui est attaché (constaté : sans ce
// uniform, `fragment()` ne partait de rien d'assombri, silencieusement — un
// COLOR resté à sa valeur par défaut plutôt que Color(0,0,0,0.5)).
uniform vec2 center = vec2(960.0, 540.0);
uniform float radius = 2000.0;
uniform float feather = 48.0;
uniform vec4 dim_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
	float dist = length(FRAGCOORD.xy - center);
	COLOR = dim_color;
	COLOR.a *= smoothstep(radius - feather, radius + feather, dist);
}
