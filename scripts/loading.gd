extends CanvasLayer
## The loading screen at start-up: the painted night lake (art/loading.png, the title painted in) covering the
## screen, its lanterns glowing and fireflies blinking at the treeline, the game's daylight bar filling as
## things load with the sun riding its end and shedding sparks, and one gameplay tip under it. When it is
## all ready the lanterns swell, the sun bursts, and the screen fades away over the map.
## Waits for: the background loads in `paths` (scripts and models), the sounds (Sfx) and the lantern art,
## then for the map to be built and drawn underneath (main.gd sets map_up): its first draw is slow on a first
## launch (the 3D pickup's shaders), so that happens while the bar is still filling, not after it.
## The bar and the text are laid out in a 720x1280 design space scaled to the screen; the picture covers it.

signal loaded  # everything is loaded: build the map underneath now, and set map_up once it has drawn

const DESIGN := Vector2(720, 1280)
const MIN_TIME := 3.0  # seconds on screen at least (real time) before it fades: long enough to read the tip
const BG_TOP := Color(0.113725, 0.164706, 0.192157)  # the boot and Android window colour
const AMBER := Color(1.0, 0.72, 0.32)
const GOLD := Color("ffd796")
const DUSK := Color("ff8a66")
const MAX_STEP := 1.0 / 30.0  # a frame that hitches pauses the animation instead of making it jump
const ART := "res://art/loading.png"
const ART_SIZE := Vector2(941, 1672)
# Painted lanterns on the picture (picture pixels): where, how big a glow, its own flicker phase.
const LAMPS := [[Vector2(612, 800), 120.0, 0.0], [Vector2(122, 988), 95.0, 1.7], [Vector2(818, 968), 95.0, 3.1],
	[Vector2(628, 1100), 150.0, 4.4]]
const FIREFLIES := [Vector2(90, 760), Vector2(205, 700), Vector2(330, 640), Vector2(470, 660), Vector2(700, 720),
	Vector2(860, 780), Vector2(760, 905), Vector2(40, 900)]
const BAR_PIC_Y := 1345.0  # the bar sits on the picture's empty water here (moved up if the tip wouldn't fit)
const TIP_SHOW := 4.0  # a slow load moves on to another tip after this long
const TIPS := [
	"Hold the left or right side of the screen to steer.",
	"Cross your own trail to close a loop. Every lantern inside lights up.",
	"One loop around several lanterns is a combo. It wins back daylight.",
	"Light three lanterns quickly for swift water.",
	"Only loops that light a lantern count towards your loops.",
	"Each lake has three goals: light them all, beat dusk, and use few loops.",
	"Stones wreck the boat. So does hitting the shore head-on.",
	"Reeds slow you down.",
	"Ducks that cross your trail snap it.",
	"Stay in the swans' water too long and the cob charges.",
	"A chasing swan turns wide. Turn sharply to lose him.",
	"Run over the swans' egg, then sail it back to them.",
	"At night your headlight runs on a battery. Combos recharge it.",
	"Twin lanterns only light together. Catch both in one loop.",
	"Small lanterns at the screen's edge show dark lanterns that way.",
	"Some lanterns hide behind islands and stones. Look for the way in.",
]

