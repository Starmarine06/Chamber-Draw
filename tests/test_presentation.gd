@tool
extends McpTestSuite

## Pure-logic coverage for the presentation layer: audio event resolution,
## settings persistence, the Juice arc math and the chamber cylinder angles.
## Everything is created off-tree (no _ready side effects).

func suite_name() -> String:
	return "presentation"


# ── AudioManager ──────────────────────────────────────────────────────

func test_audio_variant_key_strips_numeric_suffix() -> void:
	var am: Script = load("res://scripts/audio_manager.gd")
	assert_eq(am.variant_key("gunshot_2.ogg"), "gunshot", "numbered variant")
	assert_eq(am.variant_key("card_play.wav"), "card_play", "plain file keeps underscores")
	assert_eq(am.variant_key("card_play_10.mp3"), "card_play", "multi-digit variant")


func test_audio_variant_key_keeps_non_numeric_suffix() -> void:
	var am: Script = load("res://scripts/audio_manager.gd")
	assert_eq(am.variant_key("timer_urgent.ogg"), "timer_urgent", "word suffix is part of the name")


func test_audio_every_event_has_valid_config() -> void:
	var am: Script = load("res://scripts/audio_manager.gd")
	var events: Dictionary = am.EVENTS
	assert_true(events.size() >= 40, "event table populated")
	for ev: StringName in events:
		var cfg: Array = events[ev]
		assert_eq(cfg.size(), 4, "%s has [fallback, db, jitter, bus]" % ev)
		assert_true(cfg[3] in [&"SFX", &"UI"], "%s routes to a known bus" % ev)


func test_audio_fallbacks_exist_on_disk() -> void:
	var am: Script = load("res://scripts/audio_manager.gd")
	var events: Dictionary = am.EVENTS
	for ev: StringName in events:
		var fb: String = events[ev][0]
		if fb == "":
			continue
		assert_true(ResourceLoader.exists(am.KENNEY + fb + ".ogg"), "%s fallback %s exists" % [ev, fb])


# ── Settings ──────────────────────────────────────────────────────────

