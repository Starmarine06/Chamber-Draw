extends RefCounted

## Procedural sound effects (no asset files needed): ice cubes, glass clinks,
## pouring, gulps, breaths and a heartbeat. AudioManager uses these for any
## event that has no custom file in assets/audio/sfx/ (they beat the Kenney UI
## blips for realism). Each call can return several variants (random per play).

const RATE := 22050

## Event → generator. Returns Array[AudioStreamWAV] (variants).
static func variants_for(event: StringName) -> Array:
	match event:
		&"ice": return [_ice(1), _ice(2), _ice(3), _ice(4)]
		&"glass_clink": return [_glass(1), _glass(2)]
		&"pour": return [_pour(1)]
		&"gulp": return [_gulp(1), _gulp(2), _gulp(3)]
		&"inhale": return [_breath(1, 0.55, false), _breath(2, 0.5, false)]
		&"exhale": return [_breath(3, 1.1, true), _breath(4, 1.3, true)]
		&"heartbeat": return [_heartbeat()]
		&"sniff": return [_sniff(1), _sniff(2)]
		&"gunshot": return [_gunshot(1), _gunshot(2)]
		&"cylinder_click": return [_click(1, 1.0), _click(2, 0.85), _click(3, 1.15)]
		&"cylinder_spin": return [_ratchet(1)]
		&"hammer_cock": return [_hammer_cock()]
		&"blank": return [_dry_click()]
		&"backfire": return [_backfire()]
	return []

static func has_synth(event: StringName) -> bool:
	return event in [&"ice", &"glass_clink", &"pour", &"gulp", &"inhale", &"exhale", &"heartbeat", &"sniff",
		&"gunshot", &"cylinder_click", &"cylinder_spin", &"hammer_cock", &"blank", &"backfire"]

# ── Building blocks ───────────────────────────────────────────────────

