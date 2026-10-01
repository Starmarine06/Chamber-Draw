extends Node

## Voice chat over the EOS lobby RTC room (child of the EOSManager autoload, `EOSManager.voice`).
##
## The lobby is created with an RTC room (see EOSManager._create_lobby_inner) and every member
## auto-joins it, starting muted. This node decides — every frame — whether the microphone should
## be live and tells EOS only when that changes:
##   mic live = joined room AND NOT mic-muted AND NOT deafened AND (open mic OR push-to-talk held)
##
## Settings are static + saved to user://voice.cfg so the Settings panel and the lobby/game HUD
## can read and change them without reaching this node.

signal state_changed
signal speaking_changed

enum Mode { OPEN, PUSH_TO_TALK }

const Keybinds := preload("res://scripts/keybinds.gd")

const SAVE_PATH := "user://voice.cfg"
## EOS volumes run 0..100 with 50 = unity gain; the UI works in "gain" 0..2 (1.0 = 100%).
const EOS_UNITY := 50.0
const CALL_TIMEOUT := 3.0

static var mode: int = Mode.PUSH_TO_TALK
static var mic_muted := false
static var deafened := false
static var output_gain := 1.0
static var mic_gain := 1.0
static var _loaded := false

var available := false          # lobby has a connected RTC room
var transmitting := false       # microphone is live right now

var _was_connected := false
var _sent: int = -1             # last audio status confirmed to EOS (-1 unknown)
var _sending_busy := false
var _ptt_down := false
var _speaking := {}             # puid -> true while that member is talking
var _volumes_dirty := true


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mode = clampi(int(cfg.get_value("voice", "mode", mode)), 0, 1)
	mic_muted = bool(cfg.get_value("voice", "mic_muted", false))
	output_gain = clampf(float(cfg.get_value("voice", "output_gain", 1.0)), 0.0, 2.0)
	mic_gain = clampf(float(cfg.get_value("voice", "mic_gain", 1.0)), 0.0, 2.0)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("voice", "mode", mode)
	cfg.set_value("voice", "mic_muted", mic_muted)
	cfg.set_value("voice", "output_gain", output_gain)
	cfg.set_value("voice", "mic_gain", mic_gain)
	cfg.save(SAVE_PATH)


func _ready() -> void:
	_ensure()
	set_process_unhandled_key_input(true)


# ── Settings API (UI calls these) ────────────────────────────────────────

func set_mode(m: int) -> void:
	mode = clampi(m, 0, 1)
	save()
	state_changed.emit()


func toggle_mic_mute() -> void:
	mic_muted = not mic_muted
	save()
	state_changed.emit()


func toggle_deafen() -> void:
	deafened = not deafened
	_volumes_dirty = true
	state_changed.emit()


func set_output_gain(g: float) -> void:
	output_gain = clampf(g, 0.0, 2.0)
	_volumes_dirty = true
	save()


func set_mic_gain(g: float) -> void:
	mic_gain = clampf(g, 0.0, 2.0)
	_volumes_dirty = true
	save()


# ── Queries ──────────────────────────────────────────────────────────────

func is_speaking(puid: String) -> bool:
	return _speaking.has(puid)


func is_player_muted(puid: String) -> bool:
	var m := _member(puid)
	return m != null and m.rtc_state.is_locally_muted


## Locally mute / unmute one other player for this machine only.
func toggle_player_mute(puid: String) -> void:
	var m := _member(puid)
	if m == null or puid == HAuth.product_user_id:
		return
	await m.toggle_mute_member_async()
	state_changed.emit()


## Short HUD text such as "PUSH TO TALK [V]" / "MIC MUTED".
func status_text() -> String:
	if not available:
		return "VOICE OFF"
	if deafened:
		return "DEAFENED"
	if mic_muted:
		return "MIC MUTED"
	if mode == Mode.OPEN:
		return "OPEN MIC"
	return "TALKING" if transmitting else "PUSH TO TALK [%s]" % Keybinds.label(&"ptt")


# ── Runtime ──────────────────────────────────────────────────────────────

func _lobby() -> HLobby:
	var mgr := get_parent()
	return mgr.get("lobby") as HLobby if mgr != null else null


func _member(puid: String) -> HLobbyMember:
	var l := _lobby()
	return l.get_member_by_product_user_id(puid) if l != null else null


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if Keybinds.matches(event, &"mute_mic"):
		toggle_mic_mute()
	elif Keybinds.matches(event, &"deafen"):
		toggle_deafen()


func _process(_delta: float) -> void:
	var l := _lobby()
	var connected := l != null and l.rtc_room_enabled and l.rtc_room_connected and l.rtc_room_name != ""
	if connected != available:
		available = connected
		state_changed.emit()
	if connected != _was_connected:
		_was_connected = connected
		_sent = -1                 # a fresh room starts muted: resend our state
		_volumes_dirty = true
		_speaking.clear()
	if not connected:
		transmitting = false
		return

	_poll_speaking(l)

	var key := Keybinds.key_of(&"ptt")
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var down := key != KEY_NONE and not typing and Input.is_key_pressed(key as Key)
	if down != _ptt_down:
		_ptt_down = down
		state_changed.emit()

	var want_live := not mic_muted and not deafened and (mode == Mode.OPEN or _ptt_down)
	if want_live != transmitting:
		transmitting = want_live
		state_changed.emit()
	var want := EOS.RTCAudio.AudioStatus.Enabled if want_live else EOS.RTCAudio.AudioStatus.Disabled
	if int(want) != _sent and not _sending_busy:
		_push_sending(l.rtc_room_name, int(want))
	if _volumes_dirty:
		_volumes_dirty = false
		_push_volumes(l.rtc_room_name)


func _poll_speaking(l: HLobby) -> void:
	var now := {}
	for m in l.members:
		if m.rtc_state.is_talking and not m.rtc_state.is_hard_muted:
			now[m.product_user_id] = true
	if now.hash() != _speaking.hash():
		_speaking = now
		speaking_changed.emit()


func _push_sending(room: String, status: int) -> void:
	_sending_busy = true
	var opts := EOS.RTCAudio.UpdateSendingOptions.new()
	opts.room_name = room
	opts.audio_status = status
	var box := {"done": false}
	var on_done := func(_d: Variant) -> void: box.done = true
	IEOS.rtc_audio_interface_update_sending_callback.connect(on_done, CONNECT_ONE_SHOT)
	EOS.RTCAudio.RTCAudioInterface.update_sending(opts)
	var waited := 0.0
	while not box.done and waited < CALL_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if IEOS.rtc_audio_interface_update_sending_callback.is_connected(on_done):
		IEOS.rtc_audio_interface_update_sending_callback.disconnect(on_done)
	if box.done:
		_sent = status
	_sending_busy = false


func _push_volumes(room: String) -> void:
	var out_opts := EOS.RTCAudio.UpdateReceivingVolumeOptions.new()
	out_opts.room_name = room
	out_opts.volume = 0.0 if deafened else minf(output_gain * EOS_UNITY, 100.0)
	EOS.RTCAudio.RTCAudioInterface.update_receiving_volume(out_opts)
	var in_opts := EOS.RTCAudio.UpdateSendingVolumeOptions.new()
	in_opts.room_name = room
	in_opts.volume = minf(mic_gain * EOS_UNITY, 100.0)
	EOS.RTCAudio.RTCAudioInterface.update_sending_volume(in_opts)
