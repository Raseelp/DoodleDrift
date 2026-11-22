extends Node2D
## One run on the open sea (stage 1 of the fire game). The boat leaks a line of lamp oil behind it; crossing
## that line closes a loop and lights it, and every ship inside burns. Skiffs come from every side to ram
## the boat; each ram costs health, and the run ends when the boat sinks. The sea is generated fresh each
## run: a big body of water with edges, islands, and trees on every bank.

signal home_requested
signal again_requested

const Boat3D = preload("res://scripts/boat3d.gd")
const DrawNode = preload("res://scripts/draw_node.gd")
const ShipSprites = preload("res://scripts/ship_sprites.gd")
const LandShader = preload("res://scripts/land.gdshader")
const WaterShader = preload("res://scripts/water.gdshader")

const SEA := Vector2(2600, 2600)  # the sea's box (world px); the shore is drawn inside it
const SPEED := 165.0
const TURN_RATE := 2.6
const TURN_EASE := 0.2
const MOVE_FOLLOW := 8.5
const BOAT_R := 20.0
const STERN := 32.0
const STEP := 7.0  # oil points this far apart
const OIL_START := 1100.0  # the trail's length at the start of a run (px)
const MIN_RING := 2600.0  # smaller rings (area, px²) don't light
const MAX_HP := 5
const SKIFF_R := 14.0
const SKIFF_MODEL := "res://models/Pirates/Models/GLB format/boat-row-small.glb"
const BOAT_SPRITE_SCALE := 0.29
const SAVE := "user://fire.cfg"

var pal := {"deep": Color("1d4a58"), "mid": Color("29606f"), "shallow": Color("4c8a8e"), "sand": Color("d8c697"),
	"land": Color("5b7850"), "land_dark": Color("4d6a44"), "tree": Color("3c5a40"), "tree_hi": Color("6b8c5e"),
	"fire": Color("ff8a3c"), "ember": Color("ffd27a")}

# The sea
var water := PackedVector2Array()
var inner := PackedVector2Array()
var isles: Array = []
var isle_block: Array = []
var trees: Array = []
var rng := RandomNumberGenerator.new()

# The boat
var boat_pos := SEA * 0.5
var heading := -PI * 0.5
var move_dir := -PI * 0.5
var turn_vel := 0.0
var speed := 0.0
var hp := MAX_HP
var hurt_t := -10.0
var boat3d: Boat3D
var boat_sprite: Sprite2D
var boat_shadow: Sprite2D

# The oil trail and fires
var wp := PackedVector2Array()
var oil_len := OIL_START
var fires: Array = []  # {poly, t, n}

# Ships
var skiffs: Array = []  # {p, dir, spd, burn (-1 or time it bursts)}
var skiff_art: ShipSprites
var spawn_t := 0.0

# Effects and words
var parts: Array = []  # {p, v, t, life, s, c, add}
var words: Array = []  # {text, p, t, size, col}
var shake := 0.0

# The run
var state := "play"  # play, dead, summary
var clock := 0.0
var run_t := 0.0
var burned := 0
var best_ring := 0
var touches := {}
var view := Vector2.ZERO

var cam: Camera2D
var world_fx: Node2D
var glow_fx: Node2D
var words_node: Node2D
var ui: CanvasLayer
var hud: Node2D
var overlay: Control
var _dot: Texture2D


func _ready() -> void:
	rng.randomize()
	view = get_viewport_rect().size
	_generate()
	_build()
	Sfx.start_ambience(1.0)


# ---------------------------------------------------------------- the sea

