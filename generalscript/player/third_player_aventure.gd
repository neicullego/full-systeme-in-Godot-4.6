extends CharacterBody3D

@onready var ik_toe_left:  Node = $Marker3D/PhysicsMan/Armature/Skeleton3D/TwoBoneIK_PiedGauche
@onready var ik_toe_right: Node = $Marker3D/PhysicsMan/Armature/Skeleton3D/TwoBoneIK_PiedDroit

@onready var target_toe_left:  Marker3D = $IKTargetOrteilGauche
@onready var target_toe_right: Marker3D = $IKTargetOrteilDroit

@onready var head_clearance_ray: RayCast3D = $CeilingRay # ← À ajouter dans l'éditeur au-dessus de la tête du joueur
const CLEARANCE_CHECK_DISTANCE := 0.84                   # Mètres à vérifier au-dessus de la tête
var is_crouching := false                               # Déclare-le explicitement si tu ne le fais pas déjà

# 🆕 BRAS GAUCHE — mêmes mécanismes que le droit, dédié au portage à deux mains
@onready var left_arm_ik: Node = $Marker3D/PhysicsMan/Armature/Skeleton3D/TwoBoneIK_arme_left
@onready var hand_left_target: Marker3D = $main_gauche
var _left_arm_ik_influence: float = 0.0

# 🆕 PORTAGE D'OBJETS À DEUX MAINS
@onready var carry_spring_arm: SpringArm3D = $CameraPivot/CarrySpringArm3D
@onready var carry_target_marker: Marker3D = $CameraPivot/CarrySpringArm3D/CarryTargetMarker

var isCarryingObject: bool = false
var carriedObject = null
var carriedLeftMarker: Marker3D = null
var carriedRightMarker: Marker3D = null
var _is_carrying_left: bool = false

@export_group("Portage à deux mains")
@export var carry_min_spring_length: float = 1.0
@export var carry_max_spring_length: float = 1.5
@export var carry_zoom_speed: float = 0.1          # mètres par cran de molette
@export var carry_rotation_speed: float = 90.0     # degrés/seconde, R ou T maintenu
@export var carry_left_arm_ik_speed: float = 10.0


var climb_blend_val := 0.0

# ── ÉCHELLE (grimpe façon Minecraft) ───────────────────────────────────────────
@export_group("Échelle")
@export var ladder_climb_speed: float = 2.5     # Vitesse de montée/descente (m/s)
@export var ladder_strafe_speed: float = 1.2    # Vitesse de glissement latéral sur l'échelle
@export_range(0.0, 1.0) var ladder_grab_deadzone: float = 0.35  # Seuil pour s'accrocher (0-1)
@export var ladder_allow_jump_off: bool = true  # Saut = se détacher en repoussant le joueur
@export var ladder_face_wall: bool = false      # Oriente le corps face au mur pendant la grimpe (teste-le, cf. notes)

var current_ladder: Ladder3D = null             # Échelle actuellement en zone (peut être null)
var is_climbing_ladder: bool = false
var _nearby_ladders: Array[Ladder3D] = []       # Si plusieurs zones d'échelle se chevauchent
var _ladder_release_cooldown: float = 0.0       # Anti-ré-accrochage instantané après un lâcher

@onready var lamp_aim_marker: Marker3D = $CameraPivot/LampAimMarker

var wearing_heavy_suit = false

# ── SYSTÈME DE BRUITS DE PAS ──────────────────────────────────────────────────
@export_group("Bruits de pas")
@export var step_interval: float = 1.5 # Distance (en mètres) entre chaque pas
@export var sound_dirt: Array[AudioStream]
@export var sound_metal: Array[AudioStream]
@export var sound_wood: Array[AudioStream]
@export var sound_concrete: Array[AudioStream] # Ajoute autant de matières que tu veux

@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer # Assure-toi du nom du nœud

var _step_distance_accumulator: float = 0.0
var _last_foot_was_left: bool = false

@export_group("Apnée / Oxygène")
@export var base_max_oxygen: float = 20.0        # Secondes d'apnée de base
@export var oxygen_drain_rate: float = 1.0       # Unités/s perdues, tête immergée
@export var oxygen_regen_rate: float = 4.0       # Unités/s récupérées, tête hors de l'eau
@export var drowning_damage_per_sec: float = 8.0 # Dégâts/s une fois à 0 d'air

## Profondeur (m) à partir de laquelle le malus de profondeur commence (0 = dès l'immersion)
@export var depth_drain_start: float = 0.0
## Profondeur (m) où la pression devient mortelle et où le malus atteint son maximum — sans scaphandre
@export var depth_damage_threshold: float = 150.0
## Multiplicateur de consommation d'air atteint à depth_damage_threshold, sans scaphandre (1.0 = aucun effet)
@export var depth_oxygen_drain_multiplier: float = 4.0
## Dégâts/s infligés au-delà de depth_damage_threshold, sans scaphandre
@export var depth_damage_per_sec: float = 15.0

var max_oxygen: float = 20.0
var current_oxygen: float = 20.0

@onready var oxygen_bar_ui = $InventoryController/CanvasLayer/OxygenBar



@onready var camera_remote: RemoteTransform3D = $Marker3D/PhysicsMan/Armature/Skeleton3D/BoneAttachment3D2Mouth/Remotecamera
var _camera_attached_to_body: bool = true   # true = comportement normal (caméra sur la capsule)

# ── VARIABLES RÉSEAU (foot placement marionnettes) ────────────────────────────
@export var _net_velocity: Vector3 = Vector3.ZERO   # Vélocité synchronisée
@export var _net_is_on_floor: bool = true            # État sol synchronisé
@export var _net_is_turning: bool = false            # Rotation sur place synchronisée

# ── CLIMB OUT (Sortie de bassin) ───────────────────────────────────────────────
var _is_climbing_out: bool = false
var _climb_out_target: Vector3 = Vector3.ZERO
var _climb_out_timer: float = 0.0

@export_group("Climb Out")
@export var climb_out_speed: float = 5.0    # Vitesse de remontée
@export var climb_out_timeout: float = 3.0  # Sécurité : annule si bloqué

## Signal de progression du cooldown (optionnel — à connecter à une barre de progression UI)
signal cooldown_progress(progress: float)  # 0.0 → 1.0
 
var _is_cooldown_interacting: bool = false
var _cooldown_timer: float = 0.0
var _cooldown_duration: float = 3.0
var _cooldown_callback: Callable
var _cooldown_target_node: Node = null   # Référence à l'objet cible (pour vérifier la portée)
var _cooldown_marker: Marker3D = null    # Marker IK de la cible



# Marqueur de l'item en cours de ramassage (comme heldMarker pour les portes)
var _pickup_marker: Marker3D = null
var _wants_to_drop_pickup: bool = false
var heldMarker = null
#Système de déplacement du bras kinématique inverse
# Pour la main (Hand IK)
@onready var right_arm_ik: Node = $Marker3D/PhysicsMan/Armature/Skeleton3D/TwoBoneIK_arme_right # Vérifiez ce chemin!
var hand_target_position: Vector3 = Vector3.ZERO
var hand_target_rotation: Quaternion = Quaternion.IDENTITY
var _hand_lerp_speed: float = 10.0 # Vitesse de transition de la main
@onready var hand_right_target: Marker3D = $main_droite

# État d'interaction amélioré
var is_hand_interact_active = false
var _arm_ik_influence: float = 0.0

#Systèmes dinteraction du personnage
var isHoldingObject = false
var heldObject = null

# --- VARIABLES EAU & NAGE ---
@onready var water = get_tree().get_first_node_in_group("water") # Vérifie que ce chemin est correct
@onready var water_probe = $WaterProbe # Le Marker3D au niveau du torse
@onready var swim_detect_probe = $SwimDetectProbe # NOUVEAU : Marqueur BAS (Bassin/Genoux) -> Active le mode nage

@export var float_force := 2.5 # Force de remontée à la surface
const SWIM_SPEED = 2.5
var is_swimming := false
var swim_blend_val := 0.0


@export_group("Foot IK - Os des pieds")


@export var toe_left_bone_name: String  = "mixamorig_LeftToeBase"
@export var toe_right_bone_name: String = "mixamorig_RightToeBase"

var _toe_l_idx: int = -1
var _toe_r_idx: int = -1
var _toe_rotation_left:  Quaternion = Quaternion.IDENTITY
var _toe_rotation_right: Quaternion = Quaternion.IDENTITY




@onready var anim_tree = $AnimationTree
@onready var camera_pivot = $CameraPivot 
@onready var lookhead: LookAtModifier3D = $Marker3D/PhysicsMan/Armature/Skeleton3D/ModifierBoneTarget3D

@onready var stand_collision = $CollisionShape3D
@onready var crouch_collision = $CrouchCollisionSphere
@onready var crouch_collision2 = $CrouchCollisionSphere2
@onready var swimming_collision_sphere: Node3D = $SwimmingCollisionSphere

@export_range(0.0, 1.0) var sensitivity: float = 0.25
@export var turn_threshold: float = 75.0 # L'angle max avant que le perso ne se retourne

const WALK_SPEED = 2.0
const RUN_SPEED = 6.0
const JUMP_VELOCITY = 6.5
const ACCELERATION = 5.0
const FRICTION = 8.0

const PITCH_MIN = -80.0
const PITCH_MAX = 80.0

var current_blend_position := Vector2.ZERO
var run_blend_val := 0.0
var jump_blend_val := 0.0
var turn_blend_val := 0.0 # Pour le Blend3 de rotation sur place

var cam_yaw: float = 0.0
var cam_pitch: float = 0.0

var is_turning_in_place: bool = false

const CROUCH_SPEED = 1.0
var crouch_blend_val := 0.0

@onready var inventory_controller : Node = %InventoryController/CanvasLayer/InventoryUI
@onready var interaction_raycast : RayCast3D = $CameraPivot/PhysicsRayCast

var cam_original_height : float
@export var crouch_cam_offset : float = -0.6 # La descente demandée
@export var cam_lerp_speed : float = 10.0  # Pour la fluidité du mouvement

@onready var document_ui: DocumentUI = $InventoryController/CanvasLayer/DocumentUI

@onready var mouth_anchor: Marker3D = $Marker3D/PhysicsMan/Armature/Skeleton3D/BoneAttachment3D2Mouth/MouthAnchor

# ── SYSTÈME DE VIE ────────────────────────────────────────────────────────────
@export var max_health: float = 100.0
var current_health: float = 100.0
@onready var health_bar_ui = $InventoryController/CanvasLayer/HealthBar

@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $Marker3D/PhysicsMan/Armature/Skeleton3D/PhysicalBoneSimulator3D

var is_dead: bool = false

# ── RÉSERVES D'OXYGÈNE PAR TENUE ──────────────────────────────────────────────
# Clé : "" pour la tenue civile, sinon l'item_id de l'habit porté.
# Valeur : secondes d'air restantes, mémorisées indépendamment pour chaque tenue.
var _oxygen_reserves: Dictionary = {}

var _last_checkpoint_position: Vector3 = Vector3.ZERO
var _has_checkpoint: bool = false
var _initial_spawn_position: Vector3 = Vector3.ZERO

var _is_aiming_lamp: bool = false

## Appelée par l'InventoryController quand la lampe équipée s'allume/s'éteint
## (ou change de main). Active/désactive la visée IK.
func set_lamp_aiming(active: bool) -> void:
	_is_aiming_lamp = active

func set_checkpoint(pos: Vector3) -> void:
	_last_checkpoint_position = pos
	_has_checkpoint = true
	if is_multiplayer_authority():
		print("[Checkpoint] Nouveau point de réapparition enregistré.")


