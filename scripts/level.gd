extends Node2D
## One lake: the boat, its wake, loop detection, lanterns, drawing and the in-level screens.

signal exit_requested
signal level_requested(index: int)

const DrawNode = preload("res://scripts/draw_node.gd")
const WaterShader = preload("res://scripts/water.gdshader")
const LandShader = preload("res://scripts/land.gdshader")

const SPEED := 150.0
const REED_SPEED := 76.0
const TURN_RATE := 2.5
const WAKE_LIFE := 9.0
const CUT_FADE := 1.5
const WAKE_STEP := 7.0
const BOAT_RADIUS := 12.0
const MIN_LOOP_AREA := 2600.0
const NOTES := [1.0, 1.125, 1.25, 1.5, 1.6667, 2.0, 2.25, 2.5]
const HULL := [Vector2(19, 0), Vector2(9, -7.5), Vector2(-13, -7.5), Vector2(-16, -4.5),
	Vector2(-16, 4.5), Vector2(-13, 7.5), Vector2(9, 7.5)]
const TURN_EASE := 0.2
const BOOST_COUNT := 3
const BOOST_WINDOW := 7.0
const BOOST_TIME := 4.5
const BOOST_MULT := 1.4
const CHAIN_WINDOW := 4.5
const CHAIN_BONUS := 3.0
const FADE_TIME := 28.0
const DRIFT := Vector2(18, 12)
const LANTERN_SOFT := 30.0  # the boat starts being eased away from a lantern here
const LANTERN_HARD := 21.0  # and stops here: the hull just touching the lantern
const DAY_BONUS := 0.25  # extra daylight from the ad, as a share of the lake's whole day
const MAX_REVIVES := 2  # per try, for each kind of ad offer
const CRASH_LINES := {
	"rock": ["The stones were closer than they looked.", "A soft knock on the rocks.\nThe lanterns will wait.",
		"Even herons misjudge the stones.", "Bump. The lake forgives you."],
	"shore": ["The shore came up to meet you.", "Your bow found the sand.\nEasy does it.",
		"You reached the edge of the lake.", "Beached, but only a little."],
}

var lake_index := 0
var lake: Dictionary
var pal: Dictionary

# Geometry
var water := PackedVector2Array()
var inner := PackedVector2Array()
var sand_polys: Array = []
var mid_polys: Array = []
var deep_polys: Array = []
var rocks: Array = []
var reeds: Array = []
var reed_mats: Array = []
var gv := PackedVector2Array()
var gu := PackedVector2Array()
var gc := PackedColorArray()
var geo_static := false
var trees: Array = []
var lanterns: Array = []
var jetty: Array = []

# State
var state := "ready"
var clock := 0.0
var elapsed := 0.0
var dusk := 0.0
var finished_dusk := 0.0
var boat_pos := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var touches := {}
var wp := PackedVector2Array()
var wt := PackedFloat32Array()
var wc := PackedFloat32Array()  # when a duck cut this point (huge = never)
var loop_base := 0
var loops_used := 0
var flashes: Array = []
var ripples: Array = []
var motes: Array = []
var events: Array = []
var ripple_timer := 0.0
var bump_cool := 0.0
var end_timer := 0.0
var hint_alpha := 1.0
var turn_vel := 0.0
var move_dir := 0.0
var parts: Array = []
var spray_t := 0.0
var boost_until := -10.0
var light_times: Array = []
var chain := 0
var last_loop_t := -10.0
var ducks: Array = []
var splashes: Array = []
var floaters: Array = []
var duck_timer := 6.0
var fish_timer := 3.0
var const_t := -1.0
var crash_kind := ""
var crash_pos := Vector2.ZERO
var duration := 30.0  # seconds of daylight, from Game.lake_duration
var run_time := 0.0
var counted := false
var days_used := 0  # extra daylight taken this try
var patches_used := 0
var day_taken := false
var history: Array = []  # recent safe boat positions, for patching after a crash
var history_t := 0.0
var scrape_until := -10.0  # boat is rubbing the shore: slowed like in reeds
var scrape_fx := 0.0

# Nodes
var view_size := Vector2.ZERO
var off := Vector2.ZERO
var top_inset := 0.0
var world: Node2D
var detail_node: Node2D
var light_node: Node2D
var ui_draw: Node2D
var modulate_node: CanvasModulate
var ui_root: Control
var hint_label: Label
var go_label: Label
var overlay: Control


func _ready() -> void:
	lake = Game.lakes[lake_index]
	duration = Game.lake_duration(lake_index)
	pal = lake["pal"]
	view_size = get_viewport_rect().size
	off = ((view_size - Game.LAKE_SIZE) * 0.5).floor()
	top_inset = _safe_top()
	_build_geometry()
	_build_nodes()
	_build_ui()
	var s: Array = lake["start"]
	boat_pos = Vector2(s[0], s[1])
	heading = s[2]
	move_dir = heading
	Sfx.start_ambience(float(lake["pitch"]))


func _exit_tree() -> void:
	get_tree().paused = false


func _safe_top() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	return maxf(0.0, float(safe.position.y) * view_size.y / float(win.y))


# ---------------------------------------------------------------- setup

func _build_geometry() -> void:
	water = Game.water_poly(lake_index)
	inner = Game.offset_largest(water, -(BOAT_RADIUS + 2.0))
	sand_polys = Geometry2D.offset_polygon(water, 10.0, Geometry2D.JOIN_ROUND)
	mid_polys = Geometry2D.offset_polygon(water, -18.0, Geometry2D.JOIN_ROUND)
	deep_polys = Geometry2D.offset_polygon(water, -48.0, Geometry2D.JOIN_ROUND)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1301 * (lake_index + 3)

	for r in lake["rocks"]:
		var c := Vector2(r[0], r[1])
		var rad := float(r[2])
		var poly := PackedVector2Array()
		var count := 9
		for k in count:
			var a := TAU * float(k) / count + rng.randf_range(-0.2, 0.2)
			poly.append(c + Vector2.from_angle(a) * rad * rng.randf_range(0.82, 1.06))
		var hi := PackedVector2Array()
		for p in poly:
			hi.append(c + (p - c) * 0.6 + Vector2(-rad * 0.16, -rad * 0.2))
		rocks.append({"c": c, "r": rad, "poly": poly, "hi": hi, "phase": rng.randf() * TAU})

	for r in lake["reeds"]:
		var c := Vector2(r[0], r[1])
		var rad := float(r[2])
		var tufts: Array = []
		var count := int(rad * rad / 260.0)
		var tries := 0
		while tufts.size() < count and tries < count * 20:
			tries += 1
			var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (rad - 8.0)
			if not Geometry2D.is_point_in_polygon(p, inner):
				continue
			var crowded := false
			for t in tufts:
				if p.distance_to(t["p"]) < 15.0:
					crowded = true
					break
			if crowded:
				continue
			var blades: Array = []
			var nb := rng.randi_range(6, 9)
			var spin := rng.randf() * TAU
			for b in nb:
				blades.append([spin + TAU * b / nb + rng.randf_range(-0.25, 0.25), rng.randf_range(9.0, 17.0)])
			tufts.append({"p": p, "blades": blades, "ph": rng.randf() * TAU})
		reeds.append({"c": c, "r": rad, "tufts": tufts})

	var idx := 0
	for l in lake["lanterns"]:
		lanterns.append({"p": Vector2(l[0], l[1]), "home": Vector2(l[0], l[1]), "pair": int(l[2]), "lit": false,
			"lit_t": 1e9, "note": idx, "bob": rng.randf() * TAU, "reject_t": -10.0})
		idx += 1

	var j: Array = lake["jetty"]
	if j.size() == 4:
		jetty = [Vector2(j[0], j[1]), Vector2(j[2], j[3])]

	_place_trees(rng)

	for k in 30:
		motes.append({"p": Vector2(rng.randf_range(-off.x, view_size.x - off.x),
			rng.randf_range(-off.y, view_size.y - off.y)), "ph": rng.randf() * TAU,
			"v": Vector2(rng.randf_range(-9, 9), rng.randf_range(4, 12)), "rot": rng.randf() * TAU})


