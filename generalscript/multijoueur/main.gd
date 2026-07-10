extends Node3D

const PlayerScene := preload("res://scene/player/first_player.tscn")

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
	
	# 🆕 On détermine quel point de spawn utiliser.
	# players.get_child_count() donne 0 pour le 1er joueur, 1 pour le 2ème, etc.
	# Le modulo (%) permet de revenir à 0 si jamais il y a plus de joueurs que de points.
	var spawn_index = players.get_child_count() % spawn_points.size()
	var spawn_pos = spawn_points[spawn_index].global_position
	
	players.add_child(player, true)
	
	# 🆕 On assigne la position unique au joueur
	player.global_position = spawn_pos
	player.set_initial_spawn(spawn_pos)
	
	print("Joueur ", id, " a spawn à l'index ", spawn_index, " (", spawn_pos, ")")

func _remove_player(id: int) -> void:
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
