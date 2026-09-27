extends CanvasLayer

signal closed

var player_ref
var environment: Environment
@onready var water_ref = get_tree().get_first_node_in_group("water")


# Chemin du fichier de sauvegarde
const SETTINGS_FILE = "user://settings.cfg"

# Résolutions possibles pour l'atlas d'ombres (index du OptionButton -> taille en pixels)
const SHADOW_SIZES = [1024, 2048, 4096, 8192]

# Lumières directionnelles (soleil) trouvées dans la scène, pour la distance des ombres
var sun_lights: Array = []

# Variables pour stocker les paramètres actuels
var current_settings = {
	"shadow_size": 1,          # 0=1024, 1=2048, 2=4096, 3=8192
	"shadow_distance": 100.0,  # en mètres
	"glow": false,
	"ssil": false,
	"ssao": false,
	"ssr": false,
	"vsync": true,
	"sdfgi": false,
	"fps_cap": 1,
	"aa": 0,
	"scale_3d": 1.0,
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"music_volume": 1.0,
	"look_speed": 0.2,
	"window_mode": 1,
	"shadows": 3,
	"ao_quality": 2,
	"mic_enabled": true,
	"proximity_chat_volume": 1.0,
	"water_render_distance": 4
}

func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	get_viewport().use_taa = false
	var is_first_launch = load_settings()
	
	# --- AJOUT ICI : première connexion -> détection auto du matériel ---
	# Pas de fichier de sauvegarde trouvé = on règle les graphismes selon
	# la config détectée plutôt que de garder les valeurs par défaut "à l'aveugle".
	if is_first_launch:
		apply_recommended_graphics_settings()
	# ---------------------------------------------------------------------
	
	# --- AJOUT ICI : Détection Mobile ---
	# Si on est sur mobile, on écrase les paramètres chargés avant de les appliquer
	if OS.has_feature("mobile"):
		apply_mobile_overrides()
	# ------------------------------------
	
	# Chercher WorldEnvironment dans toute la scène, quel que soit son nom
	var world_env = get_tree().root.find_child("WorldEnvironment", true, false)
	if world_env:
		environment = world_env.environment

	# Chercher le joueur local dans toute la scène
	var player_node = get_tree().root.find_child("Players", true, false)
	if player_node:
		for p in player_node.get_children():
			if p.is_multiplayer_authority():
				player_ref = p
				break
	# Fallback solo
	if player_ref == null:
		var solo = get_tree().get_first_node_in_group("player")
		if solo:
			player_ref = solo
	
	# ✅ Maintenant apply fonctionne car environment n'est plus null
	$HBoxContainer/Container/video.visible = true
	$HBoxContainer/Container/audio.visible = false
	$HBoxContainer/Container/control.visible = false
	apply_all_settings()
	await get_tree().process_frame
	update_ui_controls()
	


func save_settings():
	var config = ConfigFile.new()
	
	# Sauvegarder tous les paramètres
	for key in current_settings.keys():
		config.set_value("settings", key, current_settings[key])
	
	# Sauvegarder dans le fichier
	var err = config.save(SETTINGS_FILE)
	if err != OK:
		print("Erreur lors de la sauvegarde des paramètres: ", err)
	else:
		print("Paramètres sauvegardés avec succès")

## Retourne true si c'est la toute première connexion (aucun fichier de
## sauvegarde trouvé), false si des réglages existants ont été chargés.
func load_settings() -> bool:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	
	if err != OK:
		print("Aucun fichier de paramètres trouvé, utilisation des valeurs par défaut")
		return true
	
	# Charger tous les paramètres
	for key in current_settings.keys():
		if config.has_section_key("settings", key):
			current_settings[key] = config.get_value("settings", key)
	
	print("Paramètres chargés avec succès")
	return false

func apply_all_settings():
	# On passe 'true' en deuxième argument pour éviter les écritures multiples
	set_glow(current_settings.glow, true)
	set_ssil(current_settings.ssil, true)
	set_ssao(current_settings.ssao, true)
	set_ssr(current_settings.ssr, true)
	set_vsync(current_settings.vsync, true)
	set_fps_cap(current_settings.fps_cap, true)
	scale_3d(current_settings.scale_3d, true) # N'oublie pas d'ajouter l'argument à scale_3d aussi !
	set_master_volume(current_settings.master_volume, true)
	set_sfx_volume(current_settings.sfx_volume, true)
	set_music_volume(current_settings.music_volume, true)
	set_look_speed(current_settings.look_speed, true)
	set_window_mode(current_settings.window_mode, true)
	set_shadows(current_settings.shadows, true)
	set_ao_quality(current_settings.ao_quality, true)
	set_sdfgi(current_settings.sdfgi, true)
	set_mic_enabled(current_settings.mic_enabled, true)
	set_proximity_chat_volume(current_settings.proximity_chat_volume, true)
	set_water_render_distance(current_settings.water_render_distance, true)
	set_shadow_size(current_settings.shadow_size, true)
	set_shadow_distance(current_settings.shadow_distance, true)
	
	# ✅ UNE SEULE écriture ici. Beaucoup plus sain pour le téléphone.
	save_settings()

