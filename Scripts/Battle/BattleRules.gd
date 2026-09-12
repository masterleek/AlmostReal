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

## ──────────────────────────────────────────────────────────────────────────
##  RYTHME
## ──────────────────────────────────────────────────────────────────────────

## Verdict d'une note. L'ordre compte : il indexe les deux tables ci-dessous.
enum Judgement { PERFECT, GREAT, GOOD, MISS }

## Ce qu'un bon timing rapporte quand c'est l'équipe qui frappe, et ce qu'il
## épargne quand c'est elle qui encaisse. Valeurs données par l'auteur.
##
## Les deux tables se lisent ensemble : un Perfect multiplie les dégâts par 1,5
## à l'attaque et les divise par deux en défense — donc il compte à peu près
## autant dans les deux sens. Un Miss ne PUNIT pas, il ne récompense pas : les
## deux tables valent 1, et le combat se joue alors sur les seules stats. C'est
## la règle tranchée au §7 du plan — un bon timing réduit les dégâts subis sans
## jamais les annuler, d'où un plancher à 0,5 et non à 0.
const ATTACK_MULTIPLIER: Array[float] = [1.5, 1.25, 1.1, 1.0]
const DEFENCE_MULTIPLIER: Array[float] = [0.5, 0.7, 0.85, 1.0]

## Ce qu'une note rapporte à la jauge de synergie, en fraction de niveau. Même
## indexation que les tables ci-dessus.
##
## À 0,25 pour un Perfect, il faut quatre notes parfaites pour gagner un niveau,
## et une douzaine de Good. RIEN N'EST RELEVÉ ICI : c'est un réglage de rythme de
## progression, à sentir en jouant — la référence `synergy.jpg` ne montre que les
## états de la jauge, pas ce qui la remplit.
const SYNERGY_GAIN: Array[float] = [0.25, 0.15, 0.07, 0.0]

static func synergy_gain(judgement: int) -> float:
	return SYNERGY_GAIN[clampi(judgement, 0, SYNERGY_GAIN.size() - 1)]

## Multiplicateur d'une SÉQUENCE, à partir de ses verdicts note par note.
##
## Moyenne, et pas le meilleur ni le dernier : une séquence de quatre notes doit
## valoir plus qu'une seule note réussie, et rater la moitié d'un Eko doit se
## voir. Une séquence vide rend 1 — l'action n'avait rien à jouer.
static func rhythm_attack(judgements: Array) -> float:
	return _average(judgements, ATTACK_MULTIPLIER)

static func rhythm_defence(judgements: Array) -> float:
	return _average(judgements, DEFENCE_MULTIPLIER)

static func _average(judgements: Array, table: Array[float]) -> float:
	if judgements.is_empty():
		return 1.0
	var total := 0.0
	for judgement: int in judgements:
		total += table[clampi(judgement, 0, table.size() - 1)]
	return total / float(judgements.size())

## Dégâts effectivement subis, garde comprise. `floori` plutôt qu'un arrondi :
## la garde ne doit jamais AUGMENTER les dégâts d'un point par arrondi
## supérieur. Le plancher reste garanti — une garde ne rend pas invulnérable.
static func guarded(amount: int, guarding: bool) -> int:
	if not guarding:
		return amount
	return maxi(MIN_DAMAGE, floori(amount * GUARD_FACTOR))
