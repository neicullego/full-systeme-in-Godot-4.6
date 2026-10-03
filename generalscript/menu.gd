extends Control

class_name GameMenu

static var instance: GameMenu

const PORT := 7777

var _transition_id: int = 0

## Nombre maximum de joueurs par partie (modifiable directement depuis l'Inspecteur)
@export_range(1, 16, 1, "or_greater") var max_players: int = 4

## Nombre minimum de joueurs requis pour pouvoir lancer la partie (ex: 2 pour ne pas jouer seul)
@export_range(1, 16, 1, "or_greater") var min_players_to_start: int = 2

@onready var menu = $VBoxContainer
@onready var retour = $retour
@onready var mainmenu = $MainMenu
@onready var local_ip_label: Label = $MainMenu/VBoxContainer2/LocalIPLabel
@onready var copy_button: Button = $MainMenu/VBoxContainer2/CopyButton
@onready var ip_input: LineEdit = $MainMenu/VBoxContainer2/IPInput
@onready var host_button: Button = $MainMenu/VBoxContainer2/host
@onready var join_button: Button = $MainMenu/VBoxContainer2/join
@onready var status_label: Label = $MainMenu/StatusLabel
@onready var skin_selector: SkinSelector = $MainMenu/skin_selector
@onready var steam = $MainMenu/VBoxContainerSteam
@onready var local = $MainMenu/VBoxContainer2
@onready var steam_host_button: Button = $MainMenu/VBoxContainerSteam/SteamHost
@onready var steam_join_button: Button = $MainMenu/VBoxContainerSteam/SteamJoin
@onready var settings = $settings
@onready var local_steam_toggle: HBoxContainer = $MainMenu/HBoxContainer   # 🆕
@onready var credit = $credit

var _is_choosing_skin_for_solo: bool = false 
var game_instance: Node = null
var cinematic_instance: Node = null
var players_ready: Dictionary = {}   # peer_id (int) -> est_pret (bool)


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	instance = self
	retour.visible = false
	mainmenu.visible = false
	credit.visible = false
	
	skin_selector.visible = false
	skin_selector.skin_chosen.connect(_on_skin_chosen)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	Steamworks.host_ready.connect(_on_steam_host_ready)
	Steamworks.join_started.connect(_on_steam_join_started)
	Steamworks.lobby_error.connect(_on_steam_lobby_error)

	_display_local_ip()


func _on_play_pressed() -> void:
	_is_choosing_skin_for_solo = true
	mainmenu.visible = true        # nécessaire : skin_selector est dedans
	retour.visible = true          # permet d'annuler et revenir au menu
	_show_only_skin_selector()
	skin_selector.visible = true


func _on_exiet_pressed() -> void:
	GameMenu.instance.leave_multiplayer_game()
	get_tree().quit()


func _on_multiplayer_pressed() -> void:
	menu.visible = false
	retour.visible = true
	mainmenu.visible = true
	local.visible = true
	steam.visible = false


func _on_retour_pressed() -> void:
	_return_to_menu()
# ---------------------------------------------------------------------------
# IP locale + bouton copier
# ---------------------------------------------------------------------------

func _display_local_ip() -> void:
	local_ip_label.text = "IP locale : %s" % _get_local_ip()


func _get_local_ip() -> String:
	# On cherche une adresse IPv4 privée typique d'un réseau local (Wi-Fi/Ethernet)
	for addr in IP.get_local_addresses():
		if addr.find(":") != -1:        # on ignore l'IPv6
			continue
		if addr.begins_with("127."):    # on ignore le loopback
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"


func _on_copy_button_pressed() -> void:
	var ip := _get_local_ip()
	DisplayServer.clipboard_set(ip)
	status_label.text = "IP copiée : %s" % ip


# ---------------------------------------------------------------------------
# Host / Join — réseau local (LAN, via ENet)
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	Steamworks.leave_lobby()   # au cas où un lobby Steam était actif

	var peer := ENetMultiplayerPeer.new()
	# max_clients = max_players - 1 car l'hôte compte déjà comme un joueur
	var error := peer.create_server(PORT, max(max_players - 1, 1))
	if error != OK:
		status_label.text = "Erreur serveur : %s" % error
		return

	multiplayer.multiplayer_peer = peer
	_setup_host_ui()
	status_label.text = "Serveur lancé (1/%d). En attente des joueurs…" % max_players


