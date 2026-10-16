extends Node3D

# --- ÉNUMÉRATIONS ---
enum TriggerMode { ANIMATION, SIGNAL, TUTORIAL }

# --- VARIABLES EXPORTÉES ---
@export_category("Comportement du Trigger")
@export var mode: TriggerMode = TriggerMode.ANIMATION
@export var require_all_players: bool = true
@export var trigger_once: bool = true

@export_category("Mode: Animation")
@export var animation_player: AnimationPlayer
@export var animation_name: String = "nom_de_l_animation"

@export_category("Mode: Signal")
@export var custom_signal_name: String = "mon_signal_personnalise"

@export_category("Mode: Tutoriel")
@export_multiline var tutorial_text: String = "Appuyez sur la touche d'interaction."
@export var tutorial_button_icon: Texture2D
## Nom de l'action d'entrée à valider dans l'Input Map (ex: "interact", "ui_crouch")
@export var tutorial_required_action: String = "interact"
## Durée avant fermeture automatique (0 = reste affiché jusqu'à l'action)
@export var tutorial_auto_dismiss_time: float = 0.0

@export_category("Zone de danger")
@export var is_danger_zone: bool = false

# --- VARIABLES INTERNES ---
var repetition = false
var _players_passed: Dictionary = {}

func _ready() -> void:
	repetition = false
	_players_passed.clear()

	if mode == TriggerMode.SIGNAL and not has_user_signal(custom_signal_name):
		add_user_signal(custom_signal_name)


func _on_area_3d_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return

	# Bloque le passage uniquement si le trigger est configuré comme à usage unique
	if trigger_once and repetition:
		return

	# Zone de danger (serveur uniquement)
	if is_danger_zone and multiplayer.is_server():
		body.rpc_set_wanted.rpc(true)

	# ─── MODE TUTORIEL (purement local) ───
	if mode == TriggerMode.TUTORIAL:
		if body.is_multiplayer_authority() and body.has_method("display_tutorial"):
			body.display_tutorial(
				tutorial_text,
				tutorial_button_icon,
				tutorial_required_action,
				tutorial_auto_dismiss_time
			)
		repetition = true
		return

	# ─── MODES ANIMATION / SIGNAL ───
	var is_solo: bool = multiplayer.multiplayer_peer is OfflineMultiplayerPeer

	if is_solo or not require_all_players:
		repetition = true
		if multiplayer.is_server():
			execute_networked_action.rpc()
		return

	if multiplayer.is_server():
		_rpc_mark_player_passed.rpc(body.get_multiplayer_authority())


@rpc("call_local", "reliable")
func _rpc_mark_player_passed(peer_id: int) -> void:
	if repetition:
		return
	_players_passed[peer_id] = true

	if not multiplayer.is_server():
		return

	var total_players: int = multiplayer.get_peers().size() + 1
	if _players_passed.size() >= total_players:
		repetition = true
		execute_networked_action.rpc()


@rpc("call_local", "reliable")
func execute_networked_action() -> void:
	match mode:
		TriggerMode.ANIMATION:
			if animation_player:
				animation_player.play(animation_name)
			else:
				push_warning("Attention : L'AnimationPlayer n'a pas été assigné dans " + name)

		TriggerMode.SIGNAL:
			emit_signal(custom_signal_name)
			print("Le trigger ", name, " a émis le signal : ", custom_signal_name)

func _on_area_3d_body_exited(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return

	if not trigger_once:
		repetition = false
		if multiplayer.is_server():
			_players_passed.erase(body.get_multiplayer_authority())
