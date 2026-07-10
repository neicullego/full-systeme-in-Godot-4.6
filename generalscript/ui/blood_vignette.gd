extends ColorRect

func _ready() -> void:
	# On ajoute automatiquement ce nœud au groupe "effects"
	add_to_group("effects")
	
	# On s'assure que l'effet est totalement invisible au départ
	(material as ShaderMaterial).set_shader_parameter("opacity", 0.0)

func flash_damage() -> void:
	var shader_material = material as ShaderMaterial
	if not shader_material:
		return
		
	# On crée un Tween pour animer l'opacité du shader
	var tween = create_tween()
	
	# 1. Apparition flash rapide (0.05 seconde) jusqu'à une opacité max (ex: 0.85)
	tween.tween_property(shader_material, "shader_parameter/opacity", 0.85, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. Disparition progressive (0.4 seconde) vers 0.0
	tween.tween_property(shader_material, "shader_parameter/opacity", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
