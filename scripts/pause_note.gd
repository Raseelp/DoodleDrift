extends Control
## The moments the run stops, written on the paper (UI phases 2 and 3).
## Pause: time eases down to a tenth (the car keeps sliding, smoke hanging, the sound slowing like tape)
## while the frame drains to graphite grey, then freezes mid-drift with the camera leaned in a little: a
## pencil sketch of the moment. "paused" is written in the middle on softly rubbed paper, with "hold to
## continue", "start over" and "home". Holding draws the underline under "hold to continue"; once it's
## drawn, the writing fades and the moment eases back to colour and full speed the same way it went in,
## and the finger that held carries straight on steering.
## Crash: the same, slower: the spin-out plays at a third of the speed as the colour drains, then it
## freezes and the run is written up in the middle: what happened, the score underlined (NEW BEST circled
## in red), distance, best combo, confetti; "hold to drive again" (holds count after a second) turns the
## page to a fresh run; "home" with a doodled arrow.
## Runs on real time throughout, so it keeps moving while the game is slowed or stopped.

const DrawNode = preload("res://scripts/draw_node.gd")
const SLOW := 0.6  # seconds of slow motion going into a pause
const CRASH_SLOW := 1.3  # and into a crash write-up (the spin-out)
const BACK := 0.6  # coming back from a pause
const HOLD := 0.45  # holding this long draws the underline and carries on
const CRASH_WAIT := 1.0  # after a crash, holds only count after this long (so a hand still down doesn't restart)
const PENCIL := Color(0.15, 0.15, 0.19, 0.92)
const RED := Color(0.74, 0.15, 0.13, 0.92)
const PAPER := Color(0.97, 0.965, 0.95)

var g: Node  # drift.gd
var kind := "pause"  # pause, crash
var info := {}  # crash: why, score, best, new_best, dist, combo, confetti
var phase := "slowing"  # slowing, frozen, resuming
var t := 0.0
var last_us := 0
var base_zoom := 1.0
var note := Vector2(340, 370)  # the note's size on screen
var note_at := Vector2.ZERO  # its top-left
var held := 0.0
var fingers := {}  # finger index -> screen x, for handing the hold on to the steering
var words: Array = []  # [Rect2, Callable]: the words you can tap
static var _shader: Shader
var grey: ColorRect
var grey_mat: ShaderMaterial
var ink: Node2D


