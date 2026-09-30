#buoyancy.gd
extends RigidBody3D

@export var float_force := 1.0
@export var water_drag := 0.05
@export var water_angular_drag := 0.05

@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var water = get_tree().get_first_node_in_group("water")

@onready var probes = $ProbeContainer.get_children()

var submerged := false

func _ready():
	pass

func _process(_delta):
	pass

# --- NOUVELLE FONCTION : Vérifie si un point 3D est dans une zone sèche ---
func _is_point_in_dry_zone(pt: Vector3) -> bool:
	if water and "active_dry_zones" in water:
		for zone in water.active_dry_zones:
			# ON UTILISE LA MATRICE PRÉCALCULÉE ! 
			# Fini le zone.global_transform.inverse() très lourd à chaque frame pour chaque sonde.
			var local_pt: Vector3 = zone.zone_inverse_transform * pt
			
			# Accès direct à la propriété (plus rapide que la recherche par chaîne "in")
			var z_type: int = zone.zone_type
			
			if z_type == 0: # ─── BOX ───
				if abs(local_pt.x) < zone.box_half_size.x and \
				   abs(local_pt.y) < zone.box_half_size.y and \
				   abs(local_pt.z) < zone.box_half_size.z:
					return true 
			elif z_type == 1: # ─── SPHERE ───
				# Multiplication plutôt que division (plus facile à digérer pour le processeur)
				var dx = local_pt.x * (1.0 / zone.box_half_size.x)
				var dy = local_pt.y * (1.0 / zone.box_half_size.y)
				var dz = local_pt.z * (1.0 / zone.box_half_size.z)
				if (dx*dx + dy*dy + dz*dz) < 1.0:
					return true
			elif z_type == 2: # ─── CYLINDER (Axe Y) ───
				var dx = local_pt.x * (1.0 / zone.box_half_size.x)
				var dz = local_pt.z * (1.0 / zone.box_half_size.z)
				if (dx*dx + dz*dz) < 1.0 and abs(local_pt.y) < zone.box_half_size.y:
					return true
	return false
# --------------------------------------------------------------------------

func _physics_process(_delta):
	# 1. On vérifie si la référence à l'eau est toujours valide
	if not is_instance_valid(water):
		# 2. Si elle a été détruite (changement de scène), on essaie de la retrouver
		water = get_tree().get_first_node_in_group("water")
		# 3. Si elle n'existe vraiment plus, on annule la physique pour cette frame
		if not is_instance_valid(water):
			return

	submerged = false
	for p in probes:
		var probe_pos = p.global_position
		
		# --- MODIFICATION ICI : On ignore la sonde si elle est dans une zone sèche ---
		if _is_point_in_dry_zone(probe_pos):
			continue # Passe directement à la sonde suivante sans appliquer de force
			
		var depth = water.get_height(probe_pos) - probe_pos.y
		if depth > 0:
			submerged = true
			apply_force(Vector3.UP * float_force * gravity * depth, probe_pos - global_position)

func _integrate_forces(state: PhysicsDirectBodyState3D):
	if submerged:
		state.linear_velocity *=  1 - water_drag
		state.angular_velocity *= 1 - water_angular_drag
