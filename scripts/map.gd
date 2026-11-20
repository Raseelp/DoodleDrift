extends Node2D
## The chapter map: every lake drawn as a small thumbnail of its real shape, joined by a dotted path.

signal lake_chosen(index: int)
signal reload_requested

const DrawNode = preload("res://scripts/draw_node.gd")
const LandShader = preload("res://scripts/land.gdshader")
const SPOTS := [Vector2(220, 345), Vector2(500, 520), Vector2(220, 695), Vector2(500, 870), Vector2(220, 1045)]
const THUMB := 0.135
const LAKE_CENTER := Vector2(360, 705)
const HULL := [Vector2(19, 0), Vector2(9, -7.5), Vector2(-13, -7.5), Vector2(-16, -4.5),
	Vector2(-16, 4.5), Vector2(-13, 7.5), Vector2(9, 7.5)]

var view_size := Vector2.ZERO
var off := Vector2.ZERO
var top_inset := 0.0
var clock := 0.0
var draw_node: Node2D
var glow_node: Node2D
var flies: Array = []
var path_pts := PackedVector2Array()
var thumbs: Array = []
var current := 0
var ui_root: Control
var dev_panel: Control
var map_ui: Control  # title, lake names and the gear; hidden while zoomed in on a lake
var settings: Control
var celebrating := false
var cele_test := false  # this celebration is a replay from the dev panel
var ch2_label: Label = null  # what chapter two asks for, under the chapter's name
var _thumb_xf := Transform2D()  # the lake picture being drawn: its own coordinates to the map
const TEASE_K := 2.4  # teaser figures drawn larger than life, so they read at the picture's small size
var _tease_swan: SubViewport = null  # the 3D swan gliding on her lake's picture (made in _ready)
var _tease_seen := -10.0  # when she was last drawn: she only renders while she's on screen
# Arriving from a lake (after a win, or Menu): the lake zooms out into its picture, a lake this win
# opened unlocks, and the boat sails to the next lake, which the map then zooms in on. A fresh tap skips to the end.
const A_HAND := 0.75  # the lake has faded into its picture here (level.gd LEAVE_HAND)
const A_ZOOM := 1.0  # then the camera pulls back from the lake to the whole map
const A_GAP := 0.15
const A_UNLOCK := 0.7
var arrive_level = null  # the lake (level.gd) zooming out over the map; freed when it lands
var arrive_from := -1
var travel_to := -1  # the lake the boat sails to and then zooms in on (-1: none)
var reveal := -1  # the lake this win opened
var arrive_t := -1.0  # seconds into the arrival, -1 when not arriving
var arrive_cam: Array = []  # the camera close in on the lake the arrival starts from
var still_lake := -1  # a lake the camera dives into or out of: its picture stops bobbing
var still_amp := 1.0  # its bobbing comes back gently afterwards
var enter_from: Array = []  # the camera when setting off
var still_lit: Array = []  # during a dive in or out, which of that lake's lanterns are lit on the lake itself
var unlock_played := false
var skip_armed := false  # a new touch began after the arrival started; only its lift skips
var trip_len := 0.0
var trail: Array = []  # where the pickup's back wheels have been on the trip: tyre tracks in the dirt
# The road the pickup drives: the dotted path, bending round each lake instead of through it. Every lake
# has a parking spot on it, a little before the lake with the pickup's nose towards it.
var road := PackedVector2Array()
var road_len := PackedFloat32Array()
var park_s: Array = []  # each lake's parking spot, as a distance along the road
const KEEP_OUT := Vector2(62, 88)  # the road keeps this far from a lake's middle (half width, half height)
var tint_node: CanvasModulate
var tint_color := Color.WHITE
const Rig3D = preload("res://scripts/rig3d.gd")
const Swan3D = preload("res://scripts/swan3d.gd")
const RIG_RENDER := 200  # the rig's render size; it sees 26 m, so 7.7 px a metre
const RIG_SCALE := 0.74  # drawn at about 5.7 map px a metre: the whole rig is about 125 px long
const PICKUP_M := 8.7  # the drawn pickup's length (rig3d.gd scales it up)
const PX_PER_M := RIG_SCALE * RIG_RENDER / 26.0
var boat3d: SubViewport  # the pickup, trailer and boat (rig3d.gd), drawn on the map
var rig_waiting := false  # its models are still loading: the map shows meanwhile, the rig fades in after
var rig_fade := 1.0
var rings: Array = []  # gold ripples spreading from a lake a win has just opened
# Chapter complete: each lake's lantern light on the water (0..1, 1 once it is done; the chapter moment brings
# them up one by one), a brief flare as each lights, and fireflies round the shores once night has fallen.
var lake_lit: Array = []
var lake_flare: Array = []
var shore_flies: Array = []
var shore_fly_a := 0.0
# The road of lights: the dotted road between two lakes lights up once both are done (all of it once the
# chapter is complete). road_lit is how far along it is lit, in lakes (0 = first lake, 4 = the last).
var road_dots: Array = []  # [position, how far along in lakes]
var road_lit := 0.0
var road_front := -1.0  # while a stretch is lighting: where its leading lamp is, else -1
# Fireworks for the chapter: shells rise and burst into sparks that slow in the air and fall.
var fw_shells: Array = []
var fw_sparks: Array = []
var fw_flashes: Array = []
var fw_glints: Array = []  # lanterns flashing as their lake lights up in the celebration
var fw_show := false  # the finale keeps sending them up, now and then, until the tap
var fw_show_words := false  # the chapter's words are up (on a short screen, bursts keep clear of them)
var fw_next := 0.0
var fw_rng := RandomNumberGenerator.new()
var cele_fx: Control = null
const FW_COLORS := [Color(1.0, 0.78, 0.36), Color(1.0, 0.3, 0.28), Color(0.38, 1.0, 0.48), Color(0.4, 0.6, 1.0),
	Color(0.84, 0.46, 1.0), Color(1.0, 0.97, 0.9), Color(0.32, 0.95, 1.0), Color(1.0, 0.52, 0.18), Color(1.0, 0.45, 0.7)]
var cele_ui: Control = null
var cele_blocker: Control = null
var cele_armed := false
var cele_tick := 0.0
var cele_dimmed: Array = []  # on short screens: [label, its alpha] faded while the words are up
var cele_icons_a := 1.0  # the lakes' goal icons, faded under the chapter words on a short screen
var cele_night := 0.0  # the chapter moment brings night to the whole map, wherever the pickup is

# Time of day on the map follows the chapter: bright morning with no lake lit, golden afternoon,
# dusk near the end, and night once every lake is bright (so the lanterns shine). 0 = morning, 1 = night.
const DAY_STOPS := [
	{"t": 0.0, "base": "a4c47a", "dark": "93b56c", "ink": "1f3324", "tint": "ffffff"},
	{"t": 0.25, "base": "9dbd70", "dark": "8aab61", "ink": "1f3324", "tint": "fff8ec"},
	{"t": 0.5, "base": "bba465", "dark": "a68f55", "ink": "2e2416", "tint": "ffe9cc"},
	{"t": 0.75, "base": "6f6a5c", "dark": "5f5a50", "ink": "f4efe6", "tint": "d9c9d6"},
	{"t": 1.0, "base": "23313a", "dark": "1c2830", "ink": "f1f3f2", "tint": "b8bfd8"},
]
var day_t := 0.0  # 0 morning .. 1 night: follows where the pickup is on the road (_day_target)
var night_f := 0.0  # 1 once the chapter is complete: the last lake's stretch of road turns to night
var ink := Color.WHITE  # text colour that reads on today's ground
var land_mat: ShaderMaterial
var ink_set := Color(0, 0, 0, 0)  # the ink the labels were last given
# The pickup driving between lakes on the map (outside an arrival): it only ever moves while on screen.
# Each trip is a route the tow hitch follows: the road, or, when the lake is back the way it came, a loop
# off the track to turn round (a driver steering for the road behind, never sharper than TURN_R), then the
# road. The pickup's nose looks ahead along the route and the trailer's wheels follow the same path behind.
const TURN_R := 52.0  # the rig's tightest turn on the map, px (about 9 m)
const LOOK := 46.0  # how far ahead along the road the driver aims
var drive_to := -1  # the lake it is driving to (-1: parked by `current`)
var drive_start := 0.0
var drive_time := 1.0
var drive_m0 := 0.0  # its speed at the start, in the ease's units (0 = from a standstill)
var route := PackedVector2Array()
var route_len := PackedFloat32Array()
var route_sv := PackedFloat32Array()  # the road distance each route point stands for (for the time of day)
var route_d0 := 0.0  # where on the route the hitch sets off
var route_d1 := 0.0  # and where it stops, by the lake
var clouds: Array = []
var butterflies: Array = []
var map_labels: Array = []
var trees: Array = []


func _ready() -> void:
	view_size = get_viewport_rect().size
	off = ((view_size - Game.LAKE_SIZE) * 0.5).floor()
	var win := DisplayServer.window_get_size()
	if win.y > 0:
		top_inset = maxf(0.0, float(DisplayServer.get_display_safe_area().position.y) * view_size.y / float(win.y))
	current = 0
	for i in Game.lake_count():
		if Game.is_unlocked(i):
			current = i
		if Game.is_unlocked(i) and not Game.lake_done(i):
			current = i
			break
	# The pickup stays where it was left; it only moves on screen.
	if Game.rig_lake >= 0 and Game.is_unlocked(Game.rig_lake):
		current = Game.rig_lake
	if arrive_from >= 0:
		current = arrive_from
	night_f = 1.0 if Game.chapter_done() and Game.chapter_seen else 0.0

	for i in Game.lake_count():
		var poly := Game.water_poly(i)
		thumbs.append({
			"sand": Geometry2D.offset_polygon(poly, 16.0, Geometry2D.JOIN_ROUND),
			"water": poly,
			"mid": Geometry2D.offset_polygon(poly, -40.0, Geometry2D.JOIN_ROUND),
			"deep": Geometry2D.offset_polygon(poly, -100.0, Geometry2D.JOIN_ROUND),
		})
	var spots := PackedVector2Array()
	for s in SPOTS:
		spots.append(s + off)
	path_pts = _open_curve(spots, 16)
	_build_road()

	day_t = _day_target() if not has_meta("day_t") else float(get_meta("day_t"))
	var stop := _day_stop(day_t)
	ink = _ink_for(day_t)

	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in 26:
		flies.append({"p": Vector2(rng.randf() * view_size.x, rng.randf() * view_size.y),
			"ph": rng.randf() * TAU, "v": Vector2(rng.randf_range(-6, 6), rng.randf_range(-8, -2))})

	for i in Game.lake_count():
		lake_lit.append(1.0 if Game.lake_done(i) else 0.0)
		lake_flare.append(0.0)
	if Game.chapter_done():
		_make_shore_flies()
		shore_fly_a = 1.0 if Game.chapter_seen else 0.0
	for lk in Game.lakes:
		if lk.has("swan"):
			_tease_swan = Swan3D.new()  # the swan that glides on her lake's picture
			_tease_swan.render_px = 128
			add_child(_tease_swan)
			break
	_make_road_dots()
	road_lit = _road_done()
	if is_instance_valid(arrive_level) and reveal >= 0 and arrive_from >= 1 and road_lit >= float(arrive_from):
		road_lit = float(arrive_from - 1)  # this win's stretch lights up during the arrival
	fw_rng.randomize()

	var bg := Polygon2D.new()
	# Ground well past the screen, so zooming in on a lake near the edge never runs out of it.
	bg.polygon = PackedVector2Array([-view_size, Vector2(view_size.x * 2.0, -view_size.y), view_size * 2.0, Vector2(-view_size.x, view_size.y * 2.0)])
	var m := ShaderMaterial.new()
	m.shader = LandShader
	m.set_shader_parameter("base", stop["base"])
	m.set_shader_parameter("dark", stop["dark"])
	bg.material = m
	land_mat = m
	add_child(bg)
	var tint := CanvasModulate.new()
	tint.color = stop["tint"]
	add_child(tint)
	tint_node = tint
	tint_color = stop["tint"]
	if is_instance_valid(arrive_level):
		tint.visible = false  # the lake's own tint blends into this one, then hands over

	# Cloud shadows: soft clusters drifting slowly across the meadow, fewer as the day ends.
	for k in 4:
		var puffs: Array = []
		for q in rng.randi_range(3, 4):
			puffs.append({"o": Vector2(rng.randf_range(-120, 120), rng.randf_range(-50, 50)), "r": rng.randf_range(110, 190)})
		clouds.append({"p": Vector2(rng.randf_range(-200, view_size.x + 200), rng.randf_range(150, view_size.y - 100)),
			"v": rng.randf_range(9.0, 15.0), "puffs": puffs})
	# Trees: clumps along the sides and bottom, clear of the lakes, their names and the title.
	var tries := 0
	while trees.size() < 34 and tries < 900:
		tries += 1
		var side := rng.randi() % 3
		var tp := Vector2.ZERO
		if side == 0:
			tp = Vector2(rng.randf_range(-20, 70), rng.randf_range(250, view_size.y + 20))
		elif side == 1:
			tp = Vector2(rng.randf_range(view_size.x - 70, view_size.x + 20), rng.randf_range(250, view_size.y + 20))
		else:
			tp = Vector2(rng.randf_range(-20, view_size.x + 20), rng.randf_range(view_size.y - 90, view_size.y + 30))
		var tr := rng.randf_range(22, 40)
		var clear := true
		for k in Game.lake_count():
			var sp: Vector2 = SPOTS[k] + off
			if tp.distance_to(sp) < 95.0 + tr or (absf(tp.y - sp.y) < 60.0 and absf(tp.x - (sp.x + (150.0 if sp.x < 360.0 + off.x else -150.0))) < 150.0):
				clear = false
		for t in trees:
			if tp.distance_to(t["p"]) < (tr + float(t["r"])) * 0.75:
				clear = false
		for k in range(0, road.size(), 4):
			if clear and tp.distance_to(road[k]) < tr + 22.0:
				clear = false
		# The whole parked rig too: at the first lake its trailer and boat reach past the road's start.
		for ps in park_s:
			for dm in range(-15, 11, 2):
				if clear and tp.distance_to(_road_at(float(ps) + dm * PX_PER_M)) < tr + 26.0:
					clear = false
		if clear:
			trees.append({"p": tp, "r": tr, "ph": rng.randf() * TAU})
	trees.sort_custom(func(a, b): return a["p"].y < b["p"].y)

	# Butterflies by day: a slow wander with flapping wings.
	for k in 4:
		butterflies.append({"p": Vector2(rng.randf_range(60, view_size.x - 60), rng.randf_range(260, view_size.y - 160)),
			"ph": rng.randf() * TAU, "dir": rng.randf() * TAU,
			"c": [Color("fff6d8"), Color("ffd27a"), Color("f7f2ff"), Color("ffe7b0")][k]})

	draw_node = DrawNode.new()
	draw_node.draw_fn = _draw_map
	add_child(draw_node)
	glow_node = DrawNode.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_node.material = add
	glow_node.draw_fn = _draw_glow
	add_child(glow_node)

	if Game.dev_on("boat3d"):
		if Game.models_ready([Game.PICKUP_MODEL, Game.TRAILER_MODEL, Game.BOAT_MODEL]):
			_make_rig()
		else:
			rig_waiting = true  # don't hold up the map for them (first launch)
			rig_fade = 0.0
	_build_ui()
	Sfx.start_ambience(0.84, false)
	Sfx.set_mood(day_t, 0.0, false)
	if is_instance_valid(arrive_level):
		_start_arrival()
	elif Game.dev_victory:
		Game.dev_victory = false
		cele_test = true  # a replay from the dev panel: the save isn't touched, the map comes back as it was
		_celebrate.call_deferred()
	elif Game.chapter_done() and not Game.chapter_seen:
		_celebrate.call_deferred()
	else:
		_drive_pending.call_deferred()


