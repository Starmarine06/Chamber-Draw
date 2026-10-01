extends Node

## Central audio for Chamber Draw (autoload "AudioManager").
##
## - Buses: Master -> Music / SFX / UI (created at runtime if the project has
##   no bus layout). SFX gets a light room reverb.
## - SFX are *semantic events* (`play(&"card_play")`). Each event resolves to
##   every file in res://assets/audio/sfx/ named `<event>.ogg|wav|mp3` or
##   `<event>_<n>.ogg|...` (random variant per play). If none exist yet the
##   event falls back to a Kenney UI-pack sound, so the game always has audio
##   even before the CC0 packs are dropped in. See assets/audio/README.md.
## - A pool of players means rapid sounds never cut each other off.
## - Music: `play_music(&"menu")` crossfades to res://assets/audio/music/<name>.*;
##   `duck()` / `unduck()` lower it under dramatic moments.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const KENNEY := "res://assets/imported_assets/kenney_ui-pack/Sounds/"
const AUDIO_EXTS: Array[String] = ["ogg", "wav", "mp3"]
const POOL_SIZE := 12
const SfxSynth := preload("res://scripts/fx/sfx_synth.gd")
const MusicSynth := preload("res://scripts/fx/music_synth.gd")
const MUSIC_CACHE := "user://music_%s_v1.wav"

## event -> [fallback kenney file ("" = silent), base volume dB, pitch jitter, bus]
const EVENTS := {
	# Cards
	&"card_play": ["click-a", -6.0, 0.08, &"SFX"],
	&"card_draw": ["tap-a", -6.0, 0.08, &"SFX"],
	&"card_slide": ["tap-a", -8.0, 0.1, &"SFX"],
	&"card_flip": ["click-a", -8.0, 0.06, &"SFX"],
	&"deal": ["tap-a", -9.0, 0.12, &"SFX"],
	&"shuffle": ["tap-b", -6.0, 0.04, &"SFX"],
	&"forced_draw": ["tap-b", -7.0, 0.1, &"SFX"],
	&"chip": ["click-b", -6.0, 0.1, &"SFX"],
	# Card actions
	&"draw_attack": ["switch-b", -6.0, 0.0, &"SFX"],
	&"stack": ["switch-b", -5.0, 0.04, &"SFX"],
	&"skip": ["click-b", -6.0, 0.03, &"SFX"],
	&"reverse": ["click-b", -6.0, 0.03, &"SFX"],
	&"swap": ["tap-b", -6.0, 0.03, &"SFX"],
	&"peek": ["tap-b", -6.0, 0.03, &"SFX"],
	&"rotate": ["tap-b", -6.0, 0.03, &"SFX"],
	&"extra_life": ["click-b", -6.0, 0.0, &"SFX"],
	&"jump_in": ["switch-b", -5.0, 0.03, &"SFX"],
	&"wild": ["click-b", -6.0, 0.03, &"SFX"],
	# Turn flow
	&"your_turn": ["switch-a", -6.0, 0.0, &"SFX"],
	&"banner": ["switch-a", -8.0, 0.02, &"SFX"],
	&"timer_tick": ["tap-b", -12.0, 0.0, &"SFX"],
	&"timer_urgent": ["tap-b", -7.0, 0.0, &"SFX"],
	&"timer_expired": ["switch-b", -6.0, 0.0, &"SFX"],
	&"end_turn": ["switch-a", -8.0, 0.02, &"SFX"],
	# Bomb / chamber
	&"bomb_drawn": ["switch-b", -4.0, 0.0, &"SFX"],
	&"diffuse_prompt": ["switch-b", -6.0, 0.0, &"SFX"],
	&"diffuse": ["click-b", -5.0, 0.0, &"SFX"],
	&"chamber_start": ["switch-a", -5.0, 0.0, &"SFX"],
	&"cylinder_spin": ["", -6.0, 0.0, &"SFX"],
	&"cylinder_click": ["tap-b", -8.0, 0.05, &"SFX"],
	&"hammer_cock": ["click-b", -4.0, 0.0, &"SFX"],
	&"heartbeat": ["", -4.0, 0.0, &"SFX"],
	&"sniff": ["", -2.0, 0.0, &"SFX"],
	&"gunshot": ["switch-b", 0.0, 0.0, &"SFX"],
	&"blank": ["tap-b", -4.0, 0.0, &"SFX"],
	&"backfire": ["switch-b", -3.0, 0.0, &"SFX"],
	&"lucky": ["click-b", -4.0, 0.0, &"SFX"],
	&"eliminate": ["switch-b", -4.0, 0.0, &"SFX"],
	&"respawn": ["switch-b", -5.0, 0.0, &"SFX"],
	&"vote": ["switch-b", -6.0, 0.0, &"SFX"],
	&"win": ["switch-b", -3.0, 0.0, &"SFX"],
	&"lose": ["switch-b", -3.0, 0.0, &"SFX"],
	# Vice emotes
	&"lighter": ["click-b", -8.0, 0.05, &"SFX"],
	&"lighter_close": ["tap-a", -8.0, 0.05, &"SFX"],
	&"pack": ["tap-a", -9.0, 0.08, &"SFX"],
	&"inhale": ["", -8.0, 0.05, &"SFX"],
	&"exhale": ["", -6.0, 0.05, &"SFX"],
	&"gulp": ["tap-b", -9.0, 0.05, &"SFX"],
	&"glass_clink": ["tap-a", -6.0, 0.08, &"SFX"],
	&"ice": ["tap-a", -7.0, 0.1, &"SFX"],
	&"pour": ["", -5.0, 0.04, &"SFX"],
	# UI
	&"button": ["switch-a", -8.0, 0.04, &"UI"],
	&"hover": ["", -14.0, 0.06, &"UI"],
	&"toggle": ["switch-a", -9.0, 0.04, &"UI"],
	&"invalid": ["switch-b", -8.0, 0.0, &"UI"],
	&"pause": ["click-b", -8.0, 0.0, &"UI"],
}

