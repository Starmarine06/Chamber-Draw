extends Node

## EOSManager - Epic Online Services hub autoload.
##
## Owns the whole multiplayer lifecycle:
##   1. Login (devtool / account portal / persistent / anonymous, per EOSConfig).
##   2. Lobby create/join by 6-char join code (EOS Lobbies, PublicAdvertised).
##   3. P2P transport via EOSGMultiplayerPeer (star topology, host = peer 1).
##   4. Seat roster that couples lobby members to P2P peer ids.
##
## Gameplay RPCs (intents, snapshots, logs, private messages) live in the game
## scene (game.gd); this node only owns transport + lobby + identity. Host is
## authoritative over the GameState; clients render from snapshots.

#region Signals

## "logging_in" | "logged_in" | "login_failed" | "logged_out"
signal login_state_changed(state: String)

## "none" | "creating" | "created" | "joining" | "joined" | "starting" | "started" | "left" | "error"
signal lobby_state_changed(state: String)

## Any lobby data changed (attributes, member join/leave). Lobby UI refreshes here.
signal lobby_updated

## Seat roster was rebuilt or a peer's connected flag changed.
signal roster_updated

#endregion

#region Constants

const SOCKET_ID := "CHAMBERDRAW"
const BUCKET_ID := "chamberdraw"
const ATTR_JOIN_CODE := "JOIN_CODE"
const ATTR_LOBBY_NAME := "LOBBY_NAME"
const ATTR_VERSION := "VER"
const ATTR_NAME := "NAME"
const ATTR_CONNECTED := "CONNECTED"
const ATTR_COLOR := "COLOR"
const VERSION := "1"

const HOST_PEER_ID := 1

#endregion

#region Public state

var logged_in := false
var login_in_progress := false

var is_host := false
var is_online := false
var lobby: HLobby = null
var join_code := ""
var lobby_name := ""
var max_members := 7

## Current EOSGMultiplayerPeer (untyped: native GDExtension class).
var peer = null

## Seat roster. Each entry: {seat, peer_id, puid, display_name, is_host, connected}
## seat 0 is always the host. Frozen once the game starts.
var roster: Array = []

#endregion

#region Private state

var _puid_to_peer_id: Dictionary = {}
var _peer_to_seat: Dictionary = {}
var _seats_fixed := false
var _config: Dictionary = {}

#endregion


func get_product_user_id() -> String:
	return HAuth.product_user_id


func get_display_name() -> String:
	if not HAuth.display_name.is_empty():
		return HAuth.display_name
	return EOSConfig.display_name


func is_connected_to_host() -> bool:
	if not peer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


#region Login

## Fire-and-forget login. Connect to login_state_changed for the result.
func request_login() -> void:
	if logged_in:
		login_state_changed.emit("logged_in")
		return
	if login_in_progress:
		return
	try_login()


func try_login() -> bool:
	if logged_in:
		return true
	if login_in_progress:
		return false
	login_in_progress = true
	login_state_changed.emit("logging_in")

	if not EOSConfig.has_credentials():
		push_error("EOSManager: no credentials - fill eos_config.local.json client_id etc.")
		login_in_progress = false
		login_state_changed.emit("login_failed")
		return false

	var ok := await HPlatform.setup_eos_async(EOSConfig.credentials)
	if not ok:
		push_error("EOSManager: EOS platform setup failed.")
		login_in_progress = false
		login_state_changed.emit("login_failed")
		return false

	var success := await _do_login()
	login_in_progress = false
	logged_in = success
	login_state_changed.emit("logged_in" if success else "login_failed")
	if success:
		print("[EOSManager] Logged in. EOS product_user_id=%s" % get_product_user_id())
	return success


func _do_login() -> bool:
	var method := EOSConfig.login_method.strip_edges()
	if method.is_empty() or method == "auto":
		method = "persistent_auth"

	match method:
		"anonymous":
			return await HAuth.login_anonymous_async(EOSConfig.display_name)
		"devtool":
			var ok := await HAuth.login_devtool_async(EOSConfig.devtool_server_url, EOSConfig.devtool_credential_name)
			if not ok and EOSConfig.fallback_to_account_portal:
				return await HAuth.login_account_portal_async()
			return ok
		"account_portal":
			return await HAuth.login_account_portal_async()
		"persistent_auth":
			var ok := await HAuth.login_persistent_auth_async()
			if not ok and EOSConfig.fallback_to_account_portal:
				return await HAuth.login_account_portal_async()
			return ok
		_:
			push_error("EOSManager: unknown login method '%s'" % EOSConfig.login_method)
			return false

