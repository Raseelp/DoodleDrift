extends Node
## All sound is synthesised in code at start-up (no audio files), on a background thread.
## Lake soundscape: birds by day, frogs at dusk, an owl at night, water against the hull,
## reeds rustling. Music in three layers that fade in as lanterns light.

const RATE_HI := 22050
const RATE_LO := 16000

var _ready_flag := false
var _thread: Thread
var S := {}

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _layers: Array[AudioStreamPlayer] = []
var _hull: AudioStreamPlayer
var _reeds: AudioStreamPlayer
var _ambience_pitch := -1.0
var _active := false
var _progress := 0.0
var _dusk := 0.0
var _speed := 0.0
var _in_reeds := false
var _critter_t := 2.0
var _on_lake := false  # the boat-on-water loop only plays on a lake, never on the map


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 3:
		var l := AudioStreamPlayer.new()
		l.volume_db = -60.0
		add_child(l)
		_layers.append(l)
	_hull = AudioStreamPlayer.new()
	_reeds = AudioStreamPlayer.new()
	for p in [_hull, _reeds]:
		p.volume_db = -60.0
		add_child(p)
	_thread = Thread.new()
	_thread.start(_generate)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _generate() -> void:
	var out := {
		"chime": _make_chime(), "whoosh": _make_whoosh(), "bump": _make_bump(), "tap": _make_tap(),
		"pad": _make_pad(), "shimmer": _make_shimmer(), "bells": _make_bells(),
		"hull": _make_hull(), "reeds": _make_reeds(),
		"bird": _make_bird(), "frog": _make_frog(), "owl": _make_owl(), "quack": _make_quack(),
		"stamp": _make_stamp(), "snap": _make_snap(), "peep": _make_peep(),
	}
	call_deferred("_on_generated", out)


func _on_generated(out: Dictionary) -> void:
	S = out
	_ready_flag = true
	if _thread.is_started():
		_thread.wait_to_finish()
	_layers[0].stream = S["pad"]
	_layers[1].stream = S["shimmer"]
	_layers[2].stream = S["bells"]
	_hull.stream = S["hull"]
	_reeds.stream = S["reeds"]
	if _ambience_pitch > 0.0:
		var p := _ambience_pitch
		_ambience_pitch = -1.0
		start_ambience(p, _on_lake)


# ---------------------------------------------------------------- public

func chime(pitch: float) -> void:
	_play("chime", pitch, -4.0)


func chord(pitch: float) -> void:
	for r in [1.0, 1.25, 1.5, 2.0]:
		_play("chime", pitch * r, -9.0)


func loop_closed(strength: float) -> void:
	_play("whoosh", 1.0, linear_to_db(0.9 * strength) - 2.0)


func reject() -> void:
	_play("chime", 0.5, -16.0)
	_play("chime", 0.53, -16.0)


func bump() -> void:
	_play("bump", randf_range(0.9, 1.1), -6.0)


func tap() -> void:
	_play("tap", 1.0, -10.0)


func crash() -> void:
	_play("bump", 0.8, -1.0)
	_play("whoosh", 0.6, -8.0)


func plop() -> void:
	_play("tap", randf_range(0.28, 0.36), -14.0)
	_play("whoosh", 2.2, -20.0)


## A duckling left behind: a thin high "peep-peep".
func peep() -> void:
	_play("peep", randf_range(0.92, 1.12), -17.0)


## A mallard hen gathering her brood: two soft, low quacks.
func duck_call() -> void:
	for k in 2:
		get_tree().create_timer(k * 0.22).timeout.connect(func(): _play("quack", randf_range(0.8, 0.88), -15.0 - k * 2.0))


## A mallard hen's alarm: three quick, sharp quacks.
func quack_alarm() -> void:
	for k in 3:
		get_tree().create_timer(k * 0.16).timeout.connect(func(): _play("quack", randf_range(1.12, 1.25), -11.0 - k * 1.5))


func quack() -> void:
	_play("quack", randf_range(0.9, 1.15), -6.0)
	_play("whoosh", 1.8, -14.0)


## A rubber stamp pressed onto paper: an earned goal lands firm, a missed one lands dull and low.
func stamp(earned: bool) -> void:
	if earned:
		_play("stamp", randf_range(0.97, 1.03), -1.0)
	else:
		_play("stamp", 0.72, -9.0)


## A duck snaps the trail: a quick wet flick, droplets falling back, and the duck's small complaint.
func trail_snap() -> void:
	_play("snap", randf_range(0.95, 1.08), -5.0)
	_play("quack", randf_range(1.05, 1.2), -15.0)