func _place_trees(rng: RandomNumberGenerator) -> void:
	var grown := Game.offset_largest(water, 44.0)
	var lo := -off - Vector2(30, 30)
	var hi := view_size - off + Vector2(30, 30)
	var tries := 0
	while trees.size() < 85 and tries < 2500:
		tries += 1
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var r := rng.randf_range(13.0, 30.0)
		if Geometry2D.is_point_in_polygon(p, grown):
			continue
		if jetty.size() == 2:
			var cp := Geometry2D.get_closest_point_to_segment(p, jetty[0], jetty[1])
			if p.distance_to(cp) < r + 30.0:
				continue
		var ok := true
		for t in trees:
			if p.distance_to(t["p"]) < (r + float(t["r"])) * 0.62:
				ok = false
				break
		if not ok:
			continue
		var parts: Array = [[Vector2.ZERO, r]]
		for k in rng.randi_range(0, 2):
			parts.append([Vector2.from_angle(rng.randf() * TAU) * r * 0.55, r * rng.randf_range(0.5, 0.75)])
		trees.append({"p": p, "r": r, "parts": parts})
	trees.sort_custom(func(a, b): return a["p"].y < b["p"].y)


func _build_nodes() -> void:
	world = Node2D.new()
	world.position = off
	add_child(world)

	var land := Polygon2D.new()
	land.polygon = PackedVector2Array([-off, Vector2(view_size.x - off.x, -off.y),
		view_size - off, Vector2(-off.x, view_size.y - off.y)])
	var lm := ShaderMaterial.new()
	lm.shader = LandShader
	lm.set_shader_parameter("base", pal["land"])
	lm.set_shader_parameter("dark", pal["land_dark"])
	land.material = lm
	world.add_child(land)

	var water_node := DrawNode.new()
	water_node.draw_fn = _draw_water
	world.add_child(water_node)

	var ripple_poly := Polygon2D.new()
	ripple_poly.polygon = water
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	wm.set_shader_parameter("tint", Color.WHITE)
	wm.set_shader_parameter("strength", 0.06 if lake_index == 4 else 0.09)
	ripple_poly.material = wm
	world.add_child(ripple_poly)

	_build_reeds(world)

	detail_node = DrawNode.new()
	detail_node.draw_fn = _draw_details
	world.add_child(detail_node)

	var tree_node := DrawNode.new()
	tree_node.draw_fn = _draw_trees
	world.add_child(tree_node)

	modulate_node = CanvasModulate.new()
	add_child(modulate_node)

	var light_layer := CanvasLayer.new()
	light_layer.layer = 1
	light_layer.offset = off
	add_child(light_layer)
	light_node = DrawNode.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light_node.material = add
	light_node.draw_fn = _draw_light
	light_layer.add_child(light_node)


func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.theme = Game.ui_theme
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.size = view_size
	ui_layer.add_child(ui_root)

	ui_draw = DrawNode.new()
	ui_draw.draw_fn = _draw_ui
	ui_root.add_child(ui_draw)

	var name_label := Label.new()
	name_label.text = String(lake["name"])
	name_label.position = Vector2(36, top_inset + 30)
	name_label.add_theme_font_size_override("font_size", 30)
	ui_root.add_child(name_label)

	var pause := Button.new()
	pause.icon = Game.icon("pause")
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.add_theme_constant_override("icon_max_width", 30)
	pause.custom_minimum_size = Vector2(84, 84)
	pause.position = Vector2(view_size.x - 120, top_inset + 26)
	pause.add_theme_font_size_override("font_size", 26)
	pause.pressed.connect(_pause)
	ui_root.add_child(pause)

	hint_label = Label.new()
	hint_label.text = String(lake["hint"])
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(0, top_inset + 170)
	hint_label.size = Vector2(view_size.x, 120)
	hint_label.add_theme_font_size_override("font_size", 27)
	ui_root.add_child(hint_label)

	go_label = Label.new()
	go_label.text = "Touch to set off"
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.position = Vector2(0, top_inset + 260)
	go_label.size = Vector2(view_size.x, 50)
	go_label.add_theme_font_size_override("font_size", 23)
	ui_root.add_child(go_label)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	clock += delta
	bump_cool -= delta
	match state:
		"ready":
			if _turn_input() != 0 or not touches.is_empty():
				state = "play"
				Sfx.tap()
				if not counted:
					counted = true
					Game.stat_add(lake_index, "tries")
		"play":
			elapsed += delta
			dusk = clampf(elapsed / duration, 0.0, 1.0)
			run_time += delta
			_move_boat(delta, true)
			history_t -= delta
			if history_t <= 0.0 and state == "play":
				history_t = 0.2
				history.append(boat_pos)
				if history.size() > 12:
					history.remove_at(0)
			if dusk >= 1.0 and state == "play":
				if days_used < MAX_REVIVES and _lit_count() < lanterns.size():
					_offer_daylight()
				else:
					_end("dark")
		"complete", "dark":
			_move_boat(delta, false)
			end_timer -= delta
			if end_timer <= 0.0:
				state = "results"
				_show_results()
		"crashed":
			end_timer -= delta
			heading += delta * 0.8 * maxf(0.0, end_timer)
			if end_timer <= 0.0:
				state = "results"
				_show_crash()
		"results":
			_move_boat(delta, false)

	_run_events()
	_update_effects(delta)
	if state in ["ready", "play"]:
		Sfx.set_mood(dusk, speed / SPEED, _in_reeds(boat_pos))

	var target_hint := 1.0 if state == "ready" else 0.0
	hint_alpha = move_toward(hint_alpha, target_hint, delta * 1.6)
	hint_label.modulate.a = hint_alpha
	go_label.modulate.a = hint_alpha * (0.55 + 0.45 * sin(clock * 3.0))

	modulate_node.color = Color.WHITE.lerp(pal["night"], smoothstep(0.0, 1.0, dusk) * 0.92)
	detail_node.queue_redraw()
	for m in reed_mats:
		m.set_shader_parameter("time", clock)
	light_node.queue_redraw()
	ui_draw.queue_redraw()


func _turn_input() -> int:
	var left := Input.is_action_pressed("ui_left")
	var right := Input.is_action_pressed("ui_right")
	for x in touches.values():
		if float(x) < view_size.x * 0.5:
			left = true
		else:
			right = true
	return int(right) - int(left)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position.x
		else:
			touches.erase(event.index)
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position.x


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if overlay != null and is_instance_valid(overlay):
			if state == "results":
				exit_requested.emit()
			else:
				_resume()
		else:
			_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == "play" and overlay == null:
			_pause()


func _move_boat(delta: float, steering: bool) -> void:
	var want := float(_turn_input()) * TURN_RATE if steering else 0.0
	turn_vel = move_toward(turn_vel, want, TURN_RATE / TURN_EASE * delta)
	heading += turn_vel * delta
	var target := 0.0
	if state == "play":
		target = REED_SPEED if _in_reeds(boat_pos) or clock < scrape_until else SPEED
		if clock < boost_until:
			target *= BOOST_MULT
	var accel := 140.0 if state == "play" else 45.0
	speed = move_toward(speed, target, accel * delta)
	if speed < 0.5:
		return

	move_dir = lerp_angle(move_dir, heading, 1.0 - exp(-4.5 * delta))
	if state == "play":
		var near := _shore_info(boat_pos)
		if float(near[0]) < 7.0:
			_scrape(near)
	var step := speed * delta
	var np := boat_pos + Vector2.from_angle(move_dir) * step
	if not _free(np):
		var moved := false
		var hit_rock := _hits_rock(np)
		var shore: Array = [] if hit_rock else _shore_info(boat_pos)
		# Head-on into the shore breaks the boat; a glancing touch only slows it.
		var head_on := false
		if not hit_rock:
			head_on = Vector2.from_angle(move_dir).dot(-Vector2(shore[1])) > 0.7 and speed > 70.0
		var pref := 1.0 if _turn_input() >= 0 else -1.0
		var bend := 0
		for k in range(1, 18):
			for s in [pref, -pref]:
				var a: float = heading + s * k * 0.14
				var cand := boat_pos + Vector2.from_angle(a) * step
				if _free(cand):
					bend = k
					heading = a
					move_dir = a
					np = cand
					moved = true
					break
			if moved:
				break
		if state == "play" and Game.dev_on("crash") and (hit_rock or head_on or not moved):
			_crash("rock" if hit_rock else "shore")
			return
		if not moved:
			heading += PI * 0.5
			return
		if hit_rock:
			speed *= 0.86
		else:
			_scrape(shore)
		if bump_cool <= 0.0:
			bump_cool = 0.7
			Sfx.bump()
			ripples.append({"p": np + Vector2.from_angle(heading) * 14.0, "t": clock,
				"life": 1.0, "r0": 4.0, "r1": 22.0, "light": false})
	np = _lantern_push(np, delta)
	boat_pos = np

	var stern := boat_pos - Vector2.from_angle(heading) * 14.0
	if wp.is_empty() or wp[wp.size() - 1].distance_to(stern) >= WAKE_STEP:
		_add_wake_point(stern, state == "play")

	ripple_timer -= delta
	if ripple_timer <= 0.0:
		ripple_timer = 0.38
		ripples.append({"p": stern, "t": clock, "life": 1.5, "r0": 3.0, "r1": 24.0, "light": false})

	# Spray from the bow, foam behind the stern, a bright trail while boosting.
	spray_t -= delta
	var boosting := clock < boost_until
	if spray_t <= 0.0 and speed > 40.0:
		spray_t = 0.03 if boosting else 0.055
		var fwd := Vector2.from_angle(move_dir)
		var side := fwd.orthogonal()
		var turn := absf(turn_vel) / TURN_RATE
		for s2 in [-1.0, 1.0]:
			_part(boat_pos + fwd * 15.0 + side * s2 * 5.0, side * s2 * randf_range(25, 55) * (1.0 + turn) - fwd * randf_range(5, 30),
				randf_range(0.3, 0.55), randf_range(1.4, 2.6) * (1.3 if boosting else 1.0), Color(1, 1, 1, 0.9), false)
		_part(stern + side * randf_range(-4, 4), -fwd * randf_range(4, 14) + side * randf_range(-6, 6), randf_range(0.9, 1.6), randf_range(1.2, 2.4), Color(1, 1, 1, 0.55), false)
		if boosting:
			for k in 2:
				_part(stern + side * randf_range(-3, 3), -fwd * randf_range(40, 90) + side * randf_range(-25, 25), randf_range(0.4, 0.7), randf_range(2.0, 3.6), pal["light"], true)