#endregion

#region Lobby creation

## Create a lobby. The host becomes seat 0 and opens the P2P server socket.
func create_lobby(local_name: String = "") -> bool:
	if not logged_in:
		return false
	if lobby:
		return false
	if not local_name.is_empty():
		lobby_name = local_name
	if lobby_name.is_empty():
		lobby_name = "%s's Game" % get_display_name()

	lobby_state_changed.emit("creating")

	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = BUCKET_ID
	opts.max_lobby_members = max_members
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.presence_enabled = false
	opts.enable_rtc_room = false
	opts.allow_invites = false
	opts.enable_join_by_id = true

	var new_lobby := await HLobbies.create_lobby_async(opts)
	if not new_lobby:
		lobby_state_changed.emit("error")
		return false

	lobby = new_lobby
	lobby.bucket_id = BUCKET_ID
	lobby.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	lobby.max_members = max_members
	is_host = true
	is_online = true
	join_code = _generate_join_code()
	_seats_fixed = false

	lobby.add_attribute(ATTR_JOIN_CODE, join_code, EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_attribute(ATTR_LOBBY_NAME, lobby_name, EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_attribute(ATTR_VERSION, VERSION, EOS.Lobby.LobbyAttributeVisibility.Public)
	if not await lobby.update_async():
		push_error("EOSManager: failed to publish lobby attributes.")
		lobby_state_changed.emit("error")
		return false

	# We are a lobby member too - announce identity + P2P readiness + color.
	lobby.add_current_member_attribute(ATTR_NAME, get_display_name(), EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_CONNECTED, "1", EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_COLOR, str(GameGlobals.my_color_idx), EOS.Lobby.LobbyAttributeVisibility.Public)
	await lobby.update_async()

	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_kicked)

	_host_peer_ready()
	_rebuild_roster()

	lobby_state_changed.emit("created")
	print("[EOSManager] Lobby created: id=%s join_code=%s bucket=%s" % [lobby.lobby_id, join_code, BUCKET_ID])
	return true

#endregion

#region Lobby join

## Join an existing lobby by 6-char join code, then open a P2P client socket to the host.
func join_lobby(code: String) -> bool:
	if not logged_in:
		return false
	if lobby:
		return false
	code = code.strip_edges().to_upper()
	if code.length() < 4:
		lobby_state_changed.emit("error")
		return false

	lobby_state_changed.emit("joining")

	var found: Variant = await HLobbies.search_by_attribute_async([
		{key = ATTR_JOIN_CODE, value = code, comparison = EOS.ComparisonOp.Equal},
		{key = EOS.Lobby.SEARCH_BUCKET_ID, value = BUCKET_ID, comparison = EOS.ComparisonOp.Equal},
	])
	if found == null or found.is_empty():
		push_warning("EOSManager: no lobby found for join code '%s'." % code)
		lobby_state_changed.emit("error")
		return false

	var new_lobby: Variant = await HLobbies.join_async(found[0])
	if not new_lobby:
		push_error("EOSManager: failed to join lobby for code '%s'." % code)
		lobby_state_changed.emit("error")
		return false

	lobby = new_lobby
	is_host = false
	is_online = true
	join_code = code
	lobby_name = _lobby_attribute_string(lobby, ATTR_LOBBY_NAME, lobby_name)
	_seats_fixed = false

	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_kicked)

	lobby.add_current_member_attribute(ATTR_NAME, get_display_name(), EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_CONNECTED, "1", EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_COLOR, str(GameGlobals.my_color_idx), EOS.Lobby.LobbyAttributeVisibility.Public)
	await lobby.update_async()

	_client_peer_ready(lobby.owner_product_user_id)

	lobby_state_changed.emit("joined")
	print("[EOSManager] Joined lobby: id=%s host=%s" % [lobby.lobby_id, lobby.owner_product_user_id])
	return true