func update_ui_controls():
	# Attendre une frame pour s'assurer que tous les nœuds UI sont prêts
	await get_tree().process_frame
	
	if has_node("HBoxContainer/Container/video/shadow_size_button"):
		$HBoxContainer/Container/video/shadow_size_button.selected = current_settings.shadow_size
	if has_node("HBoxContainer/Container/video/shadow_distance_slider"):
		$HBoxContainer/Container/video/shadow_distance_slider.value = current_settings.shadow_distance

	if has_node("HBoxContainer/Container/video/glow_button"):
		$HBoxContainer/Container/video/glow_button.button_pressed = current_settings.glow
	if has_node("HBoxContainer/Container/video/vscync_button"):
		$HBoxContainer/Container/video/vscync_button.button_pressed = current_settings.vsync
	if has_node("HBoxContainer/Container/audio/mic_enabled"):
		$HBoxContainer/Container/audio/mic_enabled.button_pressed = current_settings.mic_enabled


	if has_node("HBoxContainer/Container/video/sdfgi_button"):
		$HBoxContainer/Container/video/sdfgi_button.button_pressed = current_settings.sdfgi
	if has_node("HBoxContainer/Container/video/ssao_button"):
		$HBoxContainer/Container/video/ssao_button.button_pressed = current_settings.ssao
	if has_node("HBoxContainer/Container/video/ssr_button"):
		$HBoxContainer/Container/video/ssr_button.button_pressed = current_settings.ssr
	if has_node("HBoxContainer/Container/video/ssil_button"):
		$HBoxContainer/Container/video/ssil_button.button_pressed = current_settings.ssil

	# /!\ N'oublie pas de faire la même chose (mettre le bon chemin) pour tes sliders et menus déroulants en dessous ! /!\
	
	# OPTION BUTTONS (Dropdowns) - À adapter avec tes vrais chemins
	if has_node("HBoxContainer/Container/video/fps_button"):
		$HBoxContainer/Container/video/fps_button.selected = current_settings.fps_cap
	if has_node("HBoxContainer/Container/video/window_mode"):
		$HBoxContainer/Container/video/window_mode.selected = current_settings.window_mode
	if has_node("HBoxContainer/Container/video/shadow_button"):
		$HBoxContainer/Container/video/shadow_button.selected = current_settings.shadows
	if has_node("HBoxContainer/Container/video/ao_quality_button"):
		$HBoxContainer/Container/video/ao_quality_button.selected = current_settings.ao_quality
	
	# SLIDERS - À adapter avec tes vrais chemins
	if has_node("HBoxContainer/Container/video/scaling_slider"):
		$HBoxContainer/Container/video/scaling_slider.value = current_settings.scale_3d
	if has_node("HBoxContainer/Container/audio/volume_slider"):
		$HBoxContainer/Container/audio/volume_slider.value = current_settings.master_volume
	if has_node("HBoxContainer/Container/audio/sfx_slider"):
		$HBoxContainer/Container/audio/sfx_slider.value = current_settings.sfx_volume
	if has_node("HBoxContainer/Container/audio/music_slider"):
		$HBoxContainer/Container/audio/music_slider.value = current_settings.music_volume
	if has_node("HBoxContainer/Container/control/look_slider"):
		$HBoxContainer/Container/control/look_slider.value = current_settings.look_speed
	if has_node("HBoxContainer/Container/audio/proximity_chat_volume_slider"):
		$HBoxContainer/Container/audio/proximity_chat_volume_slider.value = current_settings.proximity_chat_volume
	if has_node("HBoxContainer/Container/video/Slider_render_distance"):
		$HBoxContainer/Container/video/Slider_render_distance.value = current_settings.water_render_distance
		
	print("UI synchronisée avec les paramètres sauvegardés")

# ========== FONCTIONS MODIFIÉES POUR SAUVEGARDER ==========

		
func set_glow(toggled, is_loading = false):
	current_settings.glow = toggled
	if environment != null:
		environment.glow_enabled = toggled
	if not is_loading:
		save_settings()
		
func set_ssil(toggled, is_loading = false):
	current_settings.ssil = toggled
	if environment != null:
		environment.ssil_enabled = toggled
	if not is_loading:
		save_settings()
	
