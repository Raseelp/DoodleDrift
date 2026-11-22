extends Node2D
## Firefly Swarm (MVP). You are a swarm of fireflies in a moonlit glade. Drag to steer it. Sweep up loose
## fireflies to grow; touch a smaller swarm and it streams into yours; touch a bigger one and yours is
## taken. AI swarms roam, gather, chase and flee. Your size is your score.

signal home_requested
signal again_requested

const DrawNode = preload("res://scripts/draw_node.gd")
const LandShader = preload("res://scripts/land.gdshader")
const WaterShader = preload("res://scripts/water.gdshader")

const ARENA := 1800.0  # radius of the glade
const FREE_COUNT := 800  # loose fireflies kept on the meadow
const BOTS := 18
const START := 10
const VIS_CAP := 150  # most fireflies drawn per swarm (the count can go higher)
const EAT_RATIO := 1.12  # bigger by this much to take another swarm
const SAVE := "user://swarm.cfg"
const SAFE_START := 3.0  # seconds at the start when no swarm can take yours
# Dash: a burst of speed that shakes a few fireflies loose behind.
const DASH_TIME := 0.6
const DASH_MULT := 1.8
const DASH_COOL := 2.0
const DASH_MIN := 15
# Split: half the swarm shoots ahead as a second swarm of yours; the two join back up after a while.
const SPLIT_MIN := 30
const SPLIT_LAUNCH := 900.0  # its starting extra speed (fades fast: it flies about 250 px)
const MERGE_AFTER := 8.0
const SPLIT_COOL := 14.0  # from one split to the next
const COLORS := [Color("ffd25a"), Color("8cff7a"), Color("6fe3ff"), Color("ff7ad9"), Color("b49bff"),
	Color("ffa04a"), Color("e8f6ff"), Color("ff6a6a"), Color("5affc8")]
const NAMES := ["You", "Moss", "Brook", "Bramble", "Willow", "Ember", "Frost", "Thistle", "Fern", "Reed",
	"Hollow", "Cinder", "Drift", "Pebble", "Rowan", "Sorrel", "Mire", "Glimmer", "Wick"]

var rng := RandomNumberGenerator.new()
var view := Vector2.ZERO
var clock := 0.0
var state := "play"  # play, gone, summary

# The glade
var ponds: Array = []  # PackedVector2Array outlines
var stones: Array = []  # {c, r}
var pads: Array = []  # {p, r, a}
var reeds: Array = []  # {p, h, a}
var trees: Array = []  # {p, r}

# Fireflies
var free_p := PackedVector2Array()
var free_ph := PackedFloat32Array()
var swarms: Array = []  # {name, col, c (centre), dir, count, mp (members), ph, alive, bot, aim, aim_t, kills}
var you: Dictionary  # your biggest part (a split makes two)
var you_grp := 0  # every part of a swarm shares its group number
var you_kills := 0
var next_grp := 0
var best_size := 0
var alive_t := 0.0

# Thumb steering: the stick appears where a thumb goes down and stays there while it's held; the swarm
# heads the way the thumb is from that spot. Lift and press somewhere else to move the stick.
const STICK := 70.0  # the stick's radius (the knob stops at its edge; the thumb can go further)
var touch_on := false
var touch_at := Vector2.ZERO
var touch_from := Vector2.ZERO
var stick_id := -1  # which finger holds the stick (the other can press the buttons)
var dash_btn: Button
var split_btn: Button
var cam: Camera2D
var light: Node2D
var hud: Node2D
var ui: CanvasLayer
var overlay: Control
var glow: Texture2D
var _dot: Texture2D


func _ready() -> void:
	rng.randomize()
	view = get_viewport_rect().size
	glow = Game.glow_tex
	_make_glade()
	_build()
	you = _new_swarm(0, _spawn_point(), START, false)
	you_grp = int(you["grp"])
	for k in BOTS:
		_new_swarm(k + 1, _spawn_point(), rng.randi_range(START, 35), true)
	for k in FREE_COUNT:
		_add_free(_random_spot())
	Sfx.start_ambience(1.0)


# ---------------------------------------------------------------- the glade

func _make_glade() -> void:
	for k in 4:
		var c := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(300, ARENA - 500)
		var r := rng.randf_range(150, 300)
		var pts := PackedVector2Array()
		for i in 10:
			pts.append(c + Vector2.from_angle(TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)) * r * rng.randf_range(0.7, 1.2))
		var poly := Game.smooth_closed(pts, 5)
		ponds.append(poly)
		for i in 12:
			var pp := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r * 0.8
			if Geometry2D.is_point_in_polygon(pp, poly):
				pads.append({"p": pp, "r": rng.randf_range(10, 22), "a": rng.randf() * TAU})
		for i in 26:
			var e := poly[rng.randi() % poly.size()]
			reeds.append({"p": e + (e - c).normalized() * rng.randf_range(-6, 14), "h": rng.randf_range(14, 30), "a": rng.randf() * TAU})
	for k in 30:
		var c := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (ARENA - 150)
		if c.length() < 200.0:
			continue
		stones.append({"c": c, "r": rng.randf_range(24, 62)})
	for k in 900:
		var a := rng.randf() * TAU
		var d := ARENA + rng.randf_range(-40, 700)
		var p := Vector2.from_angle(a) * d
		trees.append({"p": p, "r": rng.randf_range(26, 52)})


