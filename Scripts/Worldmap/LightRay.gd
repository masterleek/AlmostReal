extends ColorRect

## Un seul rayon de lumière (cf light_rays.gdshader), pensé pour être
## dupliqué librement (Ctrl+D dans l'éditeur, ou instancier LightRay.tscn
## plusieurs fois) : pour en ajouter un, on duplique ce nœud et on le
## déplace où on veut (Transform > Position, dans l'Inspecteur) — aucun
## code à toucher.
##
## Duplique son propre ShaderMaterial au démarrage : sans ça, toutes les
## copies partageraient LA MÊME ressource de matériau, et régler l'une
## (couleur, angle, largeur...) changerait toutes les autres en même temps.
## Une fois dupliqué, chaque copie a ses propres Shader Parameters,
## indépendants, éditables directement dans l'Inspecteur de CETTE instance.
##
## Tire aussi une phase de scintillement aléatoire (shimmer_seed) à chaque
## démarrage : sans ça, deux rayons dupliqués clignoteraient parfaitement en
## phase l'un avec l'autre (même valeur par défaut) — pas besoin d'y toucher
## à la main pour que plusieurs rayons scintillent de façon désynchronisée.

func _ready() -> void:
	if material:
		material = material.duplicate()
		material.set_shader_parameter("shimmer_seed", randf() * 1000.0)