#endregion

#region Game start

## Host-only. Freeze the seat roster, push config to every client, then the
## lobby UI switches to the game scene. Clients auto-switch on _rpc_game_started.
func host_start_game(mode: int) -> bool:
	if not is_host or not lobby:
		return false
	if _seats_fixed:
		return false
	if roster.size() < 2:
		return false
	for entry in roster:
		if not entry.connected:
			push_warning("EOSManager: cannot start - seat %d not connected." % entry.seat)
			return false

	_seats_fixed = true
	GameGlobals.is_online = true
	GameGlobals.game_mode = mode
	GameGlobals.num_players = roster.size()
	GameGlobals.own_seat = 0

	var config: Dictionary = {
		"mode": mode,
		"roster": roster.duplicate(true),
	}

	for entry in roster:
		if entry.peer_id == HOST_PEER_ID:
			continue
		rpc_id(entry.peer_id, "_rpc_game_started", config)

	lobby_state_changed.emit("started")
	print("[EOSManager] Game started. roster=%s" % _roster_summary())
	return true


@rpc("any_peer", "call_local", "reliable")
func _rpc_game_started(config: Dictionary) -> void:
	_config = config
	GameGlobals.is_online = true
	GameGlobals.game_mode = int(config.mode)
	GameGlobals.num_players = config.roster.size()

	_seats_fixed = true
	roster = config.roster.duplicate(true)
	GameGlobals.own_seat = get_own_seat()

	get_tree().change_scene_to_file("res://scenes/game.tscn")

#endregion

#region Transport

