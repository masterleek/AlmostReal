extends RefCounted

## Règles CHIFFRÉES du combat : tout ce qui se calcule, au même endroit.
##
## Pourquoi un fichier à part plutôt que des formules dispersées dans la phase
## d'assaut : ce sont les seuls nombres du combat que l'auteur voudra régler, et
## il doit pouvoir les trouver sans lire la mécanique qui les emploie. Aucune
## de ces fonctions ne touche à l'état du combat — elles prennent des nombres
## et rendent des nombres, ce qui les rend vérifiables isolément.
##
## Ce que ce fichier NE fait pas : décider QUI frappe QUI, ni quand. C'est la
## phase d'assaut (BattleAssault) qui compose, et elle vient chercher ici la
## valeur de chaque coup.

## Formule de dégâts, choisie par l'auteur : ADDITIVE.
##
##     dégâts = (puissance + force) − défense
##
## La défense a donc un poids constant : elle retire toujours le même nombre de
## points, quelle que soit la puissance du coup. Une cible très défensive
## encaisse peu, mais ne devient jamais invulnérable — c'est justement le rôle
## du plancher ci-dessous, qui garantit qu'un coup porté fait toujours quelque
## chose.
##
## L'alternative multiplicative (puissance × force / défense) a été écartée :
## elle creuse les écarts de stats beaucoup plus vite et se règle moins bien.
const MIN_DAMAGE := 1

## Coefficient appliqué aux dégâts subis par une unité en garde. La garde est
## posée AVANT le premier coup de l'assaut (cf. BattleAssault) : elle protège
## donc de tout le tour, et pas seulement de ce qui arrive après le moment où
## l'unité aurait agi.
const GUARD_FACTOR := 0.5

## Dégâts bruts d'un coup, avant garde. Jamais nuls : un coup qui porte fait au
## moins MIN_DAMAGE, sans quoi une unité bien défendue deviendrait impossible à
## entamer et le combat se bloquerait.
static func damage(power: int, force: int, defense: int) -> int:
	return maxi(MIN_DAMAGE, power + force - defense)

## Dégâts effectivement subis, garde comprise. `floori` plutôt qu'un arrondi :
## la garde ne doit jamais AUGMENTER les dégâts d'un point par arrondi
## supérieur. Le plancher reste garanti — une garde ne rend pas invulnérable.
static func guarded(amount: int, guarding: bool) -> int:
	if not guarding:
		return amount
	return maxi(MIN_DAMAGE, floori(amount * GUARD_FACTOR))