func _generate() -> void:
	# The shore: a big rough ring round the middle, smoothed.
	var coarse := PackedVector2Array()
	var c := SEA * 0.5
	var ph := rng.randf() * TAU
	for k in 28:
		var a := TAU * k / 28.0
		var r := 0.43 + 0.04 * sin(a * 3.0 + ph) + 0.03 * sin(a * 5.0 + ph * 2.0) + rng.randf_range(-0.015, 0.015)
		coarse.append(c + Vector2(cos(a) * SEA.x, sin(a) * SEA.y) * r)
	water = Game.smooth_closed(coarse, 6)
	inner = Game.offset_largest(water, -BOAT_R)
	# Islands, clear of the start, the shore and each other.
	var deep_water := Game.offset_largest(water, -270.0)
	var tries := 0
	while isles.size() < 13 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(250, SEA.x - 250), rng.randf_range(250, SEA.y - 250))
		var r := rng.randf_range(55.0, 150.0)
		if p.distance_to(c) < 320.0 or not Geometry2D.is_point_in_polygon(p, deep_water):
			continue
		var ok := true
		for isl in isles:
			if p.distance_to(isl["c"]) < r + float(isl["r"]) + 170.0:
				ok = false
				break
		if not ok:
			continue
		var pts := PackedVector2Array()
		var n := rng.randi_range(7, 10)
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.2, 0.2)
			pts.append(p + Vector2.from_angle(a) * r * rng.randf_range(0.7, 1.15))
		var poly := Game.smooth_closed(pts, 5)
		isles.append({"c": p, "r": r, "poly": poly})
		isle_block.append(Game.offset_largest(poly, BOAT_R))
	# Trees: thick round the shore outside the water, and on every island.
	var grown := Game.offset_largest(water, 40.0)
	var woods := Game.offset_largest(water, 420.0)
	tries = 0
	while trees.size() < 700 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-300, SEA.x + 300), rng.randf_range(-300, SEA.y + 300))
		if Geometry2D.is_point_in_polygon(p, grown):
			continue
		if Geometry2D.is_point_in_polygon(p, woods):
			_add_tree(p, rng.randf_range(16.0, 32.0))
	for isl in isles:
		var core := Game.offset_largest(isl["poly"], -22.0)
		for k in int(float(isl["r"]) * float(isl["r"]) / 900.0):
			var p: Vector2 = isl["c"] + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(isl["r"])
			if Geometry2D.is_point_in_polygon(p, core):
				_add_tree(p, rng.randf_range(12.0, 24.0))


func _add_tree(p: Vector2, r: float) -> void:
	for t in trees:
		if p.distance_squared_to(t["p"]) < pow((r + float(t["r"])) * 0.6, 2.0):
			return
	var parts_t: Array = [[Vector2.ZERO, r]]
	for k in rng.randi_range(0, 2):
		parts_t.append([Vector2.from_angle(rng.randf() * TAU) * r * 0.55, r * rng.randf_range(0.5, 0.75)])
	trees.append({"p": p, "r": r, "parts": parts_t})


func _free(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, inner):
		return false
	for poly in isle_block:
		if Geometry2D.is_point_in_polygon(p, poly):
			return false
	return true


# ---------------------------------------------------------------- nodes

