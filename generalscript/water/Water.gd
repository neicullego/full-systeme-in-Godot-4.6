# Water.gd
@tool
extends Node3D

@export var fog_height_offset: float = 0.5 ## Permet de remonter virtuellement la surface de l'eau pour le brouillard (en mètres)

# Variables pour la gestion de la zone sèche (Submarine / Base)
var dry_zone_inverse_matrix: Transform3D = Transform3D()
var dry_zone_half_size: Vector3 = Vector3.ZERO

@export_group("Ambiance Sous-Marine")
@export var underwater_material: ShaderMaterial # <- ASSIGNEZ ICI LE MATÉRIAU DE VOTRE SHADER UNDERWATER

const MAX_DRY_ZONES: int = 8
var active_dry_zones: Array[Area3D] = []

func register_dry_zone(zone: Area3D) -> void:
	if not zone in active_dry_zones:
		active_dry_zones.append(zone)

func unregister_dry_zone(zone: Area3D) -> void:
	active_dry_zones.erase(zone)


@export_category("Type d'Océan")
@export var infinite_ocean: bool = true

@export_group("Délimitation (Si non infini)")
@export var marker_min: Marker3D
@export var marker_max: Marker3D

@export_group("Paramètres des Chunks (LOD)")
@export var chunk_size: float = 32.0
@export var render_distance: int = 4
@export var material_template: ShaderMaterial

# Variables pour mémoriser l'environnement de la surface
var default_volumetric_fog_density: float
var default_fog_enabled: bool
var default_fog_density: float

var default_volumetric_fog_sky_affect: float


## Frames pendant lesquelles le LOD cible doit rester stable avant d'être appliqué.
## Evite les oscillations de mesh qui laissent les chunks "blancs".
@export_range(1, 10) var lod_stability_frames: int = 3

@export_group("Ambiance Sous-Marine")
@export var water_fog_volume: FogVolume
@export var max_depth: float = 30.0
@export var water_fog_color: Color = Color(0.0, 0.1, 0.2)
@export var fog_ramp_speed: float = 0.4

var noise: Image
var noise_width: int
var noise_height: int
var noise_scale: float
var wave_speed: float
var height_scale: float
var time: float

@onready var env: WorldEnvironment = $"../WorldEnvironment"

var active_chunks: Dictionary = {}

# LOD actuellement appliqué par chunk : Vector2i -> int
var chunk_lods: Dictionary = {}

# LOD en attente de stabilité : Vector2i -> { "target": int, "count": int }
var chunk_lod_pending: Dictionary = {}

var last_cam_chunk_pos: Vector2i = Vector2i(99999, 99999)


func _ready() -> void:
	if not material_template:
		push_error("Water.gd : Veuillez assigner un 'Material Template' dans l'inspecteur.")
		return
		
	# --- On sauvegarde les paramètres de l'environnement ---
	if env and env.environment:
		default_volumetric_fog_density = env.environment.volumetric_fog_density
		default_fog_enabled = env.environment.fog_enabled
		default_fog_density = env.environment.fog_density
		default_volumetric_fog_sky_affect = env.environment.volumetric_fog_sky_affect

	noise_scale  = material_template.get_shader_parameter("noise_scale")
	wave_speed   = material_template.get_shader_parameter("wave_speed")
	height_scale = material_template.get_shader_parameter("height_scale")

	var wave_tex: NoiseTexture2D = material_template.get_shader_parameter("wave")
	if wave_tex:
		if wave_tex.get_image() == null:
			await wave_tex.changed

		noise        = wave_tex.get_image()
		if noise:
			noise_width  = noise.get_width()
			noise_height = noise.get_height()

	_update_ocean_grid(true)


