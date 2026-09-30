@tool
extends Area3D

@export var water_node: Node3D
var box_half_size: Vector3 = Vector3.ZERO
@export_enum("Box", "Sphere", "Cylinder") var zone_type: int = 0

# NOUVEAU : Précalcul de la matrice inverse
var zone_inverse_transform: Transform3D

func _ready() -> void:
	var shape_node = $CollisionShape3D
	if shape_node and shape_node.shape:
		var shape = shape_node.shape
		if shape is BoxShape3D:
			box_half_size = shape.size / 2.0
		elif shape is SphereShape3D:
			box_half_size = Vector3(shape.radius, shape.radius, shape.radius)
		elif shape is CylinderShape3D or shape is CapsuleShape3D:
			box_half_size = Vector3(shape.radius, shape.height / 2.0, shape.radius)

	# PRÉCALCUL ICI : affine_inverse() est plus rapide et opti pour l'espace 3D
	zone_inverse_transform = global_transform.affine_inverse()

	if water_node and water_node.has_method("register_dry_zone"):
		water_node.register_dry_zone(self)

# Si tu supprimes une zone en plein jeu, on prévient l'eau pour éviter un crash
func _exit_tree() -> void:
	if water_node and water_node.has_method("unregister_dry_zone"):
		water_node.unregister_dry_zone(self)