func _build() -> void:
	var land := Polygon2D.new()
	land.polygon = PackedVector2Array([Vector2(-900, -900), Vector2(SEA.x + 900, -900), SEA + Vector2(900, 900), Vector2(-900, SEA.y + 900)])
	var lm := ShaderMaterial.new()
	lm.shader = LandShader
	lm.set_shader_parameter("base", pal["land"])
	lm.set_shader_parameter("dark", pal["land_dark"])
	land.material = lm
	add_child(land)
	var wn := DrawNode.new()
	wn.draw_fn = _draw_water
	add_child(wn)
	var ripple := Polygon2D.new()
	ripple.polygon = water
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	wm.set_shader_parameter("tint", Color.WHITE)
	wm.set_shader_parameter("strength", 0.08)
	ripple.material = wm
	add_child(ripple)
	var isn := DrawNode.new()
	isn.draw_fn = func(n: Node2D) -> void:
		for isl in isles:
			_poly(n, isl["poly"], pal["sand"])
	add_child(isn)
	for isl in isles:
		var g := Polygon2D.new()
		g.polygon = Game.offset_largest(isl["poly"], -10.0)
		g.material = lm
		add_child(g)
	world_fx = DrawNode.new()  # oil, fire on the water, ships, particles
	world_fx.draw_fn = _draw_world
	add_child(world_fx)
	boat3d = Boat3D.new()
	add_child(boat3d)
	boat_shadow = Sprite2D.new()
	boat_shadow.texture = boat3d.get_texture()
	boat_shadow.scale = Vector2.ONE * BOAT_SPRITE_SCALE
	boat_shadow.modulate = Color(0.02, 0.06, 0.08, 0.32)
	add_child(boat_shadow)
	boat_sprite = Sprite2D.new()
	boat_sprite.texture = boat3d.get_texture()
	boat_sprite.scale = Vector2.ONE * BOAT_SPRITE_SCALE
	add_child(boat_sprite)
	# Trees in 600 px blocks, so the ones off screen are skipped; drawn once.
	var blocks := {}
	for t in trees:
		var key := Vector2i(floori(t["p"].x / 600.0), floori(t["p"].y / 600.0))
		if not blocks.has(key):
			blocks[key] = []
		blocks[key].append(t)
	for key in blocks:
		var tn := DrawNode.new()
		tn.draw_fn = _draw_trees.bind(blocks[key])
		add_child(tn)
	glow_fx = DrawNode.new()  # flames, blasts and words, light added on top
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_fx.material = add
	glow_fx.draw_fn = _draw_glow
	add_child(glow_fx)
	words_node = DrawNode.new()
	words_node.draw_fn = _draw_words
	add_child(words_node)
	cam = Camera2D.new()
	cam.position = boat_pos
	add_child(cam)
	cam.make_current()
	skiff_art = ShipSprites.new()
	skiff_art.model_path = SKIFF_MODEL
	skiff_art.heading0 = PI * 0.5
	skiff_art.px = 112
	add_child(skiff_art)
	skiff_art.bake()
	_build_ui()


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.theme = Game.ui_theme
	root.size = view
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	hud = DrawNode.new()
	hud.draw_fn = _draw_hud
	root.add_child(hud)
	var pause := Game.square_button(Game.icon("pause"), 64, 26)
	pause.position = Vector2(view.x - 24 - 64, _top() + 14)
	pause.pressed.connect(_pause)
	root.add_child(pause)


func _top() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return maxf(0.0, float(DisplayServer.get_display_safe_area().position.y) * view.y / float(win.y))


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	clock += delta
	match state:
		"play":
			run_t += delta
			_steer(delta)
			_move(delta)
			_spawn(delta)
		"dead":
			speed = move_toward(speed, 0.0, 80.0 * delta)
			_move(delta)
			if clock - hurt_t > 1.8:
				_show_summary()
	_ships(delta)
	_effects(delta)
	_follow(delta)
	boat_sprite.position = boat_pos
	boat_shadow.position = boat_pos + Vector2(-12, 16)
	var sunk := boat3d.sunk()
	boat_sprite.modulate = Color(1, 1, 1, 1.0 - 0.9 * sunk)
	if state == "play" and clock - hurt_t < 0.5:
		boat_sprite.modulate = Color(1, 0.55, 0.5)  # just hit
	boat_shadow.modulate.a = 0.32 * (1.0 - sunk)
	boat3d.set_pose(move_dir, clampf(-turn_vel * 0.12, -0.25, 0.25), 0.0, sin(clock * 2.0) * 0.02)
	world_fx.queue_redraw()
	glow_fx.queue_redraw()
	hud.queue_redraw()
	words_node.queue_redraw()


func _steer(delta: float) -> void:
	var want := float(_turn_input()) * TURN_RATE
	turn_vel = move_toward(turn_vel, want, TURN_RATE / TURN_EASE * delta)
	heading += turn_vel * delta
	speed = move_toward(speed, SPEED, 140.0 * delta)


func _move(delta: float) -> void:
	move_dir = lerp_angle(move_dir, heading, 1.0 - exp(-MOVE_FOLLOW * delta))
	var np := boat_pos + Vector2.from_angle(move_dir) * speed * delta
	if not _free(np):
		# Land ahead: slide round it, turning towards the open side.
		for k in range(1, 14):
			for s in [1.0, -1.0]:
				var a: float = move_dir + s * k * 0.12
				var cand := boat_pos + Vector2.from_angle(a) * speed * delta
				if _free(cand):
					heading = lerp_angle(heading, a, 0.5)
					move_dir = a
					np = cand
					break
			if _free(np):
				break
		if not _free(np):
			speed *= 0.5
			return
		speed *= 0.97
	boat_pos = np
	if state == "play":
		_lay_oil()


