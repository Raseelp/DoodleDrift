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
const Radio = preload("res://scripts/radio.gd")
const Scribbles = preload("res://scripts/scribbles.gd")
const PROP_NAMES := {"pencil_blue": "pencil", "pencil_white": "pencil", "set_square": "set square"}
## Desk objects that lie across or beside the road, and how often each turns up.
const PROP_WEIGHTS := {"pencil": 2.0, "pencil_blue": 1.5, "pencil_white": 1.5, "ruler": 1.5, "scissors": 1.2, "set_square": 1.0, "sharpener": 1.2, "eraser": 1.5, "clip": 1.0}

## Cars: a sheet of 64 baked headings (8 x 8, first picture facing right, then clockwise).
const CARS := {
	"evo": {"name": "Red Evo", "sheet": "res://cars/evo.png", "px": 192},
}
## Papers: seamless textures, no printed lines.
const PAPERS := {
	"white": {"name": "White printer", "tex": "res://paper/white.jpg"},
	"sketch": {"name": "Cream sketch", "tex": "res://paper/sketch.jpg"},
	"kraft": {"name": "Kraft brown", "tex": "res://paper/kraft.jpg"},
	"recycled": {"name": "Recycled grey", "tex": "res://paper/recycled.jpg"},
}
const DEFAULT_HOLD := 0.15  # seconds a side is held before the car flicks into a drift

const SPEED := 330.0  # top speed: only reached on a long straight (the pull fades above STRONG_PULL)
const STRONG_PULL := 250.0  # full acceleration up to here ...
const TOP_EASE := 0.45  # ... then it creeps towards the top (1/s): about 4 s of straight to get near 280
const OFF_SPEED := 140.0  # across the line
const ACCEL := 140.0  # pulling away (px/s²): from a standstill at the start, and back up after leaving the line
const SCRUB := 220.0  # sliding sideways bleeds speed (px/s² at a full sideways slide), as a real drift does ...
const DRIFT_FLOOR := 140.0  # ... but never below this; let go and the car pulls back up through the gears
## Automatic gearbox: the speed (px/s) at which each gear runs out; a long straight reaches 5th.
const GEAR_TOP := [80.0, 145.0, 210.0, 280.0, 360.0]
const IDLE_RPM := 1000.0
const SHIFT_RPM := 7000.0  # changes up here ...
const PULL_RPM := 3600.0  # ... and lands about here in the next gear
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
const R_MIN := 120.0  # the tightest corner (centre line): the car's own drift circle (~85-107 px) plus room
const SAVE := "user://drift.cfg"
## Real recordings (sounds/CREDITS.txt). Each kind has one or more takes, picked at random.
const SOUNDS := {
	"rip": ["res://sounds/rip_a.ogg", "res://sounds/rip_b.ogg"],
	"coin": ["res://sounds/coin_1.ogg", "res://sounds/coin_2.ogg"],
	"bump": ["res://sounds/bump.ogg"],
	"crash": ["res://sounds/crash.ogg"],
}
## Background music (music/CREDITS.txt). The dev setting picks one, shuffles them, or turns it off.
const TRACKS := {
	"black_diamond": {"name": "Black Diamond (drum & bass)", "path": "res://music/black_diamond.ogg"},
	"space_city": {"name": "Space City (synthwave)", "path": "res://music/space_city.ogg"},
	"awake": {"name": "Awake! (breakbeat)", "path": "res://music/awake.ogg"},
	"the_rush": {"name": "The Rush (electronic)", "path": "res://music/the_rush.ogg"},
	"midnight_cruiser": {"name": "Midnight Cruiser (groove)", "path": "res://music/midnight_cruiser.ogg"},
}
const MUSIC_CHOICES := {
	"shuffle": {"name": "Shuffle"},
	"off": {"name": "Off"},
	"black_diamond": {"name": "Black Diamond (drum & bass)"},
	"space_city": {"name": "Space City (synthwave)"},
	"awake": {"name": "Awake! (breakbeat)"},
	"the_rush": {"name": "The Rush (electronic)"},
	"midnight_cruiser": {"name": "Midnight Cruiser (groove)"},
}
## Engine sounds (dev setting while choosing by ear). Each layer is a looped real recording and the rpm it
## was recorded at; several layers cross-fade as the revs climb. "bov": the turbo's blow-off on a change up.
const ENGINES := {
	"generic": {"name": "Generic", "bov": false, "layers": [["res://sounds/engine_generic/loop_5.ogg", 3000.0]]},
}
## The road's ink, per drawing style: texture, colour, width, chance a stroke is gone over again, chance of
## a hand smudge. 0 pencil, 1 blue ballpoint, 2 black marker, 3 soft 4B pencil, 4 pencil with centre dashes.
const INK := {
	0: ["pencil", Color(0.17, 0.17, 0.2, 0.95), 4.4, 0.4, 0.35],
	1: ["ballpoint", Color(0.12, 0.2, 0.55, 0.95), 2.8, 0.1, 0.0],
	2: ["marker", Color(0.08, 0.08, 0.1, 0.92), 5.0, 0.0, 0.0],
	3: ["pencil_soft", Color(0.13, 0.13, 0.15, 0.95), 5.6, 0.3, 0.6],
	4: ["pencil", Color(0.17, 0.17, 0.2, 0.95), 4.2, 0.4, 0.3],
}
const MARK_POINTS := 28  # a skid or tear being drawn is handed to a still node after this many points

