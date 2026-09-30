#Caméra du joueur 
extends Camera3D

# Le(s) matériau(x) de vos vitres de base sous-marine
@export var glass_materials: Array[ShaderMaterial]

@onready var water = get_tree().get_first_node_in_group("water")

@onready var post_process_rect = $CanvasLayer/ColorRect

# --- NOUVEAU : Glissez votre noeud de bulles (GPUParticles3D) ici dans l'inspecteur ---
@export var bubble_particles: GPUParticles3D 

const WATERLINE_SAMPLES := 64
const BINARY_STEPS      := 6

var waterline_image:   Image
var waterline_texture: ImageTexture

func _ready() -> void:
	# Priorité 1 pour tout le monde afin de s'exécuter après la mise à jour du script de l'eau
	process_priority = 1

	if not is_multiplayer_authority():
		if post_process_rect:
			post_process_rect.visible = false
		# On ne fait pas de "return" ici, on laisse le process se lancer pour les bulles
	else:
		post_process_rect.visible = true
		# L'initialisation de l'effet d'écran ne se fait que pour le joueur local
		waterline_image   = Image.create(WATERLINE_SAMPLES, 1, false, Image.FORMAT_RF)
		waterline_texture = ImageTexture.create_from_image(waterline_image)

		if post_process_rect and post_process_rect.material:
			var mat: ShaderMaterial = post_process_rect.material
			mat.set_shader_parameter("waterline_texture", waterline_texture)

func _is_lens_underwater(screen_pos: Vector2, z_depth: float) -> bool:
	var pt3d: Vector3 = project_position(screen_pos, z_depth)
	
	# ─── Vérification sur TOUTES les zones sèches actives (Multi-Formes) ───
	if water and "active_dry_zones" in water:
		for zone in water.active_dry_zones:
			# ON UTILISE LA MATRICE PRÉCALCULÉE ! Fini l'inversion à chaque pixel
			var local_pt: Vector3 = zone.zone_inverse_transform * pt3d
			var z_type: int = zone.zone_type
			
			if z_type == 0: # ─── BOX ───
				if abs(local_pt.x) < zone.box_half_size.x and \
				   abs(local_pt.y) < zone.box_half_size.y and \
				   abs(local_pt.z) < zone.box_half_size.z:
					return false 
			elif z_type == 1: # ─── SPHERE ───
				# Multiplication plutôt que division (plus rapide)
				var dx = local_pt.x * (1.0 / zone.box_half_size.x)
				var dy = local_pt.y * (1.0 / zone.box_half_size.y)
				var dz = local_pt.z * (1.0 / zone.box_half_size.z)
				if (dx*dx + dy*dy + dz*dz) < 1.0:
					return false
			elif z_type == 2: # ─── CYLINDER (Axe Y) ───
				var dx = local_pt.x * (1.0 / zone.box_half_size.x)
				var dz = local_pt.z * (1.0 / zone.box_half_size.z)
				if (dx*dx + dz*dz) < 1.0 and abs(local_pt.y) < zone.box_half_size.y:
					return false
	# ───────────────────────────────────────────────────────────────────────
	
	var wave_h: float = water.get_height(pt3d)
	return pt3d.y < wave_h
	
