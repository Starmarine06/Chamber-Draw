extends RefCounted

## Rebindable controls, saved to user://keybinds.cfg. Static-only (no autoload), so
## any script can `const Keybinds := preload("res://scripts/keybinds.gd")`.
##
## Number keys 1-9/0 (hand cards), the arrow keys (deck A/B), Esc and L stay fixed.
## Two actions may share a key only when they are never active at the same time
## (see GROUP): the "global" actions conflict with everything.

const SAVE_PATH := "user://keybinds.cfg"

## id, label, default key, group, listed in the Controls screen?
const ACTIONS := [
	{"id": &"draw_a", "label": "Draw from Deck A", "key": KEY_A, "group": "turn", "shown": true},
	{"id": &"draw_b", "label": "Draw from Deck B", "key": KEY_B, "group": "turn", "shown": true},
	{"id": &"end_turn", "label": "End turn", "key": KEY_ENTER, "group": "turn", "shown": true},
	{"id": &"smoke", "label": "Smoke / put away", "key": KEY_S, "group": "global", "shown": true},
	{"id": &"drink", "label": "Drink / set down", "key": KEY_W, "group": "global", "shown": true},
	{"id": &"change_vice", "label": "Change brand (in a vice)", "key": KEY_B, "group": "vice", "shown": true},
	{"id": &"free_cursor", "label": "Free / hide the cursor", "key": KEY_TAB, "group": "global", "shown": true},
	{"id": &"kill_high", "label": "End the high (sober up)", "key": KEY_K, "group": "global", "shown": true},
	{"id": &"ptt", "label": "Voice: push to talk (hold)", "key": KEY_V, "group": "global", "shown": true},
	{"id": &"mute_mic", "label": "Voice: mute / unmute mic", "key": KEY_M, "group": "global", "shown": true},
	{"id": &"deafen", "label": "Voice: deafen / undeafen", "key": KEY_N, "group": "global", "shown": true},
	{"id": &"line", "label": "Waiter's tray", "key": KEY_C, "group": "global", "shown": false},
]

const DEFAULT_SENSITIVITY := 0.11

static var sensitivity: float = DEFAULT_SENSITIVITY
## Bumped on every change so UI that shows key names can refresh itself.
static var version: int = 0

static var _map: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_map = {}
	for a in ACTIONS:
		_map[a.id] = int(a.key)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for a in ACTIONS:
			if cfg.has_section_key("keys", String(a.id)):
				_map[a.id] = int(cfg.get_value("keys", String(a.id), a.key))
		sensitivity = clampf(float(cfg.get_value("mouse", "sensitivity", DEFAULT_SENSITIVITY)), 0.02, 0.5)


static func save() -> void:
	_ensure()
	var cfg := ConfigFile.new()
	for a in ACTIONS:
		cfg.set_value("keys", String(a.id), _map[a.id])
	cfg.set_value("mouse", "sensitivity", sensitivity)
	cfg.save(SAVE_PATH)


static func key_of(id: StringName) -> int:
	_ensure()
	return int(_map.get(id, KEY_NONE))


static func _norm(code: int) -> int:
	return KEY_ENTER if code == KEY_KP_ENTER else code


## Does this key event trigger the action?
static func matches(event: InputEvent, id: StringName) -> bool:
	var ke := event as InputEventKey
	if ke == null or not ke.pressed:
		return false
	var want := key_of(id)
	return want != KEY_NONE and _norm(ke.keycode) == want


static func label(id: StringName) -> String:
	return key_name(key_of(id))


static func key_name(code: int) -> String:
	if code == KEY_NONE:
		return "-"
	var s := OS.get_keycode_string(code)
	return s if not s.is_empty() else "?"


static func _group(id: StringName) -> String:
	for a in ACTIONS:
		if a.id == id:
			return str(a.group)
	return "global"


static func _conflicts(a: StringName, b: StringName) -> bool:
	var ga := _group(a)
	var gb := _group(b)
	return ga == "global" or gb == "global" or ga == gb


## Binds `code` to `id`. Any conflicting action loses its key (returned so the UI can say so).
static func set_key(id: StringName, code: int) -> StringName:
	_ensure()
	code = _norm(code)
	var displaced: StringName = &""
	for a in ACTIONS:
		if a.id != id and int(_map[a.id]) == code and _conflicts(a.id, id):
			_map[a.id] = KEY_NONE
			displaced = a.id
	_map[id] = code
	version += 1
	save()
	return displaced


static func label_of_action(id: StringName) -> String:
	for a in ACTIONS:
		if a.id == id:
			return str(a.label)
	return String(id)


static func sens() -> float:
	_ensure()
	return sensitivity


static func set_sensitivity(v: float) -> void:
	_ensure()
	sensitivity = clampf(v, 0.02, 0.5)
	version += 1
	save()


static func reset_defaults() -> void:
	_loaded = true
	_map = {}
	for a in ACTIONS:
		_map[a.id] = int(a.key)
	sensitivity = DEFAULT_SENSITIVITY
	version += 1
	save()