func _random_spot() -> Vector2:
	for k in 20:
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (ARENA - 60)
		if not _in_stone(p):
			return p
	return Vector2.ZERO


func _spawn_point() -> Vector2:
	for k in 30:
		var p := _random_spot()
		var clear := true
		for s in swarms:
			# Clear of everyone, and well clear of the player (new arrivals don't drop in on top of you).
			var room := 600.0 if s == you else 260.0
			if s["alive"] and Vector2(s["c"]).distance_to(p) < room:
				clear = false
				break
		if clear:
			return p
	return _random_spot()


func _in_stone(p: Vector2) -> bool:
	for st in stones:
		if p.distance_squared_to(st["c"]) < pow(float(st["r"]), 2.0):
			return true
	return false


# ---------------------------------------------------------------- nodes

func _build() -> void:
	var ground := Polygon2D.new()
	var e := ARENA + 1200.0
	ground.polygon = PackedVector2Array([Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)])
	var lm := ShaderMaterial.new()
	lm.shader = LandShader
	lm.set_shader_parameter("base", Color("223530"))
	lm.set_shader_parameter("dark", Color("1a2a26"))
	ground.material = lm
	add_child(ground)
	var deco := DrawNode.new()  # ponds, pads, reeds, stones: drawn once
	deco.draw_fn = _draw_glade
	add_child(deco)
	for poly in ponds:
		var rip := Polygon2D.new()
		rip.polygon = poly
		var wm := ShaderMaterial.new()
		wm.shader = WaterShader
		wm.set_shader_parameter("tint", Color(0.7, 0.85, 1.0))
		wm.set_shader_parameter("strength", 0.07)
		rip.material = wm
		add_child(rip)
	# The forest round the glade, in blocks so the ones off screen are skipped.
	var blocks := {}
	for t in trees:
		var key := Vector2i(floori(t["p"].x / 700.0), floori(t["p"].y / 700.0))
		if not blocks.has(key):
			blocks[key] = []
		blocks[key].append(t)
	for key in blocks:
		var tn := DrawNode.new()
		tn.draw_fn = _draw_trees.bind(blocks[key])
		add_child(tn)
	light = DrawNode.new()  # every firefly, light added on top of the night
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light.material = add
	light.draw_fn = _draw_light
	add_child(light)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
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
	# The moves, for the right thumb: Dash in the corner, Split above and to its left.
	dash_btn = _round_button("DASH", Vector2(view.x - 112, view.y - 150), 74.0)
	dash_btn.button_down.connect(func(): _dash_group(you_grp))
	root.add_child(dash_btn)
	split_btn = _round_button("SPLIT", Vector2(view.x - 252, view.y - 236), 58.0)
	split_btn.button_down.connect(func(): _split(you))
	root.add_child(split_btn)


func _round_button(text: String, centre: Vector2, r: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(r, r) * 2.0
	b.position = centre - Vector2(r, r)
	b.add_theme_font_override("font", Game.title_font)
	b.add_theme_font_size_override("font_size", 22 if r > 60.0 else 18)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(int(r))
		box.bg_color = Color(0.05, 0.09, 0.08, 0.55) if st != "pressed" else Color(1.0, 0.85, 0.4, 0.45)
		box.border_color = Color(1, 1, 1, 0.35)
		box.set_border_width_all(2)
		b.add_theme_stylebox_override(st, box)
	return b


func _top() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return maxf(0.0, float(DisplayServer.get_display_safe_area().position.y) * view.y / float(win.y))


# ---------------------------------------------------------------- swarms

func _new_swarm(idx: int, at: Vector2, n: int, bot: bool) -> Dictionary:
	var s := {"name": NAMES[idx % NAMES.size()], "col": COLORS[idx % COLORS.size()], "c": at,
		"dir": rng.randf() * TAU, "count": n, "mp": PackedVector2Array(), "ph": PackedFloat32Array(),
		"alive": true, "bot": bot, "aim": at, "aim_t": 0.0, "kills": 0, "idx": idx, "vel": Vector2.ZERO,
		"pers": ["hunter", "shy", "shy", "grazer"][rng.randi() % 4], "alert": 0.0, "react": rng.randf_range(0.2, 0.7),
		"grp": next_grp, "boost": 0.0, "dash_until": -1.0, "dash_ready": 0.0, "split_ready": 0.0, "merge_at": -1.0}
	next_grp += 1
	if s["pers"] == "grazer":
		s["react"] = rng.randf_range(0.5, 1.0)
	for k in mini(n, VIS_CAP):
		s["mp"].append(at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0, 30))
		s["ph"].append(rng.randf() * TAU)
	swarms.append(s)
	return s


## Every live part of a group (a swarm, or the two halves of a split one).
func _parts(grp: int) -> Array:
	return swarms.filter(func(o): return o["alive"] and int(o["grp"]) == grp)


func _group_count(grp: int) -> int:
	var t := 0
	for o in _parts(grp):
		t += int(o["count"])
	return t


func _radius(n: int) -> float:
	return 8.0 * sqrt(float(n)) + 10.0


