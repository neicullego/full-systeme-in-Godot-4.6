class_name PuzzleSocket
extends Area3D

@export var accepted_group: String = "Grabbable"
@export var position_tolerance: float = 0.3
@export var rotation_tolerance_deg: float = 15.0
@export var allow_180_flip: bool = false
@export var flip_axis: Vector3 = Vector3.UP

@export var door: Door
@export var cooldown: CooldownInteractable
@export var lights_to_activate: Array[LevelLight] = []

## 🆕 Cooldown qui doit être résolu AVANT que ce puzzle ne débloque quoi que ce
## soit. Le socket peut être assemblé physiquement même si ce cooldown n'est
## pas encore résolu — les effets (lumières, porte, cooldown chaîné) se
## déclenchent dès que required_cooldown est résolu, même après coup.
@export var required_cooldown: CooldownInteractable

signal solved

var _is_physically_connected: bool = false   # 🆕 câbles branchés correctement
var _effects_fired: bool = false             # 🆕 lumières/porte/cooldown déclenchés


func _ready() -> void:
	if door == null and cooldown == null and lights_to_activate.is_empty():
		push_warning("PuzzleSocket '%s' : ni 'door', ni 'cooldown', ni 'lights_to_activate' assigné — la résolution n'aura aucun effet." % name)

	if required_cooldown:   # 🆕
		required_cooldown.solved.connect(_on_required_cooldown_solved)


func _physics_process(_delta: float) -> void:
	if _is_physically_connected:
		return
	for body in get_overlapping_bodies():
		if not body.is_in_group(accepted_group):
			continue
		if _matches_target(body):
			_rpc_connect.rpc(body.get_path())
			return


func _matches_target(body: Node3D) -> bool:
	if global_position.distance_to(body.global_position) > position_tolerance:
		return false

	var body_quat: Quaternion = body.global_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	var tol_rad: float = deg_to_rad(rotation_tolerance_deg)

	if body_quat.angle_to(target_quat) <= tol_rad:
		return true

	if allow_180_flip:
		var flipped_quat: Quaternion = Quaternion(flip_axis.normalized(), PI) * target_quat
		if body_quat.angle_to(flipped_quat) <= tol_rad:
			return true

	return false


## 🆕 Renommée depuis _rpc_solve : ne fait plus que figer l'objet en place et
## marquer le câblage comme correct. Les effets réels passent par _try_fire_effects().
@rpc("any_peer", "call_local", "reliable")
func _rpc_connect(matched_object_path: NodePath) -> void:
	if _is_physically_connected:
		return
	_is_physically_connected = true
	print("[PuzzleSocket] Câblage correct : ", name)

	var matched_object := get_node_or_null(matched_object_path)
	if matched_object and matched_object.has_method("lock_in_place"):
		matched_object.lock_in_place()

	_try_fire_effects()


## 🆕 Appelée quand required_cooldown se résout — peut arriver avant OU après
## que le câblage soit fait.
func _on_required_cooldown_solved() -> void:
	_try_fire_effects()


## 🆕 Ne déclenche les effets que si le câblage est fait ET (pas de cooldown
## requis, ou ce cooldown requis est déjà résolu). Sûre à appeler plusieurs fois.
func _try_fire_effects() -> void:
	if _effects_fired:
		return
	if not _is_physically_connected:
		return
	if required_cooldown and not required_cooldown.is_solved():
		print("[PuzzleSocket] '%s' câblé, en attente du courant." % name)
		return

	_effects_fired = true
	print("[PuzzleSocket] Résolu : ", name)
	solved.emit()

	for light in lights_to_activate:
		if is_instance_valid(light):
			light.turn_on()

	if door:
		door.unlock()
	if cooldown:
		cooldown.unlock()