func set_ssao(toggled, is_loading = false):
	current_settings.ssao = toggled
	if environment != null:
		environment.ssao_enabled = toggled
	if not is_loading:
		save_settings()
	
func set_ssr(toggled, is_loading = false):
	current_settings.ssr = toggled
	if environment != null:
		environment.ssr_enabled = toggled
	if not is_loading:
		save_settings()
		
func set_vsync(toggle, is_loading = false):
	current_settings.vsync = toggle
	if !toggle:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif toggle:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not is_loading:
		save_settings()
	
func set_sdfgi(toggled, is_loading = false):
	current_settings.sdfgi = toggled
	if environment != null:
		environment.sdfgi_enabled = toggled
	if not is_loading:
		save_settings()

		
func set_fps_cap(index, is_loading = false):
	current_settings.fps_cap = index
	if index == 0:
		Engine.max_fps = 30
	elif index == 1:
		Engine.max_fps = 60
	elif index == 2:
		Engine.max_fps = 0
	if not is_loading:
		save_settings()


func scale_3d(value, is_loading = false):
	current_settings.scale_3d = value
	get_viewport().scaling_3d_scale = value
	if not is_loading:
		save_settings()
	
func set_master_volume(value, is_loading = false):
	current_settings.master_volume = value
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
	if not is_loading:
		save_settings()
	
func set_sfx_volume(value, is_loading = false):
	current_settings.sfx_volume = value
	#AudioServer.set_bus_volume_db(1, linear_to_db(value))
	if not is_loading:
		save_settings()
	
func set_music_volume(value, is_loading = false):
	current_settings.music_volume = value
	#AudioServer.set_bus_volume_db(2, linear_to_db(value))
	if not is_loading:
		save_settings()
	
func set_look_speed(value, is_loading = false):
	current_settings.look_speed = value
	if player_ref != null:
		player_ref.sensitivity = value
	if not is_loading:
		save_settings()

func set_window_mode(index, is_loading = false):
	current_settings.window_mode = index
	if index == 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	elif index == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif index == 2:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	if not is_loading:
		save_settings()
		
func set_shadows(index, is_loading = false):
	current_settings.shadows = index
	if index == 0:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	elif index == 1:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	elif index == 2:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	elif index == 3:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	elif index == 4:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	elif index == 5:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	if not is_loading:
		save_settings()


