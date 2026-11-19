extends Node2D
## One lake: the boat, its wake, loop detection, lanterns, drawing and the in-level screens.

signal exit_requested
signal level_requested(index: int)
signal map_requested(level: Node, travel_to: int, reveal: int)

const DrawNode = preload("res://scripts/draw_node.gd")
const Boat3D = preload("res://scripts/boat3d.gd")
const WaterShader = preload("res://scripts/water.gdshader")
const WaterGlintShader = preload("res://scripts/water_glint.gdshader")
const LandShader = preload("res://scripts/land.gdshader")

const SPEED := 150.0
const REED_SPEED := 76.0
const TURN_RATE := 2.5
const WAKE_LIFE := 9.0
const BEAM_LEN := 200.0  # the boat's headlight beam on the water
const BEAM_WIDE := 200.0
const CUT_FADE := 1.5
const WAKE_STEP := 7.0
const BOAT_RADIUS := 22.0  # the boat is about 2x its first size
const JETTY_PAD := 20.0  # the boat's centre keeps this far from a jetty's deck (its moored spot is 30 off the end)
const STERN := 32.0  # distance from the boat's centre to its stern, where the wake starts
const BOW := 34.0
const MIN_LOOP_AREA := 2600.0
const NOTES := [1.0, 1.125, 1.25, 1.5, 1.6667, 2.0, 2.25, 2.5]
const HULL := [Vector2(19, 0), Vector2(9, -7.5), Vector2(-13, -7.5), Vector2(-16, -4.5),
	Vector2(-16, 4.5), Vector2(-13, 7.5), Vector2(9, 7.5)]