## An ember leaving the boat's lamp: a soft, quick breath.
func ember() -> void:
	_play("whoosh", 3.0, -18.0)


## The ember landing: a match-strike flick and a low warm catch, under the lantern's chime.
func ignite() -> void:
	_play("whoosh", 2.4, -12.0)
	_play("bump", 1.7, -14.0)


func fade_out() -> void:
	_play("chime", 0.5, -20.0)


func chain(pitch: float, level: int) -> void:
	var ratios := [2.0, 2.5, 3.0, 4.0]
	for i in mini(level, ratios.size()):
		_play("chime", pitch * float(ratios[i]), -14.0 - i * 1.5)


func boost(pitch: float) -> void:
	for i in 4:
		var r: float = [1.0, 1.25, 1.5, 2.0][i] * 2.0
		get_tree().create_timer(0.07 * i).timeout.connect(func(): _play("chime", pitch * r, -12.0))


func start_ambience(pitch: float, on_lake := true) -> void:
	_on_lake = on_lake
	if not _ready_flag:
		_ambience_pitch = pitch
		return
	_active = true
	_progress = 0.0
	_dusk = 0.0
	_speed = 0.0
	_in_reeds = false
	for l in _layers:
		l.pitch_scale = pitch
	apply_settings()


func stop_ambience() -> void:
	_ambience_pitch = -1.0
	_active = false


## Called every frame by a lake: time of day (0-1), boat speed (0-1), whether the boat is in reeds.
func set_mood(dusk: float, speed01: float, reeds: bool) -> void:
	_dusk = dusk
	_speed = speed01
	_in_reeds = reeds


## Fraction of lanterns lit: brings in the music layers.
func set_progress(f: float) -> void:
	_progress = f


func apply_settings() -> void:
	if not _ready_flag:
		return
	for p in _layers + [_hull, _reeds]:
		if not p.playing and p.stream != null:
			p.play()


func _process(delta: float) -> void:
	if not _ready_flag:
		return
	var music: bool = Game.music_on and _active
	var sound: bool = Game.sound_on and _active and not get_tree().paused
	var targets := [
		-14.0 + _progress * 4.0 if music else -60.0,
		(-30.0 + 18.0 * smoothstep(0.25, 0.6, _progress)) if music else -60.0,
		(-34.0 + 22.0 * smoothstep(0.55, 0.95, _progress)) if music else -60.0,
	]
	for i in 3:
		_layers[i].volume_db = move_toward(_layers[i].volume_db, targets[i], delta * 12.0)
	_hull.volume_db = move_toward(_hull.volume_db, (-30.0 + 16.0 * _speed) if sound and _on_lake else -60.0, delta * 20.0)
	_hull.pitch_scale = 0.85 + _speed * 0.3
	_reeds.volume_db = move_toward(_reeds.volume_db, -10.0 if sound and _in_reeds else -60.0, delta * 40.0)
	if not sound:
		return
	_critter_t -= delta
	if _critter_t <= 0.0:
		_critter_t = randf_range(1.2, 3.5)
		var day := 1.0 - _dusk
		var roll := randf()
		if roll < day * 0.8:
			for k in randi_range(1, 3):
				get_tree().create_timer(k * randf_range(0.12, 0.25)).timeout.connect(func(): _play("bird", randf_range(0.85, 1.3), -20.0))
		elif roll < 0.9 and _dusk > 0.35:
			_play("frog", randf_range(0.85, 1.1), -18.0)
		elif _dusk > 0.7 and randf() < 0.3:
			_play("owl", randf_range(0.95, 1.05), -16.0)


func _play(key: String, pitch: float, db: float) -> void:
	if not _ready_flag or not Game.sound_on or not S.has(key):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = S[key]
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.volume_db = db
	p.play()


# ---------------------------------------------------------------- synthesis

func _to_wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.85, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(secs: float, rate: int) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(secs * rate))
	return s


func _make_chime() -> AudioStreamWAV:
	var s := _buf(1.9, RATE_HI)
	var f := 523.25
	for i in s.size():
		var t := float(i) / RATE_HI
		var v := sin(TAU * f * t) * exp(-t * 2.4) + 0.32 * sin(TAU * f * 2.0 * t) * exp(-t * 4.0)
		v += 0.16 * sin(TAU * f * 2.76 * t) * exp(-t * 7.0) + 0.06 * sin(TAU * f * 5.4 * t) * exp(-t * 14.0)
		s[i] = v * minf(1.0, t / 0.004)
	return _to_wav(s, RATE_HI, false)