## Qualité de l'occlusion ambiante (SSAO) et de l'éclairage indirect en
## écran-espace (SSIL), pilotée globalement comme les ombres juste au-dessus.
## index : 0=Très faible, 1=Faible, 2=Moyen, 3=Élevé, 4=Ultra
func set_ao_quality(index, is_loading = false):
	current_settings.ao_quality = index
	var quality_levels = [
		RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		RenderingServer.ENV_SSAO_QUALITY_HIGH,
		RenderingServer.ENV_SSAO_QUALITY_ULTRA,
	]
	var ssil_quality_levels = [
		RenderingServer.ENV_SSIL_QUALITY_VERY_LOW,
		RenderingServer.ENV_SSIL_QUALITY_LOW,
		RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		RenderingServer.ENV_SSIL_QUALITY_HIGH,
		RenderingServer.ENV_SSIL_QUALITY_ULTRA,
	]
	var i = clampi(index, 0, quality_levels.size() - 1)
	# Demi-résolution sur les deux réglages les plus bas : nettement plus rapide.
	var half_size = i <= 1

	RenderingServer.environment_set_ssao_quality(quality_levels[i], half_size, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(ssil_quality_levels[i], half_size, 0.5, 2, 50.0, 300.0)

	if not is_loading:
		save_settings()


# Fonction optionnelle pour réinitialiser aux valeurs par défaut
func reset_to_defaults():
	current_settings = {
		"shadow_size": 1,          # 0=1024, 1=2048, 2=4096, 3=8192
		"shadow_distance": 100.0,  # en mètres
		"glow": false,
		"ssil": false,
		"ssao": false,
		"ssr": false,
		"vsync": true,
		"sdfgi": false,
		"fps_cap": 1,
		"aa": 0,
		"scale_3d": 1.0,
		"master_volume": 1.0,
		"sfx_volume": 1.0,
		"music_volume": 1.0,
		"look_speed": 0.2,
		"window_mode": 1,
		"shadows": 3,
		"ao_quality": 2,
		"mic_enabled": true,
		"proximity_chat_volume": 1.0,
		"water_render_distance": 4
	}
	
	# --- AJOUT ICI ---
	if OS.has_feature("mobile"):
		apply_mobile_overrides()
	# -----------------
	
	apply_all_settings()
	update_ui_controls()
	save_settings()

# NOUVEAU: Fonction pour brider les graphismes sur mobile
func apply_mobile_overrides():
	# 1. On force les paramètres incompatibles ou trop lourds à 'false'
	current_settings.ssil = false
	current_settings.ssao = false
	current_settings.ssr = false
	current_settings.sdfgi = false
	current_settings.shadow_size = 0
	current_settings.shadow_distance = 40.0
	
	# Optionnel : baisser la qualité des ombres par défaut sur mobile
	# current_settings.shadows = 1 # Soft Very Low
	
	# 2. On cache les boutons pour empêcher le joueur de les activer
	if has_node("ssil_button"):
		$HBoxContainer/Container/video/ssil_button.hide()
	if has_node("ssao_button"):
		$HBoxContainer/Container/video/ssao_button.hide()
	if has_node("ssr_button"):
		$HBoxContainer/Container/video/ssr_button.hide()
	if has_node("sdfgi_button"):
		$HBoxContainer/Container/video/sdfgi_button.hide()
		
	print("📱 Mode Mobile détecté : Effets graphiques lourds désactivés et cachés.")


## Demande à GraphicsAutoConfig (autoload) un palier de réglages basé sur le
## matériel détecté, et l'injecte dans current_settings. N'applique ni ne
## sauvegarde rien lui-même : c'est apply_all_settings() qui s'en charge,
## que ce soit au tout premier lancement (_ready) ou via le bouton manuel.
func apply_recommended_graphics_settings() -> void:
	var tier = GraphicsAutoConfig.detect_hardware_tier()
	var recommended = GraphicsAutoConfig.get_recommended_settings(tier)
	for key in recommended.keys():
		current_settings[key] = recommended[key]
	print("[Settings] Réglages graphiques recommandés appliqués (palier : %s)" % GraphicsAutoConfig.get_tier_label(tier))


## À connecter au signal "pressed" du bouton "Réglages recommandés" dans le menu.
func _on_recommended_settings_button_pressed() -> void:
	apply_recommended_graphics_settings()
	apply_all_settings()
	update_ui_controls()


func _on_close_button_pressed():
	emit_signal("closed")
	
func set_mic_enabled(toggled, is_loading = false):
	current_settings.mic_enabled = toggled
	ProximityChat.mic_enabled = toggled
	if not is_loading:
		save_settings()

func set_proximity_chat_volume(value, is_loading = false):
	current_settings.proximity_chat_volume = value
	ProximityChat.ensure_audio_buses()  # au cas où on ouvre les réglages avant d'être en jeu
	var idx = AudioServer.get_bus_index(ProximityChat.OUTPUT_BUS)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(value))
	if not is_loading:
		save_settings()


func _on_video_button_pressed() -> void:
	$HBoxContainer/Container/control.visible = false
	$HBoxContainer/Container/audio.visible = false
	$HBoxContainer/Container/video.visible = true


func _on_audio_button_pressed() -> void:
	$HBoxContainer/Container/video.visible = false
	$HBoxContainer/Container/control.visible = false
	$HBoxContainer/Container/audio.visible = true


func _on_control_button_pressed() -> void:
	$HBoxContainer/Container/video.visible = false
	$HBoxContainer/Container/audio.visible = false
	$HBoxContainer/Container/control.visible = true


func set_water_render_distance(value, is_loading = false):
	current_settings.water_render_distance = value
	if water_ref != null:
		water_ref.render_distance = value # Modifie la variable du script Water
		water_ref._update_ocean_grid(true) # Force la mise à jour immédiate des chunks
	
	if not is_loading:
		save_settings()
		
## Résolution des ombres. index : 0=1024, 1=2048, 2=4096, 3=8192
func set_shadow_size(index, is_loading = false):
	current_settings.shadow_size = index
	var i = clampi(index, 0, SHADOW_SIZES.size() - 1)
	var atlas_size: int = SHADOW_SIZES[i]

	# Soleil (lumière directionnelle)
	RenderingServer.directional_shadow_atlas_set_size(atlas_size, true)
	# Lampes omni/spot : plafonné à 4096 (8192 est très lourd en VRAM pour ces lumières)
	get_viewport().positional_shadow_atlas_size = mini(atlas_size, 4096)

	if not is_loading:
		save_settings()


## Distance maximale d'affichage des ombres du soleil (en mètres).
func set_shadow_distance(value, is_loading = false):
	current_settings.shadow_distance = value
	if sun_lights.is_empty():
		_refresh_sun_lights()
	for light in sun_lights:
		if is_instance_valid(light):
			light.directional_shadow_max_distance = value
	if not is_loading:
		save_settings()


## Cherche toutes les DirectionalLight3D de la scène (quel que soit leur nom).
## À rappeler si ton soleil est créé/remplacé après le chargement du menu.
func _refresh_sun_lights() -> void:
	sun_lights.clear()
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		sun_lights.append(node)