const TURN_EASE := 0.2
## How quickly the hull's travel follows where the bow points (higher = less sideways slide). The boat is
## drawn between the two (_vis_heading), so it carves through a turn instead of skidding.
const MOVE_FOLLOW := 8.5
const BOOST_COUNT := 3
const BOOST_WINDOW := 7.0
const BOOST_TIME := 4.5
const BOOST_MULT := 1.4
const CHAIN_WINDOW := 4.5
const CHAIN_BONUS := 3.0
const FADE_TIME := 28.0
const CATCH_TIME := 0.55  # the flame catching after the ember lands
const DRIFT := Vector2(18, 12)
const LANTERN_SOFT := 42.0  # the boat starts being eased away from a lantern here
const LANTERN_HARD := 32.0  # and stops here: the hull just touching the lantern
const DAY_BONUS := 0.25  # the ad's headlight time: this share of the lake's whole time, plus 5 s
# The headlight battery. On a day lake the sun runs first; when it sets with lanterns still dark the
# headlight comes on by itself with a small free reserve. On a night lake it is on from the start and the
# battery is the lake's whole time. When it runs flat the light dies (Lights out); an ad buys more.
const RESERVE := 6.0
const WARN := 3.5  # the last seconds: the light stutters, the bar blinks, the motor hum drops
const MAX_REVIVES := 2
const EMBER_FLIGHT := 0.55  # seconds an ember takes to arc from the boat to a lantern
const EMBER_GAP := 0.4  # seconds between embers when one loop lights several lanterns
const BAR_H := 88.0  # height of the top bar under the safe area
const HUD_EDGE := 32.0  # side margin of everything in the top bar
const HUD_PLATE := Color(0.031, 0.067, 0.086, 0.8)  # per try, for each kind of ad offer
const CRASH_LINES := {
	"rock": ["The stones were closer than they looked.", "A soft knock on the rocks.\nThe lanterns will wait.",
		"Even herons misjudge the stones.", "Bump. The lake forgives you."],
	"shore": ["The shore came up to meet you.", "Your bow found the sand.\nEasy does it.",
		"You reached the edge of the lake.", "Beached, but only a little."],
	"jetty": ["The jetty didn't move. You did.", "A knock on the planks.\nThe lanterns will wait.",
		"Wood meets bow. Wood wins.", "Moored a little too hard."],
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
var jet: Jetty = null  # the jetty, built from a seed: each lake's is different
# The pickup parked on the bank beside the jetty, nose towards it, its empty trailer behind (the boat
# is out on the lake). Rendered once from the same rig as the map's (rig3d.gd).
const LAKE_PX_PER_M := 7.1  # the boat model is about 70 px long for its 9.85 m
const RIG_RENDER := 384
const RIG_VIEW_M := 26.0
const PICKUP_M := 8.7  # the drawn pickup's length (rig3d.gd scales it up), and the trailer's
const TRAILER_M := 11.8
var rig_hitch := Vector2.ZERO  # where the trailer meets the pickup
var rig_bend := 0.0  # the trailer swung round behind the pickup
var rig_tracks: Array = []  # tyre tracks on the grass, each a polyline
var rig_steps: Array = []  # footprints: [position, direction]
var rig_ok := false  # a parking spot was found (nowhere fits: no rig rather than one in the water)
var rig_dir := 0.0  # the way the pickup faces: along the bank, towards the jetty
var rig_tex: Texture2D
var rig_anchor := Vector2.ZERO

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
var spores: Array = []  # specks drifting through the headlight beam
var spore_clock := 0.0
var glint_mat: ShaderMaterial  # the headlight caught by the water's ripple lines
var motes: Array = []
var events: Array = []
var ripple_timer := 0.0
var bump_cool := 0.0
var end_timer := 0.0
var hint_alpha := 1.0
var turn_vel := 0.0
var move_dir := 0.0
var parts: Array = []
var boat3d: SubViewport  # test: the boat as a 3D model (Dev setting "3D boat")
var boat_sprite: Sprite2D
var boat_shadow: Sprite2D
const BOAT_SPRITE_SCALE := 0.29
var shards: Array = []  # pieces of trail a duck snapped off: they flash, drift apart and sink
var embers: Array = []  # glowing embers flying from the boat's lamp to lanterns
var lamp_flare := -10.0  # when the boat's lamp last sent an ember
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
var leaving := false  # a new lake or the map has been asked for; ignore further taps
var night := false
var dusk_start := 0.0  # how far into the evening the lake starts (tint only)
var battery := -1.0  # seconds of headlight left; -1 while the sun is still up
var battery_max := 1.0
# Zooming between the map and this lake: in from the lake's picture when it starts, out to it when
# leaving for the map. No HUD or input meanwhile; a fresh tap skips to the end.
var zoom_from = null  # the map (map.gd), while this lake zooms in from it
var zooming := false
var zoom_in_t := -1.0
var skip_armed := false  # a touch began during the zoom in; only its lift skips
var newly_unlocked := -1  # the lake this win opened, for the map to show
var tree_layer: Node2D
var light_layer: CanvasLayer
var ui_layer: CanvasLayer

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
	night = Game.is_night(lake_index)
	dusk_start = float(lake.get("dusk_start", 0.0))
	Game.set_rig(lake_index)  # the pickup is parked by this lake now
	if night:
		battery = duration
		battery_max = duration
	if rig_ok and Game.dev_on("boat3d"):
		_render_parked_rig()
	if is_instance_valid(zoom_from):
		zooming = true
		zoom_in_t = 0.0
		ui_layer.visible = false
		zoom_from.tint_node.visible = false
		zoom_from.begin_enter(lake_index)
		_set_shown(0.0, zoom_from.tint_color)
		_set_growth(0.0)


# ---------------------------------------------------------------- between the map and this lake
# Setting off: the map's camera dives in on the lake's picture until it is this screen's size (map.gd),
# then this lake fades in over it and its trees grow up, the ones by the water first. Leaving runs it
# backwards: the trees shrink away, the lake fades into the map's picture and the camera pulls back.
const ENTER_CAM := 0.6  # the map's camera diving in
const ENTER_SHOW := 0.25  # this lake fading in over the map's picture
const GROW_TIME := 0.65  # all the trees growing
const LEAVE_HAND := 0.75  # leaving: when the map has taken over

var growth := 1.0  # 0 = no trees yet, 1 = all grown


func _set_shown(k: float, tint: Color) -> void:
	world.modulate.a = k
	light_node.modulate.a = k
	modulate_node.color = tint.lerp(_day_tint(), k)


func _set_growth(g: float) -> void:
	growth = g
	tree_layer.queue_redraw()


## A tree's size while they grow: it pops up with a little overshoot, starting later the farther it is
## from the water (each tree's "d").
func _tree_size(t: Dictionary) -> float:
	if growth >= 1.0:
		return 1.0
	var k := clampf((growth - float(t["d"])) / 0.5, 0.0, 1.0)
	if k <= 0.0:
		return 0.0
	return 1.0 + 2.4 * pow(k - 1.0, 3.0) + 1.4 * pow(k - 1.0, 2.0)


## The victory or pause screen fading away at the start of a zoom out.
func set_overlay_alpha(a: float) -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.modulate.a = a


## The map drives this while the lake hands back to it; t is seconds since leaving.
func leave_step(t: float, tint: Color) -> void:
	set_overlay_alpha(1.0 - clampf(t / 0.3, 0.0, 1.0))
	_set_growth(1.0 - clampf((t - 0.05) / 0.5, 0.0, 1.0))
	_set_shown(1.0 - smoothstep(0.45, LEAVE_HAND, t), tint)


func _day_tint() -> Color:
	var t := 1.0 if night else dusk_start + (1.0 - dusk_start) * dusk
	var c := Color.WHITE.lerp(pal["night"], smoothstep(0.0, 1.0, t) * 0.92)
	return c.darkened(0.3) if night else c


## How bright the headlight is, 0..1: off while the sun is up, stuttering in the last seconds and as it dies.
func _headlight() -> float:
	if state == "dying":
		var on := 1.0 if sin(clock * 41.0) * sin(clock * 23.0) > 0.0 else 0.2
		return on * clampf(end_timer, 0.0, 1.0)
	if battery < 0.0 or state in ["over", "crashed"]:
		return 0.0
	if battery < WARN and state == "play":
		var v := 0.55 + 0.45 * battery / WARN
		if sin(clock * 31.0) * sin(clock * 17.3) > 0.35:
			v *= 0.3
		return v
	return 1.0


func _end_zoom_in() -> void:
	zoom_in_t = -1.0
	zooming = false
	_set_shown(1.0, Color.WHITE)
	_set_growth(1.0)
	if is_instance_valid(zoom_from):
		zoom_from.queue_free()
	zoom_from = null
	ui_layer.visible = true
	ui_root.modulate.a = 0.0
	ui_root.create_tween().tween_property(ui_root, "modulate:a", 1.0, 0.25)


## Parks the pickup on the bank beside the jetty, nose towards it: as close behind the jetty's shore end as
## it fits with the whole pickup and trailer on dry land and on screen, on the lake's preferred side first.
func _park_rig() -> void:
	var d: Vector2 = (Vector2(jetty[1]) - Vector2(jetty[0])).normalized()
	var bank := Game.offset_largest(water, 16.0)
	# Parked the way people really leave a rig by a lake, not squared up: the pickup a little askew and
	# the trailer swung round behind it. Each lake has its own angles (seeded), and they are dropped
	# step by step until the whole rig fits on dry land.
	var rng := RandomNumberGenerator.new()
	rng.seed = 811 * (lake_index + 1)
	var bend := rng.randf_range(0.32, 0.55) * (1.0 if rng.randf() < 0.5 else -1.0)
	var skew := rng.randf_range(-0.22, 0.22)
	var tries := [[skew, bend], [skew, -bend], [skew * 0.5, bend * 0.6], [skew * 0.5, -bend * 0.6], [0.0, 0.0]]
	for tb in tries:
		for sign in [float(lake["rig"]), -float(lake["rig"])]:
			var s: Vector2 = d.orthogonal() * float(sign)
			for back in range(10, 130, 4):
				var hitch: Vector2 = Vector2(jetty[0]) - d * back + s * (PICKUP_M * LAKE_PX_PER_M + 22.0)
				var dir := (-s).angle() + float(tb[0])
				if _rig_fits(hitch, dir, float(tb[1]), bank):
					rig_hitch = hitch
					rig_dir = dir
					rig_bend = float(tb[1])
					rig_ok = true
					_leftovers(rng)
					return


## Whether the pickup (ahead of the hitch) and the trailer (behind it, swung by `bend`) are all on land
## and on screen even on the shortest phones.
func _rig_fits(hitch: Vector2, dir: float, bend: float, bank: PackedVector2Array) -> bool:
	var fwd := Vector2.from_angle(dir)
	var back := -Vector2.from_angle(dir + bend)
	for part in [[fwd, PICKUP_M], [back, TRAILER_M]]:
		var pd: Vector2 = part[0]
		var across := pd.orthogonal()
		for k in 9:
			var q: Vector2 = hitch + pd * float(part[1]) * LAKE_PX_PER_M * (k / 8.0)
			for w in [-13.0, 13.0]:
				var e: Vector2 = q + across * w
				if Geometry2D.is_point_in_polygon(e, bank) or e.x < 16.0 or e.y < 16.0 \
						or e.x > Game.LAKE_SIZE.x - 16.0 or e.y > Game.LAKE_SIZE.y - 16.0:
					return false
	return true


## Signs that someone drove in and walked down to the jetty: tyre tracks curving in behind the trailer
## and the pickup, and footprints from the driver's door to the jetty.
func _leftovers(rng: RandomNumberGenerator) -> void:
	var fwd := Vector2.from_angle(rig_dir)
	var tdir := -Vector2.from_angle(rig_dir + rig_bend)  # from the hitch back along the trailer
	var turn := signf(rig_bend) * 0.035  # the curve they came in on, carried on behind
	# The trailer's wheels, and the pickup's back wheels (which ran in through the hitch, then the trailer's path).
	var trailer_axle := rig_hitch + tdir * TRAILER_M * LAKE_PX_PER_M * 0.72
	var rear := rig_hitch + fwd * PICKUP_M * LAKE_PX_PER_M * 0.22
	var paths: Array = []
	var tp := PackedVector2Array([trailer_axle])
	var tpd := tdir
	for k in 26:
		tpd = tpd.rotated(turn)
		tp.append(tp[tp.size() - 1] + tpd * 6.0)
	paths.append([tp, 11.0])
	var pp := PackedVector2Array([rear, rig_hitch])
	var steps := int(TRAILER_M * LAKE_PX_PER_M / 6.0)
	for k in steps:
		pp.append(rig_hitch + tdir * 6.0 * (k + 1))
	var ppd := tdir
	for k in 26:
		ppd = ppd.rotated(turn)
		pp.append(pp[pp.size() - 1] + ppd * 6.0)
	paths.append([pp, 12.5])
	for path in paths:
		var pts: PackedVector2Array = path[0]
		for side in [-1.0, 1.0]:
			var line := PackedVector2Array()
			for k in pts.size():
				var dd := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
				var q: Vector2 = pts[k] + dd.orthogonal() * float(path[1]) * side
				if Geometry2D.is_point_in_polygon(q, water):
					break
				line.append(q)
			if line.size() > 1:
				rig_tracks.append(line)
	# Footprints from the driver's door to the start of the jetty.
	var door := rig_hitch + fwd * PICKUP_M * LAKE_PX_PER_M * 0.55
	var to: Vector2 = Vector2(jetty[0])
	door += fwd.orthogonal() * (16.0 if fwd.orthogonal().dot(to - door) > 0.0 else -16.0)
	var walk := door.distance_to(to)
	var wd := (to - door).normalized()
	var k := 0
	var dist := 6.0
	while dist < walk - 6.0:
		var fp := door + wd * dist + wd.orthogonal() * (2.6 if k % 2 == 0 else -2.6) + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
		if not Geometry2D.is_point_in_polygon(fp, water):
			rig_steps.append([fp, wd.angle()])
		dist += 8.0
		k += 1


## Renders the parked pickup and empty trailer once, keeps the picture and lets the 3D scene go.
func _render_parked_rig() -> void:
	var r: SubViewport = load("res://scripts/rig3d.gd").new()
	r.render_px = RIG_RENDER
	r.view_m = RIG_VIEW_M
	r.show_boat = false
	add_child(r)
	r.set_pose(rig_dir, rig_bend)
	r.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(r):
		return
	var img := r.get_texture().get_image()
	img.generate_mipmaps()
	rig_tex = ImageTexture.create_from_image(img)
	rig_anchor = r.anchor()
	r.queue_free()


## Leave for the map with the zoom out. next: from the victory screen, so the boat then sails on.
func _zoom_to_map(next: bool) -> void:
	if leaving:
		return
	leaving = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	state = "leaving"
	zooming = true
	touches.clear()
	_set_hud_visible(false)
	if overlay != null:
		_ignore_mouse(overlay)
	map_requested.emit(self, _next_lake() if next else -1, newly_unlocked)


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


## Where the boat goes after a win: the next open lake not yet lit, else simply the next lake.
func _next_lake() -> int:
	for j in range(lake_index + 1, Game.lake_count()):
		if Game.is_unlocked(j) and not Game.lake_done(j):
			return j
	return lake_index + 1 if lake_index + 1 < Game.lake_count() else -1


func _exit_tree() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0


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
	if j.size() >= 4:
		jetty = [Vector2(j[0], j[1]), Vector2(j[2], j[3])]
		var avoid: Array = [[Vector2(lake["start"][0], lake["start"][1]), 22.0]]
		for l in lanterns:
			avoid.append([l["p"], 44.0])
		for r in rocks:
			avoid.append([r["c"], float(r["r"]) + 12.0])
		for r in reeds:
			avoid.append([r["c"], float(r["r"]) + 8.0])
		jet = Jetty.build(jetty[0], jetty[1], String(j[4]) if j.size() > 4 else "", 977 * (lake_index + 1),
			pal["wood"], water, avoid, Game.is_night(lake_index))
	if lake.has("rig") and jetty.size() == 2:
		_park_rig()

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
		if rig_ok:
			var near_rig := false
			var ends := [rig_hitch + Vector2.from_angle(rig_dir) * PICKUP_M * LAKE_PX_PER_M,
				rig_hitch - Vector2.from_angle(rig_dir + rig_bend) * TRAILER_M * LAKE_PX_PER_M]
			for e in ends:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, rig_hitch, e)) < r + 20.0:
					near_rig = true
			for line in rig_tracks:
				for k in range(0, line.size(), 3):
					if p.distance_to(line[k]) < r + 6.0:
						near_rig = true
			if near_rig:
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
	var mid := Vector2.ZERO
	for q in water:
		mid += q
	mid /= maxf(1.0, water.size())
	var near := INF
	var far := 0.0
	for t in trees:
		var d := Vector2(t["p"]).distance_to(mid)
		near = minf(near, d)
		far = maxf(far, d)
	for t in trees:
		t["d"] = 0.5 * clampf((Vector2(t["p"]).distance_to(mid) - near) / maxf(1.0, far - near), 0.0, 1.0)


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
	if jet:
		var jn := DrawNode.new()  # drawn once: the jetty never changes
		var jshade := Color(0.04, 0.07, 0.08, 0.38)  # neutral, so it reads as shadow on water and grass alike
		jn.draw_fn = func(n: Node2D) -> void: jet.draw(n, jshade)
		world.add_child(jn)
	if Game.dev_on("boat3d"):
		boat3d = Boat3D.new()
		add_child(boat3d)
		boat_shadow = Sprite2D.new()
		boat_shadow.texture = boat3d.get_texture()
		boat_shadow.scale = Vector2.ONE * BOAT_SPRITE_SCALE
		boat_shadow.modulate = Color(0.02, 0.06, 0.08, 0.32)
		world.add_child(boat_shadow)
		boat_sprite = Sprite2D.new()
		boat_sprite.texture = boat3d.get_texture()
		boat_sprite.scale = Vector2.ONE * BOAT_SPRITE_SCALE  # the boat is about 70 px long on the lake
		world.add_child(boat_sprite)

	var tree_node := DrawNode.new()
	tree_layer = tree_node
	tree_node.draw_fn = _draw_trees
	world.add_child(tree_node)

	modulate_node = CanvasModulate.new()
	add_child(modulate_node)

	light_layer = CanvasLayer.new()
	light_layer.layer = 1
	light_layer.offset = off
	add_child(light_layer)
	# The water's ripple lines lit where the headlight falls on them (water only, so never on land).
	var glint := Polygon2D.new()
	glint.polygon = water
	glint_mat = ShaderMaterial.new()
	glint_mat.shader = WaterGlintShader
	glint_mat.set_shader_parameter("len", BEAM_LEN)
	glint_mat.set_shader_parameter("wide", BEAM_WIDE)
	glint_mat.set_shader_parameter("col", Color(1.0, 0.95, 0.84))
	glint.material = glint_mat
	light_node = DrawNode.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light_node.material = add
	light_node.draw_fn = _draw_light
	light_layer.add_child(light_node)
	light_node.add_child(glint)  # fades in and out with the rest of the light


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
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

	# Top bar: a dark strip holding the lanterns (left), the loop count and pause (right).
	var strip := ColorRect.new()
	strip.color = HUD_PLATE
	strip.position = Vector2.ZERO
	strip.size = Vector2(view_size.x, top_inset + BAR_H)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(strip)
	ui_root.move_child(strip, 0)
	var pause := Game.square_button(Game.icon("pause"), 64, 26)
	pause.position = Vector2(view_size.x - HUD_EDGE - 64, top_inset + (BAR_H - 64) * 0.5 - 2)
	pause.pressed.connect(_pause)
	ui_root.add_child(pause)
	pause.reset_size()


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	clock += delta
	bump_cool -= delta
	if zoom_in_t >= 0.0:
		zoom_in_t += delta
		var t := zoom_in_t
		if is_instance_valid(zoom_from):
			var ck := clampf(t / ENTER_CAM, 0.0, 1.0)
			zoom_from.set_enter_cam(ck * ck * (3.0 - 2.0 * ck))
			zoom_from.ui_root.modulate.a = 1.0 - smoothstep(0.0, 0.35, t)
			_set_shown(smoothstep(ENTER_CAM - 0.05, ENTER_CAM + ENTER_SHOW, t), zoom_from.tint_color)
			if t >= ENTER_CAM + ENTER_SHOW:
				zoom_from.queue_free()
				zoom_from = null
		_set_growth(clampf((t - ENTER_CAM) / GROW_TIME, 0.0, 1.0))
		if t >= ENTER_CAM + GROW_TIME:
			_end_zoom_in()
	match state:
		"ready":
			if not zooming and (_turn_input() != 0 or not touches.is_empty()):
				state = "play"
				Sfx.tap()
				if not counted:
					counted = true
					Game.stat_add(lake_index, "tries")
		"play":
			elapsed += delta
			dusk = clampf(elapsed / duration, 0.0, 1.0)
			run_time += delta
			if battery >= 0.0:
				battery = maxf(0.0, battery - delta)
			elif dusk >= 1.0 and _lit_count() < lanterns.size():
				# Sunset: the headlight comes on by itself, a few seconds of reserve.
				battery = RESERVE
				battery_max = RESERVE
				_float("Headlight on", boat_pos - Vector2(0, 40))
				Sfx.tap()
			_move_boat(delta, true)
			history_t -= delta
			if history_t <= 0.0 and state == "play":
				history_t = 0.2
				history.append(boat_pos)
				if history.size() > 12:
					history.remove_at(0)
			if battery == 0.0 and state == "play" and _lit_count() < lanterns.size():
				state = "dying"  # the light flickers out, then Lights out
				end_timer = 1.0
				touches.clear()
				Sfx.fade_out()
		"dying":
			_move_boat(delta, false)
			end_timer -= delta
			if end_timer <= 0.0:
				_show_game_over("dark")
		"complete", "dark":
			_move_boat(delta, false)
			end_timer -= delta
			if end_timer <= 0.0:
				state = "results"
				_show_results()
		"crashed":
			end_timer -= delta
			if not boat3d:
				heading += delta * 0.8 * maxf(0.0, end_timer)
			if end_timer <= 0.0:
				_show_game_over("wreck")
		"results":
			_move_boat(delta, false)

	_run_events()
	_update_effects(delta)
	if boat3d:
		var shown := 1.0
		boat_sprite.position = boat_pos
		boat_sprite.modulate.a = (1.0 - 0.9 * boat3d.sunk()) * shown
		boat_shadow.position = boat_pos + Vector2(-12, 16)
		boat_shadow.modulate.a = 0.32 * (1.0 - boat3d.sunk()) * shown
		# A gentle rock and pitch on top of the lean into turns, so it sits in the water.
		var lean := -turn_vel / TURN_RATE * 0.36 + sin(clock * 1.3) * 0.035  # leans well into turns, so its depth shows
		var pitch := speed / SPEED * 0.05 + sin(clock * 1.9) * 0.03
		boat3d.set_pose(_vis_heading(), lean, pitch, 0.0)
	if state == "leaving":
		pass  # the map has the sound now
	elif state in ["ready", "play"]:
		var hum := 0.45 if battery >= 0.0 and battery < WARN else 1.0  # the motor drops as the battery goes
		Sfx.set_mood(dusk, speed / SPEED * hum, _in_reeds(boat_pos))
	else:
		Sfx.set_mood(dusk, 0.0, false)

	var target_hint := 1.0 if state == "ready" and not counted else 0.0
	hint_alpha = move_toward(hint_alpha, target_hint, delta * 2.4)

	if not zooming:
		modulate_node.color = _day_tint()
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
	if zooming:
		if zoom_in_t >= 0.0 and event is InputEventScreenTouch:
			if event.pressed:
				skip_armed = true
			elif skip_armed:
				zoom_in_t = ENTER_CAM + GROW_TIME  # skip to the end
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position.x
		else:
			touches.erase(event.index)
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position.x