func _start_arrival() -> void:
	arrive_t = 0.0
	ui_root.modulate.a = 0.0
	still_lake = arrive_from
	still_amp = 0.0
	still_lit = []
	for l in arrive_level.lanterns:
		still_lit.append(bool(l["lit"]))
	arrive_cam = _full_cam(arrive_from)
	position = arrive_cam[0]
	scale = Vector2.ONE * float(arrive_cam[1])
	if reveal >= 0:
		map_labels[2 + reveal].modulate.a = 0.4
	if travel_to >= 0:
		trip_len = absf(float(park_s[travel_to]) - float(park_s[arrive_from]))
	_arrive_step()


## The road: a parking spot before the first lake, then the dotted path, with every stretch that would
## cross a lake replaced by an arc round it.
func _build_road() -> void:
	var raw := PackedVector2Array()
	var s0: Vector2 = SPOTS[0] + off
	var s1: Vector2 = SPOTS[1] + off
	var back := (s0 - s1).normalized() * s0.distance_to(s1)
	for k in range(8, 0, -1):
		raw.append(s0 + back * (float(k) / 16.0))
	raw.append_array(path_pts)
	var park_raw: Array = [0]
	for i in range(1, Game.lake_count()):
		park_raw.append(8 + i * 16 - 8)  # halfway along the road before lake i, clear of its picture
	road = PackedVector2Array()
	park_s.clear()
	var i := 0
	while i < raw.size():
		var inside := _lake_at(raw[i])
		if inside < 0 or road.is_empty():
			if park_raw.has(i):
				park_s.append(i)  # marks the index for now
			road.append(raw[i])
			i += 1
			continue
		# Entering lake `inside`: skip to where the path leaves it and go round instead.
		var c: Vector2 = SPOTS[inside] + off
		var j := i
		while j < raw.size() and _lake_at(raw[j]) == inside:
			j += 1
		var a0 := (road[road.size() - 1] - c).angle()
		var a1 := ((raw[j] if j < raw.size() else raw[raw.size() - 1]) - c).angle()
		var da := wrapf(a1 - a0, -PI, PI)
		var steps := maxi(3, int(absf(da) / 0.18))
		for k in range(1, steps):
			var a := a0 + da * float(k) / steps
			road.append(c + Vector2(cos(a) * KEEP_OUT.x * 1.05, sin(a) * KEEP_OUT.y * 1.05))
		i = j
	road = _smooth_road(road)
	road_len = PackedFloat32Array([0.0])
	for k in range(1, road.size()):
		road_len.append(road_len[k - 1] + road[k - 1].distance_to(road[k]))
	var marks := park_s.duplicate()
	park_s.clear()
	for idx in marks:
		var p: Vector2 = raw[int(idx)]
		var best := 0
		for k in road.size():
			if road[k].distance_squared_to(p) < road[best].distance_squared_to(p):
				best = k
		park_s.append(road_len[best])


## Rounds the road's corners (where it bends round a lake) into curves a pickup could drive: points every
## 4 px, each pulled towards its neighbours a few times; the two ends stay put.
func _smooth_road(pts: PackedVector2Array) -> PackedVector2Array:
	var even := PackedVector2Array([pts[0]])
	var carry := 0.0
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var b := pts[k]
		var seg := a.distance_to(b)
		var t := 4.0 - carry
		while t <= seg:
			even.append(a.lerp(b, t / seg))
			t += 4.0
		carry = seg - (t - 4.0)
	even.append(pts[pts.size() - 1])
	for pass_i in 80:
		var nxt := even.duplicate()
		for k in range(1, even.size() - 1):
			nxt[k] = (even[k - 1] + even[k] * 2.0 + even[k + 1]) * 0.25
		even = nxt
	return even


## Which lake a point on the map is inside the keep-out of, or -1.
func _lake_at(p: Vector2) -> int:
	for k in Game.lake_count():
		var d: Vector2 = (p - (SPOTS[k] + off)) / KEEP_OUT
		if d.length_squared() < 1.0:
			return k
	return -1


## A point the given distance along the road (continuing straight past either end).
func _road_at(s: float) -> Vector2:
	if s <= 0.0:
		return road[0] + (road[0] - road[1]).normalized() * -s
	var n := road.size()
	if s >= road_len[n - 1]:
		return road[n - 1] + (road[n - 1] - road[n - 2]).normalized() * (s - road_len[n - 1])
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if road_len[mid] < s:
			lo = mid
		else:
			hi = mid
	return road[lo].lerp(road[hi], (s - road_len[lo]) / maxf(0.001, road_len[hi] - road_len[lo]))


## The rig at a distance s along the road, facing on along it: [hitch, pickup heading, trailer swing].
func _rig_at(s: float) -> Array:
	var hitch := _road_at(s)
	var nose := _road_at(s + 5.0 * PX_PER_M)
	var axle := _road_at(s - 9.5 * PX_PER_M)
	var heading := (nose - hitch).angle()
	return [hitch, heading, wrapf((hitch - axle).angle() - heading, -PI, PI)]


## The camera (map offset and zoom) that makes lake i's picture exactly fill the screen the way the
## lake itself does: the moment the map hands over to the lake, or takes over from it.
func _full_cam(i: int) -> Array:
	var z := 1.0 / THUMB
	return [off - (SPOTS[i] + off - LAKE_CENTER * THUMB) * z, z]


## Moves the camera between two views, zooming smoothly about lake i (even speed in and out).
func _cam_between(a: Array, b: Array, e: float, i: int) -> void:
	var c: Vector2 = SPOTS[i] + off
	var s0: Vector2 = Vector2(a[0]) + c * float(a[1])
	var s1: Vector2 = Vector2(b[0]) + c * float(b[1])
	var z := exp(lerpf(log(float(a[1])), log(float(b[1])), e))
	scale = Vector2(z, z)
	position = s0.lerp(s1, e) - c * z


## Setting off: the lake (level.gd) drives the camera dive with set_enter_cam.
func begin_enter(i: int) -> void:
	if cam_tween:
		cam_tween.kill()
	still_lake = i
	still_amp = 0.0
	enter_from = [position, scale.x]
	still_lit = []
	for l in Game.lakes[i]["lanterns"]:
		still_lit.append(false)  # a new try starts with every lantern dark


func set_enter_cam(e: float) -> void:
	if still_lake >= 0:
		_cam_between(enter_from, _full_cam(still_lake), e, still_lake)


func _t_zoomed() -> float:
	return A_HAND + A_ZOOM


func _t_unlock() -> float:
	return _t_zoomed() + A_GAP


func _t_trip() -> float:
	return _t_unlock() + (A_UNLOCK if reveal >= 0 else 0.0)


func _trip_time() -> float:
	return clampf(trip_len / 170.0, 1.2, 2.8) if travel_to >= 0 else 0.0


func _t_end() -> float:
	return _t_trip() + _trip_time() + 0.15


func _arrive_step() -> void:
	var t := arrive_t
	if is_instance_valid(arrive_level):
		arrive_level.leave_step(t, tint_color)
		if t >= A_HAND:
			_land_level()
	_cam_between(arrive_cam, [Vector2.ZERO, 1.0], smoothstep(A_HAND, A_HAND + A_ZOOM, t), arrive_from)
	ui_root.modulate.a = smoothstep(A_HAND + A_ZOOM * 0.5, A_HAND + A_ZOOM, t)
	if reveal >= 0:
		if not unlock_played and t >= _t_unlock():
			unlock_played = true
			var lc: Color = Game.lakes[reveal]["pal"]["light"]
			rings.append({"p": SPOTS[reveal] + off, "t": clock, "c": lc})
			Sfx.chime(0.84 * 2.0)
			Sfx.stamp(true)
			Game.vibrate(20)
			if _road_done() > road_lit:
				_light_road(_road_done(), 1.6)
		map_labels[2 + reveal].modulate.a = lerpf(0.4, 1.0, _reveal_f())
	if t >= _t_end():
		_finish_arrival()


func _land_level() -> void:
	if is_instance_valid(arrive_level):
		arrive_level.queue_free()
	arrive_level = null
	tint_node.visible = true


func _finish_arrival() -> void:
	_land_level()
	if reveal >= 0:
		map_labels[2 + reveal].modulate.a = 1.0
	arrive_t = -1.0
	position = Vector2.ZERO
	scale = Vector2.ONE
	ui_root.modulate.a = 1.0
	var calm := create_tween()
	calm.tween_property(self, "still_amp", 1.0, 1.0)
	calm.tween_callback(func(): still_lake = -1)
	current = travel_to if travel_to >= 0 else arrive_from
	Game.set_rig(current)
	if Game.chapter_done() and not Game.chapter_seen:
		_celebrate()
	elif travel_to >= 0:
		_focus(travel_to)
	else:
		_drive_pending()


## 0 = still locked, 1 = open; the lake this win opened goes from one to the other during the arrival.
func _reveal_f() -> float:
	return clampf((arrive_t - _t_unlock()) / A_UNLOCK, 0.0, 1.0) if arrive_t >= 0.0 else 1.0


func _open_f(i: int) -> float:
	if i == reveal and arrive_t >= 0.0:
		return _reveal_f()
	return 1.0 if Game.is_unlocked(i) else 0.0


## How far along its trip the rig is, 0..1, eased (it pulls away and slows to a stop); -1 when not moving.
func _drive_u() -> float:
	if arrive_t >= 0.0 and travel_to >= 0:
		var u := clampf((arrive_t - _t_trip()) / _trip_time(), 0.0, 1.0)
		return u * u * (3.0 - 2.0 * u)
	if arrive_t < 0.0 and drive_to >= 0:
		return _ease(clampf((clock - drive_start) / drive_time, 0.0, 1.0))
	return -1.0


## Pulls away (or carries on at the speed it had, m0) and slows to a stop by the lake.
func _ease(u: float) -> float:
	return (u * u * u - 2.0 * u * u + u) * drive_m0 + (3.0 * u * u - 2.0 * u * u * u)


func _ease_slope(u: float) -> float:
	return (3.0 * u * u - 4.0 * u + 1.0) * drive_m0 + (6.0 * u - 6.0 * u * u)


## Where the hitch is on its route now.
func _route_d() -> float:
	if drive_to >= 0:
		return lerpf(route_d0, route_d1, _drive_u())
	return route_d1


## A point on the route d along it (carrying straight on past either end).
func _route_at(d: float) -> Vector2:
	var n := route.size()
	if d <= 0.0:
		return route[0] + (route[0] - route[1]).normalized() * -d
	if d >= route_len[n - 1]:
		return route[n - 1] + (route[n - 1] - route[n - 2]).normalized() * (d - route_len[n - 1])
	var k := route_len.bsearch(d)
	k = clampi(k, 1, n - 1)
	return route[k - 1].lerp(route[k], (d - route_len[k - 1]) / maxf(0.001, route_len[k] - route_len[k - 1]))


func _route_s(d: float) -> float:
	var n := route.size()
	var k := clampi(route_len.bsearch(clampf(d, 0.0, route_len[n - 1])), 1, n - 1)
	return lerpf(route_sv[k - 1], route_sv[k], clampf((d - route_len[k - 1]) / maxf(0.001, route_len[k] - route_len[k - 1]), 0.0, 1.0))


## The rig's distance along the road now (on a turning loop: the road beside it).
func _rig_s() -> float:
	if park_s.is_empty():
		return 0.0
	if arrive_t >= 0.0:
		if travel_to >= 0:
			return lerpf(float(park_s[arrive_from]), float(park_s[travel_to]), _drive_u())
		return float(park_s[arrive_from])
	if not route.is_empty():
		return _route_s(_route_d())
	return float(park_s[current])


## The rig now: [hitch, heading, driving, trailer swing]. Parked by a lake, or on the road.
func _boat_now() -> Array:
	var u := _drive_u()
	if arrive_t >= 0.0 or route.is_empty():
		var r := _rig_at(_rig_s())
		return [r[0], r[1], u > 0.0 and u < 1.0, r[2]]
	var d := _route_d()
	var hitch := _route_at(d)
	var heading := (_route_at(d + 5.0 * PX_PER_M) - hitch).angle()
	var axle := _route_at(d - 9.5 * PX_PER_M)
	return [hitch, heading, u > 0.0 and u < 1.0, wrapf((hitch - axle).angle() - heading, -PI, PI)]


## Drives the pickup to lake i from wherever it is, turning round off the track if the lake is behind it.
func _drive_to(i: int) -> void:
	if park_s.is_empty() or arrive_t >= 0.0 or i == drive_to:
		return
	var target := float(park_s[i])
	var cur_s := _rig_s()
	if drive_to < 0 and absf(target - cur_s) < 1.0:
		current = i
		Game.set_rig(i)
		return
	# Its speed now, to carry on smoothly if it is already moving.
	var v0 := 0.0
	if drive_to >= 0:
		var u := clampf((clock - drive_start) / drive_time, 0.0, 1.0)
		v0 = (route_d1 - route_d0) * _ease_slope(u) / drive_time
	var bn := _boat_now()
	var p: Vector2 = bn[0]
	var h: float = bn[1]
	var d_now := _route_d() if not route.is_empty() else 0.0
	var pts := PackedVector2Array()
	var sv := PackedFloat32Array()
	# The path behind the hitch, so the trailer stays where it is.
	for k in range(14, 0, -1):
		var back := k * PX_PER_M
		if route.is_empty():
			pts.append(_road_at(cur_s - back))
			sv.append(cur_s - back)
		else:
			pts.append(_route_at(d_now - back))
			sv.append(_route_s(d_now - back))
	pts.append(p)
	sv.append(cur_s)
	var start_i := pts.size() - 1
	# It carries on along its line for a few metres before it can turn (where its nose already is).
	for k in range(1, 13):
		var a := k * 0.5 * PX_PER_M
		if route.is_empty():
			pts.append(_road_at(cur_s + a))
			sv.append(cur_s + a)
		else:
			pts.append(_route_at(d_now + a))
			sv.append(_route_s(d_now + a))
	p = pts[pts.size() - 1]
	h = (p - pts[pts.size() - 2]).angle()
	cur_s = sv[sv.size() - 1]
	# Steer for the road towards the lake (turning round in a loop if that is behind), keeping clear of the
	# lakes: if the natural way round would cut across one, swing round the other way instead.
	var sgn := 1.0 if target > cur_s else -1.0
	var plan := _steer(p, h, cur_s, sgn, target, 0.0)
	if float(plan[3]) < 1.0:
		for force in [1.0, -1.0]:
			var other := _steer(p, h, cur_s, sgn, target, force)
			if float(other[3]) > float(plan[3]):
				plan = other
	pts.append_array(plan[0])
	sv.append_array(plan[1])
	# Then the road to the lake, and a little past it for the pickup's nose.
	var rs: float = plan[2]
	while sgn * (target - rs) > 0.0:
		pts.append(_road_at(rs))
		sv.append(rs)
		rs += sgn * 4.0
	pts.append(_road_at(target))
	sv.append(target)
	var end_i := pts.size() - 1
	for k in range(1, 6):
		pts.append(_road_at(target + sgn * k * 3.0 * PX_PER_M))
		sv.append(target)
	route = pts
	route_sv = sv
	route_len = PackedFloat32Array([0.0])
	for k in range(1, route.size()):
		route_len.append(route_len[k - 1] + route[k - 1].distance_to(route[k]))
	route_d0 = route_len[start_i]
	route_d1 = route_len[end_i]
	var dist := route_d1 - route_d0
	drive_time = clampf(dist / 170.0, 1.2, 4.5)
	drive_m0 = clampf(v0 * drive_time / maxf(1.0, dist), 0.0, 2.5)
	drive_to = i
	drive_start = clock


