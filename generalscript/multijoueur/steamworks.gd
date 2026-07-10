extends Node

## Autoload (singleton) qui gère l'intégration Steamworks via GodotSteam :
## initialisation, lobbies, invitations et création du MultiplayerPeer Steam.
## ⚠️ À enregistrer dans Project Settings > Autoload sous le nom EXACT "Steamworks".

# ── SIGNAUX ───────────────────────────────────────────────────────────────
signal host_ready                    # Lobby créé, on est prêt en tant qu'hôte
signal join_started                  # Lobby rejoint en tant que client
signal lobby_error(message: String)

# ── ÉTAT ──────────────────────────────────────────────────────────────────
var lobby_id: int = 0
var is_steam_initialized: bool = false
var max_players: int = 4


func _ready() -> void:
	var initialize_response: Dictionary = Steam.steamInitEx()
	print("[Steam] Initialisation : %s" % initialize_response)
	is_steam_initialized = initialize_response["status"] == Steam.STEAM_API_INIT_RESULT_OK

	if not is_steam_initialized:
		push_warning("[Steam] Échec d'initialisation. Vérifie que le client Steam est lancé et que steam_appid.txt (480) est présent à la racine du projet.")
		return

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_lobby_join_requested)

	_check_command_line()


func _process(_delta: float) -> void:
	if is_steam_initialized:
		Steam.run_callbacks()


# ── INVITATION ACCEPTÉE ALORS QUE LE JEU ÉTAIT FERMÉ ─────────────────────
# Steam relance le jeu avec l'argument "+connect_lobby <id>" dans ce cas.
func _check_command_line() -> void:
	var args := OS.get_cmdline_args()
	if args.size() > 1 and args[0] == "+connect_lobby":
		var invited_lobby_id := int(args[1])
		if invited_lobby_id > 0:
			join_lobby(invited_lobby_id)


# ── CRÉATION DE LOBBY (HÔTE) ──────────────────────────────────────────────
func create_lobby(player_limit: int) -> void:
	if not is_steam_initialized:
		lobby_error.emit("Steam n'est pas initialisé (le client Steam est-il lancé ?).")
		return
	if lobby_id != 0:
		return   # déjà dans un lobby

	max_players = player_limit
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_players)


func _on_lobby_created(connect: int, this_lobby_id: int) -> void:
	if connect != 1:
		lobby_error.emit("Impossible de créer le lobby Steam.")
		return

	lobby_id = this_lobby_id
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyData(lobby_id, "name", "%s's lobby" % Steam.getPersonaName())
	Steam.allowP2PPacketRelay(true)   # autorise le relais Steam si la connexion directe échoue (NAT/pare-feu)

	var peer := SteamMultiplayerPeer.new()
	peer.create_host(0)
	peer.server_relay = true   # les clients passent par l'hôte plutôt que de se parler entre eux
	multiplayer.set_multiplayer_peer(peer)

	host_ready.emit()


# ── REJOINDRE UN LOBBY (CLIENT) ───────────────────────────────────────────
func join_lobby(this_lobby_id: int) -> void:
	if not is_steam_initialized:
		lobby_error.emit("Steam n'est pas initialisé (le client Steam est-il lancé ?).")
		return
	Steam.joinLobby(this_lobby_id)


# Déclenché quand on accepte une invitation Steam pendant que le jeu tourne déjà
func _on_lobby_join_requested(this_lobby_id: int, _friend_id: int) -> void:
	join_lobby(this_lobby_id)


func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_error.emit("Impossible de rejoindre le lobby (code %s)." % response)
		return

	lobby_id = this_lobby_id
	var owner_id: int = Steam.getLobbyOwner(lobby_id)

	# Si on est nous-même le propriétaire (cas de l'hôte qui vient de créer son
	# propre lobby), le peer a déjà été créé dans _on_lobby_created() : on s'arrête là.
	if owner_id == Steam.getSteamID():
		return

	var peer := SteamMultiplayerPeer.new()
	peer.create_client(owner_id, 0)
	peer.server_relay = true
	multiplayer.set_multiplayer_peer(peer)

	join_started.emit()


# ── OVERLAY STEAM (invitations / liste d'amis) ────────────────────────────
func open_invite_dialog() -> void:
	if lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)


func open_friends_overlay() -> void:
	Steam.activateGameOverlay("friends")


# ── QUITTER LE LOBBY ───────────────────────────────────────────────────────
func leave_lobby() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