# 🛠️ On remplace "authority" par "any_peer" pour autoriser le serveur à l'exécuter
@rpc("any_peer", "call_local", "reliable")
func set_initial_spawn(pos: Vector3) -> void:
	_initial_spawn_position = pos
	global_position = pos

func _oxygen_key_for(data: ItemData) -> String:
	return data.item_id if data else ""

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	add_to_group("Player")   # 🆕

# Modifie take_damage et heal pour mettre à jour l'UI
func take_damage(amount: float) -> void:
	if not is_multiplayer_authority():
		$InventoryController/CanvasLayer/HealthBar.visible = false
		return
	get_tree().call_group("effects", "flash_damage")
	$InventoryController/CanvasLayer/HealthBar.visible = true
	# Ignore les dégâts si déjà mort
	if is_dead:
		return
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_bar_ui.update(current_health, max_health)
	print("[Santé] PV : ", current_health, " / ", max_health)
	if current_health <= 0.0:
		_die()

func heal(amount: float) -> void:
	if not is_multiplayer_authority():
		$InventoryController/CanvasLayer/HealthBar.visible = false
		return
	$InventoryController/CanvasLayer/HealthBar.visible = true
	current_health = clamp(current_health + amount, 0.0, max_health)
	health_bar_ui.update(current_health, max_health)
	print("[Santé] PV : ", current_health, " / ", max_health)
	
## Redonne de l'air au joueur (ex: bouteille d'oxygène). Purement local à l'autorité,
## exactement comme heal()/take_damage() — aucune synchro réseau nécessaire.
func refill_oxygen(amount: float) -> void:
	if not is_multiplayer_authority():
		return
	current_oxygen = min(current_oxygen + amount, max_oxygen)
	if oxygen_bar_ui:
		oxygen_bar_ui.update(current_oxygen, max_oxygen)
		oxygen_bar_ui.visible = current_oxygen < max_oxygen
	$Inspiration.play()
	print("[Oxygène] Bouteille utilisée : ", current_oxygen, " / ", max_oxygen)
	
var cam_original_local_position: Vector3 = Vector3.ZERO  # Position EXACTE définie dans l'éditeur

func _ready():
	current_oxygen = base_max_oxygen
	max_oxygen = base_max_oxygen
	_oxygen_reserves[""] = current_oxygen   # 🆕 réserve initiale de la tenue civile
	if oxygen_bar_ui:
		oxygen_bar_ui.visible = false
	cam_original_height = camera_pivot.position.y
	cam_original_local_position = camera_pivot.position   # ← AJOUT : on capture x, y ET z
	# 🆕 Remplace la dépendance à Main.gd, qui ne tourne jamais côté client.
	# Le nœud "Players" a la même position dans la scène, chez tous les pairs.
	var players_container := get_parent()
	if players_container:
		_initial_spawn_position = players_container.global_position
	if is_multiplayer_authority():
		$CameraPivot/SpringArm3D/Camera3D.current = true
		$InventoryController/CanvasLayer/HealthBar.visible = true
	if not is_multiplayer_authority():
		$CameraPivot/SpringArm3D/Camera3D.current = false
		$InventoryController/CanvasLayer/HealthBar.visible = false
	carry_spring_arm.add_excluded_object(get_rid()) 
	var ray_vector = Vector3(0, -2.5, 0)
	ik_toe_left.active = true   # _ready() et _rpc_sync_respawn() → true
	ik_toe_right.active = true  # _rpc_sync_death() → false
	anim_tree.active = true
	right_arm_ik.active = true
	left_arm_ik.active = true
	ik_left.active = true
	ik_right.active = true
	lookhead.active = true
	var inventory_ui = $InventoryController/CanvasLayer/InventoryUI
	inventory_ui.player_node = self
	inventory_ui.hand_anchor = $Marker3D/PhysicsMan/Armature/Skeleton3D/BoneAttachment3D/HandItemAnchor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam_yaw = camera_pivot.rotation_degrees.y
	cam_pitch = camera_pivot.rotation_degrees.x
	cam_original_height = camera_pivot.position.y
	
	health_bar_ui.update(current_health, max_health)
	
	# 🆕 Application du skin choisi en lobby — déterministe, aucun RPC nécessaire ici :
	# SkinRegistry.chosen_skins est déjà identique chez tous les pairs au moment où le joueur apparaît.
	var my_skin_id: String = SkinRegistry.chosen_skins.get(name.to_int(), SkinRegistry.get_default_skin_id())
	_apply_skin(my_skin_id)
	
	#Système de footplacement 
	# Récupérer l'index de l'os du bassin
	_pelvis_bone_idx = skeleton.find_bone(pelvis_bone_name)
	if _pelvis_bone_idx == -1:
		push_warning("FootIK: Os '%s' introuvable dans le squelette !" % pelvis_bone_name)
	
	# Initialiser les positions des cibles IK à la position actuelle
	_smooth_pos_left  = target_left.global_position
	_smooth_pos_right = target_right.global_position
	
	camera_remote.remote_path = NodePath("")
	camera_remote.update_rotation = false   # la rotation reste gérée par cam_pitch / cam_yaw
	camera_remote.update_scale = false
	
	head_clearance_ray.target_position = Vector3.UP * CLEARANCE_CHECK_DISTANCE
	head_clearance_ray.collision_mask = 1               # ⚠️ Change selon la Layer de tes murs/plafonds
	

	# Récupérer les os des pieds
	_foot_l_idx = skeleton.find_bone(foot_left_bone_name)
	if _foot_l_idx == -1:
		push_warning("FootIK: Os du pied gauche introuvable !")
		
	_foot_r_idx = skeleton.find_bone(foot_right_bone_name)
	if _foot_r_idx == -1:
		push_warning("FootIK: Os du pied droit introuvable !")
		
	_toe_l_idx = skeleton.find_bone(toe_left_bone_name)
	if _toe_l_idx == -1:
		push_warning("FootIK: Os orteil gauche introuvable !")

	_toe_r_idx = skeleton.find_bone(toe_right_bone_name)
	if _toe_r_idx == -1:
		push_warning("FootIK: Os orteil droit introuvable !")
	_ignore_self_collisions(self)
	print("Fin du _ready() du joueur : ", global_position)
		
		
	
@onready var doc = $InventoryController/CanvasLayer/DocumentUI
func _input(event):
	if is_multiplayer_authority():
	
		var inventory_ui = $InventoryController/CanvasLayer/InventoryUI
		if Input.is_action_pressed("inventory") or not doc.is_open:
			if not doc.is_open:
				inventory_ui.is_inventory_open = true  # ← NOUVEAU
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				interaction_raycast.enabled = false
			else:
				inventory_controller.visible = true
				inventory_ui.is_inventory_open = true  # ← NOUVEAU
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				interaction_raycast.enabled = false
		else:
			inventory_controller.visible = false
			inventory_ui.is_inventory_open = false  # ← NOUVEAU
			interaction_raycast.enabled = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		
	
			if event is InputEventMouseMotion:
				cam_yaw -= event.relative.x * sensitivity
				cam_yaw = wrapf(cam_yaw, -180.0, 180.0)
				
				# CHANGEMENT ICI : On utilise += pour inverser le sens vertical
				cam_pitch += event.relative.y * sensitivity 
				cam_pitch = clamp(cam_pitch, PITCH_MIN, PITCH_MAX)
			if event.is_action_pressed("interact"):
				_try_inspect_equipped_item()
			if event.is_action_pressed("interact"):
				_try_use_equipped_item()
				
			# 🆕 Molette : ajuste la distance de l'objet porté (longueur du spring arm)
			if isCarryingObject and event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					carry_spring_arm.spring_length = clamp(
						carry_spring_arm.spring_length + carry_zoom_speed,
						carry_min_spring_length, carry_max_spring_length
					)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					carry_spring_arm.spring_length = clamp(
						carry_spring_arm.spring_length - carry_zoom_speed,
						carry_min_spring_length, carry_max_spring_length
					)

			if event.is_action_pressed("interact"):
				_try_inspect_equipped_item()
			
func _try_use_equipped_item() -> void:
	var inventory_ui = $InventoryController/CanvasLayer/InventoryUI

	# Vérifie qu'un item est équipé
	if inventory_ui.equipped_slot == null or inventory_ui.equipped_slot.is_empty():
		return

	var data: ItemData = inventory_ui.equipped_slot.item_data

	# Selon le type de l'item équipé
	match data.item_type:
		ItemData.ItemType.CONSUMABLE:
			# Même fonction que depuis l'inventaire
			inventory_ui._use_consumable(inventory_ui.equipped_slot)
		ItemData.ItemType.INSPECTABLE:
			# Ouvre le document
			if document_ui.is_open:
				document_ui.open(data)
		ItemData.ItemType.TOOL:
			# Même fonction que depuis l'inventaire
			inventory_ui._use_tool(inventory_ui.equipped_slot)
		ItemData.ItemType.COOLDOWN_TOOL:              # ← ajouter
			inventory_ui._use_cooldown_tool(inventory_ui.equipped_slot)

## Tente d'inspecter l'item actuellement équipé en main
func _try_inspect_equipped_item() -> void:
	var inventory_ui = $InventoryController/CanvasLayer/InventoryUI
	
	# Vérifie qu'un item est équipé
	if inventory_ui.equipped_slot == null or inventory_ui.equipped_slot.is_empty():
		print("[Inspection] Aucun item équipé.")
		return

	var data: ItemData = inventory_ui.equipped_slot.item_data

	# Vérifie que c'est bien un document
	if data.item_type != ItemData.ItemType.INSPECTABLE:
		print("[Inspection] Cet item n'est pas un document.")
		return
	if document_ui.is_open:
		document_ui.open(data)


func _is_in_dry_zone(pos: Vector3) -> bool:
	if not water or not "active_dry_zones" in water:
		return false
		
	for zone in water.active_dry_zones:
		# On utilise la matrice précalculée au lieu de la recalculer !
		var local_pt: Vector3 = zone.zone_inverse_transform * pos
		var z_type: int = zone.zone_type
		
		# On a retiré les vérifications par chaîne de caractères. Accès direct !
		if z_type == 0: # ─── BOX ───
			if abs(local_pt.x) < zone.box_half_size.x and \
			   abs(local_pt.y) < zone.box_half_size.y and \
			   abs(local_pt.z) < zone.box_half_size.z:
				return true
		elif z_type == 1: # ─── SPHERE ───
			# Astuce : La multiplication est plus rapide que la division pour le CPU
			var dx = local_pt.x / zone.box_half_size.x
			var dy = local_pt.y / zone.box_half_size.y
			var dz = local_pt.z / zone.box_half_size.z
			if (dx*dx + dy*dy + dz*dz) < 1.0:
				return true
		elif z_type == 2: # ─── CYLINDER (Axe Y) ───
			var dx = local_pt.x / zone.box_half_size.x
			var dz = local_pt.z / zone.box_half_size.z
			if (dx*dx + dz*dz) < 1.0 and abs(local_pt.y) < zone.box_half_size.y:
				return true
	return false