var paths: Array = []
var map_up := false
var _loaded := false
var _loaded_t := 0.0
var _art: Control  # the picture and the bar; everything fades with it
var _add: Control  # light on top (additive): lantern glows, fireflies, the sun's halo, sparks
var _top: Control  # the sun icon and the tip, over the light
var _tex: Texture2D
var _t := 0.0
var _shown := 0.0  # the progress drawn: follows the real one with eased speed, so it moves as one motion
var _vel := 0.0
var _lit := 0.0  # 0..1 once everything is ready: the lanterns swell, the sun's halo grows
var _done := false
var _burst := false
var _start_ms := Time.get_ticks_msec()
var _k := 1.0  # design space to screen
var _pk := 1.0  # picture to screen (cover)
var _po := Vector2.ZERO
var _fonts := {}  # the game's fonts with their letter spacing scaled to the screen, by scale
var _sparks: Array = []
var _spark_acc := 0.0
var _sun := Vector2.ZERO  # the sun icon's centre on screen
var _bar := Rect2()
var _tip := 0
var _tip_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_tip = _rng.randi() % TIPS.size()
	# The picture is loaded right here, before the first frame: loaded in the background it queued behind
	# the models and scripts on a first launch and showed up late, after the bar. (One picture: a few
	# hundredths of a second, behind Android's own splash colour.) If it ever fails, the plain colour.
	_tex = load(ART) as Texture2D
	_art = Control.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing underneath takes taps meanwhile
	_art.draw.connect(_draw_art)
	add_child(_art)
	_add = Control.new()
	_add.set_anchors_preset(Control.PRESET_FULL_RECT)
	_add.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = mat
	_add.draw.connect(_draw_light)
	_art.add_child(_add)
	_top = Control.new()
	_top.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.draw.connect(_draw_top)
	_art.add_child(_top)


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_STEP)
	_t += dt
	if not _done:
		# Never ahead of the time on screen: on a fast load the bar still fills steadily over MIN_TIME (the
		# time to read the tip) instead of racing to the end and sitting there full.
		var target := minf(_progress(), (Time.get_ticks_msec() - _start_ms) / (MIN_TIME * 1000.0))
		# Speed eases towards what the gap asks for: big steps in the real progress become one smooth sweep.
		# Once everything is ready it hurries to the end (still eased, never a jump).
		var want := clampf((target - _shown) * 4.0, 0.0, 4.0 if target >= 1.0 else 2.2)
		_vel = lerpf(_vel, want, 1.0 - exp(-6.0 * dt))
		_shown = minf(_shown + _vel * dt, target)
		if target >= 1.0 and _shown > 0.995:
			_shown = 1.0
	if _shown >= 1.0:
		_lit = move_toward(_lit, 1.0, dt * 3.5)
		if not _burst and _bar.size.x > 0.0:
			_burst = true
			for k in 28:
				_spark(Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(90.0, 260.0))
		if _lit >= 1.0 and not _done and Time.get_ticks_msec() - _start_ms >= MIN_TIME * 1000.0:
			_done = true
			var tw := create_tween()  # the map is already drawn underneath
			tw.tween_property(_art, "modulate:a", 0.0, 0.4)
			tw.tween_callback(queue_free)
	# The sun sheds sparks as it goes, more while the bar moves fast (once the bar is laid out).
	if not _done and _shown < 1.0 and _bar.size.x > 0.0:
		_spark_acc += dt * (14.0 + 60.0 * _vel)
		while _spark_acc >= 1.0:
			_spark_acc -= 1.0
			_spark(Vector2(_rng.randf_range(-60.0, 60.0), -_rng.randf_range(70.0, 190.0)))
	_sparks = _sparks.filter(func(s): return _t - float(s["t0"]) < float(s["life"]))
	# A slow load moves on to another tip (a short fade out and in).
	if not _done and _t - _tip_t > TIP_SHOW + 0.4:
		_tip_t = _t
		var next := _rng.randi() % (TIPS.size() - 1)
		_tip = next if next < _tip else next + 1  # never the same one twice in a row
	_art.queue_redraw()
	_add.queue_redraw()
	_top.queue_redraw()


func _spark(v: Vector2) -> void:
	_sparks.append({"p": _sun, "v": v * _k, "t0": _t, "life": _rng.randf_range(0.55, 1.15), "r": _rng.randf_range(4.0, 9.0) * _k})


## 0..1 over everything start-up waits for: the loads (0..0.85), then the map's first draw (to 1). Things
## that don't report progress creep up with time until they are done, so the total keeps moving.
func _progress() -> float:
	var real := 0.85 * _loads()
	if _loaded:
		real = 1.0 if map_up else 0.85 + 0.12 * (1.0 - exp(-(_t - _loaded_t) / 0.6))
	elif real >= 0.85:
		_loaded = true
		_loaded_t = _t
		loaded.emit()
	return real if real >= 1.0 else minf(real, 0.92 if not _loaded else 0.99)


## 0..1 over the loads.
func _loads() -> float:
	var sum := 0.0
	var weight := 0.0
	for path in paths:
		var p := [0.0]
		var s := ResourceLoader.load_threaded_get_status(path, p)
		if s == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			sum += float(p[0])
		elif s != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			sum += 1.0  # loaded (or failed: then it is left out, not waited for)
		weight += 1.0
	var creep := 0.85 * (1.0 - exp(-_t / 0.8))
	sum += 1.5 * (1.0 if Sfx._ready_flag else creep)
	sum += 1.0 * (1.0 if Game.lantern_lit != null else creep)
	weight += 2.5
	return sum / weight


## A picture point on screen (the picture covers the screen, centred).
func _pic(p: Vector2) -> Vector2:
	return _po + p * _pk