## Kept for the whole session: the 3D car model (slow to load) and each car sheet's measured length.
static var model_cache := {}
static var page_tex := {}  # page and stroke textures, the hand font
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
var speed := 0.0  # each run pulls away from a standstill
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
var phase := -1  # which phrase of the rhythm: calm, build, peak, release (PHRASES)
var phrase_left := 0  # blocks left in this phrase
var pending_corners: Array = []  # corners of the block being tried
var corners: Array = []  # every drift corner ahead: {apex, len, side, r, kind}, for scoring later
var last_side := 1.0
var same_run := 0
var fallbacks := 0  # blocks that could not fit (for tuning)
var style := 0  # how the edges are drawn: pencil, ballpoint, marker, crayon, dashed
var piece_w := 1.0  # the width this piece wants, against the normal width
var page_under: Node2D  # show-through and page edges, under the road ink
var page_over: Node2D  # coffee, creases, staples, over it
var page_bits: Array = []  # {node, len}
var next_page := 2500.0
var next_decor := 600.0
var page_no := 0
var scrib: Scribbles  # notes, doodles, abandoned roads, sticky notes (scribbles.gd)
var seams: Array = []  # page edges ahead: {y, x0, x1, holes, hit, len}
var jolt_t := -9.0
var jolt_k := 0.0  # how hard the last bump was (0.5 the edge, 1 a wheel in a hole)
var prev_y := 0.0
var chunks: Array = []  # {node, end_len}: each piece of road drawn once

# On the paper
var live_skid := [null, null]  # the skid each rear wheel is drawing: {pts, a}
var live_tear := [null, null]  # {pts, w, seed}
var still_marks: Array = []
var mark_bucket: Node2D
var bucket_fns: Array = []  # {node, p}
var obstacles: Array = []  # drawn bits that don't block: {kind, p, a}
var props: Array = []  # desk objects with physics (prop.gd)
var prop_info := {}  # sizes from res://props/props.json
var prop_tex := {}
var crash_on_hit := true  # dev: hitting an object ends the run, or just bumps
var bump_t := -9.0
var car_body: AnimatableBody2D
var world: Node2D  # everything on the paper (the 3D cameras film it; the screen hides it then)
var cam_rot := 0.0
var cam_goal_zoom := 1.0
var cam_goal_pos := Vector2.ZERO
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
var squeal: AudioStreamPlayer  # loops all run; its volume and pitch follow the slide
var squeal_vol := 0.0
var shots: Array[AudioStreamPlayer] = []  # a few players for one-off sounds
var shot_i := 0
var snd := {}
var rip_t := -9.0
var engine_layers: Array = []  # [player, rpm it was recorded at]
var engine_bov := false
var gear := 1
var rpm := IDLE_RPM
var shift_t := -9.0


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
	_sound_setup()
	road.append(Vector2.ZERO)
	widths.append(150.0)
	lens.append(0.0)
	_extend(-PI * 0.5, 160.0, 0.0)  # a straight start
	_chunk(0)
	_grow_road()
	pos = road[2]
	prev_y = pos.y
	cam_goal_pos = pos


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
	page_under = Node2D.new()
	world.add_child(page_under)
	road_layer = Node2D.new()
	world.add_child(road_layer)
	page_over = Node2D.new()
	world.add_child(page_over)
	scrib = Scribbles.new()
	add_child(scrib)
	scrib.setup(self, page_under, page_over)
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

## The road is laid from a tightness profile: each segment is (length, start curvature, end curvature), with
## curvature in 1/px (+ turns right). Points every STEP follow it, so corners ease in and out instead of
## snapping from straight to full curve. Width eases towards what the block wants (piece_w).
func _lay(segs: Array) -> void:
	var dir := road_dir
	var w := widths[widths.size() - 1]
	var want := _width_now() * piece_w
	for sg in segs:
		var n := maxi(1, int(float(sg[0]) / STEP))
		for k in n:
			dir += lerpf(float(sg[1]), float(sg[2]), (k + 0.5) / n) * STEP
			road.append(road[road.size() - 1] + Vector2.from_angle(dir) * STEP)
			w = move_toward(w, want, 2.5)
			widths.append(w)
			lens.append(lens[lens.size() - 1] + STEP)
	road_dir = dir


## A straight (kept for the start and the fallback).
func _extend(dir: float, length: float, turn: float) -> void:
	road_dir = dir
	_lay([[length, turn / length, turn / length]])


func _width_now() -> float:
	return clampf(150.0 - lens[lens.size() - 1] / 400.0, 100.0, 150.0)  # it narrows slowly, never speeds up


## How far into the run (0..1): corners tighten, links shorten and peaks come more often with it.
func _difficulty() -> float:
	return clampf(lens[lens.size() - 1] / 16000.0, 0.0, 1.0)


## One corner: ease in, hold the radius, ease out, turning `angle` in all towards `side` (-1 left, 1 right).
## Entry eases are longer than exits, so a corner announces itself. `r2` > 0 makes it tighten half way
## (a decreasing-radius corner). The apex is recorded for scoring later.
func _corner(side: float, r: float, angle: float, kind: String, r2 := 0.0) -> Array:
	r = maxf(r, R_MIN)
	var k := side / r
	var ein := r * 0.35
	var eout := r * 0.22
	var arc := angle * r - (ein + eout) * 0.5
	if arc < r * 0.2:  # short corner: shrink the eases to fit
		var f := angle * r / ((ein + eout) * 0.5 + r * 0.2)
		ein *= f
		eout *= f
		arc = r * 0.2
	var segs := [[ein, 0.0, k]]
	if r2 > 0.0:
		var k2 := side / maxf(r2, R_MIN)
		segs += [[arc * 0.45, k, k], [r * 0.3, k, k2], [arc * 0.4, k2, k2], [eout, k2, 0.0]]
	else:
		segs += [[arc, k, k], [eout, k, 0.0]]
	pending_corners.append({"side": side, "r": r, "kind": kind, "at": ein + arc * 0.5})
	return segs


## Run-up before a drift corner: long enough to see it coming and set up (about a second, more for hairpins).
func _runup(secs: float) -> Array:
	return [[maxf(60.0, secs * 0.4 * 240.0 * lerpf(1.0, 0.85, _difficulty())), 0.0, 0.0]]


