extends Node

## Liste de tous les skins disponibles — modifiable depuis l'Inspecteur,
## glissez-y autant de SkinData (.tres) que vous voulez.
@export var available_skins: Array[SkinData] = []

## peer_id (int) -> skin_id (String) choisi par chaque joueur en lobby
var chosen_skins: Dictionary = {}

func get_skin_data(skin_id: String) -> SkinData:
	for s in available_skins:
		if s.skin_id == skin_id:
			return s
	return null

func get_default_skin_id() -> String:
	return available_skins[0].skin_id if available_skins.size() > 0 else ""
