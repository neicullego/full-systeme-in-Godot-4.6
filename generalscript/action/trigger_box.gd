extends Node3D

# Expose la variable dans l'inspecteur pour y glisser le nœud AnimationPlayer
@export var animation_player: AnimationPlayer

# Optionnel : Expose aussi le nom de l'animation pour plus de flexibilité
@export var animation_name: String = "nom_de_l_animation"

var repetition = false

func _ready() -> void:
	repetition = false

func _process(delta: float) -> void:
	pass

func _on_area_3d_body_entered(body: Node3D) -> void:
	# 1. On vérifie si l'entité qui entre possède bien le groupe "Player"
	if body.is_in_group("Player") and not repetition:
		repetition = true
		
		# 2. On vérifie que seul l'hôte/serveur autorise le déclenchement (Optionnel mais recommandé pour éviter le double-déclenchement)
		if multiplayer.is_server():
			# 3. On appelle la fonction RPC sur tous les pairs connectés
			play_networked_animation.rpc()


# L'annotation @rpc configure la fonction pour le réseau :
# "call_local" : Exécute la fonction sur la machine qui l'appelle en plus des autres
# "reliable"   : S'assure que le paquet réseau ne sera pas perdu en route
@rpc("call_local", "reliable")
func play_networked_animation() -> void:
	# Sécurité : on vérifie que le nœud a bien été assigné dans l'éditeur
	if animation_player:
		animation_player.play(animation_name)
	else:
		push_warning("Attention : L'AnimationPlayer n'a pas été assigné dans l'inspecteur de " + name)