func _turn_input() -> int:
	var t := 0
	if Input.is_action_pressed("ui_left"):
		t -= 1
	if Input.is_action_pressed("ui_right"):
		t += 1
	for id in touches:
		t += -1 if float(touches[id]) < view.x * 0.5 else 1
	return clampi(t, -1, 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position.x
		else:
			touches.erase(event.index)
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position.x


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		if state == "play" and overlay == null:
			_pause()


func _follow(delta: float) -> void:
	var lead := Vector2.from_angle(move_dir) * 120.0 * clampf(speed / SPEED, 0.0, 1.0)
	var want := boat_pos + lead
	var half := view * 0.5
	want.x = clampf(want.x, half.x - 200.0, SEA.x - half.x + 200.0)
	want.y = clampf(want.y, half.y - 200.0, SEA.y - half.y + 200.0)
	cam.position = cam.position.lerp(want, 1.0 - exp(-delta * 3.0))
	shake = maxf(0.0, shake - delta * 2.5)
	cam.offset = Vector2(sin(clock * 47.0), cos(clock * 39.0)) * 9.0 * shake


# ---------------------------------------------------------------- oil and fire

func _lay_oil() -> void:
	var stern := boat_pos - Vector2.from_angle(move_dir) * STERN
	if wp.size() > 0 and wp[wp.size() - 1].distance_to(stern) < STEP:
		return
	var n := wp.size()
	if n >= 6:
		var a := wp[n - 1]
		for j in range(0, n - 5):
			var x = Geometry2D.segment_intersects_segment(wp[j], wp[j + 1], a, stern)
			if x != null:
				var ring := PackedVector2Array([x])
				for k in range(j + 1, n):
					ring.append(wp[k])
				ring.append(stern)
				if absf(Game.poly_area(ring)) >= MIN_RING:
					_ignite(ring)
					wp = PackedVector2Array([stern])
					return
				break
	wp.append(stern)
	# A fixed amount of oil: the oldest end thins away as new oil leaves the boat.
	var total := 0.0
	for i in range(wp.size() - 1, 0, -1):
		total += wp[i].distance_to(wp[i - 1])
		if total > oil_len:
			wp = wp.slice(i)
			break


func _ignite(ring: PackedVector2Array) -> void:
	# The fill is the ring's outline cleaned up (a ring that crosses itself can't be filled as it is).
	fires.append({"poly": ring, "t": clock, "n": ring.size(), "fill": Geometry2D.offset_polygon(ring, 2.0, Geometry2D.JOIN_ROUND)})
	Sfx.ignite()
	Game.vibrate(25)
	var caught := 0
	var mid := Vector2.ZERO
	for q in ring:
		mid += q
	mid /= ring.size()
	for s in skiffs:
		if float(s["burn"]) < 0.0 and Geometry2D.is_point_in_polygon(s["p"], ring):
			s["burn"] = clock + 0.25 + 0.35 * clampf(Vector2(s["p"]).distance_to(ring[0]) / 400.0, 0.0, 1.0)
			caught += 1
	if caught >= 2:
		_word("×%d" % caught, mid, 58 + mini(caught, 10) * 3, pal["ember"])
		Sfx.chain(1.0, mini(caught - 1, 6))
	best_ring = maxi(best_ring, caught)


# ---------------------------------------------------------------- ships

func _spawn(delta: float) -> void:
	spawn_t -= delta
	if spawn_t > 0.0 or not skiff_art.is_ready() or skiffs.size() >= 70:
		return
	spawn_t = maxf(0.35, 2.0 - run_t * 0.012)
	var group := 1 + int(run_t / 45.0) + (1 if rng.randf() < 0.3 else 0)
	var reach := view.length() * 0.5 + 140.0
	for attempt in 12:
		var p := boat_pos + Vector2.from_angle(rng.randf() * TAU) * reach
		if not _free(p):
			continue
		for g in mini(group, 6):
			var q := p + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
			if _free(q):
				skiffs.append({"p": q, "dir": (boat_pos - q).angle(), "spd": rng.randf_range(0.9, 1.05) * minf(118.0 + run_t * 0.12, 150.0), "burn": -1.0})
		return


func _ships(delta: float) -> void:
	var keep: Array = []
	for s in skiffs:
		var p: Vector2 = s["p"]
		if float(s["burn"]) >= 0.0:
			if clock >= float(s["burn"]):
				_blast(p, 1.0)
				burned += 1
				continue
			s["dir"] = float(s["dir"]) + delta * 3.0  # burning: spinning out of control
			s["p"] = p + Vector2.from_angle(float(s["dir"])) * 30.0 * delta
			keep.append(s)
			continue
		# Chase, with a little spacing from the others, and round any land in the way.
		var want := (boat_pos - p).angle() if state == "play" else float(s["dir"]) + 0.6
		var push := Vector2.ZERO
		for o in skiffs:
			if o != s:
				var d: Vector2 = p - Vector2(o["p"])
				var l := d.length()
				if l < 34.0 and l > 0.01:
					push += d / l * (34.0 - l)
		if push != Vector2.ZERO:
			want = (Vector2.from_angle(want) + push * 0.04).angle()
		var ahead := p + Vector2.from_angle(want) * 46.0
		if not _free(ahead):
			for k in range(1, 9):
				var side := want + k * 0.35
				if _free(p + Vector2.from_angle(side) * 46.0):
					want = side
					break
				side = want - k * 0.35
				if _free(p + Vector2.from_angle(side) * 46.0):
					want = side
					break
		s["dir"] = rotate_toward(float(s["dir"]), want, 2.4 * delta)
		var np := p + Vector2.from_angle(float(s["dir"])) * float(s["spd"]) * delta
		if _free(np):
			s["p"] = np
		# Ramming the boat: it costs health, and the skiff goes down.
		if state == "play" and Vector2(s["p"]).distance_to(boat_pos) < BOAT_R + SKIFF_R:
			_hurt(Vector2(s["p"]))
			_splash(Vector2(s["p"]))
			continue
		keep.append(s)
	skiffs = keep


func _hurt(from: Vector2) -> void:
	hp -= 1
	hurt_t = clock
	shake = 1.0
	Sfx.bump()
	Game.vibrate(60)
	heading += (boat_pos - from).normalized().cross(Vector2.from_angle(move_dir)) * 0.3
	if hp <= 0:
		state = "dead"
		Sfx.crash()
		boat3d.wreck()
		wp = PackedVector2Array()
		_save()


# ---------------------------------------------------------------- effects

func _part(p: Vector2, v: Vector2, life: float, s: float, c: Color, add: bool) -> void:
	parts.append({"p": p, "v": v, "t": clock, "life": life, "s": s, "c": c, "add": add})


func _blast(p: Vector2, size: float) -> void:
	Sfx.fw_boom(size)
	shake = maxf(shake, 0.35 * size)
	for k in int(18 * size):
		_part(p, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40, 170) * size, rng.randf_range(0.4, 0.9), rng.randf_range(3, 7) * size, pal["fire"] if k % 3 else pal["ember"], true)
	for k in int(8 * size):
		_part(p, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10, 50), rng.randf_range(1.2, 2.2), rng.randf_range(8, 14) * size, Color(0.12, 0.1, 0.1, 0.5), false)
	for k in 6:
		_part(p + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)), Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 60), rng.randf_range(0.8, 1.4), rng.randf_range(2, 4), Color("8a6a48"), false)