func _process(delta):
	if is_dead:
		return
	if is_multiplayer_authority():
		
		camera_pivot.rotation_degrees.x = cam_pitch
		camera_pivot.rotation_degrees.y = cam_yaw
		camera_pivot.rotation_degrees.z = 0

	_update_ik_influence(delta)
	_update_hand_ik(delta)

	if _ik_influence < 0.001:
		var hit_l     = _get_ground_hit(ray_left)
		var hit_r     = _get_ground_hit(ray_right)
		var hit_l_toe = _get_ground_hit(ray_left_toe)
		var hit_r_toe = _get_ground_hit(ray_right_toe)
		
		# 🌊/🦘 Si on nage ou qu'on saute, on garde les cibles collées aux pieds du joueur
		# au lieu de les laisser tomber dans le vide absolu (évite l'effet élastique)
		if is_swimming or not is_on_floor():
			_smooth_pos_left  = ray_left.global_position
			_smooth_pos_right = ray_right.global_position
		else:
			_smooth_pos_left  = _compute_ankle_target(hit_l, hit_l_toe)
			_smooth_pos_right = _compute_ankle_target(hit_r, hit_r_toe)
			
			# ↓ is_on_floor() → _eff_on_floor()
		if is_swimming or not _eff_on_floor():
			_smooth_pos_left  = ray_left.global_position
			_smooth_pos_right = ray_right.global_position
		else:
			_smooth_pos_left  = _compute_ankle_target(hit_l, hit_l_toe)
			_smooth_pos_right = _compute_ankle_target(hit_r, hit_r_toe)
			
		target_left.global_position  = _smooth_pos_left
		target_right.global_position = _smooth_pos_right
		target_left.quaternion  = Quaternion.IDENTITY
		target_right.quaternion = Quaternion.IDENTITY
		
		# ✅ LA CORRECTION : On coupe obligatoirement l'IK avant de quitter la fonction !
		ik_left.influence  = 0.0
		ik_right.influence = 0.0
		ik_toe_left.influence  = 0.0
		ik_toe_right.influence = 0.0
		return

	var hit_left      = _get_ground_hit(ray_left)
	var hit_right     = _get_ground_hit(ray_right)
	# ↓ Calcul des orteils AVANT _update_foot_targets
	var hit_left_toe  = _get_ground_hit(ray_left_toe)
	var hit_right_toe = _get_ground_hit(ray_right_toe)
	
	#if is_instance_valid(debug_sphere_heel_l): debug_sphere_heel_l.global_position = hit_left["position"]
	#if is_instance_valid(debug_sphere_toe_l):  debug_sphere_toe_l.global_position = hit_left_toe["position"]
	#if is_instance_valid(debug_sphere_heel_r): debug_sphere_heel_r.global_position = hit_right["position"]
	#if is_instance_valid(debug_sphere_toe_r):  debug_sphere_toe_r.global_position = hit_right_toe["position"]

	_update_foot_targets(hit_left, hit_right, hit_left_toe, hit_right_toe, delta)
	_update_pelvis_offset(hit_left, hit_right, delta)
	_update_foot_rotations(hit_left, hit_right, hit_left_toe, hit_right_toe, delta)


	_update_foot_toe_targets(hit_left_toe, hit_right_toe, delta)

	ik_left.influence  = _ik_influence
	ik_right.influence = _ik_influence
	

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_climb_animation(delta)
	# ── Synchronisation état IK vers les marionnettes ─────────────────────────
		_net_velocity     = velocity
		_net_is_on_floor  = is_on_floor()
		_net_is_turning   = is_turning_in_place

	if is_dead:
		_update_ragdoll_buoyancy(delta)
		move_and_slide()
		return
	
	# Sortie de bassin (court-circuite toute la physique normale)
	if _is_climbing_out:
		if is_multiplayer_authority():
			_update_oxygen(delta) # <-- AJOUT : L'oxygène continue de se mettre à jour
		_update_climb_out(delta)
		move_and_slide()
		return
		
	if _is_equipping_clothing:
		_update_equip_clothing_transition(delta)
		velocity = Vector3.ZERO
		move_and_slide()
		return
		
	# Échelle (court-circuite la marche/nage tant que le joueur grimpe)
	if _handle_ladder_physics(delta):
		if is_multiplayer_authority():
			_update_oxygen(delta) # <-- AJOUT : L'oxygène continue de se mettre à jour
		move_and_slide()
		return
		
	# --- 1. DÉTECTION DE L'EAU ---
	is_swimming = false
	var depth = 0.0
	var water_probe_submerged = false  # NOUVEAU
	if _is_in_dry_zone(global_position):
		is_swimming = false
		# Optionnel : forcez ici vos variables de gravité/vitesse terrestres si nécessaire
	elif water:
	# --- 1. DÉTECTION ---
		if swim_detect_probe and water.get_height(swim_detect_probe.global_position) > swim_detect_probe.global_position.y:
			is_swimming = true
		if water_probe:
			depth = water.get_height(water_probe.global_position) - water_probe.global_position.y

	# --- 2. GRAVITÉ ---
	if is_multiplayer_authority():
		wearing_heavy_suit = _is_wearing_heavy_suit()   # 🆕 calculé en premier
		# La gravité s'applique si hors sol ET (pas en nage OU WaterProbe hors de l'eau)
		if not is_on_floor() and (not is_swimming or depth <= 0):
			velocity += get_gravity() * delta
		elif wearing_heavy_suit and is_swimming and depth > 0 and not is_on_floor():
			velocity += get_gravity() * diving_suit_gravity_scale * delta

		# --- 3. SAUT ---
		# Bloqué tant que SwimDetectProbe est dans l'eau
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			if wearing_heavy_suit:
				velocity.y = JUMP_VELOCITY * heavy_suit_jump_multiplier
			elif not is_swimming:
				velocity.y = JUMP_VELOCITY

		# --- 3. GESTION DES ETATS ET VITESSE ---
		# ── SYSTÈME DE CROUCH + DÉTECTION PLAFOND ───────────────────────────────
		var _is_pressing_crouch := Input.is_action_pressed("ui_crouch") and not is_swimming
		
		# Détecte le moment EXACT où le joueur relâche le bouton (tentative de relevé)
		if is_crouching != _is_pressing_crouch:
			if not _is_pressing_crouch:
				if head_clearance_ray.is_colliding():
					# Collision détectée → On force le retour à l'accroupi
					_is_pressing_crouch = true

		is_crouching = _is_pressing_crouch

		# --- HAUTEUR DE LA CAMÉRA (ton code original conservé) ---
		var target_cam_height = cam_original_height
		if is_crouching:
			target_cam_height += crouch_cam_offset

	
		# Interpolation fluide de la position Y
		camera_pivot.position.y = lerp(camera_pivot.position.y, target_cam_height, cam_lerp_speed * delta)
		var is_running = Input.is_action_pressed("ui_shift") and not is_crouching and not is_swimming
		if wearing_heavy_suit:
			is_running = false
		
		var current_speed = WALK_SPEED
		if is_running: current_speed = RUN_SPEED
		if is_crouching: current_speed = CROUCH_SPEED
		if is_swimming: current_speed = SWIM_SPEED 
		if wearing_heavy_suit and is_swimming:
			current_speed = WALK_SPEED

		# Swap des collisions
		# Swap des collisions
		var use_swim_collision := is_swimming and not wearing_heavy_suit   # 🆕 scaphandre = collisions de marche même sous l'eau
		swimming_collision_sphere.disabled = not use_swim_collision
		stand_collision.disabled = use_swim_collision or is_crouching
		crouch_collision.disabled = use_swim_collision or not is_crouching
		crouch_collision2.disabled = use_swim_collision or not is_crouching

		var input_dir := Input.get_vector("ui_right", "ui_left", "ui_down", "ui_up")
	
	# --- 4. CALCUL DE LA DIRECTION ET INCLINAISON DU CORPS ---
		var cam_basis = camera_pivot.global_transform.basis
		var direction = (cam_basis * Vector3(input_dir.x, 0, input_dir.y))
		
		# La valeur "Droit" pour ton modèle est 90.0
		var base_vertical_angle = 90.0 
		
		if not is_swimming or wearing_heavy_suit:
			direction.y = 0 
			# Hors de l'eau, on force le perso à rester "Droit" (90°)
			$Marker3D.rotation_degrees.x = lerp($Marker3D.rotation_degrees.x, base_vertical_angle, 5.0 * delta)
		else:
			# EN NAGE : On passe du "-" au "+" pour corriger l'inversion
			# Maintenant, regarder en bas fera pencher le perso vers l'avant (vers 0°)
			# et regarder en haut le fera pencher vers l'arrière (vers 180°)
			var target_tilt = base_vertical_angle + cam_pitch
			
			# On applique la rotation avec un lerp un peu plus nerveux (10.0 au lieu de 8.0)
			$Marker3D.rotation_degrees.x = lerp($Marker3D.rotation_degrees.x, target_tilt, 10.0 * delta)
			
		direction = direction.normalized()
		var is_moving = direction.length() > 0.1
		var old_rotation_y = rotation.y

		# --- 5. GESTION DE LA ROTATION DU CORPS ---
		if is_moving:
			is_turning_in_place = false
			
			# 1. On récupère l'angle absolu actuel de la caméra dans le monde
			var camera_world_angle = rotation.y + deg_to_rad(cam_yaw)
			
			# 2. On calcule l'angle de l'input (en fonction des touches pressées)
			# Le signe "-" devant input_dir.x permet de respecter les axes de Godot 4
			var input_angle_offset = atan2(input_dir.x, input_dir.y)
			
			# 3. L'angle cible est la direction de la caméra + l'orientation de tes touches
			var target_angle = camera_world_angle + input_angle_offset
			
			# 4. On fait pivoter le personnage activement vers cette direction
			rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)
		else:
			# Dans GTA / Zelda, le personnage ne pivote pas sur place avec la caméra s'il ne bouge pas
			is_turning_in_place = false

		# --- 6. LA COMPENSATION MAGIQUE ---
		var rotation_diff = rad_to_deg(rotation.y - old_rotation_y)
		cam_yaw -= rotation_diff
		cam_yaw = wrapf(cam_yaw, -180.0, 180.0)
	# --- 7. DÉPLACEMENT PHYSIQUE ---
		if is_moving:
			velocity.x = lerp(velocity.x, direction.x * current_speed, ACCELERATION * delta)
			velocity.z = lerp(velocity.z, direction.z * current_speed, ACCELERATION * delta)
			
			# Si on nage ET qu'on avance, on va dans la direction de la caméra (Haut/Bas)
			if is_swimming and not wearing_heavy_suit:
				velocity.y = lerp(velocity.y, direction.y * current_speed, ACCELERATION * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, FRICTION * delta)
			velocity.z = lerp(velocity.z, 0.0, FRICTION * delta)

		# --- 8. FLOTTABILITÉ ET STATIQUE DANS L'EAU ---
		if is_swimming and depth > 0 and not wearing_heavy_suit:
			if Input.is_action_pressed("ui_accept"):
				velocity.y = lerp(velocity.y, float_force, 5.0 * delta)
			elif not is_moving:
				velocity.y = lerp(velocity.y, 0.0, 5.0 * delta)
				
		_update_oxygen(delta)

		move_and_slide()
		update_animations(input_dir, is_running, is_moving, is_crouching, is_swimming and not wearing_heavy_suit, delta)
		
	
		#Système d'interaction
		var wants_to_interact = Input.is_action_pressed("interact")
		
		# MAGIE : Si la main est en route vers l'objet (influence < 0.95), 
		# on simule un clic gauche maintenu pour forcer le bras à finir son mouvement.
		if is_hand_interact_active and _arm_ik_influence < 0.95:
			wants_to_interact = true

		if wants_to_interact:
			if not isHoldingObject and not isCarryingObject:
				InteractWithDoor()
				if not isHoldingObject:
					InteractWithGrabbable()
		else:
			# Ce bloc s'exécutera NATURELLEMENT une fois que l'influence atteindra 0.95
			# (si le joueur a relâché le clic entre temps).
			if isHoldingObject and is_instance_valid(heldObject):
					heldObject.rpc_release_grab.rpc(multiplayer.get_unique_id())
					_rpc_sync_drop_ik.rpc()
			isHoldingObject = false
			heldObject = null
			heldMarker = null
			is_hand_interact_active = false
			if isCarryingObject:
				_release_carry()
				
		maintainInteraction()
		maintainCarry(delta)
		
		if is_multiplayer_authority():
			_update_camera_attachment(is_swimming)   # ← AJOUT

			if not is_on_floor() and (not is_swimming or depth <= 0):
				velocity += get_gravity() * delta
		_handle_footsteps(delta)
	


