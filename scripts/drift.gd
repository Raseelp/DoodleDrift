extends Node2D
## Doodle Drift (prototype). A toy car drifts down an endless hand-drawn road on a sheet of paper, seen from
## above. There is no ordinary steering: hold the left or right half of the screen and, after a short hold
## (dev setting), the car flicks into a drift that way; let go and the tyres grip and it straightens. Hard
## drifts scuff and then rip the paper. Stay between the lines for combos, brush past obstacles for near
## misses, pick up coins. A pencil or an eraser ends the run.
##
## Drawing is split so little is redrawn each frame: each stretch of road, and each finished skid or tear,
## is drawn once into its own node; only the marks still being made, the car and the words redraw.

signal home_requested
signal again_requested

const DrawNode = preload("res://scripts/draw_node.gd")
const Prop = preload("res://scripts/prop.gd")
const View3D = preload("res://scripts/view3d.gd")
## Cameras, switched in the game: looking down fixed north-up, looking down turning with the car, the
## same but pulling in close during drifts, and a tilted view from behind the car in 3D.
const CAMS := ["top", "follow", "close", "tilt"]
const CAM_NAMES := {"top": "Top down", "follow": "Follow", "close": "Close drift", "tilt": "Tilted chase"}
const PROP_NAMES := {"pencil_blue": "pencil", "pencil_white": "pencil", "set_square": "set square"}
## Desk objects that lie across or beside the road, and how often each turns up.
const PROP_WEIGHTS := {"pencil": 2.0, "pencil_blue": 1.5, "pencil_white": 1.5, "ruler": 1.5, "scissors": 1.2, "set_square": 1.0, "sharpener": 1.2, "eraser": 1.5, "clip": 1.0, "ring": 1.0}

## Cars: a sheet of 64 baked headings (8 x 8, first picture facing right, then clockwise).
const CARS := {
	"evo": {"name": "Red Evo", "sheet": "res://cars/evo.png", "px": 192, "model": "res://cars/evo.glb"},
}
## Papers: seamless textures, no printed lines.
const PAPERS := {
	"white": {"name": "White printer", "tex": "res://paper/white.jpg"},
	"sketch": {"name": "Cream sketch", "tex": "res://paper/sketch.jpg"},
	"kraft": {"name": "Kraft brown", "tex": "res://paper/kraft.jpg"},
	"recycled": {"name": "Recycled grey", "tex": "res://paper/recycled.jpg"},
}
const DEFAULT_HOLD := 0.15  # seconds a side is held before the car flicks into a drift

const SPEED := 235.0  # steady: the game never speeds up, so drifts stay controllable
const OFF_SPEED := 140.0  # across the line
const TURN := 2.7  # how fast the nose swings in a full drift (rad/s)
const SLIDE_TURN := 0.45  # in the light slide before a drift, the nose swings this share of TURN
const SLIDE_GRIP := 1.3  # full drift: the rear has let go and the car slides on the way it was going
const GRIP := 6.0  # gripping: the tyres pull the travel round to where the nose points
const ALIGN := 2.2  # gripping: the rear catches and swings the nose back towards the travel
const YAW_LAG := 6.0  # the car's weight: how quickly the turn rate follows what's asked (1/s)
const STEER_IN := 7.0  # a held side builds this fast (1/s) ...
const STEER_OUT := 4.0  # ... and fades this fast once let go
const DRIFT_IN := 4.5  # the slide deepens into a drift this fast (1/s) ...
const DRIFT_OUT := 1.4  # ... and the rear regains grip this slowly once let go
const CAR_LEN := 76.0
const CAR_R := 17.0
const STEP := 8.0  # road centre points this far apart
const SAVE := "user://drift.cfg"
const MARK_POINTS := 28  # a skid or tear being drawn is handed to a still node after this many points

## Kept for the whole session: the 3D car model (slow to load) and each car sheet's measured length.
static var model_cache := {}
static var car_len_px := {}

var rng := RandomNumberGenerator.new()
var view := Vector2.ZERO
var clock := 0.0
var state := "play"  # play, crashed, summary
var hold_delay := DEFAULT_HOLD

# The car
var pos := Vector2.ZERO
var heading := -PI * 0.5
var vdir := -PI * 0.5  # the way it is actually travelling
var yaw := 0.0
var speed := SPEED
var slip := 0.0
var hold_t := 0.0
var steer := 0.0  # the held side, eased: -1 left .. 1 right
var drift_amt := 0.0  # 0 gripping .. 1 full drift, eased in and out
var spin := 0.0
var crash_t := 0.0
var prev_best := 0  # best score before this run
var car_tex: Texture2D
var car_px := 192
var car_scale := 1.0

# The road: centre points, their widths, running length
var road := PackedVector2Array()
var widths := PackedFloat32Array()
var lens := PackedFloat32Array()
var road_dir := -PI * 0.5
var progress_i := 0
var history: Array = []  # the last few pieces, so none repeats too soon
var phase := 0  # the road's rhythm: calm, busy, calm, tense
var phase_left := 0.0
var style := 0  # how the edges are drawn: pencil, ballpoint, marker, crayon, dashed
var piece_w := 1.0  # the width this piece wants, against the normal width
var chunks: Array = []  # {node, end_len}: each piece of road drawn once

# On the paper
var live_skid := [null, null]  # the skid each rear wheel is drawing: {pts, a}
var live_tear := [null, null]  # {pts, w, seed}
var still_marks: Array = []  # {node, p}
var obstacles: Array = []  # drawn bits that don't block: {kind, p, a}
var props: Array = []  # desk objects with physics (prop.gd)
var prop_info := {}  # sizes from res://props/props.json
var prop_tex := {}
var crash_on_hit := true  # dev: hitting an object ends the run, or just bumps
var bump_t := -9.0
var car_body: AnimatableBody2D
var world: Node2D  # everything on the paper (the 3D cameras film it; the screen hides it then)
var cam_mode := "top"
var cam_rot := 0.0
var cam_btn: Button
var cam_msg_t := -9.0
var view3d: View3D
var car_model := ""
var prop_layer: Node2D
var coins: Array = []  # {p, got}
var flakes: Array = []  # torn paper bits flying
var words: Array = []
var things_dirty := true