func _splash(p: Vector2) -> void:
	for k in 14:
		_part(p, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, 110), rng.randf_range(0.4, 0.8), rng.randf_range(2, 4), Color(1, 1, 1, 0.85), false)


func _word(text: String, p: Vector2, size: int, col: Color) -> void:
	words = [{"text": text, "p": p, "t": clock, "size": size, "col": col}]  # one word at a time


func _effects(delta: float) -> void:
	var keep: Array = []
	for q in parts:
		if clock - float(q["t"]) < float(q["life"]):
			q["p"] = Vector2(q["p"]) + Vector2(q["v"]) * delta
			q["v"] = Vector2(q["v"]) * exp(-2.5 * delta)
			keep.append(q)
	parts = keep
	fires = fires.filter(func(f): return clock - float(f["t"]) < 2.6)
	words = words.filter(func(w): return clock - float(w["t"]) < 1.6)
	# Embers rising off the burning water.
	for f in fires:
		if rng.randf() < 0.6:
			var ring: PackedVector2Array = f["poly"]
			var q := ring[rng.randi() % ring.size()]
			_part(q, Vector2(rng.randf_range(-15, 15), rng.randf_range(-50, -20)), rng.randf_range(0.5, 1.0), rng.randf_range(2, 4), pal["ember"], true)


