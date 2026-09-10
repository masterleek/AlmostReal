extends RefCounted

## État d'une unité PENDANT un combat — ce qui évolue au fil des tours, par
## opposition à sa définition figée dans `Battle/units.json` (stats de base,
## planches d'animation, portrait) que `BattleData` sert en lecture seule.
##
## Volontairement réduit à ce que les lots livrés exploitent : les PV (Lot 3)
## et les points d'action (Lot 4). La garde et l'action planifiée viendront
## avec les lots qui les introduisent (5 et 6) plutôt que d'être posées ici
## « au cas où » — une structure vide qu'on remplit plus tard invite surtout à
## s'en écarter.

const BattleData = preload("res://Scripts/Battle/BattleData.gd")

var id: String
var hp: int
var hp_max: int
## Points d'action restants pour le tour en cours. Ils repartent au maximum à
## chaque tour de préparation ; c'est le Lot 5, qui possède la boucle de tour,
## qui appellera restore_ap().
var ap: int
var ap_max: int

func _init(unit_id: String) -> void:
	id = unit_id
	var stats: Dictionary = BattleData.get_unit(unit_id).get("stats", {})
	hp_max = maxi(1, int(stats.get("hp_max", 1)))
	hp = hp_max
	ap_max = maxi(0, int(stats.get("ap_max", 0)))
	ap = ap_max

func is_alive() -> bool:
	return hp > 0

func hp_ratio() -> float:
	return float(hp) / float(hp_max)

## Un coût nul est toujours payable, y compris par une unité sans PA du tout
## (les objets ne coûtent rien).
func can_pay(cost: int) -> bool:
	return cost <= ap

func spend_ap(cost: int) -> void:
	ap = maxi(0, ap - cost)

func restore_ap() -> void:
	ap = ap_max

## Identifiant Localization du nom affiché, déduit de l'id de l'unité. C'est
## la convention posée par le plan (§3.2) : aucun libellé n'est stocké dans
## units.json, tout passe par le catalogue de textes pour rester traduisible
## depuis la page « Textes » de MapEditor.
func name_text_id() -> String:
	return "unit.%s.name" % id