## Small swarms are much quicker than big ones, so they can always outrun a hunter: about 300 px/s at
## 10 fireflies, 210 at 50, 155 at 200, 120 at 600.
func _speed(n: int) -> float:
	return clampf(300.0 * pow(10.0 / float(maxi(n, 1)), 0.22), 110.0, 300.0)


func _add_free(p: Vector2) -> void:
	free_p.append(p)
	free_ph.append(rng.randf() * TAU)


func _grow(s: Dictionary, from: Vector2, n: int) -> void:
	s["count"] = int(s["count"]) + n
	for k in n:
		if s["mp"].size() < VIS_CAP:
			s["mp"].append(from)
			s["ph"].append(rng.randf() * TAU)


func _shrink(s: Dictionary, n: int) -> PackedVector2Array:
	var gone := PackedVector2Array()
	n = mini(n, int(s["count"]))
	s["count"] = int(s["count"]) - n
	# Drawn fireflies leave too, once the count drops below how many are drawn.
	while s["mp"].size() > mini(int(s["count"]), VIS_CAP):
		gone.append(s["mp"][s["mp"].size() - 1])
		s["mp"].remove_at(s["mp"].size() - 1)
		s["ph"].remove_at(s["ph"].size() - 1)
	return gone


# ---------------------------------------------------------------- moves

func _can_dash(s: Dictionary) -> bool:
	return state != "summary" and s["alive"] and int(s["count"]) >= DASH_MIN and clock >= float(s["dash_ready"])


## Dash every part of a group at once (your button dashes both halves of a split swarm).
func _dash_group(grp: int) -> void:
	if not you["alive"] and grp == you_grp:
		return
	var any := false
	for part in _parts(grp):
		if _can_dash(part):
			_dash(part)
			any = true
	if any and grp == you_grp:
		Sfx.boost(1.0)
		Game.vibrate(15)


func _dash(s: Dictionary) -> void:
	s["dash_until"] = clock + DASH_TIME
	s["dash_ready"] = clock + DASH_COOL
	# A few fireflies shake loose behind: free for anyone to grab.
	var shed := maxi(2, roundi(float(s["count"]) * 0.05))
	var back := Vector2(s["c"]) - Vector2.from_angle(float(s["dir"])) * _radius(int(s["count"]))
	var moved := _shrink(s, shed)
	for k in shed:
		var at := moved[k] if k < moved.size() else back
		_add_free(at + Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18)))


func _can_split(s: Dictionary) -> bool:
	return state != "summary" and s["alive"] and int(s["count"]) >= SPLIT_MIN and clock >= float(s["split_ready"]) \
		and _parts(int(s["grp"])).size() == 1


## Half the swarm shoots ahead in the way it's heading as a second swarm of the same group; both join
## back up after MERGE_AFTER seconds.
func _split(s: Dictionary) -> void:
	if not _can_split(s):
		return
	var half := int(s["count"]) / 2
	var b := s.duplicate()
	b["count"] = half
	b["kills"] = 0
	s["count"] = int(s["count"]) - half
	var mp: PackedVector2Array = s["mp"]
	var ph: PackedFloat32Array = s["ph"]
	var keep := mini(int(s["count"]), VIS_CAP)
	var go := mini(half, mp.size() - mini(keep, mp.size()))
	go = maxi(go, mini(half, mp.size() / 2))
	b["mp"] = mp.slice(mp.size() - go)
	b["ph"] = ph.slice(ph.size() - go)
	s["mp"] = mp.slice(0, mp.size() - go)
	s["ph"] = ph.slice(0, ph.size() - go)
	b["c"] = Vector2(s["c"]) + Vector2.from_angle(float(s["dir"])) * _radius(half)
	b["boost"] = SPLIT_LAUNCH
	for part in [s, b]:
		part["merge_at"] = clock + MERGE_AFTER
		part["split_ready"] = clock + SPLIT_COOL
	swarms.append(b)
	if int(s["grp"]) == you_grp:
		Sfx.loop_closed(1.0)
		Game.vibrate(20)


## Halves whose time is up drift together and join once they touch.
func _merges(delta: float) -> void:
	var seen := {}
	for a in swarms:
		if not a["alive"] or seen.has(int(a["grp"])):
			continue
		var parts := _parts(int(a["grp"]))
		seen[int(a["grp"])] = true
		if parts.size() < 2:
			if parts.size() == 1:
				parts[0]["merge_at"] = -1.0
			continue
		var p0: Dictionary = parts[0]
		var p1: Dictionary = parts[1]
		if clock < float(p0["merge_at"]):
			continue
		var d := Vector2(p0["c"]).distance_to(p1["c"])
		var big: Dictionary = p0 if int(p0["count"]) >= int(p1["count"]) else p1
		var small: Dictionary = p1 if big == p0 else p0
		if d < _radius(int(big["count"])) * 0.9:
			big["count"] = int(big["count"]) + int(small["count"])
			big["kills"] = int(big["kills"]) + int(small["kills"])
			for k in small["mp"].size():
				if big["mp"].size() < VIS_CAP:
					big["mp"].append(small["mp"][k])
					big["ph"].append(small["ph"][k])
			small["alive"] = false
			small["merged"] = true
			if small == you:
				you = big
		else:
			# Drawn together.
			var pull := (Vector2(big["c"]) - Vector2(small["c"])).normalized() * 160.0 * delta
			small["c"] = Vector2(small["c"]) + pull
			big["c"] = Vector2(big["c"]) - pull * 0.4


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	clock += delta
	if state == "play":
		alive_t += delta
		_steer_you()
	for s in swarms:
		if s["alive"]:
			if s["bot"]:
				_think(s, delta)
			_fly(s, delta)
	_collect()
	_contacts(delta)
	_merges(delta)
	_refill(delta)
	_follow(delta)
	light.queue_redraw()
	hud.queue_redraw()
	if state == "gone" and clock - float(you.get("gone_t", clock)) > 1.6:
		_show_summary()