# The run
var score := 0.0
var mult := 1
var clean_t := 0.0
var best_combo := 1
var coins_got := 0
var dist := 0.0
var on_road := true
var touches := {}
var cam: Camera2D
var paper: Polygon2D
var paper_at := Vector2(INF, INF)
var road_layer: Node2D
var marks_layer: Node2D
var live: Node2D  # marks still being drawn
var things: Node2D  # obstacles and coins
var top: Node2D  # car, flakes, words
var hud: Node2D
var ui: CanvasLayer
var overlay: Control


func _ready() -> void:
	rng.randomize()
	view = get_viewport_rect().size
	var cfg := _load()
	hold_delay = float(cfg.get_value("dev", "hold", DEFAULT_HOLD))
	crash_on_hit = bool(cfg.get_value("dev", "crash", true))
	prop_info = JSON.parse_string(FileAccess.get_file_as_string("res://props/props.json"))
	var car: Dictionary = CARS.get(String(cfg.get_value("dev", "car", "evo")), CARS["evo"])
	var pap: Dictionary = PAPERS.get(String(cfg.get_value("dev", "paper", "white")), PAPERS["white"])
	car_tex = load(car["sheet"])
	car_model = String(car.get("model", ""))
	car_px = int(car["px"])
	if not car_len_px.has(car["sheet"]):
		car_len_px[car["sheet"]] = _painted_width(car_tex.get_image(), car_px)
	car_scale = CAR_LEN / maxf(8.0, float(car_len_px[car["sheet"]]))
	_build(load(pap["tex"]))
	road.append(Vector2.ZERO)
	widths.append(150.0)
	lens.append(0.0)
	_extend(-PI * 0.5, 160.0, 0.0)  # a straight start
	_chunk(0)
	_grow_road()
	pos = road[2]


# ---------------------------------------------------------------- nodes

func _build(paper_tex: Texture2D) -> void:
	world = Node2D.new()
	world.visibility_layer = 2
	add_child(world)
	paper = Polygon2D.new()
	paper.texture = paper_tex
	paper.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	world.add_child(paper)
	road_layer = Node2D.new()
	world.add_child(road_layer)
	marks_layer = Node2D.new()
	world.add_child(marks_layer)
	live = DrawNode.new()
	live.draw_fn = _draw_live
	world.add_child(live)
	things = DrawNode.new()
	things.draw_fn = _draw_things
	world.add_child(things)
	prop_layer = Node2D.new()
	world.add_child(prop_layer)
	car_body = AnimatableBody2D.new()
	car_body.sync_to_physics = false  # moved by hand each physics frame; on, it kept snapping back to the start
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = CAR_R
	cap.height = CAR_LEN * 0.95
	cs.shape = cap
	cs.rotation = PI * 0.5
	car_body.add_child(cs)
	world.add_child(car_body)
	top = DrawNode.new()
	top.draw_fn = _draw_top
	top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	world.add_child(top)
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
	cam_btn = Button.new()
	cam_btn.text = "CAM"
	cam_btn.custom_minimum_size = Vector2(112, 64)
	cam_btn.size = Vector2(112, 64)
	cam_btn.position = Vector2(view.x - 24 - 64 - 14 - 112, _top() + 14)
	cam_btn.add_theme_font_size_override("font_size", 24)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		cam_btn.add_theme_color_override(c, Color(0.15, 0.15, 0.18))  # dark ink on the light paper
	cam_btn.focus_mode = Control.FOCUS_NONE
	cam_btn.pressed.connect(func():
		Sfx.tap()
		_set_cam(CAMS[(CAMS.find(cam_mode) + 1) % CAMS.size()], true))
	root.add_child(cam_btn)
	_set_cam(String(_load().get_value("view", "cam", "top")), false)


## Switches camera. The 3D ones are built the first time they are used.
func _set_cam(m: String, announce: bool) -> void:
	if not m in CAMS:
		m = "top"
	cam_mode = m
	var three := m == "tilt"
	if three and view3d == null and car_model != "":
		var layer := CanvasLayer.new()
		layer.layer = 1
		add_child(layer)
		view3d = View3D.new()
		layer.add_child(view3d)
		if not model_cache.has(car_model):
			model_cache[car_model] = load(car_model)
		view3d.setup(self, get_viewport().world_2d, paper.texture, model_cache[car_model], CAR_LEN)
	if three and view3d == null:
		cam_mode = "follow"
		three = false
	if view3d:
		view3d.get_parent().visible = three
		view3d.film.render_target_update_mode = SubViewport.UPDATE_ALWAYS if three else SubViewport.UPDATE_DISABLED
		view3d.stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS if three else SubViewport.UPDATE_DISABLED  # no 3D work while hidden
		if three:
			view3d.set_mode(cam_mode, vdir)
	get_viewport().canvas_cull_mask = 1 if three else 0xFFFFFFFF  # the flat world only shows through 3D then
	if announce:
		cam_msg_t = clock
		var cfg := _load()
		cfg.set_value("view", "cam", cam_mode)
		cfg.save(SAVE)


func _is_3d() -> bool:
	return cam_mode == "tilt"


func _top() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return maxf(0.0, float(DisplayServer.get_display_safe_area().position.y) * view.y / float(win.y))


## The paper is one big tiled quad, moved only when the camera has gone a long way.
func _place_paper() -> void:
	if cam.position.distance_to(paper_at) < 1200.0:
		return
	paper_at = cam.position.snapped(Vector2(1024, 1024))
	var quad := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		quad.append(paper_at + c * 4096.0)
	paper.polygon = quad
	paper.uv = quad  # one texel per world pixel, so the grain stays put while the sheet moves


# ---------------------------------------------------------------- the road

## Adds road heading `dir`, curving by `turn` radians over `length`, easing its width towards what the
## piece wants.
func _extend(dir: float, length: float, turn: float) -> void:
	var n := maxi(1, int(length / STEP))
	var w := widths[widths.size() - 1]
	var want := _width_now() * piece_w
	var most := length / (maxf(w, want) * 0.85)  # never tighter than the road is wide, or the inner line folds
	turn = clampf(turn, -most, most)
	for k in n:
		dir += turn / n
		road.append(road[road.size() - 1] + Vector2.from_angle(dir) * STEP)
		w = move_toward(w, want, 2.5)
		widths.append(w)
		lens.append(lens[lens.size() - 1] + STEP)
	road_dir = dir


func _width_now() -> float:
	return clampf(150.0 - lens[lens.size() - 1] / 400.0, 100.0, 150.0)  # it narrows slowly, never speeds up


