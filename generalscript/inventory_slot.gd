# InventorySlots.gd
extends Control
class_name InventorySlots

var item_data: ItemData = null

@onready var item_icon: TextureRect = $TextureRect

# Signal émis vers l'InventoryController quand on clique sur ce slot
signal slot_left_clicked(slot: InventorySlots)
signal slot_right_clicked(slot: InventorySlots)

func _ready() -> void:
	# Active la détection des clics souris sur ce Control
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
	# Si pas d'image assignée, on met une couleur de placeholder
	elif item_icon:
		item_icon.texture = null

func clear_slot() -> void:
	item_data = null
	if item_icon:
		item_icon.texture = null

func is_empty() -> bool:
	return item_data == null