func _steer_you() -> void:
	var d := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if touch_on:
		d = touch_at - touch_from
	if d.length() > 8.0:
		for part in _parts(you_grp):
			part["dir"] = rotate_toward(float(part["dir"]), d.angle(), 9.0 * get_process_delta_time())
	if Input.is_action_just_pressed("ui_accept"):
		_dash_group(you_grp)
	if Input.is_action_just_pressed("ui_select"):
		_split(you)


func _unhandled_input(event: InputEvent) -> void:
	# The stick belongs to one finger, put down on the left part of the screen; the right is for the moves.
	if event is InputEventScreenTouch:
		if event.pressed and stick_id < 0 and event.position.x < view.x * 0.62:
			stick_id = event.index
			touch_on = true
			touch_at = event.position
			touch_from = event.position
		elif not event.pressed and event.index == stick_id:
			stick_id = -1
			touch_on = false
	elif event is InputEventScreenDrag and event.index == stick_id:
		touch_at = event.position


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		if state == "play" and overlay == null:
			_pause()


## A swarm's queen flies on; each firefly drifts to its own place round her, a little behind as she
## turns, twinkling, and flows round stones.
func _fly(s: Dictionary, delta: float) -> void:
	var n := int(s["count"])
	var c: Vector2 = s["c"]
	var spd := _speed(n) * (DASH_MULT if clock < float(s["dash_until"]) else 1.0) + float(s["boost"])
	s["boost"] = float(s["boost"]) * exp(-3.5 * delta)
	var np := c + Vector2.from_angle(float(s["dir"])) * spd * delta
	# The glade's edge turns it back; stones it slides round.
	if np.length() > ARENA - 20.0:
		np = np.normalized() * (ARENA - 20.0)
		s["dir"] = lerp_angle(float(s["dir"]), (-np).angle(), 0.2)
	for st in stones:
		var d: Vector2 = np - Vector2(st["c"])
		var rr := float(st["r"]) + 6.0
		if d.length() < rr:
			np = Vector2(st["c"]) + d.normalized() * rr
	s["vel"] = (np - c) / maxf(delta, 0.0001)
	s["c"] = np
	# Far off screen: only the queen moves; her fireflies catch up when she comes into view.
	var half := view * 0.5 / cam.zoom.x + Vector2(300, 300)
	if absf(np.x - cam.position.x) > half.x or absf(np.y - cam.position.y) > half.y:
		return
	var near_stones: Array = []
	for st in stones:
		if np.distance_to(st["c"]) < float(st["r"]) + _radius(n) + 60.0:
			near_stones.append(st)
	var mp: PackedVector2Array = s["mp"]
	var ph: PackedFloat32Array = s["ph"]
	var m := mp.size()
	var rad := _radius(n)
	var k_follow := 1.0 - exp(-(2.2 if clock < float(s["dash_until"]) or float(s["boost"]) > 60.0 else 5.0) * delta)  # stretched into a streak while dashing
	for i in m:
		var a := float(i) * 2.39996
		var rr := rad * sqrt((float(i) + 0.5) / float(maxi(m, 1)))
		var tgt := np + Vector2.from_angle(a + clock * 0.3) * rr + Vector2(sin(clock * 1.7 + ph[i]), cos(clock * 1.3 + ph[i] * 1.7)) * 7.0
		var p := mp[i].lerp(tgt, k_follow)
		for st in near_stones:
			var d: Vector2 = p - Vector2(st["c"])
			var r2 := float(st["r"]) + 3.0
			if d.length_squared() < r2 * r2:
				p = Vector2(st["c"]) + d.normalized() * r2
		mp[i] = p
	s["mp"] = mp


