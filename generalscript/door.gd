extends RigidBody3D

# ── EXPORT ────────────────────────────────────────────────────────────────────
@export var is_locked: bool = false:
	set(value):
		is_locked = value
		freeze = value
@export var pull_force: float = 2.0        # Force d'attraction du marqueur
## ID de la clé requise pour déverrouiller — doit correspondre à l'item_id de l'inventaire
@export var door_id: String = ""

# ── NŒUDS ────────────────────────────────────────────────────────────────────
@onready var marker_node: Marker3D = $marker_node  # ⚠️ Ajustez selon votre arborescence

# ── ÉTAT D'INTERACTION ────────────────────────────────────────────────────────
# ID du peer qui tient la porte (-1 = porte libre)
var _interacting_peer: int = -1
# Position vers laquelle le marqueur de la porte doit être attiré
var _pull_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	freeze = is_locked
	# Sur le serveur uniquement : nettoie l'état si un peer se déconnecte en tenant la porte
	if is_multiplayer_authority():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# ── RPC : SAISIE ──────────────────────────────────────────────────────────────
# Appelé par le joueur (client OU serveur) quand il commence à interagir.
# "call_local" → s'exécute aussi localement pour que tous les peers connaissent
# l'état de la porte (utile pour l'IK visuel des autres joueurs).
@rpc("any_peer", "call_local", "reliable")
func rpc_request_grab(peer_id: int) -> void:
	if is_locked or _interacting_peer != -1:
		return
	_interacting_peer = peer_id


# ── RPC : MISE À JOUR DE LA CIBLE ────────────────────────────────────────────
# Envoyé chaque frame par le joueur qui tient la porte (sa position InteractPos).
# "unreliable" car le paquet suivant arrivera de toute façon 16 ms plus tard.
@rpc("any_peer", "call_local", "unreliable")
func rpc_update_pull_target(peer_id: int, target_pos: Vector3) -> void:
	if _interacting_peer == peer_id:
		_pull_target = target_pos


# ── RPC : RELÂCHEMENT ────────────────────────────────────────────────────────
@rpc("any_peer", "call_local", "reliable")
func rpc_release_grab(peer_id: int) -> void:
	if _interacting_peer == peer_id:
		_interacting_peer = -1
		_pull_target = Vector3.ZERO


# ── DÉVERROUILLAGE PAR CLÉ ──────────────────────────────────────────────────
## Appelée par InteractionManager quand le joueur a la bonne clé en inventaire.
## Retourne true si la clé correspond et déclenche le déverrouillage sur tous les peers.
func try_unlock(key_id: String) -> bool:
	if door_id.is_empty() or key_id == door_id:
		interact_ok.rpc()
		return true
	print("[Door] Mauvaise clé : '", key_id, "' — requise : '", door_id, "'")
	return false

## Déverrouille la porte sur tous les peers (y compris l'appelant via call_local).
@rpc("any_peer", "call_local", "reliable")
func interact_ok() -> void:
	is_locked = false
	print("[Door] Déverrouillée !")


# ── PHYSIQUE (côté autorité = serveur uniquement) ────────────────────────────
func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _interacting_peer == -1 or _pull_target == Vector3.ZERO:
		return
	if not is_instance_valid(marker_node):
		return

	var force_dir: Vector3 = _pull_target - marker_node.global_transform.origin
	# Évite la division par zéro si la cible est déjà sur le marqueur
	if force_dir.length_squared() < 0.0001:
		return

	apply_central_force(force_dir.normalized() * pull_force)


# ── NETTOYAGE DÉCONNEXION ─────────────────────────────────────────────────────
func _on_peer_disconnected(peer_id: int) -> void:
	# Si le joueur qui tenait la porte se déconnecte, on libère la porte
	if _interacting_peer == peer_id:
		_interacting_peer = -1
		_pull_target = Vector3.ZERO
