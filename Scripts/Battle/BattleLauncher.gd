extends RefCounted

## Ouverture d'un combat par-dessus la scène courante.
##
## Le worldmap n'est PAS déchargé : il est simplement gelé et masqué, et la
## scène de combat est ajoutée à côté. Sortir du combat n'a alors rien à
## restaurer (position du héros, caméra, tuiles révélées, musique…), là où un
## change_scene_to_file() obligerait à sérialiser tout cet état pour le
## reconstruire au retour.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## Instancie le combat au-dessus de `host` (le nœud racine du worldmap).
## `context` est transmis tel quel à BattleScene.setup() ; la capture du fond y
## est ajoutée si elle n'y figure pas déjà.
static func open(host: Node, context: Dictionary = {}) -> CanvasLayer:
	# L'ordre compte : on masque d'abord le seul HUD (sinon le compteur de hex
	# et l'indice d'action se retrouvent gravés dans le fond), on capture, et
	# seulement ensuite on masque le décor. Masquer tout avant la capture — ce
	# que faisait la première version — ne donne évidemment qu'une image vide.
	var hidden := _hide_layers(host)
	if not context.has("background"):
		context["background"] = await capture_background(host)
	hidden.append_array(_hide_world(host))
	host.process_mode = Node.PROCESS_MODE_DISABLED

	var battle: CanvasLayer = BATTLE_SCENE.instantiate()
	battle.setup(context)
	# Le combat ne sait pas ce qui l'a ouvert : il annonce que le joueur a fermé
	# son écran de fin, et c'est ici qu'on sait comment rendre la main. Branché
	# AVANT l'entrée dans l'arbre — `_ready()` peut déjà tout décider si le
	# combat s'ouvre sur une équipe déjà à terre.
	battle.exit_requested.connect(close.bind(battle))
	# Ajouté à la racine de l'arbre, PAS sous `host` : ce dernier est mis en
	# PROCESS_MODE_DISABLED juste au-dessus, ce qui gèlerait aussi ses enfants.
	# L'ordre d'affichage ne dépend pas de la place dans l'arbre — un
	# CanvasLayer se trie sur son `layer`, et celui du combat est au-dessus de
	# tout ce que pose le worldmap.
	host.get_tree().root.add_child(battle)
	battle.set_meta("worldmap_host", host)
	battle.set_meta("hidden_nodes", hidden)
	return battle

## Capture l'image affichée pour servir de fond au combat.
##
## Deux pièges, tous deux déjà rencontrés sur ce projet :
##   - il faut attendre RenderingServer.frame_post_draw, sinon on récupère la
##     frame PRÉCÉDENTE (cf. CLAUDE.md §workflow, point 5) ;
##   - le HUD du worldmap doit déjà être masqué, sinon le compteur de hex et
##     l'indice d'action se retrouvent gravés dans le fond du combat.
static func capture_background(host: Node) -> ImageTexture:
	await RenderingServer.frame_post_draw
	return ImageTexture.create_from_image(host.get_viewport().get_texture().get_image())

## Masque les CanvasLayer du worldmap (son HUD). Séparé du reste parce qu'un
## CanvasLayer se dessine indépendamment de la visibilité de son parent Node2D :
## masquer la racine ne suffirait pas à faire disparaître le HUD, et il doit
## l'être AVANT la capture du fond.
static func _hide_layers(host: Node) -> Array[Node]:
	var hidden: Array[Node] = []
	for child in host.get_children():
		if child is CanvasLayer and child.visible:
			child.visible = false
			hidden.append(child)
	return hidden

## Masque le décor du worldmap, une fois le fond capturé.
##
## Les listes renvoyées par les deux fonctions ne contiennent que les nœuds
## RÉELLEMENT masqués, pour que la sortie de combat ne réaffiche pas quelque
## chose que le jeu avait de toute façon caché avant le combat.
static func _hide_world(host: Node) -> Array[Node]:
	var hidden: Array[Node] = []
	if host is CanvasItem and host.visible:
		host.visible = false
		hidden.append(host)
	return hidden

## Ferme le combat et rend la main au worldmap dans l'état où il était.
static func close(battle: CanvasLayer) -> void:
	var host: Node = battle.get_meta("worldmap_host")
	host.process_mode = Node.PROCESS_MODE_INHERIT
	for node: Node in battle.get_meta("hidden_nodes", []):
		if is_instance_valid(node):
			node.visible = true
	battle.queue_free()