func _process(delta: float) -> void:
	time += delta
	
	# Mise à jour du shader de vague
	if material_template:
		material_template.set_shader_parameter("wave_time", time)

	var matrices: Array[Transform3D] = []
	var sizes: PackedVector3Array = PackedVector3Array()
	var types: PackedInt32Array = PackedInt32Array()
	
	var count = min(active_dry_zones.size(), MAX_DRY_ZONES)
	
	# On remplit les tableaux jusqu'à la limite MAX_DRY_ZONES
	for i in range(MAX_DRY_ZONES):
		if i < count:
			var zone = active_dry_zones[i]
			matrices.append(zone.global_transform.inverse())
			sizes.append(zone.box_half_size)
			
			var z_type = zone.zone_type if "zone_type" in zone else 0
			types.append(z_type)
		else:
			matrices.append(Transform3D())
			sizes.append(Vector3.ZERO)
			types.append(0)

	for chunk_instance in active_chunks.values():
		var mi := chunk_instance as MeshInstance3D
		if mi and mi.mesh and mi.mesh.material:
			var mat := mi.mesh.material as ShaderMaterial
			
			mat.set_shader_parameter("wave_time", time)
			mat.set_shader_parameter("dry_zone_count", count)
			mat.set_shader_parameter("dry_matrices", matrices)
			mat.set_shader_parameter("dry_sizes", sizes)
			mat.set_shader_parameter("dry_types", types)
			
	_update_ocean_grid(false)
	
	# L'ambiance sous-marine et l'environnement global ne sont mis à jour QU'EN JEU
	if not Engine.is_editor_hint():
		update_underwater_ambiance()


func _update_ocean_grid(force_update: bool) -> void:
	var cam := _get_active_camera()
	if not cam:
		return

	var cam_pos       := cam.global_position
	var cam_chunk_x   := int(floor(cam_pos.x / chunk_size))
	var cam_chunk_z   := int(floor(cam_pos.z / chunk_size))
	var current_cam_chunk := Vector2i(cam_chunk_x, cam_chunk_z)

	if current_cam_chunk == last_cam_chunk_pos and not force_update:
		return

	last_cam_chunk_pos = current_cam_chunk

	var min_chunk_x: int
	var max_chunk_x: int
	var min_chunk_z: int
	var max_chunk_z: int

	if infinite_ocean:
		min_chunk_x = cam_chunk_x - render_distance
		max_chunk_x = cam_chunk_x + render_distance
		min_chunk_z = cam_chunk_z - render_distance
		max_chunk_z = cam_chunk_z + render_distance
	else:
		if not marker_min or not marker_max:
			return
		min_chunk_x = int(floor(min(marker_min.global_position.x, marker_max.global_position.x) / chunk_size))
		max_chunk_x = int(floor(max(marker_min.global_position.x, marker_max.global_position.x) / chunk_size))
		min_chunk_z = int(floor(min(marker_min.global_position.z, marker_max.global_position.z) / chunk_size))
		max_chunk_z = int(floor(max(marker_min.global_position.z, marker_max.global_position.z) / chunk_size))

	var required_chunks: Array[Vector2i] = []

	for x in range(min_chunk_x, max_chunk_x + 1):
		for z in range(min_chunk_z, max_chunk_z + 1):
			var chunk_coords := Vector2i(x, z)
			required_chunks.append(chunk_coords)

			var distance   := chunk_coords.distance_to(current_cam_chunk)
			var target_lod := _get_subdivisions_for_lod(distance)

			if not active_chunks.has(chunk_coords):
				_create_chunk(chunk_coords, target_lod)
				chunk_lod_pending.erase(chunk_coords)
			else:
				var current_lod: int = chunk_lods.get(chunk_coords, -1)

				if current_lod == target_lod:
					chunk_lod_pending.erase(chunk_coords)
				else:
					if chunk_lod_pending.has(chunk_coords):
						var pending: Dictionary = chunk_lod_pending[chunk_coords]
						if pending["target"] == target_lod:
							pending["count"] += 1
							if pending["count"] >= lod_stability_frames:
								_apply_lod(chunk_coords, target_lod)
								chunk_lod_pending.erase(chunk_coords)
						else:
							chunk_lod_pending[chunk_coords] = { "target": target_lod, "count": 1 }
					else:
						chunk_lod_pending[chunk_coords] = { "target": target_lod, "count": 1 }

	if infinite_ocean:
		var chunks_to_remove: Array = []
		for coord in active_chunks.keys():
			if coord not in required_chunks:
				chunks_to_remove.append(coord)

		for coord in chunks_to_remove:
			if is_instance_valid(active_chunks[coord]):
				active_chunks[coord].queue_free()
			active_chunks.erase(coord)
			chunk_lods.erase(coord)
			chunk_lod_pending.erase(coord)