## The building blocks. Each returns its segments; sizes come from the car's drift circle (see report).
func _block(kind: String, side: float) -> Array:
	var d := _difficulty()
	var drift_r := func(): return lerpf(rng.randf_range(180.0, 260.0), rng.randf_range(150.0, 200.0), d)
	var link := lerpf(rng.randf_range(60.0, 90.0), rng.randf_range(35.0, 60.0), d)
	match kind:
		"constant":  # the signature corner: long and steady
			return _runup(1.0) + _corner(side, drift_r.call(), rng.randf_range(1.7, 2.6), kind) + [[50.0, 0.0, 0.0]]
		"hairpin":
			return _runup(1.3) + _corner(side, lerpf(160.0, R_MIN, d), rng.randf_range(2.4, deg_to_rad(160.0)), kind) + [[60.0, 0.0, 0.0]]
		"switchback":  # a drift flicked into the counter-drift
			var a := rng.randf_range(1.2, 1.8)
			return _runup(1.0) + _corner(side, drift_r.call(), a, kind) + [[link, 0.0, 0.0]] + _corner(-side, drift_r.call(), a * rng.randf_range(0.9, 1.1), kind) + [[50.0, 0.0, 0.0]]
		"esses":
			var segs := _runup(0.9)
			var s := side
			for i in rng.randi_range(3, 4):
				segs += _corner(s, lerpf(rng.randf_range(170.0, 240.0), rng.randf_range(150.0, 190.0), d), rng.randf_range(1.0, 1.4), kind) + [[link * 0.7, 0.0, 0.0]]
				s = -s
			return segs
		"double_apex":  # same way twice, with a short breath between
			var r: float = drift_r.call()
			return _runup(1.0) + _corner(side, r, rng.randf_range(1.0, 1.4), kind) + [[link * 0.6, 0.0, 0.0]] + _corner(side, r * rng.randf_range(0.85, 1.0), rng.randf_range(1.0, 1.4), kind) + [[50.0, 0.0, 0.0]]
		"sweeper":  # a breather, taken flat
			return _corner(side, rng.randf_range(500.0, 900.0), rng.randf_range(0.4, 0.9), kind)
		"pad":  # wide open with one long turn
			piece_w = rng.randf_range(1.5, 1.8)
			return [[70.0, 0.0, 0.0]] + _corner(side, rng.randf_range(220.0, 300.0), rng.randf_range(2.0, 2.6), kind) + [[70.0, 0.0, 0.0]]
		"squeeze":  # narrow, gentle, a control test
			piece_w = rng.randf_range(0.6, 0.7)
			return _corner(side, rng.randf_range(450.0, 700.0), rng.randf_range(0.3, 0.6), kind) + [[90.0, 0.0, 0.0]]
		"kink":  # keeps a straight alive
			return [[rng.randf_range(120.0, 220.0), 0.0, 0.0]] + _corner(side, 800.0, rng.randf_range(0.12, 0.25), kind) + [[rng.randf_range(100.0, 180.0), 0.0, 0.0]]
		"decreasing":  # late and rare: it tightens half way
			var r := rng.randf_range(220.0, 280.0)
			return _runup(1.2) + _corner(side, r, rng.randf_range(1.8, 2.4), kind, r * 0.6) + [[50.0, 0.0, 0.0]]
		_:  # "straight": a release where speed builds towards the top
			return [[rng.randf_range(120.0, 220.0), 0.0, 0.0]]


## The road's rhythm, as phrases of blocks: calm, build, peak, release. Weights move towards the peaks
## as the run goes on. Corners are linked left-right by rule; no block repeats right after itself.
const PHRASES := [
	{"name": "calm", "n": [2, 3], "w": {"constant": 5.0, "switchback": 2.0, "double_apex": 1.0, "pad": 1.0, "sweeper": 0.3}},
	{"name": "build", "n": [3, 4], "w": {"constant": 4.0, "switchback": 3.0, "double_apex": 1.5, "esses": 0.6}},
	{"name": "peak", "n": [3, 5], "w": {"hairpin": 2.2, "esses": 1.0, "switchback": 2.0, "constant": 2.5, "squeeze": 1.2, "decreasing": 0.6}},
	{"name": "release", "n": [2, 2], "w": {"pad": 2.5, "constant": 3.0, "straight": 0.5, "kink": 0.3}},
]


func _grow_road() -> void:
	while lens[lens.size() - 1] < _progress_len() + 2200.0:
		if phrase_left <= 0:
			phase = (phase + 1) % PHRASES.size()
			var ph: Dictionary = PHRASES[phase]
			phrase_left = rng.randi_range(ph["n"][0], ph["n"][1])
			if phase == 0 and lens[lens.size() - 1] > 400.0:
				var s := rng.randi_range(0, 3)
				style = s if s < style else s + 1  # each lap of the rhythm gets a new drawing style
		var start := road.size() - 1
		var placed := false
		for attempt in 8:
			var kind := _pick_block()
			if history.size() > 0 and kind == history[history.size() - 1]:
				continue
			if _try_block(kind, attempt):
				history.append(kind)
				if history.size() > 4:
					history.pop_front()
				placed = true
				break
		if not placed:
			fallbacks += 1
			piece_w = 1.0
			pending_corners.clear()
			_lay([[120.0, 0.0, wrapf(-PI * 0.5 - road_dir, -PI, PI) * 0.6 / 120.0]])  # turn back up the page
		phrase_left -= 1
		_chunk(start)
		_page_things(start)
		scrib.on_block(start)
		_place_things(start)


func _pick_block() -> String:
	var w: Dictionary = PHRASES[phase]["w"]
	var d := _difficulty()
	var total := 0.0
	for k in w:
		total += _block_weight(k, w[k], d)
	var r := rng.randf() * total
	for k in w:
		r -= _block_weight(k, w[k], d)
		if r <= 0.0:
			return k
	return "constant"