func _free(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, inner):
		return false
	for r in rocks:
		if p.distance_to(r["c"]) < float(r["r"]) + BOAT_RADIUS:
			return false
	return true


## [distance to the shore line, normal pointing into the water, closest shore point]
## Lanterns float on the water; the boat is eased around them instead of passing over them.
func _lantern_push(np: Vector2, delta: float) -> Vector2:
	for l in lanterns:
		var lp: Vector2 = l["p"]
		var d := np - lp
		var dist := d.length()
		if dist >= LANTERN_SOFT or dist < 0.001:
			continue
		var away := d / dist
		var pen := (LANTERN_SOFT - dist) / (LANTERN_SOFT - LANTERN_HARD)
		# Steer the travel direction toward the side of the lantern the boat is already on.
		var fwd := Vector2.from_angle(move_dir)
		var tangent := away.orthogonal()
		if tangent.dot(fwd) < 0.0:
			tangent = -tangent
		var turn := clampf(pen, 0.0, 1.0) * 6.0 * delta
		move_dir = lerp_angle(move_dir, tangent.angle(), turn)
		heading = lerp_angle(heading, tangent.angle(), turn)
		var cand := np + away * minf(pen * pen, 1.0) * 220.0 * delta
		if cand.distance_to(lp) < LANTERN_HARD:
			cand = lp + away * LANTERN_HARD
		if _free(cand):
			np = cand
	return np