func update_animations(input_dir: Vector2, is_running: bool, is_moving: bool, is_crouching: bool, is_swimming: bool, delta: float) -> void:

	# 1. Blend position basée sur la vitesse RÉELLE (pas les inputs)
	var local_velocity = global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	
	# Normalise par la vitesse max selon l'état
	var max_speed = RUN_SPEED if is_running else (CROUCH_SPEED if is_crouching else WALK_SPEED)
	var velocity_blend = Vector2(local_velocity.x, local_velocity.z) / max_speed
	velocity_blend = velocity_blend.clamp(Vector2(-1, -1), Vector2(1, 1))

	current_blend_position = current_blend_position.lerp(velocity_blend, 10.0 * delta)
	anim_tree.set("parameters/walk/blend_position", current_blend_position)
	anim_tree.set("parameters/run/blend_position", current_blend_position)
	anim_tree.set("parameters/crouch/blend_position", current_blend_position)

	# 2. Gestion du mélange Marche / Course
	var target_run_val = 1.0 if (is_running and is_moving) else 0.0
	run_blend_val = lerp(run_blend_val, target_run_val, 5.0 * delta)
	anim_tree.set("parameters/walk or run/blend_amount", run_blend_val)

	# 3. Gestion du TURN (Rotation sur place)
	var target_turn_val = 0.0
	if is_turning_in_place:
		target_turn_val = 1.0 if cam_yaw < 0 else -1.0
		
		# Si on vient de commencer la rotation on est plus agressif
		var lerp_speed = 20.0 if abs(turn_blend_val) < 0.1 else 10.0
		turn_blend_val = lerp(turn_blend_val, target_turn_val, lerp_speed * delta)
	else:
		# Retour rapide au neutre quand on s'arrête
		turn_blend_val = lerp(turn_blend_val, 0.0, 15.0 * delta)

	anim_tree.set("parameters/turn/blend_amount", turn_blend_val)
	# ✅ NOUVEAU : On synchronise le nœud crouch_turn avec exactement la même valeur !
	anim_tree.set("parameters/crouch_turn/blend_amount", turn_blend_val) 

	# 4. Gestion du Blend Crouch (crouch 2)
	var target_crouch_val = 1.0 if is_crouching else 0.0
	crouch_blend_val = lerp(crouch_blend_val, target_crouch_val, 5.0 * delta)
	anim_tree.set("parameters/crouch 2/blend_amount", crouch_blend_val)

	# 5. Gestion du Saut
	var target_jump_val = 1.0 if (not is_on_floor() and not is_swimming) else 0.0
	jump_blend_val = lerp(jump_blend_val, target_jump_val, 7.0 * delta)
	anim_tree.set("parameters/last or jump/blend_amount", jump_blend_val)
	
	# 6. Gestion de la Nage
	var target_swim_val = 1.0 if is_swimming else 0.0
	swim_blend_val = lerp(swim_blend_val, target_swim_val, 5.0 * delta)
	
	anim_tree.set("parameters/swimming/blend_amount", swim_blend_val) 
	anim_tree.set("parameters/swimming 2/blend_position", current_blend_position)
	
	
	
	
	
# ── OUTIL IK ──────────────────────────────────────────────────────────────────
@onready var swing_marker1: Marker3D = $Marker3D/PhysicsMan/Armature/Skeleton3D/BoneAttachment3D_Swing/SwingMarker1
@onready var swing_marker2: Marker3D = $Marker3D/PhysicsMan/Armature/Skeleton3D/BoneAttachment3D_Swing/SwingMarker2

var _is_swinging: bool = false
var _swing_callback: Callable
var _swing_impact_triggered: bool = false

# Phases du swing
enum SwingPhase { IDLE, TO_MARKER1, TO_MARKER2, RETURN }
var _swing_phase: SwingPhase = SwingPhase.IDLE

# Timers de chaque phase (en secondes, exportables depuis l'Inspecteur)
@export_group("Outil - Swing")
@export var swing_phase1_duration: float = 0.15  # Recul
@export var swing_phase2_duration: float = 0.15  # Impact
@export var swing_return_duration: float = 0.25  # Retour
@export var swing_ik_blend_in: float = 12.0      # Vitesse montée influence IK
@export var swing_ik_blend_out: float = 6.0      # Vitesse descente influence IK

var _swing_phase_timer: float = 0.0
var _swing_ik_influence: float = 0.0
var _swing_start_position: Vector3 = Vector3.ZERO  # Position de départ au repos
	
@onready var skeleton: Skeleton3D = $Marker3D/PhysicsMan/Armature/Skeleton3D

# RayCasts : placés à la hauteur de la cheville, orientés vers le bas
@onready var ray_left:  RayCast3D = $RaycastPiedGauche
@onready var ray_right: RayCast3D = $RaycastPiedDroit

# Cibles IK (Marker3D) : déplacées chaque frame vers la position sol
@onready var target_left:  Marker3D = $IKTargetPiedGauche
@onready var target_right: Marker3D = $IKTargetPiedDroit

# Pole Vectors pour orienter les genoux vers l'avant
@onready var pole_left:  Marker3D = $PoleVectorGenouGauche
@onready var pole_right: Marker3D = $PoleVectorGenouDroit

# Les deux solveurs IK (enfants de Skeleton3D)
@onready var ik_left:  Node = $Marker3D/PhysicsMan/Armature/Skeleton3D/TwoBoneIK_Gauche
@onready var ik_right: Node = $Marker3D/PhysicsMan/Armature/Skeleton3D/TwoBoneIK_Droit

# Raycasts orteils (bout du pied) — ajout
@onready var ray_left_toe:  RayCast3D = $RaycastOrteilGauche
@onready var ray_right_toe: RayCast3D = $RaycastOrteilDroit

@export_group("Foot IK - Noms des os")
@export var foot_left_bone_name: String = "mixamorig_LeftFoot" # ⚠️ À remplacer par le vrai nom de l'os dans Blender/Godot
@export var foot_right_bone_name: String = "mixamorig_RightFoot" # ⚠️ À remplacer par le vrai nom de l'os

var _foot_l_idx: int = -1
var _foot_r_idx: int = -1

var _foot_rotation_weight: float = 0.0

# ─────────────────────────────────────────
#  PARAMÈTRES (réglables dans l'Inspecteur)
# ─────────────────────────────────────────
@export_group("Foot IK - Détection")
## Distance de recherche du sol sous le pied
@export var ray_length: float = 1.2
## Décalage vertical de la semelle par rapport à l'os de cheville
@export var foot_offset: float = 0.08
## Décalage vertical de la semelle au niveau des orteils (indépendant du talon)
@export var toe_offset: float = 0.04
## Masque de collision pour le sol
@export_flags_3d_physics var ground_layer: int = 1

@export_group("Foot IK - Lissage")
## Vitesse d'interpolation de la position des pieds (plus grand = plus réactif)
@export var foot_lerp_speed: float = 12.0
## Vitesse d'interpolation de la rotation des pieds (alignement avec la normale)
@export var foot_rotation_speed: float = 10.0
## Vitesse d'interpolation du bassin
@export var pelvis_lerp_speed: float = 8.0
## Angle maximum d'inclinaison du pied sur une pente (degrés)
@export var max_foot_angle_deg: float = 35.0

@export_group("Foot IK - Influence")
## Distance de fade-out quand le personnage n'est pas au sol (saut/chute)
@export var ik_blend_speed: float = 5.0


# ─────────────────────────────────────────
#  ÉTAT INTERNE
# ─────────────────────────────────────────
# Positions IK cibles lissées (en espace global)
var _smooth_pos_left:  Vector3 = Vector3.ZERO
var _smooth_pos_right: Vector3 = Vector3.ZERO


# Décalage vertical du bassin
var _pelvis_offset_y:  float = 0.0

# Influence courante de l'IK (0 = désactivé, 1 = plein effet)
var _ik_influence:     float = 1.0

# Indice des os du bassin dans le Skeleton3D
var _pelvis_bone_idx:  int = -1

# Nom de l'os du bassin (adapter à votre rig)
@export var pelvis_bone_name: String = "Hips"

var _ik_activate_timer: float = 0.0


# ─────────────────────────────────────────
#  1. GESTION DE L'INFLUENCE IK (SAUT/CHUTE)
# ─────────────────────────────────────────
func _update_ik_influence(delta: float) -> void:
	# ↓ is_on_floor() → _eff_on_floor()
	if is_swimming or not _eff_on_floor():
		_ik_influence = 0.0
		_ik_activate_timer = 0.0
		return

	# ↓ velocity → _eff_velocity()
	var horizontal_speed := Vector2(_eff_velocity().x, _eff_velocity().z).length()
	var move_factor: float = clamp(inverse_lerp(0.1, 0.8, horizontal_speed), 0.0, 1.0)
	# ↓ is_on_floor() → _eff_on_floor()  |  is_turning_in_place → _eff_turning()
	var target_influence: float = (1.0 - move_factor) if (_eff_on_floor() and not is_swimming and not _eff_turning()) else 0.0

	if target_influence > _ik_influence:
		_ik_activate_timer += delta
		if _ik_activate_timer < 0.25:
			return
	else:
		_ik_activate_timer = 0.0

	var blend_speed: float = ik_blend_speed * 4.0 if target_influence < _ik_influence else ik_blend_speed
	_ik_influence = lerp(_ik_influence, target_influence, blend_speed * delta)

# ─────────────────────────────────────────
#  2. DÉTECTION SOL PAR RAYCAST
#     Retourne un dictionnaire {position, normal, found}
# ─────────────────────────────────────────
func _get_ground_hit(ray: RayCast3D) -> Dictionary:
	if ray.is_colliding():
		return {
			"found":    true,
			"position": ray.get_collision_point(),
			"normal":   ray.get_collision_normal()
		}
	else:
		# Pas de sol détecté : renvoyer la position du ray comme fallback
		return {
			"found":    false,
			"position": ray.global_position + Vector3.DOWN * ray_length,
			"normal":   Vector3.UP
		}


# ─────────────────────────────────────────
#  3. MISE À JOUR DES CIBLES IK (Marker3D)
# ─────────────────────────────────────────
func _update_foot_targets(hit_l: Dictionary, hit_r: Dictionary,hit_l_toe: Dictionary, hit_r_toe: Dictionary,delta: float) -> void:
	var target_pos_left  = _compute_ankle_target(hit_l, hit_l_toe)
	var target_pos_right = _compute_ankle_target(hit_r, hit_r_toe)

	_smooth_pos_left  = _smooth_pos_left.lerp(target_pos_left,  foot_lerp_speed * delta)
	_smooth_pos_right = _smooth_pos_right.lerp(target_pos_right, foot_lerp_speed * delta)

	target_left.global_position  = _smooth_pos_left
	target_right.global_position = _smooth_pos_right


