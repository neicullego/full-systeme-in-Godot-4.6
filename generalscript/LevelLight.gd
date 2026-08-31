# LevelLight.gd
# Point lumineux du niveau (applique/plafonnier). À attacher à la racine de la
# scène "light" (Cube + StaticBody3D/CollisionShape3D pour le boîtier, Cube_003
# pour l'ampoule émissive, SpotLight3D pour l'éclairage réel).
class_name LevelLight
extends Node3D

@export var spotlight: SpotLight3D
@export var emissive_material: StandardMaterial3D
@export var default_on: bool = false

var is_on: bool = false


func _ready() -> void:
	if spotlight == null:
		push_warning("LevelLight '%s' : aucun OmniLight3D assigné !" % name)
	if emissive_material == null:
		push_warning("LevelLight '%s' : aucun matériau émissif assigné !" % name)
	set_light_state(default_on)


func set_light_state(on: bool) -> void:
	is_on = on
	if spotlight:
		spotlight.visible = is_on
	if emissive_material:
		emissive_material.emission_enabled = is_on


func turn_on() -> void:
	set_light_state(true)


func turn_off() -> void:
	set_light_state(false)
