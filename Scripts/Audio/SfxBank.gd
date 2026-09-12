extends Node

## Banque de lecteurs audio, montée comme enfant de l'écran qui s'en sert.
##
## POURQUOI UN FICHIER À PART. Deux besoins cohabitent, et un `AudioStreamPlayer`
## seul n'en couvre qu'un :
##
##   - les sons FIXES (déplacement dans un menu, validation, erreur) : leur flux
##     ne change jamais, un lecteur dédié chacun suffit ;
##   - les sons VARIABLES, dont le flux est choisi à l'exécution — celui que
##     porte une action de combat, par exemple. Un lecteur unique n'en joue
##     qu'un par frame : le second écrase le premier, SANS ERREUR. D'où un petit
##     pool, et un cache par chemin pour ne pas relire le disque en plein
##     mouvement.
##
## Rien ici ne connaît le combat : le vocabulaire est « un son », « une
## musique », « un chemin ». C'est réutilisable tel quel par le worldmap, qui
## pose aujourd'hui ses lecteurs un par un dans sa scène.

## Nombre de lecteurs du pool. Quatre parce qu'une action de combat peut
## accrocher deux sons au même moment (un cri et un impact) et qu'il faut de la
## marge avant que voler un son en cours devienne visible.
const DEFAULT_VOICES := 4

## Lecteurs du pool, pour les flux choisis à l'exécution.
var _voices: Array[AudioStreamPlayer] = []
## Flux déjà chargés, indexés par chemin. Un échec est mémorisé sous forme de
## `null` : le fichier manquant est une faute de frappe dans une donnée, à
## signaler UNE fois, pas à chaque coup.
var _cache: Dictionary = {}

func _ready() -> void:
	if _voices.is_empty():
		set_voices(DEFAULT_VOICES)

## Redimensionne le pool. Appelable avant l'entrée dans l'arbre pour un écran
## qui sait avoir besoin d'autre chose que la valeur par défaut.
func set_voices(count: int) -> void:
	while _voices.size() < count:
		_voices.append(_new_player())

## Un lecteur DÉDIÉ à `stream`, à garder sous la main par l'appelant. Pour les
## sons dont le flux ne change jamais : les jouer depuis le pool les exposerait
## à se faire voler leur lecteur.
func player(stream: AudioStream) -> AudioStreamPlayer:
	var node := _new_player()
	node.stream = stream
	return node

## Lance une musique en boucle, à `volume` exprimé en PROPORTION (0,75 = 75 %).
##
## Le bouclage est une propriété de la RESSOURCE, pas du lecteur : il se force
## ici plutôt que de dépendre du réglage d'import. Conséquence assumée — c'est la
## ressource partagée qu'on modifie, deux lecteurs sur le même fichier ne
## peuvent pas boucler différemment.
func music(stream: AudioStream, volume: float = 1.0) -> AudioStreamPlayer:
	var node := player(stream)
	node.stream.loop = true
	node.volume_linear = volume
	node.play()
	return node

## Joue le son qui se trouve à `path`, quel qu'il soit. C'est l'entrée des sons
## choisis par la donnée : l'appelant n'a pas de lecteur à gérer.
func play_path(path: String) -> void:
	if path == "":
		return
	if not _cache.has(path):
		# `exists` d'abord : `load()` sur un chemin absent hurle dans la console
		# à CHAQUE appel, alors qu'un chemin faux est une faute de frappe dans
		# une donnée, à signaler une fois.
		_cache[path] = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
		if _cache[path] == null:
			push_warning("SfxBank : son introuvable (%s)" % path)
	var stream: AudioStream = _cache[path]
	if stream == null:
		return
	var voice := _free_voice()
	voice.stream = stream
	voice.play()

## Un lecteur libre, ou le premier de la liste si tous sont occupés. Voler un son
## en cours vaut mieux que de laisser tomber celui qu'on vient de demander :
## c'est le plus récent qui correspond à ce que le joueur regarde.
func _free_voice() -> AudioStreamPlayer:
	if _voices.is_empty():
		set_voices(DEFAULT_VOICES)
	for voice in _voices:
		if not voice.playing:
			return voice
	return _voices[0]

func _new_player() -> AudioStreamPlayer:
	var node := AudioStreamPlayer.new()
	add_child(node)
	return node