# ─────────────────────────────────────────
#  4. DÉCALAGE DU BASSIN (Pelvis Offset)
# ─────────────────────────────────────────
func _update_pelvis_offset(hit_l: Dictionary, hit_r: Dictionary, delta: float) -> void:
	if _pelvis_bone_idx == -1:
		return
	
	# Hauteur de chaque pied par rapport au sol du personnage
	var height_left  = hit_l["position"].y - global_position.y
	var height_right = hit_r["position"].y - global_position.y
	
	# Le pied le plus haut détermine combien le bassin doit descendre
	# pour que l'autre jambe puisse se plier naturellement
	var _higher_foot = max(height_left, height_right)
	var lower_foot  = min(height_left, height_right)
	
	# Le bassin descend d'autant que la différence de hauteur entre les deux pieds,
	# pour que la jambe la plus courte (côté sol plus bas) reste en contact
	var target_pelvis_offset = lower_foot - 0.0
	# Clamp : on ne remonte jamais le bassin artificiellement
	target_pelvis_offset = clamp(target_pelvis_offset, -0.5, 0.0)
	
	# Lisser l'offset pour éviter le jitter
	_pelvis_offset_y = lerp(_pelvis_offset_y, target_pelvis_offset, pelvis_lerp_speed * delta)
	
	# Appliquer à l'os du bassin via le pose local du Skeleton3D
	var current_pose: Transform3D = skeleton.get_bone_pose(_pelvis_bone_idx)
	current_pose.origin.y = _pelvis_offset_y
	skeleton.set_bone_pose_position(_pelvis_bone_idx, current_pose.origin)


# ─────────────────────────────────────────
#  5. ROTATION DES PIEDS (alignement avec la normale)
# ─────────────────────────────────────────
func _update_foot_rotations(hit_l, hit_r, hit_l_toe, hit_r_toe, delta) -> void:
	# ↓ velocity → _eff_velocity()  |  is_on_floor() → _eff_on_floor()
	var horizontal_speed := Vector2(_eff_velocity().x, _eff_velocity().z).length()

	if horizontal_speed > 0.3 or is_swimming or not _eff_on_floor():
		_foot_rotation_weight = 0.0
	else:
		_foot_rotation_weight = 1.0
	
func _compute_ankle_target(hit_heel: Dictionary, hit_toe: Dictionary) -> Vector3:
	if not hit_heel["found"]:
		return hit_heel["position"] + Vector3.UP * foot_offset

	# La cheville se pose toujours sur le point de contact du TALON uniquement.
	# L'inclinaison de la pente est gérée par _tilt_foot_bone, pas ici.
	var ankle_pos = hit_heel["position"] + hit_heel["normal"] * foot_offset

	return ankle_pos
	

func _update_foot_toe_targets(hit_l_toe: Dictionary, hit_r_toe: Dictionary, delta: float) -> void:
	if _foot_rotation_weight < 0.01 or is_swimming or not _eff_on_floor():
		ik_toe_left.influence  = 0.0
		ik_toe_right.influence = 0.0
		return

	# 🆕 Si le raycast ne touche rien (pied au bord du vide, ex: falaise),
	# on utilise quand même le point de repli de _get_ground_hit() (bas du raycast)
	# au lieu de laisser le target figé à sa dernière position connue.
	var goal_l: Vector3 = hit_l_toe["position"]
	if hit_l_toe["found"]:
		goal_l += hit_l_toe["normal"] * toe_offset

	var goal_r: Vector3 = hit_r_toe["position"]
	if hit_r_toe["found"]:
		goal_r += hit_r_toe["normal"] * toe_offset

	target_toe_left.global_position  = target_toe_left.global_position.lerp(goal_l, foot_rotation_speed * delta)
	target_toe_right.global_position = target_toe_right.global_position.lerp(goal_r, foot_rotation_speed * delta)

	ik_toe_left.influence  = _foot_rotation_weight
	ik_toe_right.influence = _foot_rotation_weight

func InteractWithDoor() -> void:
	if !isHoldingObject:
		$CameraPivot/PhysicsRayCast.force_raycast_update()
		if $CameraPivot/PhysicsRayCast.is_colliding():
			var collider = $CameraPivot/PhysicsRayCast.get_collider()
			if collider.is_in_group("Door"):
				# Si verrouillée, l'InteractionManager gère le déverrouillage — on ne fait rien ici
				if "is_locked" in collider and collider.is_locked:
					return
				heldMarker = collider.get_node_or_null("marker_node")
				if heldMarker:
					collider.rpc_request_grab.rpc(multiplayer.get_unique_id())
					isHoldingObject = true
					heldObject = collider
					is_hand_interact_active = true
					hand_target_position = skeleton.to_local(heldMarker.global_transform.origin)
					_rpc_sync_pickup_ik.rpc(heldMarker.get_path())
	else:
		if is_instance_valid(heldObject):
			heldObject.rpc_release_grab.rpc(multiplayer.get_unique_id())
		_rpc_sync_drop_ik.rpc()
		isHoldingObject = false
		heldObject = null
		heldMarker = null
		is_hand_interact_active = false

func maintainInteraction() -> void:
	if not (isHoldingObject and is_instance_valid(heldObject) and is_instance_valid(heldMarker)):
		return


	if not $CameraPivot/PhysicsRayCast.is_colliding() or \
	   $CameraPivot/PhysicsRayCast.get_collider() != heldObject:
		heldObject.rpc_release_grab.rpc(multiplayer.get_unique_id())
		_rpc_sync_drop_ik.rpc()  # ← NOUVEAU
		isHoldingObject = false
		heldObject = null
		heldMarker = null
		is_hand_interact_active = false
		return

	var target_pos: Vector3 = $CameraPivot/InteractPos.global_transform.origin
	heldObject.rpc_update_pull_target.rpc(multiplayer.get_unique_id(), target_pos)
		

func InteractWithGrabbable() -> void:
	if not $CameraPivot/PhysicsRayCast.is_colliding():
		return
	var collider = $CameraPivot/PhysicsRayCast.get_collider()
	if not collider.is_in_group("Grabbable"):
		return
	if collider.get_node_or_null("GrabMarkerLeft") == null or collider.get_node_or_null("GrabMarkerRight") == null:
		push_warning("Grabbable '%s' : marqueurs manquants." % collider.name)
		return

	collider.rpc_request_grab.rpc(multiplayer.get_unique_id())

	carry_spring_arm.spring_length = clamp(
		camera_pivot.global_position.distance_to(collider.global_position),
		carry_min_spring_length, carry_max_spring_length
	)
	carry_spring_arm.add_excluded_object(collider.get_rid())   # 🆕 empêche l'objet de bloquer son propre spring arm

	_rpc_sync_start_carry.rpc(collider.get_path())


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_start_carry(object_path: NodePath) -> void:
	var obj := get_node_or_null(object_path)
	if obj == null:
		return
	var left_marker: Marker3D = obj.get_node_or_null("GrabMarkerLeft")
	var right_marker: Marker3D = obj.get_node_or_null("GrabMarkerRight")
	if left_marker == null or right_marker == null:
		return

	isCarryingObject = true
	carriedObject = obj
	carriedLeftMarker = left_marker
	carriedRightMarker = right_marker
	is_hand_interact_active = true
	_is_carrying_left = true


func _release_carry() -> void:
	if is_instance_valid(carriedObject):
		carriedObject.rpc_release_grab.rpc(multiplayer.get_unique_id())
		carry_spring_arm.remove_excluded_object(carriedObject.get_rid())   # 🆕
	_rpc_sync_end_carry.rpc()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_end_carry() -> void:
	isCarryingObject = false
	carriedObject = null
	carriedLeftMarker = null
	carriedRightMarker = null
	is_hand_interact_active = false
	_is_carrying_left = false


func maintainCarry(delta: float) -> void:
	if not (isCarryingObject and is_instance_valid(carriedObject)):
		return

	if Input.is_action_pressed("rotation_r"):
		carriedObject.rpc_apply_rotation.rpc(multiplayer.get_unique_id(), Vector3.UP, deg_to_rad(carry_rotation_speed) * delta)
	if Input.is_action_pressed("rotation_t"):
		var pitch_axis: Vector3 = camera_pivot.global_transform.basis.x
		carriedObject.rpc_apply_rotation.rpc(multiplayer.get_unique_id(), pitch_axis, deg_to_rad(carry_rotation_speed) * delta)

	carriedObject.rpc_update_pull_target.rpc(multiplayer.get_unique_id(), carry_target_marker.global_position)

# ----------------------------------------------------------------
# FONCTION POUR GÉRER LE SMOOTHING DE LA MAIN (IK)
# ----------------------------------------------------------------
func _update_hand_ik(delta: float) -> void:
	# ── Gestion du timer de consommation ──────────────────────────────────────
	if _is_consuming:
		_consume_timer += delta
		var progress = _consume_timer / _consume_duration  # 0.0 → 1.0

		# Phase 1 (0% → 50%) : la main monte vers la bouche
		# Phase 2 (50% → 100%) : la main redescend
		if progress <= 0.5:
			# L'influence monte progressivement au début (évite le saut brutal)
			_consume_ik_influence = lerp(_consume_ik_influence, 1.0, 8.0 * delta)
			# La cible se déplace vers la bouche
			var t = progress / 0.5  # 0→1 pendant la montée
			hand_right_target.global_position = hand_right_target.global_position.lerp(
				mouth_anchor.global_position, 8.0 * delta
			)
		else:
			# L'influence redescend progressivement
			_consume_ik_influence = lerp(_consume_ik_influence, 0.0, 5.0 * delta)

		# Applique l'influence progressive sur l'IK du bras
		if right_arm_ik:
			right_arm_ik.influence = _consume_ik_influence

		# À mi-chemin (main à la bouche) → déclenche l'effet
		if _consume_timer >= _consume_duration * 0.5 and _consume_callback != Callable():
			_consume_callback.call()
			_consume_callback = Callable()  # Reset pour ne pas rappeler

		# Animation terminée
		if _consume_timer >= _consume_duration:
			stop_consume_animation()
		return  # On court-circuite le reste pendant la consommation
	
	# ── Cas cooldown interaction ──────────────────────────────────────────────
	if _is_cooldown_interacting:
		_update_cooldown_interaction(delta)
		# Monte progressivement l'influence IK
		_arm_ik_influence = lerp(_arm_ik_influence, 1.0, _hand_lerp_speed * delta)
		if right_arm_ik:
			right_arm_ik.influence = _arm_ik_influence
		return
	
	
	# ── Cas 2 : Swing outil ───────────────────────────────────────────────────
	if _is_swinging:
		_update_tool_swing(delta)
		return

	# ── Reste du code _update_hand_ik existant ────────────────────────────────
	var target_influence = 1.0 if (is_hand_interact_active or _is_aiming_lamp) else 0.0   
	
	# --- NOUVEAU : Gestion du ramassage "forcé" (Clic court) ---
	if _pickup_marker != null and _wants_to_drop_pickup:
		target_influence = 1.0 # On force la main à finir son trajet vers l'objet
		
		# Si on a atteint la cible (influence maximale), on exécute enfin le retour !
		if _arm_ik_influence >= 0.95:
			_execute_pickup_drop()
			
	var blend_speed = _hand_lerp_speed
	_arm_ik_influence = lerp(_arm_ik_influence, target_influence, blend_speed * delta)

	if right_arm_ik:
		right_arm_ik.influence = _arm_ik_influence

	if is_hand_interact_active:
		if heldMarker != null:
			hand_right_target.global_position = heldMarker.global_transform.origin
		elif carriedRightMarker != null:   # 🆕
			hand_right_target.global_position = carriedRightMarker.global_transform.origin
		elif _pickup_marker != null:
			hand_right_target.global_position = _pickup_marker.global_transform.origin
	elif _is_aiming_lamp and lamp_aim_marker:
		hand_right_target.global_position = lamp_aim_marker.global_position
	else:
		hand_right_target.global_position = skeleton.to_global(
			skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_RightHand")).origin
		)

	# 🆕 BRAS GAUCHE : même principe, dédié au portage à deux mains
	var left_target_influence: float = 1.0 if _is_carrying_left else 0.0
	_left_arm_ik_influence = lerp(_left_arm_ik_influence, left_target_influence, carry_left_arm_ik_speed * delta)
	if left_arm_ik:
		left_arm_ik.influence = _left_arm_ik_influence

	if _is_carrying_left and carriedLeftMarker != null:
		hand_left_target.global_position = carriedLeftMarker.global_transform.origin
	else:
		hand_left_target.global_position = skeleton.to_global(
			skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_LeftHand")).origin
		)
			