func _process(_delta: float) -> void:
	# Si l'eau n'est pas encore prête dans la scène, on ne fait rien
	if not water:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var base_z: float = 0.05

	# =======================================================================
	# ─── CODE COMMUN : EXÉCUTÉ PAR TOUT LE MONDE (Autorité + Marionnettes) ───
	# =======================================================================
	
	# Détermination de l'état de la caméra (gère nativement les zones sèches)
	var cam_is_underwater: bool = _is_lens_underwater(vp / 2.0, base_z)
	
	if not $Underwater_ambiance.playing:
		if cam_is_underwater:
			$Underwater_ambiance.play()
	if $Underwater_ambiance.playing:
		if not cam_is_underwater:	
			$Underwater_ambiance.stop()
	
	if bubble_particles:
		# Gestion de l'émission globale selon la position de la caméra de chaque joueur
		bubble_particles.emitting = cam_is_underwater
		
		# On met à jour le shader des bulles pour qu'elles disparaissent individuellement dans les zones sèches
		if bubble_particles.draw_pass_1:
			var bubble_mat = bubble_particles.draw_pass_1.material as ShaderMaterial
			if bubble_mat:
				bubble_mat.set_shader_parameter("dry_zone_inverse_matrix", water.dry_zone_inverse_matrix)
				bubble_mat.set_shader_parameter("dry_zone_half_size", water.dry_zone_half_size)
				
				# Synchronisation des vagues sur le shader des bulles
				if "material_template" in water and water.material_template:
					var w_mat = water.material_template as ShaderMaterial
					if w_mat:
						bubble_mat.set_shader_parameter("wave", w_mat.get_shader_parameter("wave"))
						bubble_mat.set_shader_parameter("noise_scale", w_mat.get_shader_parameter("noise_scale"))
						bubble_mat.set_shader_parameter("height_scale", w_mat.get_shader_parameter("height_scale"))
						bubble_mat.set_shader_parameter("wave_speed", w_mat.get_shader_parameter("wave_speed"))
						bubble_mat.set_shader_parameter("wave_time", water.time)
						bubble_mat.set_shader_parameter("water_base_y", water.global_position.y)
	

	# =======================================================================
	# ─── CODE EXCLUSIF : UNIQUEMENT L'AUTORITÉ LOCALE (Effets d'écran) ───
	# =======================================================================
	if not is_multiplayer_authority():
		if post_process_rect:
			post_process_rect.visible = false
		return # Les autres joueurs s'arrêtent ici !

	# Sécurité pour le joueur local
	if not post_process_rect or not post_process_rect.material:
		return

	var mat: ShaderMaterial = post_process_rect.material as ShaderMaterial
	var current_time: float = water.time
	mat.set_shader_parameter("time",         current_time)
	mat.set_shader_parameter("wave_time_u",  current_time)

	# Calcul de la spline de la ligne d'eau pour l'effet d'écran du joueur local
	for i in range(WATERLINE_SAMPLES):
		var sx: float = float(i) / float(WATERLINE_SAMPLES - 1) * vp.x

		var hits_top: bool = _is_lens_underwater(Vector2(sx, 1.0),         base_z)
		var hits_bot: bool = _is_lens_underwater(Vector2(sx, vp.y - 1.0),  base_z)

		var col_val: float

		if hits_top == hits_bot:
			col_val = -0.1 if hits_top else 1.1
		else:
			var y_lo: float = 1.0
			var y_hi: float = vp.y - 1.0
			for step in range(BINARY_STEPS):
				var y_mid: float = (y_lo + y_hi) * 0.5
				if _is_lens_underwater(Vector2(sx, y_mid), base_z) == hits_top:
					y_lo = y_mid
				else:
					y_hi = y_mid
			col_val = (y_lo * 0.5 + y_hi * 0.5) / vp.y

		if waterline_image:
			waterline_image.set_pixel(i, 0, Color(col_val, 0.0, 0.0, 1.0))

	if waterline_texture and waterline_image:
		waterline_texture.update(waterline_image)
		
	# On transmet la ligne d'eau générée à toutes nos vitres locales
	for glass_mat in glass_materials:
		if glass_mat and "material_template" in water and water.material_template:
			var w_mat = water.material_template as ShaderMaterial
			if w_mat:
				glass_mat.set_shader_parameter("wave", w_mat.get_shader_parameter("wave"))
				glass_mat.set_shader_parameter("noise_scale", w_mat.get_shader_parameter("noise_scale"))
				glass_mat.set_shader_parameter("height_scale", w_mat.get_shader_parameter("height_scale"))
				glass_mat.set_shader_parameter("wave_speed", w_mat.get_shader_parameter("wave_speed"))
				
				glass_mat.set_shader_parameter("wave_time", water.time)
				glass_mat.set_shader_parameter("water_base_y", water.global_position.y)
