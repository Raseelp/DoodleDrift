extends CanvasLayer
## The loading screen at start-up: a boat draws its wake loop around a lantern as things load, the lantern
## lights when the loop closes, then the screen fades away over the map. A slim bar shows the same progress.
## Waits for: the background loads in `paths` (scripts and models), the sounds (Sfx) and the lantern art,
## then for the map to be built and drawn underneath (main.gd sets map_up): its first draw is slow on a first
## launch (the 3D pickup's shaders), so that happens while the loop is still going round, not after it.
## Everything is laid out in a 720x1280 design space scaled to fit inside the screen.

signal loaded  # everything is loaded: build the map underneath now, and set map_up once it has drawn

const DESIGN := Vector2(720, 1280)
const MIN_TIME := 1.0  # seconds on screen at least (real time) before it fades, so it doesn't just flash past
const BG_TOP := Color(0.113725, 0.164706, 0.192157)  # the boot and Android window colour
const BG_BOTTOM := Color(0.06, 0.10, 0.12)
const FOAM := Color(0.86, 0.95, 0.97)
const AMBER := Color(1.0, 0.72, 0.32)
const LOOP_R := 150.0
const MAX_STEP := 1.0 / 30.0  # a frame that hitches pauses the animation instead of making it jump

var paths: Array = []
var map_up := false
var _loaded := false
var _loaded_t := 0.0
var _art: Control
var _t := 0.0
var _shown := 0.0  # the progress drawn: follows the real one with eased speed, so it moves as one motion
var _vel := 0.0
var _lit := 0.0
var _done := false
var _start_ms := Time.get_ticks_msec()
var _k := 1.0  # design space to screen
var _o := Vector2.ZERO
var _fonts := {}  # the game's fonts with their letter spacing scaled to the screen, by scale


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_art = Control.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing underneath takes taps meanwhile
	_art.draw.connect(_draw_art)
	add_child(_art)


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_STEP)
	_t += dt
	if not _done:
		var target := _progress()
		# Speed eases towards what the gap asks for: big steps in the real progress become one smooth sweep.
		# Once everything is ready it hurries round to close the loop (still eased, never a jump).
		var want := clampf((target - _shown) * 4.0, 0.0, 4.0 if target >= 1.0 else 2.2)
		_vel = lerpf(_vel, want, 1.0 - exp(-6.0 * dt))
		_shown = minf(_shown + _vel * dt, target)
		if target >= 1.0 and _shown > 0.995:
			_shown = 1.0
	if _shown >= 1.0:
		_lit = move_toward(_lit, 1.0, dt * 3.5)
		if _lit >= 1.0 and not _done and Time.get_ticks_msec() - _start_ms >= MIN_TIME * 1000.0:
			_done = true
			var tw := create_tween()  # the map is already drawn underneath
			tw.tween_property(_art, "modulate:a", 0.0, 0.4)
			tw.tween_callback(queue_free)
	_art.queue_redraw()


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


## A point on the loop at a (0..TAU from the top, clockwise), a little uneven so it reads as steered.
func _loop(c: Vector2, a: float) -> Vector2:
	var r := LOOP_R * (1.0 + 0.07 * sin(3.0 * a + 1.0) + 0.05 * sin(2.0 * a))
	return c + Vector2(sin(a), -cos(a)) * Vector2(r * 1.05, r * 0.92)