func find_marker_node(door_node: Node) -> Node:
	# Recherche le nœud "DoorMarker" sous le nœud de la porte détectée
	var potential_marker = door_node.find_child("DoorMarker")
	if potential_marker and potential_marker.has_node("CollisionShape3D"): # Optionnel : vérifier qu'il est complet
		return potential_marker
	
	return null
	
	
func activate_pickup_hand_ik(target_marker: Marker3D) -> void:
	_pickup_marker = target_marker 
	is_hand_interact_active = true
	_wants_to_drop_pickup = false # <-- AJOUT : annule l'intention de lâcher si on reclique
	if is_multiplayer_authority() and _pickup_marker:
		_rpc_sync_pickup_ik.rpc(_pickup_marker.get_path())
	

func deactivate_pickup_hand_ik() -> void:
	if _arm_ik_influence >= 0.95:
		# Si le bras est déjà (presque) arrivé, on lâche normalement
		_execute_pickup_drop()
	else:
		# Sinon, on mémorise qu'on veut lâcher, mais on laisse l'animation se finir
		_wants_to_drop_pickup = true
		
func _execute_pickup_drop() -> void:
	_pickup_marker = null
	is_hand_interact_active = false
	_wants_to_drop_pickup = false
	if is_multiplayer_authority():
		_rpc_sync_drop_ik.rpc()
	
	
# ── VARIABLES CONSOMMABLE IK ──────────────────────────────────────────────────
var _is_consuming: bool = false
var _consume_timer: float = 0.0
var _consume_duration: float = 1.2  # Durée totale de l'animation
var _consume_ik_influence: float = 0.0  # Influence qui monte progressivement
var _consume_callback: Callable  # Fonction appelée quand c'est fini

## Démarre l'animation de consommation
func start_consume_animation(callback: Callable) -> void:
	if not is_multiplayer_authority():
		return
	if _is_consuming:
		return
	_consume_callback = callback   # reste local : seule l'autorité applique l'effet (soin/dégâts)
	_rpc_sync_consume_start.rpc()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_consume_start() -> void:
	_is_consuming = true
	_consume_timer = 0.0
	_consume_ik_influence = 0.0
	is_hand_interact_active = true

## Stoppe l'animation
func stop_consume_animation() -> void:
	_is_consuming = false
	_consume_timer = 0.0
	_consume_ik_influence = 0.0
	is_hand_interact_active = false
	
	
## Démarre l'animation de swing
func start_tool_swing(callback: Callable, animations: Dictionary = {}) -> void:
	if not is_multiplayer_authority():
		return
	if _is_swinging:
		return

	_swing_callback = callback   # reste local : seule l'autorité calcule l'impact (raycast caméra)
	_rpc_sync_swing_start.rpc()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_swing_start() -> void:
	_is_swinging = true
	_swing_impact_triggered = false
	_swing_phase = SwingPhase.TO_MARKER1
	_swing_phase_timer = 0.0
	_swing_ik_influence = 0.0

	_swing_start_position = skeleton.to_global(
		skeleton.get_bone_global_pose(
			skeleton.find_bone("mixamorig_RightHand")
		).origin
	)
	print("[Swing] Démarrage — phase 1 : recul")

## Appelée chaque frame pendant le swing
func _update_tool_swing(delta: float) -> void:
	if not _is_swinging:
		return

	_swing_phase_timer += delta

	match _swing_phase:

		SwingPhase.TO_MARKER1:
			# ── Phase 1 : recul — influence monte, main va vers marker1 ──────
			_swing_ik_influence = lerp(_swing_ik_influence, 1.0, swing_ik_blend_in * delta)
			hand_right_target.global_position = hand_right_target.global_position.lerp(
				swing_marker1.global_position, swing_ik_blend_in * delta
			)
			if right_arm_ik:
				right_arm_ik.influence = _swing_ik_influence

			if _swing_phase_timer >= swing_phase1_duration:
				_swing_phase = SwingPhase.TO_MARKER2
				_swing_phase_timer = 0.0
				print("[Swing] Phase 2 : impact")

		SwingPhase.TO_MARKER2:
			# ── Phase 2 : impact — main fonce vers marker2 ───────────────────
			hand_right_target.global_position = hand_right_target.global_position.lerp(
				swing_marker2.global_position, swing_ik_blend_in * 2.0 * delta
			)
			if right_arm_ik:
				right_arm_ik.influence = _swing_ik_influence

			# Déclenche l'impact à mi-phase 2
			if not _swing_impact_triggered and _swing_phase_timer >= swing_phase2_duration * 0.5:
				_swing_impact_triggered = true
				if _swing_callback != Callable():
					_swing_callback.call()
					_swing_callback = Callable()
					print("[Swing] Impact déclenché !")

			if _swing_phase_timer >= swing_phase2_duration:
				_swing_phase = SwingPhase.RETURN
				_swing_phase_timer = 0.0
				print("[Swing] Phase 3 : retour")

		SwingPhase.RETURN:
			# ── Phase 3 : retour — influence redescend, main revient au repos ─
			_swing_ik_influence = lerp(_swing_ik_influence, 0.0, swing_ik_blend_out * delta)
			# La position de repos se met à jour en temps réel
			var rest_pos = skeleton.to_global(
				skeleton.get_bone_global_pose(
					skeleton.find_bone("mixamorig_RightHand")
				).origin
			)
			hand_right_target.global_position = hand_right_target.global_position.lerp(
				rest_pos, swing_ik_blend_out * delta
			)
			if right_arm_ik:
				right_arm_ik.influence = _swing_ik_influence

			if _swing_phase_timer >= swing_return_duration:
				_end_tool_swing()

func _end_tool_swing() -> void:
	_is_swinging = false
	_swing_phase = SwingPhase.IDLE
	_swing_phase_timer = 0.0
	_swing_ik_influence = 0.0
	if right_arm_ik:
		right_arm_ik.influence = 0.0
	is_hand_interact_active = false
	print("[Swing] Terminé.")
	
func _die() -> void:
	if not is_multiplayer_authority():
		return
	if is_dead:
		return
	is_dead = true

	if isCarryingObject and is_instance_valid(carriedObject):   # 🆕
		carriedObject.rpc_release_grab.rpc(multiplayer.get_unique_id())

	var inventory_ui = $InventoryController/CanvasLayer/InventoryUI
	inventory_ui.drop_all_on_death()

	_rpc_sync_death.rpc()

@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_death() -> void:
	is_dead = true   # 🆕 indispensable pour que les marionnettes arrêtent aussi leur _process/_physics_process
	await get_tree().process_frame

	ik_toe_left.active = true   # _ready() et _rpc_sync_respawn() → true
	ik_toe_right.active = true  # _rpc_sync_death() → false
	right_arm_ik.active = false
	left_arm_ik.active = false
	ik_left.active = false
	ik_right.active = false
	lookhead.active = false

	if skeleton and _pelvis_bone_idx != -1:
		skeleton.reset_bone_pose(_pelvis_bone_idx)

	anim_tree.active = false

	# 🆕 Retire instantanément l'apparence de l'habit (pas de fondu pendant un ragdoll)
	equipped_clothing_data = null
	_apply_clothing_visibility(_base_skin_mesh_paths)

	print("[Mort] Le joueur est mort !")

	velocity = Vector3.ZERO

	$CollisionShape3D.disabled = true
	$CrouchCollisionSphere.disabled = true
	$CrouchCollisionSphere2.disabled = true
	$SwimmingCollisionSphere.disabled = true

	call_deferred("_activate_ragdoll")
	
func _activate_ragdoll() -> void:
	await get_tree().create_timer(0.05).timeout
	physical_bone_simulator.active = true
	physical_bone_simulator.physical_bones_start_simulation()
	await get_tree().process_frame
	_apply_ragdoll_impulse()
	await get_tree().create_timer(2.0).timeout
	
	if is_multiplayer_authority():
		_respawn()   # 🆕 remplace get_tree().reload_current_scene()

@export_group("Ragdoll - Flottabilité")
## Force de flottaison ascendante appliquée aux os immergés (par unité de masse)
@export var ragdoll_buoyancy_force: float = 4.0
## Freinage du mouvement des os pendant qu'ils sont sous l'eau (évite un flottement erratique)
@export var ragdoll_water_linear_damp: float = 3.0
@export var ragdoll_head_impulse: Vector3 = Vector3(0, 0.0, -1.0)
@export var ragdoll_spine_impulse: Vector3 = Vector3(0, 0.0, -2.0)
@export var ragdoll_legs_impulse: Vector3 = Vector3(0, 0.5, 0.9)

