extends RefCounted

## Static facade over the AudioManager node, so scripts never depend on the
## autoload's global name (use `const Sound := preload("res://scripts/sound.gd")`).
## The node is created on demand if the autoload isn't registered.

const UIStyle := preload("res://scripts/ui_style.gd")

static func play(event: StringName, vol_offset_db: float = 0.0, pitch: float = 1.0) -> void:
	var am: Node = UIStyle.audio()
	if am:
		am.call("play", event, vol_offset_db, pitch)

static func play_music(track: StringName, fade: float = 1.2) -> void:
	var am: Node = UIStyle.audio()
	if am:
		am.call("play_music", track, fade)

static func duck(db: float = -14.0, time: float = 0.4) -> void:
	var am: Node = UIStyle.audio()
	if am:
		am.call("duck", db, time)

static func unduck(time: float = 0.8) -> void:
	var am: Node = UIStyle.audio()
	if am:
		am.call("unduck", time)

static func play_loop(event: StringName, vol_offset_db: float = 0.0) -> void:
	var am: Node = UIStyle.audio()
	if am:
		am.call("play_loop", event, vol_offset_db)

static func stop_loop(event: StringName, fade: float = 0.3) -> void:
	var am: Node = UIStyle.audio()
	if am:
		am.call("stop_loop", event, fade)
