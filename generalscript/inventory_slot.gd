extends Control
class_name InventorySlots

var item_data: ItemData = null

@onready var item_icon: TextureRect = $TextureRect

signal slot_left_clicked(slot: InventorySlots)
signal slot_right_clicked(slot: InventorySlots)

# 🆕 Nouveau signal pour l'échange de slots
signal slot_dropped(from_slot: InventorySlots, to_slot: InventorySlots)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if item_data == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			emit_signal("slot_left_clicked", self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			emit_signal("slot_right_clicked", self)

func set_item(data: ItemData) -> void:
	item_data = data
	if item_icon and data.item_image:
		item_icon.texture = data.item_image
	elif item_icon:
		item_icon.texture = null

func clear_slot() -> void:
	item_data = null
	if item_icon:
		item_icon.texture = null

func is_empty() -> bool:
	return item_data == null

# ── NOUVEAU : SYSTÈME DE GLISSER-DÉPOSER NATTIF DE GODOT ──

func _get_drag_data(at_position: Vector2) -> Variant:
	if is_empty():
		return null
	
	# Crée un aperçu visuel semi-transparent qui suit la souris
	var preview = TextureRect.new()
	preview.texture = item_icon.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = size
	preview.modulate.a = 0.6
	
	var control = Control.new()
	control.add_child(preview)
	preview.position = -0.5 * size # Centre l'image sur le curseur
	
	set_drag_preview(control)
	return self

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# On accepte le drop seulement si ça vient d'un autre InventorySlots
	return data is InventorySlots and data != self

func _drop_data(at_position: Vector2, data: Variant) -> void:
	# On demande au contrôleur principal d'effectuer l'échange
	emit_signal("slot_dropped", data, self)