## Bots, built on the rules the well-known agar-style bots use, with a personality each:
##  - hunter: hunts smaller swarms from far off and leads its target (aims where it will be), slow to scare;
##  - shy: hunts too, but breaks off and runs the moment something bigger comes close;
##  - grazer: only gathers loose fireflies, and runs from anything bigger.
## Each notices a threat only after a short reaction time, so a swarm can be caught off guard; running, it
## picks the way with the most room from every threat, the glade's edge and the stones, with a little
## panic in its line. With nothing to chase or flee it heads for the richest patch of loose fireflies,
## some of them drifting towards where you are, so the action happens on your screen.
func _think(s: Dictionary, delta: float) -> void:
	var c: Vector2 = s["c"]
	var n := int(s["count"])
	var pers: String = s["pers"]
	var see := 520.0 if pers == "hunter" else 420.0
	var shy_r := (240.0 if pers == "hunter" else 360.0 if pers == "shy" else 330.0)
	var threats: Array = []
	var prey: Dictionary = {}
	var prey_score := 0.0
	for o in swarms:
		if o == s or not o["alive"] or int(o["grp"]) == int(s["grp"]) or (int(o["grp"]) == you_grp and alive_t < SAFE_START):
			continue
		var on := int(o["count"])
		var oc: Vector2 = o["c"]
		var d := c.distance_to(oc)
		if on > n * EAT_RATIO and d < shy_r + _radius(on):
			threats.append(o)
		elif pers != "grazer" and n > on * EAT_RATIO and d < see:
			var prize := 1.6 if int(o["grp"]) == you_grp and on > 30 else 1.0  # the player becomes the prize once grown a bit
			var score := float(on) / (d + 80.0) * prize
			if score > prey_score:
				prey_score = score
				prey = o
	# A moment before a threat registers (and longer for a calm grazer).
	if threats.is_empty():
		s["alert"] = 0.0
	else:
		s["alert"] = float(s["alert"]) + delta
	var want: float
	if not threats.is_empty() and float(s["alert"]) >= float(s["react"]):
		want = _escape(s, threats)
		want += sin(clock * 7.0 + float(s["idx"])) * 0.25  # a little panic in the line
		# Dash away only when it's really close (dashing costs fireflies).
		var near_t := INF
		for t in threats:
			near_t = minf(near_t, c.distance_to(t["c"]) - _radius(int(t["count"])))
		if near_t < 90.0 and _can_dash(s) and clock >= float(s.get("move_t", 0.0)):
			s["move_t"] = clock + 1.0  # weighs up a move at most once a second
			if rng.randf() < 0.4:
				_dash(s)
	elif not prey.is_empty():
		# Lead the target: aim where it will be by the time this swarm gets there.
		var pc: Vector2 = prey["c"]
		var lead := c.distance_to(pc) / maxf(_speed(n), 1.0)
		var aim := pc + Vector2(prey.get("vel", Vector2.ZERO)) * minf(lead, 1.2)
		want = (aim - c).angle()
		_bot_moves(s, prey, aim)
	else:
		s["aim_t"] = float(s["aim_t"]) - delta
		if float(s["aim_t"]) <= 0.0 or c.distance_to(s["aim"]) < 50.0:
			s["aim_t"] = rng.randf_range(2.0, 4.0)
			s["aim"] = _forage_spot(s)
		want = (Vector2(s["aim"]) - c).angle()
	# Keep off the glade's edge.
	if c.length() > ARENA - 200.0:
		want = lerp_angle(want, (-c).angle(), clampf((c.length() - (ARENA - 200.0)) / 150.0, 0.0, 0.9))
	s["dir"] = rotate_toward(float(s["dir"]), want, (4.0 if pers == "hunter" else 3.2) * delta)


## A hunter's moves, used with care: it splits only when half of it would still be clearly bigger than
## the prey, the prey is in range and straight ahead, and no other swarm nearby could take a half; it
## dashes only at prey that is close, pulling away, and well worth the fireflies it costs.
func _bot_moves(s: Dictionary, prey: Dictionary, aim: Vector2) -> void:
	var c: Vector2 = s["c"]
	var n := int(s["count"])
	var pn := int(prey["count"])
	var d := c.distance_to(prey["c"])
	var ahead := absf(wrapf((aim - c).angle() - float(s["dir"]), -PI, PI)) < 0.35
	if String(s["pers"]) == "hunter" and _can_split(s) and float(pn) * EAT_RATIO * 1.15 < n / 2 \
			and d > _radius(n) * 0.8 and d < 320.0 and ahead:
		var safe := true
		for o in swarms:
			if o["alive"] and int(o["grp"]) != int(s["grp"]) and o != prey and int(o["count"]) > (n / 2) * EAT_RATIO \
					and c.distance_to(o["c"]) < 480.0:
				safe = false
				break
		if safe:
			_split(s)
			return
	var away := Vector2(prey.get("vel", Vector2.ZERO)).dot((Vector2(prey["c"]) - c).normalized()) > 40.0
	if away and d < 240.0 and n > pn * 1.4 and _can_dash(s) and clock >= float(s.get("move_t", 0.0)):
		s["move_t"] = clock + 1.0
		if rng.randf() < 0.3:
			_dash(s)


## The way out with the most room: of 16 headings, the one that ends farthest from every threat (the
## biggest and nearest weigh most), clear of the edge and the stones.
func _escape(s: Dictionary, threats: Array) -> float:
	var c: Vector2 = s["c"]
	var best := 0.0
	var best_score := -INF
	for k in 16:
		var a := TAU * k / 16.0
		var q := c + Vector2.from_angle(a) * 140.0
		var score := 0.0
		for t in threats:
			score += q.distance_to(t["c"]) * (1.0 + float(t["count"]) / 400.0)
		if q.length() > ARENA - 60.0:
			score -= 1000.0
		if _in_stone(q):
			score -= 300.0
		score -= absf(wrapf(a - float(s["dir"]), -PI, PI)) * 20.0  # rather keep going than turn round
		if score > best_score:
			best_score = score
			best = a
	return best


