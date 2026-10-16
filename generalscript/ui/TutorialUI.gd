extends Control
class_name TutorialUI

@onready var label: Label = $Panel/Label
@onready var icon_rect: TextureRect = $Panel/TextureRect

var current_action_required: String = ""

func _ready() -> void:
	visible = false

## Affiche le message de tutoriel
func show_tutorial(text: String, icon: Texture2D = null, action_name: String = "", auto_hide_delay: float = 0.0) -> void:
	label.text = text
	current_action_required = action_name
	
	if icon:
		icon_rect.texture = icon
		icon_rect.show()
	else:
		icon_rect.hide()

	visible = true

	if auto_hide_delay > 0.0:
		get_tree().create_timer(auto_hide_delay).timeout.connect(hide_tutorial)

## Masque le tutoriel
func hide_tutorial() -> void:
	visible = false
	current_action_required = ""

func _input(event: InputEvent) -> void:
	if not visible or current_action_required.is_empty():
		return

	# Si le joueur appuie sur l'action demandée (ex: "interact"), le tutoriel se ferme
	if event.is_action_pressed(current_action_required):
		hide_tutorial()