const KINDS := ["straight", "sweep", "bend", "s", "hairpin", "chicane", "wave", "zigzag", "squeeze", "pad", "long"]
const WEIGHTS := [
	[3.0, 3.0, 1.0, 1.0, 0.0, 0.0, 1.5, 0.0, 0.3, 1.5, 2.0],  # calm
	[1.0, 1.5, 3.0, 2.5, 1.0, 2.0, 2.0, 1.5, 1.0, 0.5, 0.5],  # busy
	[2.5, 3.0, 1.5, 1.0, 0.3, 0.0, 1.5, 0.3, 0.5, 1.5, 2.0],  # calm
	[0.5, 1.0, 2.5, 2.0, 2.5, 2.5, 1.0, 2.0, 2.0, 0.3, 0.3],  # tense
]


## Pieces are picked with a memory of the last few (none comes twice running), sized at random, and follow
## a rhythm: calm stretches, busy ones, calm again, then tense. Each stretch also gets its own drawing
## style. The road always keeps heading roughly up the page, and never crosses itself.
func _grow_road() -> void:
	while lens[lens.size() - 1] < _progress_len() + 2200.0:
		if phase_left <= 0.0:
			phase = (phase + 1) % 4
			phase_left = rng.randf_range(700.0, 1300.0)
			if lens[lens.size() - 1] > 400.0:
				var s := rng.randi_range(0, 3)
				style = s if s < style else s + 1  # any style but the current one
		var start := road.size() - 1
		var placed := false
		for attempt in 10:
			var kind := _pick(WEIGHTS[phase])
			if history.size() > 0 and kind == history[history.size() - 1] and kind != "straight":
				continue
			if _try_piece(kind):
				history.append(kind)
				if history.size() > 4:
					history.pop_front()
				placed = true
				break
		if not placed:
			piece_w = 1.0
			_extend(road_dir, 120.0, wrapf(-PI * 0.5 - road_dir, -PI, PI) * 0.6)  # turn back towards up the page
		phase_left -= lens[lens.size() - 1] - lens[start]
		_chunk(start)
		_place_things(start)


func _pick(weights: Array) -> String:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for k in KINDS.size():
		r -= weights[k]
		if r <= 0.0:
			return KINDS[k]
	return KINDS[0]


## Builds a piece, keeps it only if the road stays clear of itself and keeps heading up the page.
func _try_piece(kind: String) -> bool:
	var keep := road.size()
	var start_dir := road_dir
	var off_up := wrapf(road_dir - (-PI * 0.5), -PI, PI)
	var side := -signf(off_up) if absf(off_up) > 0.6 else (1.0 if rng.randf() < 0.5 else -1.0)
	piece_w = 1.0
	match kind:
		"straight":
			_extend(road_dir, rng.randf_range(120.0, 320.0), 0.0)
		"sweep":
			_extend(road_dir, rng.randf_range(260.0, 480.0), side * rng.randf_range(0.5, 1.0))
		"bend":
			_extend(road_dir, rng.randf_range(160.0, 300.0), side * rng.randf_range(1.0, 1.7))
		"s":
			var a := rng.randf_range(0.9, 1.5)
			_extend(road_dir, rng.randf_range(150.0, 240.0), side * a)
			_extend(road_dir, rng.randf_range(150.0, 240.0), -side * a * rng.randf_range(0.9, 1.2))
		"hairpin":
			_extend(road_dir, rng.randf_range(80.0, 140.0), 0.0)
			_extend(road_dir, rng.randf_range(300.0, 380.0), side * rng.randf_range(2.6, 3.0))
			_extend(road_dir, rng.randf_range(80.0, 160.0), 0.0)
			_extend(road_dir, rng.randf_range(260.0, 340.0), -side * rng.randf_range(2.2, 2.8))
		"chicane":
			var b := rng.randf_range(0.6, 1.0)
			_extend(road_dir, 110.0, side * b)
			_extend(road_dir, 150.0, -side * b * 2.0)
			_extend(road_dir, 110.0, side * b)
		"wave":  # a run of gentle swings, like a ribbon
			var c := rng.randf_range(0.5, 0.85)
			var len_w := rng.randf_range(120.0, 170.0)
			_extend(road_dir, len_w * 0.5, side * c * 0.5)
			for k in rng.randi_range(3, 5):
				side = -side
				_extend(road_dir, len_w, side * c)
			_extend(road_dir, len_w * 0.5, -side * c * 0.5)
		"zigzag":  # short sharp flicks, left right left
			var z := rng.randf_range(0.8, 1.1)
			_extend(road_dir, 60.0, side * z * 0.5)
			for k in rng.randi_range(3, 5):
				side = -side
				_extend(road_dir, 90.0, side * z)
			_extend(road_dir, 60.0, -side * z * 0.5)
		"squeeze":  # the road pinches narrow for a stretch
			piece_w = rng.randf_range(0.6, 0.7)
			_extend(road_dir, rng.randf_range(300.0, 420.0), side * rng.randf_range(0.0, 0.5))
			piece_w = 1.0
			_extend(road_dir, 80.0, 0.0)
		"pad":  # a wide open drift pad with one long sweeping turn
			piece_w = rng.randf_range(1.5, 1.8)
			_extend(road_dir, 120.0, 0.0)
			_extend(road_dir, rng.randf_range(420.0, 600.0), side * rng.randf_range(1.2, 1.8))
			piece_w = 1.0
			_extend(road_dir, 120.0, 0.0)
		"long":
			_extend(road_dir, rng.randf_range(500.0, 700.0), side * rng.randf_range(1.4, 2.0))
	piece_w = 1.0
	var ok := absf(wrapf(road_dir - (-PI * 0.5), -PI, PI)) < 1.9
	if ok:
		# Clear of the road already laid (except the stretch it grows from).
		var lo := maxi(0, keep - 700)
		var near_len := lens[keep - 1] - 500.0
		for i in range(keep, road.size(), 2):
			var p := road[i]
			for j in range(lo, keep, 3):
				if lens[j] > near_len:
					break
				var gap := (widths[j] + widths[i]) * 0.95
				if p.distance_squared_to(road[j]) < gap * gap:
					ok = false
					break
			if not ok:
				break
	if not ok:
		road.resize(keep)
		widths.resize(keep)
		lens.resize(keep)
		road_dir = start_dir
	return ok


