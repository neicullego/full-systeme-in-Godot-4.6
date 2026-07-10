extends GPUParticles3D

## Glissez-déposez votre nœud Océan (qui possède le script Water.gd) ici
@export var water_node: Node3D 

var bubble_material: ShaderMaterial

func _ready() -> void:
	# Récupération automatique du shader de la bulle
	if draw_pass_1 and draw_pass_1 is SphereMesh:
		bubble_material = draw_pass_1.material as ShaderMaterial
	
	# Synchronisation unique des paramètres structurels du shader de l'eau
	if water_node and bubble_material and water_node.material_template:
		var w_mat = water_node.material_template
		bubble_material.set_shader_parameter("wave", w_mat.get_shader_parameter("wave"))
		bubble_material.set_shader_parameter("noise_scale", w_mat.get_shader_parameter("noise_scale"))
		bubble_material.set_shader_parameter("height_scale", w_mat.get_shader_parameter("height_scale"))
		bubble_material.set_shader_parameter("wave_speed", w_mat.get_shader_parameter("wave_speed"))

func _process(_delta: float) -> void:
	# Mise à jour à chaque frame de la position de l'eau et du temps
	if water_node and bubble_material:
		bubble_material.set_shader_parameter("water_base_y", water_node.global_position.y)
		bubble_material.set_shader_parameter("wave_time", water_node.time)