# ---------------------------------------------------------------- drawing

func _poly(n: Node2D, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() < 3:
		return
	n.draw_colored_polygon(poly, col)
	var rim := poly.duplicate()
	rim.append(poly[0])
	n.draw_polyline(rim, col, 1.4, true)


func _draw_water(n: Node2D) -> void:
	for p in Geometry2D.offset_polygon(water, 12.0, Geometry2D.JOIN_ROUND):
		_poly(n, p, pal["sand"])
	_poly(n, water, pal["shallow"])
	for p in Geometry2D.offset_polygon(water, -30.0, Geometry2D.JOIN_ROUND):
		_poly(n, p, pal["mid"])
	for p in Geometry2D.offset_polygon(water, -110.0, Geometry2D.JOIN_ROUND):
		_poly(n, p, pal["deep"])
	for isl in isles:
		for ring in [[60.0, pal["mid"]], [22.0, pal["shallow"]]]:
			for p in Geometry2D.offset_polygon(isl["poly"], float(ring[0]), Geometry2D.JOIN_ROUND):
				for q in Geometry2D.intersect_polygons(p, water):
					_poly(n, q, ring[1])


func _draw_trees(n: Node2D, list: Array) -> void:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var shadow := Color(0.15, 0.22, 0.16, 0.5)
	for t in list:
		for part in t["parts"]:
			_circle(verts, cols, idx, Vector2(t["p"]) + Vector2(part[0]) + Vector2(8, 10), float(part[1]), shadow)
	for t in list:
		for part in t["parts"]:
			_circle(verts, cols, idx, Vector2(t["p"]) + Vector2(part[0]), float(part[1]), pal["tree"])
		for part in t["parts"]:
			var r := float(part[1])
			_circle(verts, cols, idx, Vector2(t["p"]) + Vector2(part[0]) + Vector2(-r * 0.22, -r * 0.24), r * 0.62, pal["tree_hi"])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, verts, cols)


func _circle(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, c: Vector2, r: float, col: Color) -> void:
	var seg := clampi(int(r * 0.6), 10, 22)
	var base := verts.size()
	verts.append(c)
	cols.append(col)
	for k in seg:
		var d := Vector2.from_angle(TAU * k / seg)
		verts.append(c + d * (r - 0.5))
		cols.append(col)
		verts.append(c + d * (r + 0.5))
		cols.append(Color(col, 0.0))
	for k in seg:
		var a := base + 1 + k * 2
		var b := base + 1 + ((k + 1) % seg) * 2
		idx.append_array([base, a, b, a, a + 1, b + 1, a, b + 1, b])


func _dot_tex() -> Texture2D:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(16.0 - Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)), 0.0, 1.0)))
		_dot = ImageTexture.create_from_image(img)
	return _dot


