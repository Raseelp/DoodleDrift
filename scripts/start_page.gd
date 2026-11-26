extends Node
## The home screen, drawn on the paper round the start (UI phase 1). From the top: a pencilled gear in the
## top right corner, the road with "hold" handwritten either side and the best run in the margin, the start
## line, the chosen car's stats, then a night car meet taking over the lot, and the title at the bottom.
## The meet: show cars parked at angles (hoods popped, doors open, a boot speaker, headlights on), a crowd
## drawn from above at true size, a coffee van, chairs, a camera on a tripod, lamp posts, a MEET sign, old
## donut marks, a drone, and the whole lot shaded for night except where the lights fall. The chosen car
## never stops: it runs a figure of eight with donut laps and a 360 spin through the middle, the crowd
## turning to watch. Holding a side sends it from wherever it is straight to the start line, then it's yours.
## The settings are written on the paper to the right, beside the gear; the gear moves the camera there,
## any other tap back.

const DrawNode = preload("res://scripts/draw_node.gd")
const PENCIL := Color(0.19, 0.19, 0.24, 0.88)
const SOFT := Color(0.19, 0.19, 0.24, 0.45)
const RED := Color(0.78, 0.2, 0.17, 0.9)
const RUBBER := Color(0.08, 0.08, 0.1)
const HINT_LOOP := 2.8  # seconds for one side's "hold" to be written, held and rubbed out (sides alternate)
const M := 76.0 / 4.5  # one metre: the Evo is 76 long

## The layout, relative to the start of the road (road[0] is (0, 0) and the road heads up, -y).
const START_Y := 40.0  # the start line
const PAGE_W := 700.0  # how much of the page the home camera shows across
const STATS_Y := 105.0  # the stats block, just below the start line
const MEET_TOP := 238.0  # the meet, below the stats, down to the title
const MEET_MIN := 380.0  # the meet needs this much height; a short screen moves the road up instead
const LOBE := 62.0  # the radius of each donut / figure-of-eight loop
const LOBE_X := 120.0
const GEAR_R := 30.0
const PANEL_W := 255.0  # the settings, written to the right of the page, beside the gear
const ROW := 64.0  # a settings row (about 48 dp to tap on a phone at the settings zoom)
const MAX_MARKS := 2600  # trick marks kept per tyre; past that the oldest wear away

## Set when the page is drawn again after a change in the settings, so the new page starts where the old
## one was looking (the settings) and pans home: no visible jump.
static var reopen_from_settings := false

var g: Node  # drift.gd
var art: Node2D  # everything still: drawn once, into `bake` (an image), so it costs nothing per frame
var bake: SubViewport
var art_rect := Rect2()
var art_scale := 1.5  # image pixels per world unit: the screen's own, so it is as sharp on every phone
var shown: Sprite2D
## Finished images of the still drawing, kept between visits to the start page: it is only drawn again when
## something on it changes (the car, the best run, the screen's shape).
static var baked := {}
var trick_marks: Node2D  # the chosen car's fresh tyre marks
var crowd: Node2D  # the people (they turn to watch)
var shade: Node2D  # night
var hint: Node2D  # the "hold" handwriting
var panel: Node2D  # the settings
var sky: Node2D  # the drone, above everything
var hint_t := 0.0
var mode := "home"  # home, settings, exit, gone
var home_cam := Vector2(0, 70)
var settings_cam := Vector2(370, 300)
var panel_top := 0.0  # the "settings" heading, level with the gear
var panel_x := 395.0  # its left edge: just past the right edge of the screen at home
var cam_pos := Vector2(0, 70)  # where the camera eases to
var cam_zoom := 1.0
var start_cam := Vector2(0, 70)  # where it starts
var start_zoom := 1.0
var home_zoom := 1.0
var hits: Array = []  # settings rows: {rect, kind, key, opts, def}
var rebuild := false  # a change that needs the page drawn again (handling: the road itself changes)
var drag_key := ""
var title_y := 600.0
var meet_bot := 600.0
var pad := Vector2.ZERO  # the middle of the figure of eight
var gear := Vector2(290, -480)
var driver := Driver.new()
var people: Array = []  # {p, ang, look, kind, sd, rate}
var cars: Array = []  # {p, ang, opts}
var lights: Array = []  # world points the night shading leaves lit
var marks := [[], [], [], []]  # per tyre (rears, then fronts): runs (PackedVector2Array) of marks, oldest first
var drone := Vector2.ZERO
var shade_tex: Texture2D
var shade_rect := Rect2()


## Where everything on the page goes (the camera, the title, the meet, the gear and the settings),
## worked out before the road is drawn so the road can keep clear of the gear and the settings.
func layout(game: Node) -> void:
	g = game
	# Fit the page across the screen; on a short, wide screen (a tablet) fit its height instead, so the
	# whole page (best run, road, stats, meet and title) is always on screen.
	var need_top := -420.0
	var need_bot := MEET_TOP + MEET_MIN + 110.0 + 40.0
	home_zoom = minf(g.view.x / PAGE_W, g.view.y / (need_bot - need_top))
	var half_h: float = g.view.y / home_zoom * 0.5
	var half_w: float = g.view.x / home_zoom * 0.5
	# the title near the bottom of the screen; if the meet would be squeezed, the camera moves down instead
	# (the road then starts higher on the screen)
	home_cam.y = maxf(70.0, MEET_TOP + MEET_MIN + 110.0 + 70.0 - half_h)
	title_y = home_cam.y + half_h - 70.0
	meet_bot = title_y - 110.0
	pad = Vector2(0, (MEET_TOP + meet_bot) * 0.5)
	gear = Vector2(half_w - 58.0, home_cam.y - half_h + (g._top() + 60.0) / home_zoom)  # the screen's top right
	panel_top = gear.y + 10.0
	panel_x = maxf(395.0, half_w + 45.0)
	settings_cam = Vector2(panel_x - 15.0, panel_top + 280.0)


## The places the road must not run through (world rects): the gear and the settings writing.
## It may pass close by or around them.
func keep_clear() -> Array:
	return [Rect2(gear - Vector2.ONE * (GEAR_R + 30.0), Vector2.ONE * (GEAR_R + 30.0) * 2.0), _panel_rect()]


func setup(game: Node) -> void:
	layout(game)
	var half_h: float = g.view.y / home_zoom * 0.5
	var half_w: float = g.view.x / home_zoom * 0.5
	_build_meet()
	# The still drawing is thousands of pencil strokes: drawn once into an image, which the page shows.
	var art_top := minf(-430.0, gear.y - 50.0)  # from the gear at the top of the screen
	art_rect = Rect2(-maxf(PAGE_W * 0.5, half_w) - 10.0, art_top, maxf(PAGE_W, half_w * 2.0) + 20.0, title_y + 60.0 - art_top)
	var win := DisplayServer.window_get_size()
	art_scale = clampf(float(win.x) / g.view.x * home_zoom, 1.0, 2.5) if win.x > 0 else 1.5
	shown = Sprite2D.new()
	shown.centered = false
	shown.position = art_rect.position
	shown.scale = Vector2.ONE / art_scale
	g.world.add_child(shown)
	g.world.move_child(shown, g.road_layer.get_index() + 1)  # pencil on the page, under skids and the car
	_bake_art()
	trick_marks = _layer(_draw_marks)
	g.world.move_child(trick_marks, shown.get_index() + 1)
	crowd = _layer(_draw_crowd)
	g.world.move_child(crowd, trick_marks.get_index() + 1)
	shade = _layer(_draw_shade)
	g.world.move_child(shade, crowd.get_index() + 1)
	hint = _layer(_draw_hint)
	g.world.move_child(hint, shade.get_index() + 1)
	panel = _layer(_panel)
	panel.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # for the rubbed-out patch of paper behind it
	g.world.move_child(panel, hint.get_index() + 1)
	sky = _layer(_draw_sky)  # last: above the car
	_make_shade()
	driver.set_path(_trick_path(), true)
	driver.spins = _spins
	driver.stops = _stops
	driver.s = driver.total * 0.62  # somewhere in the loop, already moving
	drone = pad + Vector2(90, -110)
	cam_pos = home_cam
	cam_zoom = home_zoom
	start_cam = home_cam
	start_zoom = home_zoom
	if reopen_from_settings:
		reopen_from_settings = false
		mode = "home"
		start_cam = settings_cam
		start_zoom = _settings_zoom()
	_place_car(0.0)


func _layer(fn: Callable) -> Node2D:
	var n := DrawNode.new()
	n.draw_fn = fn
	g.world.add_child(n)
	return n


func _settings_zoom() -> float:
	return minf(g.view.x / 560.0, g.view.y / 900.0)