## The driver's way from p (facing h) onto the road heading towards `target`: aiming a little ahead along
## the road, never turning tighter than TURN_R (a loop when the road is behind), then easing onto it.
## force: which way to swing round until lined up with the road (0: the natural way). [points, road distances, where it joins the road,
## how close it came to a lake (1 = the edge of its keep-out)].
func _steer(p: Vector2, h: float, s0: float, sgn: float, target: float, force: float) -> Array:
	var pts := PackedVector2Array()
	var sv := PackedFloat32Array()
	var sn := s0
	var hh := h
	var pp := p
	var side := force
	var forcing := force != 0.0
	var turned := 0.0
	var worst := INF
	for step in 300:
		sn = _near_s(pp, sn)
		var rp := _road_at(sn)
		var tang := (_road_at(sn + sgn * 4.0) - rp).angle()
		if pp.distance_to(rp) < 24.0 and absf(angle_difference(hh, tang)) < 0.45:
			break
		var aim := _road_at(sn + sgn * LOOK)
		var alpha := angle_difference(hh, (aim - pp).angle())
		var k: float
		if forcing and absf(alpha) > 0.5 and turned < PI * 1.6:
			k = force / TURN_R  # swinging round the long way, clear of a lake
		elif absf(alpha) > PI * 0.5:
			if side == 0.0:
				side = _open_side(pp, hh)  # turning round: on the side with room, away from the lakes
			k = side / TURN_R
		else:
			k = clampf(2.0 * sin(alpha) / LOOK, -1.0 / TURN_R, 1.0 / TURN_R)
		if absf(alpha) <= 0.5:
			forcing = false
		# Never across a lake: heading towards one and close, it veers away as hard as it can.
		var lc := _nearest_lake(pp)
		var fwd := Vector2.from_angle(hh)
		if _lake_room(pp) < 1.12 and fwd.dot(lc - pp) > 0.0:
			k = -signf(fwd.cross(lc - pp)) / TURN_R
		hh += k * 3.0
		turned += absf(k * 3.0)
		pp += Vector2.from_angle(hh) * 3.0
		pts.append(pp)
		sv.append(sn)
		worst = minf(worst, _lake_room(pp))
	# Ease onto the road a little further on, along a smooth curve that leaves at its heading and arrives
	# along the road.
	var js := sn + sgn * 34.0
	for k in 10:
		if (_road_at(js) - pp).dot(Vector2.from_angle(hh)) > 14.0:
			break
		js += sgn * 8.0  # join ahead of the pickup, never behind it
	if sgn * (target - js) < 0.0:
		js = target
	var q := _road_at(js)
	var qt := (_road_at(js + sgn * 4.0) - q).normalized()
	var reach := minf(16.0, pp.distance_to(q) * 0.4)
	var c1 := pp + Vector2.from_angle(hh) * reach
	var c2 := q - qt * reach
	for k in range(1, 9):
		var t := k / 8.0
		var a := pp.lerp(c1, t).lerp(c1.lerp(c2, t), t)
		var b := c1.lerp(c2, t).lerp(c2.lerp(q, t), t)
		var bp := a.lerp(b, t)
		pts.append(bp)
		sv.append(0.0)
		worst = minf(worst, _lake_room(bp))
	# Off the road the time of day moves evenly from where it left the road to where it joins it again.
	var total := 0.0
	var prev := p
	for q2 in pts:
		total += prev.distance_to(q2)
		prev = q2
	var run := 0.0
	prev = p
	for k in pts.size():
		run += prev.distance_to(pts[k])
		prev = pts[k]
		sv[k] = lerpf(s0, js, run / maxf(1.0, total))
	return [pts, sv, js + sgn * 4.0, worst]


func _nearest_lake(p: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	for k in Game.lake_count():
		var c: Vector2 = SPOTS[k] + off
		var d := ((p - c) / KEEP_OUT).length()
		if d < bd:
			bd = d
			best = c
	return best


## How far p is from the nearest lake, in keep-outs (under 1: inside one).
func _lake_room(p: Vector2) -> float:
	var r := INF
	for k in Game.lake_count():
		r = minf(r, ((p - (SPOTS[k] + off)) / KEEP_OUT).length())
	return r


## The nearest point of the road to p, searched near a guess (distance along the road).
func _near_s(p: Vector2, guess: float) -> float:
	var best := guess
	var bd := INF
	for k in range(-30, 31):
		var s := guess + k * 2.0
		var d := p.distance_squared_to(_road_at(s))
		if d < bd:
			bd = d
			best = s
	return best


## Which way to swing round when the road back is straight behind: away from the nearest lake, and on screen.
func _open_side(p: Vector2, h: float) -> float:
	var best := 1.0
	var score := -INF
	for sd in [1.0, -1.0]:
		var c: Vector2 = p + Vector2.from_angle(h + sd * PI * 0.5) * TURN_R
		var room := INF
		for k in Game.lake_count():
			room = minf(room, c.distance_to(SPOTS[k] + off))
		if c.x < TURN_R or c.x > view_size.x - TURN_R or c.y < TURN_R or c.y > view_size.y - TURN_R:
			room -= 200.0
		if room > score:
			score = room
			best = sd
	return best


## A lake a win opened while the map was away: drive there now that the map is on screen.
func _drive_pending() -> void:
	var p := Game.rig_pending
	if p >= 0 and Game.is_unlocked(p) and p != current and focus < 0 and not leaving_map:
		_drive_to(p)
	Game.rig_pending = -1


## The time of day where the rig is: each lake has its own (the first is morning, each later one later
## in the day, the last at dusk, or night once the chapter is complete), blended along the road between.
func _day_target() -> float:
	if park_s.is_empty():
		return 0.0
	var s := _rig_s()
	var n := Game.lake_count()
	if s <= float(park_s[0]):
		return _day_key(0)
	for i in range(1, n):
		var s1 := float(park_s[i])
		if s <= s1:
			var s0 := float(park_s[i - 1])
			return lerpf(_day_key(i - 1), _day_key(i), (s - s0) / maxf(1.0, s1 - s0))
	return _day_key(n - 1)


func _day_key(i: int) -> float:
	var n := Game.lake_count()
	var k := float(i) / n
	return lerpf(k, 1.0, night_f) if i == n - 1 else k


## Text colour for a time of day: dark on the bright ground, light once dusk falls (blended, not switched).
func _ink_for(t: float) -> Color:
	return Color("1f3324").lerp(Color("f1f3f2"), smoothstep(0.56, 0.68, t))


## In daylight a faint light drop shadow under the text, after dusk a dark one.
func _shadow_for(t: float) -> Color:
	return Color(1, 1, 1, 0.22).lerp(Color(0, 0, 0, 0.32), smoothstep(0.56, 0.68, t))


## Puts the current time of day on the ground, the light, the sounds and the text.
func _apply_day() -> void:
	var stop := _day_stop(day_t)
	land_mat.set_shader_parameter("base", stop["base"])
	land_mat.set_shader_parameter("dark", stop["dark"])
	tint_color = stop["tint"]
	tint_node.color = tint_color
	if not is_instance_valid(arrive_level):
		Sfx.set_mood(day_t, 0.0, false)  # while a lake is handing over, it keeps its own mood
	ink = _ink_for(day_t)
	if absf(ink.r - ink_set.r) + absf(ink.g - ink_set.g) + absf(ink.b - ink_set.b) < 0.01:
		return
	ink_set = ink
	var shadow := _shadow_for(day_t)
	for lb in map_labels:
		lb.add_theme_color_override("font_color", ink)
		lb.add_theme_color_override("font_shadow_color", shadow)
	if is_instance_valid(focus_ui):
		_ink_labels(focus_ui, shadow)


func _ink_labels(n: Node, shadow: Color) -> void:
	if n is Label and n.has_meta("ink_a"):
		n.add_theme_color_override("font_color", Color(ink, float(n.get_meta("ink_a"))))
		n.add_theme_color_override("font_shadow_color", shadow)
	for c in n.get_children():
		_ink_labels(c, shadow)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.theme = Game.ui_theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = view_size
	layer.add_child(root)
	ui_root = root
	map_ui = Control.new()
	map_ui.size = view_size
	map_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_ui)

	# Settings, top right: sound, music, vibration, credits and the developer options live there.
	var gear := Game.square_button(null, 64, 30)
	gear.position = Vector2(view_size.x - 32 - 64, top_inset + 24)
	gear.pressed.connect(func():
		if arrive_t >= 0.0 or leaving_map:
			return
		if focus >= 0:
			_unfocus()
			return
		Sfx.tap()
		_open_settings())
	root.add_child(gear)
	gear.reset_size()
	corner_btn = gear
	# Two icons on the button, crossfading with a quarter turn: settings on the map, close when zoomed in.
	for spec in [["settings", 30.0], ["close", 26.0]]:
		var ic := TextureRect.new()
		ic.texture = Game.icon(spec[0])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(spec[1], spec[1])
		ic.pivot_offset = ic.size * 0.5
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gear.add_child(ic)
		corner_icons.append(ic)
	_place_corner_icons(false)
	gear.button_down.connect(func(): _place_corner_icons(true))
	gear.button_up.connect(func(): _place_corner_icons(false))
	_set_corner(0.0)

	var title := Label.new()
	title.text = "WAKE"
	title.add_theme_font_override("font", Game.title_font)
	title.add_theme_font_size_override("font_size", 84)
	map_labels.append(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top_inset + off.y * 0.5 + 70)
	title.size = Vector2(view_size.x, 110)
	map_ui.add_child(title)

	var sub := Label.new()
	sub.text = "Chapter one  ·  The still lakes"
	sub.add_theme_font_size_override("font_size", 23)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.75
	map_labels.append(sub)
	sub.position = Vector2(0, top_inset + off.y * 0.5 + 180)
	sub.size = Vector2(view_size.x, 40)
	map_ui.add_child(sub)

	for i in Game.lake_count():
		var spot: Vector2 = SPOTS[i] + off
		var left_side := spot.x < 360.0 + off.x
		var l := Label.new()
		l.text = String(Game.lakes[i]["name"])
		l.add_theme_font_size_override("font_size", 27)
		l.size = Vector2(230, 40)
		if left_side:
			l.position = Vector2(spot.x + 90, spot.y - 34)
		else:
			l.position = Vector2(spot.x - 90 - 230, spot.y - 34)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.modulate.a = 1.0 if Game.is_unlocked(i) else 0.4
		map_labels.append(l)
		map_ui.add_child(l)
	# What opens chapter two, from the start, so it's never a surprise (after the lake names: their order
	# in map_labels matters).
	var eggs: Array = Game.eggs_returned()
	ch2_label = Label.new()
	if Game.goals_earned() >= Game.CH2_GOALS and int(eggs[0]) >= int(eggs[1]):
		ch2_label.text = "Chapter two is ready"
	else:
		ch2_label.text = "Chapter two: %d goals and every egg   ·   %d/%d, eggs %d/%d" % [Game.CH2_GOALS, Game.goals_earned(),
			Game.lake_count() * 3, int(eggs[0]), int(eggs[1])]
	ch2_label.add_theme_font_size_override("font_size", 18)
	ch2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch2_label.modulate.a = 0.55
	ch2_label.position = Vector2(0, top_inset + off.y * 0.5 + 222)
	ch2_label.size = Vector2(view_size.x, 30)
	map_labels.append(ch2_label)
	map_ui.add_child(ch2_label)
	# Labels take the day's ink colour; in daylight the dark drop shadow becomes a faint light one.
	for lb in map_labels:
		lb.add_theme_color_override("font_color", ink)
		lb.add_theme_color_override("font_shadow_color", _shadow_for(day_t))
	ink_set = ink


## Colours for a time of day, blended between the two nearest stops.
func _day_stop(t: float) -> Dictionary:
	for k in range(1, DAY_STOPS.size()):
		var a: Dictionary = DAY_STOPS[k - 1]
		var b: Dictionary = DAY_STOPS[k]
		if t <= float(b["t"]):
			var f := (t - float(a["t"])) / (float(b["t"]) - float(a["t"]))
			var out := {}
			for key in ["base", "dark", "ink", "tint"]:
				out[key] = Color(a[key]).lerp(Color(b[key]), f)
			return out
	var last: Dictionary = DAY_STOPS[DAY_STOPS.size() - 1]
	return {"base": Color(last["base"]), "dark": Color(last["dark"]), "ink": Color(last["ink"]), "tint": Color(last["tint"])}