## The colour of the daylight: gold, warming over the last stretch like the lakes' bar near dusk.
func _sun_col() -> Color:
	return GOLD.lerp(DUSK, smoothstep(0.7, 1.0, _shown))


## How tall the tip block is (the label, a gap and the wrapped tip), on screen; measured once per tip and
## screen size (the tallest tip, so the bar doesn't hop when a slow load moves on to a shorter one).
var _tip_h := {}
func _tip_height(screen: Vector2) -> float:
	var key := "%d:%d" % [int(screen.x), int(screen.y)]
	if not _tip_h.has(key):
		var w := minf(screen.x * 0.84, 600.0 * _k)
		var fs := maxi(1, roundi(22.0 * _k))
		var h := 0.0
		for t in TIPS:
			h = maxf(h, _font(Game.heading_font).get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, w, fs).y)
		_tip_h[key] = 34.0 * _k + 24.0 * _k + h
	return _tip_h[key]


func _layout(screen: Vector2) -> void:
	_k = minf(screen.x / DESIGN.x, screen.y / DESIGN.y)
	_pk = maxf(screen.x / ART_SIZE.x, screen.y / ART_SIZE.y)
	_po = (screen - ART_SIZE * _pk) * 0.5
	var bw := minf(440.0 * _k, screen.x * 0.68)
	var bh := 10.0 * _k
	var y := minf(_pic(Vector2(0, BAR_PIC_Y)).y, screen.y - _tip_height(screen) - 40.0 * _k - bh)
	_bar = Rect2(Vector2((screen.x - bw) * 0.5, y), Vector2(bw, bh))
	var r := 18.0 * _k
	_sun = Vector2(_bar.position.x + clampf(bw * _shown, r, bw - r), _bar.position.y + bh * 0.5)


func _draw_art() -> void:
	var ci := _art
	var screen := ci.size
	_layout(screen)
	if _tex:
		ci.draw_texture_rect(_tex, Rect2(_po, ART_SIZE * _pk), false)
	else:
		ci.draw_rect(Rect2(Vector2.ZERO, screen), BG_TOP)
	# The bar: a soft shadow, a dark plate with a faint rim, the fill (fading in from its start) with a sheen.
	var b := _bar
	_capsule(ci, Rect2(b.position + Vector2(0, 2.0 * _k), b.size).grow(1.5 * _k), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.35))
	_capsule(ci, b, Color(13 / 255.0, 22 / 255.0, 26 / 255.0, 0.7), Color(13 / 255.0, 22 / 255.0, 26 / 255.0, 0.7))
	var rim := _capsule_pts(b.grow(0.5))
	rim.append(rim[0])
	ci.draw_polyline(rim, Color(1, 1, 1, 0.14), 1.0, true)
	var fw := b.size.x * _shown
	if fw > 1.0:
		var col := _sun_col()
		var fill := Rect2(b.position, Vector2(maxf(fw, b.size.y), b.size.y))
		_capsule(ci, fill, Color(col, 0.55), col)
		_capsule(ci, Rect2(fill.position + Vector2(b.size.y * 0.25, b.size.y * 0.1), Vector2(maxf(fill.size.x - b.size.y * 0.5, 1.0), b.size.y * 0.4)),
			Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.16))