func _make_whoosh() -> AudioStreamWAV:
	var s := _buf(0.95, RATE_HI)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in s.size():
		var t := float(i) / s.size()
		var cut := lerpf(0.02, 0.09, sin(PI * t))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
		lp2 += (lp - lp2) * cut
		s[i] = (lp - lp2 * 0.6) * pow(sin(PI * minf(1.0, t * 1.3)), 2.0)
	return _to_wav(s, RATE_HI, false)


func _make_bump() -> AudioStreamWAV:
	var s := _buf(0.3, RATE_HI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE_HI
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		s[i] = sin(TAU * 92.0 * t) * exp(-t * 14.0) + lp * exp(-t * 30.0) * 0.8
	return _to_wav(s, RATE_HI, false)


func _make_snap() -> AudioStreamWAV:
	# A bright, very short crack of filtered noise (the line snapping), then three small droplets
	# falling back into the water: quick sine "plips" that drop in pitch.
	var s := _buf(0.5, RATE_HI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lp := 0.0
	var drops := [[0.05, 1500.0, 0.8], [0.13, 1150.0, 0.55], [0.22, 1800.0, 0.35]]
	for i in s.size():
		var t := float(i) / RATE_HI
		var nz := rng.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.35
		var v := (nz - lp) * exp(-t * 85.0) * 0.9  # high-passed crack
		for d in drops:
			var dt: float = t - float(d[0])
			if dt > 0.0:
				var f: float = float(d[1]) * (1.0 - 0.45 * minf(1.0, dt / 0.05))
				v += sin(TAU * f * dt) * exp(-dt * 38.0) * float(d[2]) * minf(1.0, dt / 0.002)
		s[i] = v
	return _to_wav(s, RATE_HI, false)


func _make_stamp() -> AudioStreamWAV:
	# Sharp clack of the stamp face (bright filtered noise), a short wooden body thud underneath,
	# and a faint papery scuff as it lifts.
	var s := _buf(0.32, RATE_HI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var hp := 0.0
	var lp := 0.0
	var prev := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE_HI
		var n := rng.randf_range(-1.0, 1.0)
		hp = 0.86 * (hp + n - prev)
		prev = n
		lp += (hp - lp) * 0.55
		var clack := lp * exp(-t * 90.0)
		var f := 70.0 + 130.0 * exp(-t * 40.0)
		ph += TAU * f / RATE_HI
		var body := sin(ph) * exp(-t * 22.0)
		var scuff := 0.0
		if t > 0.11:
			scuff = n * 0.05 * exp(-(t - 0.11) * 30.0) * minf(1.0, (t - 0.11) / 0.01)
		s[i] = (clack * 0.9 + body * 0.85 + scuff) * minf(1.0, t / 0.0008)
	return _to_wav(s, RATE_HI, false)


func _make_tap() -> AudioStreamWAV:
	var s := _buf(0.09, RATE_HI)
	for i in s.size():
		var t := float(i) / RATE_HI
		s[i] = sin(TAU * 1046.5 * t) * exp(-t * 55.0) * minf(1.0, t / 0.002)
	return _to_wav(s, RATE_HI, false)


func _make_pad() -> AudioStreamWAV:
	# 8 s seamless warm pad: root, fifth and octave with slow, whole-cycle swells.
	var secs := 8.0
	var s := _buf(secs, RATE_LO)
	var parts := [[110.0, 0.5, 1], [110.25, 0.3, 2], [165.0, 0.24, 3], [220.0, 0.16, 1], [277.5, 0.07, 2]]
	for i in s.size():
		var t := float(i) / RATE_LO
		var v := 0.0
		for p in parts:
			v += sin(TAU * float(p[0]) * t) * float(p[1]) * (0.65 + 0.35 * sin(TAU * t * float(p[2]) / secs + float(p[2])))
		s[i] = v
	return _to_wav(s, RATE_LO, true)


func _make_shimmer() -> AudioStreamWAV:
	# Slow high arpeggio, 8 s loop, notes from the same chord as the lantern chimes.
	var secs := 8.0
	var s := _buf(secs, RATE_LO)
	var notes := [440.0, 550.0, 660.0, 880.0, 660.0, 550.0, 495.0, 660.0]
	for n in notes.size():
		var start := n * secs / notes.size()
		var f: float = notes[n]
		for i in int(1.6 * RATE_LO):
			var idx := (int(start * RATE_LO) + i) % s.size()
			var t := float(i) / RATE_LO
			s[idx] += sin(TAU * f * t) * exp(-t * 1.8) * minf(1.0, t / 0.03) * 0.5 + sin(TAU * f * 2.0 * t) * exp(-t * 3.0) * 0.12
	return _to_wav(s, RATE_LO, true)


func _make_bells() -> AudioStreamWAV:
	# Sparse bell melody, 8 s loop, enters once most lanterns are lit.
	var secs := 8.0
	var s := _buf(secs, RATE_LO)
	var mel := [[0.0, 880.0], [1.5, 990.0], [2.5, 1100.0], [4.0, 880.0], [5.0, 1320.0], [6.5, 1100.0]]
	for m in mel:
		var f: float = m[1]
		for i in int(2.0 * RATE_LO):
			var idx := (int(float(m[0]) * RATE_LO) + i) % s.size()
			var t := float(i) / RATE_LO
			s[idx] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.76 * t) * exp(-t * 4.0)) * exp(-t * 2.2) * minf(1.0, t / 0.004) * 0.45
	return _to_wav(s, RATE_LO, true)


func _make_hull() -> AudioStreamWAV:
	# Soft water against a small hull: gentle low lapping, no surf.
	var secs := 4.0
	var n := int(secs * RATE_LO)
	var fade := int(0.4 * RATE_LO)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		var t := float(i) / RATE_LO
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.03
		lp2 += (lp - lp2) * 0.01
		var lap := 0.5 + 0.5 * pow(sin(TAU * t / 1.0 + 0.6 * sin(TAU * t / 4.0)), 2.0)
		raw[i] = (lp - lp2) * lap
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i]
	for i in fade:
		var w := float(i) / fade
		s[i] = raw[i] * w + raw[n + i] * (1.0 - w)
	return _to_wav(s, RATE_LO, true)


