extends RefCounted

## Procedural noir-lounge background music (no asset files). Renders a short,
## seamlessly looping jazz combo into an AudioStreamWAV:
##   - Rhodes-style electric piano comping (sine + soft harmonics, tremolo)
##   - walking upright-ish bass (quarter notes, swung approach notes)
##   - brushes + a soft ride (filtered noise, swung eighths)       [table only]
##   - a sparse vibraphone melody in the second half               [table only]
## "menu" is slower and darker (no drums), "table" is the in-game loop.
## Rendering is note-by-note (each note only touches its own samples), so it
## runs in a WorkerThreadPool task in a few seconds; AudioManager caches the
## result to user:// so later launches load instantly.

const RATE := 22050

## Chord = [root midi, intervals...]. A minor noir changes, two per 8 bars.
const PROG_TABLE := [
	[57, 0, 3, 7, 10, 14],   # Am9
	[57, 0, 3, 7, 10, 14],
	[50, 0, 3, 7, 10, 14],   # Dm9
	[50, 0, 3, 7, 10, 14],
	[53, 0, 4, 7, 11, 14],   # Fmaj9
	[52, 0, 4, 7, 10, 13],   # E7b9
	[57, 0, 3, 7, 10, 14],   # Am9
	[52, 0, 4, 7, 10, 13],   # E7b9 (turnaround)
]
const PROG_MENU := [
	[57, 0, 3, 7, 10, 14],   # Am9
	[53, 0, 4, 7, 11, 14],   # Fmaj9
	[50, 0, 3, 7, 10, 14],   # Dm9
	[52, 0, 4, 7, 10, 13],   # E7b9
]

static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

## Renders a track. Returns null for unknown names.
static func render(track: String) -> AudioStreamWAV:
	match track:
		"table": return _render(PROG_TABLE, 84.0, true, 1234)
		"menu": return _render(PROG_MENU, 66.0, false, 777)
	return null

