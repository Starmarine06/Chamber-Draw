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

## In-game only. Host: a client's connection dropped / they left. Client: host is gone.
signal player_left_game(seat: int, display_name: String)
signal host_lost_in_game

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
const ATTR_HEARTBEAT := "HB"
## Bump whenever RPCs / snapshot format change: mismatched builds silently misroute RPCs
## (everything looks broken for the older one), so joining a different version is refused.
const VERSION := "6"

const HOST_PEER_ID := 1

## Every EOS lobby round-trip is bounded so a dead backend can never wedge the UI.
const LOBBY_OP_TIMEOUT := 12.0
## The host touches the lobby this often so the backend keeps it alive/discoverable.
const LOGIN_STEP_TIMEOUT := 25.0
const HEARTBEAT_INTERVAL := 40.0
const HEARTBEAT_FAILS_BEFORE_REBUILD := 2
## After Start, re-send the start RPC to clients that have not loaded the game yet.
const START_RESEND_INTERVAL := 1.5
const START_RESEND_MAX_TRIES := 14

#endregion

#region Public state

var logged_in := false
var login_in_progress := false

var is_host := false
var is_online := false
var lobby: HLobby = null
var join_code := ""
var last_error := ""
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

var _lobby_op_busy := false
## Bumped by leave/teardown so a slow create/join that finishes late can tell it was cancelled.
var _op_generation := 0
var _hb_timer: Timer = null
var _hb_busy := false
var _hb_failures := 0
## peer_id -> true once that client's game scene has checked in (sent "hello").
var _clients_in_game: Dictionary = {}
## This machine's seat, as told by the host when the game started (clients only).
var _my_seat := -1
var _peer_graveyard: Array = []   # closed peers kept alive briefly (see _teardown_local)

signal _op_finished

#endregion


const VoiceChat := preload("res://scripts/voice_chat.gd")

## Lobby voice (RTC room): mic mode, mute, push-to-talk, per-player mute. See voice_chat.gd.
var voice: Node = null


func _ready() -> void:
	voice = VoiceChat.new()
	voice.name = "Voice"
	add_child(voice)
	HLobbies.local_rtc_options = {"flags": 0, "local_audio_device_input_starts_muted": true}


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
			print("[EOSManager] login step: persistent_auth (build 2)")
			var ok: bool = (await _await_timeout(HAuth.login_persistent_auth_async, LOGIN_STEP_TIMEOUT)) == true
			# The Epic account-portal flow has no working browser hand-off on Linux and
			# never calls back, which would hang login forever - skip it there.
			if not ok and EOSConfig.fallback_to_account_portal and OS.get_name() != "Linux":
				print("[EOSManager] login step: account_portal")
				ok = await HAuth.login_account_portal_async()
			if not ok and EOSConfig.fallback_to_anonymous:
				print("[EOSManager] login step: anonymous fallback (name='%s')" % EOSConfig.display_name)
				var anon_name: String = EOSConfig.display_name
				if anon_name.strip_edges().is_empty():
					anon_name = OS.get_environment("USER") if not OS.get_environment("USER").is_empty() else "Player"
				ok = (await _await_timeout(HAuth.login_anonymous_async.bind(anon_name), LOGIN_STEP_TIMEOUT)) == true
				print("[EOSManager] anonymous login result: %s" % ok)
			return ok
		_:
			push_error("EOSManager: unknown login method '%s'" % EOSConfig.login_method)
			return false

#endregion

#region Lobby creation

## Create a lobby. The host becomes seat 0 and opens the P2P server socket.
func create_lobby(local_name: String = "", forced_code: String = "") -> bool:
	if not logged_in:
		return false
	if _lobby_op_busy:
		return false
	# A leftover lobby/peer from an earlier failed attempt must never block a new room.
	if lobby != null or peer != null:
		await _discard_stale_session()
	_lobby_op_busy = true
	var ok := await _create_lobby_inner(local_name, forced_code)
	_lobby_op_busy = false
	return ok


