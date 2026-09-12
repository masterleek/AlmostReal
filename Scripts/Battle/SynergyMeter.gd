extends RefCounted

## Charge de synergie de l'ÉQUIPE — pas d'une unité. C'est ce qui la distingue
## des PV et des PA : elle se construit sur tout le combat, quel que soit celui
## qui joue, et c'est bien le sens du mot.
##
## CE QUI LA REMPLIT, décidé par l'auteur : la QUALITÉ DU RYTHME. Un Perfect
## remplit beaucoup, un Great moins, un Good à peine, un Miss rien. La synergie
## récompense donc la maîtrise de la mécanique centrale du jeu, et se construit
## autant en attaque qu'en défense — la barre tourne dans les deux sens.
##
## CE QU'ELLE DÉBLOQUE n'est pas encore défini : l'auteur décrira sa compétence
## spéciale plus tard. Le niveau est exposé pour qu'elle s'y branche sans que
## rien d'autre bouge, et `spend()` est déjà là — l'auteur a tranché ce
## point-là : l'utiliser VIDE la jauge entièrement, ce qui met le joueur devant
## un vrai arbitrage entre frapper au niveau 1 ou attendre le niveau 3.

const BattleRules = preload("res://Scripts/Battle/BattleRules.gd")
const SynergyGauge = preload("res://Scripts/Battle/UI/SynergyGauge.gd")

## Niveau atteint, de 0 à SynergyGauge.MAX_LEVEL.
var level: int = 0
## Remplissage du niveau EN COURS, dans [0,1]. Au niveau maximum il reste à 1 :
## la jauge est pleine et ne déborde pas.
var progress: float = 0.0

## Ajoute ce que vaut une séquence de rythme. Chaque note compte séparément :
## une séquence de quatre notes réussies vaut donc quatre fois une note seule,
## ce qui récompense les Ekos longs.
func add(judgements: Array) -> void:
	if level >= SynergyGauge.MAX_LEVEL:
		progress = 1.0
		return
	for judgement: int in judgements:
		progress += BattleRules.synergy_gain(judgement)
		while progress >= 1.0 and level < SynergyGauge.MAX_LEVEL:
			progress -= 1.0
			level += 1
	if level >= SynergyGauge.MAX_LEVEL:
		level = SynergyGauge.MAX_LEVEL
		progress = 1.0

## Vide la jauge. Appelée quand la compétence spéciale est déclenchée.
func spend() -> void:
	level = 0
	progress = 0.0

## La compétence est-elle disponible ? Le plan le dit : à partir du niveau 1.
func is_ready() -> bool:
	return level >= 1