func _shore_info(p: Vector2) -> Array:
	var best := INF
	var cp := p
	var seg := 0
	var n := inner.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, inner[i], inner[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			cp = q
			seg = i
	var nrm := (inner[(seg + 1) % n] - inner[seg]).normalized().orthogonal()
	if not Geometry2D.is_point_in_polygon(cp + nrm * 3.0, inner):
		nrm = -nrm
	return [sqrt(best), nrm, cp]


func _scrape(shore: Array) -> void:
	scrape_until = clock + 0.35
	if clock > scrape_fx:
		scrape_fx = clock + 0.07
		var cp: Vector2 = shore[2]
		var nrm: Vector2 = shore[1]
		_part(cp, nrm * randf_range(15, 40) + nrm.orthogonal() * randf_range(-20, 20), randf_range(0.4, 0.8), randf_range(1.4, 2.4), Color(pal["sand"], 0.9), false)


func _hits_rock(p: Vector2) -> bool:
	for r in rocks:
		if p.distance_to(r["c"]) < float(r["r"]) + BOAT_RADIUS:
			return true
	return false


func _crash(kind: String) -> void:
	state = "crashed"
	crash_kind = kind
	crash_pos = boat_pos
	finished_dusk = dusk
	speed = 0.0
	end_timer = 1.4
	touches.clear()
	Sfx.crash()
	Game.vibrate(90)
	for k in 3:
		ripples.append({"p": boat_pos, "t": clock + k * 0.15, "life": 1.6, "r0": 6.0, "r1": 40.0 + k * 14.0, "light": false})


# ---------------------------------------------------------------- reeds
# Reeds are built once as four meshes (beds, blades, tips, bases); a shader sways each blade
# around its base, so a reed patch costs a few draw calls instead of thousands per frame.

const REED_SHADER_CODE := """shader_type canvas_item;
uniform vec4 tint : source_color;
uniform float time;
void vertex() {
	float a = 0.18 * sin(time * 1.2 + COLOR.r * TAU);
	vec2 d = VERTEX - UV;
	VERTEX = UV + vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
	COLOR = vec4(tint.rgb, tint.a * COLOR.g);
}
"""


func _build_reeds(world: Node) -> void:
	if reeds.is_empty():
		return
	var shader := Shader.new()
	shader.code = REED_SHADER_CODE
	var bed: Color = pal["deep"].darkened(0.25)
	bed.a = 0.35
	geo_static = true
	for patch in reeds:
		for t in patch["tufts"]:
			_geo_circle(t["p"] + Vector2(3, 4), 11.0, Vector2.ZERO, 0.0)
	_reed_mesh(world, shader, bed)
	geo_static = false
	for patch in reeds:
		for t in patch["tufts"]:
			var base: Vector2 = t["p"]
			for b in t["blades"]:
				_geo_blade(base, base + Vector2.from_angle(float(b[0])) * float(b[1]), float(t["ph"]) / TAU)
	_reed_mesh(world, shader, pal["reed"])
	for patch in reeds:
		for t in patch["tufts"]:
			var base: Vector2 = t["p"]
			for b in t["blades"]:
				_geo_circle(base + Vector2.from_angle(float(b[0])) * float(b[1]), 1.7, base, float(t["ph"]) / TAU)
	_reed_mesh(world, shader, pal["reed"].lightened(0.3))
	geo_static = true
	for patch in reeds:
		for t in patch["tufts"]:
			_geo_circle(t["p"], 2.6, Vector2.ZERO, 0.0)
	_reed_mesh(world, shader, pal["reed"].darkened(0.2))
	geo_static = false


func _gvert(p: Vector2, pivot: Vector2, ph: float, a: float) -> void:
	gv.append(p)
	gu.append(p if geo_static else pivot)
	gc.append(Color(ph, a, 0.0, 1.0))


## A strip from inner edge (alpha 1) to outer edge (alpha 0): the soft antialiased rim.
func _geo_feather(i0: Vector2, i1: Vector2, o0: Vector2, o1: Vector2, pivot: Vector2, ph: float) -> void:
	_gvert(i0, pivot, ph, 1.0)
	_gvert(i1, pivot, ph, 1.0)
	_gvert(o0, pivot, ph, 0.0)
	_gvert(i1, pivot, ph, 1.0)
	_gvert(o1, pivot, ph, 0.0)
	_gvert(o0, pivot, ph, 0.0)


func _geo_circle(c: Vector2, r: float, pivot: Vector2, ph: float) -> void:
	var seg := 10 if r > 4.0 else 7
	for i in seg:
		var d0 := Vector2.from_angle(TAU * i / seg)
		var d1 := Vector2.from_angle(TAU * (i + 1) / seg)
		_gvert(c, pivot, ph, 1.0)
		_gvert(c + d0 * r, pivot, ph, 1.0)
		_gvert(c + d1 * r, pivot, ph, 1.0)
		_geo_feather(c + d0 * r, c + d1 * r, c + d0 * (r + 0.7), c + d1 * (r + 0.7), pivot, ph)


func _geo_blade(b: Vector2, t: Vector2, ph: float) -> void:
	var nrm := (t - b).orthogonal().normalized()
	var h := nrm * 1.1
	var f := nrm * 1.8
	_gvert(b + h, b, ph, 1.0)
	_gvert(t + h, b, ph, 1.0)
	_gvert(t - h, b, ph, 1.0)
	_gvert(b + h, b, ph, 1.0)
	_gvert(t - h, b, ph, 1.0)
	_gvert(b - h, b, ph, 1.0)
	_geo_feather(b + h, t + h, b + f, t + f, b, ph)
	_geo_feather(b - h, t - h, b - f, t - f, b, ph)


func _reed_mesh(world: Node, shader: Shader, tint: Color) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = gv
	arr[Mesh.ARRAY_TEX_UV] = gu
	arr[Mesh.ARRAY_COLOR] = gc
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance2D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("time", clock)
	mi.material = m
	world.add_child(mi)
	reed_mats.append(m)
	gv = PackedVector2Array()
	gu = PackedVector2Array()
	gc = PackedColorArray()


func _in_reeds(p: Vector2) -> bool:
	for r in reeds:
		if p.distance_to(r["c"]) < float(r["r"]):
			return true
	return false


# ---------------------------------------------------------------- wake and loops

func _add_wake_point(p: Vector2, detect: bool) -> void:
	var n := wp.size()
	if detect and n >= 5:
		var a := wp[n - 1]
		var hit_j := -1
		var hit_x := Vector2.ZERO
		for j in range(loop_base, n - 4):
			var x = Geometry2D.segment_intersects_segment(wp[j], wp[j + 1], a, p)
			if x != null:
				hit_j = j
				hit_x = x
		if hit_j >= 0:
			var poly := PackedVector2Array([hit_x])
			for k in range(hit_j + 1, n):
				poly.append(wp[k])
			loop_base = n
			_on_loop(poly)
	wp.append(p)
	wt.append(clock)
	wc.append(1e9)


func _prune_wake() -> void:
	while wt.size() > 0 and (clock - wt[0] > WAKE_LIFE or clock - wc[0] > CUT_FADE):
		wp.remove_at(0)
		wt.remove_at(0)
		wc.remove_at(0)
		loop_base = maxi(0, loop_base - 1)


func _on_loop(poly: PackedVector2Array) -> void:
	if absf(Game.poly_area(poly)) < MIN_LOOP_AREA:
		return
	var inside: Array = []
	for i in lanterns.size():
		if not lanterns[i]["lit"] and Geometry2D.is_point_in_polygon(lanterns[i]["p"], poly):
			inside.append(i)
	var accepted: Array = []
	var rejected := false
	for i in inside:
		var pair: int = lanterns[i]["pair"]
		if pair == 0:
			accepted.append(i)
			continue
		var partner := _partner(i)
		if partner in inside or bool(lanterns[partner]["lit"]):
			accepted.append(i)
		else:
			lanterns[i]["reject_t"] = clock
			rejected = true

	var tris := Geometry2D.triangulate_polygon(poly)
	flashes.append({"poly": poly, "tris": tris, "t": clock, "s": 1.0 if accepted.size() > 0 else 0.3})
	for k in 14:
		var vp := poly[randi() % poly.size()]
		_part(vp, Vector2(randf_range(-20, 20), randf_range(-30, -5)), randf_range(0.4, 0.8), randf_range(1.2, 2.2), pal["light"], true)

	if accepted.is_empty():
		if rejected:
			Sfx.reject()
		else:
			Sfx.loop_closed(0.45)
		return

	loops_used += 1
	Sfx.loop_closed(1.0)
	if Game.dev_on("chains"):
		chain = chain + 1 if clock - last_loop_t <= CHAIN_WINDOW else 1
		if chain >= 2:
			elapsed = maxf(0.0, elapsed - CHAIN_BONUS)
			_float("Chain x%d  ·  the sun waits" % chain, boat_pos)
			Sfx.chain(float(lake["pitch"]), chain)
	if accepted.size() >= 3:
		_float("Bright loop", boat_pos + Vector2(0, 34))
	last_loop_t = clock
	if Game.dev_on("boost"):
		for k in accepted.size():
			light_times.append(clock)
		light_times = light_times.filter(func(t): return clock - float(t) <= BOOST_WINDOW)
		if light_times.size() >= BOOST_COUNT and clock > boost_until:
			boost_until = clock + BOOST_TIME
			light_times.clear()
			_float("Swift water", boat_pos - Vector2(0, 40))
			Sfx.boost(float(lake["pitch"]))
	accepted.sort_custom(func(a, b): return lanterns[a]["p"].x < lanterns[b]["p"].x)
	var last_t := clock
	for k in accepted.size():
		var i: int = accepted[k]
		var at := clock + 0.15 + k * 0.13
		lanterns[i]["lit"] = true
		lanterns[i]["lit_t"] = at
		events.append({"at": at, "kind": "light", "i": i})
		last_t = at

	if _lit_count() == lanterns.size():
		events.append({"at": last_t + 0.55, "kind": "chord"})
		var wait := last_t - clock + 2.8
		if Game.dev_on("constellations"):
			events.append({"at": last_t + 0.7, "kind": "constellation"})
			wait += 2.6
		_end("complete", wait)


func _partner(i: int) -> int:
	for k in lanterns.size():
		if k != i and lanterns[k]["pair"] == lanterns[i]["pair"]:
			return k
	return i


func _lit_count() -> int:
	var c := 0
	for l in lanterns:
		if l["lit"]:
			c += 1
	return c


func _run_events() -> void:
	var keep: Array = []
	for e in events:
		if clock < float(e["at"]):
			keep.append(e)
			continue
		match String(e["kind"]):
			"light":
				var l: Dictionary = lanterns[e["i"]]
				Sfx.chime(NOTES[int(l["note"]) % NOTES.size()] * float(lake["pitch"]))
				Game.vibrate(22)
				ripples.append({"p": l["p"], "t": clock, "life": 1.8, "r0": 10.0, "r1": 90.0, "light": true})
				for k in 16:
					_part(l["p"], Vector2.from_angle(randf() * TAU) * randf_range(40, 120), randf_range(0.5, 1.1), randf_range(1.6, 3.2), pal["light"], true)
				Sfx.set_progress(float(_lit_count()) / lanterns.size())
			"chord":
				Sfx.chord(float(lake["pitch"]))
				Game.vibrate(60)
			"constellation":
				const_t = clock
	events = keep


func _end(kind: String, wait := 1.8) -> void:
	if state != "play":
		return
	state = kind
	finished_dusk = dusk
	end_timer = wait
	touches.clear()


func _update_effects(delta: float) -> void:
	_prune_wake()
	_update_parts(delta)
	var life := Game.dev_on("life")
	for l in lanterns:
		if life:
			var b := float(l["bob"])
			l["p"] = l["home"] + Vector2(sin(clock * 0.23 + b) * DRIFT.x, cos(clock * 0.19 + b * 1.3) * DRIFT.y)
		if state == "play" and Game.dev_on("fading") and l["lit"] and clock >= float(l["lit_t"]):
			if clock - float(l["lit_t"]) > FADE_TIME:
				l["lit"] = false
				l["lit_t"] = 1e9
				Sfx.fade_out()
				Sfx.set_progress(float(_lit_count()) / lanterns.size())
				ripples.append({"p": l["p"], "t": clock, "life": 1.2, "r0": 8.0, "r1": 30.0, "light": false})
	if life and state in ["ready", "play"]:
		duck_timer -= delta
		if duck_timer <= 0.0:
			duck_timer = randf_range(11.0, 18.0)
			_spawn_ducks()
		fish_timer -= delta
		if fish_timer <= 0.0:
			fish_timer = randf_range(2.5, 6.0)
			_spawn_fish()
	_update_ducks()
	var fk: Array = []
	for f in floaters:
		if clock - float(f["t"]) < 1.8:
			fk.append(f)
	floaters = fk
	var sk: Array = []
	for sp in splashes:
		if clock - float(sp["t"]) < 0.7:
			sk.append(sp)
	splashes = sk
	var keep: Array = []
	for r in ripples:
		if clock - float(r["t"]) < float(r["life"]):
			keep.append(r)
	ripples = keep
	keep = []
	for f in flashes:
		if clock - float(f["t"]) < 1.6:
			keep.append(f)
	flashes = keep
	var lo := -off - Vector2(20, 20)
	var hi := view_size - off + Vector2(20, 20)
	for m in motes:
		var p: Vector2 = m["p"]
		p += (m["v"] + Vector2(sin(clock * 0.7 + m["ph"]) * 8.0, 0.0)) * delta
		if p.y > hi.y:
			p.y = lo.y
		if p.x < lo.x:
			p.x = hi.x
		elif p.x > hi.x:
			p.x = lo.x
		m["p"] = p
		m["rot"] = float(m["rot"]) + delta * 0.8


func _part(p: Vector2, v: Vector2, life: float, size: float, col: Color, light: bool) -> void:
	if parts.size() > 260:
		return
	parts.append({"p": p, "v": v, "t": clock, "life": life, "s": size, "c": col, "l": light})


func _update_parts(delta: float) -> void:
	var keep: Array = []
	for q in parts:
		if clock - float(q["t"]) > float(q["life"]):
			continue
		q["p"] = Vector2(q["p"]) + Vector2(q["v"]) * delta
		q["v"] = Vector2(q["v"]) * exp(-3.0 * delta)
		keep.append(q)
	parts = keep


func _draw_parts(n: Node2D, light_pass: bool) -> void:
	var glow: Texture2D = Game.glow_tex
	for q in parts:
		if bool(q["l"]) != light_pass:
			continue
		var k := (clock - float(q["t"])) / float(q["life"])
		var c: Color = q["c"]
		var sz: float = float(q["s"]) * (1.0 - k * 0.6)
		if light_pass:
			var r := sz * 4.0
			n.draw_texture_rect(glow, Rect2(Vector2(q["p"]) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c, (1.0 - k) * 0.9))
		else:
			n.draw_circle(q["p"], sz, Color(c, c.a * (1.0 - k)), true, -1.0, true)


func _float(text: String, at: Vector2) -> void:
	floaters.append({"text": text, "p": at, "t": clock})


func _spawn_fish() -> void:
	for k in 12:
		var p := Vector2(randf_range(60, 660), randf_range(220, 1180))
		if Geometry2D.is_point_in_polygon(p, inner) and not _hits_rock(p) and p.distance_to(boat_pos) > 90.0:
			splashes.append({"p": p, "t": clock})
			ripples.append({"p": p, "t": clock, "life": 1.6, "r0": 3.0, "r1": 28.0, "light": false})
			ripples.append({"p": p, "t": clock + 0.25, "life": 1.4, "r0": 3.0, "r1": 18.0, "light": false})
			Sfx.plop()
			return


func _spawn_ducks() -> void:
	for attempt in 40:
		var a := Vector2(randf_range(60, 660), randf_range(220, 1180))
		var b := Vector2(randf_range(60, 660), randf_range(220, 1180))
		if a.distance_to(b) < 260.0:
			continue
		var ok := true
		for k in 21:
			var p := a.lerp(b, k / 20.0)
			if not Geometry2D.is_point_in_polygon(p, inner) or _hits_rock(p) or _in_reeds(p):
				ok = false
				break
		if not ok or Geometry2D.get_closest_point_to_segment(boat_pos, a, b).distance_to(boat_pos) < 70.0:
			continue
		ducks.append({"a": a, "b": b, "t0": clock, "dur": a.distance_to(b) / 34.0, "n": randi_range(1, 3), "rip": 0.0})
		return


func _duck_pos(d: Dictionary, back: float) -> Vector2:
	var a: Vector2 = d["a"]
	var b: Vector2 = d["b"]
	var k := clampf((clock - float(d["t0"])) / float(d["dur"]), 0.0, 1.0)
	return a.lerp(b, k) - (b - a).normalized() * back


func _update_ducks() -> void:
	var keep: Array = []
	for d in ducks:
		if clock - float(d["t0"]) > float(d["dur"]):
			continue
		if d.has("hit"):
			if clock - float(d["hit"]) < 1.4:
				keep.append(d)
			continue
		keep.append(d)
		var head := _duck_pos(d, 0.0)
		var struck := false
		for i in int(d["n"]):
			if state == "play" and _duck_pos(d, i * 20.0).distance_to(boat_pos) < 15.0:
				struck = true
		if struck:
			d["hit"] = clock
			d["hp"] = head
			d["hit_dir"] = (head - boat_pos).normalized()
			for k in 22:
				var fc := Color("f2ece0") if k % 3 != 0 else Color("8b7a62")
				_part(head + Vector2(randf_range(-8, 8), randf_range(-8, 8)), Vector2.from_angle(randf() * TAU) * randf_range(30, 110), randf_range(0.6, 1.3), randf_range(1.5, 3.0), fc, false)
			ripples.append({"p": head, "t": clock, "life": 1.4, "r0": 4.0, "r1": 34.0, "light": false})
			speed *= 0.9
			Sfx.quack()
			Game.vibrate(30)
			continue
		if clock - float(d["rip"]) > 0.6:
			d["rip"] = clock
			for i in int(d["n"]):
				ripples.append({"p": _duck_pos(d, 6.0 + i * 18.0), "t": clock, "life": 1.3, "r0": 3.0, "r1": 16.0, "light": false})
		# Ducks cut the wake: the part behind the cut can no longer close a loop and fades out over CUT_FADE.
		var cut := -1
		for i in wp.size():
			if wp[i].distance_to(head) < 13.0:
				cut = i
		if cut >= 0 and state == "play":
			loop_base = maxi(loop_base, cut + 1)
			for i in cut + 1:
				wc[i] = minf(wc[i], clock)
	ducks = keep


# ---------------------------------------------------------------- drawing

func _draw_water(n: Node2D) -> void:
	for p in sand_polys:
		_aa_poly(n, p, pal["sand"])
	_aa_poly(n, water, pal["shallow"])
	for p in mid_polys:
		_aa_poly(n, p, pal["mid"])
	for p in deep_polys:
		_aa_poly(n, p, pal["deep"])
	var edge := water.duplicate()
	edge.append(water[0])
	var wet: Color = pal["sand"].lightened(0.2)
	wet.a = 0.55
	n.draw_polyline(edge, wet, 2.0, true)


## Filled polygon with an anti-aliased rim (the mobile renderer has no 2D MSAA).
func _aa_poly(n: Node2D, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() < 3:
		return
	n.draw_colored_polygon(poly, col)
	var rim := poly.duplicate()
	rim.append(poly[0])
	n.draw_polyline(rim, col, 1.4, true)


func _draw_trees(n: Node2D) -> void:
	var shadow: Color = pal["shadow"]
	shadow.a = 0.5
	for t in trees:
		for part in t["parts"]:
			n.draw_circle(t["p"] + part[0] + Vector2(8, 10), part[1], shadow, true, -1.0, true)
	for t in trees:
		for part in t["parts"]:
			n.draw_circle(t["p"] + part[0], part[1], pal["tree"], true, -1.0, true)
		for part in t["parts"]:
			var r: float = part[1]
			n.draw_circle(t["p"] + part[0] + Vector2(-r * 0.22, -r * 0.24), r * 0.62, pal["tree_hi"], true, -1.0, true)


func _draw_details(n: Node2D) -> void:
	var shade: Color = pal["deep"].darkened(0.45)
	shade.a = 0.55

	if jetty.size() == 2:
		var a: Vector2 = jetty[0]
		var b: Vector2 = jetty[1]
		n.draw_line(a + Vector2(5, 7), b + Vector2(5, 7), shade, 24.0)
		n.draw_line(a, b, pal["wood"], 22.0)
		var dir := (b - a).normalized()
		var side := dir.orthogonal() * 11.0
		var len := a.distance_to(b)
		var d := 6.0
		while d < len:
			var p := a + dir * d
			n.draw_line(p - side, p + side, pal["wood"].darkened(0.3), 2.0)
			d += 10.0

	for r in rocks:
		var sh := PackedVector2Array()
		for p in r["poly"]:
			sh.append(p + Vector2(7, 9))
		_aa_poly(n, sh, shade)
		var foam := 7.0 + sin(clock * 1.4 + float(r["phase"])) * 1.8
		n.draw_arc(r["c"], float(r["r"]) + foam, 0.0, TAU, 40, Color(1, 1, 1, 0.13), 2.0, true)
		_aa_poly(n, r["poly"], pal["rock"])
		_aa_poly(n, r["hi"], pal["rock_hi"])

	for r in ripples:
		if r["light"]:
			continue
		var k := (clock - float(r["t"])) / float(r["life"])
		var rad := lerpf(float(r["r0"]), float(r["r1"]), 1.0 - pow(1.0 - k, 2.0))
		n.draw_arc(r["p"], rad, 0.0, TAU, 28, Color(1, 1, 1, 0.22 * (1.0 - k)), 1.6, true)

	for sp in splashes:
		var k := (clock - float(sp["t"])) / 0.7
		for j in 5:
			var dir := Vector2.from_angle(-PI * 0.5 + (j - 2) * 0.45)
			var dp: Vector2 = sp["p"] + dir * (6.0 + k * 16.0) + Vector2(0, k * k * 14.0)
			n.draw_circle(dp, 2.2 * (1.0 - k), Color(1, 1, 1, 0.7 * (1.0 - k)), true, -1.0, true)

	for d in ducks:
		var dir: Vector2 = (d["b"] - d["a"]).normalized()
		var age := clock - float(d["t0"])
		var fade := clampf(minf(age, float(d["dur"]) - age) / 1.2, 0.0, 1.0)
		for i in int(d["n"]):
			var sz := 1.0 if i == 0 else 0.7
			var p := _duck_pos(d, i * 20.0)
			var spin := 0.0
			if d.has("hit"):
				var hk := (clock - float(d["hit"])) / 1.4
				p = Vector2(d["hp"]) + Vector2(d["hit_dir"]) * (hk * 34.0 + i * 12.0)
				spin = hk * 10.0
				fade *= 1.0 - hk
				sz *= 1.0 - hk * 0.6
			n.draw_set_transform(p + Vector2(3, 4), dir.angle() + spin, Vector2(1.5, 1.0) * sz)
			n.draw_circle(Vector2.ZERO, 7.0, Color(shade, shade.a * fade), true, -1.0, true)
			n.draw_set_transform(p, dir.angle() + spin, Vector2(1.5, 1.0) * sz)
			n.draw_circle(Vector2.ZERO, 7.0, Color(Color("d9cbb0"), fade), true, -1.0, true)
			n.draw_set_transform(p, dir.angle() + spin, Vector2(sz, sz))
			n.draw_circle(Vector2(-3, 0), 4.0, Color(Color("b8a88c"), fade), true, -1.0, true)
			n.draw_circle(Vector2(9, 0), 4.2, Color(Color("3f6b52"), fade), true, -1.0, true)
			n.draw_circle(Vector2(13.5, 0), 1.8, Color(Color("e0a040"), fade), true, -1.0, true)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var pair_col: Color = pal["pair"]
	for i in lanterns.size():
		var l: Dictionary = lanterns[i]
		if int(l["pair"]) == 0 or l["lit"]:
			continue
		var j := _partner(i)
		if j > i and not lanterns[j]["lit"]:
			n.draw_dashed_line(l["p"], lanterns[j]["p"], Color(pair_col, 0.3), 2.0, 9.0)

	for l in lanterns:
		var p: Vector2 = l["p"] + Vector2(0, sin(clock * 1.6 + float(l["bob"])) * 1.6)
		var lit_now: bool = l["lit"] and clock >= float(l["lit_t"])
		n.draw_circle(p + Vector2(3, 4), 11.0, shade, true, -1.0, true)
		if lit_now:
			n.draw_circle(p, 10.0, pal["light"].lightened(0.25), true, -1.0, true)
			n.draw_circle(p, 5.0, Color(1, 1, 1, 0.95), true, -1.0, true)
		else:
			n.draw_circle(p, 10.0, pal["light"].darkened(0.6), true, -1.0, true)
			n.draw_arc(p, 9.0, 0.0, TAU, 28, pal["light"].darkened(0.15), 2.0, true)
			n.draw_circle(p, 4.0, pal["light"].darkened(0.3), true, -1.0, true)
		if int(l["pair"]) != 0 and not lit_now:
			n.draw_arc(p, 15.0, 0.0, TAU, 32, Color(pair_col, 0.8), 2.0, true)
		var since := clock - float(l["reject_t"])
		if since < 0.9:
			var k := since / 0.9
			n.draw_arc(p, 18.0 + k * 16.0, 0.0, TAU, 32, Color(pair_col, 0.9 * (1.0 - k)), 3.0, true)

	var petal: Color = pal["mote"]
	if String(lake["motes"]) != "fireflies":
		for m in motes:
			var a := 0.55 + 0.25 * sin(clock + float(m["ph"]))
			n.draw_set_transform(m["p"], float(m["rot"]), Vector2(1.7, 0.85))
			n.draw_circle(Vector2.ZERO, 2.6, Color(petal, a))
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_parts(n, false)
	var hull := PackedVector2Array(HULL)
	n.draw_set_transform(boat_pos + Vector2(4, 6), heading, Vector2.ONE)
	n.draw_colored_polygon(hull, shade)
	n.draw_set_transform(boat_pos, heading, Vector2.ONE)
	n.draw_colored_polygon(hull, Color("efe6d6"))
	var rim := hull.duplicate()
	rim.append(hull[0])
	n.draw_polyline(rim, Color("b9ab92"), 1.5, true)
	var lean := turn_vel / TURN_RATE * 1.6
	n.draw_rect(Rect2(-9, -4.5 + lean, 11, 9), Color("c9bca5"))
	n.draw_circle(Vector2(13, 0), 2.4, pal["light"])
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_light(n: Node2D) -> void:
	_draw_wake(n)
	_draw_parts(n, true)
	var light: Color = pal["light"]
	var glow: Texture2D = Game.glow_tex
	var power := 0.8 + 0.45 * dusk

	for f in flashes:
		var k := (clock - float(f["t"])) / 1.6
		var tris: PackedInt32Array = f["tris"]
		if tris.is_empty():
			continue
		var poly: PackedVector2Array = f["poly"]
		var a := 0.30 * float(f["s"]) * pow(1.0 - k, 2.0)
		var cols := PackedColorArray()
		cols.resize(poly.size())
		cols.fill(Color(light, a))
		RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), tris, poly, cols)

	for l in lanterns:
		var p: Vector2 = l["p"]
		if l["lit"] and clock >= float(l["lit_t"]):
			var since := clock - float(l["lit_t"])
			var pulse := 1.0 + 0.07 * sin(clock * 2.2 + float(l["bob"]))
			if Game.dev_on("fading") and state == "play":
				var left := clampf(1.0 - since / FADE_TIME, 0.0, 1.0)
				pulse *= 0.45 + 0.55 * left
				n.draw_arc(p, 15.0, -PI * 0.5, -PI * 0.5 + TAU * left, 32, Color(light, 0.8), 2.5, true)
			var burst := maxf(0.0, 1.0 - since / 0.7)
			var r := 110.0 * pulse + burst * 80.0
			n.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(light, (0.85 + burst * 0.3) * power))
			var r2 := 42.0 * pulse
			n.draw_texture_rect(glow, Rect2(p - Vector2(r2, r2), Vector2(r2, r2) * 2.0), false,
				Color(light, 0.75 * power))
			n.draw_texture_rect(glow, Rect2(p - Vector2(16, 16), Vector2(32, 32)), false, Color(1, 1, 1, 0.7))
		else:
			var r := 26.0
			n.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(light, 0.16 + 0.08 * sin(clock * 2.0 + float(l["bob"]))))

	for r in ripples:
		if not r["light"]:
			continue
		var k := (clock - float(r["t"])) / float(r["life"])
		var rad := lerpf(float(r["r0"]), float(r["r1"]), 1.0 - pow(1.0 - k, 3.0))
		n.draw_arc(r["p"], rad, 0.0, TAU, 48, Color(light, 0.5 * (1.0 - k)), 2.5, true)

	if const_t >= 0.0:
		var edges: Array = lake["constellation"]["edges"]
		for e_i in edges.size():
			var e: Array = edges[e_i]
			var k := clampf((clock - const_t - e_i * 0.28) / 0.55, 0.0, 1.0)
			if k <= 0.0:
				continue
			var a: Vector2 = lanterns[e[0]]["p"]
			var b: Vector2 = lanterns[e[1]]["p"]
			var end := a.lerp(b, k)
			n.draw_line(a, end, Color(light, 0.14), 12.0, true)
			n.draw_line(a, end, Color(light, 0.85), 2.5, true)

	var bow := boat_pos + Vector2.from_angle(heading) * 13.0
	var lr := 44.0
	n.draw_texture_rect(glow, Rect2(bow - Vector2(lr, lr), Vector2(lr, lr) * 2.0), false,
		Color(light, 0.12 + 0.3 * dusk))

	if String(lake["motes"]) == "fireflies":
		var fc: Color = pal["mote"]
		for m in motes:
			var tw := 0.5 + 0.5 * sin(clock * 2.3 + float(m["ph"]) * 3.0)
			var fr := 9.0
			var pos: Vector2 = m["p"]
			n.draw_texture_rect(glow, Rect2(pos - Vector2(fr, fr), Vector2(fr, fr) * 2.0), false,
				Color(fc, tw * (0.3 + 0.6 * dusk)))