func _notification(what: int) -> void:
	if zooming:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if overlay != null and is_instance_valid(overlay):
			if state in ["results", "over"]:
				_to_map()
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

	move_dir = lerp_angle(move_dir, heading, 1.0 - exp(-MOVE_FOLLOW * delta))
	if state == "play":
		var near := _shore_info(boat_pos)
		if float(near[0]) < 7.0:
			_scrape(near)
	var step := speed * delta
	var np := boat_pos + Vector2.from_angle(move_dir) * step
	if not _free(np):
		var moved := false
		var hit_rock := _hits_rock(np)
		var jn: Array = jet.nearest(np) if jet else [INF, Vector2.ZERO]
		var hit_jetty := not hit_rock and float(jn[0]) < JETTY_PAD
		var shore: Array = [] if hit_rock or hit_jetty else _shore_info(boat_pos)
		# Head-on into the shore or a jetty breaks the boat; a glancing touch only slows it.
		var head_on := false
		if hit_jetty:
			head_on = Vector2.from_angle(move_dir).dot(-Vector2(jn[1])) > 0.7 and speed > 70.0
		elif not hit_rock:
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
			_crash("rock" if hit_rock else "jetty" if hit_jetty else "shore")
			return
		if not moved:
			heading += PI * 0.5
			return
		if hit_rock or hit_jetty:
			speed *= 0.86
		else:
			_scrape(shore)
		if bump_cool <= 0.0:
			bump_cool = 0.7
			Sfx.bump()
			ripples.append({"p": np + Vector2.from_angle(heading) * BOW, "t": clock,
				"life": 1.0, "r0": 4.0, "r1": 22.0, "light": false})
	np = _lantern_push(np, delta)
	boat_pos = np

	var stern := boat_pos - Vector2.from_angle(_vis_heading()) * STERN
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
			_part(boat_pos + fwd * BOW * 0.9 + side * s2 * 6.0, side * s2 * randf_range(25, 55) * (1.0 + turn) - fwd * randf_range(5, 30),
				randf_range(0.3, 0.55), randf_range(1.4, 2.6) * (1.3 if boosting else 1.0), Color(1, 1, 1, 0.9), false)
		_part(stern + side * randf_range(-4, 4), -fwd * randf_range(4, 14) + side * randf_range(-6, 6), randf_range(0.9, 1.6), randf_range(1.2, 2.4), Color(1, 1, 1, 0.55), false)
		if boosting:
			for k in 2:
				_part(stern + side * randf_range(-3, 3), -fwd * randf_range(40, 90) + side * randf_range(-25, 25), randf_range(0.4, 0.7), randf_range(2.0, 3.6), pal["light"], true)


## Where the boat is drawn pointing: halfway between its travel and its bow, so turns read as a carve.
func _vis_heading() -> float:
	return lerp_angle(move_dir, heading, 0.5)


func _free(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, inner):
		return false
	if jet and float(jet.nearest(p)[0]) < JETTY_PAD:
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
	if boat3d:
		# The hull splits in slow motion; splinters of wood fly from the impact.
		boat3d.wreck()
		Engine.time_scale = 0.35
		for k in 16:
			_part(boat_pos, Vector2.from_angle(randf() * TAU) * randf_range(40, 140), randf_range(0.6, 1.2), randf_range(2.0, 3.6), Color("a8743f"), false)
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
			# Crossing its own trail cuts it there, like a duck does: the older tail snaps off, and the
			# fresh loop stays live, so it can close the next loop.
			_snap_trail(hit_j, hit_x, false)
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
		var launch := clock + 0.1 + k * EMBER_GAP
		var at := launch + EMBER_FLIGHT
		lanterns[i]["lit"] = true
		lanterns[i]["lit_t"] = at
		events.append({"at": at, "kind": "light", "i": i})
		embers.append({"i": i, "t0": launch, "from": Vector2.ZERO, "launched": false})
		last_t = at

	if _lit_count() == lanterns.size():
		events.append({"at": last_t + 0.55, "kind": "chord"})
		_end("complete", last_t - clock + 2.8)


func _partner(i: int) -> int:
	for k in lanterns.size():
		if k != i and lanterns[k]["pair"] == lanterns[i]["pair"]:
			return k
	return i


## Where a lantern's float sits on the water now (it bobs a little).
func _lantern_pos(l: Dictionary) -> Vector2:
	return Vector2(l["p"]) + Vector2(0, sin(clock * 1.6 + float(l["bob"])) * 1.6)


## Where its flame is: inside the glass, above the float.
func _glass_pos(l: Dictionary) -> Vector2:
	var p := _lantern_pos(l)
	if Game.lantern_lit:
		return p + (Game.lantern_glass - Game.lantern_anchor) * Game.LANTERN_SCALE
	return p


## How lit a lantern looks, 0..1: the flame catches over CATCH_TIME, and fades when it goes out.
func _lantern_on(l: Dictionary) -> float:
	if l["lit"]:
		var since := clock - float(l["lit_t"])
		return smoothstep(0.0, CATCH_TIME, since) if since >= 0.0 else 0.0
	return 1.0 - smoothstep(0.0, 0.6, clock - float(l.get("out_t", -10.0)))


## A slightly uneven flicker for a lantern's light; it sputters in the last seconds before it goes out.
func _flicker(l: Dictionary, warn: bool) -> float:
	var b := float(l["bob"])
	var f := 1.0 + 0.05 * sin(clock * 13.0 + b) + 0.04 * sin(clock * 7.3 + b * 2.0)
	if warn and sin(clock * 23.0 + b) * sin(clock * 9.7) > 0.35:
		f *= 0.55
	return f


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
				Sfx.ignite()
				Sfx.chime(NOTES[int(l["note"]) % NOTES.size()] * float(lake["pitch"]))
				Game.vibrate(22)
				ripples.append({"p": l["p"], "t": clock, "life": 1.8, "r0": 10.0, "r1": 90.0, "light": true})
				for k in 16:
					_part(_glass_pos(l), Vector2.from_angle(randf() * TAU) * randf_range(40, 120), randf_range(0.5, 1.1), randf_range(1.6, 3.2), pal["light"], true)
				Sfx.set_progress(float(_lit_count()) / lanterns.size())
			"chord":
				Sfx.chord(float(lake["pitch"]))
				Game.vibrate(60)
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
	var keep_e: Array = []
	for e in embers:
		if not e["launched"] and clock >= float(e["t0"]):
			e["launched"] = true
			e["from"] = boat_pos + Vector2.from_angle(_vis_heading()) * BOW * 0.4
			lamp_flare = clock
			Sfx.ember()
		if clock < float(e["t0"]) + EMBER_FLIGHT:
			keep_e.append(e)
		else:
			var lp: Vector2 = _glass_pos(lanterns[e["i"]])
			for k in 6:
				_part(lp, Vector2.from_angle(randf() * TAU) * randf_range(20, 70), randf_range(0.3, 0.6), randf_range(1.6, 2.6), Color("fff1c8"), true)
	embers = keep_e
	var life := Game.dev_on("life")
	for l in lanterns:
		if life:
			var b := float(l["bob"])
			l["p"] = l["home"] + Vector2(sin(clock * 0.23 + b) * DRIFT.x, cos(clock * 0.19 + b * 1.3) * DRIFT.y)
		if state == "play" and Game.dev_on("fading") and l["lit"] and clock >= float(l["lit_t"]):
			if clock - float(l["lit_t"]) > FADE_TIME:
				l["lit"] = false
				l["lit_t"] = 1e9
				l["out_t"] = clock
				var top := _glass_pos(l) + Vector2(0, -16)
				for k in 8:
					_part(top + Vector2(randf_range(-2, 2), 0), Vector2(randf_range(-6, 6), randf_range(-40, -18)), randf_range(0.9, 1.5), randf_range(2.0, 3.4), Color(0.86, 0.88, 0.88, 0.5), false)
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
	_update_shards(delta)
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
			if state == "play" and _duck_pos(d, i * 20.0).distance_to(boat_pos) < 26.0:
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
		# Ducks cut the wake: the part behind the cut can no longer close a loop, so it snaps off.
		var cut := -1
		for i in wp.size():
			if wp[i].distance_to(head) < 13.0 and wc[i] > 1e8:
				cut = i
		if cut >= 0 and state == "play":
			# One snap sound and splash per crossing; while the duck is still on the line it only trims.
			var loud: bool = clock - float(d.get("snap", -9.0)) > 0.8
			_snap_trail(cut, head, loud)
			d["snap"] = clock
	ducks = keep


## The trail up to `cut` snaps where the duck crossed: it leaves the live wake at once and becomes
## short pieces that flash, then break off one after another from the cut outwards, drift apart,
## curl and sink. Pieces near the cut are short and fly harder; far ones are longer and slower.
func _snap_trail(cut: int, at: Vector2, loud := true) -> void:
	loop_base = maxi(loop_base, cut + 1)
	var pts := PackedVector2Array()
	var fs := PackedFloat32Array()
	for i in cut + 1:
		if wc[i] > 1e8:
			pts.append(wp[i])
			fs.append(clampf(1.0 - (clock - wt[i]) / WAKE_LIFE, 0.0, 1.0))
		wc[i] = clock - CUT_FADE - 1.0  # gone from the live wake; _prune_wake drops it
	# Walk from the cut back along the trail, chopping it into pieces.
	var k := pts.size() - 1
	var dist := 0.0
	while k >= 1:
		var want := lerpf(16.0, 44.0, clampf(dist / 260.0, 0.0, 1.0)) * randf_range(0.8, 1.25)
		var piece := PackedVector2Array([pts[k]])
		var pf := PackedFloat32Array([fs[k]])
		var run := 0.0
		while k >= 1 and run < want:
			var step := pts[k].distance_to(pts[k - 1])
			k -= 1
			if step > 40.0:
				break  # a gap in the trail, e.g. after a patch-up
			run += step
			piece.append(pts[k])
			pf.append(fs[k])
		k -= 1  # one segment left out between pieces, so the break shows at once
		var start_d := dist
		dist += run + WAKE_STEP
		if piece.size() < 2 or pf[0] + pf[pf.size() - 1] < 0.06:
			continue  # too short, or already too faint to see
		var c := Vector2.ZERO
		for p in piece:
			c += p
		c /= piece.size()
		var local := PackedVector2Array()
		for p in piece:
			local.append(p - c)
		var near := clampf(1.0 - start_d / 320.0, 0.0, 1.0)
		var tang := (piece[piece.size() - 1] - piece[0]).normalized()
		var side := tang.orthogonal()
		if side.dot(c - at) < 0.0:
			side = -side
		var away := (c - at).normalized() if c.distance_to(at) > 1.0 else side
		var v := (away * 0.55 + side * 0.45 + tang * randf_range(-0.25, 0.25)).normalized()
		shards.append({
			"pts": local, "f": pf, "c": c,
			"v": v * lerpf(28.0, 95.0, near) * randf_range(0.8, 1.2),
			"rot": 0.0, "av": randf_range(-1.0, 1.0) * lerpf(0.25, 1.1, near),
			"curl": randf_range(-0.7, 0.7),
			"t0": clock, "delay": 0.1 + start_d / 900.0, "life": randf_range(1.0, 1.35), "sank": false,
		})
	if not loud:
		return
	# At the break itself: a bright flick, a splash and rings, and the snap.
	for j in 10:
		var fc := Color.WHITE if j % 2 == 0 else Color(pal["light"])
		_part(at + Vector2(randf_range(-4, 4), randf_range(-4, 4)), Vector2.from_angle(randf() * TAU) * randf_range(35, 95), randf_range(0.35, 0.7), randf_range(1.4, 2.6), fc, true)
	ripples.append({"p": at, "t": clock, "life": 1.1, "r0": 4.0, "r1": 28.0, "light": true})
	ripples.append({"p": at, "t": clock, "life": 1.5, "r0": 3.0, "r1": 18.0, "light": false})
	Sfx.trail_snap()
	Game.vibrate(15)