## Where to graze next: the richest of a few patches of loose fireflies nearby; about a third of the
## swarms prefer patches near the player.
func _forage_spot(s: Dictionary) -> Vector2:
	var c: Vector2 = s["c"]
	var home := c
	if int(s["idx"]) % 3 == 0 and you["alive"]:
		home = Vector2(you["c"]) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(150.0, 500.0)
	var best := _random_spot()
	var best_n := -1
	for k in 6:
		var spot := home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, 520.0)
		if spot.length() > ARENA - 80.0:
			continue
		var cnt := 0
		for j in range(0, free_p.size(), 3):
			if free_p[j].distance_squared_to(spot) < 160.0 * 160.0:
				cnt += 1
		if cnt > best_n:
			best_n = cnt
			best = spot
	return best


## Loose fireflies swept up by any swarm passing over them.
func _collect() -> void:
	# Each swarm's centre and reach in flat arrays first: far cheaper than looking them up per firefly.
	var live: Array = []
	var cs := PackedVector2Array()
	var r2 := PackedFloat32Array()
	for s in swarms:
		if s["alive"]:
			live.append(s)
			cs.append(s["c"])
			var r := _radius(int(s["count"])) + 16.0  # a generous sweep, so growing comes easily
			r2.append(r * r)
	var m := cs.size()
	var i := free_p.size() - 1
	while i >= 0:
		var p := free_p[i]
		for k in m:
			if p.distance_squared_to(cs[k]) < r2[k]:
				_grow(live[k], p, 1)
				free_p.remove_at(i)
				free_ph.remove_at(i)
				break
		i -= 1


## Swarms touching: the bigger one draws the smaller in, a stream of fireflies at a time; a swarm with
## none left is gone. Close in size, they just push apart.
func _contacts(delta: float) -> void:
	for a in swarms:
		if not a["alive"]:
			continue
		for b in swarms:
			if b == a or not b["alive"] or int(b["grp"]) == int(a["grp"]):
				continue
			if int(b["grp"]) == you_grp and alive_t < SAFE_START:
				continue  # a moment's grace at the start
			var na := int(a["count"])
			var nb := int(b["count"])
			if na < nb:
				continue
			var d := Vector2(a["c"]).distance_to(b["c"])
			if d > _radius(na) + _radius(nb) * 0.75:
				continue
			if na > nb * EAT_RATIO:
				var take := maxi(1, int(ceil(float(nb) * 4.0 * delta + 0.5)))
				var moved := _shrink(b, take)
				a["count"] = int(a["count"]) + mini(take, nb)
				for p in moved:
					if a["mp"].size() < VIS_CAP:
						a["mp"].append(p)
						a["ph"].append(rng.randf() * TAU)
				if int(b["count"]) <= 0:
					_gone(b, a)
			else:
				var push := (Vector2(b["c"]) - Vector2(a["c"])).normalized() * 60.0 * delta
				b["c"] = Vector2(b["c"]) + push
				a["c"] = Vector2(a["c"]) - push


func _gone(s: Dictionary, by: Dictionary) -> void:
	s["alive"] = false
	by["kills"] = int(by["kills"]) + 1
	if int(by["grp"]) == you_grp:
		you_kills += 1
		Sfx.chime(1.4)
		Game.vibrate(25)
	if int(s["grp"]) == you_grp:
		var rest := _parts(you_grp)
		if not rest.is_empty():
			if s == you:
				you = rest[0]  # one half is lost, the other carries on
			Sfx.reject()
			Game.vibrate(40)
			return
		state = "gone"
		you["gone_t"] = clock
		you["by"] = by["name"]
		Sfx.reject()
		Game.vibrate(80)
		_save()


## Keep the meadow stocked, and new bots coming in to replace the ones taken.
func _refill(delta: float) -> void:
	while free_p.size() < FREE_COUNT:
		_add_free(_random_spot())
	var live := 0
	for s in swarms:
		if s["alive"] and s["bot"]:
			live += 1
	if live < BOTS and rng.randf() < delta * 0.5:
		_new_swarm(rng.randi_range(1, NAMES.size() - 1), _spawn_point(), rng.randi_range(START, 40), true)
	swarms = swarms.filter(func(s): return s["alive"] or s == you)
	# Your biggest part leads (the camera and the comparisons follow it).
	for part in _parts(you_grp):
		if int(part["count"]) > int(you["count"]):
			you = part
	best_size = maxi(best_size, _group_count(you_grp))


func _follow(delta: float) -> void:
	# Between all your parts, weighted by size, so both halves of a split stay in view.
	var c := Vector2.ZERO
	var w := 0.0
	for part in _parts(you_grp):
		c += Vector2(part["c"]) * float(part["count"])
		w += float(part["count"])
	c = c / w if w > 0.0 else Vector2(you["c"])
	cam.position = cam.position.lerp(c, 1.0 - exp(-delta * 4.0))
	# Zoom out as the swarm grows, so a big one still sees around it.
	var z := clampf(1.0 - 0.09 * log(float(maxi(_group_count(you_grp), START)) / float(START)), 0.55, 1.0)
	cam.zoom = cam.zoom.lerp(Vector2.ONE * z, 1.0 - exp(-delta * 1.5))


# ---------------------------------------------------------------- drawing

