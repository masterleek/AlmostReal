extends RefCounted

## État d'une unité PENDANT un combat — ce qui évolue au fil des tours, par
## opposition à sa définition figée dans `Battle/units.json` (stats de base,
## planches d'animation, portrait) que `BattleData` sert en lecture seule.
##
## Volontairement réduit à ce que les lots livrés exploitent : les PV (Lot 3),
## les points d'action (Lot 4), l'action retenue pour le tour (Lot 5) et les
## stats de combat qu'elle consomme à l'assaut (Lot 6).
##
## DEUX SORTES DE DÉGÂTS. Une attaque « directe » retire les PV tout de suite.
## Une attaque « de blessure » ne les retire pas : elle les met en attente
## (`injury`), affichés en bleu au bout de la jauge. Ce qui décide de leur sort
## est ce qui arrive ENSUITE :
##   - un tour sans le moindre dégât les efface — l'unité guérit de ce qu'elle
##     aurait dû subir ;
##   - une nouvelle blessure s'y ajoute ;
##   - un dégât direct les convertit : tout part des PV d'un coup, augmenté du
##     bonus de conversion.
## Le modèle vit ici ; personne ne l'appelle encore, c'est la phase d'assaut
## (Lot 6) qui infligera les dégâts et refermera les tours.

const BattleData = preload("res://Scripts/Battle/BattleData.gd")

var id: String
var hp: int
var hp_max: int
## Points d'action restants pour le tour en cours. Ils repartent au maximum à
## chaque tour de préparation ; c'est le Lot 5, qui possède la boucle de tour,
## qui appellera restore_ap().
var ap: int
var ap_max: int
## Dégâts de blessure en attente : des PV qui ne sont pas encore perdus, mais
## qui le seront au premier dégât direct. Toujours ≤ hp — une blessure ne peut
## pas mettre en jeu plus de PV que l'unité n'en a.
var injury: int = 0
## Stats de combat, recopiées de units.json au montage. Recopiées plutôt que
## relues à chaque coup : la phase d'assaut les interroge plusieurs fois par
## action, et elles ont vocation à VARIER en combat (buffs, équipement) — ce
## que ne permettrait pas une lecture directe du catalogue, qui est en lecture
## seule et partagé.
var force: int
var defense: int
var agility: int
var luck: int
## L'unité s'est mise en garde pour ce tour : elle encaisse moitié moins
## (cf. BattleRules.GUARD_FACTOR). Posé avant le premier coup de l'assaut,
## effacé à la fin du tour.
var guarding: bool = false
## Action retenue pour ce tour, vide tant que l'unité n'a pas choisi. Sa forme
## est celle des dictionnaires composés par BattleScene (source, id, target,
## cost, targets). Elle est posée à la validation d'une cible et reprise si le
## joueur revient en arrière.
var action: Dictionary = {}

func _init(unit_id: String) -> void:
	id = unit_id
	var stats: Dictionary = BattleData.get_unit(unit_id).get("stats", {})
	hp_max = maxi(1, int(stats.get("hp_max", 1)))
	hp = hp_max
	ap_max = maxi(0, int(stats.get("ap_max", 0)))
	ap = ap_max
	force = int(stats.get("force", 0))
	defense = int(stats.get("defense", 0))
	agility = int(stats.get("agility", 0))
	luck = int(stats.get("luck", 0))

## Bonus appliqué quand des dégâts de blessure sont convertis en dégâts
## directs. L'auteur a confirmé la FORME — une simple addition au total — mais
## pas encore le NOMBRE (cf. docs/plan_systeme_combat.md, « Reste à
## spécifier »). À 0, la conversion se contente donc d'additionner le direct et
## la blessure : c'est le comportement neutre, pas un équilibrage choisi.
const INJURY_CONVERSION_BONUS := 0

## Vrai si l'unité a encaissé quelque chose depuis le début du tour courant.
## C'est cette trace, et elle seule, qui décide si la blessure se referme à la
## fin du tour.
var _damaged_this_turn: bool = false

func is_alive() -> bool:
	return hp > 0

## Dégâts DIRECTS : retirés des PV immédiatement. Une blessure en attente est
## emportée avec, majorée du bonus de conversion — c'est le cas le plus cher
## pour la victime, et la raison de frapper une cible déjà blessée.
func take_direct_damage(amount: int) -> void:
	var total := amount + injury
	if injury > 0:
		total += INJURY_CONVERSION_BONUS
	injury = 0
	hp = maxi(0, hp - total)
	_damaged_this_turn = true

## Dégâts de BLESSURE : mis en attente au lieu d'être retirés. Ils s'ajoutent à
## ceux déjà en attente, sans jamais dépasser les PV restants — la jauge bleue
## ne peut pas déborder du remplissage vert qu'elle ronge.
func take_injury_damage(amount: int) -> void:
	if amount <= 0:
		return
	injury = mini(hp, injury + amount)
	_damaged_this_turn = true

## Soin. Plafonné aux PV max, et il efface la BLESSURE en priorité : rendre des
## PV tout en laissant la part mise en jeu intacte serait incompréhensible à la
## lecture de la jauge, où le soin repousserait le vert dans le bleu.
func heal(amount: int) -> void:
	if amount <= 0:
		return
	injury = maxi(0, injury - amount)
	hp = mini(hp_max, hp + amount)

## Fin de tour : une unité épargnée guérit de sa blessure, et la garde tombe.
## Appelée pour TOUTES les unités, y compris celles qui n'ont rien fait : c'est
## la fin de tour qui remet le compteur de dégâts à zéro pour le tour suivant.
func end_turn() -> void:
	if not _damaged_this_turn:
		injury = 0
	_damaged_this_turn = false
	guarding = false

func has_action() -> bool:
	return not action.is_empty()

func clear_action() -> void:
	action = {}

## Bout de la jauge, blessure comprise : les PV que l'unité a encore.
func hp_ratio() -> float:
	return float(hp) / float(hp_max)

## Part de la jauge remplie en VERT — les PV acquis, blessure déduite. Le
## segment bleu occupe l'espace entre les deux ratios (cf. HpBar.set_ratio).
func solid_ratio() -> float:
	return float(hp - injury) / float(hp_max)

## Un coût nul est toujours payable, y compris par une unité sans PA du tout
## (les objets ne coûtent rien).
func can_pay(cost: int) -> bool:
	return cost <= ap

func spend_ap(cost: int) -> void:
	ap = maxi(0, ap - cost)

func refund_ap(cost: int) -> void:
	ap = mini(ap_max, ap + cost)

func restore_ap() -> void:
	ap = ap_max

## Identifiant Localization du nom affiché, déduit de l'id de l'unité. C'est
## la convention posée par le plan (§3.2) : aucun libellé n'est stocké dans
## units.json, tout passe par le catalogue de textes pour rester traduisible
## depuis la page « Textes » de MapEditor.
func name_text_id() -> String:
	return "unit.%s.name" % id