func _block_weight(kind: String, base: float, d: float) -> float:
	if kind == "decreasing":
		return base * smoothstep(0.5, 0.9, d)  # late in a run only, and rare
	if kind in ["hairpin", "esses", "squeeze"]:
		return base * lerpf(0.6, 1.3, d)
	return base


## Which way the next block turns: back towards "up" if the road has wandered, otherwise the opposite of
## the last corner (left-right links), and never three the same way running.
func _next_side() -> float:
	var off_up := wrapf(road_dir - (-PI * 0.5), -PI, PI)
	if absf(off_up) > 0.7:
		return -signf(off_up)
	if same_run >= 2:
		return -last_side
	return -last_side if rng.randf() < 0.75 else last_side


## Builds a block and keeps it only if it stays clear of the road already laid and keeps heading up the
## page. A failed try is rolled back; later tries use gentler sizes.
func _try_block(kind: String, attempt: int) -> bool:
	var keep := road.size()
	var start_dir := road_dir
	var side := _next_side()
	piece_w = 1.0
	pending_corners.clear()
	var segs := _block(kind, side)
	if attempt >= 4:  # gentler retry: open every corner up a little
		for sg in segs:
			sg[1] = float(sg[1]) * 0.75
			sg[2] = float(sg[2]) * 0.75
	_lay(segs)
	piece_w = 1.0
	var ok := absf(wrapf(road_dir - (-PI * 0.5), -PI, PI)) < 1.9
	if ok:
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
		pending_corners.clear()
		return false
	# Record the corners (apex point, which way, how tight) for scoring later; track the left-right links.
	for c in pending_corners:
		if c["r"] >= 450.0:
			continue  # sweepers and kinks are taken flat: not drift corners
		var i := clampi(keep + int(float(c["at"]) / STEP), 0, road.size() - 1)
		corners.append({"apex": road[i], "len": lens[i], "side": c["side"], "r": c["r"], "kind": c["kind"]})
		same_run = same_run + 1 if c["side"] == last_side else 1
		last_side = c["side"]
	pending_corners.clear()
	return true


## Draws the road from point `from` to the end once, as real strokes: the hand moves the pen a few hundred
## pixels at a time, pressing harder in the bends (darker, wider), lifting at the ends (thinner), sometimes
## leaving a little gap or overshooting, going back over some strokes, and a pencil hand smears beside them.
func _chunk(from: int) -> void:
	var pts := road.slice(from)
	var ws := widths.slice(from)
	var ls := lens.slice(from)
	var m := pts.size()
	if m < 2:
		return
	var st := style
	var holder := Node2D.new()
	road_layer.add_child(holder)
	chunks.append({"node": holder, "end_len": ls[m - 1]})
	var nrm := PackedVector2Array()
	nrm.resize(m)
	var bend := PackedFloat32Array()
	bend.resize(m)
	for i in m:
		nrm[i] = (pts[mini(m - 1, i + 1)] - pts[maxi(0, i - 1)]).normalized().orthogonal()
		if i > 0 and i < m - 1:
			bend[i] = absf((pts[i] - pts[i - 1]).angle_to(pts[i + 1] - pts[i])) / STEP
	var ink: Array = INK[st]
	for side in [-1.0, 1.0]:
		var edge := PackedVector2Array()
		edge.resize(m)
		for i in m:
			var wob := sin(ls[i] * 0.021 + side * 3.0) * 1.4 + sin(ls[i] * 0.07) * 0.6
			edge[i] = pts[i] + nrm[i] * side * (ws[i] * 0.5 + wob)
		var i := 0
		while i < m - 1:
			var j := mini(m - 1, i + rng.randi_range(35, 90))
			if m - 1 - j < 14:
				j = m - 1
			_stroke(holder, edge, bend, nrm, side, i, j, ink)
			i = j + (1 if rng.randf() < 0.15 else -1)  # pencil lifted: a small gap, or the next stroke overlaps
			i = maxi(i, 0)
		# A palm dragged through fresh graphite smears it, on the side the hand rests (screen right).
		if ink[4] > 0.0 and rng.randf() < ink[4]:
			var out: float = (nrm[m / 2] * side).x
			if out > 0.2:
				var a := rng.randi_range(0, m / 3)
				var b := mini(m - 1, a + rng.randi_range(m / 3, m - 1))
				var sm := PackedVector2Array()
				for k in range(a, b + 1):
					sm.append(edge[k] + nrm[k] * side * 9.0)
				_line(holder, sm, "smudge", Color(0.25, 0.25, 0.28, 0.09), rng.randf_range(18.0, 26.0))
	if st == 4:  # dashes down the middle
		var dn := DrawNode.new()
		dn.draw_fn = func(c: Node2D): _draw_road(c, pts, ls)
		holder.add_child(dn)


