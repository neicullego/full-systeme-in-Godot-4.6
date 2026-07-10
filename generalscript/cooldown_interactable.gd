class_name CooldownInteractable
extends Node3D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var tool_required_id: String = ""
@export var single_use: bool = true

## Durée de rendu visuel de la jauge (doit correspondre à la durée de votre outil, ex: 3.0)
@export var cooldown_duration: float = 3.0

# ── Signaux ───────────────────────────────────────────────────────────────────
signal interaction_completed(interactable: CooldownInteractable)
signal interaction_cancelled(interactable: CooldownInteractable)

# ── État interne ──────────────────────────────────────────────────────────────
var _already_used: bool = false
var _particles: Array[Node] = []
var _tween: Tween = null

# ── Référence au Sprite 3D local ──────────────────────────────────────────────
@onready var _timer_sprite: Sprite3D = get_node_or_null("TimerSprite3D")

# ── Initialisation ────────────────────────────────────────────────────────────
func _ready() -> void:
	if not is_in_group("CooldownInteractable"):
		add_to_group("CooldownInteractable")

	_find_particles(self)

	if get_node_or_null("marker_node") == null:
		push_warning("[CooldownInteractable] '%s' n'a pas de nœud 'marker_node' !" % name)
		
	# Cache la jauge par défaut
	if _timer_sprite:
		_timer_sprite.visible = false

# ── API publique ──────────────────────────────────────────────────────────────

func try_interact(tool_id: String) -> bool:
	if single_use and _already_used:
		print("[CooldownInteractable] '%s' déjà utilisé." % name)
		return false
	if tool_required_id != "" and tool_id != tool_required_id:
		print("[CooldownInteractable] Mauvais outil. Requis : '%s', Reçu : '%s'" % [tool_required_id, tool_id])
		return false
	return true

## Appelée au début de l'interaction
func start_interaction() -> void:
	_set_particles_emitting(true)
	print("[CooldownInteractable] Interaction démarrée sur : ", name)
	
	# Gestion de l'animation de la jauge de progression
	if _timer_sprite:
		_timer_sprite.visible = true
		
		# On réinitialise le Tween s'il tournait déjà
		if _tween and _tween.is_valid():
			_tween.kill()
			
		_tween = create_tween()
		# On anime la propriété "progress" du ShaderMaterial de 0.0 à 1.0
		if _timer_sprite.material_override is ShaderMaterial:
			_tween.tween_property(_timer_sprite.material_override, "shader_parameter/progress", 1.0, cooldown_duration).from(0.0)

## Appelée à la fin du cooldown
@rpc("any_peer", "call_local", "reliable")
func complete_interaction() -> void:
	_set_particles_emitting(false)
	
	if _tween and _tween.is_valid():
		_tween.kill()
	if _timer_sprite:
		_timer_sprite.visible = false
		
	if single_use:
		_already_used = true
	emit_signal("interaction_completed", self)
	print("[CooldownInteractable] Interaction terminée sur : ", name)

## Appelée si l'interaction est annulée
func cancel_interaction() -> void:
	_set_particles_emitting(false)
	
	if _tween and _tween.is_valid():
		_tween.kill()
	if _timer_sprite:
		_timer_sprite.visible = false
		
	emit_signal("interaction_cancelled", self)
	print("[CooldownInteractable] Interaction annulée sur : ", name)

func get_hand_marker() -> Marker3D:
	return get_node_or_null("marker_node") as Marker3D

# ── Gestion des particules ────────────────────────────────────────────────────
func _find_particles(node: Node) -> void:
	for child in node.get_children():
		if child is GPUParticles3D or child is CPUParticles3D:
			_particles.append(child)
			child.emitting = false
		_find_particles(child)

func _set_particles_emitting(active: bool) -> void:
	for p in _particles:
		if is_instance_valid(p):
			p.emitting = active
			