func _create_lobby_inner(local_name: String, forced_code: String) -> bool:
	var gen := _op_generation
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
	opts.enable_rtc_room = true
	# Members join the voice room muted; voice_chat.gd opens the mic per the player's settings.
	opts.local_rtc_options = {"flags": 0, "local_audio_device_input_starts_muted": true}
	opts.allow_invites = false
	opts.enable_join_by_id = true

	var new_lobby: Variant = await _await_timeout(HLobbies.create_lobby_async.bind(opts), LOBBY_OP_TIMEOUT, true)
	if not new_lobby and gen == _op_generation:
		# Voice rooms need RTC enabled on the Dev Portal deployment; never let that block playing.
		push_warning("EOSManager: lobby with voice failed - retrying without voice.")
		opts.enable_rtc_room = false
		opts.local_rtc_options = null
		new_lobby = await _await_timeout(HLobbies.create_lobby_async.bind(opts), LOBBY_OP_TIMEOUT, true)
	if not new_lobby or gen != _op_generation:
		if new_lobby:
			await _destroy_quietly(new_lobby)
		push_warning("EOSManager: create lobby failed or timed out.")
		lobby_state_changed.emit("error")
		return false

	lobby = new_lobby
	lobby.bucket_id = BUCKET_ID
	lobby.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	lobby.max_members = max_members
	is_host = true
	is_online = true
	join_code = forced_code if not forced_code.is_empty() else _generate_join_code()
	_seats_fixed = false
	_clients_in_game = {}

	lobby.add_attribute(ATTR_JOIN_CODE, join_code, EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_attribute(ATTR_LOBBY_NAME, lobby_name, EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_attribute(ATTR_VERSION, VERSION, EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_attribute(ATTR_HEARTBEAT, str(int(Time.get_unix_time_from_system())), EOS.Lobby.LobbyAttributeVisibility.Public)
	var published: Variant = await _await_timeout(lobby.update_async, LOBBY_OP_TIMEOUT)
	if published != true or gen != _op_generation:
		push_error("EOSManager: failed to publish lobby attributes.")
		await _discard_stale_session()
		lobby_state_changed.emit("error")
		return false

	# We are a lobby member too - announce identity + P2P readiness + color.
	lobby.add_current_member_attribute(ATTR_NAME, get_display_name(), EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_CONNECTED, "1", EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_COLOR, str(GameGlobals.my_color_idx), EOS.Lobby.LobbyAttributeVisibility.Public)
	await _await_timeout(lobby.update_async, LOBBY_OP_TIMEOUT)
	if gen != _op_generation or lobby == null:
		return false

	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_kicked)

	_host_peer_ready()
	_rebuild_roster()
	_start_heartbeat()

	lobby_state_changed.emit("created")
	print("[EOSManager] Lobby created: id=%s join_code=%s bucket=%s" % [lobby.lobby_id, join_code, BUCKET_ID])
	return true

#endregion

#region Lobby join

## Join an existing lobby by 6-char join code, then open a P2P client socket to the host.
func join_lobby(code: String) -> bool:
	if not logged_in:
		return false
	if _lobby_op_busy:
		return false
	code = code.strip_edges().to_upper()
	if code.length() < 4:
		lobby_state_changed.emit("error")
		return false
	# A leftover lobby/peer from an earlier failed attempt must never block a new join.
	if lobby != null or peer != null:
		await _discard_stale_session()
	_lobby_op_busy = true
	var ok := await _join_lobby_inner(code)
	_lobby_op_busy = false
	return ok


func _join_lobby_inner(code: String) -> bool:
	var gen := _op_generation
	last_error = ""
	lobby_state_changed.emit("joining")

	var search_args: Array = [
		{key = ATTR_JOIN_CODE, value = code, comparison = EOS.ComparisonOp.Equal},
		{key = EOS.Lobby.SEARCH_BUCKET_ID, value = BUCKET_ID, comparison = EOS.ComparisonOp.Equal},
	]
	var found: Variant = await _await_timeout(HLobbies.search_by_attribute_async.bind(search_args), LOBBY_OP_TIMEOUT)
	if gen != _op_generation:
		return false  # cancelled (player backed out) while searching
	if found == null or found.is_empty():
		push_warning("EOSManager: no lobby found for join code '%s'." % code)
		lobby_state_changed.emit("error")
		return false

	var new_lobby: Variant = await _await_timeout(HLobbies.join_async.bind(found[0]), LOBBY_OP_TIMEOUT, true)
	if not new_lobby or gen != _op_generation:
		if new_lobby:
			await _leave_quietly(new_lobby)
		push_error("EOSManager: failed to join lobby for code '%s'." % code)
		if gen == _op_generation:
			lobby_state_changed.emit("error")
		return false

	var host_ver := _lobby_attribute_string(new_lobby, ATTR_VERSION, "")
	if host_ver != VERSION:
		push_error("EOSManager: version mismatch (host=%s, me=%s)" % [host_ver, VERSION])
		await _leave_quietly(new_lobby)
		last_error = "Version mismatch: the host is on build %s, you are on build %s. Both players need the same (latest) build." % [host_ver if host_ver != "" else "?", VERSION]
		lobby_state_changed.emit("error")
		return false
	last_error = ""
	lobby = new_lobby
	is_host = false
	is_online = true
	join_code = code
	lobby_name = _lobby_attribute_string(lobby, ATTR_LOBBY_NAME, lobby_name)
	_seats_fixed = false
	_clients_in_game = {}

	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_kicked)

	lobby.add_current_member_attribute(ATTR_NAME, get_display_name(), EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_CONNECTED, "1", EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_current_member_attribute(ATTR_COLOR, str(GameGlobals.my_color_idx), EOS.Lobby.LobbyAttributeVisibility.Public)
	await _await_timeout(lobby.update_async, LOBBY_OP_TIMEOUT)
	if gen != _op_generation or lobby == null:
		return false

	if not _client_peer_ready(lobby.owner_product_user_id):
		# Joined the lobby but cannot reach the host: undo it so the player can retry.
		await _discard_stale_session()
		lobby_state_changed.emit("error")
		return false

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

	_clients_in_game = {}
	_my_seat = 0
	for entry in roster:
		if entry.peer_id == HOST_PEER_ID:
			continue
		# Every client is told its seat EXPLICITLY (never inferred from ids on its side).
		var cfg := config.duplicate(true)
		cfg["your_seat"] = entry.seat
		rpc_id(entry.peer_id, "_rpc_game_started", cfg)

	lobby_state_changed.emit("started")
	print("[EOSManager] Game started. roster=%s" % _roster_summary())
	_resend_start_until_loaded(config)
	return true



## A client's game scene calls this (via its "hello" intent) so we stop re-sending Start.
func mark_client_in_game(peer_id: int) -> void:
	_clients_in_game[peer_id] = true


## The start RPC is sent once; if it was lost or arrived while the client was busy the
## player would sit in the lobby forever. Keep nudging clients that never checked in.
func _resend_start_until_loaded(config: Dictionary) -> void:
	var gen := _op_generation
	for _try in START_RESEND_MAX_TRIES:
		await get_tree().create_timer(START_RESEND_INTERVAL).timeout
		if gen != _op_generation or not is_host or peer == null:
			return
		var pending := false
		for entry in roster:
			if entry.peer_id == HOST_PEER_ID or _clients_in_game.has(entry.peer_id):
				continue
			if entry.peer_id != 0 and peer.has_peer(entry.peer_id):
				pending = true
				var cfg := config.duplicate(true)
				cfg["your_seat"] = entry.seat
				rpc_id(entry.peer_id, "_rpc_game_started", cfg)
		if not pending:
			return


@rpc("any_peer", "call_local", "reliable")
func _rpc_game_started(config: Dictionary) -> void:
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == "res://scenes/game.tscn":
		return  # duplicate (re-sent) start while already in the game
	_config = config
	GameGlobals.is_online = true
	GameGlobals.game_mode = int(config.mode)
	GameGlobals.num_players = config.roster.size()

	_seats_fixed = true
	roster = config.roster.duplicate(true)
	_my_seat = int(config.get("your_seat", -1))
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


func _client_peer_ready(host_puid: String) -> bool:
	if host_puid.is_empty():
		push_error("EOSManager: cannot create client peer - host puid unknown.")
		return false
	peer = EOSGMultiplayerPeer.new()
	peer.peer_disconnected.connect(_on_peer_disconnected)
	var err: int = peer.create_client(SOCKET_ID, host_puid)
	if err != OK:
		push_error("EOSManager: create_client failed: %s" % error_string(err))
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	return true


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
		var left_name := ""
		var in_game := _seats_fixed
		for entry in roster:
			if entry.peer_id == peer_id:
				left_name = str(entry.display_name)
		if peer:
			peer.call_deferred("disconnect_peer", peer_id)   # never inside the peer's own signal
		_puid_to_peer_id.erase(_puid_for_peer_id(peer_id))
		print("[EOSManager] Client disconnected: peer_id=%s seat=%s" % [peer_id, seat])
		_rebuild_roster()
		if in_game and seat > 0:
			player_left_game.emit(seat, left_name)
	else:
		print("[EOSManager] Lost connection to host.")
		# This handler runs INSIDE the EOS peer's own poll/tick. Freeing or closing that
		# peer right here left the SDK calling into a dead object (segfault in IEOS.tick),
		# so the whole teardown is deferred to after the tick finishes.
		_handle_host_lost.call_deferred()


func _handle_host_lost() -> void:
	var was_in_game := _seats_fixed
	_teardown_local()
	if was_in_game:
		host_lost_in_game.emit()
	else:
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
		_dedupe_roster_colors()
	else:
		for entry in roster:
			if entry.peer_id == HOST_PEER_ID:
				entry.connected = true
			else:
				entry.connected = entry.peer_id != 0 and peer.has_peer(entry.peer_id)

	roster_updated.emit()


## Seat order wins: a later seat holding an already-used color gets the first free one.
func _dedupe_roster_colors() -> void:
	var used := {}
	for entry in roster:
		var idx: int = int(entry.get("color_idx", 0)) % GameGlobals.PALETTE.size()
		if used.has(idx):
			for c in range(GameGlobals.PALETTE.size()):
				if not used.has(c):
					idx = c
					break
		used[idx] = true
		entry["color_idx"] = idx


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
	if is_host:
		return 0
	if _my_seat >= 0:
		return _my_seat
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
	if _peer_to_seat.has(peer_id):
		return _peer_to_seat[peer_id]
	# Unknown peer id (e.g. the client's P2P link was re-established after the roster
	# froze): recover the seat from the sender's product user id and re-bind it.
	if peer != null and is_host and peer_id != HOST_PEER_ID:
		var puid: String = peer.get_peer_user_id(peer_id)
		for entry in roster:
			if entry.puid == puid and not puid.is_empty():
				entry.peer_id = peer_id
				entry.connected = true
				_peer_to_seat[peer_id] = entry.seat
				_puid_to_peer_id[puid] = peer_id
				print("[EOSManager] Re-bound peer %d to seat %d (puid match)." % [peer_id, entry.seat])
				return entry.seat
		print("[EOSManager] Unknown peer %d (puid='%s') - not in roster %s" % [peer_id, puid, _roster_summary()])
	return -1


func _puid_for_peer_id(peer_id: int) -> String:
	for puid in _puid_to_peer_id.keys():
		if _puid_to_peer_id[puid] == peer_id:
			return puid
	return ""

#endregion

#region Local test transport

## Two processes on one machine, no EOS: used by tests/net_*.gd to exercise the real
## game networking (seat mapping, intents, snapshots, cameras) end to end.
func debug_enet_host(port: int) -> bool:
	var p := ENetMultiplayerPeer.new()
	if p.create_server(port, 4) != OK:
		return false
	peer = p
	multiplayer.multiplayer_peer = p
	is_host = true
	is_online = true
	logged_in = true
	roster = [{"seat": 0, "peer_id": HOST_PEER_ID, "puid": "host", "display_name": "Host", "is_host": true, "connected": true, "color_idx": 0}]
	p.peer_connected.connect(func(id: int) -> void:
		var seat := roster.size()
		roster.append({"seat": seat, "peer_id": id, "puid": "client%d" % seat, "display_name": "Client%d" % seat, "is_host": false, "connected": true, "color_idx": seat})
		_peer_to_seat[id] = seat
		print("[EOSManager] (enet) client connected id=%d seat=%d" % [id, seat]))
	_peer_to_seat[HOST_PEER_ID] = 0
	return true


func debug_enet_client(port: int) -> bool:
	var p := ENetMultiplayerPeer.new()
	if p.create_client("127.0.0.1", port) != OK:
		return false
	peer = p
	multiplayer.multiplayer_peer = p
	is_host = false
	is_online = true
	logged_in = true
	return true


func debug_start(mode: int) -> void:
	_seats_fixed = true
	GameGlobals.is_online = true
	GameGlobals.game_mode = mode
	GameGlobals.num_players = roster.size()
	GameGlobals.own_seat = 0
	_my_seat = 0
	var config := {"mode": mode, "roster": roster.duplicate(true)}
	for entry in roster:
		if entry.peer_id == HOST_PEER_ID:
			continue
		var cfg := config.duplicate(true)
		cfg["your_seat"] = entry.seat
		rpc_id(entry.peer_id, "_rpc_game_started", cfg)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

#endregion

#region Lifecycle

func _on_lobby_updated() -> void:
	_rebuild_roster()
	lobby_updated.emit()


func _on_kicked() -> void:
	print("[EOSManager] Left lobby (kicked/destroyed).")
	var was_in_game := _seats_fixed and not is_host
	lobby = null   # the lobby object is already gone: never touch it again
	_teardown_local()
	if was_in_game:
		host_lost_in_game.emit()   # in a match: the game scene shows "host left" + exits
	else:
		lobby_state_changed.emit("left")


## Leave (client) or destroy (host) the lobby and tear down the P2P peer.
func leave_lobby() -> void:
	if lobby == null and peer == null:
		# Nothing joined yet, but a create/join may still be in flight: cancel it.
		_op_generation += 1
		_lobby_op_busy = false
		return

	_seats_fixed = false
	is_online = false
	is_host = false
	_op_generation += 1  # cancels any create/join still in flight
	_lobby_op_busy = false

	if lobby != null:
		var local_lobby: HLobby = lobby
		lobby = null
		await _release_lobby(local_lobby)

	_teardown_local()
	lobby_state_changed.emit("left")


## Drop whatever lobby/peer state is left over from a failed or abandoned attempt,
## without telling the UI. Guarantees the next create/join starts clean.
func _discard_stale_session() -> void:
	_op_generation += 1
	if lobby != null:
		var stale: HLobby = lobby
		lobby = null
		await _release_lobby(stale)
	_teardown_local()


func _release_lobby(l: HLobby) -> void:
	if l.is_owner():
		await _await_timeout(l.destroy_async, LOBBY_OP_TIMEOUT)
	else:
		await _await_timeout(l.leave_async, LOBBY_OP_TIMEOUT)


func _destroy_quietly(l: Variant) -> void:
	if l is HLobby:
		await _release_lobby(l)


func _leave_quietly(l: Variant) -> void:
	if l is HLobby:
		await _release_lobby(l)


## Runs an async EOS call but gives up after `seconds` (returns null then). With
## `release_late` a lobby that arrives after the timeout is released instead of leaked.
func _await_timeout(fn: Callable, seconds: float, release_late := false) -> Variant:
	var box := {"done": false, "timed_out": false, "value": null}
	var runner := func() -> void:
		var v: Variant = await fn.call()
		if box.timed_out:
			if release_late and v is HLobby:
				_release_lobby(v)
			return
		box.done = true
		box.value = v
		_op_finished.emit()
	runner.call()
	if not box.done:
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if not box.done:
				box.timed_out = true
				box.done = true
				_op_finished.emit())
		while not box.done:
			await _op_finished
	return box.value


#region Host heartbeat

func _start_heartbeat() -> void:
	_stop_heartbeat()
	_hb_failures = 0
	_hb_timer = Timer.new()
	_hb_timer.wait_time = HEARTBEAT_INTERVAL
	_hb_timer.one_shot = false
	_hb_timer.timeout.connect(_host_heartbeat)
	add_child(_hb_timer)
	_hb_timer.start()


func _stop_heartbeat() -> void:
	if _hb_timer != null:
		_hb_timer.queue_free()
		_hb_timer = null
	_hb_busy = false


## Host-only, pre-game. Touches the lobby so it stays alive, verifies it can still be
## found by join code, and rebuilds it (same code) if the backend dropped it.
func _host_heartbeat() -> void:
	if not is_host or lobby == null or _seats_fixed or _hb_busy:
		return
	_hb_busy = true
	var gen := _op_generation
	var healthy := false

	lobby.add_attribute(ATTR_HEARTBEAT, str(int(Time.get_unix_time_from_system())), EOS.Lobby.LobbyAttributeVisibility.Public)
	var updated: Variant = await _await_timeout(lobby.update_async, LOBBY_OP_TIMEOUT)
	if updated == true and gen == _op_generation:
		var search_args: Array = [
			{key = ATTR_JOIN_CODE, value = join_code, comparison = EOS.ComparisonOp.Equal},
			{key = EOS.Lobby.SEARCH_BUCKET_ID, value = BUCKET_ID, comparison = EOS.ComparisonOp.Equal},
		]
		var found: Variant = await _await_timeout(HLobbies.search_by_attribute_async.bind(search_args), LOBBY_OP_TIMEOUT)
		healthy = found != null and not found.is_empty()

	if gen != _op_generation or not is_host:
		_hb_busy = false
		return
	if healthy:
		_hb_failures = 0
		_hb_busy = false
		return

	_hb_failures += 1
	push_warning("EOSManager: lobby heartbeat failed (%d)." % _hb_failures)
	_hb_busy = false
	if _hb_failures >= HEARTBEAT_FAILS_BEFORE_REBUILD and roster.size() <= 1:
		await _rebuild_lobby_same_code()


## Nobody has joined yet, so it is safe to silently recreate the room under the same code.
func _rebuild_lobby_same_code() -> void:
	if _lobby_op_busy:
		return
	var code := join_code
	var name_keep := lobby_name
	var color_keep := GameGlobals.my_color_idx
	print("[EOSManager] Lobby went stale - rebuilding room %s." % code)
	await _discard_stale_session()
	GameGlobals.my_color_idx = color_keep
	if not await create_lobby(name_keep, code):
		lobby_state_changed.emit("left")

#endregion


func _teardown_local() -> void:
	_stop_heartbeat()
	if peer != null:
		var old_peer = peer
		peer = null
		multiplayer.multiplayer_peer = null   # detach BEFORE closing so nothing polls a dead peer
		# Keep the object alive for a few seconds so late SDK callbacks never hit freed memory.
		_peer_graveyard.append(old_peer)
		old_peer.call_deferred("close")
		get_tree().create_timer(6.0).timeout.connect(func() -> void: _peer_graveyard.erase(old_peer))
	multiplayer.multiplayer_peer = null
	roster = []
	_puid_to_peer_id = {}
	_peer_to_seat = {}
	_config = {}
	_my_seat = -1
	_clients_in_game = {}
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