func _draw_world(n: Node2D) -> void:
	# The oil: a dark sheen with a shifting rainbow edge, thin at its old end.
	var m := wp.size()
	if m >= 2:
		var pts := wp.duplicate()
		pts.append(boat_pos - Vector2.from_angle(move_dir) * STERN)
		m = pts.size()
		for pass_i in 2:
			var verts := PackedVector2Array()
			var cols := PackedColorArray()
			for i in m:
				var f := float(i) / float(m - 1)
				var w := (4.0 + 9.0 * minf(1.0, f * 3.0)) * (2.2 if pass_i == 0 else 1.0)
				var col := Color(0.08, 0.07, 0.1, 0.45) if pass_i == 0 else Color.from_hsv(fposmod(clock * 0.15 + f * 1.5, 1.0), 0.45, 1.0, 0.55)
				col.a *= minf(1.0, f * 4.0)
				var prev := pts[maxi(i - 1, 0)]
				var next := pts[mini(i + 1, m - 1)]
				var nrm := (next - prev).orthogonal().normalized() * w * 0.5
				verts.append(pts[i] + nrm)
				verts.append(pts[i] - nrm)
				cols.append(col)
				cols.append(col)
			var idx := PackedInt32Array()
			for i in m - 1:
				var b := i * 2
				idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
			RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, verts, cols)
	# Burning water inside each ring: a hot glow that fades.
	for f in fires:
		var age := clock - float(f["t"])
		var a := clampf(age / 0.35, 0.0, 1.0) * (1.0 - smoothstep(1.6, 2.6, age))
		for piece in f["fill"]:
			if Geometry2D.triangulate_polygon(piece).size() > 0:
				n.draw_colored_polygon(piece, Color(1.0, 0.45, 0.12, 0.28 * a * (0.85 + 0.15 * sin(clock * 23.0))))
	# Ships.
	for s in skiffs:
		var tex := skiff_art.frame(float(s["dir"]))
		if tex == null:
			continue
		var sz := tex.get_size() * 0.62
		var p: Vector2 = s["p"]
		n.draw_texture_rect(tex, Rect2(p - sz * 0.5 + Vector2(-6, 9), sz), false, Color(0.02, 0.06, 0.08, 0.3))
		var col := Color.WHITE
		if float(s["burn"]) >= 0.0:
			col = Color(1.0, 0.6, 0.4)
		n.draw_texture_rect(tex, Rect2(p - sz * 0.5, sz), false, col)
	for q in parts:
		if not bool(q["add"]):
			var k := (clock - float(q["t"])) / float(q["life"])
			var c: Color = q["c"]
			var s := float(q["s"]) * (1.0 + k * 0.6)
			n.draw_texture_rect(_dot_tex(), Rect2(Vector2(q["p"]) - Vector2(s, s), Vector2(s, s) * 2.0), false, Color(c, c.a * (1.0 - k)))