func _draw_wake(n: Node2D) -> void:
	var pts := wp.duplicate()
	var ages := PackedFloat32Array()
	var cuts := PackedFloat32Array()
	for i in wt.size():
		ages.append(clock - wt[i])
		cuts.append(clampf(1.0 - (clock - wc[i]) / CUT_FADE, 0.0, 1.0))
	pts.append(boat_pos - Vector2.from_angle(heading) * 14.0)
	ages.append(0.0)
	cuts.append(1.0)
	var m := pts.size()
	if m < 2:
		return
	var light: Color = pal["light"]
	for pass_i in 2:
		var verts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in m:
			var f := clampf(1.0 - ages[i] / WAKE_LIFE, 0.0, 1.0)
			var head := minf(1.0, float(m - 1 - i) / 7.0)
			var w := (2.0 + 7.0 * f) * (0.3 + 0.7 * head)
			var a := pow(f, 1.25) * cuts[i]
			if clock < boost_until and ages[i] < 3.0:
				w *= 1.35
				a = minf(1.0, a * 1.3)
			if pass_i == 0:
				w *= 3.4
				a *= 0.13
			else:
				a *= 0.75
			var prev := pts[maxi(i - 1, 0)]
			var next := pts[mini(i + 1, m - 1)]
			var nrm := (next - prev).orthogonal().normalized() * w * 0.5
			verts.append(pts[i] + nrm)
			verts.append(pts[i] - nrm)
			cols.append(Color(light, a))
			cols.append(Color(light, a))
		var idx := PackedInt32Array()
		for i in m - 1:
			if pts[i].distance_to(pts[i + 1]) > 40.0:
				continue  # a gap, e.g. after the boat was patched and moved back
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
		RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, verts, cols)