func _respawn() -> void:
	if not is_multiplayer_authority():
		return
	var respawn_pos: Vector3 = _last_checkpoint_position if _has_checkpoint else _initial_spawn_position
	_rpc_sync_respawn.rpc(respawn_pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_respawn(respawn_pos: Vector3) -> void:
	physical_bone_simulator.physical_bones_stop_simulation()
	physical_bone_simulator.active = true

	if skeleton and _pelvis_bone_idx != -1:
		skeleton.reset_bone_pose(_pelvis_bone_idx)

	ik_toe_left.active = true   # _ready() et _rpc_sync_respawn() → true
	ik_toe_right.active = true  # _rpc_sync_death() → false
	right_arm_ik.active = true
	left_arm_ik.active = true
	ik_left.active = true
	ik_right.active = true
	lookhead.active = true
	anim_tree.active = true

	$CollisionShape3D.disabled = false
	$CrouchCollisionSphere.disabled = true
	$CrouchCollisionSphere2.disabled = true
	$SwimmingCollisionSphere.disabled = true

	# Sécurité : on s'assure qu'aucun état d'interaction ne reste bloqué
	is_hand_interact_active = false
	_is_swinging = false
	_is_consuming = false
	_is_cooldown_interacting = false
	_is_climbing_out = false
	_is_equipping_clothing = false
	isCarryingObject = false   # 🆕
	carriedObject = null       # 🆕
	carriedLeftMarker = null   # 🆕
	carriedRightMarker = null  # 🆕
	_is_carrying_left = false  # 🆕
	_update_camera_attachment(false)

	global_position = respawn_pos
	velocity = Vector3.ZERO
	is_dead = false

	if is_multiplayer_authority():
		current_health = max_health
		max_oxygen = base_max_oxygen
		current_oxygen = max_oxygen
		_oxygen_reserves.clear()
		_oxygen_reserves[""] = current_oxygen
		health_bar_ui.update(current_health, max_health)
		if oxygen_bar_ui:
			oxygen_bar_ui.update(current_oxygen, max_oxygen)

	print("[Respawn] Joueur réapparu.")

func _apply_ragdoll_impulse() -> void:
	# Convertit les directions locales en directions mondiales
	var basis = global_transform.basis

	for bone in physical_bone_simulator.get_children():
		if not bone is PhysicalBone3D:
			continue

		var bone_name = bone.name

		if "Head" in bone_name or "Neck" in bone_name:
			bone.apply_central_impulse(basis * ragdoll_head_impulse)

		elif "Spine2" in bone_name or "Spine1" in bone_name:
			bone.apply_central_impulse(basis * ragdoll_spine_impulse)

		elif "Spine" in bone_name or "Hips" in bone_name:
			bone.apply_central_impulse(basis * ragdoll_spine_impulse)

		elif "Arm" in bone_name or "Shoulder" in bone_name:
			bone.apply_central_impulse(basis * ragdoll_spine_impulse)

		elif "Leg" in bone_name or "Foot" in bone_name or "Thigh" in bone_name:
			bone.apply_central_impulse(basis * ragdoll_legs_impulse)
			
			
			
## Démarre une interaction cooldown (appelée par InventoryController)
func start_cooldown_interaction(
		marker: Marker3D,
		duration: float,
		target_node: Node,
		callback: Callable
) -> void:
	if not is_multiplayer_authority():
		return
	if _is_cooldown_interacting:
		return

	_cooldown_duration = max(duration, 0.1)
	_cooldown_callback = callback        # reste local : seule l'autorité valide/termine l'interaction
	_cooldown_target_node = target_node  # idem : sert à la vérification de portée côté autorité

	_rpc_sync_cooldown_start.rpc(marker.get_path())
	print("[CooldownInteraction] Démarrage — durée : ", duration, "s")


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_cooldown_start(marker_path: NodePath) -> void:
	var marker := get_node_or_null(marker_path)
	if marker == null:
		return
	_is_cooldown_interacting = true
	_cooldown_timer = 0.0
	_cooldown_marker = marker
	_pickup_marker = marker
	is_hand_interact_active = true
 
## Annule l'interaction en cours (appelée depuis l'extérieur ou en interne)
func cancel_cooldown_interaction() -> void:
	if not is_multiplayer_authority():
		return
	if not _is_cooldown_interacting:
		return

	_cooldown_timer = 0.0
	_cooldown_callback = Callable()
	_cooldown_target_node = null

	_rpc_sync_cooldown_cancel.rpc()
	print("[CooldownInteraction] Annulée.")


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_cooldown_cancel() -> void:
	_is_cooldown_interacting = false
	_cooldown_marker = null
	_pickup_marker = null
	is_hand_interact_active = false
 
## Mise à jour interne du cooldown — appelée depuis _update_hand_ik chaque frame
func _update_cooldown_interaction(delta: float) -> void:
	_cooldown_timer += delta
 
	# Émet la progression (pour une barre UI)
	emit_signal("cooldown_progress", clamp(_cooldown_timer / _cooldown_duration, 0.0, 1.0))
 
	# Maintient la cible IK sur le marqueur
	if _cooldown_marker != null and is_instance_valid(_cooldown_marker):
		hand_right_target.global_position = _cooldown_marker.global_transform.origin
 
	# Cooldown terminé
	if _cooldown_timer >= _cooldown_duration:
		var cb = _cooldown_callback
		_is_cooldown_interacting = false
		_cooldown_timer = 0.0
		_cooldown_callback = Callable()
		_cooldown_target_node = null
		_cooldown_marker = null
		_pickup_marker = null
		is_hand_interact_active = false
 
		if cb != Callable():
			cb.call()
		print("[CooldownInteraction] Terminée avec succès.")
		
# --- SYSTÈME DE DEBUG IK ---
var debug_sphere_heel_l: MeshInstance3D
var debug_sphere_toe_l: MeshInstance3D
var debug_sphere_heel_r: MeshInstance3D
var debug_sphere_toe_r: MeshInstance3D

## Démarre la remontée vers le rebord du bassin.
## Appelée par InteractionManager.
func start_climb_out(exit_pos: Vector3) -> void:
	if _is_climbing_out or not is_swimming:
		return
	_is_climbing_out = true
	_climb_out_target = exit_pos
	_climb_out_timer = 0.0
	velocity = Vector3.ZERO
	print("[ClimbOut] Remontée démarrée → ", exit_pos)


## Mise à jour du mouvement de remontée — appelée chaque frame par _physics_process.
func _update_climb_out(delta: float) -> void:
	_climb_out_timer += delta

	# Timeout de sécurité (joueur bloqué contre un mur, etc.)
	if _climb_out_timer > climb_out_timeout:
		_is_climbing_out = false
		print("[ClimbOut] Timeout — remontée annulée.")
		return

	var to_target: Vector3 = _climb_out_target - global_position

	# ── Arrivée à destination ──────────────────────────────────────────────────
	if to_target.length() < 0.25:
		global_position = _climb_out_target
		velocity = Vector3.ZERO
		_is_climbing_out = false
		print("[ClimbOut] Sortie du bassin terminée !")
		return

	var vertical_diff: float = _climb_out_target.y - global_position.y

	# ── Phase 1 : Montée verticale ─────────────────────────────────────────────
	# Tant que la cible est au-dessus, on monte en priorité
	if vertical_diff > 0.3:
		velocity.y = lerp(velocity.y, climb_out_speed * 1.8, 12.0 * delta)
		# Légère correction horizontale pour s'éloigner du mur
		velocity.x = lerp(velocity.x, to_target.x * 0.8, 8.0 * delta)
		velocity.z = lerp(velocity.z, to_target.z * 0.8, 8.0 * delta)

	# ── Phase 2 : Glissement horizontal vers le rebord ─────────────────────────
	else:
		var dir: Vector3 = to_target.normalized()
		velocity = velocity.lerp(dir * climb_out_speed, 10.0 * delta)
		
		

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_pickup_ik(marker_path: NodePath) -> void:
	# Grâce aux noms synchronisés, le get_node_or_null trouvera l'objet à coup sûr !
	var target_marker = get_node_or_null(marker_path)
	if target_marker is Marker3D:
		activate_pickup_hand_ik(target_marker)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_drop_ik() -> void:
	deactivate_pickup_hand_ik()
	
	
# ── HELPERS RÉSEAU (choisissent la bonne source selon l'autorité) ─────────────

## Vélocité correcte : physique locale pour l'autorité, réseau pour les marionnettes
func _eff_velocity() -> Vector3:
	return velocity if is_multiplayer_authority() else _net_velocity

## État sol correct : CharacterBody3D pour l'autorité, réseau pour les marionnettes  
func _eff_on_floor() -> bool:
	return is_on_floor() if is_multiplayer_authority() else _net_is_on_floor

## Rotation sur place correcte
func _eff_turning() -> bool:
	return is_turning_in_place if is_multiplayer_authority() else _net_is_turning
	
## Bascule la position de la CameraPivot : sur la capsule (normal) ou sur le squelette (nage)
func _update_camera_attachment(swimming: bool) -> void:
	if swimming and _camera_attached_to_body:
		camera_remote.remote_path = camera_pivot.get_path()
		_camera_attached_to_body = false
	elif not swimming and not _camera_attached_to_body:
		camera_remote.remote_path = NodePath("")
		_camera_attached_to_body = true
		camera_pivot.position = cam_original_local_position   # ← AJOUT : retour exact à la position éditeur


func _update_oxygen(delta: float) -> void:
	if is_dead:
		return

	var head_submerged := false
	var head_depth := 0.0
	
	# --- CORRECTION ICI : On supprime "is_swimming and" ---
	if water:
		var water_height: float = water.get_height(mouth_anchor.global_position)
		head_depth = water_height - mouth_anchor.global_position.y
		head_submerged = head_depth > 0.0

	wearing_heavy_suit = _is_wearing_heavy_suit()   # 🆕 annule tous les effets de profondeur

	if head_submerged:
		# 🆕 Au-delà du seuil critique : dégâts directs, quel que soit l'air restant — sauf en scaphandre
		if not wearing_heavy_suit and head_depth >= depth_damage_threshold:
			if not $AudioStreamPlayer3D.playing:
				$AudioStreamPlayer3D.play()
			take_damage(depth_damage_per_sec * delta)

		# 🆕 Plus on descend, plus l'air se consomme vite — sauf en scaphandre (respiration normale à toute profondeur)
		var drain_multiplier := 1.0
		if not wearing_heavy_suit and head_depth > depth_drain_start:
			var t: float = clamp(
				(head_depth - depth_drain_start) / max(depth_damage_threshold - depth_drain_start, 0.01),
				0.0, 1.0
			)
			drain_multiplier = lerp(1.0, depth_oxygen_drain_multiplier, t)

		current_oxygen = max(current_oxygen - oxygen_drain_rate * drain_multiplier * delta, 0.0)
		if current_oxygen <= 0.0:
			if not $AudioStreamPlayer3D.playing:
				$AudioStreamPlayer3D.play()
			take_damage(drowning_damage_per_sec * delta)
	else:
		current_oxygen = min(current_oxygen + oxygen_regen_rate * delta, max_oxygen)

	if oxygen_bar_ui:
		oxygen_bar_ui.update(current_oxygen, max_oxygen)
		oxygen_bar_ui.visible = current_oxygen < max_oxygen
		
# ── HABITS (CLOTHING) ────────────────────────────────────────────────────────
@export_group("Habits")
@export var default_body_mesh_paths: Array[String] = []
## Gravité appliquée sous l'eau quand on porte un habit "heavy_diving_suit" (1.0 = gravité normale terrestre)
@export var diving_suit_gravity_scale: float = 0.35
@export var heavy_suit_jump_multiplier: float = 0.5 

var equipped_clothing_data: ItemData = null

## Le mesh de base réellement utilisé par CE joueur (dépend du skin choisi en lobby).
## Remplace l'usage figé de default_body_mesh_paths comme référence "sans habit".
var _base_skin_mesh_paths: PackedStringArray = []

func _apply_skin(skin_id: String) -> void:
	var skin_data: SkinData = SkinRegistry.get_skin_data(skin_id)
	var paths: PackedStringArray = []
	if skin_data and not skin_data.skin_mesh_node_paths.is_empty():
		for p in skin_data.skin_mesh_node_paths:
			paths.append(str(p))
	else:
		for p in default_body_mesh_paths:
			paths.append(p)   # repli de sécurité si aucun skin valide trouvé

	_base_skin_mesh_paths = paths
	_apply_clothing_visibility(paths)   # ✅ même fonction que pour les habits

## Vrai si l'habit actuellement porté restreint les déplacements (ex: scaphandre)
func _is_wearing_heavy_suit() -> bool:
	return equipped_clothing_data != null and equipped_clothing_data.heavy_diving_suit


func _apply_clothing_visibility(mesh_path_strings: PackedStringArray) -> void:
	var visible_nodes: Array[Node] = []
	for s in mesh_path_strings:
		var n = skeleton.get_node_or_null(NodePath(s))
		if n:
			visible_nodes.append(n)

	for child in skeleton.get_children():
		if child is MeshInstance3D and child.is_in_group("OutfitMesh"):
			child.visible = child in visible_nodes


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_equip_clothing(mesh_path_strings: PackedStringArray) -> void:
	_apply_clothing_visibility(mesh_path_strings)



	
# ── HABILLAGE : transition visuelle ──────────────────────────────────────────
var _is_equipping_clothing: bool = false
var _equip_clothing_timer: float = 0.0
@export var equip_clothing_duration: float = 1.4
var _equip_clothing_applied: bool = false
var _equip_clothing_pending_data: ItemData = null
var _equip_clothing_is_removal: bool = false

@onready var equip_fade_rect: ColorRect = $InventoryController/CanvasLayer/EquipFade


func equip_clothing(data: ItemData) -> void:
	if not is_multiplayer_authority():
		return
	if _is_equipping_clothing:
		return
	_is_equipping_clothing = true
	_equip_clothing_timer = 0.0
	_equip_clothing_applied = false
	_equip_clothing_pending_data = data
	_equip_clothing_is_removal = false
	print("[Habit] Début de l'habillage : ", data.item_name)
	
func unequip_clothing() -> void:
	if not is_multiplayer_authority():
		return
	if _is_equipping_clothing:
		return
	_is_equipping_clothing = true
	_equip_clothing_timer = 0.0
	_equip_clothing_applied = false
	_equip_clothing_is_removal = true
	print("[Habit] Début du retrait.")
	

func _update_equip_clothing_transition(delta: float) -> void:
	if not _is_equipping_clothing:
		return

	_equip_clothing_timer += delta
	var progress: float = _equip_clothing_timer / equip_clothing_duration

	if equip_fade_rect:
		var alpha: float = 0.0
		if progress < 0.5:
			alpha = progress / 0.5
		else:
			alpha = 1.0 - ((progress - 0.5) / 0.5)
		equip_fade_rect.color.a = alpha
		equip_fade_rect.visible = alpha > 0.01

	# Au point le plus sombre : on applique réellement le changement
	if not _equip_clothing_applied and progress >= 0.5:
		_equip_clothing_applied = true
		if _equip_clothing_is_removal:
			_apply_clothing_unequip()
		else:
			_apply_clothing_equip(_equip_clothing_pending_data)

	if progress >= 1.0:
		_is_equipping_clothing = false
		_equip_clothing_pending_data = null
		


func _apply_clothing_equip(data: ItemData) -> void:
	# 🆕 On sauvegarde la réserve d'air de la tenue qu'on quitte (civil, ou habit précédent)
	_oxygen_reserves[_oxygen_key_for(equipped_clothing_data)] = current_oxygen

	equipped_clothing_data = data

	if data.oxygen_multiplier != 1.0:
		max_oxygen = (base_max_oxygen + data.oxygen_bonus) * data.oxygen_multiplier
	else:
		max_oxygen = base_max_oxygen + data.oxygen_bonus

	# 🆕 Réserve propre à CET habit. Pleine la toute première fois qu'on le porte.
	var key := _oxygen_key_for(data)
	current_oxygen = min(_oxygen_reserves.get(key, max_oxygen), max_oxygen)

	var paths: PackedStringArray = []
	for p in data.clothing_mesh_node_paths:
		paths.append(str(p))

	if data.show_civilian_with_clothing:
		for p in default_body_mesh_paths:
			paths.append(str(p))

	_rpc_sync_equip_clothing.rpc(paths)

func _apply_clothing_unequip() -> void:
	# 🆕 On sauvegarde la réserve d'air de l'habit qu'on retire
	_oxygen_reserves[_oxygen_key_for(equipped_clothing_data)] = current_oxygen

	equipped_clothing_data = null
	max_oxygen = base_max_oxygen

	# 🆕 On restaure la réserve civile
	current_oxygen = min(_oxygen_reserves.get("", max_oxygen), max_oxygen)

	if _base_skin_mesh_paths.is_empty():
		push_warning("[Habit] Aucun skin de base enregistré — impossible de restaurer l'apparence !")

	_rpc_sync_equip_clothing.rpc(_base_skin_mesh_paths)
	print("[Habit] Retiré, retour au skin de base.")
	
## Remplace la gravité par une flottabilité sur les os du ragdoll immergés.
## Tourne localement chez CHAQUE pair (la simulation ragdoll n'est pas répliquée),
## exactement comme _apply_ragdoll_impulse().
func _update_ragdoll_buoyancy(delta: float) -> void:
	if not physical_bone_simulator.active:
		return
	if water == null:
		return

	for bone in physical_bone_simulator.get_children():
		if not bone is PhysicalBone3D:
			continue

		var bone_pos: Vector3 = bone.global_position
		var water_height: float = water.get_height(bone_pos)
		var submerged: bool = water_height > bone_pos.y

		bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE

		if submerged:
			bone.gravity_scale = 0.0   # 🆕 plus de gravité sous l'eau...
			bone.linear_damp = ragdoll_water_linear_damp
			bone.apply_central_impulse(Vector3.UP * ragdoll_buoyancy_force * bone.mass * delta)   # ...remplacée par la flottabilité
		else:
			bone.gravity_scale = 1.0
			bone.linear_damp = 0.0

func _play_footstep() -> void:
	# Alterne entre le pied gauche et le pied droit en utilisant tes RayCasts IK existants
	var current_ray = ray_left if _last_foot_was_left else ray_right
	_last_foot_was_left = not _last_foot_was_left
	
	
	if not current_ray.is_colliding():
		return
		
	var collider = current_ray.get_collider()
	var streams_to_play: Array[AudioStream] = []
	
	# Vérifie les groupes du sol pour choisir le bon tableau de sons
	if collider.is_in_group("mat_metal"):
		streams_to_play = sound_metal
	elif collider.is_in_group("mat_wood"):
		streams_to_play = sound_wood
	elif collider.is_in_group("mat_concrete"):
		streams_to_play = sound_concrete
	else:
		# Son par défaut si aucun groupe n'est trouvé
		streams_to_play = sound_dirt 
		
	# Joue un son aléatoire si le tableau n'est pas vide
	if streams_to_play.size() > 0:
		var random_stream = streams_to_play.pick_random()
		footstep_player.stream = random_stream
		# Varie légèrement la hauteur du son pour plus de réalisme
		footstep_player.pitch_scale = randf_range(0.85, 1.15)
		footstep_player.play()

func _handle_footsteps(delta: float) -> void:
	# On ignore le calcul si le joueur nage ou n'est pas au sol
	# (Tu peux aussi utiliser tes raycasts IK s'ils sont mis à jour pour les marionnettes)
	if is_swimming and ! wearing_heavy_suit or not is_on_floor():
		_step_distance_accumulator = step_interval * 0.8
		return
		
	# On calcule la vitesse horizontale réelle de ce personnage (marionnette ou local)
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# Si le personnage bouge suffisamment pour qu'on considère qu'il marche
	if horizontal_speed > 0.5:
		# Distance = Vitesse * Temps
		var distance_moved = horizontal_speed * delta
		_step_distance_accumulator += distance_moved
		
		# Ajustement de la foulée : on allonge la distance du pas si le joueur court
		# (On clamp pour éviter des divisions par zéro ou des valeurs extrêmes)
		var speed_ratio = clamp(horizontal_speed / WALK_SPEED, 0.5, 2.0)
		var actual_interval = step_interval * speed_ratio
		
		if _step_distance_accumulator >= actual_interval:
			_play_footstep()
			_step_distance_accumulator = 0.0
	else:
		# Le joueur est presque à l'arrêt, on garde l'accumulateur chargé pour le prochain départ
		_step_distance_accumulator = step_interval * 0.8
		
# ── ÉCHELLE : API appelée par Ladder3D (Area3D) ────────────────────────────────
## Le joueur entre dans la zone de grimpe d'une échelle
func _enter_ladder_zone(ladder: Ladder3D) -> void:
	if not _nearby_ladders.has(ladder):
		_nearby_ladders.append(ladder)
	current_ladder = _nearby_ladders.back()

## Le joueur quitte la zone de grimpe d'une échelle
func _exit_ladder_zone(ladder: Ladder3D) -> void:
	_nearby_ladders.erase(ladder)
	current_ladder = _nearby_ladders.back() if not _nearby_ladders.is_empty() else null
	if current_ladder == null:
		is_climbing_ladder = false
		
		
# ── ÉCHELLE : physique de grimpe ────────────────────────────────────────────────
## Gère la grimpe façon Minecraft : marcher vers l'échelle fait monter, marcher en
## arrière fait descendre. Retourne true si le joueur grimpe activement ce frame
## (le mouvement normal doit alors être court-circuité par l'appelant).
func _handle_ladder_physics(delta: float) -> bool:
	if current_ladder == null:
		is_climbing_ladder = false
		return false

	# Seule l'autorité réseau du joueur simule sa propre physique de grimpe
	if not is_multiplayer_authority():
		return is_climbing_ladder

	if _ladder_release_cooldown > 0.0:
		_ladder_release_cooldown -= delta

	var into_dir: Vector3 = current_ladder.get_into_direction()

	# Direction de déplacement voulue par le joueur (même logique que la marche normale)
	var input_dir := Input.get_vector("ui_right", "ui_left", "ui_down", "ui_up")
	var cam_basis = camera_pivot.global_transform.basis
	var wish_dir: Vector3 = cam_basis * Vector3(input_dir.x, 0, input_dir.y)
	wish_dir.y = 0.0
	var has_input := wish_dir.length() > 0.05
	if has_input:
		wish_dir = wish_dir.normalized()

	# > 0 : le joueur marche VERS l'échelle (montera) / < 0 : à l'opposé (descendra)
	var push_amount: float = wish_dir.dot(into_dir) if has_input else 0.0

	# ── Accroche : il faut pousser franchement vers l'échelle pour s'y accrocher ──
	if not is_climbing_ladder:
		if _ladder_release_cooldown > 0.0 or push_amount <= ladder_grab_deadzone:
			return false
		is_climbing_ladder = true

	# ── Saut = lâcher l'échelle en repoussant le joueur en arrière ─────────────
	if ladder_allow_jump_off and Input.is_action_just_pressed("ui_accept"):
		is_climbing_ladder = false
		_ladder_release_cooldown = 0.25
		velocity = -into_dir * WALK_SPEED + Vector3.UP * (JUMP_VELOCITY * 0.6)
		return true

	# ── Montée / descente : la vitesse verticale suit l'intention du joueur ────
	var target_vertical_speed: float = (push_amount * ladder_climb_speed) if has_input else 0.0
	velocity.y = move_toward(velocity.y, target_vertical_speed, ladder_climb_speed * 8.0 * delta)

	# ── Glissement latéral le long de l'échelle ─────────────────────────────────
	var side_dir: Vector3 = into_dir.cross(Vector3.UP)
	var side_amount: float = wish_dir.dot(side_dir) if has_input else 0.0
	var lateral_velocity: Vector3 = side_dir * side_amount * ladder_strafe_speed
	velocity.x = lateral_velocity.x
	velocity.z = lateral_velocity.z

	# ── Le personnage fait face au mur pendant la grimpe ────────────────────────
	if ladder_face_wall:
		var target_yaw := atan2(-into_dir.x, -into_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 10.0 * delta)

	# ── Sortie en bas : on touche le sol en descendant (ou à l'arrêt) ───────────
	if is_on_floor() and target_vertical_speed <= 0.0:
		is_climbing_ladder = false
		_ladder_release_cooldown = 0.15
		return false

	return true
	
## Pilote l'anim de grimpe : fait apparaître/disparaître le blend, et règle le
## sens de lecture du clip (avant = monte, arrière = descend, ~0 = suspendu).
## Appelée à la fois pendant la grimpe (court-circuit physique) et pendant
## update_animations() en temps normal (pour redescendre le blend à 0).
func _update_climb_animation(delta: float) -> void:
	var target_climb_val = 1.0 if is_climbing_ladder else 0.0
	climb_blend_val = lerp(climb_blend_val, target_climb_val, 7.0 * delta)
	anim_tree.set("parameters/climbing/blend_amount", climb_blend_val)

	# Sens/vitesse de lecture du clip : >0 monte, <0 descend, ~0 suspendu
	var climb_speed_ratio := 0.0
	if is_climbing_ladder:
		climb_speed_ratio = clamp(velocity.y / ladder_climb_speed, -1.0, 1.0)
	anim_tree.set("parameters/TimeScale/scale", climb_speed_ratio)


func _ignore_self_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is RayCast3D:
			# Le Raycast ignorera la Hitbox de ce script
			child.add_exception(self)
		elif child is SpringArm3D:
			# Le SpringArm utilise le RID pour les exclusions
			child.add_excluded_object(self.get_rid())
		
		# Récursion pour s'assurer de trouver les nœuds imbriqués (ex: dans CameraPivot)
		if child.get_child_count() > 0:
			_ignore_self_collisions(child)
