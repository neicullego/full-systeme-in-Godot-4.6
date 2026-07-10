class_name SkinSelector
extends Control

signal skin_chosen(skin_id: String)

@onready var skin_grid: GridContainer = %SkinGrid
var skin_button_prefab: PackedScene = load("res://scene/ui/skin_button.tscn")

var _buttons: Dictionary = {}   # skin_id -> Button
var selected_skin_id: String = ""

func _ready() -> void:
	for skin_data in SkinRegistry.available_skins:
		var btn := skin_button_prefab.instantiate()
		skin_grid.add_child(btn)
		btn.setup(skin_data)
		btn.pressed.connect(_on_skin_button_pressed.bind(skin_data.skin_id))
		_buttons[skin_data.skin_id] = btn

	# 🆕 Pré-sélection VISUELLE uniquement — pas d'émission de signal, on attend un vrai clic
	if SkinRegistry.available_skins.size() > 0:
		selected_skin_id = SkinRegistry.available_skins[0].skin_id
		_buttons[selected_skin_id].button_pressed = true


func _on_skin_button_pressed(skin_id: String) -> void:
	selected_skin_id = skin_id
	for id in _buttons:
		_buttons[id].button_pressed = (id == skin_id)
	skin_chosen.emit(skin_id)