func _update_shards(delta: float) -> void:
	var keep: Array = []
	for s in shards:
		var t := clock - float(s["t0"]) - float(s["delay"])
		var life := float(s["life"])
		if t > life:
			continue
		keep.append(s)
		if t <= 0.0:
			continue
		s["c"] += s["v"] * delta
		s["v"] *= exp(-1.4 * delta)
		s["rot"] += float(s["av"]) * delta
		s["av"] *= exp(-1.2 * delta)
		if not s["sank"] and t > life * 0.55:
			s["sank"] = true  # it goes under: a small ring where it was
			ripples.append({"p": s["c"], "t": clock, "life": 0.9, "r0": 2.0, "r1": 11.0, "light": false})
	shards = keep


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
	var sizes := PackedFloat32Array()
	for t in trees:
		sizes.append(_tree_size(t))
	for i in trees.size():
		var g := sizes[i]
		if g <= 0.0:
			continue
		var t: Dictionary = trees[i]
		for part in t["parts"]:
			n.draw_circle(t["p"] + (part[0] + Vector2(8, 10)) * g, part[1] * g, shadow, true, -1.0, true)
	for i in trees.size():
		var g := sizes[i]
		if g <= 0.0:
			continue
		var t: Dictionary = trees[i]
		for part in t["parts"]:
			n.draw_circle(t["p"] + part[0] * g, part[1] * g, pal["tree"], true, -1.0, true)
		for part in t["parts"]:
			var r: float = part[1] * g
			n.draw_circle(t["p"] + part[0] * g + Vector2(-r * 0.22, -r * 0.24), r * 0.62, pal["tree_hi"], true, -1.0, true)


func _draw_details(n: Node2D) -> void:
	var shade: Color = pal["deep"].darkened(0.45)
	shade.a = 0.55

	# Tyre tracks and footprints first, under the rig: someone drove in and walked to the jetty.
	for tr in rig_tracks:
		var line: PackedVector2Array = tr
		for k in range(1, line.size()):
			var fade := 1.0 - float(k) / line.size()
			n.draw_line(line[k - 1], line[k], Color(0.2, 0.16, 0.1, 0.2 * fade + 0.04), 2.6, true)
	for st in rig_steps:
		n.draw_set_transform(st[0], float(st[1]), Vector2(1.0, 0.62))
		n.draw_circle(Vector2.ZERO, 2.3, Color(0.2, 0.16, 0.1, 0.22), true, -1.0, true)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The pickup parked beside the jetty with its empty trailer.
	if rig_tex:
		var sc := LAKE_PX_PER_M / (RIG_RENDER / RIG_VIEW_M)
		var hitch := rig_hitch
		n.draw_set_transform(hitch + Vector2(-5, 6), 0.0, Vector2.ONE * sc)
		n.draw_texture(rig_tex, -rig_anchor, Color(shade, 0.5))
		n.draw_set_transform(hitch, 0.0, Vector2.ONE * sc)
		n.draw_texture(rig_tex, -rig_anchor)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if jet:
		jet.draw_water(n, clock)  # the water moving round the pilings, under the deck

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
		if k < 0.0:
			continue
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

	# Storm lanterns standing on their floats (a 3D render, see lantern_art.gd), unlit with the lit
	# picture over it as the flame catches. Rings for twins and refusals lie flat on the water.
	for l in lanterns:
		var p := _lantern_pos(l)
		var on := _lantern_on(l)
		if Game.lantern_lit:
			n.draw_set_transform(p + Vector2(7, 2), 0.0, Vector2(1.0, 0.36))
			n.draw_circle(Vector2.ZERO, 18.0, Color(shade, 0.4), true, -1.0, true)
			n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var sz := Game.lantern_unlit.get_size() * Game.LANTERN_SCALE
			var tl := p - Game.lantern_anchor * Game.LANTERN_SCALE
			n.draw_texture_rect(Game.lantern_unlit, Rect2(tl, sz), false)
			if on > 0.0:
				n.draw_texture_rect(Game.lantern_lit, Rect2(tl, sz), false, Color(1, 1, 1, on))
		else:
			n.draw_circle(p + Vector2(3, 4), 11.0, shade, true, -1.0, true)
			n.draw_circle(p, 10.0, pal["light"].darkened(0.6).lerp(pal["light"].lightened(0.25), on), true, -1.0, true)
		var lit_now: bool = l["lit"] and clock >= float(l["lit_t"])
		n.draw_set_transform(p, 0.0, Vector2(1.0, 0.38))
		if int(l["pair"]) != 0 and not lit_now:
			n.draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 40, Color(pair_col, 0.85), 2.5, true)
		var since := clock - float(l["reject_t"])
		if since < 0.9:
			var k := since / 0.9
			n.draw_arc(Vector2.ZERO, 22.0 + k * 18.0, 0.0, TAU, 40, Color(pair_col, 0.9 * (1.0 - k)), 3.0, true)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var petal: Color = pal["mote"]
	if String(lake["motes"]) != "fireflies":
		for m in motes:
			var a := 0.55 + 0.25 * sin(clock + float(m["ph"]))
			n.draw_set_transform(m["p"], float(m["rot"]), Vector2(1.7, 0.85))
			n.draw_circle(Vector2.ZERO, 2.6, Color(petal, a))
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_parts(n, false)
	# Embers in flight, drawn solid so they read as warm sparks even on bright daytime water.
	for e in embers:
		if not e["launched"]:
			continue
		var ek := clampf((clock - float(e["t0"])) / EMBER_FLIGHT, 0.0, 1.0)
		var ea: Vector2 = e["from"]
		var eb: Vector2 = _glass_pos(lanterns[e["i"]])
		var emid := (ea + eb) * 0.5 + Vector2(0, -minf(140.0, 60.0 + ea.distance_to(eb) * 0.35))
		for s2 in range(6, -1, -1):
			var kk := maxf(0.0, ek - s2 * 0.04)
			var ep := ea.lerp(emid, kk).lerp(emid.lerp(eb, kk), kk)
			if s2 == 0:
				n.draw_circle(ep, 7.0, Color("ff9a3c"), true, -1.0, true)
				n.draw_circle(ep, 4.0, Color("ffe7a6"), true, -1.0, true)
			else:
				n.draw_circle(ep, 4.2 - s2 * 0.5, Color(1.0, 0.62, 0.24, 0.75 - s2 * 0.1), true, -1.0, true)
	var hull := PackedVector2Array(HULL)
	if boat3d:
		return
	n.draw_set_transform(boat_pos + Vector2(6, 10), _vis_heading(), Vector2.ONE * 2.0)
	n.draw_colored_polygon(hull, shade)
	n.draw_set_transform(boat_pos, _vis_heading(), Vector2.ONE * 2.0)
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
	# The boat's lamp: a small warm light at the bow that flares when it sends an ember.
	var flare := clampf(1.0 - (clock - lamp_flare) / 0.35, 0.0, 1.0)
	var lamp := boat_pos + Vector2.from_angle(_vis_heading()) * BOW * 0.7
	var lamp_r := 18.0 + 16.0 * flare
	var afloat: float = (1.0 - boat3d.sunk()) if boat3d else 1.0
	n.draw_texture_rect(glow, Rect2(lamp - Vector2(lamp_r, lamp_r), Vector2(lamp_r, lamp_r) * 2.0), false, Color(light, (0.35 + 0.2 * dusk + 0.5 * flare) * afloat))
	for e in embers:
		if not e["launched"]:
			continue
		var k := clampf((clock - float(e["t0"])) / EMBER_FLIGHT, 0.0, 1.0)
		var a: Vector2 = e["from"]
		var b: Vector2 = _glass_pos(lanterns[e["i"]])
		var mid := (a + b) * 0.5 + Vector2(0, -minf(140.0, 60.0 + a.distance_to(b) * 0.35))
		for s in range(7, -1, -1):
			var kk := maxf(0.0, k - s * 0.04)
			var p := a.lerp(mid, kk).lerp(mid.lerp(b, kk), kk)
			var r := 34.0 if s == 0 else 14.0 - s * 1.4
			n.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(light, (0.45 + 0.3 * dusk) if s == 0 else 0.35 - s * 0.04))
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
		var p := _lantern_pos(l)
		var gp := _glass_pos(l)
		var on := _lantern_on(l)
		if on > 0.0:
			var lit_now: bool = l["lit"] and clock >= float(l["lit_t"])
			var since := clock - float(l["lit_t"]) if lit_now else 99.0
			var left := 1.0
			var fading: bool = lit_now and Game.dev_on("fading") and state == "play"
			if fading:
				left = clampf(1.0 - since / FADE_TIME, 0.0, 1.0)
			var fl := _flicker(l, fading and left < 0.2)
			var pulse := (1.0 + 0.06 * sin(clock * 2.2 + float(l["bob"]))) * fl * (0.7 + 0.3 * left)
			var burst := maxf(0.0, 1.0 - since / 0.7)
			# A wide soft light round it, kept low in the middle so the lantern still shows inside its glow,
			# and a small bright core where the glass is.
			var r := 120.0 * pulse + burst * 70.0
			n.draw_texture_rect(glow, Rect2(gp - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(light, (0.42 + burst * 0.3) * power * on))
			var r2 := 30.0 * pulse
			n.draw_texture_rect(glow, Rect2(gp - Vector2(r2, r2), Vector2(r2, r2) * 2.0), false,
				Color(light, 0.28 * power * on))
			n.draw_texture_rect(glow, Rect2(gp - Vector2(7, 9), Vector2(14, 18)), false, Color(1, 0.9, 0.7, 0.35 * on * fl))
			# Its reflection: a soft warm streak on the water under the float.
			n.draw_set_transform(p + Vector2(0, 12), 0.0, Vector2(0.4, 1.3))
			n.draw_texture_rect(glow, Rect2(-Vector2(24, 24), Vector2(48, 48)), false, Color(light, 0.38 * on * fl))
			n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# The flame catching: a quick flash in the glass as the ember lands.
			if since < 0.18:
				var fk := since / 0.18
				n.draw_texture_rect(glow, Rect2(gp - Vector2(20, 20) * (1.0 + fk), Vector2(40, 40) * (1.0 + fk)), false, Color(1, 1, 1, 0.9 * (1.0 - fk)))
			if fading:
				_draw_burn_ring(n, p, left, light)
		else:
			var r := 22.0
			n.draw_texture_rect(glow, Rect2(gp - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(light, (0.2 if night else 0.08) + 0.05 * sin(clock * 2.0 + float(l["bob"]))))  # findable in the dark

	for r in ripples:
		if not r["light"]:
			continue
		var k := (clock - float(r["t"])) / float(r["life"])
		if k < 0.0:
			continue
		var rad := lerpf(float(r["r0"]), float(r["r1"]), 1.0 - pow(1.0 - k, 3.0))
		n.draw_arc(r["p"], rad, 0.0, TAU, 48, Color(light, 0.5 * (1.0 - k)), 2.5, true)

	var hl := _headlight()
	if glint_mat:
		var vh := _vis_heading()
		glint_mat.set_shader_parameter("power", 1.3 * hl)
		glint_mat.set_shader_parameter("apex", boat_pos + Vector2.from_angle(vh) * BOW * 0.75)
		glint_mat.set_shader_parameter("dir", Vector2.from_angle(vh))
	if hl > 0.0:
		_draw_headlight(n, hl)
	if jet and jet.lamp != null:
		var jl: Vector2 = jet.lamp
		var jr := 30.0 + 4.0 * sin(clock * 3.0)
		n.draw_texture_rect(glow, Rect2(jl - Vector2(jr, jr), Vector2(jr, jr) * 2.0), false, Color(light, 0.5 * power))
	var bow := boat_pos + Vector2.from_angle(_vis_heading()) * 13.0
	var lr := 44.0
	n.draw_texture_rect(glow, Rect2(bow - Vector2(lr, lr), Vector2(lr, lr) * 2.0), false,
		Color(light, (0.12 + 0.3 * dusk) * afloat))

	if String(lake["motes"]) == "fireflies":
		var fc: Color = pal["mote"]
		for m in motes:
			var tw := 0.5 + 0.5 * sin(clock * 2.3 + float(m["ph"]) * 3.0)
			var fr := 9.0
			var pos: Vector2 = m["p"]
			n.draw_texture_rect(glow, Rect2(pos - Vector2(fr, fr), Vector2(fr, fr) * 2.0), false,
				Color(fc, tw * (0.3 + 0.6 * dusk)))


## The boat's headlight on the water: a soft beam, brightest just ahead of the bow and fading with distance.
## The water's ripple lines catch it (water_glint.gdshader), so do the live ripple rings, and now and then
## a spore drifts through it and lights up.
func _draw_headlight(n: Node2D, hl: float) -> void:
	var vh := _vis_heading()
	var fwd := Vector2.from_angle(vh)
	var apex := boat_pos + fwd * BOW * 0.75
	var warm := Color(1.0, 0.95, 0.84)
	Game.draw_beam(n, apex, vh, BEAM_LEN, BEAM_WIDE, Color(warm, 0.5 * hl))
	n.draw_texture_rect(Game.glow_tex, Rect2(apex + fwd * 60.0 - Vector2(55, 55), Vector2(110, 110)), false, Color(warm, 0.12 * hl))
	# The rings the boat, ducks and lanterns send out catch the light where they cross the beam on the water.
	for r in ripples:
		if r["light"]:
			continue
		var k := (clock - float(r["t"])) / float(r["life"])
		if k < 0.0 or k >= 1.0:
			continue
		var c: Vector2 = r["p"]
		var rad := lerpf(float(r["r0"]), float(r["r1"]), 1.0 - pow(1.0 - k, 2.0))
		const SEG := 20
		for i in SEG:
			var a0 := TAU * i / SEG
			var q := c + Vector2.from_angle(a0 + PI / SEG) * rad
			var bw := _beam_at(q, apex, fwd)
			if bw < 0.03 or not Geometry2D.is_point_in_polygon(q, water):
				continue
			# Only the side of the ring facing the lamp throws the light back, broken up as the water moves.
			var facing := pow(maxf(0.0, Vector2.from_angle(a0 + PI / SEG).dot((apex - c).normalized())), 2.0)
			var sparkle := 0.35 + 0.65 * absf(sin(clock * 7.0 + i * 2.3 + c.x * 0.1))
			var ra := bw * facing * sparkle * (1.0 - k) * hl * 1.1
			if ra > 0.02:
				n.draw_arc(c, rad, a0, a0 + TAU / SEG, 3, Color(warm, minf(1.0, ra)), 1.3, true)
	# Spores: rare, at random places in the beam, drifting slowly; lit only while the beam is on them.
	var dt := clampf(clock - spore_clock, 0.0, 0.1)
	spore_clock = clock
	if spores.size() < 4 and randf() < dt * 0.8:
		var u := randf_range(0.15, 0.85)
		spores.append({"p": apex + fwd * (u * BEAM_LEN) + fwd.orthogonal() * randf_range(-0.4, 0.4) * BEAM_WIDE * (0.2 + 0.8 * u),
			"v": Vector2.from_angle(randf() * TAU) * randf_range(4.0, 11.0), "t": clock,
			"life": randf_range(2.5, 4.5), "s": randf_range(2.0, 3.6)})
	var keep: Array = []
	for sp in spores:
		var age := (clock - float(sp["t"])) / float(sp["life"])
		if age >= 1.0:
			continue
		sp["v"] = Vector2(sp["v"]).rotated(randf_range(-1.2, 1.2) * dt)
		sp["p"] = Vector2(sp["p"]) + Vector2(sp["v"]) * dt
		var a := _beam_at(sp["p"], apex, fwd) * sin(age * PI) * hl
		if a > 0.02:
			var sz: float = sp["s"]
			n.draw_texture_rect(Game.glow_tex, Rect2(Vector2(sp["p"]) - Vector2(sz, sz) * 2.0, Vector2(sz, sz) * 4.0), false, Color(warm, 0.9 * a))
			n.draw_circle(sp["p"], 0.8, Color(1, 1, 1, minf(1.0, 1.4 * a)))
		keep.append(sp)
	spores = keep


## How much of the headlight beam reaches p (0..1), matching the beam picture.
func _beam_at(p: Vector2, apex: Vector2, fwd: Vector2) -> float:
	var d := p - apex
	var u := d.dot(fwd) / BEAM_LEN
	if u <= 0.0 or u >= 1.0:
		return 0.0
	var v := absf(d.dot(fwd.orthogonal())) / (BEAM_WIDE * 0.5)
	return (1.0 - smoothstep(0.45, 1.0, v / (0.2 + 0.8 * u))) * pow(1.0 - u, 1.2) * smoothstep(0.0, 0.08, u)


## How long a lit lantern has left (fading lanterns): a thin line of light on the water round its float,
## like a reflection, draining clockwise. It warms to orange near the end and pulses gently in the last
## seconds while the flame sputters.
func _draw_burn_ring(n: Node2D, p: Vector2, left: float, light: Color) -> void:
	var col := light.lerp(Color("ff7a45"), 1.0 - smoothstep(0.15, 0.4, left))
	var a := 1.0
	if left < 0.2:
		a = 0.6 + 0.4 * (0.5 + 0.5 * sin(clock * 7.0))
	var a0 := -PI * 0.5
	var a1 := a0 + TAU * left
	n.draw_set_transform(p, 0.0, Vector2(1.0, 0.36))
	n.draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 64, Color(1, 1, 1, 0.1), 2.0, true)
	if left > 0.0:
		n.draw_arc(Vector2.ZERO, 27.0, a0, a1, 64, Color(col, 0.2 * a), 8.0, true)
		n.draw_arc(Vector2.ZERO, 27.0, a0, a1, 64, Color(col, 0.95 * a), 2.4, true)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wake(n: Node2D) -> void:
	var pts := wp.duplicate()
	var ages := PackedFloat32Array()
	var cuts := PackedFloat32Array()
	for i in wt.size():
		ages.append(clock - wt[i])
		cuts.append(clampf(1.0 - (clock - wc[i]) / CUT_FADE, 0.0, 1.0))
	pts.append(boat_pos - Vector2.from_angle(_vis_heading()) * STERN)
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
	_draw_shards(n)


func _draw_shards(n: Node2D) -> void:
	if shards.is_empty():
		return
	var light: Color = pal["light"]
	var sunk_col: Color = pal["deep"].lightened(0.35)
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for s in shards:
		var age := clock - float(s["t0"])
		var tt := clampf((age - float(s["delay"])) / float(s["life"]), 0.0, 1.0)
		var flash := clampf(1.0 - age / 0.22, 0.0, 1.0)  # everything cut lights up once at the snap
		var fade := pow(1.0 - tt, 1.6)
		var col := light.lerp(Color.WHITE, flash * 0.8).lerp(sunk_col, smoothstep(0.3, 1.0, tt))
		var pts: PackedVector2Array = s["pts"]
		var fs: PackedFloat32Array = s["f"]
		var m := pts.size()
		var shrink := 1.0 - 0.3 * tt
		var world_pts := PackedVector2Array()
		for i in m:
			var u := float(i) / float(m - 1) - 0.5
			var ang := float(s["rot"]) + float(s["curl"]) * tt * u * 2.0
			world_pts.append(s["c"] + (pts[i] * shrink).rotated(ang))
		for pass_i in 2:
			var base := verts.size()
			for i in m:
				var f := fs[i]
				var tip := 0.35 if i == 0 or i == m - 1 else 1.0  # snapped ends taper to a point
				var w := (2.0 + 7.0 * f) * tip * (1.0 - 0.5 * tt) * (1.0 + 0.12 * flash)
				var a := minf(1.0, pow(f, 1.25) + flash * 0.5) * fade
				if pass_i == 0:
					w *= 2.4
					a *= 0.12 + 0.1 * flash
				else:
					a *= 0.8
				var prev := world_pts[maxi(i - 1, 0)]
				var next := world_pts[mini(i + 1, m - 1)]
				var nrm := (next - prev).orthogonal().normalized() * w * 0.5
				verts.append(world_pts[i] + nrm)
				verts.append(world_pts[i] - nrm)
				cols.append(Color(col, a))
				cols.append(Color(col, a))
			for i in m - 1:
				var b := base + i * 2
				idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, verts, cols)