## Draws the road from point `from` to the end once, into a node of its own.
func _chunk(from: int) -> void:
	var pts := road.slice(from)
	var ws := widths.slice(from)
	var ls := lens.slice(from)
	if pts.size() < 2:
		return
	var st := style
	var n := DrawNode.new()
	n.draw_fn = func(c: Node2D): _draw_road(c, pts, ws, ls, st)
	road_layer.add_child(n)
	chunks.append({"node": n, "end_len": ls[ls.size() - 1]})


## Obstacles and coins along the newest piece, more of them as the road goes on (and in tense stretches).
func _place_things(from: int) -> void:
	var depth := lens[lens.size() - 1]
	if depth < 700.0 or road.size() - from < 4:
		return
	things_dirty = true
	var chance := clampf(0.3 + depth / 12000.0, 0.3, 0.8) * (1.4 if phase == 3 else 0.8 if phase % 2 == 0 else 1.0)
	if rng.randf() < chance:
		var i := rng.randi_range(from + 2, road.size() - 2)
		var c := road[i]
		var nrm := Vector2.from_angle(_dir_at(i) + PI * 0.5)
		var half := widths[i] * 0.5
		var kind: String = _pick_prop()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		match kind:
			"clip":
				obstacles.append({"kind": "clip", "p": c + nrm * side * rng.randf_range(0.0, 0.8) * half, "a": rng.randf() * TAU})
			"ring":
				obstacles.append({"kind": "ring", "p": c + nrm * rng.randf_range(-1.2, 1.2) * half, "a": 0.0})
			_:
				var info: Dictionary = prop_info[kind]
				var length := float(info["len"])
				var at: Vector2
				var ang: float
				if length > 120.0:  # long things lie in from the edge, leaving room to drift past
					var into := rng.randf_range(0.25, 0.5) * half
					var tip := c + nrm * side * (half - into)
					ang = (nrm * -side).angle() + rng.randf_range(-0.35, 0.35)
					at = tip - Vector2.from_angle(ang) * length * 0.5
				else:
					at = c + nrm * side * rng.randf_range(0.15, 0.6) * half
					ang = rng.randf() * TAU
				_spawn_prop(kind, at, ang)
	if rng.randf() < 0.55:
		var i0 := rng.randi_range(from, maxi(from, road.size() - 22))
		var off := rng.randf_range(-0.3, 0.3)
		for k in 5:
			var i := mini(i0 + k * 4, road.size() - 1)
			coins.append({"p": road[i] + Vector2.from_angle(_dir_at(i) + PI * 0.5) * off * widths[i], "got": false})


func _pick_prop() -> String:
	var total := 0.0
	for k in PROP_WEIGHTS:
		total += PROP_WEIGHTS[k]
	var r := rng.randf() * total
	for k in PROP_WEIGHTS:
		r -= PROP_WEIGHTS[k]
		if r <= 0.0:
			return k
	return "pencil"


func _spawn_prop(kind: String, at: Vector2, ang: float) -> void:
	for o in props:  # never dropped on top of another
		if (o as Node2D).position.distance_to(at) < 140.0:
			return
	if not prop_tex.has(kind):
		prop_tex[kind] = load("res://props/%s.png" % kind)
	var o := Prop.new()
	o.position = at
	o.rotation = ang
	o.set_meta("kind", kind)
	o.setup(prop_info[kind], prop_tex[kind], car_body)
	o.hit_car.connect(_on_prop_hit)
	prop_layer.add_child(o)
	props.append(o)


## The car ran into a desk object: the run ends (or, with the dev switch off, it just bumps and slows).
func _on_prop_hit(o: Node) -> void:
	if state != "play":
		return
	var name: String = PROP_NAMES.get(o.get_meta("kind"), o.get_meta("kind"))
	if crash_on_hit:
		_crash("Hit the %s" % name)
	elif clock - bump_t > 0.4:
		bump_t = clock
		speed *= 0.55
		mult = 1
		clean_t = 0.0
		Sfx.crash()
		_word("BUMP", pos + Vector2(0, -50), Color(0.75, 0.2, 0.2))


func _physics_process(_delta: float) -> void:
	car_body.position = pos
	car_body.rotation = heading


func _dir_at(i: int) -> float:
	var a := road[maxi(0, i - 1)]
	var b := road[mini(road.size() - 1, i + 1)]
	return (b - a).angle()


func _progress_len() -> float:
	return lens[mini(progress_i, lens.size() - 1)]


## The nearest road point to the car, searched near where it was; what's far behind is dropped.
func _track() -> void:
	var best := progress_i
	var bd := INF
	for i in range(maxi(0, progress_i - 20), mini(road.size(), progress_i + 60)):
		var d := pos.distance_squared_to(road[i])
		if d < bd:
			bd = d
			best = i
	progress_i = best
	dist = maxf(dist, lens[best] / 10.0)
	var drop := progress_i - 180
	if drop > 60:
		road = road.slice(drop)
		widths = widths.slice(drop)
		lens = lens.slice(drop)
		progress_i -= drop
		var behind := lens[0]
		while not chunks.is_empty() and float(chunks[0]["end_len"]) < behind:
			(chunks.pop_front()["node"] as Node).queue_free()
		obstacles = obstacles.filter(func(o): return Vector2(o["p"]).distance_to(pos) < 1500.0)
		var near_props: Array = []
		for o in props:
			if (o as Node2D).position.distance_to(pos) < 1500.0:
				near_props.append(o)
			else:
				(o as Node).queue_free()
		props = near_props
		coins = coins.filter(func(c): return not c["got"] and Vector2(c["p"]).distance_to(pos) < 1500.0)
		things_dirty = true
		var keep: Array = []
		for m in still_marks:
			if Vector2(m["p"]).distance_to(pos) < 1600.0:
				keep.append(m)
			else:
				(m["node"] as Node).queue_free()
		still_marks = keep


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	clock += delta
	match state:
		"play":
			_drive(delta)
			_track()
			_grow_road()
			_marks()
			_score(delta)
			_hits()
		"crashed", "summary":
			spin *= exp(-2.0 * delta)
			heading += spin * delta
			speed = move_toward(speed, 0.0, 300.0 * delta)
			pos += Vector2.from_angle(vdir) * speed * delta
			if state == "crashed" and clock - crash_t > 1.6 and overlay == null:
				_show_summary()
	_effects(delta)
	_follow(delta)
	_place_paper()
	live.queue_redraw()
	top.queue_redraw()
	hud.queue_redraw()
	if things_dirty:
		things_dirty = false
		things.queue_redraw()