var _streams: Dictionary = {}          # event -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _pool_next: int = 0
var _last_played_ms: Dictionary = {}   # event -> msec, anti-spam
var _loops: Dictionary = {}            # event -> AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_track: StringName = &""
var _music_base_db: float = -6.0
var _duck_db: float = 0.0
var _duck_tween: Tween
var _settings: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_music_active = _music_a
	_scan_sfx()
	_settings = get_node_or_null("/root/Settings")
	if _settings:
		_settings.changed.connect(apply_volumes)
	apply_volumes()

# ── Buses ─────────────────────────────────────────────────────────────

func _ensure_buses() -> void:
	for bus_name in [&"Music", &"SFX", &"UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
			if bus_name == &"SFX":
				var reverb := AudioEffectReverb.new()
				reverb.room_size = 0.35
				reverb.damping = 0.6
				reverb.wet = 0.08
				reverb.dry = 1.0
				AudioServer.add_bus_effect(idx, reverb)

func apply_volumes() -> void:
	var master := 0.9
	var music := 0.55
	var sfx := 0.85
	var ui := 0.7
	if _settings:
		master = _settings.master_volume
		music = _settings.music_volume
		sfx = _settings.sfx_volume
		ui = _settings.ui_volume
	_set_bus_linear(&"Master", master)
	_set_bus_linear(&"Music", music)
	_set_bus_linear(&"SFX", sfx)
	_set_bus_linear(&"UI", ui)

func _set_bus_linear(bus_name: StringName, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))

# ── SFX ───────────────────────────────────────────────────────────────

## Strips extension and a trailing `_<digits>` variant suffix:
## "gunshot_2.ogg" -> "gunshot", "card_play.wav" -> "card_play".
static func variant_key(file_name: String) -> String:
	var base := file_name.get_basename()
	var us := base.rfind("_")
	if us > 0 and base.substr(us + 1).is_valid_int():
		return base.substr(0, us)
	return base

func _list_audio(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in ResourceLoader.list_directory(dir):
		if f.get_extension().to_lower() in AUDIO_EXTS:
			out.append(f)
	return out

func _scan_sfx() -> void:
	_streams.clear()
	for f in _list_audio(SFX_DIR):
		var key := StringName(variant_key(f))
		var stream := load(SFX_DIR + f) as AudioStream
		if stream == null:
			continue
		if not _streams.has(key):
			_streams[key] = []
		_streams[key].append(stream)
	# Fallbacks for events with no custom file yet: synthesized sounds first
	# (ice, glass, pour, gulp, breaths, heartbeat), then the Kenney UI blips.
	for ev in EVENTS:
		if _streams.has(ev):
			continue
		if SfxSynth.has_synth(ev):
			_streams[ev] = SfxSynth.variants_for(ev)
			continue
		var fb: String = EVENTS[ev][0]
		if fb == "":
			continue
		var s := load(KENNEY + fb + ".ogg") as AudioStream
		if s:
			_streams[ev] = [s]

## True if the event resolved to a custom (non-Kenney) file.
func has_custom(event: StringName) -> bool:
	if not _streams.has(event):
		return false
	var arr: Array = _streams[event]
	return arr.size() > 0 and not (arr[0] as AudioStream).resource_path.begins_with(KENNEY)

## Plays a semantic sound event. Unknown / silent events are a safe no-op.
func play(event: StringName, vol_offset_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(event):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(event, -1000)) < 28:
		return  # same sound twice in one frame reads as one louder click
	_last_played_ms[event] = now
	var arr: Array = _streams[event]
	var stream: AudioStream = arr[randi() % arr.size()]
	var cfg: Array = EVENTS.get(event, ["", -6.0, 0.05, &"SFX"])
	var p := _next_player()
	p.stream = stream
	p.bus = cfg[3]
	p.volume_db = float(cfg[1]) + vol_offset_db
	var jitter: float = cfg[2]
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	p.play()

func _next_player() -> AudioStreamPlayer:
	for i in range(POOL_SIZE):
		var p := _pool[(_pool_next + i) % POOL_SIZE]
		if not p.playing:
			_pool_next = (_pool_next + i + 1) % POOL_SIZE
			return p
	var oldest := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % POOL_SIZE
	return oldest

## Starts a looping event (e.g. heartbeat). No-op if already looping or silent.
func play_loop(event: StringName, vol_offset_db: float = 0.0) -> void:
	if _loops.has(event) or not _streams.has(event):
		return
	var arr: Array = _streams[event]
	var stream: AudioStream = (arr[0] as AudioStream).duplicate()
	_set_stream_loop(stream, true)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"SFX"
	p.volume_db = float(EVENTS.get(event, ["", -6.0])[1]) + vol_offset_db
	add_child(p)
	p.play()
	_loops[event] = p

func stop_loop(event: StringName, fade: float = 0.3) -> void:
	if not _loops.has(event):
		return
	var p: AudioStreamPlayer = _loops[event]
	_loops.erase(event)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.queue_free)