func _draw_ui(n: Node2D) -> void:
	var light: Color = pal["light"]
	var font: Font = Game.heading_font
	var cy := top_inset + BAR_H * 0.5
	var par := int(lake["par"])

	# Lanterns, left: one icon per lantern, lit ones glow in the lake's light colour.
	const LI := 44.0
	const LGAP := 10.0
	for k in lanterns.size():
		var l: Dictionary = lanterns[k]
		var c := Vector2(HUD_EDGE + LI * 0.5 + k * (LI + LGAP), cy)
		var on: bool = l["lit"] and clock >= float(l["lit_t"])
		if on:
			n.draw_texture_rect(Game.glow_tex, Rect2(c - Vector2(34, 34), Vector2(68, 68)), false, Color(light, 0.55))
		Game.draw_icon(n, "lantern", c, LI / 1.1, light if on else Color(1, 1, 1, 0.42))

	# Loops, right of centre next to pause: icon and count, red once over the limit.
	var over := loops_used > par
	var loop_col := Color("ff9a8a") if over else light
	var txt := "%d/%d" % [loops_used, par]
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var lx := view_size.x - HUD_EDGE - 64 - 24 - tw
	Game.draw_icon(n, "loop", Vector2(lx - 8 - 17, cy), 34, loop_col)
	n.draw_string(font, Vector2(lx, cy + 10), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE if not over else loop_col)

	# Seconds of light left, in the bar next to the loops: the sun's, or the headlight battery's.
	var batt := battery >= 0.0
	var charge := clampf(battery / maxf(0.001, battery_max), 0.0, 1.0)
	var warn := batt and battery < WARN and state == "play"
	var blink := 0.45 + 0.55 * absf(sin(clock * 7.0)) if warn else 1.0
	var secs := "%d s" % (ceili(battery) if batt else ceili((1.0 - dusk) * duration))
	var sw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var sun_x := lx - 8 - 34 - 32 - sw
	var day_col := light.lerp(Color("ff8a66"), smoothstep(0.7, 1.0, dusk))
	if batt:
		day_col = Color("cfe6ff").lerp(Color("ff7a5a"), 1.0 - smoothstep(0.1, 0.3, charge))
		day_col.a = blink
	Game.draw_icon(n, Game.battery_icon(charge) if batt else "sun", Vector2(sun_x - 8 - 17, cy), 34, day_col)
	n.draw_string(font, Vector2(sun_x, cy + 10), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)

	# Daylight: a bar under the strip that fills to the right as the day passes, the sun riding its end.
	# Two marks on it, told apart by colour, shape and label: DUSK (white tick, the "before dusk" goal)
	# and BEST (gold pointer, where your best time on this lake finished).
	var by := top_inset + BAR_H
	var w := view_size.x
	var day_f := clampf(dusk, 0.0, 1.0)
	var late := dusk > 0.75 or day_taken
	n.draw_rect(Rect2(0, by, w, 10), HUD_PLATE)
	n.draw_rect(Rect2(0, by, w, 10), Color(1, 1, 1, 0.14))
	if batt:
		# The battery: full from the left, draining back; on a night lake the SPARE mark is the time goal.
		n.draw_rect(Rect2(0, by, w * charge, 10), day_col)
		if night and not day_taken:
			var spare_x := w * 0.25
			var spare_a := 0.35 if late else 0.95
			n.draw_rect(Rect2(spare_x - 2, by - 6, 4, 22), Color(1, 1, 1, spare_a))
			var best_n := float(Game.stats[lake_index]["best"])
			var spare_w := _tag_width(font, "SPARE")
			var spare_l := spare_x - spare_w * 0.5
			if best_n > 0.0:
				var bx := (1.0 - clampf(best_n / maxf(1.0, duration), 0.0, 1.0)) * w
				n.draw_colored_polygon(PackedVector2Array([Vector2(bx - 9, by - 14), Vector2(bx + 9, by - 14), Vector2(bx, by - 2)]), light)
				n.draw_rect(Rect2(bx - 2, by - 2, 4, 16), light)
				var btn := "BEST %d s" % roundi(best_n)
				var bwn := _tag_width(font, btn)
				var bl := bx - bwn * 0.5
				if absf(bx - spare_x) < (bwn + spare_w) * 0.5 + 8.0:
					var mid := (bx + spare_x) * 0.5
					if bx <= spare_x:
						bl = mid - 4.0 - bwn
						spare_l = mid + 4.0
					else:
						spare_l = mid - 4.0 - spare_w
						bl = mid + 4.0
				_tag(n, font, bl, by + 22.0, btn, light)
			_tag(n, font, spare_l, by + 22.0, "SPARE", Color(1, 1, 1, spare_a))
		Game.draw_icon(n, Game.battery_icon(charge), Vector2(clampf(w * charge, 22.0, w - 22.0), by + 5), 36, day_col)
		_draw_popups(n, font, by, light)
		return
	n.draw_rect(Rect2(0, by, w * day_f, 10), day_col)
	var dusk_x := w * 0.75
	var dusk_a := 0.35 if late else 0.95
	n.draw_rect(Rect2(dusk_x - 2, by - 6, 4, 22), Color(1, 1, 1, dusk_a))
	var label_y := by + 22.0
	var dusk_w := _tag_width(font, "DUSK")
	var dusk_l := dusk_x - dusk_w * 0.5
	var best := float(Game.stats[lake_index]["best"])
	if best > 0.0:
		var best_x := clampf(best / maxf(1.0, duration), 0.0, 1.0) * w
		n.draw_colored_polygon(PackedVector2Array([Vector2(best_x - 9, by - 14), Vector2(best_x + 9, by - 14), Vector2(best_x, by - 2)]), light)
		n.draw_rect(Rect2(best_x - 2, by - 2, 4, 16), light)
		var bt := "BEST %d s" % roundi(best)
		var bw := _tag_width(font, bt)
		var best_l := best_x - bw * 0.5
		# Too close to share the row centred: slide the two tags apart around the point between the marks.
		if absf(best_x - dusk_x) < (bw + dusk_w) * 0.5 + 8.0:
			var mid := (best_x + dusk_x) * 0.5
			if best_x <= dusk_x:
				best_l = mid - 4.0 - bw
				dusk_l = mid + 4.0
			else:
				dusk_l = mid - 4.0 - dusk_w
				best_l = mid + 4.0
		_tag(n, font, best_l, label_y, bt, light)
	_tag(n, font, dusk_l, label_y, "DUSK", Color(1, 1, 1, dusk_a))
	var sx := clampf(w * day_f, 22.0, w - 22.0)
	Game.draw_icon(n, "sun", Vector2(sx, by + 5), 36, day_col)

	_draw_popups(n, font, by, light)