func _make_reeds() -> AudioStreamWAV:
	var secs := 2.0
	var s := _buf(secs, RATE_HI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var prev := 0.0
	for i in s.size():
		var t := float(i) / RATE_HI
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		s[i] = hp * (0.4 + 0.6 * pow(absf(sin(TAU * t * 3.0 + sin(TAU * t))), 3.0))
	return _to_wav(s, RATE_HI, true)


func _make_peep() -> AudioStreamWAV:
	var s := _buf(0.24, RATE_HI)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE_HI
		var k := fmod(t, 0.12) / 0.08  # two short chirps
		var on := 1.0 if k < 1.0 else 0.0
		var f := 3300.0 + 900.0 * clampf(k, 0.0, 1.0)
		ph += TAU * f / RATE_HI
		s[i] = sin(ph) * on * sin(PI * clampf(k, 0.0, 1.0)) * 0.5
	return _to_wav(s, RATE_HI, false)


func _make_bird() -> AudioStreamWAV:
	var s := _buf(0.18, RATE_HI)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE_HI
		var f := 2600.0 + 1500.0 * sin(PI * t / 0.18) + 200.0 * sin(TAU * 40.0 * t)
		ph += TAU * f / RATE_HI
		s[i] = sin(ph) * sin(PI * t / 0.18)
	return _to_wav(s, RATE_HI, false)


func _make_frog() -> AudioStreamWAV:
	var s := _buf(0.32, RATE_HI)
	for i in s.size():
		var t := float(i) / RATE_HI
		var am := 0.5 + 0.5 * sin(TAU * 26.0 * t)
		var v := sin(TAU * 170.0 * t) + 0.5 * sin(TAU * 340.0 * t) + 0.25 * sin(TAU * 510.0 * t)
		s[i] = v * am * sin(PI * t / 0.32)
	return _to_wav(s, RATE_HI, false)


func _make_owl() -> AudioStreamWAV:
	var s := _buf(1.1, RATE_HI)
	for i in s.size():
		var t := float(i) / RATE_HI
		var env := 0.0
		if t < 0.4:
			env = sin(PI * t / 0.4)
		elif t > 0.55:
			env = sin(PI * (t - 0.55) / 0.55)
		s[i] = (sin(TAU * 380.0 * t) + 0.2 * sin(TAU * 760.0 * t)) * env
	return _to_wav(s, RATE_HI, false)


func _make_quack() -> AudioStreamWAV:
	var s := _buf(0.28, RATE_HI)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE_HI
		var f := 520.0 - 180.0 * t / 0.28
		ph += TAU * f / RATE_HI
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		s[i] = (saw * 0.7 + sin(ph * 2.0) * 0.3) * sin(PI * t / 0.28) * (0.6 + 0.4 * sin(TAU * 45.0 * t))
	return _to_wav(s, RATE_HI, false)
