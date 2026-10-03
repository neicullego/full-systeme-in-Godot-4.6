# InventoryController.gd
extends Control
class_name InventoryController

var item_memory = false
var slot_memory = null

var data: ItemData = null

@onready var clothing_slot: InventorySlots = %ClothingSlot

var item = null

# Stockage local des offsets pour l'autorité ET les marionnettes
var _current_item_pos_offset: Vector3 = Vector3.ZERO
var _current_item_rot_offset: Vector3 = Vector3.ZERO

var item_slots_count: int = 9
var inventory_slot_prefab: PackedScene = load("res://scene/ui/inventory_slot.tscn")

@onready var inventory_grid: GridContainer = %GridContainer

var is_inventory_open: bool = false

var inventory_slots: Array[InventorySlots] = []
var inventory_full: bool = false

# Référence au joueur (assignée depuis la scène principale)
var player_node: Node3D = null

# L'item actuellement tenu en main
var equipped_slot: InventorySlots = null
var equipped_instance: Node3D = null  # Le modèle 3D dans la main

# Référence au Marker3D de la main (assignée depuis la scène principale)
var hand_anchor: Marker3D = null

func _ready() -> void:
	if not is_multiplayer_authority():
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if get_parent() is CanvasLayer:
			get_parent().visible = false
		return
		
	for i in item_slots_count:
		var slot = inventory_slot_prefab.instantiate() as InventorySlots
		inventory_grid.add_child(slot)
		inventory_slots.append(slot)
		slot.slot_left_clicked.connect(_on_slot_left_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_dropped.connect(_on_slot_dropped) # 🆕 Connexion du drag and drop

	if clothing_slot:
		clothing_slot.slot_left_clicked.connect(_on_slot_left_clicked)
		clothing_slot.slot_right_clicked.connect(_on_slot_right_clicked)
		clothing_slot.slot_dropped.connect(_on_slot_dropped) # 🆕

# ── Clic gauche : équiper / déséquiper ────────────────────────────────────────
func _on_slot_left_clicked(slot: InventorySlots) -> void:
	if not is_multiplayer_authority():
		return
	if slot.is_empty():
		return
	
	# 🆕 Clic sur l'emplacement Habit lui-même → on le retire
	if slot == clothing_slot:
		_unequip_clothing()
		return

	# 🆕 Clic sur un habit dans la grille → on l'équipe (jamais dans la main)
	if slot.item_data.item_type == ItemData.ItemType.CLOTHING:
		_equip_clothing(slot)
		return
	
	if slot == equipped_slot:
		# ✅ Si l'inventaire est ouvert → toujours déséquiper, jamais swinguer
		if is_inventory_open:
			_unequip_item()
			return

		match slot.item_data.item_type:
			ItemData.ItemType.CONSUMABLE:
				_use_consumable(slot)
				return
			ItemData.ItemType.TOOL:
				_use_tool(slot)
				return
			ItemData.ItemType.COOLDOWN_TOOL:   # ← AJOUTER CES 3 LIGNES
				_use_cooldown_tool(slot)
				return
			_:
				_unequip_item()
				return

	_equip_item(slot)

# ── Clic droit : jeter depuis la main ─────────────────────────────────────────
func _on_slot_right_clicked(slot: InventorySlots) -> void:
	if not is_multiplayer_authority():
		return
	if slot.is_empty():
		return
		
	data = slot.item_data
	
	# 🆕 Jeter l'habit actuellement porté
	if slot == clothing_slot:
		clothing_slot.clear_slot()
		if player_node:
			player_node.unequip_clothing()
		_drop_item(data, slot)
		return

	# 🆕 Jeter un habit qui est simplement dans la grille (jamais via la main)
	if data.item_type == ItemData.ItemType.CLOTHING:
		_drop_item(data, slot)
		return
	
	# Dans tous les cas : on équipe d'abord, puis on lâche depuis la main
	if slot != equipped_slot:
		_equip_item(slot)
	_drop_from_hand(slot)

# ── Équiper : faire apparaître l'item dans la main ────────────────────────────
func _equip_item(slot: InventorySlots) -> void:
	if hand_anchor == null:
		print("[Équipement] ERREUR : hand_anchor est null !")
		return
	equipped_slot = slot
	data = slot.item_data
	item = data

	if data.pickup_scene_path == "":
		return

	# ✅ Un seul RPC envoyé uniquement au moment du clic !
	_rpc_sync_equip.rpc(data.pickup_scene_path, data.hand_position_offset, data.hand_rotation_offset)
	print("[Équipement] Succès ! ", data.item_name, " équipé.")


func _unequip_item() -> void:
	if player_node and player_node._is_cooldown_interacting:
		var target = player_node._cooldown_target_node
		if target and is_instance_valid(target) and target.has_method("cancel_interaction"):
			target.cancel_interaction()
		player_node.cancel_cooldown_interaction()
		
	equipped_slot = null
	
	# ✅ Un seul RPC pour dire à tout le monde d'enlever l'objet
	_rpc_sync_unequip.rpc()
	print("[Équipement] Item déséquipé.")

# ── Drop depuis la main : jeter à la position de la main ──────────────────────
# ── Drop depuis la main ────────────────────────────────────────────────────────
# ── Drop depuis la main ────────────────────────────────────────────────────────
func _drop_from_hand(slot: InventorySlots) -> void:
	if not is_multiplayer_authority():
		return

	# ✅ On capture TOUT ce dont on a besoin AVANT tout appel destructeur
	data = slot.item_data
	if data == null:
		return
	
	slot_memory = null
	
	var drop_position: Vector3
	if hand_anchor != null:
		drop_position = hand_anchor.global_position
	elif player_node != null:
		drop_position = player_node.global_position + (-player_node.global_transform.basis.z * 1.2)
	else:
		drop_position = Vector3.ZERO

	var drop_velocity: Vector3 = Vector3.ZERO
	if player_node != null:
		drop_velocity = (-player_node.global_transform.basis.z * 3.0) + (Vector3.UP * 1.5)

	if data.pickup_scene_path == "":
		return

	# ✅ On génère le nom AVANT _unequip_item()
	var generated_name = "Dropped_" + data.item_id + "_" + str(Time.get_ticks_msec())

	# 1. Déséquipe — equipped_slot devient null ici, mais on s'en fiche
	_unequip_item()
	# 2. Vide le slot UI
	slot.clear_slot()
	
	if not data.stays_on_ground:
		_rpc_sync_drop.rpc(data.pickup_scene_path, drop_position, drop_velocity, generated_name)
		print("[Drop] ", data.item_name, " jeté depuis la main via réseau.")
	else:
		print("[Drop] ", data.item_name, " supprimé définitivement (stays_on_ground).")

# ── Drop classique (depuis la grille d'inventaire directement) ──────────────────
func _drop_item(data: ItemData, slot: InventorySlots) -> void:
	if not is_multiplayer_authority():
		return

	if data == null:
		return

	slot.clear_slot()
	if player_node == null:
		push_warning("[Drop] player_node est null.")
		return
	if data.pickup_scene_path == "":
		push_warning("[Drop] pickup_scene_path est VIDE sur '" + data.item_name + "' — impossible de l'instancier au sol !")
		return

	var drop_position = player_node.global_position + (-player_node.global_transform.basis.z * 1.2)
	var drop_velocity  = -player_node.global_transform.basis.z * 2.0

	# ✅ On utilise `data` (paramètre), plus equipped_slot qui peut être null
	var generated_name = "Dropped_" + data.item_id + "_" + str(Time.get_ticks_msec())
	if not data.stays_on_ground:
		_rpc_sync_drop.rpc(data.pickup_scene_path, drop_position, drop_velocity, generated_name)
		print("[Drop] ", data.item_name, " jeté depuis la grille via réseau.")
	else:
		print("[Drop] ", data.item_name, " supprimé de la grille (stays_on_ground).")
# ── Configure la physique de l'objet (équipé vs jeté) ────────────────────────
func _set_item_physics_mode(node: Node, is_equipped: bool) -> void:
	if node is CollisionShape3D:
		node.disabled = is_equipped
	elif node is RigidBody3D:
		node.freeze = is_equipped
		if is_equipped:
			# ✅ CRUCIAL : Permet au RigidBody de suivre les animations du parent/os
			node.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			node.linear_velocity = Vector3.ZERO
			node.angular_velocity = Vector3.ZERO
		else:
			# Quand on le jette, on peut le repasser en mode statique par défaut avant qu'il tombe
			node.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			
	# On applique la règle récursivement à tous les enfants
	for child in node.get_children():
		_set_item_physics_mode(child, is_equipped)

# ── Fonctions existantes ───────────────────────────────────────────────────────
func add_item(data: ItemData) -> bool:
	for slot in inventory_slots:
		if slot.is_empty():
			slot.set_item(data)
			print("[Inventaire] Ajouté : ", data.item_name)
			inventory_full = false
			return true
	inventory_full = true
	print("[Inventaire] Inventaire plein ! Objet jeté au sol pour ne pas le perdre : ", data.item_name)
	_drop_on_ground(data)  # 🆕
	return false
	
func _drop_on_ground(data: ItemData) -> void:
	if not is_multiplayer_authority():
		return
	if data == null:
		return
	if player_node == null:
		push_warning("[Drop] player_node est null, impossible de jeter '" + data.item_name + "' au sol.")
		return
	if data.pickup_scene_path == "":
		push_warning("[Drop] pickup_scene_path est VIDE sur '" + data.item_name + "' — impossible de l'instancier au sol !")
		return

	var drop_position = player_node.global_position + (-player_node.global_transform.basis.z * 1.2)
	var drop_velocity  = -player_node.global_transform.basis.z * 2.0

	var generated_name = "Dropped_" + data.item_id + "_" + str(Time.get_ticks_msec())
	if not data.stays_on_ground:
		_rpc_sync_drop.rpc(data.pickup_scene_path, drop_position, drop_velocity, generated_name)
		print("[Inventaire plein] ", data.item_name, " jeté au sol automatiquement.")
	else:
		print("[Inventaire plein] Impossible d'ajouter ", data.item_name, " : objet ignoré (stays_on_ground).")

func remove_item(item_id: String) -> void:
	for slot in inventory_slots:
		if not slot.is_empty() and slot.item_data.item_id == item_id:
			slot.clear_slot()
			return

func has_item(item_id: String) -> bool:
	for slot in inventory_slots:
		if not slot.is_empty() and slot.item_data.item_id == item_id:
			return true
	return false
	
	
func _physics_process(_delta: float) -> void:
	_update_equipped_item_transform()
	
	if not is_multiplayer_authority():
		return
	
	if Input.is_action_just_pressed("unequipe_input"):
		unequipe_input()

	if Input.is_action_just_pressed("drop_input"):
		drop_input()

	
	if player_node and player_node._is_cooldown_interacting:
		var raycast: RayCast3D = player_node.get_node("CameraPivot/PhysicsRayCast")
		raycast.force_raycast_update()
		var target_node: Node = player_node._cooldown_target_node
		var collider: Node = raycast.get_collider() if raycast.is_colliding() else null
		var hit_interactable: Node = _find_cooldown_interactable(collider) if collider else null
		if hit_interactable != target_node:
			if target_node and is_instance_valid(target_node) and target_node.has_method("cancel_interaction"):
				target_node.cancel_interaction()
			player_node.cancel_cooldown_interaction()
			print("[CooldownTool] Interaction annulée — cible perdue.")
		
func get_slot_with_item(item_id: String) -> InventorySlots:
	for slot in inventory_slots:
		if not slot.is_empty() and slot.item_data.item_id == item_id:
			return slot
	return null
	
	
func _use_consumable(slot: InventorySlots) -> void:
	if player_node == null:
		return

	data = slot.item_data
	print("[Consommable] Utilisation de : ", data.item_name)

	# Lance l'animation IK — l'effet est appliqué à mi-animation
	player_node.start_consume_animation(func():
		# Applique l'effet de santé
		if data.health_effect > 0:
			player_node.heal(data.health_effect)
		elif data.health_effect < 0:
			player_node.take_damage(abs(data.health_effect))

		# Retire l'item de l'inventaire et le déséquipe
		_unequip_item()
		slot.clear_slot()
		print("[Consommable] Effet appliqué : ", data.health_effect, " PV")
	)



func _use_tool(slot: InventorySlots) -> void:
	if player_node == null:
		return
	if player_node._is_swinging:
		return

	data = slot.item_data
	print("[Outil] Utilisation de : ", data.item_name)

	# Passe le dictionnaire d'animations à start_tool_swing
	player_node.start_tool_swing(
		func(): _check_tool_impact(data),
		data.tool_animations  # ← le dictionnaire
	)

## Vérifie si le swing touche quelque chose
func _check_tool_impact(data: ItemData) -> void:
	if player_node == null:
		return

	var raycast: RayCast3D = player_node.get_node("CameraPivot/PhysicsRayCast")
	raycast.force_raycast_update()

	if not raycast.is_colliding():
		print("[Outil] Swing dans le vide.")
		return

	var collider = raycast.get_collider()

	var enemy_root = _find_in_group(collider, "Enemy")
	if enemy_root:
		if enemy_root.has_method("take_damage"):
			enemy_root.take_damage(data.tool_damage)
		return

	var interactive_root = _find_tool_interactable(collider)
	if interactive_root:
		var success = interactive_root.try_interact_with_tool(data.tool_required_id)
		if success:
			# Cache l'indicateur après interaction réussie
			var im = player_node.get_node_or_null("InteractionManager")
			if im and im._indicator:
				im._indicator.hide_indicator()
		else:
			# Mauvais outil → vibration
			var im = player_node.get_node_or_null("InteractionManager")
			if im:
				im.trigger_indicator_shake()
		return


## Remonte l'arbre pour trouver un nœud avec try_interact_with_tool
func _find_tool_interactable(node: Node) -> Node:
	var current = node
	while current != null:
		print("[DEBUG] Remontée : ", current.name, " | has try_interact_with_tool : ", current.has_method("try_interact_with_tool"))
		if current.has_method("try_interact_with_tool"):
			return current
		current = current.get_parent()
	return null

## Remonte l'arbre pour trouver un nœud dans un groupe
func _find_in_group(node: Node, group: String) -> Node:
	var current = node
	while current != null:
		if current.is_in_group(group):
			return current
		current = current.get_parent()
	return null
			
			
			
# ── Met à jour la position globale de l'objet en main avec les offsets ────────
func _update_equipped_item_transform() -> void:
	# ✅ On ne vérifie plus le slot, juste l'instance 3D et l'ancre de la main
	if equipped_instance == null or hand_anchor == null:
		return

	# 1. On extrait la rotation et la position globale de la main de ce joueur
	var hand_quat: Quaternion = hand_anchor.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var hand_pos: Vector3 = hand_anchor.global_position
	
	# 2. On recrée un Transform3D propre
	var clean_hand_transform := Transform3D(Basis(hand_quat), hand_pos)

	# 3. ✅ On applique les offsets mémorisés localement
	var rot_rad := Vector3(
		deg_to_rad(_current_item_rot_offset.x),
		deg_to_rad(_current_item_rot_offset.y),
		deg_to_rad(_current_item_rot_offset.z)
	)
	var offset_transform := Transform3D(Basis.from_euler(rot_rad), _current_item_pos_offset)

	# 4. Combinaison de l'ancre et de l'offset
	equipped_instance.global_transform = clean_hand_transform * offset_transform
	equipped_instance.scale = Vector3(1, 1, 1)
	
	
func _use_cooldown_tool(slot: InventorySlots) -> void:
	if player_node == null:
		return
	if player_node._is_cooldown_interacting:
		print("[CooldownTool] Interaction déjà en cours.")
		return

	data = slot.item_data
	var raycast: RayCast3D = player_node.get_node("CameraPivot/PhysicsRayCast")
	raycast.force_raycast_update()

	if not raycast.is_colliding():
		print("[CooldownTool] Rien en vue.")
		return

	var interactable: Node = _find_cooldown_interactable(raycast.get_collider())
	if interactable == null:
		print("[CooldownTool] Cible non compatible.")
		return

	# ── VÉRIFICATION DE L'OUTIL AVEC RETOUR VISUEL ─────────────────────────────
	if not interactable.try_interact(data.item_id): # <-- Assurez-vous de passer l'ID de l'item en main (data.item_id)
		# Mauvais outil ou objet déjà utilisé -> déclenche la vibration de refus
		var im = player_node.get_node_or_null("InteractionManager")
		if im:
			im.trigger_indicator_shake()
		return
	# ──────────────────────────────────────────────────────────────────────────

	var marker: Marker3D = interactable.get_hand_marker()
	if marker == null:
		push_error("[CooldownTool] Pas de marker_node sur : " + interactable.name)
		return

	interactable.start_interaction()
	player_node.start_cooldown_interaction(
		marker,
		data.cooldown_duration,
		interactable,
		func(): interactable.complete_interaction.rpc()
	)
	print("[CooldownTool] Lancé sur : ", interactable.name, " (", data.cooldown_duration, "s)")


func _find_cooldown_interactable(node: Node) -> Node:
	var current = node
	while current != null:
		if current.is_in_group("CooldownInteractable"):
			return current
		current = current.get_parent()
	return null
	
func _fix_mesh_culling(node: Node) -> void:
	if node is MeshInstance3D:
		# Force une AABB géante → le renderer ne culera JAMAIS ce mesh
		node.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
		node.extra_cull_margin = 100.0
		node.ignore_occlusion_culling = true
	for child in node.get_children():
		_fix_mesh_culling(child)
		
@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_equip(scene_path: String, pos_offset: Vector3, rot_offset: Vector3) -> void:
	# Sécurité : Si un objet était déjà présent sur cette marionnette, on le supprime
	if equipped_instance != null:
		equipped_instance.queue_free()
		equipped_instance = null

	# Enregistrement des offsets pour que le _physics_process local prenne le relais
	_current_item_pos_offset = pos_offset
	_current_item_rot_offset = rot_offset

	var scene: PackedScene = load(scene_path)
	if scene == null:
		return

	# Apparition de l'objet chez la marionnette
	equipped_instance = scene.instantiate()
	get_tree().current_scene.add_child(equipped_instance)
	
	# Désactivation des scripts et de la physique de l'objet pour tout le monde (évite les bugs)
	_set_item_physics_mode(equipped_instance, true)
	equipped_instance.set_process(false)
	equipped_instance.set_physics_process(false)
	
	var item_area = equipped_instance.get_node_or_null("Area3D")
	if item_area is Area3D:
		item_area.monitoring = false
		item_area.monitorable = false
		
	_fix_mesh_culling(equipped_instance)
	
	if player_node and player_node.has_method("set_lamp_aiming"):
		var lamp_is_lit: bool = "is_on" in equipped_instance and equipped_instance.is_on
		player_node.set_lamp_aiming(lamp_is_lit)


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_unequip() -> void:
	if equipped_instance != null:
		equipped_instance.queue_free()
		equipped_instance = null
	if player_node and player_node.has_method("set_lamp_aiming"):   # 🆕
		player_node.set_lamp_aiming(false)
		
@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_drop(scene_path: String, position: Vector3, initial_velocity: Vector3, unique_name: String) -> void:
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return

	# Instanciation de l'objet au sol chez TOUT LE MONDE
	var dropped = scene.instantiate()
	
	# 🌟 ON FORCE LE MÊME NOM PARTOUT AVANT LE ADD_CHILD :
	dropped.name = unique_name 
	
	get_tree().current_scene.add_child(dropped)
	
	# Placement initial exact reçu par le réseau
	dropped.global_position = position
	# Réactivation de la physique complète (RigidBody / Collisions)
	_set_item_physics_mode(dropped, false) 
	
	# Si l'objet est un RigidBody3D, on lui donne la force de lancer initiale.
	# Le moteur physique de chaque joueur va ensuite calculer la trajectoire de la chute à l'identique.
	if dropped is RigidBody3D:
		dropped.linear_velocity = initial_velocity
		
	print("[RPC Drop] Objet instancié et synchronisé au sol.")
	
func _equip_clothing(slot: InventorySlots) -> void:
	if not is_multiplayer_authority():
		return
	if slot.is_empty() or player_node == null:
		return

	data = slot.item_data
	if data.item_type != ItemData.ItemType.CLOTHING:
		return

	# On mémorise l'habit déjà porté (s'il y en a un) AVANT de le remplacer
	var previous_data: ItemData = null
	if clothing_slot and not clothing_slot.is_empty():
		previous_data = clothing_slot.item_data

	clothing_slot.set_item(data)   # le nouvel habit prend la place d'équipement
	slot.clear_slot()              # le slot d'origine se vide...
	if previous_data:
		slot.set_item(previous_data)  # ...et récupère l'ancien habit (inversion demandée)

	player_node.equip_clothing(data)
	print("[Habit] Équipé : ", data.item_name)


func _unequip_clothing() -> void:
	if not is_multiplayer_authority():
		return
	if clothing_slot == null or clothing_slot.is_empty():
		return

	data = clothing_slot.item_data

	var free_slot: InventorySlots = null
	for s in inventory_slots:
		if s.is_empty():
			free_slot = s
			break

	clothing_slot.clear_slot()
	if player_node:
		player_node.unequip_clothing()

	if free_slot == null:
		print("[Habit] Inventaire plein, habit jeté au sol : ", data.item_name)
		_drop_on_ground(data)  # 🆕
	else:
		free_slot.set_item(data)
		print("[Habit] Retiré : ", data.item_name)
		
## Bascule l'allumage de la lampe actuellement équipée (si c'en est une).
## Appelée par l'InteractionManager quand on presse "interact" en tenant une lampe.
func toggle_equipped_lamp() -> void:
	if not is_multiplayer_authority():
		return
	if equipped_slot == null or equipped_slot.is_empty():
		return
	if equipped_slot.item_data.item_type != ItemData.ItemType.LAMP:
		return

	_rpc_sync_toggle_lamp.rpc()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_toggle_lamp() -> void:
	var lamp = null

	if equipped_instance and equipped_instance.get_child_count() > 0:
		lamp = equipped_instance.get_child(0)

		if lamp.has_method("toggle_light"):
			lamp.toggle_light()

	if player_node and player_node.has_method("set_lamp_aiming"):
		var lamp_is_lit := false

		if lamp != null:
			lamp_is_lit = lamp.is_on

		player_node.set_lamp_aiming(lamp_is_lit)
	
	
## Jette tous les objets du joueur (grille, main, habit porté) au sol à l'endroit de sa mort.
func drop_all_on_death() -> void:
	await get_tree().process_frame
	if not is_multiplayer_authority():
		return
	if player_node == null:
		return

	var death_position: Vector3 = player_node.global_position

	for slot in inventory_slots:
		if slot.is_empty():
			continue
		_drop_item_at(slot.item_data, death_position)
		slot.clear_slot()

	if equipped_slot != null and not equipped_slot.is_empty():
		_drop_item_at(equipped_slot.item_data, death_position)
	equipped_slot = null
	_rpc_sync_unequip.rpc()

	if clothing_slot != null and not clothing_slot.is_empty():
		_drop_item_at(clothing_slot.item_data, death_position)
		clothing_slot.clear_slot()
	# Remarque : la réapparition visuelle (mesh civil/skin) est gérée par
	# _rpc_sync_death() côté joueur, pour rester bien synchrone avec le ragdoll.


## Variante de _drop_item, avec un léger éparpillement aléatoire autour du point de mort
func _drop_item_at(data: ItemData, center: Vector3) -> void:
	await get_tree().process_frame
	if data == null or data.pickup_scene_path == "":
		return

	# ✅ On détruit l'objet au lieu de le faire tomber si c'est un objet fixe
	if data.stays_on_ground:
		return

	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 1.5
	var drop_position := center + scatter + Vector3.UP * 0.3
	var drop_velocity := Vector3.UP * 1.0 + scatter * 0.5

	var generated_name := "Dropped_" + data.item_id + "_" + str(Time.get_ticks_msec()) + "_" + str(randi())
	_rpc_sync_drop.rpc(data.pickup_scene_path, drop_position, drop_velocity, generated_name)
	print("[Mort] ", data.item_name, " jeté au sol.")

func unequipe_input():
	var slot = equipped_slot
	if slot != null:
		slot_memory = slot
		
	if slot_memory == null:
		return
	slot = slot_memory
	
	
	if slot == equipped_slot:
		_unequip_item()
		return
	_equip_item(slot)



func drop_input():
	var slot = equipped_slot
	if slot == null:
		return
	
	_drop_from_hand(slot)
	
## Vrai si l'objet actuellement équipé est une lampe torche ET qu'elle est allumée.
func is_equipped_lamp_on() -> bool:
	if equipped_slot == null or equipped_slot.is_empty():
		return false
	if equipped_slot.item_data.item_type != ItemData.ItemType.LAMP:
		return false
	if equipped_instance == null or equipped_instance.get_child_count() == 0:
		return false
	var lamp = equipped_instance.get_child(0)
	return lamp.has_method("toggle_light") and "is_on" in lamp and lamp.is_on

# ── LOGIQUE D'ÉCHANGE (DRAG AND DROP) ──────────────────────────────────────────
func _on_slot_dropped(from_slot: InventorySlots, to_slot: InventorySlots) -> void:
	if not is_multiplayer_authority(): return
	
	var was_equipped = false
	var target_re_equip = null
	
	# Si un des objets est actuellement en main, on le déséquipe proprement avant l'échange
	if equipped_slot == from_slot or equipped_slot == to_slot:
		was_equipped = true
		target_re_equip = to_slot if equipped_slot == from_slot else from_slot
		_unequip_item()
		
	# Échange des données
	var temp_data = to_slot.item_data
	
	if from_slot.item_data:
		to_slot.set_item(from_slot.item_data)
	else:
		to_slot.clear_slot()
		
	if temp_data:
		from_slot.set_item(temp_data)
	else:
		from_slot.clear_slot()
		
	# Si on tenait l'objet en main, on rééquipe le nouveau slot où il se trouve
	if was_equipped and target_re_equip and not target_re_equip.is_empty():
		# Ne rééquipe pas si on a échangé un outil contre un habit (on ne tient pas les habits en main)
		if target_re_equip.item_data.item_type != ItemData.ItemType.CLOTHING:
			_equip_item(target_re_equip)

# ── LOGIQUE DE NAVIGATION (MOLETTE ET TOUCHES 1 À 9) ──────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	
	# On ne navigue pas dans la barre d'accès rapide si l'inventaire est ouvert
	if is_inventory_open: return
	
	# Sécurité : on ne change pas d'objet si on porte un gros objet à deux mains
	if player_node and "isCarryingObject" in player_node and player_node.isCarryingObject: return

	# Détection des touches de 1 à 9 (utilisation du physical_keycode pour la compatibilité AZERTY/QWERTY)
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			var index = event.physical_keycode - KEY_1
			if index < inventory_slots.size():
				_switch_to_slot(index)

	# Détection de la molette de la souris
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_slot(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_slot(1)

func _cycle_slot(direction: int) -> void:
	var current_idx = -1
	if equipped_slot:
		current_idx = inventory_slots.find(equipped_slot)
	
	if current_idx == -1:
		current_idx = 0 if direction > 0 else (inventory_slots.size() - 1)
	else:
		current_idx = (current_idx + direction) % inventory_slots.size()
		if current_idx < 0:
			current_idx = inventory_slots.size() - 1
			
	_switch_to_slot(current_idx)

func _switch_to_slot(index: int) -> void:
	var target_slot = inventory_slots[index]
	
	# Si on a déjà ce slot en main, on l'enlève (comme un raccourci pour ranger l'objet)
	if target_slot == equipped_slot:
		_unequip_item()
		return
		
	# Si le joueur change de slot, on déséquipe toujours l'ancien objet en premier
	if equipped_slot:
		_unequip_item()
		
	# On équipe le nouveau slot s'il contient quelque chose
	if not target_slot.is_empty():
		# On ignore volontairement les habits, car ils s'équipent sur le corps, pas dans la main
		if target_slot.item_data.item_type != ItemData.ItemType.CLOTHING:
			_equip_item(target_slot)