## Every frame on the start page: the car keeps doing tricks, the crowd watches, the hint writes itself.
func update(delta: float) -> void:
	if mode == "gone":
		return
	hint_t += delta
	driver.step(delta)
	_place_car(delta)
	hint.queue_redraw()


## Hold: from wherever it is, the car heads for the start line on one sweeping line through the stats.
func begin_exit(line: Vector2) -> void:
	mode = "exit"
	var p := driver.at(driver.s)
	var d := Vector2.from_angle(driver.dir(driver.s))
	var reach := clampf(p.distance_to(line) * 0.45, 90.0, 220.0)
	var path := PackedVector2Array()
	var c1 := p + d * reach
	var c2 := line + Vector2(0, 150)
	for i in 121:
		path.append(p.bezier_interpolate(c1, c2, line, i / 120.0))
	driver.set_path(path, false)
	driver.vmax = 250.0
	driver.grip = 650.0  # throws it through the turn out of the meet sideways rather than braking for it
	driver.end_speed = -1.0  # no lifting at the end: it reaches the line flat out and the run carries that on
	driver.accel = 340.0  # it means it: hard on the throttle out of the meet
	driver.spins = []
	driver.stops = []
	driver.hold = 0.0


## Whether the player can take over: the car has turned out of the donuts and is pointing at the road.
func can_take_over(line: Vector2) -> bool:
	if driver.s < 40.0:
		return false
	var to_line := (line - driver.at(driver.s)).angle()
	return absf(wrapf(driver.dir(driver.s) - to_line, -PI, PI)) < deg_to_rad(30.0)


## After the run has started: the drone that was filming flies back to the pit and hovers there.
func after(delta: float) -> void:
	var home := pad + Vector2(90, -110)
	if drone.distance_to(home) < 0.5:
		return
	drone = drone.move_toward(home, minf(220.0, 40.0 + drone.distance_to(home) * 1.6) * delta)
	sky.queue_redraw()


## The run out to the line, every frame; true once the car is on it.
func drive_exit(delta: float) -> bool:
	hint_t += delta
	driver.step(delta)
	_place_car(delta)
	return driver.s >= driver.total - 0.5


func _redraw_art() -> void:
	_bake_art()


## What the still drawing shows, so a kept image is only reused when it would look the same.
func _art_key() -> String:
	var cfg := _cfg()
	return "%s|%s|%s|%d|%d|%d" % [g.view, art_rect, String(cfg.get_value("dev", "car", "evo")),
		int(cfg.get_value("best", "score", 0)), int(cfg.get_value("best", "dist", 0)), int(cfg.get_value("best", "combo", 1))]


## Shows the still drawing: a kept image if there is one, else draws it once into an image (a frame later
## the image is copied out and kept, and the drawing setup is let go).
func _bake_art() -> void:
	var key := _art_key()
	if baked.has(key):
		shown.texture = baked[key]
		return
	if bake == null:
		bake = SubViewport.new()
		bake.transparent_bg = true
		bake.size = Vector2i(art_rect.size * art_scale)
		add_child(bake)  # in the tree first: its canvas exists only from then
		bake.canvas_transform = Transform2D(0.0, Vector2.ONE * art_scale, 0.0, -art_rect.position * art_scale)
		art = DrawNode.new()
		art.draw_fn = _draw_art
		bake.add_child(art)
	art.queue_redraw()
	bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	shown.texture = bake.get_texture()
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or bake == null or key != _art_key():
		return  # gone, or changed again meanwhile (that change baked its own)
	var tex := ImageTexture.create_from_image(bake.get_texture().get_image())
	baked.clear()  # keep only the latest: each is several MB of graphics memory
	baked[key] = tex
	shown.texture = tex
	var old := bake  # let go of the drawing setup: the drawing first, the image surface a frame later
	bake = null
	art.queue_free()
	art = null
	await get_tree().process_frame
	if is_instance_valid(old):  # (the page may have gone meanwhile, taking it with it)
		old.queue_free()


## The run has started properly: the page stops moving and stays on the paper.
func leave() -> void:
	mode = "gone"
	panel.queue_redraw()
	hint.queue_redraw()
	crowd.queue_redraw()


## Puts the game's car where the driver is, with its slide, smoke and fresh marks; the crowd and the
## drone follow it.
func _place_car(delta: float) -> void:
	var s := driver.s
	g.pos = driver.at(s)
	g.vdir = driver.dir(s)
	g.heading = g.vdir + driver.slip + driver.extra
	g.speed = driver.v
	g.slip = absf(wrapf(g.heading - g.vdir, -PI, PI))
	var burn := driver.burnout
	if burn:  # standing on the brakes, rear tyres spinning: the car shudders and the tyres scream
		g.heading += sin(hint_t * 47.0) * 0.035
		g.slip = 0.9
	g.drift_amt = clampf(g.slip / 0.7, 0.0, 1.0)
	if delta <= 0.0:
		return
	var wh: Array = g._wheels()
	var sliding: bool = burn or (g.slip > 0.14 and g.speed > 30.0)
	if mode == "home":  # the trick marks (the run itself lays the game's own skids)
		var along := Vector2.from_angle(g.vdir)
		for k in 4:  # the rears mark as soon as it slides, the fronts in a real drift (as in the run)
			if burn:  # a burnout scrubs black rubber on the spot under the rear tyres
				if k < 2:
					_mark(k, wh[k] + along * randf_range(-6.0, 6.0), true)
			else:
				_mark(k, wh[k], sliding if k < 2 else (g.slip > 0.3 and g.speed > 30.0))
		trick_marks.queue_redraw()
	g.fx.emit(delta, [wh[0], wh[1]], g.vdir, 230.0 if burn else g.speed, g.slip, 330.0, sliding, false)
	for p in people:
		var want: float = (g.pos - p["p"]).angle()
		p["look"] = p["look"] + wrapf(want - p["look"], -PI, PI) * (1.0 - exp(-delta * p["rate"]))
	crowd.queue_redraw()
	drone = drone.lerp(g.pos + Vector2(70, -80), 1.0 - exp(-delta * 0.9))
	sky.queue_redraw()


func _mark(k: int, w: Vector2, on: bool) -> void:
	var runs: Array = marks[k]
	if not on:
		if not runs.is_empty() and (runs[runs.size() - 1] as PackedVector2Array).size() > 0:
			runs.append(PackedVector2Array())  # lift: the next slide starts a new mark
		return
	if runs.is_empty():
		runs.append(PackedVector2Array())
	var cur: PackedVector2Array = runs[runs.size() - 1]
	if cur.size() == 0 or cur[cur.size() - 1].distance_to(w) > 5.0:
		cur.append(w)
		runs[runs.size() - 1] = cur
	var total := 0
	for r in runs:
		total += (r as PackedVector2Array).size()
	while total > MAX_MARKS and not runs.is_empty():  # the oldest marks wear away
		var first: PackedVector2Array = runs[0]
		if first.size() <= 1:
			runs.pop_front()
			total -= first.size()
		else:
			first.remove_at(0)
			runs[0] = first
			total -= 1


# ---------------------------------------------------------------- the trick loop

var _spins: Array = []  # [from, to, turn]: the body turning round on its own (the 360, the moonwalk)
var _stops: Array = []  # [at, seconds]: a stop before launching off again (the burnout)
var slalom_cones: Array = []


## A figure of eight: one and a half donut laps round the left loop, across the middle (with a full
## 360 spin of the body on the way), one and a half laps the other way round the right loop, and back.
func _trick_path() -> PackedVector2Array:
	var a := pad + Vector2(-LOBE_X, 0)
	var b := pad + Vector2(LOBE_X, 0)
	var r := LOBE
	var out := PackedVector2Array()
	out.append_array(_arc(a, r, PI * 0.5, PI * 0.5 + PI * 3.0))  # round the left loop, clockwise
	var i_cross := out.size()
	out.append_array(_cross(a + Vector2(0, -r), b + Vector2(0, r), Vector2.RIGHT))
	var i_cross_end := out.size()
	out.append_array(_arc(b, r, PI * 0.5, PI * 0.5 - PI * 3.0))  # round the right loop, anticlockwise
	out.append_array(_cross(b + Vector2(0, -r), a + Vector2(0, r), Vector2.LEFT))
	var acc := _lengths(out)
	var c0: float = acc[i_cross]
	var c1: float = acc[i_cross_end]
	_spins = [[lerpf(c0, c1, 0.22), lerpf(c0, c1, 0.78), TAU]]  # the 360 through the middle
	_stops = []
	slalom_cones.clear()
	return out


