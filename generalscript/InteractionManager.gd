extends Node

@onready var raycast: RayCast3D = $"../CameraPivot/PhysicsRayCast"
@onready var inventory: InventoryController = $"../InventoryController/CanvasLayer/InventoryUI"
@onready var player: CharacterBody3D = $".."

var _nearby_climb_zone: Node = null
const INTERACT_DISTANCE: float = 2.5

var _pickup_timer: float = 0.0
var _pickup_delay: float = 0.3
var _pending_pickup: Node = null
var _is_picking_up: bool = false

# ── Référence à l'indicateur ───────────────────────────────────────────────────
var _indicator: InteractionIndicator = null

func _ready() -> void:
	# 🔒 SÉCURITÉ RÉSEAU : Seul le joueur local doit exécuter la détection
	if not is_multiplayer_authority():
		set_process(false)
		set_process_input(false)
		return

	if not raycast:
		push_error("InteractionManager : PhysicsRayCast introuvable !")
	if not inventory:
		push_error("InteractionManager : InventoryController introuvable !")
		
	# 🔍 RECHERCHE DE L'INDICATEUR D'INTERACTION
	# Stratégie 1 : Recherche dans les enfants du Joueur (Architecture recommandée)
	_indicator = player.get_node_or_null("InteractionIndicator")
	
	# Stratégie 2 : Repli vers la scène principale si non trouvé chez le joueur
	if _indicator == null:
		_indicator = get_tree().current_scene.get_node_or_null("InteractionIndicator")
		
	if _indicator == null:
		push_warning("InteractionManager : InteractionIndicator introuvable dans l'arbre !")

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if _is_picking_up:
		_pickup_timer += delta
		if _pickup_timer >= _pickup_delay:
			_finish_pickup()

	_update_indicator()

## Appelée par l'InventoryController en cas d'erreur/refus d'outil
func trigger_indicator_shake() -> void:
	if _indicator:
		_indicator.shake()

# ── Gestion du Raycast et mise à jour visuelle ───────────────────────────────
func _update_indicator() -> void:
	if _indicator == null or not raycast:
		return

	raycast.force_raycast_update()

	# Si le raycast ne touche rien, on cache
	if not raycast.is_colliding():
		_indicator.hide_indicator()
		return

	# Si la cible est trop lointaine, on cache
	var hit_point: Vector3 = raycast.get_collision_point()
	if player.global_position.distance_to(hit_point) > INTERACT_DISTANCE:
		_indicator.hide_indicator()
		return

	var collider: Node = raycast.get_collider()
	var interactable: Node = _get_interactable_node(collider)

	# Si c'est un objet interactif valide, on affiche l'indicateur dessus
	if interactable:
		# 🆕 AJOUT : On cache l'indicateur si c'est un Grabbable déjà tenu en main
		if interactable.has_method("is_held") and interactable.is_held():
			_indicator.hide_indicator()
		else:
			# (Rappel de la correction précédente : on cible bien le collider)
			_indicator.show_for(collider)
	else:
		_indicator.hide_indicator()

## Identifie l'objet interactif à partir du collider touché
func _get_interactable_node(collider: Node) -> Node:
	if collider == null:
		return null
	
	var climber = _find_in_group(collider, "Climber")
	if climber: return climber
	
	var grabbable = _find_in_group(collider, "Grabbable")
	if grabbable: return grabbable
	
	var pickup = _find_in_group(collider, "Pickup")
	if pickup: return pickup

	var door = _find_in_group(collider, "Door")
	if door: return door
	
	var oxygen_tank = _find_in_group(collider, "OxygenTank")   # 🆕
	if oxygen_tank: return oxygen_tank

	var tool_target = _find_with_method(collider, "try_interact_with_tool")
	if tool_target: return tool_target

	var cooldown = _find_in_group(collider, "CooldownInteractable")
	if cooldown: return cooldown

	return null

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	if player.is_swimming and _nearby_climb_zone != null:
		player.start_climb_out(_nearby_climb_zone.get_exit_position())
		return
	
	if inventory.is_equipped_lamp_on():
		inventory.unequipe_input()
		return
	
	if inventory.equipped_slot and not inventory.equipped_slot.is_empty():
		if inventory.equipped_slot.item_data.item_type == ItemData.ItemType.LAMP:
			inventory.toggle_equipped_lamp()
			return
	
	if _is_picking_up: 
		return
	if not raycast or not raycast.is_colliding():
		return
	var hit_point: Vector3 = raycast.get_collision_point()
	if player.global_position.distance_to(hit_point) > INTERACT_DISTANCE:
		return

	var collider: Node = raycast.get_collider()
	
	# Vérification rapide de l'outil équipé (Videur)
	var current_item_id = ""
	if inventory.equipped_slot and not inventory.equipped_slot.is_empty():
		current_item_id = inventory.equipped_slot.item_data.item_id
		
	if is_wrong_tool(collider, current_item_id):
		return
	
	var pickup_root = _find_in_group(collider, "Pickup")
	if pickup_root:
		_start_pickup(pickup_root)
		return

	if collider.is_in_group("Door"):
		_handle_door(collider)
		return
	var oxygen_tank_root = _find_in_group(collider, "OxygenTank")   # 🆕
	if oxygen_tank_root:
		_handle_oxygen_tank(oxygen_tank_root)
		return