## One stroke over edge points a..b, with pressure from the bend and tapered ends, landing a touch early and
## overshooting a touch at the end; sometimes traced over again, slightly off.
func _stroke(holder: Node2D, edge: PackedVector2Array, bend: PackedFloat32Array, nrm: PackedVector2Array, side: float, a: int, b: int, ink: Array) -> void:
	if b - a < 2:
		return
	var p := edge.slice(a, b + 1)
	var t0 := (p[1] - p[0]).normalized()
	var t1 := (p[p.size() - 1] - p[p.size() - 2]).normalized()
	p.insert(0, p[0] - t0 * rng.randf_range(2.0, 6.0))
	p.append(p[p.size() - 1] + t1.rotated(rng.randf_range(-0.08, 0.08)) * rng.randf_range(4.0, 12.0))
	var n := p.size()
	var curve := Curve.new()
	var grad := Gradient.new()
	grad.remove_point(1)
	var col: Color = ink[1]
	var seed := rng.randf() * 10.0
	var samples := clampi(n / 5, 4, 24)
	for s in samples + 1:
		var t := float(s) / samples
		var k := clampi(a + int(t * (b - a)), a, b)
		var press := 0.78 + 0.42 * smoothstep(1.0 / 700.0, 1.0 / 160.0, bend[k]) + 0.07 * sin(t * 9.0 + seed)
		press *= lerpf(0.45, 1.0, smoothstep(0.0, 0.06, t)) * lerpf(0.4, 1.0, smoothstep(1.0, 0.9, t))  # lift at the ends
		curve.add_point(Vector2(t, clampf(press, 0.0, 1.0)))
		var c := col
		c.a = col.a * clampf(0.55 + 0.45 * press, 0.0, 1.0)
		if s == 0:
			grad.set_color(0, c)
		else:
			grad.add_point(t, c)
	var l := _line(holder, p, ink[0], col, ink[2])
	l.width_curve = curve
	l.gradient = grad
	if rng.randf() < ink[3]:  # gone over again, a little off the first line
		var q := PackedVector2Array()
		var off := rng.randf_range(0.8, 1.8) * (1.0 if rng.randf() < 0.5 else -1.0)
		var qa := rng.randi_range(0, n / 4)
		var qb := n - 1 - rng.randi_range(0, n / 4)
		for k in range(qa, qb + 1):
			var e := clampi(a + k - 1, a, b)
			q.append(p[k] + nrm[e] * side * off * (0.6 + 0.4 * sin(k * 0.2 + seed)))
		var c2 := col
		c2.a *= 0.38
		_line(holder, q, ink[0], c2, ink[2] * 0.7)


func _line(holder: Node2D, p: PackedVector2Array, tex_name: String, col: Color, w: float) -> Line2D:
	var l := Line2D.new()
	l.points = p
	l.width = w
	l.default_color = col
	l.texture = _tex(tex_name)
	l.texture_mode = Line2D.LINE_TEXTURE_TILE
	l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	holder.add_child(l)
	return l


static func _tex(tex_name: String) -> Texture2D:
	if not page_tex.has(tex_name):
		page_tex[tex_name] = load("res://art/page/%s.png" % tex_name)
	return page_tex[tex_name]