func _input_side() -> int:
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


## How a real drift goes, eased so no step is sudden. A held side first loads the car into a light slide
## (the rear steps out a little and the nose eases round). Keep holding past `hold_delay` and the rear lets
## go fully: the slide deepens into a drift, the nose swings hard while the car keeps travelling on its old
## line. Let go and it unwinds the same way: the rear tyres slowly find grip again, they swing the nose back
## towards the way the car is going (the "catch"), and the travel bends round until both line up.
## Nothing jumps: the turn rate has weight (YAW_LAG), and the input and the drift both ease in and out.
func _drive(delta: float) -> void:
	var side := _input_side()
	hold_t = hold_t + delta if side != 0 else 0.0  # switching sides without letting go keeps the drift
	steer += (side - steer) * (1.0 - exp(-delta * (STEER_IN if side != 0 else STEER_OUT)))
	var want := 0.0
	if side != 0:
		want = 1.0 if hold_t >= hold_delay else 0.35
	drift_amt += (want - drift_amt) * (1.0 - exp(-delta * (DRIFT_IN if want > drift_amt else DRIFT_OUT)))
	var s := wrapf(heading - vdir, -PI, PI)
	# The catch only works on a car that is actually sliding: in a light turn the tyres grip, the path
	# bends with the nose, and nothing pulls the nose back (that made a tap pivot the car on the spot).
	var catch := clampf(absf(s) / 0.5, 0.0, 1.0) * (1.0 - drift_amt)
	var yaw_want := steer * TURN * lerpf(SLIDE_TURN, 1.0, drift_amt) - s * ALIGN * catch
	yaw += (yaw_want - yaw) * (1.0 - exp(-delta * YAW_LAG))
	heading += yaw * delta
	var grip := lerpf(GRIP, SLIDE_GRIP, drift_amt * drift_amt)  # grip holds through a light turn, goes in the drift
	s = wrapf(heading - vdir, -PI, PI)
	vdir += s * (1.0 - exp(-delta * grip))  # the travel bends towards the nose, harder the more grip
	s = wrapf(heading - vdir, -PI, PI)
	if absf(s) > 1.35:  # never more than sideways
		vdir = heading - signf(s) * 1.35
	slip = absf(wrapf(heading - vdir, -PI, PI))
	var i := progress_i
	var half := widths[i] * 0.5
	var off := pos.distance_to(road[i])
	var was := on_road
	on_road = off < half - CAR_R * 0.4
	if was and not on_road:
		_word("LINE", pos, Color(0.35, 0.35, 0.4))
		clean_t = 0.0
		mult = 1
	# Off the line the paper drags: the car eases down (never stops) so it can be steered back, and picks up
	# again gently once it's back between the lines.
	speed += ((SPEED if on_road else OFF_SPEED) - speed) * (1.0 - exp(-delta * (0.9 if on_road else 0.7)))
	pos += Vector2.from_angle(vdir) * speed * delta
	if off > half + 170.0:
		_crash("Lost the road")


# ---------------------------------------------------------------- the paper

func _wheels() -> Array:
	var f := Vector2.from_angle(heading)
	var r := f.orthogonal()
	var back := pos - f * CAR_LEN * 0.32
	return [back + r * 13.0, back - r * 13.0]


## Graphite skids whenever it slides; past a hard slide the tyres start ripping the paper itself.
func _marks() -> void:
	var wheels := _wheels()
	var sliding := slip > 0.22
	var ripping := slip > 0.75 and speed > 180.0 and on_road
	for k in 2:
		var w: Vector2 = wheels[k]
		if sliding:
			if live_skid[k] == null:
				live_skid[k] = {"pts": PackedVector2Array([w]), "a": clampf(slip, 0.25, 0.8)}
			var sk: Dictionary = live_skid[k]
			var pts: PackedVector2Array = sk["pts"]
			if pts[pts.size() - 1].distance_to(w) > 5.0:
				pts.append(w)
				sk["pts"] = pts
				if pts.size() >= MARK_POINTS:
					_still_skid(k)
					live_skid[k] = {"pts": PackedVector2Array([w]), "a": sk["a"]}
		elif live_skid[k] != null:
			_still_skid(k)
		if ripping:
			if live_tear[k] == null:
				live_tear[k] = {"pts": PackedVector2Array([w]), "w": PackedFloat32Array([2.0]), "seed": rng.randf() * 100.0}
			var t: Dictionary = live_tear[k]
			var tp: PackedVector2Array = t["pts"]
			if tp[tp.size() - 1].distance_to(w) > 6.0:
				tp.append(w)
				var ww: PackedFloat32Array = t["w"]
				ww.append(clampf(4.0 + (slip - 0.75) * 18.0, 3.0, 11.0))
				t["pts"] = tp
				t["w"] = ww
				if rng.randf() < 0.6:  # torn bits of paper kick up
					flakes.append({"p": w, "v": Vector2.from_angle(vdir + PI + rng.randf_range(-1.0, 1.0)) * rng.randf_range(40, 120), "t": clock, "a": rng.randf() * TAU, "s": rng.randf_range(2.5, 5.0)})
				if tp.size() >= MARK_POINTS:  # carry on seamlessly in a fresh piece
					_still_tear(k, false)
					live_tear[k] = {"pts": PackedVector2Array([tp[tp.size() - 2], w]), "w": PackedFloat32Array([ww[ww.size() - 2], ww[ww.size() - 1]]), "seed": t["seed"] + 7.0, "joined": true}
		elif live_tear[k] != null:
			_still_tear(k, true)


func _still_skid(k: int) -> void:
	var sk: Dictionary = live_skid[k]
	live_skid[k] = null
	if (sk["pts"] as PackedVector2Array).size() < 2:
		return
	_still(func(c: Node2D): _draw_skid(c, sk), sk["pts"][0])


func _still_tear(k: int, ends: bool) -> void:
	var t: Dictionary = live_tear[k]
	live_tear[k] = null
	if (t["pts"] as PackedVector2Array).size() < 2:
		return
	t["end"] = ends
	_still(func(c: Node2D): _draw_tear(c, t), t["pts"][0])


