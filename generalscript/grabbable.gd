# Grabbable.gd
# Objet déplaçable à deux mains (RigidBody3D). Ajoutez ce nœud au groupe "Grabbable"
# dans l'Inspecteur, et prévoyez deux Marker3D enfants nommés GrabMarkerLeft et
# GrabMarkerRight, à l'endroit où chaque main doit se poser sur l'objet.
class_name Grabbable
extends RigidBody3D

@export var follow_force: float = 40.0        # Force de rappel vers la cible
@export var follow_damping: float = 8.0       # Amortissement (évite les oscillations)
@export var max_follow_speed: float = 8.0     # Vitesse max autorisée pendant le portage
@export var rotation_response: float = 10.0   # Réactivité de la rotation vers l'orientation désirée

var _holder_peer_id: int = 0     # 0 = personne ne porte l'objet
var _pull_target: Vector3 = Vector3.ZERO
var _has_pull_target: bool = false
var _target_basis: Basis


func _ready() -> void:
	if not is_in_group("Grabbable"):
		add_to_group("Grabbable")
	if get_node_or_null("GrabMarkerLeft") == null or get_node_or_null("GrabMarkerRight") == null:
		push_warning("Grabbable '%s' : GrabMarkerLeft et/ou GrabMarkerRight manquant(s) !" % name)
	_target_basis = global_transform.basis


@rpc("any_peer", "call_local", "reliable")
func rpc_request_grab(peer_id: int) -> void:
	# Le premier arrivé garde la main — évite que deux joueurs saisissent en même temps
	if _holder_peer_id != 0 and _holder_peer_id != peer_id:
		return
	_holder_peer_id = peer_id
	_has_pull_target = false
	_target_basis = global_transform.basis


@rpc("any_peer", "call_local", "reliable")
func rpc_release_grab(peer_id: int) -> void:
	if _holder_peer_id != peer_id:
		return
	_holder_peer_id = 0
	_has_pull_target = false


@rpc("any_peer", "call_local", "reliable")
func rpc_update_pull_target(peer_id: int, target_pos: Vector3) -> void:
	if _holder_peer_id != peer_id:
		return
	_pull_target = target_pos
	_has_pull_target = true


@rpc("any_peer", "call_local", "reliable")
func rpc_apply_rotation(peer_id: int, axis: Vector3, angle_delta_rad: float) -> void:
	if _holder_peer_id != peer_id:
		return
	_target_basis = (Basis(axis.normalized(), angle_delta_rad) * _target_basis).orthonormalized()


func _physics_process(delta: float) -> void:
	if not _has_pull_target:
		return

	# ── Rappel vers la position cible (bout du spring arm du porteur) ─────────
	var to_target: Vector3 = _pull_target - global_position
	var desired_velocity: Vector3 = to_target * follow_force * delta
	linear_velocity = linear_velocity.lerp(desired_velocity, follow_damping * delta)
	if linear_velocity.length() > max_follow_speed:
		linear_velocity = linear_velocity.normalized() * max_follow_speed

	# ── Rotation douce vers l'orientation désirée (modifiée par R/T) ──────────
	var current_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = _target_basis.get_rotation_quaternion()
	global_transform.basis = Basis(current_quat.slerp(target_quat, rotation_response * delta))
	angular_velocity = Vector3.ZERO   # on pilote directement l'orientation, pas de couple physique résiduel