## The notebook itself, along the run: where one page ends and the next starts (torn binding edge, punched
## holes, the page number), coffee rings from a mug, fold creases, a stray staple, and writing from the other
## side of the page showing through.
func _page_things(from: int) -> void:
	var L := lens[lens.size() - 1]
	var mid := road[clampi((from + road.size()) / 2, 0, road.size() - 1)]
	if L >= next_page:
		next_page = L + rng.randf_range(4500.0, 6500.0)
		page_no += 1
		var under := Node2D.new()
		page_under.add_child(under)
		var y := mid.y
		# The torn edge wanders and thickens and thins, as a real rip does.
		var tp := PackedVector2Array()
		var sd := rng.randf() * 10.0
		var x := mid.x - 2200.0
		while x <= mid.x + 2200.0:
			tp.append(Vector2(x, y + 6.0 * sin(x * 0.004 + sd) + 3.0 * sin(x * 0.013 + sd * 2.0) + rng.randf_range(-1.5, 1.5)))
			x += 40.0
		var tl := _line(under, tp, "torn", Color.WHITE, 36.0)
		var tc := Curve.new()
		for k in 11:
			tc.add_point(Vector2(k / 10.0, rng.randf_range(0.7, 1.25)))
		tl.width_curve = tc
		# Each hole punched a little differently: spacing, size, angle; some torn open, now and then one missing.
		var xs := PackedFloat32Array()
		x = mid.x - 2200.0 + rng.randf_range(0.0, 40.0)
		while x < mid.x + 2200.0:
			if rng.randf() > 0.04:
				var h := Sprite2D.new()
				var torn := rng.randf() < 0.22
				h.texture = _tex("hole_%d" % (rng.randi_range(5, 7) if torn else rng.randi_range(0, 4)))
				h.position = Vector2(x, y + 30.0 + rng.randf_range(-2.5, 2.5) + 2.0 * sin(x * 0.01 + sd))
				h.rotation = rng.randf_range(-0.08, 0.08) if torn else rng.randf() * TAU
				h.scale = Vector2.ONE * 0.9 * rng.randf_range(0.93, 1.07)
				under.add_child(h)
				xs.append(x)
			x += 46.0 * rng.randf_range(0.9, 1.12)
		seams.append({"y": y + 15.0, "x0": mid.x - 2200.0, "x1": mid.x + 2200.0, "holes": xs, "hit": false, "len": L + 2600.0})
		var num := DrawNode.new()
		var txt: String = String(["p. %d", "%d", "pg %d", "- %d -"][rng.randi() % 4]) % page_no
		var at := Vector2(mid.x + rng.randf_range(130.0, 230.0) * (1.0 if rng.randf() < 0.5 else -1.0), y + 95)
		var tilt := rng.randf_range(-0.12, 0.12)
		num.draw_fn = func(c: Node2D):
			c.draw_set_transform(at, tilt)
			c.draw_string(hand_font(), Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.2, 0.22, 0.3, 0.75))
		under.add_child(num)
		page_bits.append({"node": under, "len": L + 2600.0})
	if L >= next_decor:
		next_decor = L + rng.randf_range(900.0, 1900.0)
		var i := rng.randi_range(from, road.size() - 1)
		var c := road[i]
		var nn := Vector2.from_angle(_dir_at(i) + PI * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
		var roll := rng.randf()
		var node: Node2D
		if roll < 0.4:  # a mug was put down here: usually beside the road, sometimes on it
			var s := Sprite2D.new()
			s.texture = _tex("coffee_%d" % (rng.randi() % 3))
			s.rotation = rng.randf() * TAU
			s.scale = Vector2.ONE * rng.randf_range(0.55, 0.75)
			s.position = c + nn * (widths[i] * 0.5 + rng.randf_range(-40.0, 160.0))
			page_over.add_child(s)
			node = s
		elif roll < 0.62:  # the page was folded once: a crease right across it
			var a := rng.randf_range(-0.5, 0.5)
			var d := Vector2.from_angle(a)
			node = Node2D.new()
			page_over.add_child(node)
			_line(node, PackedVector2Array([c - d * 2400.0, c + d * 2400.0]), "crease", Color.WHITE, 40.0)
		elif roll < 0.75:  # a stray staple
			var s := Sprite2D.new()
			s.texture = _tex("staple")
			s.rotation = rng.randf() * TAU
			s.scale = Vector2.ONE * 0.8
			s.position = c + nn * (widths[i] * 0.5 + rng.randf_range(60.0, 220.0))
			page_over.add_child(s)
			node = s
		else:  # writing on the back of the page shows through
			var s := Sprite2D.new()
			s.texture = _tex("showthrough_%d" % (rng.randi() % 3))
			s.rotation = rng.randf_range(-0.05, 0.05)
			s.position = c + nn * (widths[i] * 0.5 + rng.randf_range(220.0, 380.0))
			page_under.add_child(s)
			node = s
		page_bits.append({"node": node, "len": L + 2600.0})


## The punched holes along a page edge, one texture tile per hole.
static func _hole_row() -> Texture2D:
	if not page_tex.has("hole_row"):
		var hole := (load("res://art/page/hole.png") as Texture2D).get_image()
		hole.convert(Image.FORMAT_RGBA8)
		var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
		img.blit_rect(hole, Rect2i(0, 0, 40, 40), Vector2i(12, 0))
		page_tex["hole_row"] = ImageTexture.create_from_image(img)
	return page_tex["hole_row"]


static func hand_font() -> Font:
	if not page_tex.has("font"):
		page_tex["font"] = load("res://fonts/hand/Caveat.ttf")
	return page_tex["font"]


## Obstacles and coins along the newest piece, more of them as the road goes on (and in tense stretches).
func _place_things(from: int) -> void:
	var depth := lens[lens.size() - 1]
	if depth < 700.0 or road.size() - from < 4:
		return
	things_dirty = true
	var chance := clampf(0.3 + depth / 12000.0, 0.3, 0.8) * (1.4 if phase == 2 else 0.8 if phase == 0 or phase == 3 else 1.0)
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
		_play("bump", 0.0)
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
		while not corners.is_empty() and float(corners[0]["len"]) < behind:
			corners.pop_front()
		scrib.prune(behind)
		while not seams.is_empty() and float(seams[0]["len"]) < behind:
			seams.pop_front()
		while not page_bits.is_empty() and float(page_bits[0]["len"]) < behind:
			(page_bits.pop_front()["node"] as Node).queue_free()
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
				if m["node"] == mark_bucket:
					mark_bucket = null
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
	_squeal(delta)
	_engine(delta)
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
		if scrib:
			scrib.save_seen()  # the app may be closed from here


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
	var cruise := SPEED if on_road else OFF_SPEED
	if speed < cruise:
		if speed < STRONG_PULL or not on_road:
			speed = move_toward(speed, minf(cruise, STRONG_PULL) if on_road else cruise, ACCEL * delta)
		if on_road and speed >= STRONG_PULL - 0.01:
			speed += (cruise - speed) * (1.0 - exp(-delta * TOP_EASE))
	else:
		speed += (cruise - speed) * (1.0 - exp(-delta * 0.7))
	if slip > 0.15 and speed > DRIFT_FLOOR:  # the tyres scrub: a long drift drops a gear, the exit pulls back up
		speed = maxf(DRIFT_FLOOR, speed - SCRUB * sin(minf(slip, 1.4)) * delta)
	pos += Vector2.from_angle(vdir) * speed * delta
	_seam_bump()
	if off > half + 170.0:
		_crash("Lost the road")


## Over a page edge the car thumps down the step onto the next sheet; a wheel that finds a punched hole
## drops in like a gutter: a harder knock, a twitch of the nose, some speed lost, a squash and a shake.
func _seam_bump() -> void:
	for sm in seams:
		if sm["hit"] or pos.x < sm["x0"] or pos.x > sm["x1"]:
			continue
		if signf(prev_y - sm["y"]) != signf(pos.y - sm["y"]):
			sm["hit"] = true
			var drop := false
			for hx in (sm["holes"] as PackedFloat32Array):
				if absf(hx - pos.x) < 22.0:
					drop = true
					break
			jolt_t = clock
			jolt_k = 1.0 if drop else 0.5
			speed *= 0.9 if drop else 0.97
			yaw += rng.randf_range(-1.0, 1.0) * jolt_k
			_play("bump", -2.0 if drop else -9.0, 0.75)
			Game.vibrate(45 if drop else 15)
	prev_y = pos.y


## How far the car is sunk in a bump right now (0..1), for the squash and the camera shake.
func _jolt() -> float:
	var t := clock - jolt_t
	return jolt_k * exp(-t * 9.0) if t >= 0.0 else 0.0


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
	var ripping := slip > 0.75 and speed > 110.0  # anywhere on the sheet: off the track is the same paper
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
				if clock - rip_t > 0.3:  # the paper keeps tearing: a fresh rip every so often
					rip_t = clock
					_play("rip", -3.0, 0.9 + slip * 0.15)
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


## Finished marks are drawn in groups of up to 24 per node (one node each cost the phone hundreds of draw
## calls on a drifty run). A group is redrawn when a mark joins it, then stays still.
func _still(fn: Callable, p: Vector2) -> void:
	if mark_bucket == null or bucket_fns.size() >= 24:
		var fns: Array = []
		bucket_fns = fns
		mark_bucket = DrawNode.new()
		mark_bucket.draw_fn = func(c: Node2D):
			for f in fns:
				(f as Callable).call(c)
		marks_layer.add_child(mark_bucket)
		still_marks.append({"node": mark_bucket, "p": p})
	bucket_fns.append(fn)
	still_marks[still_marks.size() - 1]["p"] = p  # a group is dropped once its newest mark is far behind
	mark_bucket.queue_redraw()


# ---------------------------------------------------------------- sound

func _sound_setup() -> void:
	for k in SOUNDS:
		snd[k] = (SOUNDS[k] as Array).map(func(p): return load(p))
	squeal = AudioStreamPlayer.new()
	var loop: AudioStreamOggVorbis = (load("res://sounds/squeal_loop.ogg") as AudioStreamOggVorbis).duplicate()
	loop.loop = true
	squeal.stream = loop
	squeal.volume_db = -80.0
	add_child(squeal)
	squeal.play()
	for i in 5:
		var p := AudioStreamPlayer.new()
		add_child(p)
		shots.append(p)
	var eng: Dictionary = ENGINES.get(String(_load().get_value("dev", "engine", "generic")), ENGINES["generic"])
	engine_bov = eng["bov"]
	for layer in eng["layers"]:
		var p := AudioStreamPlayer.new()
		var st: AudioStreamOggVorbis = (load(layer[0]) as AudioStreamOggVorbis).duplicate()
		st.loop = true
		p.stream = st
		p.volume_db = -80.0
		add_child(p)
		p.play()
		engine_layers.append([p, float(layer[1])])
	_radio()


## The music is a session-long radio (radio.gd) on the root, so it carries on across runs.
func _radio() -> void:
	var pick := String(_load().get_value("dev", "music", "shuffle"))
	var r: Node = get_tree().root.get_node_or_null("Radio")
	if r == null:
		r = Radio.new()
		r.name = "Radio"
		get_tree().root.add_child(r)
		var paths := {}
		for k in TRACKS:
			paths[k] = TRACKS[k]["path"]
		r.off = pick == "off" or not Game.music_on
		r.setup(paths, pick)
	else:
		r.choose(pick)


func _play(kind: String, db: float, pitch := 1.0) -> void:
	if not Game.sound_on:
		return
	var p := shots[shot_i]
	shot_i = (shot_i + 1) % shots.size()
	var takes: Array = snd[kind]
	p.stream = takes[rng.randi() % takes.size()]
	p.volume_db = db
	p.pitch_scale = pitch * rng.randf_range(0.94, 1.06)  # never quite the same twice
	p.play()


## Tyres: silent while gripping, rising in and out with the slide (and softer as the car slows). Higher
## pitched the harder it slides.
func _squeal(delta: float) -> void:
	var want := 0.0
	if state == "play" and Game.sound_on:
		want = smoothstep(0.15, 0.9, slip) * clampf(speed / SPEED, 0.3, 1.0)
	squeal_vol = move_toward(squeal_vol, want, delta * 3.0)
	squeal.volume_db = linear_to_db(maxf(squeal_vol, 0.0001)) - 6.0
	squeal.pitch_scale = 0.85 + 0.3 * clampf(slip / 1.2, 0.0, 1.0)


## An automatic gearbox: the revs climb through each gear with speed, it changes up near the top and down
## when the car slows (off the line), and in a drift the revs flare because the rear wheels spin. The rev
## needle eases rather than jumps, so a change up is a quick fall and a change down a quick rise; the
## throttle lifts for a moment at each change. One engine recording is pitched to the revs.
func _engine(delta: float) -> void:
	var lo := 0.0 if gear == 1 else float(GEAR_TOP[gear - 2])
	var hi := float(GEAR_TOP[gear - 1])
	if speed > hi and gear < GEAR_TOP.size():
		gear += 1
		shift_t = clock
		if engine_bov and state == "play":
			_play("bov", -8.0)  # the turbo dumps its boost as the throttle lifts for the change
	elif gear > 1 and speed < lo - 12.0:
		gear -= 1
		shift_t = clock
	lo = 0.0 if gear == 1 else float(GEAR_TOP[gear - 2])
	hi = float(GEAR_TOP[gear - 1])
	var t := clampf((speed - lo) / (hi - lo), 0.0, 1.0)
	var want := lerpf(IDLE_RPM * 1.6 if gear == 1 else PULL_RPM, SHIFT_RPM, t)
	if state == "play":
		want += drift_amt * clampf(slip / 0.8, 0.0, 1.0) * 1800.0  # wheelspin in the slide
	else:
		want = IDLE_RPM * 1.2  # crashed: off the throttle, settling to idle
	want = minf(want, 7800.0)
	rpm += (want - rpm) * (1.0 - exp(-delta * 9.0))
	var lift := smoothstep(0.0, 0.18, clock - shift_t)  # throttle lifts for the change, then back on
	var load_k := 1.0 if state == "play" else 0.5
	var vol := (0.55 + 0.45 * clampf((rpm - IDLE_RPM) / (SHIFT_RPM - IDLE_RPM), 0.0, 1.0)) * lerpf(0.55, 1.0, lift) * load_k
	if not Game.sound_on:
		vol = 0.0
	# Each layer plays nearest the revs it was recorded at, fading into its neighbours.
	var n := engine_layers.size()
	for k in n:
		var p: AudioStreamPlayer = engine_layers[k][0]
		var base: float = engine_layers[k][1]
		var w := 1.0
		if n > 1:
			var below: float = engine_layers[k - 1][1] if k > 0 else -INF
			var above: float = engine_layers[k + 1][1] if k < n - 1 else INF
			if rpm < base and k > 0:
				w = clampf((rpm - below) / (base - below), 0.0, 1.0)
			elif rpm > base and k < n - 1:
				w = clampf((above - rpm) / (above - base), 0.0, 1.0)
		p.volume_db = linear_to_db(maxf(vol * sqrt(w), 0.0001)) - 10.0  # equal-power fade
		p.pitch_scale = clampf(rpm / base, 0.35, 3.0)


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
			_play("coin", -6.0)


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
	_play("crash", 0.0)
	Game.vibrate(70)
	_word(why.to_upper(), pos + Vector2(0, -60), Color(0.75, 0.2, 0.2))
	prev_best = int(_load().get_value("best", "score", 0))
	scrib.save_seen()
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


## The one camera: top down, north up, a little ahead of the car, zoomed to show the road coming up. If a
## note or drawing sits beside that stretch, it zooms out enough to show all of it rather than cut it off.
func _follow(delta: float) -> void:
	cam_rot = 0.0
	Prop.view_rot = 0.0
	var lo := pos
	var hi := pos
	for i in range(progress_i, mini(road.size(), progress_i + 70), 5):
		lo = lo.min(road[i])
		hi = hi.max(road[i])
	var road_box := Rect2(lo, hi - lo).grow(170.0)
	var box := road_box
	for rr in scrib.rects:
		var rc: Rect2 = rr[0]
		if rc.intersects(road_box.grow(60.0)):
			box = box.merge(rc.grow(30.0))
	var want := clampf(minf(view.x / box.size.x, view.y / box.size.y), 0.45, 1.15)
	# Ease the goal itself first (a note coming into the frame must not make it jump), then follow it, and
	# never change zoom faster than a gentle rate either way.
	cam_goal_zoom += (want - cam_goal_zoom) * (1.0 - exp(-delta * 0.9))
	var z := cam.zoom.x
	z += clampf((cam_goal_zoom - z) * (1.0 - exp(-delta * 1.6)), -0.35 * delta, 0.35 * delta)
	cam.zoom = Vector2.ONE * z
	var target := box.get_center().lerp(pos, 0.45)
	cam_goal_pos = cam_goal_pos.lerp(target, 1.0 - exp(-delta * 2.5))
	cam.position = cam.position.lerp(cam_goal_pos, 1.0 - exp(-delta * 3.0))
	var shake := 7.0 * _jolt()
	cam.offset = Vector2(rng.randf_range(-shake, shake), rng.randf_range(-shake, shake))


# ---------------------------------------------------------------- drawing

## Dashes down the middle of a dashed-style stretch.
func _draw_road(n: Node2D, pts: PackedVector2Array, ls: PackedFloat32Array) -> void:
	var m := pts.size()
	for i in range(0, m - 3, 6):
		if int(ls[i] / 48.0) % 2 == 0:
			n.draw_line(pts[i], pts[i + 3], Color(0.25, 0.25, 0.28, 0.4), 2.2, true)


func _draw_skid(n: Node2D, sk: Dictionary) -> void:
	n.draw_polyline(sk["pts"], Color(0.2, 0.2, 0.22, float(sk["a"]) * 0.45), 5.0, false)  # no antialiasing: soft enough, and it batches


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
	# One batch of triangles for the whole rip (shadow, torn white edge, the desk through the hole): drawn as
	# separate pieces it cost the phone hundreds of draw calls on a drifty run.
	var sh := Vector2(1.5, 2.0)
	var tp := PackedVector2Array()
	var tc := PackedColorArray()
	var layers := [[outer_l, outer_r, sh, Color(0, 0, 0, 0.14)], [outer_l, outer_r, Vector2.ZERO, Color(0.995, 0.99, 0.975)], [hole_l, hole_r, Vector2.ZERO, Color(0.45, 0.3, 0.18)]]
	for ly in layers:
		var L: PackedVector2Array = ly[0]
		var R: PackedVector2Array = ly[1]
		var o: Vector2 = ly[2]
		for i in m - 1:
			tp.append_array([L[i] + o, L[i + 1] + o, R[i + 1] + o, L[i] + o, R[i + 1] + o, R[i] + o])
			for k in 6:
				tc.append(ly[3])
	_tris(n, tp, tc)
	n.draw_polyline(pts, Color(0.32, 0.2, 0.11, 0.55), maxf(1.0, ww[m / 2] * 0.22), false)  # wood grain
	var fp := PackedVector2Array()
	var fc := PackedColorArray()
	var fl := PackedVector2Array()
	for i in range(2, m - 1, 4):  # curled flaps of paper along the rip
		var a := pts[i - 1]
		var b := pts[i + 1]
		var along := (b - a).normalized()
		var nrm := along.orthogonal() * (1.0 if int(i / 4) % 2 == 0 else -1.0)
		var base := pts[i] + nrm * ww[i] * 0.5
		var tip := base + nrm * (3.0 + absf(sin(i + sd)) * 4.0) + along * 3.0
		fp.append_array([base - along * 3.5, tip, base + along * 3.5])
		for k in 3:
			fc.append(Color(0.97, 0.96, 0.93))
		fl.append_array([base, tip])
	_tris(n, fp, fc)
	if fl.size() >= 2:
		n.draw_multiline(fl, Color(0, 0, 0, 0.1), 1.0)


## Plain triangles (3 points each) in one draw call.
func _tris(n: Node2D, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if pts.size() < 3:
		return
	var idx := PackedInt32Array()
	idx.resize(pts.size())
	for k in pts.size():
		idx[k] = k
	RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, pts, cols)


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
	var sz := Vector2.ONE * car_px * car_scale * (1.0 - 0.07 * _jolt())
	n.draw_set_transform(pos + Vector2(-6, 8).rotated(cam_rot), rest)
	n.draw_texture_rect_region(car_tex, Rect2(-sz * 0.5, sz), src, Color(0.1, 0.08, 0.05, 0.28))
	n.draw_set_transform(pos, rest)
	n.draw_texture_rect_region(car_tex, Rect2(-sz * 0.5, sz), src)
	n.draw_set_transform(Vector2.ZERO)
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
	if scrib:
		scrib.save_seen()  # remember the notes seen, however the run ended
	get_viewport().canvas_cull_mask = 0xFFFFFFFF  # a 3D camera hid the flat world; the title screen needs it back