## Pop-ups (chain, swift water, patched up…) under the bar, then the tutorial before setting off.
func _draw_popups(n: Node2D, font: Font, by: float, light: Color) -> void:
	var w := view_size.x
	# Pop-ups (chain, swift water, patched up…): gold on a dark plate under the bar, newest at the top.
	var py := by + 64.0
	for k in range(floaters.size() - 1, -1, -1):
		var f: Dictionary = floaters[k]
		var age := (clock - float(f["t"])) / 1.8
		var a := clampf(minf(age * 8.0, (1.0 - age) * 4.0), 0.0, 1.0)
		var t: String = String(f["text"]).to_upper()
		var fw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var rect := Rect2(Vector2((w - fw) * 0.5 - 24, py + 24), Vector2(fw + 48, 48))
		n.draw_style_box(_plate_box(), rect)
		n.draw_string(font, Vector2(rect.position.x + 24, rect.position.y + 32), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(light, a))
		py += 56.0

	# Before setting off: the lake's rule under the bar, the steering zones and a callout on a lantern.
	if hint_alpha > 0.01:
		_draw_tutorial(n, font, by, light, hint_alpha)


## The tutorial shown before you set off; it fades once you start moving.
func _draw_tutorial(n: Node2D, font: Font, by: float, light: Color, a: float) -> void:
	var w := view_size.x
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The lake's rule, one plate under the bar (lakes without a rule show none).
	var rule := String(lake["hint"])
	if rule != "":
		var rw := 0.0
		for line in rule.split("\n"):
			rw = maxf(rw, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x)
		rw = minf(rw + 16.0, w - 2 * HUD_EDGE - 48)
		var lines := font.get_multiline_string_size(rule, HORIZONTAL_ALIGNMENT_CENTER, rw, 24).y
		var rr := Rect2(Vector2((w - rw) * 0.5 - 24, by + 72), Vector2(rw + 48, lines + 24))
		var box := _plate_box()
		box.bg_color.a *= a
		n.draw_style_box(box, rr)
		n.draw_multiline_string(font, Vector2(rr.position.x + 24, rr.position.y + 12 + 24), rule, HORIZONTAL_ALIGNMENT_CENTER, rw, 24, -1, Color(1, 1, 1, a))

	# Steering zones: the lower 40% of the screen, split down the middle.
	var zt := view_size.y * 0.6
	var zh := view_size.y - zt
	var dy := zt + zh * 0.08
	while dy < view_size.y - zh * 0.08:
		n.draw_line(Vector2(w * 0.5, dy), Vector2(w * 0.5, minf(dy + 14, view_size.y)), Color(1, 1, 1, 0.35 * a), 3.0)
		dy += 26.0
	for side in [-1.0, 1.0]:
		var cx := w * (0.25 if side < 0 else 0.75)
		var ccy := zt + zh * 0.34
		var ch := PackedVector2Array([Vector2(cx - side * 10, ccy - 26), Vector2(cx + side * 14, ccy), Vector2(cx - side * 10, ccy + 26)])
		n.draw_polyline(ch, Color(0, 0, 0, 0.5 * a), 11.0, true)
		n.draw_polyline(ch, Color(1, 1, 1, 0.9 * a), 6.0, true)
		_shadow_text(n, font, Vector2(cx - 120, ccy + 70), "HOLD TO TURN", 22, Color(1, 1, 1, 0.9 * a), 240, HORIZONTAL_ALIGNMENT_CENTER)

	# Callout on the first lake only: a ring around the lantern nearest the boat, a thin line out to a short note.
	if lake_index != 0:
		return
	var best_l: Dictionary = lanterns[0]
	for l in lanterns:
		if Vector2(l["p"]).distance_to(boat_pos) < Vector2(best_l["p"]).distance_to(boat_pos):
			best_l = l
	var lp: Vector2 = _glass_pos(best_l) + Vector2(0, 6) + off
	var toward_centre := -1.0 if lp.x > w * 0.5 else 1.0
	n.draw_arc(lp, 26.0, 0.0, TAU, 40, Color(0, 0, 0, 0.45 * a), 5.0, true)
	n.draw_arc(lp, 26.0, 0.0, TAU, 40, Color(light, a), 2.5, true)
	var elbow := lp + Vector2(toward_centre * 26.0 * 0.7071, -26.0 * 0.7071)
	var end := elbow + Vector2(toward_centre * 28.0, -64.0)
	n.draw_line(elbow, end, Color(0, 0, 0, 0.45 * a), 5.0, true)
	n.draw_line(elbow, end, Color(light, a), 2.5, true)
	var note := "Loop to light the lantern"
	var nw := font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var nx := end.x - 16 if toward_centre > 0 else end.x + 16 - nw
	_shadow_text(n, font, Vector2(clampf(nx, 16, w - 16 - nw), end.y - 12), note, 24, Color(light, a))


func _shadow_text(n: Node2D, font: Font, pos: Vector2, text: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	n.draw_string(font, pos + Vector2(0, 3), text, align, width, size, Color(0, 0, 0, 0.7 * col.a))
	n.draw_string(font, pos, text, align, width, size, col)


func _tag_width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 20.0


## A small label on a dark tag starting at x (kept on screen).
func _tag(n: Node2D, font: Font, x: float, y: float, text: String, col: Color) -> void:
	var tw := _tag_width(font, text)
	var r := Rect2(Vector2(clampf(x, 8.0, view_size.x - 8.0 - tw), y), Vector2(tw, 30.0))
	var b := _plate_box()
	b.set_corner_radius_all(8)
	n.draw_style_box(b, r)
	n.draw_string(font, Vector2(r.position.x + 10.0, y + 22.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


func _plate_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = HUD_PLATE
	b.set_corner_radius_all(12)
	b.anti_aliasing = true
	return b


# ---------------------------------------------------------------- screens

func _pause() -> void:
	if overlay != null or zooming or state in ["results", "crashed", "leaving", "dying"]:
		return
	touches.clear()
	get_tree().paused = true
	overlay = Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.size = view_size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_hud_visible(false)
	ui_root.add_child(overlay)
	var light: Color = pal["light"]

	# Tapping anywhere that is not a button carries on.
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.047, 0.063, 0.72)
	dim.size = view_size
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed:
			Sfx.tap()
			_resume())
	overlay.add_child(dim)

	var top := top_inset + view_size.y * 0.06
	var name_l := Label.new()
	name_l.text = String(lake["name"])
	name_l.add_theme_font_override("font", Game.heading_font)
	name_l.add_theme_font_size_override("font_size", 36)
	name_l.position = Vector2(44, top)
	name_l.size = Vector2(360, 76)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_child(name_l)
	var tg_row := HBoxContainer.new()
	tg_row.add_theme_constant_override("separation", 18)
	tg_row.alignment = BoxContainer.ALIGNMENT_END
	tg_row.position = Vector2(view_size.x - 44 - 3 * 76 - 2 * 18, top)
	tg_row.size = Vector2(3 * 76 + 2 * 18, 76)
	overlay.add_child(tg_row)
	for key in ["sound", "music", "vibration"]:
		var b := _square_button(Game.icon(key), 76, 36)
		Game.style_toggle(b, key, _setting(key))
		b.custom_minimum_size = Vector2(76, 76)
		b.pressed.connect(func():
			Game.set_setting(key, not _setting(key))
			Game.style_toggle(b, key, _setting(key))
			b.custom_minimum_size = Vector2(76, 76)
			Sfx.tap())
		tg_row.add_child(b)

	var paused := Label.new()
	paused.text = "PAUSED"
	paused.add_theme_font_override("font", Game.title_font)
	paused.add_theme_font_size_override("font_size", 62)
	paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused.position = Vector2(0, view_size.y * 0.27)
	paused.size = Vector2(view_size.x, 90)
	overlay.add_child(paused)

	# Goals, the same three readouts as in play.
	var lit_now := 0
	for l in lanterns:
		if l["lit"] and clock >= float(l["lit_t"]):
			lit_now += 1
	var par := int(lake["par"])
	var goals := [["lantern", "%d/%d" % [lit_now, lanterns.size()]],
		[Game.battery_icon(battery / maxf(0.001, battery_max)), "%d s" % ceili(battery)] if battery >= 0.0 else ["sun", "%d s" % ceili((1.0 - dusk) * duration)],
		["loop", "%d/%d" % [loops_used, par]]]
	var g_row := HBoxContainer.new()
	g_row.alignment = BoxContainer.ALIGNMENT_CENTER
	g_row.add_theme_constant_override("separation", 50)
	g_row.position = Vector2(0, view_size.y * 0.37)
	g_row.size = Vector2(view_size.x, 50)
	g_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(g_row)
	for g in goals:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 12)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.texture = Game.icon(String(g[0]))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var isz := 40.0 * float(Game.ICON_OPTICAL.get(String(g[0]), 1.0))
		ic.custom_minimum_size = Vector2(isz, isz)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.modulate = Color("cfe6ff") if String(g[0]).begins_with("battery") else light.lerp(Color("ff8a66"), smoothstep(0.7, 1.0, dusk)) if g[0] == "sun" else (Color("ff9a8a") if (g[0] == "loop" and loops_used > par) else light)
		item.add_child(ic)
		var t := Label.new()
		t.text = String(g[1])
		t.add_theme_font_size_override("font_size", 33)
		item.add_child(t)
		g_row.add_child(item)

	var play := TextureRect.new()
	play.texture = Game.icon("play")
	play.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	play.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	play.size = Vector2(116, 116)
	play.position = Vector2(view_size.x * 0.5 - 58, view_size.y * 0.54 - 58)
	play.modulate = light
	play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(play)
	var pulse := play.create_tween().set_loops()
	pulse.tween_property(play, "modulate:a", 0.6, 1.2).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(play, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	var tap := Label.new()
	tap.text = "TAP TO RESUME"
	tap.add_theme_font_override("font", Game.title_font)
	tap.add_theme_font_size_override("font_size", 26)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.position = Vector2(0, view_size.y * 0.63)
	tap.size = Vector2(view_size.x, 40)
	tap.modulate.a = 0.8
	overlay.add_child(tap)

	_add_corner_buttons(overlay)

	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.25)


