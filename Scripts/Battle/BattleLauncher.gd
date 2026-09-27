extends RefCounted

## Ouverture d'un combat par-dessus la scène courante.
##
## Le worldmap n'est PAS déchargé : il est simplement gelé, et la scène de combat
## est ajoutée à côté. Sortir du combat n'a alors rien à restaurer (position du
## héros, caméra, tuiles révélées, musique…), là où un change_scene_to_file()
## obligerait à sérialiser tout cet état pour le reconstruire au retour.
##
## IL RESTE AFFICHÉ, EN DIRECT, derrière le combat : c'est son décor qui sert de
## fond, sous le voile noir de la scène (cf. Battle.tscn, BackgroundDim). Seul
## son HUD disparaît. Il n'y a plus de capture d'écran — un fond figé à
## recadrer, remettre à l'échelle du canvas et agrandir pour qu'aucun
## déplacement n'en découvre le bord.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## Instancie le combat au-dessus de `host` (le nœud racine du worldmap).
## `context` est transmis à BattleScene.setup(), complété ici de
## `intro_focus` (sauf s'il y figure déjà) : la position ÉCRAN du Hero du
## worldmap, sur laquelle l'iris d'ouverture se referme (cf. BattleIntro).
## Relevée AVANT de geler `host`, donc telle qu'elle était encore à l'instant
## du déclenchement — figer `host` ne change de toute façon pas une position
## déjà lue, mais autant le faire avant par clarté.
static func open(host: Node, context: Dictionary = {}) -> CanvasLayer:
	var full_context := context.duplicate()
	if not full_context.has("intro_focus"):
		var hero := host.get_node_or_null("Hero")
		if hero is Node2D:
			# Même conversion monde -> écran que WorldmapCursor.world_to_screen,
			# tient compte de la position ET du zoom de la caméra.
			full_context["intro_focus"] = (
				host.get_viewport().get_canvas_transform() * (hero as Node2D).global_position
			)

	var hidden := _hide_layers(host)
	# Gelé, pas masqué : il continue d'être dessiné, mais plus rien n'y bouge ni
	# n'y répond aux entrées — le combat a la main.
	host.process_mode = Node.PROCESS_MODE_DISABLED

	var battle: CanvasLayer = BATTLE_SCENE.instantiate()
	battle.setup(full_context)
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

## Masque les CanvasLayer du worldmap (son HUD). Un CanvasLayer se dessine
## indépendamment de la visibilité de son parent Node2D : c'est lui qu'il faut
## masquer, le décor restant, lui, affiché.
static func _hide_layers(host: Node) -> Array[Node]:
	var hidden: Array[Node] = []
	for child in host.get_children():
		if child is CanvasLayer and child.visible:
			child.visible = false
			hidden.append(child)
	return hidden

## Ferme le combat et rend la main au worldmap dans l'état où il était.
##
## La liste ne contient que les nœuds RÉELLEMENT masqués à l'ouverture, pour ne
## pas réafficher quelque chose que le jeu avait de toute façon caché avant.
static func close(battle: CanvasLayer) -> void:
	var host: Node = battle.get_meta("worldmap_host")
	host.process_mode = Node.PROCESS_MODE_INHERIT
	for node: Node in battle.get_meta("hidden_nodes", []):
		if is_instance_valid(node):
			node.visible = true
	battle.queue_free()