func _still(fn: Callable, p: Vector2) -> void:
	var n := DrawNode.new()
	n.draw_fn = fn
	marks_layer.add_child(n)
	still_marks.append({"node": n, "p": p})


# ---------------------------------------------------------------- scoring and hits

func _score(delta: float) -> void:
	score += speed * delta * 0.05  # distance
	if slip > 0.25 and on_road:
		var edge := absf(widths[progress_i] * 0.5 - pos.distance_to(road[progress_i]))
		var close := 1.6 if edge < 26.0 else 1.0  # drifting close to the line pays more
		score += rad_to_deg(slip) * delta * 0.4 * mult * close
		clean_t += delta
		var m := 1 + int(clean_t / 1.6)
		if m > mult:
			mult = mini(m, 9)
			best_combo = maxi(best_combo, mult)
			_word("x%d" % mult, pos + Vector2(0, -40), Color(0.85, 0.35, 0.15))
	for c in coins:
		if not c["got"] and pos.distance_to(c["p"]) < CAR_R + 12.0:
			c["got"] = true
			things_dirty = true
			coins_got += 1
			score += 25.0
			Sfx.chime(1.6)


## Near misses: brushing past a desk object without touching it. (Touching is caught by the physics.)
func _hits() -> void:
	for o in props:
		if o.near or (o as Node2D).position.distance_squared_to(pos) > 250.0 * 250.0:
			continue
		var d: float = o.gap_to(pos)
		if d < CAR_R + 16.0 and d > CAR_R + 2.0:
			o.near = true
			score += 60.0 * mult
			_word("NEAR MISS", pos + Vector2(0, -50), Color(0.2, 0.4, 0.75))


func _crash(why: String) -> void:
	if state != "play":
		return
	state = "crashed"
	crash_t = clock
	spin = 9.0 * (1.0 if rng.randf() < 0.5 else -1.0)
	Sfx.crash()
	Game.vibrate(70)
	_word(why.to_upper(), pos + Vector2(0, -60), Color(0.75, 0.2, 0.2))
	prev_best = int(_load().get_value("best", "score", 0))
	_save()


func _word(text: String, p: Vector2, col: Color) -> void:
	words = [{"text": text, "p": p, "t": clock, "col": col}]


func _effects(delta: float) -> void:
	var keep: Array = []
	for f in flakes:
		if clock - float(f["t"]) < 0.9:
			f["p"] = Vector2(f["p"]) + Vector2(f["v"]) * delta
			f["v"] = Vector2(f["v"]) * exp(-4.0 * delta)
			f["a"] = float(f["a"]) + delta * 6.0
			keep.append(f)
	flakes = keep
	if not words.is_empty() and clock - float(words[0]["t"]) > 1.5:
		words.clear()


## Top down: north up, a little ahead of the car, zoomed to keep the road coming up in view. Follow and Close
## turn with the car so the way it is going points up the screen; Close also pulls in during a drift. The
## 3D cameras are handled by view3d.gd.
func _follow(delta: float) -> void:
	if _is_3d():
		cam_rot = 0.0
		Prop.view_rot = 0.0
		cam.rotation = 0.0
		cam.position = pos  # the paper sheet is moved by this camera, even though it isn't shown
		view3d.follow(delta, pos, heading, vdir)
		return
	var turning := cam_mode != "top"
	cam_rot = lerp_angle(cam_rot, vdir + PI * 0.5 if turning else 0.0, 1.0 - exp(-delta * 2.0))
	cam.ignore_rotation = false
	cam.rotation = cam_rot
	Prop.view_rot = cam_rot
	# The road ahead, measured across the screen as the camera sees it.
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for i in range(progress_i, mini(road.size(), progress_i + 70), 5):
		var q := (road[i] - pos).rotated(-cam_rot)
		lo = lo.min(q)
		hi = hi.max(q)
	var box := Rect2(lo, hi - lo).grow(170.0)
	var want := clampf(minf(view.x / box.size.x, view.y / box.size.y), 0.55, 1.15)
	var target := pos + box.get_center().rotated(cam_rot).lerp(Vector2.ZERO, 0.45)
	if cam_mode == "close":
		want = clampf(want * lerpf(1.25, 1.6, drift_amt), 0.8, 1.7)
		target = pos + Vector2.from_angle(vdir) * lerpf(140.0, 90.0, drift_amt)
	cam.zoom = cam.zoom.lerp(Vector2.ONE * want, 1.0 - exp(-delta * 1.2))
	cam.position = cam.position.lerp(target, 1.0 - exp(-delta * 3.0))


# ---------------------------------------------------------------- drawing

## One stretch of road's edges, in that stretch's style: pencil (soft grey, drawn twice), ballpoint
## (thin blue), marker (bold black), crayon (waxy red, broken), or pencil with a dashed centre line.
func _draw_road(n: Node2D, pts: PackedVector2Array, ws: PackedFloat32Array, ls: PackedFloat32Array, st: int) -> void:
	var m := pts.size()
	var nrms := PackedVector2Array()
	nrms.resize(m)
	for i in m:
		nrms[i] = (pts[mini(m - 1, i + 1)] - pts[maxi(0, i - 1)]).normalized().orthogonal()
	for side in [-1.0, 1.0]:
		var passes := 1 if st == 1 or st == 2 else 2
		for pass_k in passes:
			var line := PackedVector2Array()
			line.resize(m)
			for i in m:
				var wob := sin(ls[i] * 0.021 + side * 3.0 + pass_k * 1.7) * 1.6 + sin(ls[i] * 0.07 + pass_k) * 0.7
				line[i] = pts[i] + nrms[i] * side * (ws[i] * 0.5 + wob + pass_k * 0.8)
			match st:
				1:
					n.draw_polyline(line, Color(0.13, 0.22, 0.58, 0.85), 2.0, true)
				2:
					n.draw_polyline(line, Color(0.09, 0.09, 0.11, 0.88), 5.0, true)
				3:  # crayon: thick waxy strokes with little gaps where the wax skipped
					var seg := PackedVector2Array()
					for i in m:
						var skip := fposmod(sin(ls[i] * 0.13 + pass_k * 5.0 + side) * 43758.5, 1.0) < 0.12
						if skip:
							if seg.size() >= 2:
								n.draw_polyline(seg, Color(0.78, 0.2, 0.18, 0.55 if pass_k == 0 else 0.35), 4.5 if pass_k == 0 else 2.5, true)
							seg = PackedVector2Array()
						else:
							seg.append(line[i])
					if seg.size() >= 2:
						n.draw_polyline(seg, Color(0.78, 0.2, 0.18, 0.55 if pass_k == 0 else 0.35), 4.5 if pass_k == 0 else 2.5, true)
				_:
					n.draw_polyline(line, Color(0.22, 0.22, 0.25, 0.55 if pass_k == 0 else 0.3), 2.6 if pass_k == 0 else 1.4, true)
	if st == 4:  # dashes down the middle
		for i in range(0, m - 3, 6):
			if int(ls[i] / 48.0) % 2 == 0:
				n.draw_line(pts[i], pts[i + 3], Color(0.25, 0.25, 0.28, 0.45), 2.2, true)