static func _wav(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = buf.size()
	return w

static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

## Adds a decaying sine "ping" (glassy partial) at time t0.
static func _ping(b: PackedFloat32Array, t0: float, freq: float, amp: float, decay: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(decay * 6.0 * RATE), b.size() - start)
	var w := TAU * freq / RATE
	for i in n:
		b[start + i] += sin(w * i) * amp * exp(-float(i) / (decay * RATE))

static func _noise_burst(b: PackedFloat32Array, rng: RandomNumberGenerator, t0: float, dur: float, amp: float, smooth: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - start)
	var lp := 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * smooth
		b[start + i] += lp * amp * exp(-float(i) / (dur * 0.25 * RATE))

# ── Sounds ────────────────────────────────────────────────────────────

## Ice: a cluster of bright, short glassy ticks — cubes knocking the glass.
static func _ice(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + seed_v
	var b := _buf(0.45)
	var t := 0.0
	var hits := rng.randi_range(3, 5)
	for h in hits:
		var amp := 1.0 if h == 0 else rng.randf_range(0.25, 0.7)
		var base := rng.randf_range(2300.0, 4200.0)
		_ping(b, t, base, amp, rng.randf_range(0.012, 0.03))
		_ping(b, t, base * rng.randf_range(1.45, 1.7), amp * 0.5, rng.randf_range(0.008, 0.02))
		_ping(b, t, base * rng.randf_range(2.3, 2.8), amp * 0.25, 0.008)
		_noise_burst(b, rng, t, 0.01, amp * 0.25, 0.9)
		t += rng.randf_range(0.03, 0.09)
	return _wav(b)

## Glass on glass / glass on felt: a clear ring with a soft knock.
static func _glass(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8000 + seed_v
	var b := _buf(0.7)
	var f := rng.randf_range(1650.0, 2050.0)
	_ping(b, 0.0, f, 0.8, 0.12)
	_ping(b, 0.0, f * 2.71, 0.35, 0.07)
	_ping(b, 0.0, f * 4.13, 0.18, 0.04)
	_ping(b, 0.0, 180.0, 0.5, 0.03)  # knock body
	_noise_burst(b, rng, 0.0, 0.02, 0.3, 0.6)
	return _wav(b)

## Pour: lowpassed noise with a glug modulation whose pitch rises as it fills.
static func _pour(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9000 + seed_v
	var dur := 1.5
	var b := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t / 0.08, 1.0) * minf((dur - t) / 0.2, 1.0)
		var cutoff := 0.08 + 0.06 * (t / dur)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var glug := 0.55 + 0.45 * sin(TAU * (7.0 + 5.0 * t / dur) * t)
		var tone := sin(TAU * (220.0 + 260.0 * t / dur) * t) * 0.12
		b[i] = (lp2 * 3.0 * glug + tone * glug) * env
	return _wav(b)

## Gulp: a short low pitch drop with a soft throat click.
static func _gulp(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9500 + seed_v
	var b := _buf(0.3)
	var f0 := rng.randf_range(210.0, 260.0)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(f0, 85.0, minf(t / 0.16, 1.0))
		ph += TAU * f / RATE
		b[i] = sin(ph) * exp(-t / 0.07) * minf(t / 0.01, 1.0)
	_noise_burst(b, rng, 0.0, 0.015, 0.4, 0.5)
	return _wav(b)

## Breath: breathy noise swell (inhale = shorter, with faint tobacco crackle).
## A sharp, wet double sniff: two fast high-passed noise bursts with a thump.
static func _sniff(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20000 + seed_v
	var b := _buf(0.7)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := 0.0
		if t < 0.28:
			env = sin(PI * t / 0.28) * (0.5 + 0.5 * (t / 0.28))
		elif t > 0.3 and t < 0.55:
			env = 0.7 * sin(PI * (t - 0.3) / 0.25)
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.55
		b[i] = (n - lp * 0.6) * env
	_thump(b, 0.5, 0.12, 60.0, 110.0, 8.0, 0.35)
	return _wav(b)

static func _breath(seed_v: int, dur: float, out: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10000 + seed_v
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var x := t / dur
		var env := sin(PI * x) * (1.0 - 0.4 * x if out else 0.6 + 0.4 * x)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.18 if out else 0.3)
		b[i] = lp * env
	if not out:
		for k in rng.randi_range(5, 9):
			_noise_burst(b, rng, rng.randf_range(0.05, dur - 0.05), 0.006, 0.5, 0.95)
	return _wav(b)

## Adds a sine sweep that falls from f_hi to f_lo (kick / cannon body).
static func _thump(b: PackedFloat32Array, t0: float, dur: float, f_lo: float, f_hi: float, rate: float, amp: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - start)
	for i in n:
		var t := float(i) / RATE
		var phase := TAU * (f_lo * t + (f_hi - f_lo) / rate * (1.0 - exp(-rate * t)))
		b[start + i] += sin(phase) * amp * exp(-t / (dur * 0.3))

## Revolver shot: sharp noise crack, chest-thump sweep and a rumbling room tail.
static func _gunshot(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + seed_v
	var b := _buf(1.7)
	_noise_burst(b, rng, 0.0, 0.05, 1.0, 0.9)
	_noise_burst(b, rng, 0.0, 0.3, 0.75, 0.2)
	_thump(b, 0.0, 0.45, 38.0, 170.0, 16.0, 1.1)
	_noise_burst(b, rng, 0.07, 1.4, 0.22, 0.04)
	_noise_burst(b, rng, 0.21, 0.9, 0.12, 0.06)
	return _wav(b)

## One metallic ratchet tick (cylinder passing a chamber).
static func _click(seed_v: int, pitch: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9200 + seed_v
	var b := _buf(0.09)
	_ping(b, 0.0, 3100.0 * pitch, 0.6, 0.004)
	_ping(b, 0.0, 1650.0 * pitch, 0.5, 0.007)
	_ping(b, 0.002, 5200.0 * pitch, 0.25, 0.002)
	_noise_burst(b, rng, 0.0, 0.012, 0.5, 0.7)
	return _wav(b)

## Cylinder spin: a ratchet that starts fast and slows to a stop (~2.2 s).
static func _ratchet(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9300 + seed_v
	var b := _buf(2.4)
	var t := 0.0
	while t < 2.2:
		var k := t / 2.2
		var amp := 0.55 * (1.0 - k * 0.45)
		_ping(b, t, 2800.0 + rng.randf_range(-250.0, 250.0), amp, 0.004)
		_ping(b, t, 1500.0, amp * 0.8, 0.006)
		_noise_burst(b, rng, t, 0.008, amp * 0.5, 0.7)
		t += 0.03 + 0.32 * pow(k, 3.0)
	return _wav(b)

## Hammer drawn back: two rising clicks (half-cock, full-cock).
static func _hammer_cock() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9400
	var b := _buf(0.4)
	for hit: Array in [[0.0, 1.0], [0.13, 1.35]]:
		var t0: float = hit[0]
		var p: float = hit[1]
		_ping(b, t0, 1900.0 * p, 0.7, 0.006)
		_ping(b, t0, 900.0 * p, 0.6, 0.012)
		_noise_burst(b, rng, t0, 0.015, 0.6, 0.6)
	_ping(b, 0.16, 420.0, 0.25, 0.05)
	return _wav(b)

## Empty chamber: a dull, dry "click" — the worst best sound.
static func _dry_click() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9500
	var b := _buf(0.5)
	_ping(b, 0.0, 1300.0, 0.7, 0.01)
	_ping(b, 0.0, 620.0, 0.6, 0.02)
	_noise_burst(b, rng, 0.0, 0.02, 0.6, 0.5)
	_thump(b, 0.0, 0.12, 70.0, 150.0, 30.0, 0.4)
	_ping(b, 0.05, 2200.0, 0.12, 0.08)
	return _wav(b)

## Backfire: a fat, ragged bang with metal shrapnel rattling away.
static func _backfire() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9600
	var b := _buf(1.6)
	_noise_burst(b, rng, 0.0, 0.08, 1.0, 0.8)
	_noise_burst(b, rng, 0.0, 0.45, 0.8, 0.12)
	_thump(b, 0.0, 0.5, 30.0, 120.0, 12.0, 1.0)
	for i in 9:
		_ping(b, 0.08 + i * 0.07 + rng.randf() * 0.04, rng.randf_range(1800.0, 4800.0), 0.3 * (1.0 - i / 10.0), 0.02)
	_noise_burst(b, rng, 0.3, 1.1, 0.25, 0.9)  # hissing steam
	return _wav(b)

## Heartbeat: "lub-dub" low thumps, loopable at ~70 bpm.
static func _heartbeat() -> AudioStreamWAV:
	var b := _buf(0.86)
	for hit: Array in [[0.0, 1.0, 58.0], [0.18, 0.7, 50.0]]:
		var t0: float = hit[0]
		var amp: float = hit[1]
		var f: float = hit[2]
		var start := int(t0 * RATE)
		for i in int(0.16 * RATE):
			var t := float(i) / RATE
			b[start + i] += sin(TAU * f * t * (1.0 - t * 1.5)) * amp * exp(-t / 0.045) * minf(t / 0.004, 1.0)
	return _wav(b, true)
