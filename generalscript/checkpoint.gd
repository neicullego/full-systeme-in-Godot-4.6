class_name Checkpoint
extends Area3D

## Optionnel : un Marker3D pour un point de sortie légèrement décalé.
## Si vide, la position du checkpoint lui-même est utilisée.
@export var respawn_point: Marker3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
	var pos: Vector3 = respawn_point.global_position if respawn_point else global_position
	body.set_checkpoint(pos)