## Menu (bottom left) and Restart (bottom right): each a column of button over label, so they stay centred.
## Menu goes to the lake map for now.
func _add_corner_buttons(parent: Control) -> void:
	const SIDE := 108.0
	const COL_W := 148.0
	const EDGE := 50.0
	var bottom := view_size.y - view_size.y * 0.06
	for spec in [["menu", "Menu", _to_map, EDGE - (COL_W - SIDE) * 0.5],
			["restart", "Restart", _retry, view_size.x - EDGE - SIDE - (COL_W - SIDE) * 0.5]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.position = Vector2(float(spec[3]), bottom - SIDE - 8 - 34)
		col.size = Vector2(COL_W, SIDE + 8 + 34)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(col)
		var b := _square_button(Game.icon(String(spec[0])), SIDE, 50)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var fn: Callable = spec[2]
		b.pressed.connect(func():
			Sfx.tap()
			fn.call())
		col.add_child(b)
		var l := Label.new()
		l.text = String(spec[1])
		l.add_theme_font_size_override("font_size", 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(COL_W, 34)
		l.modulate.a = 0.75
		col.add_child(l)


## A solid square game button with a darker bottom edge, holding one white icon.
func _square_button(tex: Texture2D, side: float, icon_w: int) -> Button:
	return Game.square_button(tex, side, icon_w)


func _resume() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	_set_hud_visible(true)
	touches.clear()
	get_tree().paused = false


## Hides the play screen's own top bar (name, goals, pause button) while the pause screen is up.
func _set_hud_visible(on: bool) -> void:
	for ch in ui_root.get_children():
		if ch != overlay:
			ch.visible = on


func _retry() -> void:
	_go(lake_index)


func _to_map() -> void:
	_zoom_to_map(false)


## Leaves this lake for another lake (or the map when i is -1), once only.
func _go(i: int) -> void:
	if leaving:
		return
	leaving = true
	get_tree().paused = false
	if i < 0:
		exit_requested.emit()
	else:
		level_requested.emit(i)


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
	if got & Game.MARK_ALL and lake_index + 1 < Game.lake_count() and not Game.is_unlocked(lake_index + 1):
		newly_unlocked = lake_index + 1
		Game.set_rig_pending(newly_unlocked)  # the pickup drives there once the map is on screen
	Game.record_result(lake_index, got)
	var prev_best := float(Game.stats[lake_index]["best"])
	if lit == total:
		Game.stat_win(lake_index, run_time)
	else:
		Game.stat_fail(lake_index, lit, total)
	var last := lake_index == Game.lake_count() - 1
	_show_victory(got, prev_best, last)


## Every lantern lit: "ALL LIT", the three goals stamped down one by one, a daylight bar with this time
## and the best time, then tap anywhere for the next lake. Menu and Restart sit in the corners as on pause.
func _show_victory(got: int, prev_best: float, last: bool) -> void:
	var light: Color = pal["light"]
	var total := lanterns.size()
	var par := int(lake["par"])
	_set_hud_visible(false)
	overlay = Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.size = view_size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	var can_continue := [false]
	# A tap while the goals are still being stamped plays the rest about six times faster (still animated,
	# so it never flickers); once it has all played, a tap carries on.
	var speed := [1.0]
	var seq: Array = []
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.047, 0.063, 0.74)
	dim.size = view_size
	dim.gui_input.connect(func(e: InputEvent):
		if not (e is InputEventScreenTouch and not e.pressed):
			return
		if can_continue[0]:
			Sfx.tap()
			_zoom_to_map(true)
		elif speed[0] == 1.0:
			speed[0] = 6.0
			for t in seq:
				if is_instance_valid(t):
					(t as Tween).set_speed_scale(6.0))
	overlay.add_child(dim)

	var title := Label.new()
	title.text = "ALL LIT"
	title.add_theme_font_override("font", Game.title_font)
	title.add_theme_font_size_override("font_size", 62)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, view_size.y * 0.15)
	title.size = Vector2(view_size.x, 90)
	overlay.add_child(title)
	var name_l := Label.new()
	name_l.text = String(lake["name"])
	name_l.add_theme_font_size_override("font_size", 32)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.position = Vector2(0, view_size.y * 0.245)
	name_l.size = Vector2(view_size.x, 46)
	name_l.modulate.a = 0.7
	overlay.add_child(name_l)

	# Goals: empty dashed slots first, then each icon is stamped into its slot.
	const SLOT := 115.0
	const ITEM_W := 151.0
	const GAP := 58.0
	var goals := [["lantern", "All %d lanterns" % total, got & Game.MARK_ALL != 0],
		[Game.time_goal(lake_index)[0], Game.time_goal(lake_index)[1], got & Game.MARK_TIME != 0],
		["loop", "%d loop%s" % [par, "" if par == 1 else "s"], got & Game.MARK_LOOPS != 0]]
	var x0 := (view_size.x - (3.0 * ITEM_W + 2.0 * GAP)) * 0.5
	var gy := view_size.y * 0.33
	var tw := overlay.create_tween()
	seq.append(tw)
	tw.tween_interval(0.5)
	for k in 3:
		var ok: bool = goals[k][2]
		var kind: String = goals[k][0]
		var cx := x0 + k * (ITEM_W + GAP) + ITEM_W * 0.5
		var slot := Control.new()
		slot.position = Vector2(cx - SLOT * 0.5, gy)
		slot.size = Vector2(SLOT, SLOT)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.draw.connect(func():
			for d in 16:
				var a := TAU * d / 16.0
				slot.draw_arc(Vector2(SLOT, SLOT) * 0.5, SLOT * 0.5 - 2.0, a, a + TAU / 32.0, 4, Color(1, 1, 1, 0.18), 3.0, true))
		overlay.add_child(slot)
		var ring := Control.new()
		ring.size = Vector2(SLOT, SLOT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_meta("k", -1.0)
		ring.draw.connect(func():
			var rk: float = ring.get_meta("k")
			if rk >= 0.0:
				ring.draw_arc(Vector2(SLOT, SLOT) * 0.5, SLOT * 0.5 * (0.8 + 1.1 * rk), 0.0, TAU, 48, Color(light, 0.9 * (1.0 - rk)), 5.0, true))
		slot.add_child(ring)
		var sparks: Array = []
		for d in 6:
			var sp := Control.new()
			sp.size = Vector2(10, 10)
			sp.position = Vector2(SLOT, SLOT) * 0.5 - Vector2(5, 5)
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sp.modulate.a = 0.0
			sp.draw.connect(func(): sp.draw_circle(Vector2(5, 5), 5.0, light, true, -1.0, true))
			slot.add_child(sp)
			sparks.append(sp)
		var ic := TextureRect.new()
		ic.texture = Game.icon(kind)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var isz := (SLOT - 8.0) * float(Game.ICON_OPTICAL.get(kind, 1.0))
		ic.size = Vector2(isz, isz)
		ic.position = (Vector2(SLOT, SLOT) - ic.size) * 0.5
		ic.pivot_offset = ic.size * 0.5
		ic.modulate = Color(light, 0.0) if ok else Color(1, 1, 1, 0.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
		var cap := Label.new()
		cap.text = String(goals[k][1])
		cap.add_theme_font_size_override("font_size", 24)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.position = Vector2(cx - ITEM_W * 0.5, gy + SLOT + 16)
		cap.size = Vector2(ITEM_W, 34)
		cap.modulate.a = 0.0
		overlay.add_child(cap)
		tw.tween_callback(func():
			if ok:
				ic.scale = Vector2.ONE * 2.6
				ic.rotation = deg_to_rad(-14.0)
				var st := ic.create_tween().set_speed_scale(speed[0]).set_parallel()
				st.tween_property(ic, "modulate:a", 1.0, 0.25)
				st.tween_property(ic, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				st.tween_property(ic, "rotation", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				ic.scale = Vector2.ONE * 1.5
				var st := ic.create_tween().set_speed_scale(speed[0]).set_parallel()
				st.tween_property(ic, "modulate:a", 0.28, 0.3)
				st.tween_property(ic, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT)
				var sh := ic.create_tween().set_speed_scale(speed[0])
				sh.tween_interval(0.35)
				for dx in [-10.0, 9.0, -5.0, 0.0]:
					sh.tween_property(ic, "position:x", (SLOT - ic.size.x) * 0.5 + dx, 0.07))
		tw.tween_interval(0.3)
		tw.tween_callback(func():
			Sfx.stamp(ok)
			cap.create_tween().set_speed_scale(speed[0]).tween_property(cap, "modulate:a", 1.0 if ok else 0.5, 0.3)
			if ok:
				Game.vibrate(20)
				ring.create_tween().set_speed_scale(speed[0]).tween_method(func(v: float):
					ring.set_meta("k", v)
					ring.queue_redraw(), 0.0, 1.0, 0.7)
				for d in 6:
					var sp: Control = sparks[d]
					var dir := Vector2.from_angle(TAU * d / 6.0 - PI * 0.5)
					sp.modulate.a = 1.0
					var ss := sp.create_tween().set_speed_scale(speed[0]).set_parallel()
					ss.tween_property(sp, "position", sp.position + dir * 80.0, 0.6).set_ease(Tween.EASE_OUT)
					ss.tween_property(sp, "modulate:a", 0.0, 0.6))
		tw.tween_interval(0.3)

	# Daylight bar: the whole day of this lake. Gold up to this run's time (label above, gold),
	# a white tick at the best time (label below, white). A new best puts "NEW BEST" under the gold mark.
	const BAR_W := 475.0
	var bx := (view_size.x - BAR_W) * 0.5
	var by := view_size.y * 0.58
	var day := maxf(1.0, duration)
	var now_f := clampf(run_time / day, 0.02, 1.0)
	var new_best := prev_best <= 0.0 or run_time < prev_best
	var best_t := run_time if new_best else prev_best
	var best_f := clampf(best_t / day, 0.02, 1.0)
	var bar := Control.new()
	bar.position = Vector2(bx, by)
	bar.size = Vector2(BAR_W, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta("f", 0.0)
	bar.draw.connect(func():
		var f: float = bar.get_meta("f")
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_W, 12)), Color(1, 1, 1, 0.16))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_W * now_f * f, 12)), light)
		if not new_best:
			bar.draw_rect(Rect2(Vector2(BAR_W * best_f - 2.0, -10), Vector2(4, 32)), Color(1, 1, 1, 0.95 * f))
		var tip := Vector2(BAR_W * now_f * f, -8)
		bar.draw_colored_polygon(PackedVector2Array([tip + Vector2(-9, -12), tip + Vector2(9, -12), tip]), Color(light, f)))
	bar.modulate.a = 0.0
	overlay.add_child(bar)
	var sun := TextureRect.new()
	sun.texture = Game.icon("sun")
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sun.size = Vector2(34, 34)
	sun.position = Vector2(bx + BAR_W + 14, by + 6 - 17)
	sun.modulate = Color(1, 1, 1, 0.5)
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.visible = false
	overlay.add_child(sun)
	var mk_label := func(text: String, small: String, x: float, y: float, col: Color) -> HBoxContainer:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sl := Label.new()
		sl.text = small
		sl.add_theme_font_override("font", Game.heading_font)
		sl.add_theme_font_size_override("font_size", 20)
		sl.add_theme_color_override("font_color", Color(col, 0.75))
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sl)
		var vl := Label.new()
		vl.text = text
		vl.add_theme_font_size_override("font_size", 34)
		vl.add_theme_color_override("font_color", col)
		h.add_child(vl)
		overlay.add_child(h)
		h.reset_size()
		h.position = Vector2(clampf(x - h.size.x * 0.5, 30.0, view_size.x - 30.0 - h.size.x), y)
		h.modulate.a = 0.0
		return h
	var time_l: HBoxContainer = mk_label.call("%d s" % roundi(run_time), "TIME", bx + BAR_W * now_f, by - 72, light)
	var best_l: HBoxContainer
	if new_best:
		best_l = mk_label.call("", "NEW BEST", bx + BAR_W * now_f, by + 26, light)
	else:
		best_l = mk_label.call("%d s" % roundi(best_t), "BEST", bx + BAR_W * best_f, by + 26, Color.WHITE)
	tw.tween_callback(func():
		sun.visible = true
		bar.create_tween().set_speed_scale(speed[0]).tween_property(bar, "modulate:a", 1.0, 0.2)
		bar.create_tween().set_speed_scale(speed[0]).tween_method(func(v: float):
			bar.set_meta("f", v)
			bar.queue_redraw(), 0.0, 1.0, 0.6).set_ease(Tween.EASE_OUT))
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		time_l.create_tween().set_speed_scale(speed[0]).tween_property(time_l, "modulate:a", 1.0, 0.25)
		best_l.create_tween().set_speed_scale(speed[0]).tween_property(best_l, "modulate:a", 1.0, 0.25))
	tw.tween_interval(0.3)

	# Tap for the next lake.
	var arrow := TextureRect.new()
	arrow.texture = Game.icon("next")
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.size = Vector2(80, 80)
	arrow.position = Vector2(view_size.x * 0.5 - 40, view_size.y * 0.69 - 40)
	arrow.modulate = Color(light, 0.0)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(arrow)
	var tap := Label.new()
	tap.text = "TAP TO CONTINUE" if last else "TAP FOR NEXT LAKE"
	tap.add_theme_font_override("font", Game.title_font)
	tap.add_theme_font_size_override("font_size", 26)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.position = Vector2(0, view_size.y * 0.75)
	tap.size = Vector2(view_size.x, 40)
	tap.modulate.a = 0.0
	overlay.add_child(tap)
	tw.tween_callback(func():
		can_continue[0] = true
		tap.create_tween().set_speed_scale(speed[0]).tween_property(tap, "modulate:a", 0.8, 0.3)
		var nudge := arrow.create_tween().set_loops()
		nudge.tween_property(arrow, "position:x", arrow.position.x + 14.0, 0.8).set_trans(Tween.TRANS_SINE)
		nudge.tween_property(arrow, "position:x", arrow.position.x, 0.8).set_trans(Tween.TRANS_SINE)
		arrow.create_tween().set_speed_scale(speed[0]).tween_property(arrow, "modulate:a", 1.0, 0.3))

	_add_corner_buttons(overlay)
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)