func _draw_glow(n: Node2D) -> void:
	var glow: Texture2D = Game.glow_tex
	# Flames racing round each ring from where it closed, then burning along it.
	for f in fires:
		var ring: PackedVector2Array = f["poly"]
		var age := clock - float(f["t"])
		var cnt := ring.size()
		var fade := 1.0 - smoothstep(1.8, 2.6, age)
		for i in range(0, cnt, 2):
			var reach := float(mini(i, cnt - i)) / maxf(1.0, cnt * 0.5)
			var lit := clampf((age - reach * 0.45) / 0.15, 0.0, 1.0)
			if lit <= 0.0:
				continue
			var fl := 0.75 + 0.25 * sin(clock * 19.0 + i * 1.7)
			var r := (14.0 + 8.0 * fl) * lit
			n.draw_texture_rect(glow, Rect2(ring[i] - Vector2(r, r * 1.3), Vector2(r * 2.0, r * 2.2)), false, Color(pal["fire"], 0.55 * fade * fl))
			n.draw_texture_rect(glow, Rect2(ring[i] - Vector2(r, r) * 0.4, Vector2(r, r) * 0.8), false, Color(pal["ember"], 0.8 * fade))
	for s in skiffs:
		if float(s["burn"]) >= 0.0:
			var r := 26.0 + 6.0 * sin(clock * 21.0)
			n.draw_texture_rect(glow, Rect2(Vector2(s["p"]) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(pal["fire"], 0.7))
	for q in parts:
		if bool(q["add"]):
			var k := (clock - float(q["t"])) / float(q["life"])
			var s := float(q["s"]) * (1.0 - k * 0.5)
			n.draw_texture_rect(glow, Rect2(Vector2(q["p"]) - Vector2(s, s) * 2.0, Vector2(s, s) * 4.0), false, Color(q["c"], 1.0 - k))


func _draw_words(n: Node2D) -> void:
	var font: Font = Game.title_font
	for w in words:
		var age := clock - float(w["t"])
		var a := minf(1.0, age * 8.0) * (1.0 - smoothstep(1.1, 1.6, age))
		var pop := 1.0 + 0.3 * exp(-age * 9.0) * cos(age * 14.0)
		var size := int(w["size"])
		var p: Vector2 = Vector2(w["p"]) - Vector2(0, 40.0 * (1.0 - exp(-age * 2.5)))
		n.draw_set_transform(p, 0.0, Vector2.ONE * pop)
		var tw := font.get_string_size(w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		n.draw_string_outline(font, Vector2(-tw * 0.5, size * 0.35), w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(0.2, 0.08, 0.02, 0.85 * a))
		n.draw_string(font, Vector2(-tw * 0.5, size * 0.35), w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(w["col"], a))
		n.draw_set_transform(Vector2.ZERO)


func _draw_hud(n: Node2D) -> void:
	var font: Font = Game.heading_font
	var top := _top() + 46.0
	# Health: one pip per hit the hull can take.
	for k in MAX_HP:
		var r := Rect2(Vector2(24 + k * 34, top - 12), Vector2(26, 24))
		n.draw_rect(r, Color(0, 0, 0, 0.45))
		if k < hp:
			n.draw_rect(r.grow(-3), Color("ff7a5a") if hp <= 2 else pal["ember"])
	var t := "%d:%02d" % [int(run_t) / 60, int(run_t) % 60]
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	n.draw_string_outline(font, Vector2((view.x - tw) * 0.5, top + 12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 6, Color(0, 0, 0, 0.6))
	n.draw_string(font, Vector2((view.x - tw) * 0.5, top + 12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	var b := "%d burned" % burned
	var bw := font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	n.draw_string_outline(font, Vector2((view.x - bw) * 0.5, top + 44), b, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 5, Color(0, 0, 0, 0.6))
	n.draw_string(font, Vector2((view.x - bw) * 0.5, top + 44), b, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, pal["ember"])
	if run_t < 6.0 and state == "play":
		var hint := "Hold left or right to steer. Cross your oil to set it alight."
		var a := 1.0 - smoothstep(4.5, 6.0, run_t)
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		n.draw_string_outline(font, Vector2((view.x - hw) * 0.5, view.y - 120), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.6 * a))
		n.draw_string(font, Vector2((view.x - hw) * 0.5, view.y - 120), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, a))


# ---------------------------------------------------------------- pause and summary

func _pause() -> void:
	if overlay != null or state != "play":
		return
	get_tree().paused = true
	Sfx.tap()
	overlay = _panel("PAUSED", [], [["Resume", _resume], ["Home", _home]])


func _resume() -> void:
	get_tree().paused = false
	touches.clear()
	if overlay:
		overlay.queue_free()
	overlay = null


func _home() -> void:
	get_tree().paused = false
	home_requested.emit()


func _show_summary() -> void:
	if state == "summary":
		return
	state = "summary"
	var cfg := _load()
	var best_t := float(cfg.get_value("best", "time", 0.0))
	var lines := [
		"Survived  %d:%02d%s" % [int(run_t) / 60, int(run_t) % 60, "   NEW BEST" if run_t >= best_t - 0.01 else "   best %d:%02d" % [int(best_t) / 60, int(best_t) % 60]],
		"Ships burned  %d" % burned,
		"Best ring  ×%d" % best_ring,
	]
	overlay = _panel("SUNK", lines, [["Sail again", func(): again_requested.emit()], ["Home", _home]])


func _panel(title: String, lines: Array, buttons: Array) -> Control:
	var o := Control.new()
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	o.theme = Game.ui_theme
	o.size = view
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.06, 0.72)
	dim.size = view
	o.add_child(dim)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.size = view
	o.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", Game.title_font)
	t.add_theme_font_size_override("font_size", 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	for l in lines:
		var lb := Label.new()
		lb.text = l
		lb.add_theme_font_size_override("font_size", 28)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(lb)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(320, 84)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 30)
		btn.pressed.connect(func():
			Sfx.tap()
			b[1].call())
		box.add_child(btn)
	ui.add_child(o)
	o.modulate.a = 0.0
	o.create_tween().tween_property(o, "modulate:a", 1.0, 0.3)
	return o


func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return cfg


func _save() -> void:
	var cfg := _load()
	cfg.set_value("best", "time", maxf(float(cfg.get_value("best", "time", 0.0)), run_t))
	cfg.set_value("best", "ring", maxi(int(cfg.get_value("best", "ring", 0)), best_ring))
	cfg.set_value("total", "burned", int(cfg.get_value("total", "burned", 0)) + burned)
	cfg.save(SAVE)


func _exit_tree() -> void:
	get_tree().paused = false
