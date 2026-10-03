# Caméra classique corrigée
extends Camera3D

# Le(s) matériau(x) de vos vitres de base sous-marine
@export var glass_materials: Array[ShaderMaterial]

# L'eau n'est plus figée une seule fois dans _ready() : elle est (re)résolue et validée
# à chaque frame par _ensure_water(). Sinon on peut rester accroché à l'eau d'une autre scène.
var water = null

@onready var post_process_rect = $CanvasLayer/ColorRect

# --- NOUVEAU : Glissez votre noeud de bulles (GPUParticles3D) ici dans l'inspecteur ---
@export var bubble_particles: GPUParticles3D 

const WATERLINE_SAMPLES := 128
const BINARY_STEPS      := 12

var waterline_image:   Image
var waterline_texture: ImageTexture

func _ready() -> void:
	# Priorité 1 pour tout le monde afin de s'exécuter après la mise à jour du script de l'eau
	process_priority = 1

	# L'effet d'écran reste MASQUÉ par défaut : _process() ne l'affiche que s'il y a de l'eau
	# dans la scène ET que cette caméra est la caméra active.
	if post_process_rect:
		post_process_rect.visible = false

	# On ne fait pas de "return" ici, on laisse le process se lancer pour les bulles
	if is_multiplayer_authority():
		# L'initialisation de l'effet d'écran ne se fait que pour le joueur local
		_init_waterline()


# Création de la texture de ligne d'eau. Appelée depuis _ready() ET, au besoin, depuis
# _process() si l'autorité n'était pas encore attribuée lors du _ready().
func _init_waterline() -> void:
	waterline_image   = Image.create(WATERLINE_SAMPLES, 1, false, Image.FORMAT_RF)
	waterline_image.fill(Color(1.1, 0.0, 0.0, 1.0)) # 1.1 = "à sec" tant que rien n'est calculé
	waterline_texture = ImageTexture.create_from_image(waterline_image)

	if post_process_rect and post_process_rect.material:
		var mat: ShaderMaterial = post_process_rect.material

		# Copie PRIVÉE du matériau : on ne le partage plus avec la caméra du joueur
		# (sinon les deux s'écrasent mutuellement les paramètres du shader).
		# EXCEPTION : si ce matériau est aussi `underwater_material` de Water.gd, Water.gd
		# lui envoie des paramètres (inv_view_matrix, camera_in_dry_zone...). Une copie ne
		# les recevrait plus, donc on garde alors l'original.
		var w = _find_water()
		var driven_by_water: bool = w != null and "underwater_material" in w and w.underwater_material == mat
		if not driven_by_water:
			mat = mat.duplicate() as ShaderMaterial
			post_process_rect.material = mat

		mat.set_shader_parameter("waterline_texture", waterline_texture)


# Cherche l'eau qui appartient à LA MÊME scène que cette caméra, en ignorant celles
# qui sont en cours de suppression.
func _find_water() -> Node:
	var candidates: Array[Node] = get_tree().get_nodes_in_group("water")
	if candidates.is_empty():
		return null

	# Racine de "ma" scène = l'ancêtre direct de /root
	var scene_root: Node = self
	while scene_root.get_parent() != null and scene_root.get_parent() != get_tree().root:
		scene_root = scene_root.get_parent()

	for w in candidates:
		if not w.is_queued_for_deletion() and scene_root.is_ancestor_of(w):
			return w
	# Repli : première eau valide, même si elle est dans une autre branche
	for w in candidates:
		if not w.is_queued_for_deletion():
			return w
	return null


# Garantit que `water` pointe vers une eau vivante, dans l'arbre, et pas en cours de suppression.
func _ensure_water() -> bool:
	if is_instance_valid(water) and water.is_inside_tree() and not water.is_queued_for_deletion():
		return true

	var new_water = _find_water()
	# Petit log de diagnostic (uniquement quand ça change)
	if new_water != water:
		print("[", name, "] eau résolue : ", str(new_water.get_path()) if new_water else "AUCUNE")
	water = new_water
	return water != null


# Pas d'eau valide : on coupe tous les effets pour ne pas garder un état périmé.
func _disable_effects() -> void:
	if bubble_particles:
		bubble_particles.emitting = false
	if has_node("Underwater_ambiance") and $Underwater_ambiance.playing:
		$Underwater_ambiance.stop()
	if post_process_rect:
		post_process_rect.visible = false


