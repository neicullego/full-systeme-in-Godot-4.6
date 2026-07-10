extends RigidBody3D

@export var required_tool_id: String = "marteau"  # ID du bon outil

func try_interact_with_tool(tool_id: String) -> bool:
	if tool_id == required_tool_id:
		interact_ok.rpc()
		return true
	else:
		print("Il faut un marteau pour ça !")
		return false

@rpc("any_peer", "call_local", "reliable")
func interact_ok():
	print("Planche détachée !")
	# Ici tu peux : jouer une animation, détruire le nœud, spawner des objets...
	queue_free()