func _draw_skid(n: Node2D, sk: Dictionary) -> void:
	n.draw_polyline(sk["pts"], Color(0.2, 0.2, 0.22, float(sk["a"]) * 0.45), 5.0, true)


func _draw_live(n: Node2D) -> void:
	for k in 2:
		if live_skid[k] != null and (live_skid[k]["pts"] as PackedVector2Array).size() >= 2:
			_draw_skid(n, live_skid[k])
	for k in 2:
		if live_tear[k] != null:
			_draw_tear(n, live_tear[k])


## A rip: a soft shadow where the torn edge lifts, the white fibrous core of the paper, the wooden desk
## through the hole, and little curled flaps along it.
func _draw_tear(n: Node2D, t: Dictionary) -> void:
	var pts: PackedVector2Array = t["pts"]
	var ww: PackedFloat32Array = t["w"]
	var m := pts.size()
	if m < 2:
		return
	var sd := float(t["seed"])
	var taper_start: bool = not t.get("joined", false)
	var taper_end: bool = t.get("end", false)
	var outer_l := PackedVector2Array()
	var outer_r := PackedVector2Array()
	var hole_l := PackedVector2Array()
	var hole_r := PackedVector2Array()
	for i in m:
		var a := pts[maxi(0, i - 1)]
		var b := pts[mini(m - 1, i + 1)]
		var nrm := (b - a).normalized().orthogonal()
		var w := ww[i]
		if (i == 0 and taper_start) or (i == m - 1 and taper_end):
			w *= 0.4
		var j1 := sin(i * 2.7 + sd) * 1.5 + sin(i * 7.1 + sd * 2.0) * 1.0  # torn paper is ragged
		var j2 := sin(i * 3.3 + sd * 1.3) * 1.5 + sin(i * 6.4 + sd) * 1.0
		hole_l.append(pts[i] + nrm * (w * 0.5 + j1))
		hole_r.append(pts[i] - nrm * (w * 0.5 + j2))
		outer_l.append(pts[i] + nrm * (w * 0.5 + j1 + 2.2 + absf(sin(i * 5.0 + sd)) * 1.6))
		outer_r.append(pts[i] - nrm * (w * 0.5 + j2 + 2.2 + absf(sin(i * 4.3 + sd)) * 1.6))
	var sh := Vector2(1.5, 2.0)
	for i in m - 1:
		_quad(n, outer_l[i] + sh, outer_l[i + 1] + sh, outer_r[i + 1] + sh, outer_r[i] + sh, Color(0, 0, 0, 0.14))
	for i in m - 1:
		_quad(n, outer_l[i], outer_l[i + 1], outer_r[i + 1], outer_r[i], Color(0.995, 0.99, 0.975))
	for i in m - 1:
		_quad(n, hole_l[i], hole_l[i + 1], hole_r[i + 1], hole_r[i], Color(0.45, 0.3, 0.18))
	n.draw_polyline(pts, Color(0.32, 0.2, 0.11, 0.55), maxf(1.0, ww[m / 2] * 0.22), true)  # wood grain
	for i in range(2, m - 1, 4):
		var a := pts[i - 1]
		var b := pts[i + 1]
		var along := (b - a).normalized()
		var nrm := along.orthogonal() * (1.0 if int(i / 4) % 2 == 0 else -1.0)
		var base := pts[i] + nrm * ww[i] * 0.5
		var tip := base + nrm * (3.0 + absf(sin(i + sd)) * 4.0) + along * 3.0
		n.draw_primitive(PackedVector2Array([base - along * 3.5, tip, base + along * 3.5]), PackedColorArray([Color(0.97, 0.96, 0.93)]), PackedVector2Array())
		n.draw_line(base, tip, Color(0, 0, 0, 0.1), 1.0, true)


## How wide the solid part of the first picture on a car sheet is (faint edge pixels don't count). It faces
## right, so that width is the car's length.
func _painted_width(img: Image, px: int) -> float:
	if img.is_compressed():
		img.decompress()
	var lo := px
	var hi := -1
	for y in range(0, px, 2):
		for x in px:
			if img.get_pixel(x, y).a > 0.5:
				lo = mini(lo, x)
				hi = maxi(hi, x)
	return float(hi - lo + 1)