func _start_pickup(pickup_node: Node) -> void:
	var marker: Marker3D = pickup_node.get_node_or_null("container_of_markers/marker_node")
	if marker == null:
		var pickup_path: NodePath = pickup_node.get_path()   # 🆕 capturé AVANT get_picked_up(), qui peut libérer le nœud
		var data: ItemData = pickup_node.get_picked_up()
		if data:
			inventory.add_item(data)
			if not data.stays_on_ground:   # 🆕
				_despawn_pickup.rpc(pickup_path)
		return

	player.activate_pickup_hand_ik(marker)
	_pending_pickup = pickup_node
	_pickup_timer = 0.0
	_is_picking_up = true
	

func _finish_pickup() -> void:
	_is_picking_up = false
	_pickup_timer = 0.0
	player.deactivate_pickup_hand_ik()

	if _pending_pickup == null or not is_instance_valid(_pending_pickup):
		_pending_pickup = null
		return

	if not _pending_pickup.has_method("get_picked_up"):
		_pending_pickup = null
		return
	
	var pickup_path: NodePath = _pending_pickup.get_path()
	var data: ItemData = _pending_pickup.get_picked_up()
	_pending_pickup = null

	if data == null:
		return

	inventory.add_item(data)
	if not data.stays_on_ground:   # 🆕
		_despawn_pickup.rpc(pickup_path)

	if _indicator:
		_indicator.hide_indicator()

	var slot = inventory.get_slot_with_item(data.item_id)
	if slot and data.item_type != ItemData.ItemType.CLOTHING:
		inventory.call_deferred("_equip_item", slot)

@rpc("authority", "call_local", "reliable")
func _despawn_pickup(path: NodePath) -> void:
	var node := get_node_or_null(path)
	if node:
		node.queue_free()

func _handle_door(door: Node) -> void:
	if not ("is_locked" in door) or not door.is_locked:
		return
	var required_id: String = door.door_id
	if inventory.has_item(required_id):
		if door.try_unlock(required_id):
			if _indicator:
				_indicator.hide_indicator()
	else:
		if _indicator:
			_indicator.shake()
			
func _handle_oxygen_tank(tank: Node) -> void:
	if not tank.has_method("try_use"):
		return
	if tank.try_use(player):
		if _indicator:
			_indicator.hide_indicator()
	else:
		if _indicator:
			_indicator.shake()   # Encore en recharge

func _find_in_group(node: Node, group: String) -> Node:
	var current = node
	while current != null:
		if current.is_in_group(group):
			return current
		current = current.get_parent()
	return null

func _find_with_method(node: Node, method_name: String) -> Node:
	var current = node
	while current != null:
		if current.has_method(method_name):
			return current
		current = current.get_parent()
	return null

func register_climb_zone(zone: Node) -> void:
	_nearby_climb_zone = zone

func unregister_climb_zone(zone: Node) -> void:
	if _nearby_climb_zone == zone:
		_nearby_climb_zone = null
		
func is_wrong_tool(collider: Node, equipped_item_id: String) -> bool:
	var interactable = _get_interactable_node(collider)
	if not interactable:
		return false
		
	var required_id: String = ""
	if "tool_required_id" in interactable:
		required_id = interactable.tool_required_id
	elif "door_id" in interactable:
		required_id = interactable.door_id
		
	if required_id != "" and required_id != equipped_item_id:
		trigger_indicator_shake()
		return true
		
	return false