func _apply_lod(chunk_coords: Vector2i, new_lod: int) -> void:
	if not active_chunks.has(chunk_coords):
		return
	var mesh_instance := active_chunks[chunk_coords] as MeshInstance3D
	if not mesh_instance or not mesh_instance.mesh:
		return
	var plane_mesh := mesh_instance.mesh as PlaneMesh
	if plane_mesh.subdivide_width != new_lod:
		plane_mesh.subdivide_width = new_lod
		plane_mesh.subdivide_depth = new_lod
		chunk_lods[chunk_coords]   = new_lod


func _get_subdivisions_for_lod(distance: float) -> int:
	if distance <= 1.5:
		return 256
	elif distance <= 2.5:
		return 128
	elif distance <= 4.0:
		return 64
	return 16


func _create_chunk(coords: Vector2i, subdivisions: int) -> void:
	var mesh_instance := MeshInstance3D.new()
	var plane_mesh    := PlaneMesh.new()

	plane_mesh.size             = Vector2(chunk_size + 0.145, chunk_size + 0.145)
	plane_mesh.subdivide_width  = subdivisions
	plane_mesh.subdivide_depth  = subdivisions

	if material_template:
		var mat: ShaderMaterial = material_template.duplicate()
		mat.set_shader_parameter("chunk_world_offset",
			Vector2(coords.x * chunk_size, coords.y * chunk_size))
		mat.set_shader_parameter("wave_time", time)
		plane_mesh.material = mat

	mesh_instance.mesh  = plane_mesh
	add_child(mesh_instance)

	mesh_instance.global_position = Vector3(
		coords.x * chunk_size + (chunk_size * 0.5),
		global_position.y,
		coords.y * chunk_size + (chunk_size * 0.5)
	)

	active_chunks[coords] = mesh_instance
	chunk_lods[coords]    = subdivisions


func _sample_bilinear(uv: Vector2) -> float:
	if noise == null:
		return 0.0
	var px: float = uv.x * noise_width  - 0.5
	var py: float = uv.y * noise_height - 0.5
	var x0: int = posmod(int(floor(px)),     noise_width)
	var y0: int = posmod(int(floor(py)),     noise_height)
	var x1: int = posmod(int(floor(px)) + 1, noise_width)
	var y1: int = posmod(int(floor(py)) + 1, noise_height)
	var fx: float = px - floor(px)
	var fy: float = py - floor(py)
	var c00: float = noise.get_pixel(x0, y0).r
	var c10: float = noise.get_pixel(x1, y0).r
	var c01: float = noise.get_pixel(x0, y1).r
	var c11: float = noise.get_pixel(x1, y1).r
	return lerp(lerp(c00, c10, fx), lerp(c01, c11, fx), fy)


func get_height(world_position: Vector3) -> float:
	if noise == null:
		return global_position.y
	var uv1 := Vector2(
		fposmod(world_position.x / noise_scale + time * wave_speed, 1.0),
		fposmod(world_position.z / noise_scale + time * wave_speed, 1.0)
	)
	var uv2 := Vector2(
		fposmod(world_position.x / (noise_scale * 0.4) + time * (wave_speed * 1.5), 1.0),
		fposmod(world_position.z / (noise_scale * 0.4) + time * (wave_speed * 1.5), 1.0)
	)
	var h1: float = _sample_bilinear(uv1)
	var h2: float = _sample_bilinear(uv2)
	return global_position.y + ((h1 * 0.7) + (h2 * 0.3)) * height_scale


