extends Control

func _ready() -> void:
	$pause_menu.visible = false
	$settings.visible = false
	#$controls.visible = false
	
	# ✅ Connecter le signal de fermeture des settings
	if $settings.has_signal("closed"):
		$settings.closed.connect(close_menus)

func open_settings():
	if not is_multiplayer_authority():
		return
	$pause_menu.visible = false
	$settings.visible = true

#func open_controls():
#	$pause_menu.visible = false
#	$controls.visible = true

func close_menus():
	if not is_multiplayer_authority():
		return
	$pause_menu.visible = true
	$settings.visible = false
	#$controls.visible = false

func resume_game():
	if not is_multiplayer_authority():
		return
	
	get_tree().paused = false
	$pause_menu.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func quit_game():
	if not is_multiplayer_authority():
		return
		
	# On s'assure que le menu existe toujours avant de l'appeler
	if is_instance_valid(GameMenu.instance):
		GameMenu.instance.leave_multiplayer_game()
		
	get_tree().quit()

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if Input.is_action_just_pressed("ui_cancel") and !$settings.visible:
		$pause_menu.visible = !$pause_menu.visible
		get_tree().paused = $pause_menu.visible
		if get_tree().paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if !get_tree().paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			$pause_menu.visible = false
#func play_hover() -> void:
#	pass # Replace with function body.

#func main_menu():
#	get_tree().paused = false
#	get_tree().change_scene_to_file("res://scene/ui/main_menu.tscn")