## Light on the picture: the painted lanterns glowing (each flickering its own way, swelling when ready),
## fireflies blinking at the treeline, the bar's glow, the sun's halo and its sparks.
func _draw_light() -> void:
	var ci := _add
	var glow: Texture2D = Game.glow_tex
	if _tex:
		var swell := 1.0 + 0.7 * _lit
		for lamp in LAMPS:
			var ph: float = lamp[2]
			var f := 0.86 + 0.08 * sin(_t * 7.1 + ph) + 0.05 * sin(_t * 12.7 + ph * 2.0) + 0.04 * sin(_t * 3.3 + ph)
			var r: float = float(lamp[1]) * _pk * (1.0 + 0.04 * sin(_t * 5.3 + ph)) * swell
			ci.draw_texture_rect(glow, Rect2(_pic(lamp[0]) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(AMBER, 0.42 * f * swell))
		for i in FIREFLIES.size():
			var p := _pic(FIREFLIES[i] + Vector2(sin(_t * 0.7 + i) * 6.0, cos(_t * 0.9 + i * 1.3) * 4.0))
			var blink := pow(maxf(0.0, sin(_t * 1.3 + i * 2.1)), 2.0)
			var fr := 16.0 * _pk
			ci.draw_texture_rect(glow, Rect2(p - Vector2(fr, fr), Vector2(fr, fr) * 2.0), false, Color(1.0, 0.85, 0.45, 0.8 * blink))
			ci.draw_texture_rect(glow, Rect2(p - Vector2(fr, fr) * 0.3, Vector2(fr, fr) * 0.6), false, Color(1, 1, 0.8, blink))
	var col := _sun_col()
	var fw := _bar.size.x * _shown
	if fw > 1.0:
		var g := 14.0 * _k
		ci.draw_texture_rect(glow, Rect2(_bar.position - Vector2(g, g), Vector2(fw + g * 2.0, _bar.size.y + g * 2.0)), false, Color(col, 0.3))
	var hr := 40.0 * _k * (1.0 + 0.5 * _lit) * (1.0 + 0.05 * sin(_t * 3.0))
	ci.draw_texture_rect(glow, Rect2(_sun - Vector2(hr, hr), Vector2(hr, hr) * 2.0), false, Color(col, 0.55))
	for s in _sparks:
		var t := _t - float(s["t0"])
		var k := t / float(s["life"])
		var p: Vector2 = Vector2(s["p"]) + Vector2(s["v"]) * t + Vector2(0, 320.0 * _k) * t * t
		var r := float(s["r"]) * (1.0 - k * 0.6)
		ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, 1.0 - k))
		ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r) * 0.35, Vector2(r, r) * 0.7), false, Color(1, 1, 1, 1.0 - k))


## The sun icon turning slowly at the end of the fill, and the tip under the bar.
func _draw_top() -> void:
	var ci := _top
	var screen := ci.size
	var col := _sun_col()
	ci.draw_set_transform(_sun, _t * TAU / 14.0, Vector2.ONE)
	Game.draw_icon(ci, "sun", Vector2.ZERO, 36.0 * _k, col)
	ci.draw_set_transform(Vector2.ZERO)
	# The tip: a small gold label, then the tip itself, fading between tips on a slow load.
	var age := _t - _tip_t
	var fade_in := 1.0 if _tip_t == 0.0 else clampf(age / 0.2, 0.0, 1.0)  # the first tip is there from the start
	var fade_out := 1.0 if _done else clampf((TIP_SHOW + 0.2 - age) / 0.2, 0.0, 1.0)
	var a := fade_in * fade_out
	var y := _bar.end.y + 34.0 * _k
	var lf := _font(Game.title_font)
	var lfs := maxi(1, roundi(16.0 * _k))
	var lw := lf.get_string_size("TIP", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
	ci.draw_string(lf, Vector2((screen.x - lw) * 0.5, y), "TIP", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(GOLD, 0.9 * a))
	var w := minf(screen.x * 0.84, 600.0 * _k)
	var fs := maxi(1, roundi(22.0 * _k))
	var tp := Vector2((screen.x - w) * 0.5, y + 24.0 * _k + fs)
	var tf := _font(Game.heading_font)
	ci.draw_multiline_string(tf, tp + Vector2(0, 2.0 * _k), TIPS[_tip], HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, Color(0, 0, 0, 0.55 * a))
	ci.draw_multiline_string(tf, tp, TIPS[_tip], HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, Color(1, 1, 1, 0.72 * a))


## A fully rounded bar filled with a colour running from left to right.
func _capsule(ci: CanvasItem, r: Rect2, left: Color, right: Color) -> void:
	var pts := _capsule_pts(r)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(left.lerp(right, clampf((p.x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)))
	ci.draw_polygon(pts, cols)


func _capsule_pts(r: Rect2) -> PackedVector2Array:
	var rad := minf(r.size.y * 0.5, r.size.x * 0.5)
	var pts := PackedVector2Array()
	var cl := Vector2(r.position.x + rad, r.position.y + r.size.y * 0.5)
	var cr := Vector2(r.end.x - rad, cl.y)
	for k in 9:
		pts.append(cr + Vector2.from_angle(-PI * 0.5 + PI * k / 8.0) * rad)
	for k in 9:
		pts.append(cl + Vector2.from_angle(PI * 0.5 + PI * k / 8.0) * rad)
	return pts


## A copy of a game font whose letter spacing grows with the screen like everything else.
func _font(f: FontVariation) -> Font:
	var key := "%d:%.2f" % [f.get_instance_id(), _k]
	if not _fonts.has(key):
		var v := f.duplicate() as FontVariation
		v.spacing_glyph = roundi(f.spacing_glyph * _k)
		_fonts[key] = v
	return _fonts[key]