## Game over for both endings. While a revive is left (an ad: patch the boat, or more daylight), a round
## gold button sits inside a ring that drains over COUNTDOWN seconds; when it runs out, or no revives are
## left, the screen turns into "tap to try again". Menu and Restart sit in the corners as everywhere else.
const COUNTDOWN := 5.0


func _show_game_over(kind: String) -> void:
	Engine.time_scale = 1.0
	state = "over"
	touches.clear()
	get_tree().paused = true
	_set_hud_visible(false)
	var light: Color = pal["light"]
	var lit := _lit_count()
	var total := lanterns.size()
	var wreck := kind == "wreck"
	if wreck:
		Game.stat_add(lake_index, "crashes")
	var can_revive := (patches_used if wreck else days_used) < MAX_REVIVES
	overlay = Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.size = view_size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	var tap_ready := [false]
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.047, 0.063, 0.74)
	dim.size = view_size
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed and tap_ready[0]:
			Sfx.tap()
			_retry())
	overlay.add_child(dim)

	var title := Label.new()
	title.text = "WRECKED" if wreck else "LIGHTS OUT"
	title.add_theme_font_override("font", Game.title_font)
	title.add_theme_font_size_override("font_size", 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, view_size.y * 0.14)
	title.size = Vector2(view_size.x, 90)
	overlay.add_child(title)
	var line := Label.new()
	if wreck:
		var lines: Array = CRASH_LINES[crash_kind]
		line.text = String(lines[randi() % lines.size()]).replace("\n", " ")
	else:
		var left := total - lit
		line.text = "The battery ran flat with %d lantern%s still waiting." % [left, "" if left == 1 else "s"]
	line.add_theme_font_size_override("font_size", 30)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.position = Vector2(60, view_size.y * 0.23)
	line.size = Vector2(view_size.x - 120, 90)
	line.modulate.a = 0.75
	overlay.add_child(line)

	# How close you got: one lantern per lantern on the lake, lit ones gold.
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 22)
	pips.position = Vector2(0, view_size.y * 0.34)
	pips.size = Vector2(view_size.x, 58)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(pips)
	for k in total:
		var pi := TextureRect.new()
		pi.texture = Game.icon("lantern")
		pi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pi.custom_minimum_size = Vector2(58, 58)
		pi.modulate = light if k < lit else Color(1, 1, 1, 0.25)
		pips.add_child(pi)
	var pip_cap := Label.new()
	pip_cap.text = "%d of %d lanterns lit" % [lit, total]
	pip_cap.add_theme_font_size_override("font_size", 24)
	pip_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pip_cap.position = Vector2(0, view_size.y * 0.415)
	pip_cap.size = Vector2(view_size.x, 34)
	pip_cap.modulate.a = 0.6
	overlay.add_child(pip_cap)

	_add_corner_buttons(overlay)
	var corner_restart: Control = overlay.get_child(overlay.get_child_count() - 1)

	# The "try again" state, shown once no revive is on offer.
	var again := Control.new()
	again.size = view_size
	again.mouse_filter = Control.MOUSE_FILTER_IGNORE
	again.modulate.a = 0.0
	overlay.add_child(again)
	var r_icon := TextureRect.new()
	r_icon.texture = Game.icon("restart")
	r_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r_icon.size = Vector2(94, 94)
	r_icon.position = Vector2(view_size.x * 0.5 - 47, view_size.y * 0.58 - 47)
	r_icon.pivot_offset = r_icon.size * 0.5
	r_icon.modulate = light
	r_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	again.add_child(r_icon)
	var tap := Label.new()
	tap.text = "TAP TO TRY AGAIN"
	tap.add_theme_font_override("font", Game.title_font)
	tap.add_theme_font_size_override("font_size", 26)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.position = Vector2(0, view_size.y * 0.66)
	tap.size = Vector2(view_size.x, 40)
	tap.modulate.a = 0.8
	again.add_child(tap)
	var show_again := func():
		if not is_instance_valid(again):
			return
		if not wreck:
			Game.record_result(lake_index, 0)
			Game.stat_fail(lake_index, lit, total)
		tap_ready[0] = true
		corner_restart.visible = false
		again.create_tween().tween_property(again, "modulate:a", 1.0, 0.3)
		var spin := r_icon.create_tween().set_loops()
		spin.tween_property(r_icon, "rotation", TAU, 2.4).as_relative()

	if not can_revive:
		show_again.call()
	else:
		# Countdown offer: ring drains around a round gold button.
		var offer := Control.new()
		offer.size = view_size
		offer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(offer)
		var cx := view_size.x * 0.5
		var cy := view_size.y * 0.57
		const RING := 245.0
		const CORE := 180.0
		var ring := Control.new()
		ring.position = Vector2(cx - RING * 0.5, cy - RING * 0.5)
		ring.size = Vector2(RING, RING)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_meta("left", 1.0)
		ring.draw.connect(func():
			var c := Vector2(RING, RING) * 0.5
			var f: float = ring.get_meta("left")
			ring.draw_arc(c, RING * 0.5 - 8.0, 0.0, TAU, 64, Color(1, 1, 1, 0.14), 12.0, true)
			if f > 0.0:
				ring.draw_arc(c, RING * 0.5 - 8.0, -PI * 0.5, -PI * 0.5 + TAU * f, 64, light, 12.0, true))
		offer.add_child(ring)
		var core := Button.new()
		core.icon = Game.icon("play")
		core.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		core.add_theme_constant_override("icon_max_width", 64)
		for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			core.add_theme_color_override(c, Color("2a1d05"))
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = light if not st.ends_with("pressed") else light.darkened(0.08)
			sb.border_color = light.darkened(0.35)
			sb.border_width_bottom = 0 if st.ends_with("pressed") else 9
			sb.set_corner_radius_all(int(CORE * 0.5))
			sb.content_margin_left = 10
			sb.content_margin_right = 0
			sb.content_margin_top = 9 if st.ends_with("pressed") else 0
			sb.content_margin_bottom = 0
			sb.anti_aliasing = true
			core.add_theme_stylebox_override(st, sb)
		core.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		core.custom_minimum_size = Vector2(CORE, CORE)
		core.size = Vector2(CORE, CORE)
		core.position = Vector2(cx - CORE * 0.5, cy - CORE * 0.5)
		offer.add_child(core)
		var ask := Label.new()
		ask.text = "Patch the boat?" if wreck else "%d s of headlight?" % int(_day_bonus())
		ask.add_theme_font_size_override("font_size", 33)
		ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ask.position = Vector2(0, view_size.y * 0.67)
		ask.size = Vector2(view_size.x, 46)
		offer.add_child(ask)
		var note := Label.new()
		var left_n := MAX_REVIVES - (patches_used if wreck else days_used)
		note.text = "Watch a short ad  ·  %d of %d left" % [left_n, MAX_REVIVES]
		note.add_theme_font_size_override("font_size", 22)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.position = Vector2(0, view_size.y * 0.67 + 46)
		note.size = Vector2(view_size.x, 32)
		note.modulate.a = 0.55
		offer.add_child(note)
		var drain := offer.create_tween()
		drain.tween_method(func(v: float):
			ring.set_meta("left", v)
			ring.queue_redraw(), 1.0, 0.0, COUNTDOWN)
		drain.tween_callback(func():
			var fade := offer.create_tween()
			fade.tween_property(offer, "modulate:a", 0.0, 0.25)
			fade.tween_callback(offer.queue_free)
			show_again.call())
		core.pressed.connect(func():
			drain.kill()
			Sfx.tap()
			if wreck:
				_patch_boat()
			else:
				_take_daylight())

	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)


func _take_daylight() -> void:
	state = "play"
	_close_overlay()
	day_taken = true
	days_used += 1
	battery = _day_bonus()  # a fresh charge for the headlight
	battery_max = battery
	Game.stat_add(lake_index, "revives")
	_float("+%d s of headlight" % int(_day_bonus()), boat_pos - Vector2(0, 40))
	Sfx.chime(float(lake["pitch"]) * 1.5)


## The ad's headlight time: a quarter of the lake's time, plus 5 s.
func _day_bonus() -> float:
	return roundf(duration * DAY_BONUS) + 5.0


## Put the boat back where it was a moment before the crash, facing away from it.
func _patch_boat() -> void:
	patches_used += 1
	if boat3d:
		boat3d.reset()
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
	_set_hud_visible(true)
	touches.clear()
	get_tree().paused = false


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


func _setting(key: String) -> bool:
	match key:
		"sound": return Game.sound_on
		"music": return Game.music_on
	return Game.vibration_on
