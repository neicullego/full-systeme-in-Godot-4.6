# InteractionIndicator.gd
extends Node3D
class_name InteractionIndicator

@onready var sprite: Sprite3D = $Sprite3D

@export var height_offset: float = 0.0  # Hauteur au-dessus de l'objet ciblé

var _is_shaking: bool = false
var _shake_tween: Tween = null
var _current_target: Node = null

func _ready() -> void:
	top_level = true
	visible = false
	# 🔒 SÉCURITÉ MULTIJOUEUR : Si cet indicateur appartient à la marionnette 
	# d'un autre joueur, on coupe son traitement pour ne pas polluer l'écran local.
	if get_parent() is CharacterBody3D and not get_parent().is_multiplayer_authority():
		set_process(false)
		return

func _process(_delta: float) -> void:
	if not visible:
		return
		
	# ✅ ANTI-CRASH : Si l'objet ciblé est détruit ou ramassé par quelqu'un d'autre
	if _current_target == null or not is_instance_valid(_current_target):
		hide_indicator()
		return
		
	# L'indicateur suit la position globale de la cible
	global_position = _current_target.global_position + Vector3.UP * height_offset

## Active et affiche l'indicateur au-dessus d'une cible
func show_for(target_node: Node) -> void:
	if target_node == null:
		return
		
	_current_target = target_node
	global_position = target_node.global_position + Vector3.UP * height_offset
	visible = true
	if sprite:
		sprite.visible = true

## Masque l'indicateur
func hide_indicator() -> void:
	_current_target = null
	visible = false
	_stop_shake()
	if sprite:
		sprite.position = Vector3.ZERO
		sprite.visible = false

## Animation de vibration (ex: mauvaise clé, mauvais outil détecté par l'inventaire)
func shake() -> void:
	if _is_shaking:
		return
	_is_shaking = true
	_stop_shake()

	_shake_tween = create_tween()
	_shake_tween.set_loops(4)
	_shake_tween.tween_property(sprite, "position:x", -0.08, 0.04)
	_shake_tween.tween_property(sprite, "position:x",  0.08, 0.08)
	_shake_tween.tween_property(sprite, "position:x",  0.0,  0.04)
	_shake_tween.finished.connect(_on_shake_finished, CONNECT_ONE_SHOT)

func _on_shake_finished() -> void:
	_is_shaking = false
	if sprite:
		sprite.position = Vector3.ZERO

func _stop_shake() -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_is_shaking = false
	if sprite:
		sprite.position = Vector3.ZERO