func _host_peer_ready() -> void:
	peer = EOSGMultiplayerPeer.new()
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	var err: int = peer.create_server(SOCKET_ID)
	if err != OK:
		push_error("EOSManager: create_server failed: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer


func _client_peer_ready(host_puid: String) -> void:
	if host_puid.is_empty():
		push_error("EOSManager: cannot create client peer - host puid unknown.")
		return
	peer = EOSGMultiplayerPeer.new()
	peer.peer_disconnected.connect(_on_peer_disconnected)
	var err: int = peer.create_client(SOCKET_ID, host_puid)
	if err != OK:
		push_error("EOSManager: create_client failed: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer


func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	if peer == null:
		return
	var puid: String = peer.get_peer_user_id(peer_id)
	_puid_to_peer_id[puid] = peer_id
	print("[EOSManager] Client connected: peer_id=%s puid=%s" % [peer_id, puid])
	_rebuild_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host:
		var seat: int = _peer_to_seat.get(peer_id, -1)
		if peer:
			peer.disconnect_peer(peer_id)
		_puid_to_peer_id.erase(_puid_for_peer_id(peer_id))
		print("[EOSManager] Client disconnected: peer_id=%s seat=%s" % [peer_id, seat])
		_rebuild_roster()
	else:
		print("[EOSManager] Lost connection to host.")
		_teardown_local()
		lobby_state_changed.emit("left")

#endregion

#region Roster helpers

## Local player picked a new color in the lobby. Update the shared globals and,
## if in a lobby, publish the change as a public member attribute so the host's
## roster rebuild sees it when the lobby updates.
func set_my_color(idx: int) -> void:
	GameGlobals.my_color_idx = idx
	if lobby == null:
		return
	lobby.add_current_member_attribute(ATTR_COLOR, str(idx), EOS.Lobby.LobbyAttributeVisibility.Public)
	await lobby.update_async()
	if is_host:
		_rebuild_roster()

## Rebuild seat roster from lobby members + P2P state. Host-side only.
func _rebuild_roster() -> void:
	if not is_host or lobby == null or peer == null:
		return

	if not _seats_fixed:
		roster = []
		_peer_to_seat = {}
		roster.append({
			"seat": 0,
			"peer_id": HOST_PEER_ID,
			"puid": get_product_user_id(),
			"display_name": get_display_name(),
			"is_host": true,
			"connected": true,
			"color_idx": GameGlobals.my_color_idx,
		})
		_peer_to_seat[HOST_PEER_ID] = 0

		var next_seat := 1
		for member in lobby.members:
			if member.is_owner():
				continue
			var puid: String = member.product_user_id
			var peer_id: int = _puid_to_peer_id.get(puid, 0)
			var entry := {
				"seat": next_seat,
				"peer_id": peer_id,
				"puid": puid,
				"display_name": _member_display_name(member),
				"is_host": false,
				"connected": peer_id != 0 and peer.has_peer(peer_id),
				"color_idx": _member_color_idx(member),
			}
			roster.append(entry)
			if peer_id != 0:
				_peer_to_seat[peer_id] = next_seat
			next_seat += 1
	else:
		for entry in roster:
			if entry.peer_id == HOST_PEER_ID:
				entry.connected = true
			else:
				entry.connected = entry.peer_id != 0 and peer.has_peer(entry.peer_id)

	roster_updated.emit()


func _member_display_name(member: HLobbyMember) -> String:
	var attr: Variant = member.get_attribute(ATTR_NAME)
	if attr and attr.get("value") != null:
		return str(attr.value)
	return member.product_user_id.substr(0, 8)


func _member_color_idx(member: HLobbyMember) -> int:
	var attr: Variant = member.get_attribute(ATTR_COLOR)
	var raw: Variant = attr.get("value", null) if attr != null else null
	if raw == null:
		return 0
	var idx: int = raw.to_int() if raw is String else int(raw)
	if idx < 0 or idx >= GameGlobals.PALETTE.size():
		return 0
	return idx


func member_color(member: HLobbyMember) -> Color:
	return GameGlobals.PALETTE[_member_color_idx(member)]


func color_for_entry(entry: Dictionary) -> Color:
	var idx: int = int(entry.get("color_idx", 0)) % GameGlobals.PALETTE.size()
	return GameGlobals.PALETTE[idx]


func _lobby_attribute_string(l: HLobby, key: String, fallback: String) -> String:
	var attr: Variant = l.get_attribute(key)
	if attr and attr.get("value") != null:
		return str(attr.value)
	return fallback


func _roster_summary() -> String:
	var parts: Array[String] = []
	for entry in roster:
		parts.append("%d:peer%d:%s" % [entry.seat, entry.peer_id, entry.display_name])
	return "[%s]" % ", ".join(parts)


func get_own_seat() -> int:
	if not is_online:
		return 0
	var puid := get_product_user_id()
	for entry in roster:
		if entry.puid == puid:
			return entry.seat
	return 0


func get_peer_id_for_seat(seat: int) -> int:
	for entry in roster:
		if entry.seat == seat:
			return entry.peer_id
	return 0


func get_seat_for_peer(peer_id: int) -> int:
	return _peer_to_seat.get(peer_id, -1)


func _puid_for_peer_id(peer_id: int) -> String:
	for puid in _puid_to_peer_id.keys():
		if _puid_to_peer_id[puid] == peer_id:
			return puid
	return ""

#endregion

#region Lifecycle

func _on_lobby_updated() -> void:
	_rebuild_roster()
	lobby_updated.emit()


func _on_kicked() -> void:
	print("[EOSManager] Left lobby (kicked/destroyed).")
	_teardown_local()
	lobby_state_changed.emit("left")


## Leave (client) or destroy (host) the lobby and tear down the P2P peer.
func leave_lobby() -> void:
	if lobby == null and peer == null:
		return

	_seats_fixed = false
	is_online = false
	is_host = false

	if lobby != null:
		var local_lobby: HLobby = lobby
		lobby = null
		if local_lobby.is_owner():
			await local_lobby.destroy_async()
		else:
			await local_lobby.leave_async()

	_teardown_local()
	lobby_state_changed.emit("left")


func _teardown_local() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	roster = []
	_puid_to_peer_id = {}
	_peer_to_seat = {}
	_config = {}
	is_host = false
	is_online = false
	_seats_fixed = false
	GameGlobals.is_online = false

#endregion

#region Misc

func _generate_join_code() -> String:
	const chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	for i in 6:
		s += chars[randi_range(0, chars.length() - 1)]
	return s

#endregion