func _draw_ui(n: Node2D) -> void:
	var light: Color = pal["light"]
	var y := top_inset + 92.0
	for i in lanterns.size():
		var l: Dictionary = lanterns[i]
		var p := Vector2(48 + i * 26, y)
		if l["lit"] and clock >= float(l["lit_t"]):
			n.draw_circle(p, 7.0, light)
		else:
			n.draw_arc(p, 6.0, 0.0, TAU, 24, Color(1, 1, 1, 0.55), 2.0, true)
	var font: Font = Game.ui_theme.default_font
	for f in floaters:
		var k := (clock - float(f["t"])) / 1.8
		var fp: Vector2 = f["p"] + off + Vector2(-200, -30 - k * 40.0)
		n.draw_string(font, fp + Vector2(0, 2), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 400, 25, Color(0, 0, 0, 0.35 * (1.0 - k)))
		n.draw_string(font, fp, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 400, 25, Color(light.lightened(0.4), 1.0 - k * k))
	if clock < boost_until and state == "play":
		var bx := 48.0 + lanterns.size() * 26.0 + 14.0
		var left := (boost_until - clock) / BOOST_TIME
		n.draw_line(Vector2(bx, y), Vector2(bx + 70.0 * left, y), Color(light, 0.9), 4.0, true)
	var gx := view_size.x - 150.0
	var gy := top_inset + 150.0
	var lit_now := 0
	for l in lanterns:
		if l["lit"] and clock >= float(l["lit_t"]):
			lit_now += 1
	var par := int(lake["par"])
	var late := dusk > 0.75 or day_taken
	Game.draw_icon(n, "lantern", Vector2(gx, gy), 30, light if lit_now == lanterns.size() else Color(1, 1, 1, 0.9))
	n.draw_string(font, Vector2(gx + 24, gy + 9), "%d/%d" % [lit_now, lanterns.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.92))
	Game.draw_icon(n, "sun", Vector2(gx, gy + 44), 30, Color(1, 1, 1, 0.3) if late else light)
	n.draw_string(font, Vector2(gx + 24, gy + 53), "late" if late else "%d s" % int((0.75 - dusk) * duration), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.45 if late else 0.92))
	# Loop goal: gold while within the limit, red once it is exceeded.
	Game.draw_icon(n, "loop", Vector2(gx, gy + 88), 30, Color("ff9a8a") if loops_used > par else light)
	n.draw_string(font, Vector2(gx + 24, gy + 97), "%d/%d" % [loops_used, par], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("ff9a8a") if loops_used > par else Color(1, 1, 1, 0.92))
	var x0 := 40.0
	var x1 := view_size.x - 40.0
	var ty := top_inset + 10.0
	n.draw_line(Vector2(x0, ty), Vector2(x1, ty), Color(1, 1, 1, 0.16), 2.0, true)
	var sx := lerpf(x0, x1, dusk)
	n.draw_line(Vector2(x0, ty), Vector2(sx, ty), Color(light, 0.55), 2.0, true)
	n.draw_circle(Vector2(sx, ty), 5.0, Color(light, 1.0 - dusk * 0.6))


