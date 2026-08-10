# DocumentUI.gd
extends Control
class_name DocumentUI

@onready var document_image: TextureRect = $ColorRect/MarginContainer/DocumentImage
@onready var document_text: Label = $ColorRect/MarginContainer/DocumentImage/DocumentText
var is_open = false

func _ready() -> void:
	visible = false
	# Permet de capter Échap pour fermer
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_open = true

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		if not is_open :
			await get_tree().process_frame
			close()

## Ouvre le document avec l'image et le texte de l'ItemData
func open(data: ItemData) -> void:
	if not is_open :
		return
	else:
		is_open = false
		if data.document_image:
			document_image.texture = data.document_image
			document_image.visible = true
		else:
			document_image.visible = false

		document_text.text = data.document_text
		visible = true
		# Libère la souris pour éventuellement scroller le texte
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("[Document] Ouverture : ", data.item_name)
	

## Ferme le document
func close() -> void:
	
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[Document] Fermé.")
	await get_tree().process_frame
	is_open = true