func _draw_art() -> void:
	var ci := _art
	var screen := ci.size
	# The design fits inside the screen (nothing cut off on tall phones, tablets or landscape); the water
	# and its ripples fill the rest.
	_k = minf(screen.x / DESIGN.x, screen.y / DESIGN.y)
	_o = (screen - DESIGN * _k) * 0.5
	# Water at dusk, darker towards the bottom.
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
	# Slow ripples drifting across the whole screen.
	for i in 9:
		var y := fmod(screen.y * (0.12 + 0.1 * i) + _t * 6.0 * _k, screen.y + 40.0 * _k) - 20.0 * _k
		var x := screen.x * (0.15 + 0.7 * fposmod(0.17 + 0.37 * i + _t * 0.01, 1.0))
		var w := (40.0 + 18.0 * (i % 3)) * _k
		ci.draw_arc(Vector2(x, y + w), w, -PI * 0.62, -PI * 0.38, 10, Color(1, 1, 1, 0.05), 2.0 * _k, true)

	ci.draw_set_transform(_o, 0.0, Vector2.ONE * _k)
	var sz := DESIGN
	var c := Vector2(sz.x * 0.5, sz.y * 0.47)

	# Lily pads.
	for pad in [[0.17, 0.37, 26.0, 0.4], [0.82, 0.3, 20.0, 2.1], [0.84, 0.74, 30.0, 4.0], [0.18, 0.8, 22.0, 1.2],
			[0.3, 0.92, 14.0, 5.0]]:
		var pp := Vector2(sz.x * pad[0], sz.y * pad[1])
		var pr: float = pad[2]
		var rot: float = pad[3] + 0.05 * sin(_t * 0.7 + pr)
		var pts := PackedVector2Array()
		for k in 21:
			var a := rot + 0.35 + (TAU - 0.7) * k / 20.0  # the pad's notch
			pts.append(pp + Vector2.from_angle(a) * pr)
		pts.append(pp)
		ci.draw_colored_polygon(pts, Color(0.22, 0.38, 0.27, 0.85))

	# The wake: everything the boat has drawn so far, soft and wide under a bright line.
	var head := _shown * TAU
	var trail := PackedVector2Array()
	var n := maxi(2, int(64.0 * _shown) + 2)
	for k in n:
		trail.append(_loop(c, head * k / float(n - 1)))
	if _shown > 0.005:
		ci.draw_polyline(trail, Color(FOAM, 0.10), 18.0, true)
		ci.draw_polyline(trail, Color(FOAM, 0.55), 4.0, true)

	# The lantern in the middle: dim and waiting, then lit when the loop closes.
	var flicker := 1.0 + 0.04 * sin(_t * 13.0) + 0.03 * sin(_t * 7.3)
	var glow := 0.12 + 0.1 * sin(_t * 2.0) * (1.0 - _lit) + 0.8 * _lit
	var gs := (90.0 + 150.0 * _lit) * flicker
	ci.draw_texture_rect(Game.glow_tex, Rect2(c - Vector2.ONE * gs, Vector2.ONE * gs * 2.0), false,
		Color(AMBER, glow))
	ci.draw_circle(c + Vector2(3, 4), 15.0, Color(0, 0, 0, 0.25))
	ci.draw_circle(c, 15.0, Color(0.32, 0.22, 0.15))  # the float
	ci.draw_circle(c, 9.0, Color(0.14, 0.2, 0.22))  # the tank from above
	ci.draw_circle(c, 5.0, AMBER.lerp(Color(1, 0.96, 0.85), _lit) * Color(1, 1, 1, 0.35 + 0.65 * _lit))

	# The boat at the head of the wake, with its V spreading behind.
	var bp := _loop(c, head)
	var fwd := (_loop(c, head + 0.02) - bp).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	for s in [-1.0, 1.0]:
		ci.draw_line(bp - fwd * 14.0, bp - fwd * 46.0 + side * s * 18.0, Color(FOAM, 0.35), 2.0, true)
	var hull := PackedVector2Array([bp + fwd * 26.0, bp + fwd * 10.0 + side * 10.0, bp - fwd * 22.0 + side * 9.0,
		bp - fwd * 24.0 - side * 9.0, bp + fwd * 10.0 - side * 10.0])
	var shadow := PackedVector2Array()
	for q in hull:
		shadow.append(q + Vector2(4, 6))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	ci.draw_colored_polygon(hull, Color(0.86, 0.84, 0.78))
	ci.draw_colored_polygon(PackedVector2Array([bp + fwd * 14.0, bp + fwd * 4.0 + side * 6.5,
		bp - fwd * 18.0 + side * 6.0, bp - fwd * 18.0 - side * 6.0, bp + fwd * 4.0 - side * 6.5]),
		Color(0.55, 0.38, 0.24))
	ci.draw_line(bp - fwd * 4.0 + side * 6.0, bp - fwd * 4.0 - side * 6.0, Color(0.86, 0.84, 0.78), 2.0)

	# The bar near the bottom.
	var bw := 420.0
	var bar := Rect2(Vector2((sz.x - bw) * 0.5, sz.y * 0.84), Vector2(bw, 6.0))
	ci.draw_rect(bar, Color(1, 1, 1, 0.12))
	ci.draw_rect(Rect2(bar.position, Vector2(bw * _shown, 6.0)), Color(AMBER, 0.9))

	# Text is drawn at the screen's own size (not scaled up), so it stays sharp.
	ci.draw_set_transform(Vector2.ZERO)
	var ty := sz.y * 0.17
	_text(ci, "WAKE", _font(Game.title_font), 96, Vector2(sz.x * 0.5 + 7.0, ty + 4.0), Color(0, 0, 0, 0.3))
	_text(ci, "WAKE", _font(Game.title_font), 96, Vector2(sz.x * 0.5 + 7.0, ty), Color(1, 1, 1, 0.95))
	_text(ci, "close the loop, light the lantern", _font(Game.heading_font), 26, Vector2(sz.x * 0.5, ty + 52.0),
		Color(1, 1, 1, 0.6))
	_text(ci, "Loading" if _shown < 1.0 else "Ready", _font(Game.heading_font), 24,
		Vector2(sz.x * 0.5, bar.position.y + 46.0), Color(1, 1, 1, 0.5))


## Text centred on a design-space point (its baseline at y), at the screen's scale.
func _text(ci: CanvasItem, s: String, font: Font, size: int, at: Vector2, col: Color) -> void:
	var fs := maxi(1, roundi(size * _k))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, _o + at * _k - Vector2(w * 0.5, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A copy of a game font whose letter spacing grows with the screen like everything else.
func _font(f: FontVariation) -> Font:
	var key := "%d:%.2f" % [f.get_instance_id(), _k]
	if not _fonts.has(key):
		var v := f.duplicate() as FontVariation
		v.spacing_glyph = roundi(f.spacing_glyph * _k)
		_fonts[key] = v
	return _fonts[key]