# ---------------------------------------------------------------- screens

func _pause() -> void:
	if overlay != null or state in ["results", "crashed"]:
		return
	touches.clear()
	get_tree().paused = true
	overlay = Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.size = view_size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.6)
	dim.size = view_size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var head := Label.new()
	head.text = String(lake["name"])
	head.add_theme_font_override("font", Game.heading_font)
	head.add_theme_font_size_override("font_size", 40)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size = Vector2(view_size.x, 60)
	head.position = Vector2(0, view_size.y * 0.16)
	overlay.add_child(head)
	var opts := [["Continue", _resume], ["Try again", _retry], ["Lakes", _to_map]]
	for i in 3:
		var c := _lantern_button(String(opts[i][0]), opts[i][1], i)
		c.position = Vector2(view_size.x * 0.5 - 100, view_size.y * 0.27 + i * 200)
		overlay.add_child(c)
	var box := VBoxContainer.new()
	box.position = Vector2(40, view_size.y - 150)
	box.size = Vector2(view_size.x - 80, 80)
	overlay.add_child(box)
	_add_settings(box)
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)


## A floating lantern you tap: glow, paper body, label underneath.
func _lantern_button(text: String, fn: Callable, idx: int) -> Control:
	var c := Control.new()
	c.size = Vector2(200, 180)
	c.custom_minimum_size = c.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var light: Color = pal["light"]
	c.draw.connect(func():
		var ctr := Vector2(100, 66)
		var glow: Texture2D = Game.glow_tex
		c.draw_texture_rect(glow, Rect2(ctr - Vector2(90, 90), Vector2(180, 180)), false, Color(light, 0.55))
		c.draw_circle(ctr + Vector2(4, 6), 36, Color(0, 0, 0, 0.25), true, -1.0, true)
		c.draw_circle(ctr, 36, light.lightened(0.15), true, -1.0, true)
		c.draw_circle(ctr, 20, Color(1, 1, 1, 0.9), true, -1.0, true)
		c.draw_rect(Rect2(ctr + Vector2(-22, -46), Vector2(44, 10)), light.darkened(0.45))
		c.draw_line(ctr + Vector2(0, -46), ctr + Vector2(0, -62), light.darkened(0.45), 3.0, true)
		c.draw_string(Game.ui_theme.default_font, Vector2(0, 160), text, HORIZONTAL_ALIGNMENT_CENTER, 200, 30, Color(1, 1, 1, 0.95)))
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed:
			Sfx.tap()
			fn.call())
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "position:y", 6.0, 1.2 + idx * 0.2).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "position:y", -6.0, 1.2 + idx * 0.2).as_relative().set_trans(Tween.TRANS_SINE)
	return c


func _resume() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	touches.clear()
	get_tree().paused = false


func _retry() -> void:
	get_tree().paused = false
	level_requested.emit(lake_index)


func _to_map() -> void:
	get_tree().paused = false
	exit_requested.emit()