func update_underwater_ambiance() -> void:
	var cam := _get_active_camera()
	if not cam or not env:
		return

	var surface_y := global_position.y
	
	var cam_in_dry := false
	for zone in active_dry_zones:
		if "box_half_size" in zone and zone.box_half_size != Vector3.ZERO:
			var local_cam_pt: Vector3 = zone.global_transform.inverse() * cam.global_position
			var z_type = zone.zone_type if "zone_type" in zone else 0
			
			if z_type == 0: # BOX
				if abs(local_cam_pt.x) < zone.box_half_size.x and \
				   abs(local_cam_pt.y) < zone.box_half_size.y and \
				   abs(local_cam_pt.z) < zone.box_half_size.z:
					cam_in_dry = true
					break
			elif z_type == 1: # SPHERE
				var dx = local_cam_pt.x / zone.box_half_size.x
				var dy = local_cam_pt.y / zone.box_half_size.y
				var dz = local_cam_pt.z / zone.box_half_size.z
				if (dx*dx + dy*dy + dz*dz) < 1.0:
					cam_in_dry = true
					break
			elif z_type == 2: # CYLINDER
				var dx = local_cam_pt.x / zone.box_half_size.x
				var dz = local_cam_pt.z / zone.box_half_size.z
				if (dx*dx + dz*dz) < 1.0 and abs(local_cam_pt.y) < zone.box_half_size.y:
					cam_in_dry = true
					break

	var depth := 0.0
	if not cam_in_dry:
		depth = surface_y - cam.global_position.y

	if underwater_material:
		underwater_material.set_shader_parameter("time", time)
		underwater_material.set_shader_parameter("dry_zone_inverse_matrix", dry_zone_inverse_matrix)
		underwater_material.set_shader_parameter("dry_zone_half_size", dry_zone_half_size)
		underwater_material.set_shader_parameter("camera_in_dry_zone", cam_in_dry)
		
		underwater_material.set_shader_parameter("inv_view_matrix", cam.global_transform)
		underwater_material.set_shader_parameter("inv_projection_matrix", cam.get_camera_projection().inverse())

	if water_fog_volume and water_fog_volume.material:
		var fog_mat := water_fog_volume.material as ShaderMaterial
		fog_mat.set_shader_parameter("surface_y",  surface_y + fog_height_offset)
		fog_mat.set_shader_parameter("max_depth",  max_depth)
		fog_mat.set_shader_parameter("fog_color",  water_fog_color)
		if infinite_ocean:
			water_fog_volume.global_position.x = cam.global_position.x
			water_fog_volume.global_position.z = cam.global_position.z
			water_fog_volume.global_position.y = (surface_y + fog_height_offset) - (water_fog_volume.size.y * 0.5)

	var fog_depth: float = depth + fog_height_offset

	if env and env.environment:
		if fog_depth > 0:
			var depth_factor = clamp(fog_depth / max_depth, 0.0, 1.0)
			var fast_factor  := pow(depth_factor, fog_ramp_speed)
			
			env.environment.fog_light_color      = water_fog_color
			env.environment.volumetric_fog_sky_affect = 1.0
		else:
			env.environment.ambient_light_energy = 1.0
			env.environment.fog_enabled          = default_fog_enabled
			env.environment.fog_density          = default_fog_density
			env.environment.volumetric_fog_density = default_volumetric_fog_density
			env.environment.volumetric_fog_sky_affect = default_volumetric_fog_sky_affect


func _get_active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		# On vérifie et récupère le singleton via une chaîne de caractères
		if Engine.has_singleton("EditorInterface"):
			var editor_interface = Engine.get_singleton("EditorInterface")
			var viewport_3d = editor_interface.get_editor_viewport_3d(0)
			return viewport_3d.get_camera_3d() if viewport_3d else null
		return null
	else:
		return get_viewport().get_camera_3d()