func _on_join_pressed() -> void:
	Steamworks.leave_lobby()   # au cas où un lobby Steam était actif

	var ip_text := ip_input.text.strip_edges()
	if ip_text.is_empty():
		ip_text = "127.0.0.1"

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip_text, PORT)
	if error != OK:
		status_label.text = "Erreur client : %s" % error
		return

	multiplayer.multiplayer_peer = peer
	status_label.text = "Connexion en cours…"
	host_button.disabled = true
	join_button.disabled = true
	steam_host_button.disabled = true
	steam_join_button.disabled = true


func _on_connected_to_server() -> void:
	status_label.text = "Connecté ! Choisis ton personnage…"
	_show_only_skin_selector()
	skin_selector.visible = true



func _on_connection_failed() -> void:
	status_label.text = "Connexion échouée."
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	host_button.disabled = false
	join_button.disabled = false
	steam_host_button.disabled = false
	steam_join_button.disabled = false


# ---------------------------------------------------------------------------
# Host / Join — en ligne via Steam (lobby + invitation par l'overlay)
# ---------------------------------------------------------------------------

func _on_steam_host_pressed() -> void:
	steam_host_button.disabled = true
	status_label.text = "Création du lobby Steam…"
	Steamworks.create_lobby(max_players)


func _on_steam_join_pressed() -> void:
	# Pas de connexion directe ici : on ouvre la liste d'amis Steam.
	# Clique droit sur un ami en train de jouer -> "Rejoindre la partie".
	Steamworks.open_friends_overlay()
	status_label.text = "Ouvre ta liste d'amis Steam, clique-droit sur un ami en jeu puis « Rejoindre la partie »."


func _on_steam_host_ready() -> void:
	_setup_host_ui()
	status_label.text = "Lobby Steam créé (1/%d). Ouverture de l'invitation…" % max_players
	Steamworks.open_invite_dialog()


func _on_steam_join_started() -> void:
	status_label.text = "Connexion au lobby Steam…"
	host_button.disabled = true
	join_button.disabled = true
	steam_host_button.disabled = true
	steam_join_button.disabled = true


func _on_steam_lobby_error(message: String) -> void:
	status_label.text = "Erreur Steam : %s" % message
	steam_host_button.disabled = false
	steam_join_button.disabled = false


# ---------------------------------------------------------------------------
# Mise en place de l'interface côté hôte (commune LAN + Steam)
# ---------------------------------------------------------------------------

func _setup_host_ui() -> void:
	players_ready.clear()
	players_ready[1] = ""
	_show_only_skin_selector()
	skin_selector.visible = true
	host_button.disabled = true
	join_button.disabled = true
	steam_host_button.disabled = true
	steam_join_button.disabled = true
# ---------------------------------------------------------------------------
# Suivi des joueurs connectés (côté hôte) — commun LAN + Steam
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players_ready[id] = ""
	var count := multiplayer.get_peers().size() + 1
	status_label.text = "%d/%d joueurs connectés." % [count, max_players]


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players_ready.erase(id)
	var count := multiplayer.get_peers().size() + 1
	status_label.text = "%d/%d joueurs connectés." % [count, max_players]


# ---------------------------------------------------------------------------
# Système "prêt" : on attend que tout le monde clique avant de lancer la partie
# ---------------------------------------------------------------------------

func _on_skin_chosen(skin_id: String) -> void:
	if _is_choosing_skin_for_solo:
		SkinRegistry.chosen_skins[1] = skin_id
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_launch_game()
		return

	_set_skin_choice.rpc_id(1, skin_id)