func _draw_glade(n: Node2D) -> void:
	for poly in ponds:
		n.draw_colored_polygon(Game.offset_largest(poly, 8.0), Color("243a33"))
		n.draw_colored_polygon(poly, Color("0d1c25"))
	for p in pads:
		n.draw_set_transform(p["p"], float(p["a"]), Vector2.ONE)
		var pts := PackedVector2Array()
		for k in 15:
			pts.append(Vector2.from_angle(0.35 + (TAU - 0.7) * k / 14.0) * float(p["r"]))
		pts.append(Vector2.ZERO)
		n.draw_colored_polygon(pts, Color("2c4a35"))
	n.draw_set_transform(Vector2.ZERO)
	for st in stones:
		var c: Vector2 = st["c"]
		var r := float(st["r"])
		n.draw_circle(c + Vector2(6, 8), r, Color(0, 0, 0, 0.3), true, -1.0, true)
		n.draw_circle(c, r, Color("3a4a4a"), true, -1.0, true)
		n.draw_circle(c + Vector2(-r * 0.2, -r * 0.25), r * 0.6, Color("4a5c58"), true, -1.0, true)
		n.draw_circle(c + Vector2(r * 0.25, -r * 0.1), r * 0.35, Color("38563f"), true, -1.0, true)  # moss
	for rd in reeds:
		var b: Vector2 = rd["p"]
		var tip := b + Vector2.from_angle(-PI * 0.5 + 0.3 * sin(float(rd["a"]))) * float(rd["h"])
		n.draw_line(b, tip, Color("4a6a40"), 2.0, true)
	# The glade's rim: the meadow darkens into the trees.
	n.draw_arc(Vector2.ZERO, ARENA + 30.0, 0.0, TAU, 128, Color(0.03, 0.06, 0.05, 0.6), 80.0, true)


func _draw_trees(n: Node2D, list: Array) -> void:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for t in list:
		_circle(verts, cols, idx, Vector2(t["p"]) + Vector2(10, 12), float(t["r"]), Color(0, 0, 0, 0.35))
	for t in list:
		_circle(verts, cols, idx, t["p"], float(t["r"]), Color("13241d"))
		_circle(verts, cols, idx, Vector2(t["p"]) + Vector2(-float(t["r"]) * 0.2, -float(t["r"]) * 0.25), float(t["r"]) * 0.6, Color("1b3226"))
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, verts, cols)


func _circle(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, c: Vector2, r: float, col: Color) -> void:
	var seg := clampi(int(r * 0.5), 10, 22)
	var base := verts.size()
	verts.append(c)
	cols.append(col)
	for k in seg:
		verts.append(c + Vector2.from_angle(TAU * k / seg) * r)
		cols.append(col)
	for k in seg:
		idx.append_array([base, base + 1 + k, base + 1 + (k + 1) % seg])