## Two triangles, drawn without triangulating (a thin or twisted quad would refuse to draw).
func _quad(n: Node2D, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var cols := PackedColorArray([col])
	n.draw_primitive(PackedVector2Array([a, b, c]), cols, PackedVector2Array())
	n.draw_primitive(PackedVector2Array([a, c, d]), cols, PackedVector2Array())


func _draw_things(n: Node2D) -> void:
	for o in obstacles:
		_draw_obstacle(n, o)
	for c in coins:
		if not c["got"]:
			var p: Vector2 = c["p"]
			n.draw_circle(p + Vector2(2, 3), 9.0, Color(0, 0, 0, 0.18), true, -1.0, true)
			n.draw_circle(p, 9.0, Color("e8b730"), true, -1.0, true)
			n.draw_circle(p, 6.0, Color("f6d55c"), true, -1.0, true)
			n.draw_circle(p + Vector2(-2.5, -2.5), 2.2, Color(1, 1, 1, 0.7), true, -1.0, true)


func _draw_top(n: Node2D) -> void:
	for f in flakes:
		var k := (clock - float(f["t"])) / 0.9
		var s := float(f["s"])
		n.draw_set_transform(f["p"], float(f["a"]), Vector2.ONE)
		n.draw_colored_polygon(PackedVector2Array([Vector2(-s, -s * 0.6), Vector2(s, -s * 0.3), Vector2(s * 0.4, s), Vector2(-s * 0.8, s * 0.5)]), Color(0.98, 0.97, 0.94, 1.0 - k))
	n.draw_set_transform(Vector2.ZERO)
	# The car: its shadow on the paper, then the car itself.
	# The nearest of the 64 baked angles, turned the last few degrees so the car rotates smoothly instead of
	# stepping from picture to picture.
	var rel := heading - cam_rot  # the picture is picked as the camera sees the car
	var i := int(roundf(fposmod(rel, TAU) / TAU * 64.0)) % 64
	var rest := wrapf(rel - TAU * i / 64.0, -PI, PI) + cam_rot
	var src := Rect2((i % 8) * car_px, (i / 8) * car_px, car_px, car_px)
	var sz := Vector2.ONE * car_px * car_scale
	n.draw_set_transform(pos + Vector2(-6, 8).rotated(cam_rot), rest)
	n.draw_texture_rect_region(car_tex, Rect2(-sz * 0.5, sz), src, Color(0.1, 0.08, 0.05, 0.28))
	if not _is_3d():  # in 3D the real model drives over its shadow
		n.draw_set_transform(pos, rest)
		n.draw_texture_rect_region(car_tex, Rect2(-sz * 0.5, sz), src)
	n.draw_set_transform(Vector2.ZERO)
	if _is_3d():
		return  # words go on the screen instead (drawn by the HUD)
	var font: Font = Game.title_font
	for w in words:
		var age := clock - float(w["t"])
		var a := minf(1.0, age * 8.0) * (1.0 - smoothstep(1.0, 1.5, age))
		var tw := font.get_string_size(w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		n.draw_set_transform(w["p"], cam_rot)  # upright on screen whichever way the camera has turned
		n.draw_string(font, Vector2(-tw * 0.5, -30.0 * age), w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(w["col"], a))
	n.draw_set_transform(Vector2.ZERO)


func _draw_obstacle(n: Node2D, o: Dictionary) -> void:
	var p: Vector2 = o["p"]
	var a := float(o["a"])
	match String(o["kind"]):
		"clip":
			n.draw_set_transform(p, a, Vector2.ONE)
			var pts := PackedVector2Array([Vector2(-20, -5), Vector2(14, -5), Vector2(18, 0), Vector2(14, 5), Vector2(-14, 5), Vector2(-17, 2), Vector2(-14, -1), Vector2(10, -1)])
			n.draw_polyline(pts, Color(0, 0, 0, 0.15), 3.0, true)
			n.draw_polyline(pts, Color("a9b0b8"), 1.8, true)
			n.draw_set_transform(Vector2.ZERO)
		"ring":
			n.draw_arc(p, 34.0, 0.0, TAU, 48, Color(0.55, 0.36, 0.2, 0.16), 6.0, true)
			n.draw_arc(p, 31.0, 0.3, 5.5, 40, Color(0.5, 0.32, 0.18, 0.12), 2.0, true)


func _draw_hud(n: Node2D) -> void:
	var font: Font = Game.heading_font
	var top_y := _top() + 46.0
	var s := "%d" % int(score)
	var sw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	_text(n, font, s, Vector2((view.x - sw) * 0.5, top_y + 10), 46, Color(0.15, 0.15, 0.18))
	_text(n, font, "%d m" % int(dist), Vector2(28, top_y), 24, Color(0.2, 0.2, 0.25))
	_text(n, font, "%d coins" % coins_got, Vector2(28, top_y + 30), 22, Color(0.62, 0.45, 0.05))
	if mult > 1:
		var m := "x%d COMBO" % mult
		var mw := font.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(n, font, m, Vector2((view.x - mw) * 0.5, top_y + 46), 26, Color(0.85, 0.35, 0.15))
	if _is_3d():
		for w in words:
			var age := clock - float(w["t"])
			var a := minf(1.0, age * 8.0) * (1.0 - smoothstep(1.0, 1.5, age))
			var ww := font.get_string_size(w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
			_text(n, font, w["text"], Vector2((view.x - ww) * 0.5, view.y * 0.36 - 30.0 * age), 34, Color(w["col"], a))
	if clock - cam_msg_t < 1.6:
		var cm: String = "Camera: " + CAM_NAMES[cam_mode]
		var cw := font.get_string_size(cm, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		_text(n, font, cm, Vector2((view.x - cw) * 0.5, top_y + 96), 28, Color(0.15, 0.15, 0.18, 1.0 - smoothstep(1.1, 1.6, clock - cam_msg_t)))
	if state == "play" and dist < 25.0:
		for k in 2:
			var h: String = ["Hold left or right to drift that way.", "Let go to straighten. Stay between the lines."][k]
			var hw := font.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			_text(n, font, h, Vector2((view.x - hw) * 0.5, view.y * 0.72 + k * 34), 24, Color(0.2, 0.2, 0.25))


func _text(n: Node2D, font: Font, s: String, p: Vector2, size: int, col: Color) -> void:
	n.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1, 1, 1, 0.7))
	n.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---------------------------------------------------------------- pause and summary

func _pause() -> void:
	if overlay != null or state != "play":
		return
	get_tree().paused = true
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
	state = "summary"
	var lines := [
		"Score  %d%s" % [int(score), "   NEW BEST" if int(score) > prev_best else "   best %d" % prev_best],
		"Distance  %d m" % int(dist),
		"Best combo  x%d" % best_combo,
		"Coins  %d" % coins_got,
	]
	overlay = _panel("CRASHED", lines, [["Drive again", func(): again_requested.emit()], ["Home", _home]])


func _panel(title: String, lines: Array, buttons: Array) -> Control:
	var o := Control.new()
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	o.theme = Game.ui_theme
	o.size = view
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.6)
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
	return o


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return cfg


func _save() -> void:
	var cfg := _load()
	cfg.set_value("best", "score", maxi(int(cfg.get_value("best", "score", 0)), int(score)))
	cfg.set_value("best", "combo", maxi(int(cfg.get_value("best", "combo", 0)), best_combo))
	cfg.set_value("best", "dist", maxi(int(cfg.get_value("best", "dist", 0)), int(dist)))
	cfg.set_value("total", "coins", int(cfg.get_value("total", "coins", 0)) + coins_got)
	cfg.save(SAVE)


func _exit_tree() -> void:
	get_tree().paused = false
	get_viewport().canvas_cull_mask = 0xFFFFFFFF  # a 3D camera hid the flat world; the title screen needs it back