func _process(delta: float) -> void:
	clock += delta
	if arrive_t >= 0.0:
		arrive_t += delta
		_arrive_step()
	if drive_to >= 0 and arrive_t < 0.0 and clock - drive_start >= drive_time:
		current = drive_to
		drive_to = -1
		Game.set_rig(current)
	if not has_meta("day_t"):
		day_t = lerpf(_day_target(), 1.0, cele_night)
		_apply_day()
	if rig_waiting and Game.models_ready([Game.PICKUP_MODEL, Game.TRAILER_MODEL, Game.BOAT_MODEL]):
		rig_waiting = false
		_make_rig()
		create_tween().tween_property(self, "rig_fade", 1.0, 0.4)
	var bn := _boat_now()
	if boat3d:
		boat3d.set_pose(float(bn[1]), float(bn[3]))
	if bn[2]:
		# The pickup's back axle, a metre and a half ahead of the hitch.
		var axle: Vector2 = Vector2(bn[0]) + Vector2.from_angle(float(bn[1])) * 1.5 * PX_PER_M
		if trail.is_empty() or Vector2(trail[-1]["p"]).distance_to(axle) > 3.0:
			trail.append({"p": axle, "a": float(bn[1]), "t": clock})
	while not trail.is_empty() and clock - float(trail[0]["t"]) > 5.0:
		trail.remove_at(0)
	for c in clouds:
		c["p"] = Vector2(c["p"]) + Vector2(float(c["v"]), float(c["v"]) * 0.25) * delta
		if Vector2(c["p"]).x > view_size.x + 380.0:
			c["p"] = Vector2(-380.0, randf_range(150, view_size.y - 100))
	for b in butterflies:
		b["dir"] = float(b["dir"]) + sin(clock * 0.7 + float(b["ph"])) * delta * 1.6
		var np: Vector2 = Vector2(b["p"]) + Vector2.from_angle(float(b["dir"])) * 26.0 * delta
		if np.x < 30 or np.x > view_size.x - 30 or np.y < 220 or np.y > view_size.y - 60:
			b["dir"] = (view_size * 0.5 - np).angle()
		b["p"] = np
	for f in flies:
		var p: Vector2 = f["p"] + (f["v"] + Vector2(sin(clock * 0.6 + f["ph"]) * 10.0, 0.0)) * delta
		if p.y < -20.0:
			p.y = view_size.y + 20.0
		p.x = wrapf(p.x, -20.0, view_size.x + 20.0)
		f["p"] = p
	if not fw_shells.is_empty() or not fw_sparks.is_empty() or not fw_flashes.is_empty() or not fw_glints.is_empty() or fw_show:
		_fw_step(delta)
	if is_instance_valid(cele_fx):
		cele_fx.queue_redraw()
	if is_instance_valid(_tease_swan):
		# The map's swan renders only while she's drawn (not while a lake is in focus or being dived into).
		var want := SubViewport.UPDATE_ALWAYS if clock - _tease_seen < 0.25 else SubViewport.UPDATE_DISABLED
		if _tease_swan.render_target_update_mode != want:
			_tease_swan.render_target_update_mode = want
	draw_node.queue_redraw()
	glow_node.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if arrive_t >= 0.0:
		# The lift of the tap that left the lake arrives here too; only a fresh tap skips.
		if event is InputEventScreenTouch:
			if event.pressed:
				skip_armed = true
			elif skip_armed:
				arrive_t = _t_end()  # skip to the end
				_arrive_step()
		return
	if dev_panel != null or settings != null or celebrating or leaving_map:
		return
	if not (event is InputEventScreenTouch and not event.pressed):
		return
	var p := _to_map_space(event.position)
	if focus >= 0:
		if p.distance_to(SPOTS[focus] + off) < FOCUS_RING_MAX:
			_set_off(focus)
		else:
			_unfocus()
		return
	var best := -1
	var best_d := 120.0
	for i in Game.lake_count():
		var d: float = p.distance_to(SPOTS[i] + off)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and Game.is_unlocked(best):
		Sfx.tap()
		_focus(best)
	elif best >= 0:
		Sfx.reject()
		_toast("Light every lantern on %s to open it" % Game.lakes[best - 1]["name"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if arrive_t >= 0.0:
			arrive_t = _t_end()
			_arrive_step()
		elif leaving_map:
			pass
		elif settings != null:
			_close_settings()
		elif focus >= 0:
			_unfocus()
		elif dev_panel != null:
			reload_requested.emit()
		else:
			get_tree().quit()


# ---------------------------------------------------------------- focus on a lake
# Tapping a lake zooms the map in on it and shows its details on the map under it; tapping the lake
# again sets off (the lake zooms the rest of the way in), tapping elsewhere or back zooms out again.
const CARD_PAD_X := 40.0  # the settings card's padding
const CARD_PAD_TOP := 32.0
const CARD_PAD_BOTTOM := 40.0 + 10.0
const FOCUS_Z := 2.0  # how far the map zooms in on a lake
const FOCUS_Y := 0.29  # where the focused lake sits, as a share of the screen height
const FOCUS_TIME := 0.5
const FOCUS_RING := 92.0  # the ring around the focused lake, in map units: from here...
const FOCUS_RING_MAX := 112.0  # ...to here
var focus := -1  # the lake zoomed in on, -1 when showing the whole map
var last_focus := -1  # the lake last zoomed in on: it stays bright while the map zooms back out
var focus_f := 0.0  # 0..1 while zooming in: the other lakes, the path and the small goal icons fade back
var focus_ui: Control
var cam_tween: Tween
var leaving_map := false  # a lake has been set off
var corner_btn: Button  # top right: settings on the map, close while zoomed in on a lake
var corner_icons: Array = []  # [settings, close]
var corner_f := 0.0  # 0 = settings, 1 = close


## Centres the corner icons on the button face (lower while it is pressed down into its edge).
func _place_corner_icons(down: bool) -> void:
	var face := Vector2(64, 64 - 4.0)
	for ic in corner_icons:
		ic.position = (face - ic.size) * 0.5 + Vector2(0, 4.0 if down else 0.0)


func _set_corner(f: float) -> void:
	corner_f = f
	var gear_i: TextureRect = corner_icons[0]
	var close_i: TextureRect = corner_icons[1]
	gear_i.modulate.a = 1.0 - f
	gear_i.rotation = f * PI * 0.5
	close_i.modulate.a = f
	close_i.rotation = (f - 1.0) * PI * 0.5


func _to_map_space(p: Vector2) -> Vector2:
	return (p - position) / scale.x


## Map scale and offset that put lake i's picture at the focus spot.
func _focus_cam(i: int) -> Array:
	var target := Vector2(view_size.x * 0.5, top_inset + view_size.y * FOCUS_Y)
	return [target - (SPOTS[i] + off) * FOCUS_Z, FOCUS_Z]


func _move_cam(pos: Vector2, z: float, f: float) -> void:
	if cam_tween:
		cam_tween.kill()
	cam_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	cam_tween.tween_property(self, "position", pos, FOCUS_TIME)
	cam_tween.tween_property(self, "scale", Vector2(z, z), FOCUS_TIME)
	cam_tween.tween_property(self, "focus_f", f, FOCUS_TIME)
	cam_tween.tween_method(_set_corner, corner_f, f, FOCUS_TIME * 0.7)


func _focus(i: int) -> void:
	focus = i
	last_focus = i
	Game.rig_pending = -1  # the player chose where to go
	_drive_to(i)
	var cam := _focus_cam(i)
	_move_cam(cam[0], cam[1], 1.0)
	var fade := create_tween()
	fade.tween_property(map_ui, "modulate:a", 0.0, FOCUS_TIME * 0.5)
	if is_instance_valid(focus_ui):
		focus_ui.queue_free()
	focus_ui = _build_focus_ui(i)
	focus_ui.modulate.a = 0.0
	var show := focus_ui.create_tween()
	show.tween_interval(FOCUS_TIME * 0.6)
	show.tween_property(focus_ui, "modulate:a", 1.0, 0.25)


func _unfocus() -> void:
	if focus < 0:
		return
	focus = -1
	Sfx.tap()
	_move_cam(Vector2.ZERO, 1.0, 0.0)
	if is_instance_valid(focus_ui):
		var old := focus_ui
		var out := old.create_tween()
		out.tween_property(old, "modulate:a", 0.0, 0.15)
		out.tween_callback(old.queue_free)
	focus_ui = null
	var back := create_tween()
	back.tween_interval(FOCUS_TIME * 0.5)
	back.tween_property(map_ui, "modulate:a", 1.0, FOCUS_TIME * 0.5)


## The focused lake's details, laid out under its picture: number and name, the three goals,
## best time and daylight, and how to set off. Text in the map's ink so it sits on the ground.
func _build_focus_ui(i: int) -> Control:
	var lake: Dictionary = Game.lakes[i]
	var light: Color = lake["pal"]["light"]
	var m := int(Game.marks[i])
	var total: int = lake["lanterns"].size()
	var par := int(lake["par"])
	var inner_w := minf(560.0, view_size.x - 96.0)
	var shadow := _shadow_for(day_t)
	var root := Control.new()
	root.size = view_size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var text := func(t: String, size: int, font: Font, a: float) -> Label:
		var l := Label.new()
		l.text = t
		if font:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", Color(ink, a))
		l.set_meta("ink_a", a)
		l.add_theme_color_override("font_shadow_color", shadow)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(inner_w, 0)
		col.add_child(l)
		return l
	var gap := func(h: float):
		var g := Control.new()
		g.custom_minimum_size = Vector2(0, h)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(g)

	text.call("LAKE %d" % (i + 1), 22, Game.heading_font, 0.65)
	gap.call(4)
	text.call(String(lake["name"]).to_upper(), 40, Game.title_font, 1.0)
	gap.call(24)

	# Goals: the map's dark discs, bigger, each over its label.
	var goals := [["lantern", "All %d lanterns" % total, Game.MARK_ALL],
		[Game.time_goal(i)[0], Game.time_goal(i)[1], Game.MARK_TIME],
		["loop", "Max %d loop%s" % [par, "" if par == 1 else "s"], Game.MARK_LOOPS]]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.custom_minimum_size = Vector2(inner_w, 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for k in 3:
		var on: bool = m & int(goals[k][2]) != 0
		var kind: String = goals[k][0]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.custom_minimum_size = Vector2(inner_w / 3.0, 0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cell)
		var disc := Control.new()
		disc.custom_minimum_size = Vector2(inner_w / 3.0, 64)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.draw.connect(func():
			var c := disc.size * 0.5
			disc.draw_circle(c, 30.0, Color(0.03, 0.06, 0.08, 0.62 if on else 0.42), true, -1.0, true)
			Game.draw_icon(disc, kind, c, 34, light if on else Color(1, 1, 1, 0.5)))
		cell.add_child(disc)
		var gl := Label.new()
		gl.text = String(goals[k][1])
		gl.add_theme_font_size_override("font_size", 20)
		gl.add_theme_color_override("font_color", Color(ink, 0.9 if on else 0.72))
		gl.set_meta("ink_a", 0.9 if on else 0.72)
		gl.add_theme_color_override("font_shadow_color", shadow)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(gl)
	gap.call(24)

	var best := float(Game.stats[i]["best"])
	var day := int(Game.lake_duration(i))
	text.call(("Best  %d s      Daylight  %d s" % [roundi(best), day]) if best > 0.0 else "Daylight  %d s" % day, 24, null, 0.8)
	gap.call(24)

	# How to set off, on a small dark plate so it reads on any ground.
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.031, 0.067, 0.086, 0.85)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	plate.add_theme_stylebox_override("panel", sb)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint := Label.new()
	hint.text = "TAP THE LAKE TO SET OFF"
	hint.add_theme_font_override("font", Game.heading_font)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", light)
	plate.add_child(hint)
	col.add_child(plate)

	# Under the lake's picture once zoomed in, clear of the ring that pulses around it.
	col.reset_size()
	col.position = Vector2((view_size.x - inner_w) * 0.5,
		top_inset + view_size.y * FOCUS_Y + FOCUS_RING_MAX * FOCUS_Z + 12.0)
	return root


## Tapping the focused lake: the lake zooms the rest of the way in and starts.
func _set_off(i: int) -> void:
	if leaving_map:
		return
	leaving_map = true
	Sfx.tap()
	lake_chosen.emit(i)


func _open_curve(pts: PackedVector2Array, sub: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in sub:
			var t := float(s) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


func _draw_map(n: Node2D) -> void:
	# Dotted path between the lakes; where it is lit, the dots are small warm lamps.
	var dot_a := 1.0 - 0.75 * focus_f
	for d in road_dots:
		var lit := _road_lamp(float(d[1]))
		if lit <= 0.0:
			n.draw_circle(d[0], 2.4, Color(ink, 0.28 * dot_a))
		else:
			var warm := Color(1.0, 0.9, 0.7, lerpf(0.42, 0.75, smoothstep(0.4, 0.85, day_t)) * dot_a)
			n.draw_circle(d[0], 2.4, Color(ink, 0.28 * dot_a).lerp(warm, lit))

	# Trees, shadows first: the shadow falls away from the sun (down and left by day, longer as it sinks).
	var green := Color("5f8a4a").lerp(Color("1e2c26"), smoothstep(0.4, 1.0, day_t))
	var green_hi := Color("86b065").lerp(Color("2b3d33"), smoothstep(0.4, 1.0, day_t))
	var shadow_off := Vector2(-10, 14).lerp(Vector2(-30, 10), smoothstep(0.0, 0.7, day_t))
	var shadow_a := 0.22 * (1.0 - smoothstep(0.65, 0.9, day_t))
	for t in trees:
		n.draw_circle(Vector2(t["p"]) + shadow_off, float(t["r"]), Color(0.05, 0.1, 0.05, shadow_a), true, -1.0, true)
	for t in trees:
		var tp: Vector2 = t["p"]
		var tr := float(t["r"])
		n.draw_circle(tp, tr, green, true, -1.0, true)
		n.draw_circle(tp + Vector2(tr * 0.22, -tr * 0.25), tr * 0.6, green_hi, true, -1.0, true)

	for i in Game.lake_count():
		var lake: Dictionary = Game.lakes[i]
		var pal: Dictionary = lake["pal"]
		var of := _open_f(i)
		var alpha := lerpf(0.3, 1.0, of)
		if i != (focus if focus >= 0 else last_focus):
			alpha *= 1.0 - 0.7 * focus_f
		var spot: Vector2 = SPOTS[i] + off
		var origin := spot - LAKE_CENTER * THUMB
		var bob := sin(clock * 0.9 + i) * 2.0 * (still_amp if i == still_lake else 1.0)
		origin.y += bob
		var th: Dictionary = thumbs[i]
		n.draw_set_transform(origin + Vector2(6, 9), 0.0, Vector2(THUMB, THUMB))
		n.draw_colored_polygon(th["water"], Color(0, 0, 0, 0.28 * alpha))
		n.draw_set_transform(origin, 0.0, Vector2(THUMB, THUMB))
		for p in th["sand"]:
			n.draw_colored_polygon(p, Color(pal["sand"], alpha))
		n.draw_colored_polygon(th["water"], Color(pal["shallow"], alpha))
		for p in th["mid"]:
			n.draw_colored_polygon(p, Color(pal["mid"], alpha))
		for p in th["deep"]:
			n.draw_colored_polygon(p, Color(pal["deep"], alpha))
		# Lanterns: small storm lanterns, at exactly the size and place of the lake's own lanterns, so the
		# camera can dive straight into them (dots until the lantern pictures are ready at start-up).
		var done := Game.lake_done(i)
		var mini := 1.0 if Game.lantern_lit else 0.0
		var lamp: Texture2D = Game.lantern_lit if done else Game.lantern_unlit
		for li in lake["lanterns"].size():
			var l: Array = lake["lanterns"][li]
			var lp := Vector2(l[0], l[1])
			if mini < 1.0:
				var c := Color(pal["light"], alpha) if done else Color(pal["light"].darkened(0.45), alpha)
				c.a *= 1.0 - mini
				n.draw_circle(lp, 34.0, c)
			if mini > 0.0:
				# While diving in or out of this lake, its lanterns match the lake's own, then ease back.
				var r := Rect2(lp - Game.lantern_anchor * Game.LANTERN_SCALE, lamp.get_size() * Game.LANTERN_SCALE)
				var tex := lamp
				if i == still_lake and li < still_lit.size():
					tex = Game.lantern_lit if still_lit[li] else Game.lantern_unlit
				n.draw_texture_rect(tex, r, false, Color(1, 1, 1, alpha * mini))
				if tex != lamp and i == still_lake and still_amp > 0.0:
					n.draw_texture_rect(lamp, r, false, Color(1, 1, 1, alpha * mini * still_amp))
		# Each lake's own thing, open or locked; gone while the camera dives into (or out of) a lake.
		var tease_a := (1.0 - focus_f) * clampf(2.0 - scale.x, 0.0, 1.0)
		if tease_a > 0.0:
			_thumb_xf = Transform2D(0.0, Vector2(THUMB, THUMB), 0.0, origin)
			_draw_teaser(n, i, th, tease_a)  # still in the lake's own coordinates
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Goals under the name, as the same icons used everywhere else. Each sits on a small dark disc,
		# like the lock, so it reads on every ground from morning green to night: earned ones in the
		# lake's light, the rest a dim white.
		var left_side := spot.x < 360.0 + off.x
		var m := int(Game.marks[i])
		for k in (3 if focus_f < 1.0 else 0):
			var x := spot.x + 108 + k * 38 if left_side else spot.x - 108 - (2 - k) * 38
			var gp := Vector2(x, spot.y + 26)
			var kind: String = ["lantern", Game.time_goal(i)[0], "loop"][k]
			var on := m & (1 << k) != 0
			var ga := (1.0 - focus_f) * clampf(3.0 - scale.x, 0.0, 1.0) * cele_icons_a  # hidden while the camera is close in (and under the chapter words on a short screen)
			n.draw_circle(gp, 17.0, Color(0.03, 0.06, 0.08, (0.62 if on else 0.42) * lerpf(0.6, 1.0, of) * ga), true, -1.0, true)
			Game.draw_icon(n, kind, gp, 24, Color(Color(pal["light"]) if on else Color(1, 1, 1, lerpf(0.3, 0.5, of)), (1.0 if on else lerpf(0.3, 0.5, of)) * ga))
		if of < 1.0:
			# Locked; while a lake opens, its lock swells and fades away.
			var lk := 1.0 + 0.6 * of
			var la := (1.0 - of) * (1.0 - 0.7 * focus_f)
			n.draw_circle(spot, 30.0 * lk, Color(0.03, 0.06, 0.08, 0.75 * la), true, -1.0, true)
			Game.draw_icon(n, "lock", spot, 30 * lk, Color(1, 1, 1, 0.85 * la))

	# Cloud shadows over everything on the ground, fading out toward night.
	var shade := (1.0 - smoothstep(0.55, 0.9, day_t)) * 0.13
	if shade > 0.0:
		for c in clouds:
			for q in c["puffs"]:
				var r := float(q["r"])
				var cp: Vector2 = Vector2(c["p"]) + Vector2(q["o"])
				n.draw_texture_rect(Game.glow_tex, Rect2(cp - Vector2(r, r * 0.7), Vector2(r * 2.0, r * 1.4)), false, Color(0.05, 0.12, 0.08, shade))
	# Butterflies by day.
	var fly_a := 1.0 - smoothstep(0.45, 0.7, day_t)
	if fly_a > 0.0:
		for b in butterflies:
			var bp: Vector2 = b["p"]
			var flap := absf(sin(clock * 9.0 + float(b["ph"])))
			var ang := float(b["dir"]) + PI * 0.5
			n.draw_set_transform(bp + Vector2(3, 5), ang, Vector2.ONE)
			_draw_wings(n, flap, Color(0, 0, 0, 0.12 * fly_a))
			n.draw_set_transform(bp, ang, Vector2.ONE)
			_draw_wings(n, flap, Color(b["c"], fly_a))
			n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var fl := focus if focus >= 0 else last_focus
	if fl >= 0 and focus_f > 0.0 and not leaving_map:
		var rk := fmod(clock / 2.2, 1.0)
		var fc: Color = Game.lakes[fl]["pal"]["light"]
		var ra := focus_ui.modulate.a if focus >= 0 and is_instance_valid(focus_ui) else focus_f
		n.draw_arc(SPOTS[fl] + off, FOCUS_RING + rk * (FOCUS_RING_MAX - FOCUS_RING), 0.0, TAU, 64, Color(fc, 0.7 * (1.0 - rk) * ra), 2.0, true)

	# Chapter-complete ripples.
	for r in rings:
		for k in 2:
			var rk := (clock - float(r["t"]) - 0.28 * k) / 1.8
			if rk >= 0.0 and rk <= 1.0:
				var e := 1.0 - (1.0 - rk) * (1.0 - rk)
				n.draw_arc(r["p"], 46.0 + e * 110.0, 0.0, TAU, 64, Color(r["c"], (0.8 - 0.3 * k) * (1.0 - rk)), 3.2 * (1.0 - rk) + 0.8, true)

	# The pickup parked by the current lake, or towing the boat to the next one, leaving tyre tracks.
	var half_track := 0.85 * PX_PER_M
	for k in range(1, trail.size()):
		var age := (clock - float(trail[k]["t"])) / 5.0
		var col := Color(0.32, 0.24, 0.14, 0.32 * (1.0 - age))
		var sd0 := Vector2.from_angle(float(trail[k - 1]["a"])).orthogonal() * half_track
		var sd1 := Vector2.from_angle(float(trail[k]["a"])).orthogonal() * half_track
		for side in [-1.0, 1.0]:
			n.draw_line(Vector2(trail[k - 1]["p"]) + sd0 * side, Vector2(trail[k]["p"]) + sd1 * side, col, 1.4, true)
	var bn := _boat_now()
	var bp: Vector2 = bn[0]
	if rig_waiting:
		return  # still loading: it fades in shortly
	if boat3d:
		_draw_boat(n, bp, 0.0)
		return
	n.draw_set_transform(bp, float(bn[1]), Vector2(1.1, 1.1))
	n.draw_colored_polygon(PackedVector2Array(HULL), Color("efe6d6"))
	n.draw_rect(Rect2(-9, -4.5, 11, 9), Color("c9bca5"))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The rig's render with its hitch at p, and its shadow on the ground.
func _make_rig() -> void:
	boat3d = Rig3D.new()
	boat3d.render_px = RIG_RENDER
	add_child(boat3d)


func _draw_boat(ci: CanvasItem, p: Vector2, _rot: float) -> void:
	var tex := boat3d.get_texture()
	var at: Vector2 = -boat3d.anchor()
	ci.draw_set_transform(p + Vector2(-4, 5), 0.0, Vector2.ONE * RIG_SCALE)
	ci.draw_texture(tex, at, Color(0.05, 0.08, 0.05, 0.3 * rig_fade))
	ci.draw_set_transform(p, 0.0, Vector2.ONE * RIG_SCALE)
	ci.draw_texture(tex, at, Color(1, 1, 1, rig_fade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wings(n: Node2D, flap: float, col: Color) -> void:
	var w := 4.0 + 6.0 * flap
	for side in [-1.0, 1.0]:
		n.draw_colored_polygon(PackedVector2Array([Vector2(0, -2), Vector2(side * w, -7), Vector2(side * w * 0.9, 1), Vector2(0, 2)]), col)
		n.draw_colored_polygon(PackedVector2Array([Vector2(0, 1), Vector2(side * w * 0.7, 3), Vector2(side * w * 0.5, 7), Vector2(0, 4)]), col)


func _draw_glow(n: Node2D) -> void:
	var glow: Texture2D = Game.glow_tex
	# The pickup's headlights from dusk: two warm beams on the road ahead and a glow.
	var beams := smoothstep(0.5, 0.85, day_t)
	if boat3d and beams > 0.0:
		var hl: Array = boat3d.headlamps()
		if not hl.is_empty():
			var bn := _boat_now()
			var at: Vector2 = Vector2(bn[0]) - boat3d.anchor() * RIG_SCALE
			var ang: float = hl[2]
			var warm := Color(1.0, 0.9, 0.68)
			for k in 2:
				var o: Vector2 = at + Vector2(hl[k]) * RIG_SCALE
				Game.draw_beam(n, o, ang, 80.0, 66.0, Color(warm, 0.55 * beams))
				n.draw_texture_rect(glow, Rect2(o - Vector2(5, 5), Vector2(10, 10)), false, Color(1, 0.97, 0.88, 0.9 * beams))
			# Where the two beams meet the ground ahead: a soft pool of light.
			var mid: Vector2 = at + (Vector2(hl[0]) + Vector2(hl[1])) * 0.5 * RIG_SCALE + Vector2.from_angle(ang) * 34.0
			n.draw_texture_rect(glow, Rect2(mid - Vector2(34, 34), Vector2(68, 68)), false, Color(warm, 0.22 * beams))
	# The sun: high in the top right in the morning, sinking toward the right edge and warming to
	# orange through the afternoon, gone at night.
	var sun_a := 1.0 - smoothstep(0.7, 0.95, day_t)
	if sun_a > 0.0:
		var sp := Vector2(view_size.x * lerpf(0.88, 1.06, day_t), lerpf(-40.0, view_size.y * 0.55, smoothstep(0.0, 0.9, day_t)))
		var sc := Color("fff4d6").lerp(Color("ffa860"), smoothstep(0.2, 0.75, day_t))
		for k in 3:
			var r: float = [620.0, 300.0, 120.0][k]
			n.draw_texture_rect(glow, Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(sc, float([0.28, 0.32, 0.55][k]) * sun_a))
	var dark := smoothstep(0.45, 0.85, day_t)
	for i in Game.lake_count():
		if not Game.lake_done(i):
			continue
		var spot: Vector2 = SPOTS[i] + off
		var c: Color = Game.lakes[i]["pal"]["light"]
		var lit := float(lake_lit[i])
		var fl := float(lake_flare[i])
		var r := 80.0 + 50.0 * fl
		n.draw_texture_rect(glow, Rect2(spot - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c, 0.22 * lit + 0.4 * fl))
		# After dark each lantern lays a warm, flickering pool of light on the water around it.
		if dark > 0.0 and lit > 0.0:
			var origin := spot - LAKE_CENTER * THUMB + Vector2(0, sin(clock * 0.9 + i) * 2.0 * (still_amp if i == still_lake else 1.0))
			var lights: Array = Game.lakes[i]["lanterns"]
			for li in lights.size():
				var lp := origin + Vector2(lights[li][0], lights[li][1]) * THUMB
				var flick := 0.86 + 0.08 * sin(clock * 7.1 + li * 2.3 + i) + 0.06 * sin(clock * 12.7 + li)
				var pr := 26.0 * flick
				n.draw_texture_rect(glow, Rect2(lp - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false, Color(c, 0.34 * dark * lit * flick))
	# Fireflies round the lakes once the chapter is complete: they wander slowly near the shore and flash
	# on briefly every few seconds, each to its own rhythm, then go dark again.
	var shore_a := shore_fly_a * smoothstep(0.55, 0.85, day_t)
	if shore_a > 0.0:
		for f in shore_flies:
			var per := float(f["per"])
			var u := fposmod(clock + float(f["ph"]) * per, per) / per
			var flash := smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.1, 0.32, u))
			if flash <= 0.01:
				continue
			var ph := float(f["ph"]) * TAU
			var fp: Vector2 = Vector2(f["home"]) + Vector2(sin(clock * float(f["sx"]) + ph) * 26.0 + sin(clock * 0.9 + ph * 2.0) * 8.0,
				cos(clock * float(f["sy"]) + ph) * 20.0 + sin(clock * 1.3 + ph) * 6.0)
			var col := Color(0.8, 1.0, 0.45)
			n.draw_texture_rect(glow, Rect2(fp - Vector2(13, 13), Vector2(26, 26)), false, Color(col, 0.55 * flash * shore_a))
			n.draw_texture_rect(glow, Rect2(fp - Vector2(3.5, 3.5), Vector2(7, 7)), false, Color(1.0, 1.0, 0.85, flash * shore_a))
	# The road's lamps: barely a warmth by day, a soft glow after dusk; the leading lamp brighter while a
	# stretch is lighting.
	var lamp_a := 0.03 + 0.3 * smoothstep(0.4, 0.85, day_t)
	for d in road_dots:
		var lit := _road_lamp(float(d[1]))
		if lit <= 0.0:
			continue
		var u := float(d[1])
		var flick := 0.93 + 0.07 * sin(clock * 2.3 + u * 7.0)
		var r := 9.0 + 3.0 * smoothstep(0.4, 0.85, day_t)
		n.draw_texture_rect(glow, Rect2(Vector2(d[0]) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1.0, 0.82, 0.52, lamp_a * lit * flick))
		if road_front >= 0.0 and absf(u - road_front) < 0.06:
			var k := 1.0 - absf(u - road_front) / 0.06
			n.draw_texture_rect(glow, Rect2(Vector2(d[0]) - Vector2(20, 20), Vector2(40, 40)), false, Color(1.0, 0.86, 0.6, 0.5 * k))
	var fire_a := smoothstep(0.5, 0.8, day_t)
	for f in flies:
		if fire_a <= 0.0:
			break
		var tw := (0.5 + 0.5 * sin(clock * 2.0 + float(f["ph"]) * 3.0)) * fire_a
		var r := 8.0
		n.draw_texture_rect(glow, Rect2(f["p"] - Vector2(r, r), Vector2(r, r) * 2.0), false,
			Color(1.0, 0.93, 0.66, tw * 0.55))


const DEV_ITEMS := [
	["chains", "Chain loops", "Quick loops one after another give the sun +3 s."],
	["boost", "Speed boost", "3 lanterns within 7 s gives 4.5 s of swift water."],
	["life", "Moving life", "Ducks cut your wake, fish jump, lanterns drift."],
	["fading", "Fading lanterns", "Lit lanterns go out again after 28 s."],
	["crash", "Crashes end the run", "Hitting a rock, or the shore head-on, ends the lake."],
	["unlock_all", "Unlock all lakes", "For testing."],
	["boat3d", "3D boat (test)", "Draws the boat as a 3D model. Turn off to compare with the flat boat."],
]


func _open_dev() -> void:
	if dev_panel != null:
		return
	Sfx.tap()
	dev_panel = Control.new()
	dev_panel.size = view_size
	dev_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(dev_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.08, 0.92)
	dim.size = view_size
	dev_panel.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(48, top_inset + 50)
	scroll.size = Vector2(view_size.x - 96, view_size.y - top_inset - 80)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dev_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(view_size.x - 96, 0)
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	var head := Label.new()
	head.text = "Developer settings"
	head.add_theme_font_override("font", Game.heading_font)
	head.add_theme_font_size_override("font_size", 38)
	box.add_child(head)
	var note := Label.new()
	note.text = "Mechanics being tested. Changes apply to the next lake you start."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 21)
	note.modulate.a = 0.6
	box.add_child(note)
	for item in DEV_ITEMS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var cb := CheckButton.new()
		cb.text = item[1]
		cb.button_pressed = Game.dev_on(item[0])
		cb.add_theme_font_size_override("font_size", 27)
		var key: String = item[0]
		cb.toggled.connect(func(on: bool):
			Game.set_dev(key, on)
			Sfx.tap())
		row.add_child(cb)
		var desc := Label.new()
		desc.text = item[2]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 19)
		desc.modulate.a = 0.55
		row.add_child(desc)
		box.add_child(row)
	var day_head := Label.new()
	day_head.add_theme_font_size_override("font_size", 25)
	box.add_child(day_head)
	var day_note := Label.new()
	day_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	day_note.add_theme_font_size_override("font_size", 18)
	day_note.modulate.a = 0.7
	var mult := HSlider.new()
	mult.min_value = 0.5
	mult.max_value = 2.0
	mult.step = 0.05
	mult.value = Game.day_mult
	mult.custom_minimum_size = Vector2(0, 48)
	var fixed := HSlider.new()
	fixed.min_value = 0
	fixed.max_value = 90
	fixed.step = 5
	fixed.value = Game.day_fixed
	fixed.custom_minimum_size = Vector2(0, 48)
	var mult_l := Label.new()
	mult_l.add_theme_font_size_override("font_size", 20)
	var fixed_l := Label.new()
	fixed_l.add_theme_font_size_override("font_size", 20)
	var refresh := func():
		Game.set_daylight(mult.value, int(fixed.value))
		day_head.text = "Daylight"
		mult_l.text = "Automatic time  ×%.2f" % mult.value
		fixed_l.text = "Same time for every lake:  " + ("off (automatic)" if fixed.value <= 0 else "%d s" % int(fixed.value))
		var parts := PackedStringArray()
		for i in Game.lake_count():
			parts.append("%s %d s" % [Game.lakes[i]["name"], int(Game.lake_duration(i))])
		day_note.text = "Now: " + ",  ".join(parts)
	mult.value_changed.connect(func(_v): refresh.call())
	fixed.value_changed.connect(func(_v): refresh.call())
	refresh.call()
	box.add_child(mult_l)
	box.add_child(mult)
	box.add_child(fixed_l)
	box.add_child(fixed)
	box.add_child(day_note)
	var tilt_l := Label.new()
	tilt_l.add_theme_font_size_override("font_size", 20)
	tilt_l.text = "3D boat camera tilt:  %d°" % int(Game.boat_tilt)
	box.add_child(tilt_l)
	var tilt := HSlider.new()
	tilt.min_value = 0
	tilt.max_value = 60
	tilt.step = 5
	tilt.value = Game.boat_tilt
	tilt.custom_minimum_size = Vector2(0, 48)
	tilt.value_changed.connect(func(v: float):
		Game.set_boat_tilt(v)
		tilt_l.text = "3D boat camera tilt:  %d°" % int(v))
	box.add_child(tilt)
	var st_head := Label.new()
	st_head.text = "Play stats"
	st_head.add_theme_font_size_override("font_size", 25)
	box.add_child(st_head)
	var st := Label.new()
	var lines: Array = []
	for i in Game.lake_count():
		var s: Dictionary = Game.stats[i]
		var best := float(s["best"])
		var line := "%s:  %d tries, %d wins, %d crashes, %d revives%s" % [Game.lakes[i]["name"], s["tries"], s["wins"],
			s["crashes"], s["revives"], (", best %d s" % roundi(best)) if best > 0.0 else ""]
		var lf: Array = s["last_fails"]
		if not lf.is_empty():
			line += "\n      lit when the sun set: " + "  ".join(PackedStringArray(lf))
		lines.append(line)
	st.text = "\n".join(PackedStringArray(lines))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.add_theme_font_size_override("font_size", 18)
	st.modulate.a = 0.7
	box.add_child(st)
	var st_reset := Button.new()
	st_reset.text = "Reset stats"
	st_reset.custom_minimum_size = Vector2(0, 56)
	st_reset.pressed.connect(func():
		Game.reset_stats()
		st.text = "Stats cleared."
		Sfx.tap())
	box.add_child(st_reset)
	var victory := Button.new()
	victory.text = "Play chapter victory"
	victory.custom_minimum_size = Vector2(0, 56)
	victory.pressed.connect(func():
		Sfx.tap()
		Game.dev_victory = true  # the map that opens next plays it, as a test
		reload_requested.emit())
	box.add_child(victory)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var reset := Button.new()
	reset.text = "Reset progress"
	reset.custom_minimum_size = Vector2(0, 66)
	reset.pressed.connect(func():
		Game.reset_progress()
		reset.text = "Progress reset"
		Sfx.tap())
	box.add_child(reset)
	var close := Button.new()
	close.text = "Done"
	close.custom_minimum_size = Vector2(0, 72)
	close.pressed.connect(func():
		Sfx.tap()
		reload_requested.emit())
	box.add_child(close)


## A short message on a dark plate near the bottom of the map.
var _toast_node: Control


func _toast(text: String) -> void:
	if is_instance_valid(_toast_node):
		_toast_node.queue_free()
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.031, 0.067, 0.086, 0.9)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	plate.add_theme_stylebox_override("panel", sb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	plate.add_child(l)
	ui_root.add_child(plate)
	plate.reset_size()
	plate.position = Vector2((view_size.x - plate.size.x) * 0.5, view_size.y - off.y * 0.3 - 120)
	_toast_node = plate
	var tw := plate.create_tween()
	plate.modulate.a = 0.0
	tw.tween_property(plate, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(plate, "modulate:a", 0.0, 0.3)
	tw.tween_callback(plate.queue_free)


## Settings: a card with sound, music and vibration; credits; the developer options.
func _open_settings() -> void:
	if settings != null:
		return
	var card_w := minf(620.0, view_size.x - 48.0)
	var inner_w := card_w - CARD_PAD_X * 2.0
	settings = Control.new()
	settings.size = view_size
	settings.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(settings)
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.047, 0.063, 0.66)
	dim.size = view_size
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed:
			_close_settings())
	settings.add_child(dim)
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("13232a")
	sb.border_color = Color("0a161b")
	sb.border_width_bottom = 10
	sb.set_corner_radius_all(22)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 32
	sb.shadow_offset = Vector2(0, 16)
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	settings.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.position = Vector2(CARD_PAD_X, CARD_PAD_TOP)
	col.size = Vector2(inner_w, 0)
	panel.add_child(col)
	var gap := func(h: float):
		var g := Control.new()
		g.custom_minimum_size = Vector2(0, h)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(g)
	var rule := func():
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.08)
		r.custom_minimum_size = Vector2(inner_w, 2)
		col.add_child(r)
	var kicker := func(text: String) -> Label:
		var k := Label.new()
		k.text = text
		k.add_theme_font_override("font", Game.heading_font)
		k.add_theme_font_size_override("font_size", 22)
		k.modulate.a = 0.55
		return k

	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(inner_w, 64)
	col.add_child(head)
	var title: Label = kicker.call("SETTINGS")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_FILL
	head.add_child(title)
	var close := Game.square_button(Game.icon("close"), 64, 26)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		Sfx.tap()
		_close_settings())
	head.add_child(close)
	gap.call(32)

	# Three toggles, each a square icon button over its name.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	col.add_child(row)
	for spec in [["sound", "Sound"], ["music", "Music"], ["vibration", "Vibration"]]:
		var key: String = spec[0]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 12)
		row.add_child(cell)
		var b := Game.square_button(Game.icon(key), 96, 34)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		Game.style_toggle(b, key, _setting(key))
		b.pressed.connect(func():
			Game.set_setting(key, not _setting(key))
			Game.style_toggle(b, key, _setting(key))
			Sfx.tap())
		cell.add_child(b)
		var l := Label.new()
		l.text = String(spec[1])
		l.add_theme_font_size_override("font_size", 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(120, 0)
		l.modulate.a = 0.75
		cell.add_child(l)
	gap.call(32)
	rule.call()
	gap.call(24)

	col.add_child(kicker.call("CREDITS"))
	gap.call(8)
	var credits := Label.new()
	credits.text = "Boat: \"Fishing Boat\" by CharlieCatling, Sketchfab\nPickup: \"Low Poly Car - Chevrolet C10 Pickup 1963\" by ROH3D (CC BY 4.0)\nTrailer: \"Boat Trailer\" by BoatUS Foundation (CC BY 4.0)\nSwan: \"Animated Swan - Rigged & Optimized\" by GAMICO (CC BY 4.0)\nIcons by Lorc, Delapouite and priorblue, game-icons.net (CC BY 3.0)\nPause, play and restart icons: Phosphor Icons (MIT)\nFont: Josefin Sans by Santiago Orozco (SIL OFL 1.1)\nMade with the Godot Engine"
	credits.add_theme_font_size_override("font_size", 21)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size = Vector2(inner_w, 0)
	credits.modulate.a = 0.75
	col.add_child(credits)
	gap.call(24)
	rule.call()
	gap.call(24)

	# Developer options: a plain full-width row in the same button style.
	var dev := Button.new()
	dev.text = "Developer settings"
	dev.alignment = HORIZONTAL_ALIGNMENT_LEFT
	dev.custom_minimum_size = Vector2(inner_w, 72)
	dev.add_theme_font_size_override("font_size", 24)
	var base := Game.square_button(null, 72, 0)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var bs: StyleBoxFlat = base.get_theme_stylebox(st).duplicate()
		bs.set_corner_radius_all(14)
		bs.content_margin_left = 24
		bs.content_margin_right = 24
		dev.add_theme_stylebox_override(st, bs)
	base.free()
	dev.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	dev.pressed.connect(func():
		Sfx.tap()
		_close_settings()
		_open_dev())
	col.add_child(dev)

	col.reset_size()
	var card_h := CARD_PAD_TOP + col.get_combined_minimum_size().y + CARD_PAD_BOTTOM
	panel.size = Vector2(card_w, card_h)
	panel.position = ((view_size - panel.size) * 0.5).floor()
	settings.modulate.a = 0.0
	settings.create_tween().tween_property(settings, "modulate:a", 1.0, 0.2)


func _close_settings() -> void:
	if settings != null:
		settings.queue_free()
		settings = null


## Chapter complete, shown once (or replayed from the dev panel). Night falls over the map; one by one each
## lake lights up (its lanterns glint, sparks fountain off the water, a small shell goes up, a rising chime)
## and its best time shows beside it, while the road of lights sweeps on; fireflies come out. Then the
## heading and the chapter's numbers over the map itself, under a volley of fireworks. A tap carries on.
func _celebrate() -> void:
	celebrating = true
	cele_armed = false
	cele_blocker = Control.new()  # takes every tap while this plays (the map, the gear), and the last one ends it
	cele_blocker.size = view_size
	cele_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	cele_blocker.gui_input.connect(_on_cele_input)
	ui_root.add_child(cele_blocker)
	cele_ui = Control.new()
	cele_ui.size = view_size
	cele_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(cele_ui)
	cele_fx = Control.new()  # the fireworks: over the map and any shade, under the words
	cele_fx.size = view_size
	cele_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	cele_fx.material = add
	cele_fx.draw.connect(_fw_draw)
	cele_ui.add_child(cele_fx)
	road_lit = 0.0
	for lb in [map_labels[0], map_labels[1], ch2_label]:
		create_tween().tween_property(lb, "modulate:a", 0.0, 0.8)
	if shore_flies.is_empty():
		_make_shore_flies()
	create_tween().tween_property(self, "night_f", 1.0, 3.0).set_trans(Tween.TRANS_SINE)
	create_tween().tween_property(self, "cele_night", 1.0, 3.0).set_trans(Tween.TRANS_SINE)
	var flies_in := create_tween()
	flies_in.tween_interval(1.6)
	flies_in.tween_property(self, "shore_fly_a", 1.0, 3.5)
	for i in Game.lake_count():
		lake_lit[i] = 0.0
	var notes := [1.0, 1.125, 1.25, 1.5, 1.6667]
	var tw := create_tween()
	tw.tween_interval(1.0)
	for i in Game.lake_count():
		var lp: Dictionary = Game.lakes[i]["pal"]
		tw.tween_callback(func():
			_lake_burst(i, Color(lp["light"]))
			lake_flare[i] = 1.0
			var up := create_tween().set_parallel()
			up.tween_method(func(v: float): lake_lit[i] = v, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE)
			up.tween_method(func(v: float): lake_flare[i] = v, 1.0, 0.0, 1.8).set_ease(Tween.EASE_OUT)
			_cele_best_label(i)
			if i > 0:
				_light_road(float(i), 0.55)
			var from: Vector2 = SPOTS[i] + off + Vector2(fw_rng.randf_range(-30.0, 30.0), -40.0)
			_fw_launch(from, from + Vector2(fw_rng.randf_range(-70.0, 70.0), -fw_rng.randf_range(200.0, 260.0)), "peony", 0.6)
			Sfx.ignite()
			Sfx.chime(0.84 * 2.0 * float(notes[i % notes.size()]))
			Game.vibrate(14))
		tw.tween_interval(0.6)
	tw.tween_interval(0.3)
	tw.tween_callback(func():
		Sfx.chord(0.84 * 2.0)
		_show_chapter_words())


## Beside a lake as it lights up: its best time (or that it was lit), in the lake's own light.
func _cele_best_label(i: int) -> void:
	var spot: Vector2 = SPOTS[i] + off
	var left_side := spot.x < 360.0 + off.x
	var best := float(Game.stats[i]["best"])
	var l := Label.new()
	l.text = ("Best  %.1f s" % best) if best > 0.0 else "Lit"
	l.add_theme_font_override("font", Game.heading_font)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(Game.lakes[i]["pal"]["light"]))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.size = Vector2(230, 30)
	if left_side:
		l.position = Vector2(spot.x + 90, spot.y + 50)
	else:
		l.position = Vector2(spot.x - 90 - 230, spot.y + 50)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	cele_ui.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "modulate:a", 1.0, 0.6)
	tw.tween_property(l, "position:y", l.position.y - 8.0, 0.6).from(l.position.y).set_ease(Tween.EASE_OUT)