func _set_stream_loop(stream: AudioStream, on: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = on
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = on
	elif stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		if on and w.loop_end <= 0 and w.data.size() > 0:
			var frame_bytes := (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
			w.loop_end = w.data.size() / frame_bytes

# ── Music ─────────────────────────────────────────────────────────────

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.volume_db = -60.0
	add_child(p)
	return p

func _find_music(track: StringName) -> AudioStream:
	for ext in AUDIO_EXTS:
		var path := MUSIC_DIR + String(track) + "." + ext
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null

## Crossfades to a music track. Missing tracks fade the current one out.
func play_music(track: StringName, fade: float = 1.2) -> void:
	if track == _music_track and _music_active.playing:
		return
	_music_track = track
	var stream := _find_music(track)
	if stream == null:
		# No music file: use the procedural lounge track (cached after the first
		# render; rendered on a worker thread so nothing hitches).
		stream = _cached_synth_music(track)
		if stream == null:
			_render_synth_music(track, fade)
	_start_music_stream(stream, fade)

## Crossfades from the current music player to `stream` (null = fade out only).
func _start_music_stream(stream: AudioStream, fade: float) -> void:
	var old := _music_active
	var nxt := _music_b if _music_active == _music_a else _music_a
	if old.playing:
		var tw_out := create_tween()
		tw_out.tween_property(old, "volume_db", -60.0, fade)
		tw_out.tween_callback(old.stop)
	if stream == null:
		return
	stream = stream.duplicate()
	_set_stream_loop(stream, true)
	nxt.stream = stream
	nxt.volume_db = -60.0
	nxt.play()
	_music_active = nxt
	var tw_in := create_tween()
	tw_in.tween_property(nxt, "volume_db", _music_base_db + _duck_db, fade)

func _cached_synth_music(track: StringName) -> AudioStream:
	var path := MUSIC_CACHE % String(track)
	if not FileAccess.file_exists(path):
		return null
	var w := AudioStreamWAV.load_from_file(path)
	if w == null:
		return null
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / 2
	return w

var _rendering: Dictionary = {}

func _render_synth_music(track: StringName, fade: float) -> void:
	if _rendering.has(track):
		return
	_rendering[track] = true
	var name_s := String(track)
	WorkerThreadPool.add_task(func() -> void:
		var w: AudioStreamWAV = MusicSynth.render(name_s)
		_on_synth_music_ready.call_deferred(track, w, fade))

func _on_synth_music_ready(track: StringName, w: AudioStreamWAV, fade: float) -> void:
	_rendering.erase(track)
	if w == null:
		return
	w.save_to_wav(MUSIC_CACHE % String(track))
	if _music_track == track:
		_start_music_stream(w, fade)

func stop_music(fade: float = 1.0) -> void:
	_music_track = &""
	for p in [_music_a, _music_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, fade)
			tw.tween_callback(p.stop)

## Lowers music by `db` (negative) over `time` — e.g. under the chamber.
func duck(db: float = -14.0, time: float = 0.4) -> void:
	_duck_db = db
	_tween_music_to(_music_base_db + db, time)

func unduck(time: float = 0.8) -> void:
	_duck_db = 0.0
	_tween_music_to(_music_base_db, time)

func _tween_music_to(db: float, time: float) -> void:
	if not _music_active or not _music_active.playing:
		return
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_music_active, "volume_db", db, time)
