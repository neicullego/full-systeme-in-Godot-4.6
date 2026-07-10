# Lamp.gd
# Script à attacher à la racine (RigidBody3D) de la scène "lampe en main"
# (celle référencée par pickup_scene_path sur l'ItemData de type LAMP).
class_name Lamp
extends RigidBody3D

# ── Allumage ──────────────────────────────────────────────────────────────────
@export var spot_light: SpotLight3D
@export var emissive_material: StandardMaterial3D
@export var default_on: bool = true

var is_on: bool = true

# ── Flottabilité (reprise telle quelle de votre script existant) ─────────────
@export var float_force := 1.0
@export var water_drag := 0.05
@export var water_angular_drag := 0.05
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var water = get_tree().get_first_node_in_group("water")
@onready var probes = $ProbeContainer.get_children()
var submerged := false


func _ready() -> void:
	if spot_light == null:
		push_warning("Lamp '%s' : aucun SpotLight3D assigné !" % name)
	if emissive_material == null:
		push_warning("Lamp '%s' : aucun matériau émissif assigné !" % name)
	is_on = default_on
	_apply_state()


func toggle_light() -> void:
	is_on = not is_on
	_apply_state()


func _apply_state() -> void:
	if spot_light:
		spot_light.visible = is_on
	if emissive_material:
		emissive_material.emission_enabled = is_on


func _is_point_in_dry_zone(pt: Vector3) -> bool:
	if water and "active_dry_zones" in water:
		for zone in water.active_dry_zones:
			if "box_half_size" in zone and zone.box_half_size != Vector3.ZERO:
				var local_pt: Vector3 = zone.global_transform.inverse() * pt
				var z_type = zone.zone_type if "zone_type" in zone else 0

				if z_type == 0:
					if abs(local_pt.x) < zone.box_half_size.x and \
					   abs(local_pt.y) < zone.box_half_size.y and \
					   abs(local_pt.z) < zone.box_half_size.z:
						return true
				elif z_type == 1:
					var dx = local_pt.x / zone.box_half_size.x
					var dy = local_pt.y / zone.box_half_size.y
					var dz = local_pt.z / zone.box_half_size.z
					if (dx*dx + dy*dy + dz*dz) < 1.0:
						return true
				elif z_type == 2:
					var dx = local_pt.x / zone.box_half_size.x
					var dz = local_pt.z / zone.box_half_size.z
					if (dx*dx + dz*dz) < 1.0 and abs(local_pt.y) < zone.box_half_size.y:
						return true
	return false


func _physics_process(_delta):
	if not is_instance_valid(water):
		water = get_tree().get_first_node_in_group("water")
		if not is_instance_valid(water):
			return
	submerged = false
	for p in probes:
		var probe_pos = p.global_position
		if _is_point_in_dry_zone(probe_pos):
			continue
		var depth = water.get_height(probe_pos) - probe_pos.y
		if depth > 0:
			submerged = true
			apply_force(Vector3.UP * float_force * gravity * depth, probe_pos - global_position)


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if submerged:
		state.linear_velocity *= 1 - water_drag
		state.angular_velocity *= 1 - water_angular_drag
