extends Node

## Player preferences (audio levels, display, motion), persisted to
## user://settings.cfg. Autoload "Settings". Other systems read the fields
## directly and listen to `changed` to re-apply.

signal changed

const SAVE_PATH := "user://settings.cfg"

## Linear volumes, 0..1.
var master_volume: float = 0.9
var music_volume: float = 0.55
var sfx_volume: float = 0.85
var ui_volume: float = 0.7
## The game always runs fullscreen (borderless, native resolution).
var fullscreen: bool = true
## Disables screen shake, flashes and hit-stops.
var reduced_motion: bool = false
## Multiplier on juice-animation speed (higher = faster).
var anim_speed: float = 1.0
## 0..1 strength of camera/screen shake.
var shake_strength: float = 1.0

func _ready() -> void:
	load_settings()
	apply_display()

func load_settings(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui", ui_volume)), 0.0, 1.0)
	reduced_motion = bool(cfg.get_value("motion", "reduced", reduced_motion))
	anim_speed = clampf(float(cfg.get_value("motion", "anim_speed", anim_speed)), 0.5, 2.0)
	shake_strength = clampf(float(cfg.get_value("motion", "shake", shake_strength)), 0.0, 1.0)

func save_settings(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("motion", "reduced", reduced_motion)
	cfg.set_value("motion", "anim_speed", anim_speed)
	cfg.set_value("motion", "shake", shake_strength)
	cfg.save(path)

## Call after changing any field: persists, re-applies display, notifies.
func commit() -> void:
	save_settings()
	apply_display()
	changed.emit()

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	fullscreen = true
	var mode := DisplayServer.window_get_mode()
	if mode != DisplayServer.WINDOW_MODE_FULLSCREEN and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

## Effective shake multiplier (0 when reduced motion is on).
func shake_factor() -> float:
	return 0.0 if reduced_motion else shake_strength