## `instant`: the app is being left, so no slow motion, straight to the frozen page.
func setup(game: Node, instant: bool, what := "pause", details := {}) -> void:
	g = game
	kind = what
	info = details
	if kind == "crash":
		note = Vector2(470, 520)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = g.view
	base_zoom = g.cam.zoom.x
	last_us = Time.get_ticks_usec()
	# the sketch: the screen drained to graphite, only while stopped (it costs one screen pass)
	grey = ColorRect.new()
	grey.size = size
	grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:  # built once and kept: compiling it at the moment of pausing could stutter
		_shader = Shader.new()
		_shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 gph = vec3(l * 0.92 + 0.07, l * 0.92 + 0.07, l * 0.92 + 0.085);
	COLOR = vec4(mix(c, gph, amount), 1.0);
}"""
	grey_mat = ShaderMaterial.new()
	grey_mat.shader = _shader
	grey.material = grey_mat
	add_child(grey)
	ink = DrawNode.new()
	ink.draw_fn = _draw_ink
	add_child(ink)
	if instant:
		_freeze()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf(0.1, (now - last_us) / 1000000.0)
	last_us = now
	t += dt
	match phase:
		"slowing":  # time, sound and colour all ease down together, and the camera leans in
			var slow := CRASH_SLOW if kind == "crash" else SLOW
			var u := smoothstep(0.0, slow, t)
			var low := 0.3 if kind == "crash" else 0.1
			Engine.time_scale = lerpf(1.0, low, smoothstep(0.0, 0.35, t) if kind == "crash" else u)
			AudioServer.playback_speed_scale = lerpf(1.0, 0.4, u)
			g.cam.zoom = Vector2.ONE * base_zoom * lerpf(1.0, 1.08, u)
			_set_grey(u)
			if t >= slow:
				_freeze()
		"frozen":
			var holding := not fingers.is_empty() or Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right")
			if kind == "crash" and t < CRASH_WAIT:
				holding = false  # a hand still down from the run doesn't restart it
			held = minf(HOLD, held + dt) if holding else maxf(0.0, held - dt * 2.0)
			if held >= HOLD:
				if kind == "crash":
					phase = "done"
					g.drive_again()  # the page turns to a fresh run
				else:
					_resume()
		"resuming":  # the same way back: colour, time, sound and the camera ease back up together
			var u := smoothstep(0.0, BACK, t)
			Engine.time_scale = lerpf(0.1, 1.0, u)
			AudioServer.playback_speed_scale = lerpf(0.4, 1.0, u)
			g.cam.zoom = Vector2.ONE * base_zoom * lerpf(1.08, 1.0, u)
			_set_grey(1.0 - u)
			if t >= BACK:
				_done()
	ink.queue_redraw()


func _freeze() -> void:
	phase = "frozen"
	t = 0.0
	held = 0.0
	fingers.clear()
	mouse_filter = Control.MOUSE_FILTER_STOP
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	get_tree().paused = true
	g.cam.zoom = Vector2.ONE * base_zoom * 1.08
	_set_grey(1.0)
	note_at = (size - note) * 0.5  # always in the middle, so it's always found in the same place


## Carry on: the game runs again (slowed, easing back up), and the finger that held is handed to the
## steering so it drives straight on without lifting.
func _resume() -> void:
	phase = "resuming"
	t = 0.0
	get_tree().paused = false
	Engine.time_scale = 0.1
	AudioServer.playback_speed_scale = 0.4
	for id in fingers:
		g.touches[id] = fingers[id]
	g.hold_lock = false  # this hold steers, even if the hold that started the run was never let go
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # from now on touches go to the game as usual


func _set_grey(a: float) -> void:
	grey_mat.set_shader_parameter("amount", a)


## Back to normal time; the game takes the pause away.
func _done() -> void:
	_restore()
	g.pause_done(self)


func _restore() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


func _exit_tree() -> void:
	_restore()  # however it ends (start over, home, the scene going), time and sound are normal again


func _gui_input(e: InputEvent) -> void:
	if phase != "frozen":
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			for w in words:
				if (w[0] as Rect2).has_point(e.position):
					w[1].call()
					return
			fingers[e.index] = e.position.x
		else:
			fingers.erase(e.index)
	elif e is InputEventScreenDrag and fingers.has(e.index):
		fingers[e.index] = e.position.x


## The note, on paper rubbed clean in the middle of the screen; coming back from a pause it all fades as
## the colour returns.
func _draw_ink(n: Node2D) -> void:
	if phase == "slowing":
		return
	var tt := t if phase == "frozen" else 9.0  # (done: the page is turning over it; it stays written)
	var fade := 1.0 - smoothstep(0.0, 0.25, t) if phase == "resuming" else 1.0
	if fade <= 0.0:
		return
	var clean := smoothstep(0.0, 0.3, tt) * fade
	var squash := 0.72 if kind == "pause" else note.y / note.x * 0.92  # the crash note is taller: cover all of it
	for k in 3:  # the paper under the note, rubbed clean so it reads over anything already there
		n.draw_set_transform(note_at + note * 0.5, -0.04, Vector2(1.0, squash))
		n.draw_circle(Vector2.ZERO, note.x * 0.6 + k * 22.0, Color(PAPER, (0.55 - k * 0.15) * clean))
	n.draw_set_transform(Vector2.ZERO)
	words.clear()
	if kind == "crash":
		_draw_crash(n, tt)
	else:
		_draw_pause(n, tt, fade)


func _draw_pause(n: Node2D, tt: float, fade: float) -> void:
	var font: Font = g.ui_font()
	var x := note_at.x + 10.0
	var y := note_at.y + 90.0
	_word(n, font, "paused", Vector2(x, y), 80, smoothstep(0.15, 0.55, tt), fade)
	var w := font.get_string_size("paused", HORIZONTAL_ALIGNMENT_LEFT, -1, 80).x
	_pencil(n, [Vector2(x - 4, y + 16), Vector2(x + w * 0.5, y + 20), Vector2(x + w * smoothstep(0.4, 0.7, tt), y + 13)], 4.0, fade, 11)
	var items := [["hold to continue", Callable()], ["start over", func(): g.pause_start_over()], ["home", func(): g._home()]]
	for k in items.size():
		var yy := y + 84.0 + k * 66.0
		var rv := smoothstep(0.5 + k * 0.15, 0.9 + k * 0.15, tt)
		var text: String = items[k][0]
		_word(n, font, text, Vector2(x + 6, yy), 42, rv, fade)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
		if k == 0:  # the hold: its underline is drawn as you hold, and when it's whole the game carries on
			var u := 1.0 if phase == "resuming" else held / HOLD
			if u > 0.0:
				_pencil(n, [Vector2(x + 4, yy + 10), Vector2(x + 4 + tw * u * 0.5, yy + 12), Vector2(x + 6 + tw * u, yy + 9)], 3.2, fade, 20)
		else:
			_pencil(n, [Vector2(x + 6, yy + 9), Vector2(x + 6 + tw * rv, yy + 7)], 2.2, fade, 20 + k)
			words.append([Rect2(x - 10, yy - 52, tw + 32, 72), items[k][1]])


## The run, written up in one centred column, most important first: what happened (small, grey), the score
## (big, underlined; circled in red with "new best!" under it, or the best in grey), a pencil rule, three
## stats each with its label under it, then the one thing to do ("hold to drive again", underlined as you
## hold) and the way out ("home", small).
func _draw_crash(n: Node2D, tt: float) -> void:
	var font: Font = g.ui_font()
	var cx := note_at.x + note.x * 0.5
	var y0 := note_at.y
	var grey := Color(PENCIL, 0.55)
	# what happened
	var why := String(info.get("why", "crashed")).to_lower()
	_centred(n, font, why, cx, y0 + 52.0, 30, smoothstep(0.1, 0.45, tt), grey)
	# the score
	var score := _thousands(int(info.get("score", 0)))
	var sy := y0 + 165.0
	var sw := font.get_string_size(score, HORIZONTAL_ALIGNMENT_LEFT, -1, 104).x
	_centred(n, font, score, cx, sy, 104, smoothstep(0.35, 0.7, tt), PENCIL)
	if info.get("new_best", false):  # circled in red pen, like a teacher's mark, with the words under it
		var u := smoothstep(0.8, 1.15, tt)
		if u > 0.0:
			var c := Vector2(cx, sy - 36.0)
			var ra := minf(sw * 0.5 + 28.0, note.x * 0.5 - 12.0)  # always inside the note
			var ring := PackedVector2Array()
			for i in int(1 + 36 * u):
				var a := -2.6 + TAU * 1.08 * i / 36.0
				ring.append(c + Vector2(cos(a) * ra, sin(a) * 62.0) * (1.0 + 0.04 * i / 36.0))
			if ring.size() > 1:
				n.draw_polyline(ring, RED, 3.0, true)
			_centred(n, font, "new best!", cx, sy + 62.0, 32, u, RED)
	else:
		_pencil(n, [Vector2(cx - sw * 0.5, sy + 16), Vector2(cx, sy + 20), Vector2(cx - sw * 0.5 + sw * smoothstep(0.6, 0.85, tt), sy + 14)], 4.0, 1.0, 31)
		_centred(n, font, "best " + _thousands(int(info.get("best", 0))), cx, sy + 62.0, 28, smoothstep(0.8, 1.1, tt), grey)
	# a pencil rule, then the stats: value on top, what it is underneath
	var rv := smoothstep(0.9, 1.3, tt)
	var ry := y0 + 250.0
	if rv > 0.0:
		_pencil(n, [Vector2(cx - 150.0, ry), Vector2(cx, ry + 2.0), Vector2(cx - 150.0 + 300.0 * rv, ry - 1.0)], 1.8, 0.5, 33)
	var stats := [[_thousands(int(info.get("dist", 0))) + " m", "distance"], ["x%d" % int(info.get("combo", 1)), "best combo"], [_thousands(int(info.get("confetti", 0))), "confetti"]]
	for k in 3:
		var sx := cx + (k - 1) * note.x * 0.31
		_centred(n, font, String(stats[k][0]), sx, ry + 58.0, 38, rv, PENCIL)
		_centred(n, font, String(stats[k][1]), sx, ry + 86.0, 20, rv, grey)
	# hold to drive again: the one thing to do, underlined as you hold (after a moment)
	var hy := y0 + 420.0
	var hold_text := "hold to drive again"
	var hw := font.get_string_size(hold_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	_centred(n, font, hold_text, cx, hy, 44, smoothstep(1.1, 1.5, tt), PENCIL if tt >= CRASH_WAIT else Color(PENCIL, 0.5))
	if held > 0.0:
		var u := held / HOLD
		var hx := cx - hw * 0.5
		_pencil(n, [Vector2(hx - 2, hy + 10), Vector2(hx + hw * u * 0.5, hy + 13), Vector2(hx + hw * u, hy + 9)], 3.4, 1.0, 40)
	# home: small, with a doodled arrow
	var my := y0 + 482.0
	var hv := smoothstep(1.3, 1.7, tt)
	if hv > 0.0:
		var mw := font.get_string_size("home", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		var mx := cx - (mw + 40.0) * 0.5
		_pencil(n, [Vector2(mx + 30, my - 12), Vector2(mx + 16, my - 11), Vector2(mx + 2, my - 12)], 2.4, hv * 0.7, 41)
		_pencil(n, [Vector2(mx + 11, my - 20), Vector2(mx + 1, my - 12), Vector2(mx + 11, my - 4)], 2.4, hv * 0.7, 42)
		_word(n, font, "home", Vector2(mx + 40.0, my), 32, hv, 0.7)
		words.append([Rect2(mx - 16, my - 44, mw + 72, 64), func(): g._home()])


## A word written centred on `cx` (baseline at y).
func _centred(n: Node2D, font: Font, s: String, cx: float, y: float, size_px: int, reveal: float, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_word(n, font, s, Vector2(cx - w * 0.5, y), size_px, reveal, 1.0, col)


## 12345 -> "12,345"
static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## Handwriting, letter by letter as it is written (`reveal` 0..1), with a faint second pass.
func _word(n: Node2D, font: Font, s: String, at: Vector2, size_px: int, reveal: float, alpha: float, col := PENCIL) -> void:
	var count := int(ceil(s.length() * reveal))
	var x := 0.0
	for i in count:
		var p := at + Vector2(x, sin(i * 2.3) * 1.2)
		n.draw_char(font, p + Vector2(1.6, 1.2), s[i], size_px, Color(col, 0.2 * alpha))
		n.draw_char(font, p, s[i], size_px, Color(col, col.a * alpha))
		x += font.get_char_size(s.unicode_at(i), size_px).x


func _pencil(n: Node2D, pts: Array, w: float, alpha: float, sd: int) -> void:
	var p := PackedVector2Array()
	for i in pts.size():
		var v: Vector2 = pts[i]
		p.append(v + Vector2(sin(i * 12.9 + sd), cos(i * 7.3 + sd)) * 0.8)
	n.draw_polyline(p, Color(PENCIL, PENCIL.a * alpha), w, true)