static func _lengths(p: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(p.size())
	for i in range(1, p.size()):
		out[i] = out[i - 1] + p[i].distance_to(p[i - 1])
	return out


static func _arc(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := int(absf(to - from) * r / 4.0)
	for i in steps:
		var t := from + (to - from) * i / float(steps)
		out.append(c + Vector2(cos(t), sin(t)) * r)
	return out


static func _cross(p0: Vector2, p3: Vector2, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 60:
		out.append(p0.bezier_interpolate(p0 + d * 110.0, p3 - d * 110.0, p3, i / 60.0))
	return out


## A smooth curve from p0 (heading d0) to p3 (arriving heading d3), the end point left for what follows.
static func _link(p0: Vector2, d0: Vector2, p3: Vector2, d3: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dist := p0.distance_to(p3)
	var h := maxf(40.0, dist * k)
	var n := maxi(8, int(dist / 4.0))
	for i in n:
		out.append(p0.bezier_interpolate(p0 + d0 * h, p3 - d3 * h, p3, i / float(n)))
	return out


## Follows a path the way a driver would: brakes for tight turns before reaching them, lets the tail swing
## out with the speed and the tightness of the turn (a damped pendulum, so it flicks from one way to the
## other naturally), can throw the body round on its own (spins, a backwards slide), and can stop dead for
## a burnout and launch off again with the tail kicking out.
class Driver:
	var pts := PackedVector2Array()
	var acc := PackedFloat32Array()
	var total := 0.0
	var closed := true
	var s := 0.0
	var v := 110.0
	var slip := 0.0
	var slip_v := 0.0
	var extra := 0.0  # the body's own turn on top of the slide (spins, the moonwalk)
	var spins: Array = []  # [from, to, turn]
	var stops: Array = []  # [at, seconds]
	var hold := 0.0  # seconds left standing at a stop
	var stop_done := -1  # the stop already made this lap
	var burnout := false
	var launch := 0.0  # seconds of hard throttle after a stop
	var vmax := 200.0
	var grip := 220.0  # how hard it may corner: speed = sqrt(grip * radius)
	var end_speed := -1.0  # an open path is arrived at about this fast
	var accel := 150.0

	func set_path(p: PackedVector2Array, loop: bool) -> void:
		pts = p
		closed = loop
		acc = PackedFloat32Array()
		acc.resize(p.size())
		var t := 0.0
		for i in range(1, p.size()):
			t += p[i].distance_to(p[i - 1])
			acc[i] = t
		total = t + (p[p.size() - 1].distance_to(p[0]) if loop else 0.0)
		s = 0.0

	func at(d: float) -> Vector2:
		d = fposmod(d, total) if closed else clampf(d, 0.0, acc[acc.size() - 1])
		var hi := acc.size() - 1
		if d >= acc[hi]:
			if not closed:
				return pts[hi]
			return pts[hi].lerp(pts[0], (d - acc[hi]) / maxf(total - acc[hi], 0.001))
		var lo := 0
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if acc[mid] <= d:
				lo = mid
			else:
				hi = mid
		return pts[lo].lerp(pts[hi], (d - acc[lo]) / maxf(acc[hi] - acc[lo], 0.001))

	func dir(d: float) -> float:
		if not closed:  # near the ends of an open path, look along its last (or first) stretch, never past it
			d = clampf(d, 4.0, total - 4.0)
		return (at(d + 4.0) - at(d - 4.0)).angle()

	func curv(d: float) -> float:
		if not closed:
			d = clampf(d, 18.0, total - 18.0)
		return wrapf(dir(d + 14.0) - dir(d - 14.0), -PI, PI) / 28.0

	func _turn_at(d: float) -> float:
		var e := 0.0
		for sp in spins:
			e += float(sp[2]) * smoothstep(sp[0], sp[1], d)
		return e

	func _slow(d: float) -> bool:
		for sp in spins:
			if d >= float(sp[0]) - 30.0 and d <= float(sp[1]) + 10.0:
				return true
		return false

	## In small slices, so a slow frame never makes the slide's spring overshoot.
	func step(delta: float) -> void:
		var n := maxi(1, ceili(delta * 120.0))
		for i in n:
			_step(delta / n)

	func _step(delta: float) -> void:
		burnout = false
		if hold > 0.0:  # stopped: the burnout
			hold -= delta
			v = 0.0
			burnout = true
			if hold <= 0.0:  # let go: it launches, the tail kicking out as the tyres bite
				launch = 0.9
				slip_v += 2.4 if randf() < 0.5 else -2.4
			slip_v += ((0.0 - slip) * 24.0 - slip_v * 7.0) * delta
			slip += slip_v * delta
			return
		var k := maxf(absf(curv(s)), absf(curv(s + maxf(v, 40.0) * 0.45)))
		var vt := clampf(sqrt(grip / maxf(k, 0.0005)), 60.0, vmax)
		if _slow(s + v * 0.5):
			vt = minf(vt, 95.0)
		for i in stops.size():  # braking to stop on the mark
			var ahead: float = float(stops[i][0]) - s
			if i != stop_done and ahead > -1.0 and ahead < 240.0:
				vt = minf(vt, sqrt(2.0 * 240.0 * maxf(ahead, 0.0)) + 1.0)
		if not closed and end_speed > 0.0:
			vt = minf(vt, end_speed + (total - s) * 0.9)
		launch = maxf(0.0, launch - delta)
		var up := 330.0 if launch > 0.0 else accel
		v = move_toward(v, vt, (up if vt > v else 280.0) * delta)
		var before := s
		s += v * delta
		if closed and s >= total:
			s -= total
			before -= total
			stop_done = -1
		for i in stops.size():
			var at_s: float = stops[i][0]
			if i != stop_done and before < at_s and s >= at_s - 0.5:
				stop_done = i
				s = at_s
				v = 0.0
				hold = stops[i][1]
		var want := clampf(curv(s) * v * 0.55, -1.15, 1.15)
		slip_v += ((want - slip) * 24.0 - slip_v * 7.0) * delta
		slip += slip_v * delta
		if closed:
			extra = _turn_at(s)
		else:  # out on the run to the line: settle on the nearest whole turn
			extra += (roundf(extra / TAU) * TAU - extra) * (1.0 - exp(-delta * 5.0))


# ---------------------------------------------------------------- input

## A tap on the page (world position). True when it was meant for the page (gear, settings), so it must
## not count as holding a side.
func tap(wp: Vector2) -> bool:
	if mode == "home":
		if wp.distance_to(gear) < GEAR_R + 30.0:
			Sfx.tap()
			mode = "settings"
			cam_pos = settings_cam
			cam_zoom = _settings_zoom()
			return true
		return false
	if mode != "settings":
		return false
	for h in hits:
		if (h["rect"] as Rect2).has_point(wp):
			_use(h, wp)
			return true
	if not _panel_rect().has_point(wp):
		_close()  # a tap anywhere else goes back
	return true  # while the settings are open, nothing starts a run


func drag(wp: Vector2) -> void:
	if mode == "settings" and drag_key == "hold":
		for h in hits:
			if h["key"] == "hold":
				_slide(h, wp)


func release() -> void:
	drag_key = ""


func _panel_rect() -> Rect2:
	return Rect2(panel_x - 30.0, panel_top - 70.0, PANEL_W + 60.0, ROW * 10.0 + 120.0)


## Back to the start page: the writing stays and the camera pans home. A handling change needs the road
## drawn again, so then the page is rebuilt, starting from this same view.
func _close() -> void:
	Sfx.tap()
	if rebuild:
		reopen_from_settings = true
		g.home_requested.emit()
		return
	mode = "home"
	cam_pos = home_cam
	cam_zoom = home_zoom


func _use(h: Dictionary, wp: Vector2) -> void:
	var key: String = h["key"]
	match h["kind"]:
		"toggle":
			Sfx.tap()
			if key in ["sound", "music", "vibration"]:
				Game.set_setting(key, not _game_on(key))
				if key == "music":
					g._radio()
			else:
				_set_dev(key, not bool(_cfg().get_value("dev", key, true)))
		"cycle":
			Sfx.tap()
			var opts: Dictionary = _c(h["opts"])
			var ids := opts.keys()
			var cur := ids.find(String(_cfg().get_value("dev", key, h["def"])))
			_set_dev(key, ids[(cur + 1) % ids.size()])
		"slider":
			drag_key = key
			_slide(h, wp)
	panel.queue_redraw()


func _slide(h: Dictionary, wp: Vector2) -> void:
	var r: Rect2 = h["rect"]
	var v := snappedf(clampf((wp.x - r.position.x - 20.0) / (r.size.x - 40.0), 0.0, 1.0) * 0.6, 0.01)
	_set_dev("hold", v)
	panel.queue_redraw()


func _game_on(key: String) -> bool:
	match key:
		"sound": return Game.sound_on
		"music": return Game.music_on
	return Game.vibration_on


func _cfg() -> ConfigFile:
	return g._load()


## Saved straight away and applied live where the page allows (drift.gd apply_dev); handling waits for
## the page to be drawn again.
func _set_dev(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg.set_value("dev", key, value)
	cfg.save(_c("SAVE"))
	if key == "handling":
		rebuild = true
	else:
		g.apply_dev(key, value)
	if key == "car":
		_redraw_art()  # the stats belong to the car


## One of drift.gd's constants (read through its script, not the node).
func _c(name: String) -> Variant:
	return g.get_script().get_script_constant_map()[name]


# ---------------------------------------------------------------- the meet: where everything stands

func _build_meet() -> void:
	var t := MEET_TOP
	var b := meet_bot
	var mid := pad.y
	# show cars, parked the way they are at a takeover: at angles, in loose clusters, fronts to the action
	var spots := [
		[-270, t + 38, 1.25, {"hood": true}], [-175, t + 30, 1.75, {}], [175, t + 32, 1.4, {"lights": true}], [270, t + 40, 1.85, {"hood": true}],
		[-300, mid - 20, 0.25, {"lights": true}], [300, mid + 10, PI - 0.2, {"doors": true}],
		[-150, b - 34, -1.35, {"boot": true}], [-60, b - 30, -1.7, {"hood": true}], [70, b - 32, -1.45, {"lights": true}],
		[175, b - 36, -1.9, {"hood": true}], [290, b - 34, -2.3, {}],
	]
	for sp in spots:
		cars.append({"p": Vector2(sp[0], sp[1]), "ang": sp[2], "opts": sp[3]})
		if sp[3].get("lights", false):
			lights.append(Vector2(sp[0], sp[1]) + Vector2.from_angle(sp[2]) * 90.0)
	lights.append(pad)
	for lp in [Vector2(-335, t + 6), Vector2(335, t + 6), Vector2(-335, b - 6)]:
		lights.append(lp)
	# the crowd: lining the cones, round the popped hoods, by the van, on chairs, behind the tripod
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kinds := ["phone", "cap", "hands", "phone", "hood", "hands", "cap", "phone", "kid", "hands"]
	var rx := LOBE_X + LOBE + 70.0
	var ry := minf(LOBE + 62.0, (b - t) * 0.5 - 40.0)
	var n := 30
	for i in n:
		var a := -PI * 0.5 + 0.5 + TAU * (i + rng.randf_range(-0.2, 0.2)) / n * 0.93
		var p := pad + Vector2(cos(a) * (rx + rng.randf_range(0, 18)), sin(a) * (ry + rng.randf_range(0, 14)))
		if absf(p.x) > 330.0:
			continue
		_person(p, kinds[i % kinds.size()], rng)
	for c in cars:  # two or three people round each popped hood, looking in
		var o: Dictionary = c["opts"]
		if not (o.get("hood", false) or o.get("doors", false) or o.get("boot", false)):
			continue
		var front: Vector2 = c["p"] + Vector2.from_angle(c["ang"]) * (52.0 if not o.get("boot", false) else -52.0)
		for j in 2 + int(o.get("hood", false)):
			_person(front + Vector2(rng.randf_range(-12, 12), rng.randf_range(-10, 10)), kinds[(j * 3 + int(c["p"].x)) % kinds.size()], rng)
	var van := Vector2(-262, b - 46)
	for p in [van + Vector2(30, -40), van + Vector2(48, -34), van + Vector2(14, -46)]:
		_person(p, "hands", rng)
	_person(Vector2(232, b - 70), "chair", rng)
	_person(Vector2(257, b - 74), "chair", rng)
	_person(Vector2(LOBE_X + 120.0, t + 92.0), "camera", rng)
	_person(Vector2(0, t - 4), "torch", rng)  # the marshal at the way out
	_person(Vector2(-200, b - 92), "dog", rng)  # someone brought the dog

	people.sort_custom(func(x, y): return x["p"].y < y["p"].y)  # back to front


const DOODLE := Color(0.2, 0.2, 0.25, 0.85)
## The kinds of people at the meet, as doodles: chosen by what they're doing, with a few just there.
const DOODLE_KINDS := ["stick", "blob", "cap", "hoodie", "stick", "hips", "cheer", "drink", "blob", "stick"]


func _person(p: Vector2, kind: String, rng: RandomNumberGenerator) -> void:
	var a := (pad - p).angle()
	var look := kind
	if kind in ["hands", "hood"]:
		look = DOODLE_KINDS[rng.randi() % DOODLE_KINDS.size()]
	people.append({"p": p, "ang": a, "look": a, "kind": kind, "rate": rng.randf_range(2.0, 4.5),
		"segs": _segments(_doodle(look, rng))})


## A doodle's lines as pairs of points, so the whole crowd draws in one batch.
static func _segments(lines: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for l in lines:
		var pts: PackedVector2Array = l
		for i in pts.size() - 1:
			out.append(pts[i])
			out.append(pts[i + 1])
	return out


## One careless pencil person, feet at (0, 0), about 19 tall, facing right (+x). Each line wobbles and
## overshoots a little; nothing is quite closed.
func _doodle(kind: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var k := 0.72 if kind == "kid" else rng.randf_range(0.9, 1.08)
	var j := func(pts: Array) -> PackedVector2Array:  # the hand's wobble
		var o := PackedVector2Array()
		for v in pts:
			o.append((v + Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45))) * k)
		return o
	var head := func(c: Vector2, r: float) -> PackedVector2Array:  # a quick loop, a little more than round
		var pts: Array = []
		var a0 := rng.randf() * TAU
		for i in 11:
			var t := a0 + TAU * 1.12 * i / 10.0
			pts.append(c + Vector2(cos(t) * r * (1.0 + 0.08 * i / 10.0), sin(t) * r * 1.08))
		return j.call(pts)
	var hip := Vector2(rng.randf_range(-0.4, 0.4), -7.5)
	var neck := Vector2(rng.randf_range(-0.3, 0.6), -14.0)
	var crown := neck + Vector2(0.4, -3.0)
	match kind:
		"blob":  # a round sack of a body, little legs
			var body: Array = []
			for i in 12:
				var t := TAU * 1.05 * i / 11.0 + 0.3
				body.append(Vector2(cos(t) * 3.8, -10.5 + sin(t) * 4.2))
			out.append(j.call(body))
			out.append(j.call([Vector2(-1.5, -6.5), Vector2(-1.8, 0.2)]))
			out.append(j.call([Vector2(1.5, -6.5), Vector2(1.9, 0.2)]))
			out.append(head.call(Vector2(0.3, -17.2), 2.6))
			return out
		"hoodie":  # a pointed hood, a boxy body, hands in the front pocket
			out.append(j.call([Vector2(-3.4, -7.2), Vector2(-3.6, -13.2), Vector2(-1.2, -18.6), Vector2(1.8, -18.2), Vector2(3.6, -13.0), Vector2(3.3, -7.0), Vector2(-3.2, -7.2)]))
			out.append(head.call(Vector2(0.6, -15.4), 1.8))
			out.append(j.call([Vector2(-1.8, -9.8), Vector2(1.9, -9.9)]))
			out.append(j.call([Vector2(-1.3, -7.2), Vector2(-1.6, 0.2)]))
			out.append(j.call([Vector2(1.3, -7.2), Vector2(1.7, 0.2)]))
			return out
		"chair":  # sitting back in a camping chair, legs stuck out
			out.append(j.call([Vector2(-4.5, -4.5), Vector2(-4.0, -12.0)]))
			out.append(j.call([Vector2(-4.6, -5.0), Vector2(3.5, -4.6), Vector2(4.2, 0.2)]))
			out.append(j.call([Vector2(-4.0, -4.6), Vector2(-4.6, 0.2)]))
			out.append(j.call([Vector2(-1.5, -5.2), Vector2(-2.2, -11.6)]))
			out.append(j.call([Vector2(-1.4, -5.0), Vector2(4.6, -4.2), Vector2(5.6, -0.4)]))
			out.append(j.call([Vector2(-2.0, -10.4), Vector2(1.6, -7.2)]))
			out.append(head.call(Vector2(-2.2, -14.2), 2.4))
			return out
		"dog":  # someone brought the dog
			out.append(j.call([Vector2(-4.0, -4.0), Vector2(2.6, -4.4), Vector2(3.6, -6.4), Vector2(5.4, -6.2), Vector2(5.0, -4.2), Vector2(3.4, -3.6)]))
			out.append(j.call([Vector2(-3.4, -4.0), Vector2(-3.6, 0.2)]))
			out.append(j.call([Vector2(-1.6, -4.0), Vector2(-1.4, 0.2)]))
			out.append(j.call([Vector2(1.4, -4.2), Vector2(1.2, 0.2)]))
			out.append(j.call([Vector2(2.6, -4.2), Vector2(2.9, 0.2)]))
			out.append(j.call([Vector2(-4.0, -4.0), Vector2(-5.6, -6.6)]))
			return out
	# the stick-figure family: body, arms by what they're doing, legs
	out.append(head.call(crown + Vector2(0, -1.2), 2.5))
	out.append(j.call([neck, hip]))
	match kind:
		"phone", "camera":  # one arm up, filming
			out.append(j.call([neck + Vector2(0, 1.2), neck + Vector2(4.2, -0.4), neck + Vector2(5.6, -3.2)]))
			var sz := 2.8 if kind == "camera" else 1.8
			out.append(j.call([neck + Vector2(5.0, -3.2), neck + Vector2(5.0 + sz, -3.4), neck + Vector2(5.0 + sz, -3.2 - sz * 1.5), neck + Vector2(5.0, -3.0 - sz * 1.5), neck + Vector2(5.0, -3.2)]))
			out.append(j.call([neck + Vector2(0, 1.2), neck + Vector2(-2.6, 4.8)]))
		"cheer":  # both arms up
			out.append(j.call([neck + Vector2(-3.6, -4.6), neck + Vector2(0, 1.0), neck + Vector2(3.8, -4.4)]))
		"hips":  # hands on hips
			out.append(j.call([neck + Vector2(0, 1.0), neck + Vector2(-3.2, 3.4), hip + Vector2(-0.4, -0.6)]))
			out.append(j.call([neck + Vector2(0, 1.0), neck + Vector2(3.2, 3.4), hip + Vector2(0.5, -0.6)]))
		"drink":  # holding a coffee
			out.append(j.call([neck + Vector2(0, 1.2), neck + Vector2(2.8, 4.0), neck + Vector2(4.0, 2.4)]))
			out.append(j.call([neck + Vector2(3.6, 2.6), neck + Vector2(3.8, 0.4), neck + Vector2(5.4, 0.4), neck + Vector2(5.2, 2.6)]))
			out.append(j.call([neck + Vector2(0, 1.2), neck + Vector2(-2.6, 5.2)]))
		"torch":  # the marshal, torch out
			out.append(j.call([neck + Vector2(0, 1.4), neck + Vector2(6.0, 2.0)]))
			out.append(j.call([neck + Vector2(6.0, 1.0), neck + Vector2(8.5, 1.4)]))
			for r in [-1.0, 0.0, 1.0]:
				out.append(j.call([neck + Vector2(9.5, 1.4), neck + Vector2(34.0, 1.4 + r * 6.0)]))
			out.append(j.call([neck + Vector2(0, 1.2), neck + Vector2(-2.6, 5.2)]))
		_:  # arms hanging, a little bent
			out.append(j.call([neck + Vector2(-2.8, 5.4), neck + Vector2(0, 1.0), neck + Vector2(2.9, 5.2)]))
	if kind == "cap":
		out.append(j.call([crown + Vector2(-2.4, -1.6), crown + Vector2(0.0, -3.2), crown + Vector2(2.4, -1.6), crown + Vector2(4.6, -1.3)]))
	var stride := rng.randf_range(1.0, 2.6)
	out.append(j.call([Vector2(-stride, 0.2), hip, Vector2(stride, 0.2)]))
	return out


# ---------------------------------------------------------------- drawing

func _draw_art(n: Node2D) -> void:
	var font: Font = g.hand_font()
	var hw: float = g.widths[0] * 0.5
	_stroke(n, [Vector2(-hw + 6, START_Y), Vector2(-hw * 0.3, START_Y + 2.0), Vector2(hw * 0.3, START_Y - 1.5), Vector2(hw - 6, START_Y + 1.0)], 3.2, PENCIL, 1)
	_stroke(n, [Vector2(-hw + 12, START_Y + 10), Vector2(hw - 14, START_Y + 11)], 1.8, SOFT, 2)
	_stats(n, font)
	_meet(n, font)
	_gear(n)
	_write(n, font, "Doodle Drift", Vector2(0, title_y), 124, -0.03, 3)
	_stroke(n, _wave(Vector2(-230, title_y + 24), Vector2(230, title_y + 17), 5.0, 3.0), 2.6, PENCIL, 4)
	_best(n, font, hw)


## The chosen car's name, and its stats as pencil bars in two columns across the page, hatched in.
func _stats(n: Node2D, font: Font) -> void:
	var cars_c: Dictionary = _c("CARS")
	var car: Dictionary = cars_c.get(String(_cfg().get_value("dev", "car", "evo")), cars_c["evo"])
	var x0 := -PAGE_W * 0.46
	_write_left(n, font, String(car["name"]), Vector2(x0, STATS_Y + 14.0), 46, -0.02, 60)
	_stroke(n, _wave(Vector2(x0, STATS_Y + 24.0), Vector2(x0 + 150.0, STATS_Y + 21.0), 2.0, 2.0), 1.8, PENCIL, 59)
	var rows := [
		["top speed", float(_c("SPEED")) / 400.0],
		["pull", float(_c("ACCEL")) / 200.0],
		["grip", float(_c("GRIP")) / 10.0],
		["drift", float(_c("FLOW_ANGLE")[1]) / 70.0],
	]
	for i in rows.size():
		var cx := x0 + (i % 2) * (PAGE_W * 0.48)
		var ry := STATS_Y + 66.0 + (i / 2) * 44.0
		_write_left(n, font, rows[i][0], Vector2(cx, ry), 28, 0.0, 61 + i)
		var b := Rect2(cx + 112.0, ry - 16.0, PAGE_W * 0.46 - 130.0, 15.0)
		_stroke(n, [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y), b.position + Vector2(0, -1)], 1.6, PENCIL, 70 + i)
		var fill: float = clampf(rows[i][1], 0.0, 1.0) * b.size.x
		var k := 0.0
		while k < fill - 3.0:
			_stroke(n, [Vector2(b.position.x + k + 2.0, b.end.y - 1.5), Vector2(b.position.x + k + 9.0, b.position.y + 1.5)], 1.3, PENCIL, 80 + i * 40 + int(k))
			k += 4.5


## The still part of the meet: old donut marks, a burnout strip, cones, show cars, lamp posts, the van,
## chairs and cooler, the tripod, the sign.
func _meet(n: Node2D, font: Font) -> void:
	var a := pad + Vector2(-LOBE_X, 0)
	var b := pad + Vector2(LOBE_X, 0)
	_donut(n, a + Vector2(-6, 4), LOBE + 4.0, 7, 3, 1.0)
	_donut(n, b + Vector2(5, -3), LOBE + 2.0, 6, 17, 0.85)
	_donut(n, pad + Vector2(-230, -10), 48.0, 3, 29, 0.55)
	for side in [-1.0, 1.0]:  # a burnout strip: two straight black bars where someone sat and spun the tyres
		var o := pad + Vector2(170, 95)
		_stroke(n, [o + Vector2(-60, side * 11.0), o + Vector2(0, side * 11.0 + 1.0), o + Vector2(60, side * 11.0)], 4.6, Color(RUBBER, 0.32), 40 + int(side))
	for i in cars.size():
		var c: Dictionary = cars[i]
		_show_car(n, c["p"], c["ang"], 400 + i * 70, c["opts"])
	for lp in [Vector2(-335, MEET_TOP + 6), Vector2(335, MEET_TOP + 6), Vector2(-335, meet_bot - 6)]:
		_lamp(n, lp, 1700 + int(lp.x))
	_van(n, Vector2(-262, meet_bot - 46), 0.04, 1800)
	_cooler(n, Vector2(245, meet_bot - 100), 1820)
	_tripod(n, Vector2(LOBE_X + 110.0, MEET_TOP + 84.0), 1860)


func _donut(n: Node2D, c: Vector2, r: float, laps: int, sd: int, strength: float) -> void:
	# two rings a lap (one per rear tyre, 1.5 m apart), laid again and again with the centre wandering,
	# each ring made of thin rubber streaks so it darkens where laps cross, and the run-in
	for l in laps:
		var cc := c + Vector2(cos(l * 1.7 + sd) * 7.0, sin(l * 1.3 + sd) * 5.0)
		for off in [0.0, -1.5 * M]:
			var rr: float = r + off + _n(l, sd) * 3.0
			var a0 := _n(l + 9, sd) * PI
			var span := PI * (1.6 + 0.35 * absf(_n(l + 3, sd)))
			for st in 3:
				var pts: Array = []
				for i in 37:
					var ang := a0 + span * i / 36.0
					var rj := rr + _n(i + st * 40, sd + l) * 1.2 + st * 1.1
					pts.append(cc + Vector2(cos(ang) * rj, sin(ang) * rj * 0.97))
				_stroke(n, pts, 1.6 + st * 0.4, Color(RUBBER, 0.11 * strength), sd + l * 10 + st + (5 if off != 0.0 else 0), 0.4)
	var e := c + Vector2(r + 10.0, 0)
	for off in [-12.0, 12.0]:
		_stroke(n, [e + Vector2(90, 70 + off), e + Vector2(50, 30 + off * 0.6), e + Vector2(12, 6 + off * 0.3), e + Vector2(-4, -10 + off * 0.2)], 2.6, Color(RUBBER, 0.13 * strength), sd + 90 + int(off), 0.5)


## A show car from above: rounded body, windscreen and rear glass, roof, mirrors, tyres peeking out.
## Options: hood (popped: the bonnet stands over the windscreen, engine bay showing), doors, boot (open on a
## speaker box), lights (two pencil beams ahead).
func _show_car(n: Node2D, c: Vector2, ang: float, sd: int, o: Dictionary) -> void:
	var t := func(v: Vector2) -> Vector2: return c + v.rotated(ang)
	var sh := PackedVector2Array()
	for v in [Vector2(-42, -12), Vector2(36, -13), Vector2(36, 21), Vector2(-42, 21)]:
		sh.append(c + v.rotated(ang))
	n.draw_colored_polygon(sh, Color(0, 0, 0, 0.09))
	var L := 38.0
	var W := 15.0
	var body := [Vector2(-L + 4, -W), Vector2(L - 9, -W - 0.5), Vector2(L - 2, -W + 4), Vector2(L, -6), Vector2(L, 6), Vector2(L - 2, W - 4), Vector2(L - 9, W + 0.5), Vector2(-L + 4, W), Vector2(-L, W - 4), Vector2(-L, -W + 4), Vector2(-L + 4, -W)]
	var bp := PackedVector2Array()
	for v in body:
		bp.append(t.call(v))
	n.draw_colored_polygon(bp, Color(0.97, 0.96, 0.93))
	_stroke(n, body.map(t), 1.8, PENCIL, sd)
	for w in [Vector2(23, -16.5), Vector2(23, 16.5), Vector2(-24, -16.5), Vector2(-24, 16.5)]:
		_stroke(n, [t.call(w + Vector2(-6, 0)), t.call(w + Vector2(6, 0))], 3.2, Color(RUBBER, 0.85), sd + 2 + int(w.x + w.y), 0.3)
	_stroke(n, [t.call(Vector2(9, -17.5)), t.call(Vector2(9, -20))], 2.2, PENCIL, sd + 9)
	_stroke(n, [t.call(Vector2(9, 17.5)), t.call(Vector2(9, 20))], 2.2, PENCIL, sd + 10)
	_stroke(n, [Vector2(14, -12), Vector2(9, 0), Vector2(14, 12)].map(t), 1.3, PENCIL, sd + 11)
	_stroke(n, [Vector2(8, -11.5), Vector2(-16, -11.5), Vector2(-16, 11.5), Vector2(8, 11.5), Vector2(8.5, -11)].map(t), 1.2, Color(PENCIL, 0.7), sd + 12)
	_stroke(n, [Vector2(-22, -11), Vector2(-25, 0), Vector2(-22, 11)].map(t), 1.2, Color(PENCIL, 0.7), sd + 13)
	if o.get("hood", false):
		_stroke(n, [Vector2(15, -13), Vector2(3, -13.5), Vector2(3, 13.5), Vector2(15, 13), Vector2(15.5, -12)].map(t), 1.6, PENCIL, sd + 20)
		for k in 5:
			_stroke(n, [t.call(Vector2(4 + k * 2.4, -12)), t.call(Vector2(5 + k * 2.4, 12))], 0.8, Color(PENCIL, 0.35), sd + 21 + k, 0.2)
		for k in 4:
			_stroke(n, [Vector2(18 + k * 4.5, -9), Vector2(20 + k * 4.5, -2 + _n(k, sd) * 3.0), Vector2(18 + k * 4.5, 8)].map(t), 1.1, Color(PENCIL, 0.6), sd + 30 + k, 0.3)
		_stroke(n, _circle(t.call(Vector2(29, -6)), 3.2, 1.0, 0.0), 1.1, Color(PENCIL, 0.7), sd + 35, 0.2)
	if o.get("doors", false):
		_stroke(n, [t.call(Vector2(4, -W)), t.call(Vector2(-10, -W - 13))], 1.7, PENCIL, sd + 40)
		_stroke(n, [t.call(Vector2(4, W)), t.call(Vector2(-10, W + 13))], 1.7, PENCIL, sd + 41)
	if o.get("boot", false):
		_stroke(n, [Vector2(-L + 2, -11), Vector2(-L - 9, -12), Vector2(-L - 9, 12), Vector2(-L + 2, 11)].map(t), 1.4, PENCIL, sd + 50)
		_stroke(n, _circle(t.call(Vector2(-L + 7, -5)), 4.0, 1.0, 0.0), 1.3, PENCIL, sd + 51, 0.2)
		_stroke(n, _circle(t.call(Vector2(-L + 7, 5)), 4.0, 1.0, 0.0), 1.3, PENCIL, sd + 52, 0.2)
	if o.get("lights", false):
		for y in [-10.0, 10.0]:
			for k in [-1.0, 0.0, 1.0]:
				_stroke(n, [t.call(Vector2(L, y)), t.call(Vector2(L + 120, y * 1.4 + k * 22))], 0.9, Color(PENCIL, 0.16), sd + 60 + int(y + k * 3))


## A traffic cone from above: the dark tip and the round base, with a soft shadow.
func _cone_quick(n: Node2D, c: Vector2) -> void:
	n.draw_circle(c + Vector2(-1.5, 2.5), 6.0, Color(0, 0, 0, 0.08))
	n.draw_arc(c, 5.5, 0.0, TAU, 14, RED, 1.3, true)
	n.draw_circle(c, 2.2, RED)


func _lamp(n: Node2D, c: Vector2, sd: int) -> void:
	_stroke(n, _circle(c, 6.0, 1.05, 0.3), 1.6, PENCIL, sd)
	_stroke(n, [c + Vector2(-9, 0), c + Vector2(9, 0)], 1.1, Color(PENCIL, 0.7), sd + 1)
	_stroke(n, [c + Vector2(0, -9), c + Vector2(0, 9)], 1.1, Color(PENCIL, 0.7), sd + 2)


func _van(n: Node2D, c: Vector2, ang: float, sd: int) -> void:
	var t := func(v: Vector2) -> Vector2: return c + v.rotated(ang)
	_stroke(n, [Vector2(-48, -19), Vector2(48, -19), Vector2(48, 19), Vector2(-48, 19), Vector2(-47.5, -18)].map(t), 1.9, PENCIL, sd)
	_stroke(n, [t.call(Vector2(28, -19)), t.call(Vector2(28, 19))], 1.3, Color(PENCIL, 0.8), sd + 1)
	_stroke(n, [Vector2(-30, -19), Vector2(14, -19), Vector2(14, -34), Vector2(-30, -34), Vector2(-29.5, -19)].map(t), 1.4, PENCIL, sd + 2)
	for k in 6:  # the striped awning over the serving hatch
		_stroke(n, [t.call(Vector2(-28 + k * 7.5, -20)), t.call(Vector2(-26 + k * 7.5, -33))], 2.4, Color(RED, 0.45), sd + 3 + k, 0.3)
	_write(n, g.hand_font(), "coffee", t.call(Vector2(-8, 6)), 20, ang, sd + 10)


func _cooler(n: Node2D, c: Vector2, sd: int) -> void:
	_stroke(n, [c + Vector2(-8, -5.5), c + Vector2(8, -5.5), c + Vector2(8, 5.5), c + Vector2(-8, 5.5), c + Vector2(-7.5, -5)], 1.3, PENCIL, sd)
	_stroke(n, [c + Vector2(-7, -1), c + Vector2(7, -1)], 0.9, Color(PENCIL, 0.5), sd + 1)


func _tripod(n: Node2D, c: Vector2, sd: int) -> void:
	for k in 3:
		_stroke(n, [c, c + Vector2.from_angle(0.6 + k * 2.1) * 9.0], 1.0, PENCIL, sd + k, 0.2)
	_stroke(n, [c + Vector2(-2.5, -2), c + Vector2(2.5, -2), c + Vector2(2.5, 2), c + Vector2(-2.5, 2), c + Vector2(-2.4, -1.8)], 1.2, PENCIL, sd + 4, 0.2)


func _sign(n: Node2D, font: Font, c: Vector2, sd: int) -> void:
	var r := Rect2(c - Vector2(32, 15), Vector2(64, 30))
	_stroke(n, [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position + Vector2(1, -1)], 1.5, PENCIL, sd)
	_write(n, font, "MEET", c + Vector2(0, 4), 24, -0.06, sd + 1)
	_write(n, font, "11 pm", c + Vector2(20, 21), 14, -0.06, sd + 2)
	for s in [-1.0, 1.0]:  # tape at the top corners
		_stroke(n, [c + Vector2(s * 30, -16), c + Vector2(s * 22, -10)], 3.5, Color(0.86, 0.82, 0.67, 0.8), sd + 3 + int(s), 0.2)


## The chosen car's marks, drawn the way the run draws its skids: dark graphite, the rears full and wide,
## the fronts lighter; they build up darker where laps cross, and only the very oldest wear away.
func _draw_marks(n: Node2D) -> void:
	var col: Color = g.inks.skid_col()
	for k in 4:
		var runs: Array = marks[k]
		var strength := 1.0 if k < 2 else 0.6
		var w := 6.0 if k < 2 else 4.5
		var idx := 0
		for r in runs:
			var pts: PackedVector2Array = r
			if pts.size() < 2:
				idx += pts.size()
				continue
			if idx > 160:
				n.draw_polyline(pts, Color(col, col.a * strength), w, false)
			else:
				var cols := PackedColorArray()
				cols.resize(pts.size())
				for i in pts.size():
					cols[i] = Color(col, col.a * strength * smoothstep(0.0, 160.0, float(idx + i)))
				n.draw_polyline_colors(pts, cols, w, false)
			idx += pts.size()


## The people: quick pencil doodles, the kind scribbled in a margin without much care, each made once
## (wobbly lines that overshoot, heads that are a loop that doesn't quite close) in a mix of types. To watch
## the car they turn like a paper cut-out, flipping round through edge-on.
func _draw_crowd(n: Node2D) -> void:
	for c in [pad + Vector2(-LOBE_X, 0), pad + Vector2(LOBE_X, 0)]:  # one in each loop, the way drifters circle one
		_cone_quick(n, c)
	var all := PackedVector2Array()
	for p in people:
		var c := cos(float(p["look"]))
		var fx := signf(c) * maxf(0.75, minf(1.0, absf(c) * 2.2)) if c != 0.0 else 1.0  # never thinner than this
		var at: Vector2 = p["p"]
		for v in p["segs"]:
			all.append(at + Vector2(v.x * fx, v.y))
	n.draw_multiline(all, DOODLE, 1.2)  # one batch for the whole crowd


## Night over the meet: a soft graphite shade, lifted where the lamps, the headlights and the pad are lit.
func _make_shade() -> void:
	var x0 := art_rect.position.x
	var y0 := MEET_TOP - 40.0
	var w := art_rect.size.x
	var h := meet_bot - MEET_TOP + 100.0
	shade_rect = Rect2(x0, y0, w, h)
	var k := 5.0
	var iw := int(w / k)
	var ih := int(h / k)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	for y in ih:
		for x in iw:
			var wp := Vector2(x0 + (x + 0.5) * k, y0 + (y + 0.5) * k)
			var lit := 0.0
			for l in lights:
				lit = maxf(lit, 1.0 - smoothstep(20.0, 120.0, wp.distance_to(l)))
			var edge := smoothstep(0.0, 40.0, wp.y - y0) * smoothstep(0.0, 40.0, y0 + h - wp.y) * smoothstep(0.0, 30.0, wp.x - x0) * smoothstep(0.0, 30.0, x0 + w - wp.x)
			img.set_pixel(x, y, Color(0.14, 0.14, 0.2, 0.2 * (1.0 - lit * 0.9) * edge))
	shade_tex = ImageTexture.create_from_image(img)


func _draw_shade(n: Node2D) -> void:
	if shade_tex:
		n.draw_texture_rect(shade_tex, shade_rect, false)


## The drone: above everything, drifting after the car to film it.
func _draw_sky(n: Node2D) -> void:
	n.draw_circle(drone + Vector2(-10, 28), 9.0, Color(0, 0, 0, 0.07))
	_stroke(n, [drone + Vector2(-9, -9), drone + Vector2(9, 9)], 1.3, PENCIL, 2000, 0.3)
	_stroke(n, [drone + Vector2(-9, 9), drone + Vector2(9, -9)], 1.3, PENCIL, 2001, 0.3)
	for v in [Vector2(-9, -9), Vector2(9, 9), Vector2(-9, 9), Vector2(9, -9)]:
		n.draw_arc(drone + v, 4.5, 0.0, TAU, 12, Color(PENCIL, 0.6), 0.9, true)


## A pencilled gear: a ring of teeth and a hub. On the page, so it scrolls away with it.
func _gear(n: Node2D) -> void:
	var pts: Array = []
	var teeth := 8
	for i in teeth * 4 + 1:
		var a := 0.2 + TAU * i / (teeth * 4.0)
		var r := GEAR_R if (i % 4) in [1, 2] else GEAR_R * 0.74
		pts.append(gear + Vector2.from_angle(a) * r)
	_stroke(n, pts, 2.6, PENCIL, 90)
	_stroke(n, _circle(gear, GEAR_R * 0.32, 1.1, 0.2), 2.2, PENCIL, 91)


## The best run, written down the margin beside the road.
func _best(n: Node2D, font: Font, hw: float) -> void:
	var cfg := _cfg()
	var best := int(cfg.get_value("best", "score", 0))
	if best <= 0:
		return
	var x := hw + 40.0
	var y := -330.0
	_write_left(n, font, "best", Vector2(x, y), 34, -0.03, 100)
	_stroke(n, [Vector2(x, y + 7), Vector2(x + 58, y + 5)], 1.8, PENCIL, 101)
	_write_left(n, font, "%d" % best, Vector2(x, y + 48), 48, -0.02, 102)
	_write_left(n, font, "%d m" % int(cfg.get_value("best", "dist", 0)), Vector2(x, y + 88), 32, 0.02, 103)
	_write_left(n, font, "x%d combo" % int(cfg.get_value("best", "combo", 1)), Vector2(x, y + 124), 32, -0.01, 104)


## The hint, either side of the road: "hold" written letter by letter, underlined with an arrow pointing
## the way to drift, then "drift left/right"; held, rubbed out, written again (the sides take turns).
## Once the run starts it stays on the paper, fully written.
func _draw_hint(n: Node2D) -> void:
	var font: Font = g.hand_font()
	var hw: float = g.widths[0] * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * (hw + 92.0)
		var y := -100.0
		var sd := 750 + int(side) * 30
		var done := mode == "gone" or mode == "exit"
		var u := 0.6 if done else fposmod(hint_t / HINT_LOOP + (0.0 if side < 0 else 0.5), 1.0)
		var fade := 1.0 if done else 1.0 - smoothstep(0.8, 0.98, u)
		if fade <= 0.0:
			continue
		var letters := 99 if done else int(smoothstep(0.0, 0.4, u) * 5.0)
		_write(n, font, "hold", Vector2(x, y), 54, side * 0.04, sd, fade, letters)
		var ar := 1.0 if done else smoothstep(0.4, 0.55, u)
		if ar > 0.0:
			var a0 := Vector2(x - side * 30.0, y + 26.0)
			var a1 := Vector2(x + side * 50.0, y + 22.0)
			var end := a0.lerp(a1, ar)
			_stroke(n, [a0, a0.lerp(end, 0.5), end], 2.6, Color(PENCIL, PENCIL.a * fade), sd + 2)
			if ar >= 0.98:
				_stroke(n, [a1 + Vector2(-side * 12.0, -9.0), a1, a1 + Vector2(-side * 12.0, 9.0)], 2.6, Color(PENCIL, PENCIL.a * fade), sd + 3)
		var lab := 1.0 if done else smoothstep(0.55, 0.65, u)
		if lab > 0.0:
			_write(n, font, "drift " + ("left" if side < 0 else "right"), Vector2(x, y + 66.0), 30, side * 0.04, sd + 4, fade * lab)


## The settings, written on the paper to the right of the page, beside the gear: ticks, choices you tap
## through, a slider.
## Always there; drawn again only when something changes.
func _panel(n: Node2D) -> void:
	var font: Font = g.hand_font()
	hits.clear()
	if mode != "gone":  # on the start page, the paper behind the settings is rubbed clean so the road
		# never runs through the writing (the same grain as the sheet, soft at the edges); the run brings it back
		var tex: Texture2D = g.paper.texture
		var r := _panel_rect().grow(-10.0)
		for k in 4:
			var rr := r.grow(18.0 - k * 6.0)
			n.draw_texture_rect_region(tex, rr, rr, Color(1, 1, 1, 0.35 + k * 0.22))
	var x0: float = panel_x
	var x1: float = panel_x + PANEL_W
	var y := panel_top
	_write_left(n, font, "settings", Vector2(x0, y), 54, -0.02, 300)
	_stroke(n, _wave(Vector2(x0, y + 12), Vector2(x0 + 150, y + 9), 2.5, 2.0), 2.2, PENCIL, 301)
	y += ROW + 8.0
	var cfg := _cfg()
	var rows := [
		["toggle", "sound", "sound", _game_on("sound")],
		["toggle", "music", "music", _game_on("music")],
		["toggle", "vibration", "vibration", _game_on("vibration")],
		["cycle", "car", "car", "CARS", "evo"],
		["cycle", "paper", "paper", "PAPERS", "white"],
		["cycle", "handling (applies when you close)", "handling", "HANDLING", "flow"],
		["cycle", "music track", "music", "MUSIC_CHOICES", "shuffle"],
		["slider", "hold before drift (classic)", "hold"],
		["toggle", "a hit ends the run", "crash", bool(cfg.get_value("dev", "crash", true))],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var sd := 310 + i * 10
		var rect := Rect2(x0 - 10.0, y - 38.0, x1 - x0 + 20.0, ROW)
		match r[0]:
			"toggle":
				var box := Rect2(x0, y - 24.0, 24.0, 24.0)
				_stroke(n, [box.position, Vector2(box.end.x + 1, box.position.y), box.end, Vector2(box.position.x, box.end.y + 1), box.position + Vector2(1, -2)], 1.9, PENCIL, sd)
				if r[3]:
					_stroke(n, [box.position + Vector2(3, 12), box.position + Vector2(10, 21), box.position + Vector2(30, -6)], 2.6, PENCIL, sd + 1)
				_write_left(n, font, r[1], Vector2(x0 + 40.0, y), 34, 0.0, sd + 2)
			"cycle":
				var opts: Dictionary = _c(r[3])
				var cur: Dictionary = opts.get(String(cfg.get_value("dev", r[2], r[4])), opts[r[4]])
				_write_left(n, font, r[1], Vector2(x0, y - 22.0), 22, 0.0, sd)
				_write_left(n, font, String(cur["name"]), Vector2(x0 + 6.0, y + 6.0), 28, -0.01, sd + 1)
				var ax := Vector2(x1 - 6.0, y - 4.0)
				_stroke(n, [ax + Vector2(-8, -9), ax, ax + Vector2(-8, 9)], 2.2, PENCIL, sd + 2)
				rect = Rect2(x0 - 10.0, y - 44.0, x1 - x0 + 20.0, ROW + 6.0)
				y += 10.0
			"slider":
				var v := float(cfg.get_value("dev", "hold", _c("DEFAULT_HOLD")))
				_write_left(n, font, "%s  %.2f s" % [r[1], v], Vector2(x0, y - 18.0), 22, 0.0, sd)
				var a := Vector2(x0 + 10.0, y + 8.0)
				var b := Vector2(x1 - 10.0, y + 8.0)
				_stroke(n, [a, a.lerp(b, 0.5) + Vector2(0, 1.5), b], 2.0, PENCIL, sd + 1)
				for k in 4:
					var tx := a.lerp(b, k / 3.0)
					_stroke(n, [tx + Vector2(0, -5), tx + Vector2(0.5, 5)], 1.3, SOFT, sd + 2 + k)
				_stroke(n, _circle(a.lerp(b, v / 0.6), 9.0, 1.1, 0.3), 2.4, PENCIL, sd + 7)
				rect = Rect2(x0 - 10.0, y - 30.0, x1 - x0 + 20.0, ROW)
		hits.append({"rect": rect, "kind": r[0], "key": r[2], "opts": r[3] if r[0] == "cycle" else "", "def": r[4] if r[0] == "cycle" else ""})
		y += ROW


# ---------------------------------------------------------------- pencil

## A small fixed random number in -1..1 for a point of a stroke.
func _n(i: int, sd: int) -> float:
	var f := sin(float(i) * 12.9898 + float(sd) * 78.233) * 43758.5453
	return (f - floorf(f)) * 2.0 - 1.0


## A pencil stroke through `pts`: it wobbles, overshoots its ends a little, is pressed harder in the middle
## than at the ends, and a lighter second pass goes over most of it.
func _stroke(n: Node2D, pts: Array, w: float, col: Color, sd: int, wob := 0.85) -> void:
	var m := pts.size()
	if m < 2:
		return
	var p := PackedVector2Array()
	var over := (2.0 + 2.5 * absf(_n(0, sd + 7))) * minf(1.0, w / 2.0)
	var d0: Vector2 = (pts[0] - pts[1]).normalized()
	p.append(pts[0] + d0 * over)
	for i in m:
		p.append(pts[i] + Vector2(_n(i, sd), _n(i + 50, sd)) * wob)
	var d1: Vector2 = (pts[m - 1] - pts[m - 2]).normalized()
	p.append(pts[m - 1] + d1 * over * 0.7)
	var k := p.size()
	var cuts := [0, maxi(1, k / 4), maxi(2, k - 1 - k / 4), k - 1]
	var press := [0.62, 1.0, 0.7]
	for r in 3:
		var a: int = cuts[r]
		var b: int = cuts[r + 1]
		if b <= a:
			continue
		n.draw_polyline(p.slice(a, b + 1), col, w * press[r] * (0.9 + 0.12 * _n(r, sd + 3)), true)
	if w < 1.2:
		return
	var q := PackedVector2Array()  # the second, lighter pass: a hair off, over the middle of the stroke
	for i in range(k / 6, k - k / 6):
		q.append(p[i] + Vector2(0.9 + 0.5 * _n(i, sd + 11), 0.7 + 0.5 * _n(i, sd + 13)))
	if q.size() > 1:
		n.draw_polyline(q, Color(col, col.a * 0.32), w * 0.6, true)


## Handwriting: the hand font letter by letter, each set a little differently, with a faint second pass.
## `upto` writes only the first letters (for writing it out); centred on the whole word, so nothing shifts.
func _write(n: Node2D, font: Font, s: String, at: Vector2, size: int, tilt: float, sd: int, alpha := 1.0, upto := 999) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_letters(n, font, s, at + Vector2(-w * 0.5, 0).rotated(tilt), size, tilt, sd, alpha, upto)


func _write_left(n: Node2D, font: Font, s: String, at: Vector2, size: int, tilt: float, sd: int) -> void:
	_letters(n, font, s, at, size, tilt, sd, 1.0, 999)


func _letters(n: Node2D, font: Font, s: String, at: Vector2, size: int, tilt: float, sd: int, alpha: float, upto: int) -> void:
	var x := 0.0
	var wob := size / 60.0
	for i in mini(s.length(), upto):
		var p := at + Vector2(x, 0).rotated(tilt) + Vector2(_n(i, sd), _n(i + 30, sd)) * 0.7 * wob
		n.draw_set_transform(p, tilt + _n(i + 60, sd) * 0.035)
		n.draw_char(font, Vector2(1.1, 0.8), s[i], size, Color(PENCIL, 0.22 * alpha))
		n.draw_char(font, Vector2.ZERO, s[i], size, Color(PENCIL, PENCIL.a * alpha))
		x += font.get_char_size(s.unicode_at(i), size).x
	n.draw_set_transform(Vector2.ZERO)


## A hand-drawn circle: a little more than one turn, so the ends overlap as a quick circle does.
func _circle(c: Vector2, r: float, turns: float, start: float) -> Array:
	return _ellipse(c, r, r, turns, start)


func _ellipse(c: Vector2, rx: float, ry: float, turns: float, start: float) -> Array:
	var out: Array = []
	var steps := maxi(8, int(24 * turns))
	for i in steps + 1:
		var a := start + TAU * turns * i / steps
		var grow := 1.0 + 0.06 * float(i) / steps  # the pen drifts outwards as it comes round
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry) * grow)
	return out


static func _wave(from: Vector2, to: Vector2, amp: float, waves: float) -> Array:
	var out: Array = []
	for i in 25:
		var t := i / 24.0
		out.append(from.lerp(to, t) + Vector2(0, sin(t * TAU * waves) * amp * (0.6 + 0.4 * sin(t * 9.0))))
	return out
