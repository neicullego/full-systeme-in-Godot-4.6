extends Button
@onready var preview: TextureRect = $VBoxContainer/Preview
@onready var name_label: Label = $VBoxContainer/NameLabel

func setup(skin_data: SkinData) -> void:
	if preview:
		preview.texture = skin_data.preview_image
	if name_label:
		name_label.text = skin_data.skin_name