func _show_results() -> void:
	var lit := _lit_count()
	var total := lanterns.size()
	var got := 0
	if lit == total:
		got |= Game.MARK_ALL
		if finished_dusk <= 0.75 and not day_taken:
			got |= Game.MARK_TIME
		if loops_used <= int(lake["par"]):
			got |= Game.MARK_LOOPS
	Game.record_result(lake_index, got)
	if lit == total:
		Game.stat_win(lake_index, run_time)
	else:
		Game.stat_fail(lake_index, lit, total)
	var last := lake_index == Game.lake_count() - 1
	var box := _open_overlay(String(lake["name"]))
	var sub := Label.new()
	if lit == total:
		sub.text = "Every lantern is lit." if not last else "Every lantern is lit.\nThe still lakes are bright again."
	else:
		sub.text = "%d of %d lanterns lit before dark." % [lit, total]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.modulate.a = 0.8
	box.add_child(sub)
	var par := int(lake["par"])
	var goals := [["lantern", "Light all %d lanterns" % total, got & Game.MARK_ALL != 0],
		["sun", "Finish before the sun is low", got & Game.MARK_TIME != 0],
		["loop", "Use %d loop%s or fewer" % [par, "" if par == 1 else "s"], got & Game.MARK_LOOPS != 0]]
	var rows: Array = []
	var icons: Array = []
	var light: Color = pal["light"]
	for g in goals:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 18)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(64, 64)
		ic.pivot_offset = Vector2(32, 32)
		ic.set_meta("lit", false)
		var kind: String = g[0]
		ic.draw.connect(func():
			var on: bool = ic.get_meta("lit", false)
			if on:
				ic.draw_texture_rect(Game.glow_tex, Rect2(Vector2(-18, -18), Vector2(100, 100)), false, Color(light, 0.5))
			Game.draw_icon(ic, kind, Vector2(32, 32), 46, light if on else Color(1, 1, 1, 0.3)))
		row.add_child(ic)
		var l := Label.new()
		l.text = String(g[1])
		l.custom_minimum_size = Vector2(380, 0)
		l.add_theme_font_size_override("font_size", 25)
		row.add_child(l)
		row.modulate.a = 0.0
		box.add_child(row)
		rows.append(row)
		icons.append(ic)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)
	var buttons: Array = []
	if lit == total and not last:
		buttons.append(_add_button(box, "Next lake", func(): level_requested.emit(lake_index + 1)))
	buttons.append(_add_button(box, "Try again", _retry))
	buttons.append(_add_button(box, "Lakes", _to_map))
	for b in buttons:
		b.modulate.a = 0.0
	var tw := overlay.create_tween()
	tw.tween_interval(0.5)
	for k in 3:
		var row: Control = rows[k]
		var ic: Control = icons[k]
		var ok: bool = goals[k][2]
		tw.tween_property(row, "modulate:a", 1.0, 0.25)
		tw.tween_callback(func():
			if ok:
				ic.set_meta("lit", true)
				ic.queue_redraw()
				ic.scale = Vector2.ONE * 1.5
				ic.create_tween().tween_property(ic, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
				Sfx.chime(float(lake["pitch"]) * [1.0, 1.25, 1.5][k] * 2.0)
				Game.vibrate(15))
		tw.tween_interval(0.35)
	for b in buttons:
		tw.tween_property(b, "modulate:a", 1.0, 0.2)


func _show_crash() -> void:
	var lines: Array = CRASH_LINES[crash_kind]
	var box := _open_overlay(String(lines[randi() % lines.size()]), 34)
	var sub := Label.new()
	var lit := _lit_count()
	sub.text = "%d of %d lanterns were glowing." % [lit, lanterns.size()] if lit > 0 else "The lanterns are still waiting."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 25)
	sub.modulate.a = 0.75
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)
	Game.stat_add(lake_index, "crashes")
	if patches_used < MAX_REVIVES:
		_add_ad_button(box, "Patch the boat", _patch_boat, MAX_REVIVES - patches_used)
	_add_button(box, "Try again", _retry)
	_add_button(box, "Lakes", _to_map)


## The sun is down but lanterns are left: offer more daylight once per try (an ad, later).
func _offer_daylight() -> void:
	touches.clear()
	get_tree().paused = true
	var lit := _lit_count()
	var box := _open_overlay("The sun is setting", 42)
	var sub := Label.new()
	var left := lanterns.size() - lit
	sub.text = "%d of %d lanterns lit.\n%s to go." % [lit, lanterns.size(), "Just one" if left == 1 else str(left)]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.modulate.a = 0.8
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)
	_add_ad_button(box, "+%d s of daylight" % int(_day_bonus()), _take_daylight, MAX_REVIVES - days_used)
	_add_button(box, "Let it set", _decline_daylight)


func _take_daylight() -> void:
	_close_overlay()
	day_taken = true
	days_used += 1
	elapsed = maxf(0.0, duration - _day_bonus())
	dusk = clampf(elapsed / duration, 0.0, 1.0)
	Game.stat_add(lake_index, "revives")
	_float("+%d s of daylight" % int(_day_bonus()), boat_pos - Vector2(0, 40))
	Sfx.chime(float(lake["pitch"]) * 1.5)


## A quarter of the lake's daylight, at least 5 s.
func _day_bonus() -> float:
	return maxf(5.0, roundf(duration * DAY_BONUS))


func _decline_daylight() -> void:
	_close_overlay()
	_end("dark", 0.8)


## Put the boat back where it was a moment before the crash, facing away from it.
func _patch_boat() -> void:
	patches_used += 1
	_close_overlay()
	var spot := Vector2.INF
	for k in range(history.size() - 1, -1, -1):
		var p: Vector2 = history[k]
		if p.distance_to(crash_pos) >= 45.0 and _free(p):
			spot = p
			break
	if spot == Vector2.INF:
		spot = Vector2(lake["start"][0], lake["start"][1])
	boat_pos = spot
	heading = (spot - crash_pos).angle()
	move_dir = heading
	speed = 0.0
	turn_vel = 0.0
	history.clear()
	# The old trail fades out and can no longer close a loop with the new one.
	for i in wc.size():
		wc[i] = minf(wc[i], clock)
	loop_base = wp.size()
	state = "ready"
	Game.stat_add(lake_index, "revives")
	_float("Patched up", boat_pos - Vector2(0, 40))


func _close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	touches.clear()
	get_tree().paused = false


## A rewarded-ad button. No ad network yet: it grants the reward straight away.
func _add_ad_button(box: Container, text: String, fn: Callable, left: int) -> void:
	var b := _add_button(box, text, fn)
	# Play icon sits right before the centred text.
	b.text = ""
	var inner := HBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 12)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	ic.texture = Game.icon("play")
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(22, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = pal["light"]
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(ic)
	var tl := Label.new()
	tl.text = text
	tl.add_theme_color_override("font_color", pal["light"])
	tl.add_theme_font_size_override("font_size", b.get_theme_font_size("font_size"))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(tl)
	b.add_child(inner)
	b.add_theme_color_override("font_color", pal["light"])
	var note := Label.new()
	note.text = "Watch a short ad  ·  %d of %d left  ·  test build, none plays yet" % [left, MAX_REVIVES]
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 18)
	note.modulate.a = 0.5
	box.add_child(note)


func _open_overlay(title: String, title_size := 46) -> VBoxContainer:
	overlay = Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.size = view_size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.08, 0.62)
	dim.size = view_size
	overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = Vector2(view_size.x - 120, view_size.y)
	box.position = Vector2(60, 0)
	overlay.add_child(box)
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_override("font", Game.heading_font)
	head.add_theme_font_size_override("font_size", title_size)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.35)
	return box


func _add_button(box: Container, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.pressed.connect(func():
		Sfx.tap()
		fn.call())
	box.add_child(b)
	return b


func _add_mark(box: Container, got: bool, text: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(11)
	sb.anti_aliasing = true
	if got:
		sb.bg_color = pal["light"]
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(1, 1, 1, 0.45)
		sb.set_border_width_all(2)
	dot.add_theme_stylebox_override("panel", sb)
	row.add_child(dot)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.modulate.a = 1.0 if got else 0.6
	row.add_child(l)
	box.add_child(row)


func _add_settings(box: Container) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for key in ["sound", "music", "vibration"]:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(0, 64)
		_label_setting(b, key)
		b.pressed.connect(func():
			Game.set_setting(key, not _setting(key))
			_label_setting(b, key)
			Sfx.tap())
		row.add_child(b)


func _setting(key: String) -> bool:
	match key:
		"sound": return Game.sound_on
		"music": return Game.music_on
	return Game.vibration_on


func _label_setting(b: Button, key: String) -> void:
	Game.style_toggle(b, key, _setting(key))
