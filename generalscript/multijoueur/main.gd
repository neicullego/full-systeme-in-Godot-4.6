extends Node3D

const PlayerScene := preload("res://scene/player/third_player_aventure.tscn")

@onready var players: Node3D = $Players
# 🆕 On récupère la liste des points de spawn que tu as créés dans l'éditeur
@onready var spawn_points: Array[Node] = $SpawnPoints.get_children()

func _ready() -> void:
	if not multiplayer.is_server():
		return

	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)

	for id in multiplayer.get_peers():
		_add_player(id)

	_add_player(1) # le serveur lui-même

func _add_player(id: int) -> void:
	var player := PlayerScene.instantiate()
	player.name = str(id)
	
	# Si tu attribues l'autorité ici, c'est très bien :
	player.set_multiplayer_authority(id)
	
	var spawn_index = players.get_child_count() % spawn_points.size()
	var spawn_pos = spawn_points[spawn_index].global_position
	
	# 1. On applique la position locale avant d'entrer dans l'arbre
	player.position = spawn_pos
	
	# 2. On ajoute à l'arbre (le MultiplayerSpawner réplique l'apparition chez le client)
	players.add_child(player, true)
	
	# 3. Le serveur ordonne au client de définir sa position de spawn
	player.rpc("set_initial_spawn", spawn_pos)
	
	print("Joueur ", id, " a spawn à l'index ", spawn_index, " (", spawn_pos, ")")

func _remove_player(id: int) -> void:
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