## A firefly: soft glow with a bright core, in one picture, so each one is a single sprite.
func _dot_tex() -> Texture2D:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) / 16.0
				var core := clampf((0.2 - d) / 0.08, 0.0, 1.0)
				var halo := pow(clampf(1.0 - d, 0.0, 1.0), 2.2) * 0.55
				var a := clampf(core + halo, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_dot = ImageTexture.create_from_image(img)
	return _dot


func _draw_light(n: Node2D) -> void:
	var half := view * 0.5 / cam.zoom.x + Vector2(60, 60)
	var vr := Rect2(cam.position - half, half * 2.0)
	var dot := _dot_tex()
	# Loose fireflies: pale, twinkling.
	for i in free_p.size():
		var p := free_p[i]
		if not vr.has_point(p):
			continue
		var tw := 0.35 + 0.65 * maxf(0.0, sin(clock * 2.3 + free_ph[i]))
		n.draw_texture_rect(dot, Rect2(p - Vector2(11, 11), Vector2(22, 22)), false, Color(1.0, 0.97, 0.7, tw))
	# Swarms: each firefly in its swarm's colour, the queen brighter at the heart.
	for s in swarms:
		if not s["alive"] and s != you:
			continue
		var col: Color = s["col"]
		var c: Vector2 = s["c"]
		var rad := _radius(int(s["count"]))
		if not vr.grow(rad).has_point(c):
			continue
		var fade := 1.0
		if not s["alive"]:
			fade = maxf(0.0, 1.0 - (clock - float(s.get("gone_t", clock))) / 1.2)
		n.draw_texture_rect(glow, Rect2(c - Vector2(rad, rad) * 1.7, Vector2(rad, rad) * 3.4), false, Color(col, 0.16 * fade))
		var mp: PackedVector2Array = s["mp"]
		var ph: PackedFloat32Array = s["ph"]
		var fc := col.lightened(0.25)
		for i in mp.size():
			var tw := 0.65 + 0.35 * sin(clock * 3.1 + ph[i])
			n.draw_texture_rect(dot, Rect2(mp[i] - Vector2(14, 14), Vector2(28, 28)), false, Color(fc, tw * fade))
		if s["alive"]:
			# The queen's heartbeat tells you how this swarm compares with yours: a threat's queen beats big,
			# slow and deep; a smaller swarm's flickers small and quick; one your size glows steady.
			# Its glow is tinted too, softly: green if you can take it, red if it can take you.
			var qr := 34.0
			var qa := 0.75
			var qc := col
			if int(s["grp"]) != you_grp and state == "play":
				var on := int(s["count"])
				var yn := int(you["count"])
				if on > yn * EAT_RATIO:
					var beat := pow(maxf(0.0, sin(clock * 5.5 + float(s["idx"]))), 4.0)  # a quick, strong beat
					qr = 34.0 + 40.0 * beat
					qa = 0.35 + 0.3 * beat
					qc = Color("ff5a4e")
				elif yn > on * EAT_RATIO:
					qr = 22.0 + 7.0 * sin(clock * 26.0 + float(s["idx"]))
					qa = 0.35 + 0.18 * sin(clock * 31.0 + float(s["idx"]))
					qc = Color("7dff8a")
			n.draw_texture_rect(glow, Rect2(c - Vector2(qr, qr), Vector2(qr, qr) * 2.0), false, Color(qc, qa))
			n.draw_texture_rect(dot, Rect2(c - Vector2(16, 16), Vector2(32, 32)), false, Color(1, 1, 1, 1.0))


func _draw_hud(n: Node2D) -> void:
	var font: Font = Game.heading_font
	var top := _top() + 40.0
	var n_you := _group_count(you_grp)
	var t := "%d" % n_you
	_text(n, font, t, Vector2(28, top + 14), 44, you["col"])
	_text(n, font, "fireflies", Vector2(28, top + 44), 20, Color(1, 1, 1, 0.7))
	# The top five (a split swarm counts as one), and where you stand.
	var groups := {}
	for s in swarms:
		if s["alive"]:
			var g := int(s["grp"])
			if not groups.has(g):
				groups[g] = {"name": s["name"], "col": s["col"], "count": 0, "you": g == you_grp}
			groups[g]["count"] = int(groups[g]["count"]) + int(s["count"])
	var live: Array = groups.values()
	live.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	var rank := 1
	for k in live.size():
		if live[k]["you"]:
			rank = k + 1
	var y := top + 96.0
	for k in mini(5, live.size()):
		var s: Dictionary = live[k]
		var line := "%d. %s  %d" % [k + 1, s["name"], int(s["count"])]
		_text(n, font, line, Vector2(28, y), 20, Color(s["col"], 1.0 if s["you"] else 0.75))
		y += 26.0
	if rank > 5:
		_text(n, font, "%d. You  %d" % [rank, n_you], Vector2(28, y), 20, you["col"])
	# The buttons: dim while they can't be used, with a ring filling up as the cooldown runs out.
	if dash_btn:
		var dash_ok := state == "play" and _can_dash(you)
		var split_ok := state == "play" and _can_split(you)
		dash_btn.modulate.a = 1.0 if dash_ok else 0.45
		split_btn.modulate.a = 1.0 if split_ok else 0.45
		for pair in [[dash_btn, float(you["dash_ready"]) - clock, DASH_COOL], [split_btn, float(you["split_ready"]) - clock, SPLIT_COOL]]:
			var left := float(pair[1])
			if left > 0.0:
				var b: Button = pair[0]
				var cc := b.position + b.size * 0.5
				var f := 1.0 - left / float(pair[2])
				n.draw_arc(cc, b.size.x * 0.5 + 6.0, -PI * 0.5, -PI * 0.5 + TAU * f, 48, Color(1.0, 0.85, 0.45, 0.8), 4.0, true)
	if touch_on and state == "play":
		n.draw_arc(touch_from, STICK, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 3.0, true)
		n.draw_circle(touch_from + (touch_at - touch_from).limit_length(STICK), 22.0, Color(1, 1, 1, 0.22), true, -1.0, true)
	if alive_t < 6.0 and state == "play":
		var a := 1.0 - smoothstep(4.5, 6.0, alive_t)
		for li in 2:
			var hint: String = ["Left thumb steers, right thumb moves.", "Take smaller swarms. Flee bigger ones."][li]
			var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			_text(n, font, hint, Vector2((view.x - hw) * 0.5, view.y * 0.62 + li * 34), 24, Color(1, 1, 1, a))


func _text(n: Node2D, font: Font, s: String, p: Vector2, size: int, col: Color) -> void:
	n.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.6 * col.a))
	n.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---------------------------------------------------------------- pause and summary

func _pause() -> void:
	if overlay != null or state != "play":
		return
	get_tree().paused = true
	Sfx.tap()
	overlay = _panel("PAUSED", [], [["Resume", _resume], ["Home", _home]])


func _resume() -> void:
	get_tree().paused = false
	touch_on = false
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
	var best := int(cfg.get_value("best", "size", 0))
	var lines := [
		"Taken by %s" % String(you.get("by", "?")),
		"Biggest swarm  %d%s" % [best_size, "   NEW BEST" if best_size >= best else "   best %d" % best],
		"Swarms taken  %d" % you_kills,
		"Time  %d:%02d" % [int(alive_t) / 60, int(alive_t) % 60],
	]
	overlay = _panel("SCATTERED", lines, [["Fly again", func(): again_requested.emit()], ["Home", _home]])


func _panel(title: String, lines: Array, buttons: Array) -> Control:
	var o := Control.new()
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	o.theme = Game.ui_theme
	o.size = view
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.72)
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
	t.add_theme_font_size_override("font_size", 60)
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
	cfg.set_value("best", "size", maxi(int(cfg.get_value("best", "size", 0)), best_size))
	cfg.set_value("best", "taken", maxi(int(cfg.get_value("best", "taken", 0)), you_kills))
	cfg.save(SAVE)


func _exit_tree() -> void:
	get_tree().paused = false
