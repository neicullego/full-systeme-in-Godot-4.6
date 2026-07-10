extends Node3D

@export var objet_a: Node3D
@export var objet_b: Node3D
@onready var pivot = $Pivot
@onready var mesh_instance = $Pivot/MeshInstance3D

func _process(_delta: float) -> void:
	if not objet_a or not objet_b:
		return

	var pos_a = objet_a.global_position
	var pos_b = objet_b.global_position
	
	# 1. Placement au centre
	global_position = (pos_a + pos_b) / 2.0
	
	# 2. Orientation du pivot vers l'objet B
	pivot.look_at(pos_b, Vector3.UP)
	pivot.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
	# 3. Étirement uniquement sur le MeshInstance3D
	# On garde scale.x et scale.z à 1.0 (ou leur valeur d'origine) pour ne pas l'écraser
	var distance = pos_a.distance_to(pos_b)
	mesh_instance.scale.y = distance