func test_settings_round_trip() -> void:
	var path := "user://test_settings_roundtrip.cfg"
	var a: Variant = load("res://scripts/settings.gd").new()
	a.music_volume = 0.3
	a.reduced_motion = true
	a.anim_speed = 1.25
	a.shake_strength = 0.4
	a.save_settings(path)
	var b: Variant = load("res://scripts/settings.gd").new()
	b.load_settings(path)
	assert_true(is_equal_approx(b.music_volume, 0.3), "music volume restored")
	assert_true(b.reduced_motion, "reduced motion restored")
	assert_true(is_equal_approx(b.anim_speed, 1.25), "anim speed restored")
	assert_true(is_equal_approx(b.shake_strength, 0.4), "shake restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	a.free()
	b.free()


func test_settings_reduced_motion_zeroes_shake() -> void:
	var s: Variant = load("res://scripts/settings.gd").new()
	s.shake_strength = 0.8
	assert_true(is_equal_approx(s.shake_factor(), 0.8), "shake passes through")
	s.reduced_motion = true
	assert_eq(s.shake_factor(), 0.0, "reduced motion disables shake")
	s.free()


func test_settings_load_missing_file_keeps_defaults() -> void:
	var s: Variant = load("res://scripts/settings.gd").new()
	var before: float = s.sfx_volume
	s.load_settings("user://definitely_missing_settings.cfg")
	assert_eq(s.sfx_volume, before, "defaults untouched")
	s.free()


# ── Juice math ────────────────────────────────────────────────────────

func test_bezier_endpoints_and_midpoint() -> void:
	var j: Script = load("res://scripts/fx/juice.gd")
	var a := Vector2(0, 0)
	var c := Vector2(50, -100)
	var b := Vector2(100, 0)
	assert_true(j.bezier(a, c, b, 0.0).is_equal_approx(a), "t=0 is start")
	assert_true(j.bezier(a, c, b, 1.0).is_equal_approx(b), "t=1 is end")
	assert_true(j.bezier(a, c, b, 0.5).is_equal_approx(Vector2(50, -50)), "t=0.5 is halfway to control")


func test_arc_control_bows_upward() -> void:
	var j: Script = load("res://scripts/fx/juice.gd")
	var ctrl: Vector2 = j.arc_control(Vector2(0, 100), Vector2(200, 100), 0.25)
	assert_true(is_equal_approx(ctrl.x, 100.0), "centered horizontally")
	assert_true(ctrl.y < 100.0, "control point is above the chord (screen-up)")
	assert_true(is_equal_approx(ctrl.y, 50.0), "height = 25%% of distance")


# ── Chamber cylinder ──────────────────────────────────────────────────

func test_cylinder_hammer_index_at_rest() -> void:
	var cyl: Script = load("res://scripts/fx/chamber_cylinder.gd")
	assert_eq(cyl.chamber_at_hammer(0.0), 0, "chamber 0 starts under the hammer")


func test_cylinder_target_angle_lands_requested_chamber() -> void:
	var cyl: Script = load("res://scripts/fx/chamber_cylinder.gd")
	for idx in range(6):
		var a: float = cyl.target_angle(0.3, 3, idx)
		assert_eq(cyl.chamber_at_hammer(a), idx, "lands on chamber %d" % idx)
		assert_true(a >= 0.3 + TAU * 3.0 - 0.0001, "spins at least the requested turns")


func test_cylinder_emits_on_chamber_crossing() -> void:
	var node: Variant = load("res://scripts/fx/chamber_cylinder.gd").new()
	var hits: Array[int] = []
	node.chamber_passed.connect(func(i: int) -> void: hits.append(i))
	node.angle = TAU  # one full turn in a single step lands back on 0: no crossing
	node.angle = TAU + TAU / 6.0
	assert_eq(hits.size(), 1, "one crossing reported")
	node.free()


# ── Vice emotes ───────────────────────────────────────────────────────

func test_emote_rig_arm_reaches_toward_mouth() -> void:
	var rig: Script = load("res://scripts/fx/emote_rig.gd")
	var q: Quaternion = rig.arm_to(rig.HAND_SMOKE)
	var hand_dir: Vector3 = q * Vector3.DOWN
	var want: Vector3 = (rig.HAND_SMOKE - rig.SHOULDER).normalized()
	assert_true(hand_dir.is_equal_approx(want), "arm points from shoulder to the lips")
	assert_true(hand_dir.y > 0.0 and hand_dir.z > 0.0, "raised up and forward")


func test_emote_rig_head_tilt_looks_up() -> void:
	var rig: Script = load("res://scripts/fx/emote_rig.gd")
	var q: Quaternion = rig.head_tilt(-20.0)
	assert_true((q * Vector3.FORWARD * -1.0).y > 0.0, "negative tilt lifts the face (+Z) upward")


func test_ui_style_is_static_library() -> void:
	var ui: Script = load("res://scripts/ui_style.gd")
	var b: Button = ui.make_button("X", &"primary", Vector2(10, 10), 12)
	assert_eq(b.text, "X", "builds a button without any autoload")
	assert_true(b.get_theme_stylebox("normal") is StyleBoxFlat, "noir stylebox applied")
	b.free()


# ── Chamber-odds gauge ────────────────────────────────────────────────

func test_gauge_loaded_chambers_scale_with_risk() -> void:
	var g: Script = load("res://scripts/ui/deck_gauge.gd")
	assert_eq(g.loaded_chambers(0), 0, "no bombs, no rounds")
	assert_eq(g.loaded_chambers(1), 1, "any risk shows at least one round")
	assert_true(g.loaded_chambers(40) > g.loaded_chambers(10), "more risk, more rounds")
	assert_eq(g.loaded_chambers(100), 6, "capped at a full cylinder")


func test_gauge_risk_colors_escalate() -> void:
	var g: Script = load("res://scripts/ui/deck_gauge.gd")
	assert_ne(g.risk_color(2), g.risk_color(25), "safe and deadly odds look different")


# ── Interactive cigarette ─────────────────────────────────────────────

func test_cigarette_lasts_a_reasonable_number_of_pulls() -> void:
	var smoke: Script = load("res://scripts/fx/first_person_smoke.gd")
	var pulls := ceili(1.0 / float(smoke.BASE_BURN_PER_PULL))
	assert_true(pulls >= 20 and pulls <= 60, "a cigarette lasts 20-60 scroll pulls (got %d)" % pulls)


func test_cigarette_starts_needing_a_fresh_one() -> void:
	var smoke: Script = load("res://scripts/fx/first_person_smoke.gd")
	assert_true(float(smoke.burn) >= 0.0 and float(smoke.burn) <= 1.0, "burn is a 0..1 fraction")


# ── Procedural audio ──────────────────────────────────────────────────

func test_sfx_synth_builds_ice_and_glass() -> void:
	var ss: Script = load("res://scripts/fx/sfx_synth.gd")
	for ev: StringName in [&"ice", &"glass_clink", &"pour", &"gulp", &"exhale"]:
		var vs: Array = ss.variants_for(ev)
		assert_true(vs.size() >= 1, "%s has synthesized variants" % ev)
		assert_true((vs[0] as AudioStreamWAV).data.size() > 1000, "%s has audio data" % ev)


func test_music_synth_note_math() -> void:
	var ms: Script = load("res://scripts/fx/music_synth.gd")
	assert_true(is_equal_approx(ms.midi_hz(69.0), 440.0), "A4 = 440 Hz")
	assert_true(is_equal_approx(ms.midi_hz(57.0), 220.0), "A3 = 220 Hz")


func test_whiskey_glass_lasts_a_reasonable_number_of_sips() -> void:
	var d: Script = load("res://scripts/fx/first_person_drink.gd")
	var sips := ceili(1.0 / float(d.BASE_SIP_PER_TICK))
	assert_true(sips >= 10 and sips <= 40, "a glass lasts 10-40 sips (got %d)" % sips)