static func _render(prog: Array, bpm: float, drums: bool, seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var bars := prog.size() * (2 if prog.size() < 8 else 1)
	var total := bar * bars
	var n := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var swing := beat * 0.64  # swung "and": 2/3 of the beat, a touch laid back

	for b in bars:
		var chord: Array = prog[b % prog.size()]
		var root: int = chord[0]
		var t_bar := b * bar
		# Rhodes comping: a long voicing on 1, a short stab on the "and of 2".
		var voicing: Array[float] = []
		for k in range(2, chord.size()):
			voicing.append(float(root + int(chord[k])))
		voicing.append(float(root + int(chord[1]) + 12))
		for m in voicing:
			_rhodes(buf, t_bar, midi_hz(m), bar * 0.95, 0.075)
			if drums or b % 2 == 1:
				_rhodes(buf, t_bar + beat + swing, midi_hz(m), beat * 0.9, 0.05)
		# Walking bass: root, chord tone, chord tone, chromatic approach to next root.
		var next_root: int = (prog[(b + 1) % prog.size()] as Array)[0]
		var bass_root := root - 24
		var line := [bass_root, bass_root + int(chord[2]), bass_root + int(chord[3]),
			(next_root - 24) + (1 if rng.randf() < 0.5 else -1)]
		if not drums:
			line = [bass_root, bass_root, bass_root + int(chord[3]), bass_root + int(chord[2])]
		for q in 4:
			_bass(buf, t_bar + q * beat, midi_hz(float(line[q])), beat * 0.95, 0.42 if q == 0 else 0.34)
		if drums:
			for q in 4:
				var tq := t_bar + q * beat
				# Brush swish: longer on 2 and 4.
				_noise(buf, rng, tq, beat * (0.55 if q % 2 == 1 else 0.3), 0.05 if q % 2 == 1 else 0.03, 0.12)
				# Ride: on the beat + the swung "and".
				_noise(buf, rng, tq, 0.09, 0.028, 0.85)
				_noise(buf, rng, tq + swing, 0.06, 0.018, 0.85)
			# Soft kick feathered on 1 and 3.
			_kick(buf, t_bar, 0.18)
			_kick(buf, t_bar + beat * 2.0, 0.12)
		# Vibraphone phrase in the back half (A minor pentatonic, sparse).
		if drums and b * 2 >= bars:
			var scale := [69, 72, 74, 76, 79, 81]
			var tn := t_bar + beat * float(rng.randi_range(0, 1))
			while tn < t_bar + bar - beat * 0.5:
				if rng.randf() < 0.65:
					_vibes(buf, tn, midi_hz(float(scale[rng.randi_range(0, scale.size() - 1)])), 0.07)
				tn += swing if rng.randf() < 0.5 else beat

	# Gentle saturation + normalize, then encode as a seamless loop.
	var peak := 0.0001
	for i in n:
		var v := buf[i]
		v = v / (1.0 + absf(v) * 0.6)
		buf[i] = v
		peak = maxf(peak, absf(v))
	var gain := 0.8 / peak
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

# ── Instruments (each writes only its own note window, wrapping at the loop end) ──

## Electric piano: fundamental + soft 2nd/3rd, bell-ish attack, slow tremolo.
static func _rhodes(buf: PackedFloat32Array, t0: float, f: float, dur: float, amp: float) -> void:
	var s0 := int(t0 * RATE)
	var nb := buf.size()
	var len := int(dur * RATE)
	var w := TAU * f / RATE
	for i in len:
		var t := float(i) / RATE
		var env := minf(t / 0.008, 1.0) * exp(-t / (dur * 0.55)) * minf(float(len - i) / (0.03 * RATE), 1.0)
		var trem := 1.0 + 0.18 * sin(TAU * 4.8 * t)
		var v := sin(w * i) + 0.28 * sin(2.0 * w * i) * exp(-t / 0.3) + 0.08 * sin(3.0 * w * i) * exp(-t / 0.12)
		buf[(s0 + i) % nb] += v * env * trem * amp

## Upright-ish bass: sine + a little 2nd harmonic, thumpy attack.
static func _bass(buf: PackedFloat32Array, t0: float, f: float, dur: float, amp: float) -> void:
	var s0 := int(t0 * RATE)
	var nb := buf.size()
	var len := int(dur * RATE)
	var w := TAU * f / RATE
	for i in len:
		var t := float(i) / RATE
		var env := minf(t / 0.006, 1.0) * exp(-t / 0.35) * minf(float(len - i) / (0.02 * RATE), 1.0)
		var v := sin(w * i) + 0.35 * sin(2.0 * w * i) * exp(-t / 0.08)
		buf[(s0 + i) % nb] += v * env * amp

## Vibraphone: pure sine with a shimmer, long ring.
static func _vibes(buf: PackedFloat32Array, t0: float, f: float, amp: float) -> void:
	var s0 := int(t0 * RATE)
	var nb := buf.size()
	var len := int(1.6 * RATE)
	var w := TAU * f / RATE
	for i in len:
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t / 0.55)
		var v := sin(w * i) * (1.0 + 0.25 * sin(TAU * 5.5 * t)) + 0.15 * sin(4.0 * w * i) * exp(-t / 0.05)
		buf[(s0 + i) % nb] += v * env * amp

## Filtered noise hit: `bright` 0..1 (low = brush swish, high = ride tick).
static func _noise(buf: PackedFloat32Array, rng: RandomNumberGenerator, t0: float, dur: float, amp: float, bright: float) -> void:
	var s0 := int(t0 * RATE)
	var nb := buf.size()
	var len := int(dur * RATE)
	var lp := 0.0
	var prev := 0.0
	for i in len:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * (0.05 + bright * 0.5)
		var hp := lp - prev * (bright * 0.9)
		prev = lp
		var env := minf(t / 0.01, 1.0) * exp(-t / (dur * 0.35))
		buf[(s0 + i) % nb] += hp * env * amp

static func _kick(buf: PackedFloat32Array, t0: float, amp: float) -> void:
	var s0 := int(t0 * RATE)
	var nb := buf.size()
	var len := int(0.25 * RATE)
	var ph := 0.0
	for i in len:
		var t := float(i) / RATE
		ph += TAU * lerpf(90.0, 45.0, minf(t / 0.08, 1.0)) / RATE
		buf[(s0 + i) % nb] += sin(ph) * exp(-t / 0.08) * amp