@rpc("any_peer", "call_local", "reliable")
func _set_skin_choice(skin_id: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1   # appel local fait par l'hôte lui-même

	players_ready[sender_id] = skin_id

	var ready_count := 0
	for v in players_ready.values():
		if v != "":
			ready_count += 1

	if players_ready.size() < min_players_to_start:
		status_label.text = "%d/%d ont choisi (minimum %d joueurs)." % [ready_count, players_ready.size(), min_players_to_start]
	else:
		status_label.text = "%d/%d joueurs prêts." % [ready_count, players_ready.size()]

	_check_all_ready()



func _check_all_ready() -> void:
	if players_ready.size() < min_players_to_start:
		return
	for v in players_ready.values():
		if v == "":
			return
	_start_game.rpc(players_ready.duplicate())   # 🆕 on diffuse aussi les choix à tout le monde


@rpc("authority", "call_local", "reliable")
func _start_game(all_skin_choices: Dictionary) -> void:
	SkinRegistry.chosen_skins = all_skin_choices.duplicate()
	_launch_game()


func _launch_game() -> void:
	var id := _transition_id
	hide()
	await _free_and_wait(get_node_or_null("SubViewportContainer/SubViewport/Node3D"))
	if id != _transition_id:
		return   # le joueur a quitté pendant la transition
	var cinematic_scene: PackedScene = load("res://scene/cinematique.tscn")
	cinematic_instance = cinematic_scene.instantiate()
	get_tree().root.add_child(cinematic_instance)
	cinematic_instance.finished.connect(_on_cinematic_finished, CONNECT_ONE_SHOT)
	
func _on_cinematic_finished() -> void:
	var id := _transition_id
	var old_cinematic := cinematic_instance
	cinematic_instance = null

	# On attend que la cinématique ait VRAIMENT quitté l'arbre (eau, zones sèches, caméra)
	await _free_and_wait(old_cinematic)
	if id != _transition_id:
		return   # le joueur a quitté pendant la transition

	var game_scene: PackedScene = load("res://main.tscn")
	game_instance = game_scene.instantiate()
	get_tree().root.add_child(game_instance)

func _on_local_button_pressed() -> void:
	local.visible = true
	steam.visible = false


func _on_steam_button_pressed() -> void:
	local.visible = false
	steam.visible = true


func _on_settings_pressed() -> void:
	menu.visible = false
	settings.visible = true


func _on_x_button_pressed() -> void:
	menu.visible = true
	settings.visible = false


## Masque toute l'UI du menu, sauf le sélecteur de skin lui-même
## (SubViewportContainer, Control et le bouton retour ne sont jamais touchés ici)
func _show_only_skin_selector() -> void:
	menu.visible = false
	local_steam_toggle.visible = false
	local.visible = false
	steam.visible = false
	
	
# ---------------------------------------------------------------------------
# Déconnexion propre — couvre LAN (ENet) ET Steam, hôte ET client
# ---------------------------------------------------------------------------

## Filet de sécurité : déclenché côté CLIENT si l'hôte disparaît sans prévenir
## (crash, Alt+F4, coupure réseau...). C'est ce signal qui manquait.
func _on_server_disconnected() -> void:
	_return_to_menu("Connexion à l'hôte perdue. Retour au menu.")


## RPC envoyée par l'hôte AVANT de fermer sa connexion, pour que les clients
## reviennent au menu instantanément plutôt que d'attendre un timeout réseau.
@rpc("authority", "call_local", "reliable")
func _notify_server_leaving() -> void:
	if multiplayer.is_server():
		return   # l'hôte gère son propre retour via leave_multiplayer_game()
	_return_to_menu("L'hôte a quitté la partie. Retour au menu.")


## À appeler depuis le jeu (bouton "Quitter" du menu pause, touche Echap...)
## pour quitter proprement une partie en cours — que l'on soit hôte ou client.
func leave_multiplayer_game() -> void:
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_notify_server_leaving.rpc()
		await get_tree().create_timer(0.3).timeout   # laisse partir le paquet

	_return_to_menu()


## Nettoyage complet + retour à l'écran d'accueil (res://scene/ui/menu.tscn,
## qui est déjà cette scène-ci : pas besoin de la recharger, juste de la réafficher).
func _return_to_menu(message: String = "") -> void:
	_transition_id += 1
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if is_instance_valid(cinematic_instance):   # 🆕
		cinematic_instance.queue_free()
	cinematic_instance = null 
	if is_instance_valid(game_instance):
		game_instance.queue_free()
	game_instance = null

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Steamworks.leave_lobby()

	players_ready.clear()
	_is_choosing_skin_for_solo = false

	show()
	menu.visible = true
	retour.visible = false
	mainmenu.visible = false
	settings.visible = false
	skin_selector.visible = false

	local_steam_toggle.visible = true
	status_label.visible = true
	host_button.disabled = false
	join_button.disabled = false
	steam_host_button.disabled = false
	steam_join_button.disabled = false
	credit.visible = false

	status_label.text = message
	


func _on_credi_pressed() -> void:
	retour.visible = true
	menu.visible = false
	credit.visible = true

func _free_and_wait(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_inside_tree():
		node.queue_free()
		await node.tree_exited
	else:
		node.queue_free()
	await get_tree().process_frame