## The chapter's words at the top and its numbers at the bottom, over soft shade so they read on the map.
func _show_chapter_words() -> void:
	var n := Game.lake_count()
	var lanterns := 0
	var goals := 0
	var tries := 0
	var water := 0.0
	var best_i := -1
	var best_k := INF
	for i in n:
		lanterns += (Game.lakes[i]["lanterns"] as Array).size()
		var m := int(Game.marks[i])
		var got := int(m & 1 != 0) + int(m & 2 != 0) + int(m & 4 != 0)
		goals += got
		var st: Dictionary = Game.stats[i]
		tries += int(st["tries"])
		water += float(st.get("water", 0.0))
		var b := float(st["best"])
		if b > 0.0 and b / maxf(1.0, Game.lake_duration(i)) < best_k:
			best_k = b / maxf(1.0, Game.lake_duration(i))
			best_i = i

	var top := top_inset + off.y * 0.5
	# A tall screen has room above and below the map: the words go at the top and the numbers at the bottom,
	# over soft shade. A short one hasn't: the map dims a little, its labels fade, and it all sits in the middle.
	var compact := view_size.y < 1450.0
	var shades: Array = []
	if compact:
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.05, 0.07, 0.7)
		dim.size = view_size
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shades.append(dim)
		cele_dimmed.clear()
		for lb in map_labels.slice(2, 2 + Game.lake_count()):  # the lake names
			cele_dimmed.append([lb, lb.modulate.a])
			lb.create_tween().tween_property(lb, "modulate:a", 0.0, 0.6)
		for lb in cele_ui.get_children():
			if lb is Label:
				lb.create_tween().tween_property(lb, "modulate:a", 0.0, 0.6)  # the best times beside the lakes
		create_tween().tween_property(self, "cele_icons_a", 0.0, 0.6)
	else:
		shades.append(_shade(true, top + 330.0))
		shades.append(_shade(false, 380.0 + off.y * 0.5))
	for sh in shades:
		cele_ui.add_child(sh)
		cele_ui.move_child(sh, 0)  # under the fireworks
		sh.modulate.a = 0.0
		sh.create_tween().tween_property(sh, "modulate:a", 1.0, 0.8)
	var col: VBoxContainer = null
	if compact:
		col = VBoxContainer.new()
		col.add_theme_constant_override("separation", 56)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.position.x = 30
		col.custom_minimum_size = Vector2(view_size.x - 60, 0)
		cele_ui.add_child(col)
		col.resized.connect(func(): col.position.y = (view_size.y - col.size.y) * 0.5)

	var steps: Array = []  # [node, at seconds]
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.position = Vector2(30, top + 52)
	head.custom_minimum_size = Vector2(view_size.x - 60, 0)
	(col if compact else cele_ui).add_child(head)
	# The heading lands: big and gold, settling from a touch larger.
	var lines := ["CHAPTER ONE", "COMPLETE"]
	var fs := 58
	while fs > 24 and Game.title_font.get_string_size(lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > view_size.x - 80.0:
		fs -= 1
	var heading := _cele_label("\n".join(lines), Game.title_font, fs, 1.0)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.add_theme_color_override("font_color", Color("ffd796"))
	heading.add_theme_constant_override("line_spacing", -6)
	head.add_child(heading)
	var sub := _cele_label("%s lakes  ·  %s lanterns lit" % [_words(n).capitalize(), _words(lanterns)], Game.heading_font, 25, 0.85)
	head.add_child(sub)
	steps.append([sub, 0.6])
	heading.modulate.a = 0.0
	heading.resized.connect(func(): heading.pivot_offset = heading.size * 0.5)
	var land := heading.create_tween().set_parallel()
	land.tween_property(heading, "modulate:a", 1.0, 0.45)
	land.tween_property(heading, "scale", Vector2.ONE, 0.7).from(Vector2.ONE * 1.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Bottom: four even columns of numbers with fine rules between, then the best run, then the way on.
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.position.x = 30
	bottom.custom_minimum_size = Vector2(view_size.x - 60, 0)
	(col if compact else cele_ui).add_child(bottom)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	var counters := [
		[lanterns, "LANTERNS", func(v: float) -> String: return str(roundi(v))],
		[goals, "GOALS", func(v: float) -> String: return "%d/%d" % [roundi(v), n * 3]],
		[tries, "TRIES", func(v: float) -> String: return str(roundi(v))],
		[water, "ON THE WATER", _water_text],
	]
	var col_w := floorf((view_size.x - 60.0 - 3.0) / counters.size())
	var num_font := Game.title_font.duplicate() as FontVariation
	num_font.spacing_glyph = 3
	var t0 := 1.0
	for k in counters.size():
		var c: Array = counters[k]
		if k > 0:
			var rule := ColorRect.new()
			rule.color = Color(1, 1, 1, 0.14)
			rule.custom_minimum_size = Vector2(1, 58)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(rule)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.custom_minimum_size.x = col_w
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var num := _cele_label((c[2] as Callable).call(0.0), num_font, 36, 1.0)
		num.add_theme_color_override("font_color", Color("ffd796"))
		num.autowrap_mode = TextServer.AUTOWRAP_OFF
		num.custom_minimum_size.x = col_w
		var cap := _cele_label(String(c[1]), Game.heading_font, 15, 0.6)
		cap.autowrap_mode = TextServer.AUTOWRAP_OFF
		cap.custom_minimum_size.x = col_w
		box.add_child(num)
		box.add_child(cap)
		row.add_child(box)
		box.modulate.a = 0.0
		var at := t0 + k * 0.45
		var tw := box.create_tween()
		tw.tween_interval(at)
		tw.tween_property(box, "modulate:a", 1.0, 0.3)
		var fmt: Callable = c[2]
		tw.parallel().tween_method(func(v: float):
			var txt: String = fmt.call(v)
			if txt != num.text:
				num.text = txt
				if clock - cele_tick > 0.07:
					cele_tick = clock
					Sfx.tap(), 0.0, float(c[0]), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if best_i >= 0:
		var best := _cele_label("Best run  ·  %s  ·  %.1f s" % [Game.lakes[best_i]["name"], float(Game.stats[best_i]["best"])], Game.heading_font, 20, 0.8)
		bottom.add_child(best)
		steps.append([best, t0 + 2.4])
	var gap := Control.new()  # the way on stands apart from the numbers
	gap.custom_minimum_size = Vector2(0, 58)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)
	var tap := _cele_label("TAP TO CONTINUE", Game.title_font, 19, 0.0)
	bottom.add_child(tap)
	# Sits on the bottom edge once its wrapped lines have their real width (known only after layout).
	if not compact:
		bottom.resized.connect(func(): bottom.position.y = view_size.y - 78.0 - bottom.size.y)

	# The finale: a quick volley of fireworks as the heading lands, then one now and then until the tap.
	fw_show_words = true
	var volley := create_tween()
	for k in 7:
		volley.tween_callback(func(): _fw_random(1.0))
		volley.tween_interval([0.18, 0.35, 0.12, 0.5, 0.3, 0.6, 0.0][k])
	volley.tween_callback(func():
		fw_show = true
		fw_next = 1.0)

	for st in steps:
		var node: Control = st[0]
		var keep := node.modulate.a
		node.modulate.a = 0.0
		var tw := node.create_tween()
		tw.tween_interval(float(st[1]))
		tw.tween_property(node, "modulate:a", keep, 0.7)
	var arm := create_tween()
	arm.tween_interval(t0 + 3.2)
	arm.tween_callback(func():
		cele_armed = true
		var blink := tap.create_tween().set_loops()
		blink.tween_property(tap, "modulate:a", 0.85, 0.9).set_trans(Tween.TRANS_SINE)
		blink.tween_property(tap, "modulate:a", 0.35, 0.9).set_trans(Tween.TRANS_SINE))


func _on_cele_input(e: InputEvent) -> void:
	if not (e is InputEventScreenTouch and not e.pressed and celebrating and cele_armed):
		return
	Sfx.tap()
	if cele_test:
		_end_cele_test()
	else:
		Game.mark_chapter_seen()
	celebrating = false
	cele_armed = false
	var out := cele_ui.create_tween()
	out.tween_property(cele_ui, "modulate:a", 0.0, 0.5)
	out.tween_callback(cele_ui.queue_free)
	cele_blocker.queue_free()
	for d in cele_dimmed:
		create_tween().tween_property(d[0], "modulate:a", float(d[1]), 0.6)
	cele_dimmed.clear()
	create_tween().tween_property(self, "cele_icons_a", 1.0, 0.6)
	create_tween().tween_property(map_labels[0], "modulate:a", 1.0, 0.6)
	create_tween().tween_property(map_labels[1], "modulate:a", 0.75, 0.6)
	create_tween().tween_property(ch2_label, "modulate:a", 0.55, 0.6)
	fw_show = false
	fw_show_words = false
	create_tween().tween_property(self, "cele_night", 0.0, 2.5).set_trans(Tween.TRANS_SINE)  # back to this spot's own time of day


## After a dev replay: the lakes, the road, the fireflies and the night go back to what this save really has.
func _end_cele_test() -> void:
	cele_test = false
	var done := Game.chapter_done() and Game.chapter_seen
	var back := create_tween().set_parallel()
	back.tween_property(self, "night_f", 1.0 if done else 0.0, 2.5).set_trans(Tween.TRANS_SINE)
	back.tween_property(self, "shore_fly_a", 1.0 if done else 0.0, 2.0)
	back.tween_method(func(v: float): road_lit = v, road_lit, _road_done(), 1.2)
	for i in Game.lake_count():
		lake_lit[i] = 1.0 if Game.lake_done(i) else 0.0


func _cele_label(text: String, font: Font, size: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = text
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = view_size.x - 60.0  # a set width, so wrapped lines measure right in a container
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = alpha
	return l


## A soft dark shade from one edge of the screen, so words read over the map.
func _shade(from_top: bool, h: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.05, 0.07, 0.78), Color(0.02, 0.05, 0.07, 0.45), Color(0.02, 0.05, 0.07, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0) if from_top else Vector2(0.5, 1.0)
	t.fill_to = Vector2(0.5, 1.0) if from_top else Vector2(0.5, 0.0)
	t.width = 4
	t.height = 64
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = Vector2(view_size.x, h)
	r.position = Vector2(0, 0.0 if from_top else view_size.y - h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _water_text(v: float) -> String:
	var mins := roundi(v / 60.0)
	if v < 60.0:
		return "%d s" % roundi(v)
	if mins < 60:
		return "%d min" % mins
	return "%d h %d min" % [mins / 60, mins % 60]


## Small numbers in words, for the chapter's title.
func _words(v: int) -> String:
	var ones := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
		"twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
	var tens := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
	if v < 20:
		return ones[v]
	if v < 100:
		return tens[v / 10] + ("" if v % 10 == 0 else "-" + ones[v % 10])
	return str(v)


## The road's dots, every 15 px along it, each with how far along it is in lakes (the curve has 16 points
## from one lake to the next).
func _make_road_dots() -> void:
	road_dots.clear()
	var acc := 0.0
	for i in range(1, path_pts.size()):
		var a := path_pts[i - 1]
		var b := path_pts[i]
		var seg := a.distance_to(b)
		while acc < seg:
			road_dots.append([a.lerp(b, acc / seg), (float(i - 1) + acc / seg) / 16.0])
			acc += 15.0
		acc -= seg


## How much of the road the finished lakes light: up to the last lake of an unbroken run from the first.
func _road_done() -> float:
	var k := -1
	for i in Game.lake_count():
		if not Game.lake_done(i):
			break
		k = i
	return float(maxi(k, 0))


## 0..1: how lit the road's lamp at u (in lakes) is; the lit edge is soft, a lamp or two wide.
func _road_lamp(u: float) -> float:
	return smoothstep(u - 0.05, u, road_lit)


## Lights the road on to `to`, lamp by lamp, over `secs`.
func _light_road(to: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float):
		road_lit = v
		road_front = v, road_lit, to, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): road_front = -1.0)


## A shell of a random kind and colour, up into the open sky between the lakes.
func _fw_random(k: float) -> void:
	var to := Vector2(fw_rng.randf_range(150.0, 570.0), fw_rng.randf_range(330.0, 820.0)) + off
	if view_size.y < 1450.0 and fw_show_words:
		# A short screen has the words in the middle: burst above or below them instead.
		var above := fw_rng.randf() < 0.5
		to = Vector2(fw_rng.randf_range(130.0, view_size.x - 130.0),
			fw_rng.randf_range(150.0, 280.0) if above else fw_rng.randf_range(view_size.y - 300.0, view_size.y - 170.0))
	var from := Vector2(to.x + fw_rng.randf_range(-50.0, 50.0), minf(view_size.y + 30.0, to.y + fw_rng.randf_range(420.0, 560.0)))
	var kinds := ["peony", "peony", "willow", "crackle", "glitter"]
	_fw_launch(from, to, kinds[fw_rng.randi() % kinds.size()], k * fw_rng.randf_range(0.85, 1.15))


func _fw_launch(from: Vector2, to: Vector2, kind: String, k: float) -> void:
	var col: Color = FW_COLORS[fw_rng.randi() % FW_COLORS.size()]
	var col2: Color = col if fw_rng.randf() < 0.5 else FW_COLORS[fw_rng.randi() % FW_COLORS.size()]
	if kind == "willow":
		col = Color(1.0, 0.8, 0.45)
		col2 = Color(1.0, 0.55, 0.22)
	fw_shells.append({"from": from, "to": to, "p": from, "t": 0.0, "dur": fw_rng.randf_range(0.95, 1.3),
		"kind": kind, "k": k, "col": col, "col2": col2, "trail": 0.0, "ph": fw_rng.randf() * TAU})
	Sfx.fw_launch()


## Moves everything in the air: shells rise (slowing towards the top, a little wobble, a trail of embers),
## sparks slow in the air and fall, crackle stars pop at the end; the finale sends up more now and then.
func _fw_step(delta: float) -> void:
	var keep: Array = []
	for sh in fw_shells:
		sh["t"] = float(sh["t"]) + delta
		var u := clampf(float(sh["t"]) / float(sh["dur"]), 0.0, 1.0)
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		sh["p"] = Vector2(sh["from"]).lerp(sh["to"], e) + Vector2(sin(float(sh["t"]) * 11.0 + float(sh["ph"])) * 1.6, 0.0)
		sh["trail"] = float(sh["trail"]) - delta
		if float(sh["trail"]) <= 0.0:
			sh["trail"] = 0.018
			fw_sparks.append({"p": sh["p"], "v": Vector2(fw_rng.randf_range(-12, 12), fw_rng.randf_range(4, 22)), "age": 0.0,
				"life": fw_rng.randf_range(0.3, 0.55), "col": Color(1.0, 0.82, 0.55), "col2": Color(1.0, 0.5, 0.2),
				"drag": 3.0, "g": 30.0, "streak": 0.0, "kind": "ember", "w": fw_rng.randf() * TAU})
		if u >= 1.0:
			_fw_burst(sh)
		else:
			keep.append(sh)
	fw_shells = keep
	var alive: Array = []
	for sp in fw_sparks:
		sp["age"] = float(sp["age"]) + delta
		if float(sp["age"]) >= float(sp["life"]):
			if sp["kind"] == "crackle":
				for c in 2:
					fw_flashes.append({"p": Vector2(sp["p"]) + Vector2(fw_rng.randf_range(-6, 6), fw_rng.randf_range(-6, 6)),
						"c": Color(1.0, 0.98, 0.9), "t0": clock + fw_rng.randf() * 0.12, "s": 9.0, "len": 0.09})
			continue
		var v: Vector2 = sp["v"] * exp(-float(sp["drag"]) * delta)
		v.y += float(sp["g"]) * delta
		sp["v"] = v
		sp["p"] = Vector2(sp["p"]) + v * delta
		alive.append(sp)
	fw_sparks = alive
	var lit: Array = []
	for f in fw_flashes:
		if clock - float(f["t0"]) < float(f["len"]):
			lit.append(f)
	fw_flashes = lit
	var shining: Array = []
	for gl in fw_glints:
		if clock - float(gl["t0"]) < 0.7:
			shining.append(gl)
	fw_glints = shining
	if fw_show:
		fw_next -= delta
		if fw_next <= 0.0:
			_fw_random(fw_rng.randf_range(0.75, 1.0))
			if fw_rng.randf() < 0.3:
				_fw_random(fw_rng.randf_range(0.6, 0.85))  # sometimes two together
			fw_next = fw_rng.randf_range(1.1, 2.1)


## A shell bursts: a white-hot flash, then its stars. Seen side on, a sphere of stars looks densest at its
## rim, so each star's speed is the sphere's speed times how side-on it flies.
func _fw_burst(sh: Dictionary) -> void:
	var p: Vector2 = sh["p"]
	var k := float(sh["k"])
	var kind: String = sh["kind"]
	var n := 120
	var speed := 330.0
	var drag := 1.8
	var g := 58.0
	var life := Vector2(1.4, 2.0)
	var streak := 0.06
	match kind:
		"willow":
			n = 100
			speed = 250.0
			drag = 2.4
			g = 22.0
			life = Vector2(2.6, 3.3)
			streak = 0.16
		"crackle":
			n = 80
			speed = 290.0
			life = Vector2(0.9, 1.3)
		"glitter":
			n = 100
			speed = 300.0
			life = Vector2(1.6, 2.2)
	n = int(n * lerpf(0.6, 1.0, clampf(k, 0.0, 1.0)))
	for i in n:
		var z := fw_rng.randf_range(-1.0, 1.0)
		var dir := Vector2.from_angle(fw_rng.randf() * TAU) * sqrt(1.0 - z * z)
		fw_sparks.append({"p": p, "v": dir * speed * k * fw_rng.randf_range(0.92, 1.05), "age": 0.0,
			"life": fw_rng.randf_range(life.x, life.y), "col": sh["col"], "col2": sh["col2"], "drag": drag, "g": g,
			"streak": streak, "kind": kind, "w": fw_rng.randf() * TAU})
	fw_flashes.append({"p": p, "c": Color(sh["col"]).lerp(Color.WHITE, 0.5), "t0": clock, "s": 190.0 * k, "len": 0.35})
	# The sound arrives a moment after the light.
	var big := k
	get_tree().create_timer(fw_rng.randf_range(0.1, 0.25)).timeout.connect(Sfx.fw_boom.bind(big))  # not tied to the map, which may be gone by then
	if kind == "crackle":
		get_tree().create_timer(1.0).timeout.connect(Sfx.fw_crackle)


## A lake lighting up in the celebration: its lanterns flash one after another with a star glint, and a
## fountain of sparks in the lake's light shoots up off the water and falls back.
func _lake_burst(i: int, col: Color) -> void:
	var origin: Vector2 = SPOTS[i] + off - LAKE_CENTER * THUMB
	var lights: Array = Game.lakes[i]["lanterns"]
	for li in lights.size():
		var rays: Array = []  # each glint's own few rays, uneven in angle and length, so no two look ruled
		var base := fw_rng.randf() * TAU
		for r in fw_rng.randi_range(4, 6):
			rays.append([base + TAU * r / 5.0 + fw_rng.randf_range(-0.35, 0.35), fw_rng.randf_range(0.55, 1.15)])
		fw_glints.append({"p": origin + Vector2(lights[li][0], lights[li][1]) * THUMB, "t0": clock + li * 0.08, "c": col,
			"rays": rays, "spin": fw_rng.randf_range(-0.5, 0.5)})
	var c: Vector2 = SPOTS[i] + off
	for k in 46:
		var from := c + Vector2(fw_rng.randf_range(-30.0, 30.0), fw_rng.randf_range(-40.0, 40.0))
		fw_sparks.append({"p": from, "v": Vector2(fw_rng.randf_range(-70.0, 70.0), -fw_rng.randf_range(150.0, 280.0)),
			"age": 0.0, "life": fw_rng.randf_range(0.9, 1.5), "col": col.lerp(Color.WHITE, 0.3), "col2": col,
			"drag": 1.3, "g": 260.0, "streak": 0.045, "kind": "fountain", "w": fw_rng.randf() * TAU})


## Draws the fireworks (added light): lantern glints, flashes, then each star as a short streak along its
## flight, white-hot at first and settling into its colour (some changing colour late), fading at the end.
func _fw_draw() -> void:
	var ci := cele_fx
	var glow: Texture2D = Game.glow_tex
	# Lantern glints: a quick four-point star that opens and fades.
	for gl in fw_glints:
		var age := clock - float(gl["t0"])
		if age < 0.0 or age > 0.7:
			continue
		var u := age / 0.7
		var a := minf(u / 0.12, 1.0) * (1.0 - smoothstep(0.35, 1.0, u))  # a quick rise, then a fade (no jump)
		# Soft, tapering rays of light (stretched glow, no hard lines), uneven and turning slowly as they fade.
		var arm := 30.0 * (0.6 + 0.6 * sin(PI * u * 0.5))
		var p: Vector2 = gl["p"]
		var c: Color = Color(gl["c"]).lerp(Color.WHITE, 0.45)
		for ray in gl["rays"]:
			var ang := float(ray[0]) + float(gl["spin"]) * u
			var reach := arm * float(ray[1])  # from the lantern out to the ray's soft tip
			ci.draw_set_transform(p + Vector2.from_angle(ang) * reach * 0.5, ang, Vector2(reach * 0.55 / 16.0, 0.16))
			ci.draw_texture_rect(glow, Rect2(-16, -16, 32, 32), false, Color(c, 0.75 * a))
		ci.draw_set_transform(Vector2.ZERO)
		ci.draw_texture_rect(glow, Rect2(p - Vector2(18, 18), Vector2(36, 36)), false, Color(c, 0.65 * a))
	for f in fw_flashes:
		var age := clock - float(f["t0"])
		if age < 0.0:
			continue
		var a := pow(1.0 - age / float(f["len"]), 2.0)
		var r := float(f["s"]) * (0.6 + age * 1.5)
		ci.draw_texture_rect(glow, Rect2(Vector2(f["p"]) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(f["c"], 0.6 * a))
		if float(f["s"]) > 40.0:
			var sky := 420.0
			ci.draw_texture_rect(glow, Rect2(Vector2(f["p"]) - Vector2(sky, sky), Vector2(sky, sky) * 2.0), false, Color(f["c"], 0.08 * a))
	for sp in fw_sparks:
		var age := float(sp["age"])
		var u := age / float(sp["life"])
		var a := 1.0 - smoothstep(0.55, 1.0, u)
		var w := float(sp["w"])
		if sp["kind"] == "glitter" and u > 0.35:
			a *= 0.25 + 0.75 * float(sin(clock * 31.0 + w * 5.0) > 0.1)
		elif u > 0.6:
			a *= 0.8 + 0.2 * sin(clock * 37.0 + w)
		var c: Color = Color(1.0, 0.97, 0.9).lerp(sp["col"], clampf(age / 0.22, 0.0, 1.0)).lerp(sp["col2"], smoothstep(0.45, 0.8, u))
		var pos: Vector2 = sp["p"]
		if sp["kind"] == "ember":
			ci.draw_texture_rect(glow, Rect2(pos - Vector2(3, 3), Vector2(6, 6)), false, Color(c, 0.8 * a))
			continue
		var tail: Vector2 = pos - Vector2(sp["v"]) * float(sp["streak"])
		ci.draw_line(tail, pos, Color(c, a), lerpf(3.0, 1.4, u), true)
		if u < 0.4:
			ci.draw_texture_rect(glow, Rect2(pos - Vector2(9, 9), Vector2(18, 18)), false, Color(c, 0.4 * a))


## Fireflies round each lake's shore, for the chapter's night.
func _make_shore_flies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in Game.lake_count():
		for k in 9:
			var a := rng.randf() * TAU
			shore_flies.append({"home": SPOTS[i] + off + Vector2.from_angle(a) * rng.randf_range(70.0, 135.0),
				"ph": rng.randf(), "per": rng.randf_range(2.4, 4.6), "sx": rng.randf_range(0.18, 0.4), "sy": rng.randf_range(0.15, 0.35)})


## Each lake shows the thing it brings, drawn small into its picture (in the lake's own coordinates), locked
## or open: ducks paddling in a line, a swan gliding, reeds swaying at the shore, twin lights pulsing
## together. It fades while a lake is in focus and while the camera dives in or out.
func _draw_teaser(n: Node2D, i: int, th: Dictionary, a: float) -> void:
	if a <= 0.01:
		return
	var lake: Dictionary = Game.lakes[i]
	var pal: Dictionary = lake["pal"]
	var path := _teaser_path(th)
	var pairs := _pairs(lake)
	if lake.has("swan"):
		if lake.has("reeds") and not (lake["reeds"] as Array).is_empty():
			_teaser_reeds(n, th, Color(pal["reed"]), a)  # Reed Bend: its reeds (its swans are met at Stones)
			return
		var sp: Array = _path_at(path, fmod(clock * 22.0, _path_len(path)))
		_teaser_swan(n, sp[0], sp[1], a)
	elif pairs.size() >= 2:
		for pr in pairs:
			# Twin lanterns: each pair glows and fades together, in step.
			var pulse := 0.5 + 0.5 * sin(clock * 2.2 + float(pr[2]) * 1.7)
			for q in [pr[0], pr[1]]:
				var r := 70.0 + 20.0 * pulse
				n.draw_texture_rect(Game.glow_tex, Rect2(Vector2(q) - Vector2(r, r), Vector2(r, r) * 2.0), false,
					Color(pal["light"], (0.25 + 0.55 * pulse) * a))
	elif int(lake.get("ducks", 0)) >= 2:
		var total := _path_len(path)
		var head := fmod(clock * 16.0, total)
		for k in 4:
			var dp: Array = _path_at(path, fposmod(head - (k * 26.0 + (8.0 if k > 0 else 0.0)) * TEASE_K, total))
			_teaser_duck(n, dp[0], dp[1], k == 0, a)


## A loop round the lake's inside for things to travel along: its deep water, or the middle if there's
## none deep enough.
func _teaser_path(th: Dictionary) -> PackedVector2Array:
	for key in ["deep", "mid"]:
		var best := PackedVector2Array()
		for p in th[key]:
			if p.size() > best.size():
				best = p
		if best.size() > 8:
			return best
	return th["water"]


func _path_len(poly: PackedVector2Array) -> float:
	var total := 0.0
	for k in poly.size():
		total += poly[k].distance_to(poly[(k + 1) % poly.size()])
	return maxf(total, 1.0)


## The point s along a closed path, and the way along it there.
func _path_at(poly: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		var seg := a.distance_to(b)
		if acc + seg >= s:
			return [a.lerp(b, (s - acc) / maxf(seg, 0.001)), (b - a).angle()]
		acc += seg
	return [poly[0], 0.0]


func _pairs(lake: Dictionary) -> Array:
	var by := {}
	for l in lake["lanterns"]:
		if (l as Array).size() > 2 and int(l[2]) != 0:
			if not by.has(int(l[2])):
				by[int(l[2])] = []
			by[int(l[2])].append(Vector2(l[0], l[1]))
	var out: Array = []
	for key in by:
		if (by[key] as Array).size() == 2:
			out.append([by[key][0], by[key][1], key])
	return out


func _teaser_swan(n: Node2D, p: Vector2, dir: float, a: float) -> void:
	var f := Vector2.from_angle(dir)
	var s := f.orthogonal()
	for side in [-1.0, 1.0]:
		n.draw_line(p - f * 12.0 * TEASE_K, p - f * 46.0 * TEASE_K + s * side * 16.0 * TEASE_K, Color(1, 1, 1, 0.22 * a), 3.0 * TEASE_K, true)  # her wake
	# The real swan (the same 3D model as on the lakes), turned to where she swims, with her shadow.
	if not is_instance_valid(_tease_swan):
		return
	_tease_seen = clock
	_tease_swan.set_pose(dir)
	_tease_swan.play("Idle", 0.8)
	var sc: float = 32.0 * TEASE_K * Swan3D.VIEW / float(_tease_swan.render_px)
	var tex := _tease_swan.get_texture()
	var anchor: Vector2 = _tease_swan.anchor()
	n.draw_set_transform_matrix(_thumb_xf * Transform2D(0.0, Vector2.ONE * sc, 0.0, p + Vector2(-5, 7) * TEASE_K))
	n.draw_texture(tex, -anchor, Color(0.04, 0.07, 0.08, 0.3 * a))
	n.draw_set_transform_matrix(_thumb_xf * Transform2D(0.0, Vector2.ONE * sc, 0.0, p))
	n.draw_texture(tex, -anchor, Color(1, 1, 1, a))
	n.draw_set_transform_matrix(_thumb_xf)


func _teaser_duck(n: Node2D, p: Vector2, dir: float, hen: bool, a: float) -> void:
	n.draw_set_transform_matrix(_thumb_xf * Transform2D(dir, Vector2.ONE * TEASE_K, 0.0, p))
	var k := 1.0 if hen else 0.55
	n.draw_line(Vector2(-14, 0) * k, Vector2(-48, -16) * k, Color(1, 1, 1, 0.22 * a), 3.0, true)
	n.draw_line(Vector2(-14, 0) * k, Vector2(-48, 16) * k, Color(1, 1, 1, 0.22 * a), 3.0, true)
	_ellipse(n, Vector2.ZERO, Vector2(18, 10) * k, Color("8a6a48") if hen else Color("c8a46a"), a)
	n.draw_circle(Vector2(16, 0) * k, 7.0 * k, Color(Color("6e5236") if hen else Color("b08a50"), a))
	n.draw_set_transform_matrix(_thumb_xf)


func _teaser_reeds(n: Node2D, th: Dictionary, col: Color, a: float) -> void:
	var edge: PackedVector2Array = th["water"]
	var count := 7
	for t in count:
		var base := edge[int(edge.size() * (t + 0.3) / count) % edge.size()]
		var inward := (Vector2(LAKE_CENTER) - base).normalized()
		base += inward * 12.0
		for b in 5:
			var sway := sin(clock * 1.6 + t * 1.3 + b * 0.7) * 0.22
			var ang := inward.angle() + (b - 2) * 0.32 + sway  # leaning out over the water from the shallows
			var tip := base + Vector2.from_angle(ang) * (140.0 + 36.0 * (b % 2))
			n.draw_line(base, tip, Color(col, 0.9 * a), 14.0, true)
			n.draw_circle(tip, 11.0, Color(col.darkened(0.25), 0.85 * a))


func _ellipse(n: Node2D, c: Vector2, r: Vector2, col: Color, a := 1.0) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var t := TAU * k / 20.0
		pts.append(c + Vector2(cos(t) * r.x, sin(t) * r.y))
	n.draw_colored_polygon(pts, Color(col, col.a * a))


func _setting(key: String) -> bool:
	match key:
		"sound": return Game.sound_on
		"music": return Game.music_on
	return Game.vibration_on