func _is_lens_underwater(screen_pos: Vector2, z_depth: float) -> bool:
	if not is_instance_valid(water):
		return false

	var pt3d: Vector3 = project_position(screen_pos, z_depth)
	
	# ─── Vérification sur TOUTES les zones sèches actives (Multi-Formes) ───
	if "active_dry_zones" in water:
		for zone in water.active_dry_zones:
			# Zone libérée pendant un changement de scène : on l'ignore au lieu de planter.
			if not is_instance_valid(zone):
				continue
			# --- MODIFICATION ICI : On utilise la version optimisée de la caméra joueur ---
			var local_pt: Vector3
			# On vérifie si la propriété précalculée existe (au cas où)
			if "zone_inverse_transform" in zone:
				local_pt = zone.zone_inverse_transform * pt3d
			else:
				# Fallback de sécurité si la propriété n'est pas encore là
				local_pt = zone.global_transform.inverse() * pt3d
				
			var z_type = zone.zone_type if "zone_type" in zone else 0
			
			if z_type == 0: # ─── BOX ───
				if abs(local_pt.x) < zone.box_half_size.x and \
				   abs(local_pt.y) < zone.box_half_size.y and \
				   abs(local_pt.z) < zone.box_half_size.z:
					return false 
			elif z_type == 1: # ─── SPHERE ───
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

# --- AJOUTE CETTE FONCTION POUR COUPER LE SON À LA SUPPRESSION ---
func _exit_tree() -> void:
	_stop_watching()
	if has_node("Underwater_ambiance") and $Underwater_ambiance.playing:
		$Underwater_ambiance.stop()


# ─── MODE "PAS D'EAU DANS LA SCÈNE" ─────────────────────────────────────────────
# Aucune eau trouvée = la scène n'en contient pas. On coupe alors TOUT : plus d'effet
# d'écran, plus de bulles, plus de son, et surtout plus aucun _process (zéro calcul par frame).
# Si une eau est ajoutée plus tard dans l'arbre, on se réveille automatiquement
# (signal node_added : pas de polling, donc aucun coût tant que rien ne se passe).
var _watching_for_water: bool = false

func _go_dormant() -> void:
	_disable_effects()
	set_process(false)
	if not _watching_for_water:
		get_tree().node_added.connect(_on_node_added)
		_watching_for_water = true


func _on_node_added(node: Node) -> void:
	if node.is_in_group("water") and _ensure_water():
		_stop_watching()
		set_process(true)


func _stop_watching() -> void:
	if not _watching_for_water:
		return
	_watching_for_water = false
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


# --- REMPLACE TOUTE TA FONCTION _process PAR CELLE-CI ---
func _process(_delta: float) -> void:
	# Pas d'eau dans la scène -> on ne calcule plus rien (voir _go_dormant)
	if not _ensure_water():
		_go_dormant()
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var base_z: float = 0.05
	
	# 1. On détermine l'état global de la caméra
	var is_active_camera = is_multiplayer_authority() and is_current()
	var cam_is_underwater: bool = _is_lens_underwater(vp / 2.0, base_z)

	# 2. GESTION DU SON (Placée AVANT le return pour pouvoir s'arrêter !)
	if is_active_camera and cam_is_underwater:
		if not $Underwater_ambiance.playing:
			$Underwater_ambiance.play()
	else:
		# Coupe le son si la caméra n'est plus active (skip) OU si on entre dans une zone sèche
		if $Underwater_ambiance.playing:
			$Underwater_ambiance.stop()

	# 3. GESTION DES BULLES
	if bubble_particles:
		bubble_particles.emitting = (is_active_camera and cam_is_underwater)
		
		if is_active_camera and bubble_particles.draw_pass_1:
			var bubble_mat = bubble_particles.draw_pass_1.material as ShaderMaterial
			if bubble_mat:
				bubble_mat.set_shader_parameter("dry_zone_inverse_matrix", water.dry_zone_inverse_matrix)
				bubble_mat.set_shader_parameter("dry_zone_half_size", water.dry_zone_half_size)
				
				if "material_template" in water and water.material_template:
					var w_mat = water.material_template as ShaderMaterial
					if w_mat:
						bubble_mat.set_shader_parameter("wave", w_mat.get_shader_parameter("wave"))
						bubble_mat.set_shader_parameter("noise_scale", w_mat.get_shader_parameter("noise_scale"))
						bubble_mat.set_shader_parameter("height_scale", w_mat.get_shader_parameter("height_scale"))
						bubble_mat.set_shader_parameter("wave_speed", w_mat.get_shader_parameter("wave_speed"))
						bubble_mat.set_shader_parameter("wave_time", water.time)
						bubble_mat.set_shader_parameter("water_base_y", water.global_position.y)

	# 4. BLOC DE SÉCURITÉ : On arrête les calculs lourds si la caméra est inactive
	if not is_active_camera:
		if post_process_rect:
			post_process_rect.visible = false
		return

	# =======================================================================
	# ─── CODE EXCLUSIF : UNIQUEMENT L'AUTORITÉ LOCALE ET ACTIVE (Visuels) ──
	# =======================================================================
	if post_process_rect:
		post_process_rect.visible = true
	if waterline_image == null:
		_init_waterline()
		
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
	
