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
const Inks = preload("res://scripts/inks.gd")
const TyreFx = preload("res://scripts/tyre_fx.gd")
const StartPage = preload("res://scripts/start_page.gd")
const PauseNote = preload("res://scripts/pause_note.gd")
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
## Handling models (dev "handling"). Flow: the car is always loose, a held side swings it into a slide that
## settles at a steady angle and carries the car round; letting go or switching sides swings it back like a
## pendulum. Classic: the older grip-then-hold-to-drift model. Flow roads are wider with bigger corners.
const HANDLING := {"flow": {"name": "Flow (always drifting)"}, "classic": {"name": "Classic (hold to drift)"}}
const FLOW_ROAD := 1.45  # how much wider and rounder the road is in flow mode
const FLOW_TURN := 1.35  # how hard the slide bends the travel (rad/s at a full sideways slide)
const FLOW_ANGLE := [32.0, 50.0]  # the settled slide angle (degrees): light hold .. held on
const FLOW_DEEP := [18.0, 1.2, 3.5]  # held on the same side, the slide keeps deepening: + degrees, from .. to (s)
const FLOW_SPRING := 22.0  # pendulum: how hard the car swings to the wanted angle
const FLOW_DAMP := 6.5  # and how fast the swing settles (lower overshoots more)

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
	"stamp": ["res://sounds/stamp.wav"],  # made for the game (sounds/CREDITS.txt)
	"combo": ["res://sounds/combo_up.wav"],
	"clip": ["res://sounds/clip.wav"],
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
var state := "play"  # home, play, crashed, summary
var start_home := false  # set before adding: begin parked at the start line, the home screen (start_page.gd)
var start_page: StartPage
var no_road: Array = []  # world rects the road must not run through (the start page's gear and settings)
var hold_lock := false  # the start hold is being ignored (see _input_side)
var home_hold := 0.0  # how long a side has been held on the start page (a short hold starts the run)
const HOLD_TO_START := 0.25
var pause_btn: Button
var hold_delay := DEFAULT_HOLD

# The car
var pos := Vector2.ZERO
var heading := -PI * 0.5
var vdir := -PI * 0.5  # the way it is actually travelling
var yaw := 0.0
var speed := 0.0  # each run pulls away from a standstill
var slip := 0.0
var hold_t := 0.0
var flow := true  # dev "handling" is flow
var road_k := 1.0  # road size factor (FLOW_ROAD in flow mode)
var slip_v := 0.0  # how fast the slide angle is swinging (flow)
var same_t := 0.0  # how long the same side has been held (flow: a switch starts it again)
var held_side := 0
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
var inks: Inks  # what the pens mean: red edges, highlighter, dots, crayon, ink (inks.gd)
var seams: Array = []  # page edges ahead: {y, x0, x1, holes, hit, len}
var jolt_t := -9.0
var jolt_k := 0.0  # how hard the last bump was (0.5 the edge, 1 a wheel in a hole)
var prev_y := 0.0
var chunks: Array = []  # {node, end_len}: each piece of road drawn once

# On the paper
var live_skid := [null, null, null, null]  # the skid each tyre is drawing (rears, then fronts): {pts, a, col, w}
var skid_on := [false, false]  # rears, fronts: marking now
var skid_tip := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]  # where each tyre is now: the live line always reaches it
var skid_quiet := 0.0  # how long the car has been gripping with no side held; the marks stop after SKID_GRACE
const SKID_GRACE := 0.6
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
var fx: TyreFx  # smoke and rubber while sliding, graphite and eraser crumbs while tearing (tyre_fx.gd)
var pop_t := -9.0  # when the last piece was collected (the HUD handful pops)
var chads_up: Array = []  # collected confetti tumbling away: {p, v, a, t, dir}
var chads_fly: Array = []  # confetti won by a clip, flying from it to the counter (screen): {from, t, v, a, n, side}
const CHAD_FLY := 0.75  # how long each piece takes to reach the counter
const CLIP_CONFETTI := [0, 15, 30]  # per grade: CLIP, PERFECT
const CHAD_SIZE := 28.0  # on the road (world px)
var words: Array = []
var things_dirty := true

# The run
var score := 0.0
var mult := 1
## Points (2026-11-26, after Absolute Drift, Forza and real drift judging): only drifting scores.
## A chain runs while the car drifts past CHAIN_DEG: points per second from the slide's angle (40% just
## above it, full from 65, nothing past 90), more along the edge of the line, plus clips and near misses.
## The chain gathers them before the combo (as Forza does); the combo multiplies the whole chain when it
## is stamped. A switch of sides raises the combo (up to x9) once the meter
## (side_pts) has SWITCH_PTS in it. A short grace (longer while swapping) carries the chain over a dip;
## when it runs out, or on the line, a bump or a crash, the whole chain is banked: stamped in red ink and
## counted into the total.
var flights: Array = []  # clip points flying up to the chain: {pts, from (screen), t, col}
const FLIGHT := 0.55  # how long they take to reach it
var live_t := -9.0  # when clip points last landed in the chain (its pulse)
var mult_t := -9.0  # when the combo last went up (its pulse)
var total_t := -9.0  # when a stamp last landed in the total (its pulse)
var swap_wait := false  # this low-angle moment already got the longer swap wait
var side_pts := 0.0  # the combo meter: points (as shown, before the combo) since it last cashed in; a swap before it is full carries it over
var chain_mile := 0  # how many 500s the chain has passed (one ping each)
var chain_on := false
var chain_pts := 0.0
var chain_side := 0.0
var chain_grace := 0.0  # seconds left before an idle chain is banked
const CHAIN_GRACE := 0.6  # just long enough to swing through a side switch
const SWITCH_PTS := 80.0  # a side switch only raises the combo once the meter has this many points (as shown, before the combo)
const SWAP_GRACE := 1.4  # ... but swinging over to the other side (holding it) may take this long in all
const CHAIN_DEG := 25.0  # below this angle the chain is not being kept up
var stamps: Array = []  # {pts, t, rot}: banked, flying up, not yet counted into the total
var merged_t := -9.0  # when the last stamp was counted in (the old total is crossed out)
var merged_from := 0
const STAMP_HOLD := 0.8  # a stamp sits this long, then slides into the total
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
## Tyre sound: the one squeal loop follows the slide. Two extra layers (a light-slide scrub and a start chirp)
## are kept behind USE_SCRUB / USE_CHIRP but switched off: they didn't sound right.
var scrub: AudioStreamPlayer
var scrub_vol := 0.0
var chirp: AudioStreamPlayer
var chirp_left := 0.0
var chirp_t := -10.0
var chirp_slip := 0.0  # last frame's slip, to catch the moment it lets go
var wob := 0.0
const CHIRP_LEN := 0.22
const USE_CHIRP := false  # the start chirp sounded like a screech: off
const USE_SCRUB := false  # the extra light-slide layer: off, back to the one original squeal
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
	flow = String(cfg.get_value("dev", "handling", "flow")) != "classic"
	road_k = FLOW_ROAD if flow else 1.0
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
	if start_home:  # the start page's layout first: the road keeps clear of its gear and settings
		start_page = StartPage.new()
		start_page.layout(self)
		no_road = start_page.keep_clear()
	road.append(Vector2.ZERO)
	widths.append(150.0 * road_k)
	lens.append(0.0)
	_extend(-PI * 0.5, 160.0, 0.0)  # a straight start
	_chunk(0)
	_grow_road()
	pos = road[2]
	prev_y = pos.y
	cam_goal_pos = pos
	if not start_home:  # a quick restart: no empty paper below the start line, it begins at the screen's bottom
		cam_goal_pos.y = minf(cam_goal_pos.y, _restart_floor())
		cam.position = cam_goal_pos
	if start_home:
		state = "home"
		pause_btn.visible = false
		add_child(start_page)
		start_page.setup(self)  # puts the car into its tricks at the meet
		prev_y = pos.y
		cam.zoom = Vector2.ONE * start_page.start_zoom  # the settings view after a rebuild, else the page
		cam_goal_zoom = cam.zoom.x
		cam.position = start_page.start_cam
		cam_goal_pos = cam.position


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
	inks = Inks.new()
	add_child(inks)
	inks.setup(self, page_over)
	marks_layer = Node2D.new()
	world.add_child(marks_layer)
	live = DrawNode.new()
	live.draw_fn = _draw_live
	world.add_child(live)
	fx = TyreFx.new()
	world.add_child(fx)
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
	world.add_child(fx.over)
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
	pause_btn = PauseSign.new()
	pause_btn.position = Vector2(view.x - 24 - 84, _top() + 8)
	pause_btn.pressed.connect(_pause)
	root.add_child(pause_btn)


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
	return clampf(150.0 - lens[lens.size() - 1] / 400.0, 100.0, 150.0) * road_k  # it narrows slowly, never speeds up


## How far into the run (0..1): corners tighten, links shorten and peaks come more often with it.
func _difficulty() -> float:
	return clampf(lens[lens.size() - 1] / 16000.0, 0.0, 1.0)


## One corner: ease in, hold the radius, ease out, turning `angle` in all towards `side` (-1 left, 1 right).
## Entry eases are longer than exits, so a corner announces itself. `r2` > 0 makes it tighten half way
## (a decreasing-radius corner). The apex is recorded for scoring later.
func _corner(side: float, r: float, angle: float, kind: String, r2 := 0.0) -> Array:
	r = maxf(r, R_MIN) * road_k
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
		var k2 := side / (maxf(r2, R_MIN) * road_k)
		segs += [[arc * 0.45, k, k], [r * 0.3, k, k2], [arc * 0.4, k2, k2], [eout, k2, 0.0]]
	else:
		segs += [[arc, k, k], [eout, k, 0.0]]
	pending_corners.append({"side": side, "r": r, "kind": kind, "at": ein + arc * 0.5})
	return segs


## Run-up before a drift corner: long enough to see it coming and set up (about a second, more for hairpins).
func _runup(secs: float) -> Array:
	return [[maxf(60.0, secs * 0.4 * 240.0 * lerpf(1.0, 0.85, _difficulty())) * road_k, 0.0, 0.0]]


## The building blocks. Each returns its segments; sizes come from the car's drift circle (see report).
func _block(kind: String, side: float) -> Array:
	var d := _difficulty()
	var drift_r := func(): return lerpf(rng.randf_range(180.0, 260.0), rng.randf_range(150.0, 200.0), d)
	var link := lerpf(rng.randf_range(60.0, 90.0), rng.randf_range(35.0, 60.0), d) * road_k
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
		var c0 := corners.size()
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
			# turn back up the page; if that would run through the gear or the settings, turn hard away instead
			var keep := road.size()
			var dir0 := road_dir
			var away := _away_from_no_road()
			var turns := [wrapf(-PI * 0.5 - road_dir, -PI, PI) * 0.6, away * 1.4, away * 2.4, -away * 1.4, -away * 2.4]
			for k in turns.size():
				_lay([[120.0, 0.0, float(turns[k]) / 120.0]])
				if k == turns.size() - 1 or not (_crosses_no_road(keep) or _heads_into_no_road()):
					break
				road.resize(keep)
				widths.resize(keep)
				lens.resize(keep)
				road_dir = dir0
		phrase_left -= 1
		_chunk(start)
		_page_things(start)
		scrib.on_block(start)
		inks.on_block(start, corners.slice(c0))
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
	if kind == "hairpin" and flow:
		return base * 0.4 * lerpf(0.6, 1.3, d)  # flow wants big sweepers; hairpins stay a rare treat
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
## Whether the road from index `from` on runs through any no-go area (grown by half the road's width).
func _crosses_no_road(from: int) -> bool:
	for i in range(from, road.size(), 2):
		for r in no_road:
			if (r as Rect2).grow(widths[i] * 0.5 + 20.0).has_point(road[i]):
				return true
	return false


## Whether the road's end is aimed at a no-go area not far ahead (so the next piece couldn't miss it).
func _heads_into_no_road() -> bool:
	var end := road[road.size() - 1]
	var d := Vector2.from_angle(road_dir)
	for r in no_road:
		var to: Vector2 = (r as Rect2).get_center() - end
		if to.length() < 520.0 + (r as Rect2).size.length() * 0.5 and d.dot(to.normalized()) > 0.45:
			return true
	return false


## Which way to turn (+1 or -1, as the road's curvature) to steer away from the nearest no-go area.
func _away_from_no_road() -> float:
	var end := road[road.size() - 1]
	var d := Vector2.from_angle(road_dir)
	var best := INF
	var side := 1.0
	for r in no_road:
		var to: Vector2 = (r as Rect2).get_center() - end
		if to.length() < best:
			best = to.length()
			side = -signf(d.cross(to)) if d.cross(to) != 0.0 else 1.0
	return side


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
	if ok and (_crosses_no_road(keep) or _heads_into_no_road()):  # never through the gear or the settings
		ok = false  # writing (close by is fine); and not aimed straight at them, so it turns away in time
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
		if c["r"] >= 450.0 * road_k:
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
	var red_ink: Array = inks.edge_ink(ls[0])
	if not red_ink.is_empty():  # a red-ink chapter: the edges are walls
		ink = red_ink
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
		inks.new_page(lens[lens.size() - 1])  # from the next stretch: it is drawn in the new pen from its first point, so ink and rule match
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


## The game's own writing (points, pause and crash notes, tutorial notes): Itim, upright and quick to read.
static func ui_font() -> Font:
	if not page_tex.has("ui_font"):
		page_tex["ui_font"] = load("res://fonts/hand/Itim.ttf")
	return page_tex["ui_font"]


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
			# hole-punch confetti, scattered a little: never quite in a neat row
			var jit := Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			coins.append({"p": road[i] + Vector2.from_angle(_dir_at(i) + PI * 0.5) * off * widths[i] + jit, "got": false, "v": rng.randi() % 6, "a": rng.randf() * TAU, "f": 0})


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
		_bank_chain()  # a broken chain still counts
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


## What the camera shows now, in world space.
func _view_rect() -> Rect2:
	var size := view / cam.zoom
	return Rect2(cam.get_screen_center_position() - size * 0.5, size)


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
		inks.prune(behind)
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
		var seen := _view_rect().grow(400.0)
		for m in still_marks:
			if seen.intersects(m["box"]):
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
		"home":
			start_page.update(delta)
			home_hold = home_hold + delta if _input_side() != 0 and start_page.mode == "home" and overlay == null else 0.0
			if home_hold >= HOLD_TO_START:  # held a side: the car breaks off its tricks for the start line
				state = "intro"
				start_page.begin_exit(road[2])
		"intro":
			_intro(delta)
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
	_effects(delta)
	if start_page != null and start_page.mode == "gone":
		start_page.after(delta)  # the drone heads back to the pit
	fx.step(delta)
	inks.update()
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
	if hold_lock:  # the hold that started the run is not steering: ignored until it is let go
		if t != 0:
			return 0
		hold_lock = false
	return clampi(t, -1, 1)


func _unhandled_input(event: InputEvent) -> void:
	var page := state == "home" and start_page != null
	if event is InputEventScreenTouch:
		if event.pressed:
			if page and start_page.tap(get_viewport().get_canvas_transform().affine_inverse() * event.position):
				return  # the gear or a setting: not a hold to start
			touches[event.index] = event.position.x
		else:
			touches.erase(event.index)
			if page:
				start_page.release()
	elif event is InputEventScreenDrag:
		if page:
			start_page.drag(get_viewport().get_canvas_transform().affine_inverse() * event.position)
		if touches.has(event.index):
			touches[event.index] = event.position.x


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		if state == "play" and overlay == null:
			_pause(true)
		elif state == "play" and overlay is PauseNote and overlay.phase in ["slowing", "resuming"]:
			overlay._freeze()  # leaving mid-way: frozen there and then, not left running
		if scrib:
			scrib.save_seen()  # the app may be closed from here
			inks.save()


## How a real drift goes, eased so no step is sudden. A held side first loads the car into a light slide
## (the rear steps out a little and the nose eases round). Keep holding past `hold_delay` and the rear lets
## go fully: the slide deepens into a drift, the nose swings hard while the car keeps travelling on its old
## line. Let go and it unwinds the same way: the rear tyres slowly find grip again, they swing the nose back
## towards the way the car is going (the "catch"), and the travel bends round until both line up.
## Nothing jumps: the turn rate has weight (YAW_LAG), and the input and the drift both ease in and out.
func _drive(delta: float) -> void:
	if flow:
		_steer_flow(delta)
	else:
		_steer_classic(delta)
	_move(delta)


## Flow handling (after Absolute Drift): the slide angle is a damped spring towards a wanted angle, so it
## settles steady in a held drift and swings through on a release or a side switch. The slide itself turns
## the car's travel (more sideways = tighter line); throttle is always on, so speed mostly holds.
func _steer_flow(delta: float) -> void:
	var side := _input_side()
	hold_t = hold_t + delta if side != 0 else 0.0
	steer += (side - steer) * (1.0 - exp(-delta * (8.0 if side != 0 else 4.0)))
	same_t = same_t + delta if side != 0 and side == held_side else 0.0
	held_side = side
	var s := wrapf(heading - vdir, -PI, PI)
	var ang := lerpf(FLOW_ANGLE[0], FLOW_ANGLE[1], smoothstep(0.0, 1.2, hold_t))
	ang += FLOW_DEEP[0] * smoothstep(FLOW_DEEP[1], FLOW_DEEP[2], same_t)  # deeper slide = tighter line, more scrub
	var want := steer * deg_to_rad(ang) * smoothstep(0.0, 90.0, speed)  # no swinging the nose round while standing still
	slip_v += ((want - s) * FLOW_SPRING - slip_v * FLOW_DAMP) * delta
	s = clampf(s + slip_v * delta, -1.35, 1.35)
	if absf(s) >= 1.35:
		slip_v = 0.0
	vdir += FLOW_TURN * sin(s) * inks.grip_mul(pos) * minf(1.0, speed / 150.0) * delta  # no pivoting on the spot
	var old := heading
	heading = vdir + s
	yaw = wrapf(heading - old, -PI, PI) / maxf(delta, 0.0001)
	slip = absf(s)
	drift_amt = clampf(slip / 0.7, 0.0, 1.0)
	if slip > 0.15 and speed > DRIFT_FLOOR:  # the tyres scrub like the classic drift: deeper slide, more speed lost, so the line tightens
		speed = maxf(DRIFT_FLOOR, speed - SCRUB * sin(minf(slip, 1.4)) * delta)


func _steer_classic(delta: float) -> void:
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
	grip *= inks.grip_mul(pos)  # crayon wax, wet ink
	s = wrapf(heading - vdir, -PI, PI)
	vdir += s * (1.0 - exp(-delta * grip))  # the travel bends towards the nose, harder the more grip
	s = wrapf(heading - vdir, -PI, PI)
	if absf(s) > 1.35:  # never more than sideways
		vdir = heading - signf(s) * 1.35
	slip = absf(wrapf(heading - vdir, -PI, PI))
	if slip > 0.15 and speed > DRIFT_FLOOR:  # the tyres scrub: a long drift drops a gear, the exit pulls back up
		speed = maxf(DRIFT_FLOOR, speed - SCRUB * sin(minf(slip, 1.4)) * delta)


## The lowest the camera's centre may sit on a quick restart: with the start line just above the screen's
## bottom edge.
func _restart_floor() -> float:
	return 70.0 - view.y / maxf(cam.zoom.y, 0.01) * 0.5


## How far a point is from the road's centre line (nearest centre point around index i).
func _off_line(p: Vector2, i: int) -> float:
	var best := INF
	for j in range(maxi(0, i - 4), mini(road.size(), i + 5)):
		best = minf(best, p.distance_squared_to(road[j]))
	return sqrt(best)


## A dev setting changed on the start page: applied straight away (handling waits for the page to be redrawn).
func apply_dev(key: String, value: Variant) -> void:
	match key:
		"paper":
			paper.texture = load(PAPERS.get(String(value), PAPERS["white"])["tex"])
		"car":
			var car: Dictionary = CARS.get(String(value), CARS["evo"])
			car_tex = load(car["sheet"])
			car_px = int(car["px"])
			if not car_len_px.has(car["sheet"]):
				car_len_px[car["sheet"]] = _painted_width(car_tex.get_image(), car_px)
			car_scale = CAR_LEN / maxf(8.0, float(car_len_px[car["sheet"]]))
		"crash":
			crash_on_hit = bool(value)
		"hold":
			hold_delay = float(value)
		"music":
			_radio()


## What both handling models share: staying on the line, speed, moving, page edges and the ways out.
func _move(delta: float) -> void:
	var i := progress_i
	var half := widths[i] * 0.5
	var off := pos.distance_to(road[i])  # the car itself: red lines and losing the road go by this
	# The meet below the start line is open ground: coming out of it under your own control is no penalty.
	var in_lot := start_page != null and progress_i < 8 and pos.y > -6.0 and absf(pos.x) < 420.0
	# Only the rear tyres count for slowing: the paper drags once both of them are past the edge.
	var wh := _wheels()
	var was := on_road
	on_road = in_lot or _off_line(wh[0], i) < half or _off_line(wh[1], i) < half
	if was and not on_road:
		_word("LINE", pos, Color(0.35, 0.35, 0.4))
		_bank_chain()  # a broken chain still counts
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
	pos += Vector2.from_angle(vdir) * speed * delta
	_seam_bump()
	if in_lot:
		return
	if off > half + 34.0 and inks.red_here(lens[i]):  # fully over a red line
		inks.mark_out(pos)
		_crash("Over the red line")
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
	var front := pos + f * CAR_LEN * 0.3
	return [back + r * 13.0, back - r * 13.0, front + r * 13.0, front - r * 13.0]


## Graphite skids whenever it slides; past a hard slide the tyres start ripping the paper itself.
func _marks() -> void:
	var wheels := _wheels()
	# The rears mark as soon as the car slides; the fronts only in a real drift (the whole car going
	# sideways drags them too), and lighter. Each has a higher slip to start than to stop, so no gaps.
	# Once on, a mark only stops when the car has been gripping with no side held for a while, so a quick
	# lift between corners never breaks the line.
	var quiet := _input_side() == 0 and slip < 0.12 or speed < 40.0
	skid_quiet = skid_quiet + get_process_delta_time() if quiet else 0.0
	var stop := skid_quiet > SKID_GRACE
	skid_on[0] = not stop if skid_on[0] else slip > 0.18 and speed > 40.0
	skid_on[1] = not stop if skid_on[1] else slip > 0.30 and speed > 40.0
	var ripping := slip > 0.75 and speed > 110.0  # anywhere on the sheet: off the track is the same paper
	for k in 4:
		var w: Vector2 = wheels[k]
		skid_tip[k] = w
		var front := k >= 2
		if skid_on[1 if front else 0]:
			if live_skid[k] == null:
				live_skid[k] = {"pts": PackedVector2Array([w]), "a": 0.6 if front else 1.0, "col": inks.skid_col(), "w": 4.5 if front else 6.0}
			var sk: Dictionary = live_skid[k]
			var pts: PackedVector2Array = sk["pts"]
			if pts[pts.size() - 1].distance_to(w) > 5.0:
				pts.append(w)
				sk["pts"] = pts
				if pts.size() >= MARK_POINTS:
					_still_skid(k)
					live_skid[k] = {"pts": PackedVector2Array([w]), "a": sk["a"], "col": inks.skid_col(), "w": sk["w"]}
		elif live_skid[k] != null:
			_still_skid(k)
		if front:
			continue  # only the driven rears tear the paper
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
					_play("rip", -9.0, rng.randf_range(0.82, 0.9))  # low and steady: a higher pitch screeched
				if rng.randf() < 0.6:  # torn bits of paper kick up
					flakes.append({"p": w, "v": Vector2.from_angle(vdir + PI + rng.randf_range(-1.0, 1.0)) * rng.randf_range(40, 120), "t": clock, "a": rng.randf() * TAU, "s": rng.randf_range(2.5, 5.0)})
				if tp.size() >= MARK_POINTS:  # carry on seamlessly in a fresh piece
					_still_tear(k, false)
					live_tear[k] = {"pts": PackedVector2Array([tp[tp.size() - 2], w]), "w": PackedFloat32Array([ww[ww.size() - 2], ww[ww.size() - 1]]), "seed": t["seed"] + 7.0, "joined": true}
		elif live_tear[k] != null:
			_still_tear(k, true)
	fx.emit(get_process_delta_time(), [wheels[0], wheels[1]], vdir, speed, slip, SPEED, skid_on[0], ripping)


func _still_skid(k: int) -> void:
	var sk: Dictionary = live_skid[k]
	live_skid[k] = null
	if (sk["pts"] as PackedVector2Array).size() < 2:
		return
	_still(func(c: Node2D): _draw_skid(c, sk), sk["pts"])


func _still_tear(k: int, ends: bool) -> void:
	var t: Dictionary = live_tear[k]
	live_tear[k] = null
	if (t["pts"] as PackedVector2Array).size() < 2:
		return
	t["end"] = ends
	_still(func(c: Node2D): _draw_tear(c, t), t["pts"])


## Finished marks are drawn in groups of up to 24 per node (one node each cost the phone hundreds of draw
## calls on a drifty run). A group is redrawn when a mark joins it, then stays still.
func _still(fn: Callable, pts: PackedVector2Array) -> void:
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	box = box.grow(16.0)
	if mark_bucket == null or bucket_fns.size() >= 24:
		var fns: Array = []
		bucket_fns = fns
		mark_bucket = DrawNode.new()
		mark_bucket.draw_fn = func(c: Node2D):
			for f in fns:
				(f as Callable).call(c)
		marks_layer.add_child(mark_bucket)
		still_marks.append({"node": mark_bucket, "box": box})
	bucket_fns.append(fn)
	var last: Dictionary = still_marks[still_marks.size() - 1]
	last["box"] = (last["box"] as Rect2).merge(box)  # a group is dropped only once all of it is off screen
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
	squeal.play(rng.randf() * loop.get_length())
	scrub = AudioStreamPlayer.new()  # silent unless USE_SCRUB (its sound file was removed)
	scrub.volume_db = -80.0
	add_child(scrub)
	chirp = AudioStreamPlayer.new()
	chirp.stream = loop
	chirp.volume_db = -80.0
	add_child(chirp)
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


func _play(kind: String, db: float, pitch := 1.0, vary := true) -> void:
	if not Game.sound_on:
		return
	var p := shots[shot_i]
	shot_i = (shot_i + 1) % shots.size()
	var takes: Array = snd[kind]
	p.stream = takes[rng.randi() % takes.size()]
	p.volume_db = db
	p.pitch_scale = pitch * (rng.randf_range(0.94, 1.06) if vary else 1.0)  # never quite the same twice
	p.play()


## Tyres: silent while gripping, rising in and out with the slide (and softer as the car slows). Higher
## pitched the harder it slides.
func _squeal(delta: float) -> void:
	var on := (_driving() or state == "home") and Game.sound_on
	var spd := clampf(speed / SPEED, 0.3, 1.0)
	wob += delta
	var w := sin(wob * 1.7) * 0.025 + sin(wob * 4.3 + 1.0) * 0.015
	# The scrub: tyres just starting to slide, a rubbery skid; it steps back as the squeal takes over.
	var sw := smoothstep(0.06, 0.3, slip) * (1.0 - 0.6 * smoothstep(0.4, 0.9, slip)) * spd if on and USE_SCRUB else 0.0
	scrub_vol = move_toward(scrub_vol, sw, delta * 4.0)
	scrub.volume_db = linear_to_db(maxf(scrub_vol, 0.0001)) - 10.0
	scrub.pitch_scale = 0.9 + 0.15 * clampf(speed / SPEED, 0.0, 1.0) + w
	# The squeal: a real drift. It comes in at the pace of the slide and tails off slower as grip returns.
	var want := smoothstep(0.15, 0.9, slip) * spd if on else 0.0  # the original squeal, at the quieter level
	if state == "home":
		want *= 0.5  # the tricks at the meet, a little further off
	squeal_vol = move_toward(squeal_vol, want, delta * 3.0)
	squeal.volume_db = linear_to_db(maxf(squeal_vol, 0.0001)) - 11.0
	squeal.pitch_scale = 0.85 + 0.3 * clampf(slip / 1.2, 0.0, 1.0)
	# The chirp: the moment the tyres let go, a short bark from a random bit of the recording.
	if USE_CHIRP and on and chirp_slip < 0.28 and slip >= 0.28 and speed > 100.0 and clock - chirp_t > 0.8:
		chirp_t = clock
		chirp_left = CHIRP_LEN
		chirp.pitch_scale = rng.randf_range(1.15, 1.3)
		chirp.play(rng.randf() * (chirp.stream as AudioStreamOggVorbis).get_length() * 0.8)
	chirp_slip = slip
	if chirp_left > 0.0:
		chirp_left -= delta
		chirp.volume_db = linear_to_db(maxf(chirp_left / CHIRP_LEN, 0.0001)) - 13.0
		if chirp_left <= 0.0:
			chirp.stop()


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
		if engine_bov and _driving():
			_play("bov", -8.0)  # the turbo dumps its boost as the throttle lifts for the change
	elif gear > 1 and speed < lo - 12.0:
		gear -= 1
		shift_t = clock
	lo = 0.0 if gear == 1 else float(GEAR_TOP[gear - 2])
	hi = float(GEAR_TOP[gear - 1])
	var t := clampf((speed - lo) / (hi - lo), 0.0, 1.0)
	var want := lerpf(IDLE_RPM * 1.6 if gear == 1 else PULL_RPM, SHIFT_RPM, t)
	if _driving() or state == "home":  # the tricks on the start page rev it too
		want += drift_amt * clampf(slip / 0.8, 0.0, 1.0) * 1800.0  # wheelspin in the slide
	else:
		want = IDLE_RPM * 1.2  # crashed: off the throttle, settling to idle
	want = minf(want, 7800.0)
	rpm += (want - rpm) * (1.0 - exp(-delta * 9.0))
	var lift := smoothstep(0.0, 0.18, clock - shift_t)  # throttle lifts for the change, then back on
	var load_k := 1.0 if _driving() else (0.6 if state == "home" else 0.5)
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
	var side := signf(wrapf(heading - vdir, -PI, PI))
	if rad_to_deg(slip) > CHAIN_DEG and on_road:
		if not chain_on:  # a new chain
			for st in stamps:  # a stamp still sitting where the chain is shown flies off now, out of its way
				st["t"] = minf(float(st["t"]), clock - STAMP_HOLD)
			chain_on = true
			chain_pts = 0.0
			chain_mile = 0
			side_pts = 0.0
			mult = 1
			chain_side = side
		elif side != chain_side:  # linked from one side to the other: the combo goes up if that drift was a real one
			chain_side = side
			var earned := side_pts >= SWITCH_PTS
			if earned:  # cashed in: the meter starts again; not full yet, it carries over to the new side
				side_pts = 0.0
			if earned and mult < 9:
				mult += 1
				mult_t = clock
				best_combo = maxi(best_combo, mult)
				_word("x%d" % mult, pos + Vector2(0, -40), Color(0.85, 0.35, 0.15))
				_play("combo", -4.0, pow(2.0, (mult - 2) / 6.0), false)  # a whole tone higher with each combo step
		chain_grace = CHAIN_GRACE
		swap_wait = false
		var deg := rad_to_deg(slip)
		var steep := smoothstep(CHAIN_DEG, 65.0, deg)  # flow drifts settle at 32-50 and deepen to ~68 when held
		var angle := lerpf(0.4, 1.0, steep) * (1.0 - smoothstep(85.0, 100.0, deg))  # a shallow slide still pays 40%, most from 65; past 90 is a spin
		var pace := clampf(speed / DRIFT_FLOOR, 0.2, 1.0)  # full pay at drift speed (a drift scrubs the car down to DRIFT_FLOOR); less only when crawling
		var edge := absf(widths[progress_i] * 0.5 - pos.distance_to(road[progress_i]))
		var close := 1.6 if edge < 26.0 else 1.0  # drifting along the edge of the line pays more
		var got := 120.0 * angle * pace * close * inks.score_mul(lens[progress_i], pos) * delta  # before the combo
		side_pts += got
		chain_pts += got
		if int(chain_pts / 500.0) > chain_mile:  # every 500 points in the chain
			chain_mile = int(chain_pts / 500.0)
			_play("coin", -3.0, 1.45)
	elif chain_on:
		# Holding the other side (straight away, or pressed again before the short wait ran out after letting
		# go): it's a swap, so the chain waits for the car to swing through. Just straightening up does not.
		var inp := signi(_input_side())
		if not swap_wait and inp != 0 and float(inp) != chain_side:
			swap_wait = true
			chain_grace += SWAP_GRACE - CHAIN_GRACE
		chain_grace -= delta
		if chain_grace <= 0.0:
			_bank_chain()
	_clips()
	for c in coins:
		if not c["got"] and pos.distance_to(c["p"]) < CAR_R + 12.0:
			c["got"] = true
			things_dirty = true
			coins_got += 1  # confetti is collected for later (the garage), not score
			pop_t = clock
			chads_up.append({"p": c["p"], "v": c["v"], "a": c["a"], "t": clock, "dir": Vector2.from_angle(vdir).rotated(rng.randf_range(-0.6, 0.6))})
			_play("coin", -6.0)
		elif not c["got"] and int(c["f"]) == 0 and pos.distance_to(c["p"]) < CAR_R + 70.0:
			c["f"] = 1  # the car's wind nudges it once: it turns a little on the page and settles flat
			c["a"] = float(c["a"]) + rng.randf_range(-0.5, 0.5)
			things_dirty = true


## Cones and boxes (inks.gd): the nose near the cone, the tail in the box, while drifting. CLIP 150, PERFECT
## 300 into the chain (the combo multiplies it at the stamp); the points fly from the clip up to the chain
## (they count straight away). Any corner or side of the car touching a cone tips it over.
func _clips() -> void:
	var f := Vector2.from_angle(heading)
	var r := f.orthogonal()
	var front := pos + f * CAR_LEN * 0.5
	var back := pos - f * CAR_LEN * 0.5
	var nose := [front, front + r * 13.0, front - r * 13.0]
	var tails := [back + r * 13.0, back - r * 13.0]
	var body := nose + tails + [pos + r * 13.0, pos - r * 13.0]  # anything of the car touching a cone tips it
	var drifting := rad_to_deg(slip) > CHAIN_DEG and on_road
	for ev in inks.clip_check(nose, tails, body, lens[progress_i], drifting):
		var perfect := int(ev["grade"]) == 2
		var pts := 300 if perfect else 150  # before the combo, like everything in the chain
		var col := Color(0.75, 0.16, 0.15) if perfect else Color(0.15, 0.25, 0.65)
		_word("PERFECT" if perfect else "CLIP", Vector2(ev["p"]) + Vector2(0, -36), col)
		_play("clip", -3.0, 1.3 if perfect else 1.0, false)
		# confetti: counted now, shown as pieces flying up to the counter (each carries part of it)
		var won: int = CLIP_CONFETTI[int(ev["grade"])]
		var sp0 := (Vector2(ev["p"]) - cam.get_screen_center_position()) * cam.zoom + view * 0.5
		coins_got += won
		var pieces := 5 if perfect else 3
		for k in pieces:
			var share := won / pieces + (1 if k < won % pieces else 0)
			chads_fly.append({"from": sp0 + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)), "t": clock + k * 0.07,
				"v": rng.randi() % 6, "a": rng.randf() * TAU, "n": share, "side": rng.randf_range(-1.0, 1.0)})
		if chain_on:
			chain_pts += pts
			side_pts += pts
			var sp := (Vector2(ev["p"]) - cam.get_screen_center_position()) * cam.zoom + view * 0.5
			flights.append({"pts": pts, "from": sp, "t": clock, "col": col})
		else:
			_stamp_points(pts, mult, "PERFECT" if perfect else "CLIP")


## Near misses: brushing past a desk object without touching it. (Touching is caught by the physics.)
func _hits() -> void:
	for o in props:
		if o.near or (o as Node2D).position.distance_squared_to(pos) > 250.0 * 250.0:
			continue
		var d: float = o.gap_to(pos)
		if d < CAR_R + 16.0 and d > CAR_R + 2.0:
			o.near = true
			if chain_on:
				side_pts += 150.0
				chain_pts += 150.0  # brushing past in a drift: into the chain
			else:
				_stamp_points(150, 1, "NEAR MISS")
			_word("NEAR MISS", pos + Vector2(0, -50), Color(0.2, 0.4, 0.75))


## The chain is over: it's banked, stamped in red ink and counted into the total.
func _bank_chain() -> void:
	flights.clear()
	if chain_on and chain_pts >= 5.0:
		_stamp_points(int(chain_pts * mult), mult)  # the combo multiplies the whole chain here
	chain_on = false
	chain_pts = 0.0
	mult = 1


func _stamp_points(pts: int, combo := 1, label := "") -> void:
	score += pts
	if label == "":
		label = "BIG DRIFT" if pts > 1500 else "DRIFT"
	stamps.append({"pts": pts, "t": clock, "rot": rng.randf_range(-0.22, 0.22), "seed": rng.randi() % 100000, "combo": combo, "label": label})
	_play("stamp", -2.0 if pts > 1500 else -4.0, 0.9 if pts > 1500 else 1.0)  # the stamp thumping down (a big one deeper)
	Game.vibrate(12)


func _crash(why: String) -> void:
	if state != "play":
		return
	_bank_chain()  # a broken chain still counts
	for st in stamps:  # the slow-motion freezes before a stamp could fly: count it into the total now
		st["t"] = clock - STAMP_HOLD - 0.45
	state = "crashed"
	crash_t = clock
	spin = 9.0 * (1.0 if rng.randf() < 0.5 else -1.0)
	_play("crash", 0.0)
	Game.vibrate(70)
	prev_best = int(_load().get_value("best", "score", 0))
	scrib.save_seen()
	_save()
	# the spin-out in slow motion as the colour drains, then the run written up on the paper (pause_note.gd)
	if overlay != null and overlay is PauseNote:  # crashed while a pause was still easing back: it gives way
		overlay.queue_free()
		overlay = null
	if overlay == null:
		var note := PauseNote.new()
		overlay = note
		ui.add_child(note)
		note.setup(self, false, "crash", {"why": why, "score": int(score), "best": prev_best, "new_best": int(score) > prev_best,
			"dist": int(dist), "combo": best_combo, "confetti": coins_got})
		pause_btn.visible = false


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
## Driving: the run itself, or the drive out of the bay before it.
func _driving() -> bool:
	return state == "play" or state == "intro"


## The car breaks off its tricks and sweeps to the start line (start_page.gd drives it), then the run is
## the player's: it carries on exactly as it is moving, the slide's swing included.
func _intro(delta: float) -> void:
	var done := start_page.drive_exit(delta)
	_marks()
	if done or start_page.can_take_over(road[2]):  # as soon as it has turned out of the donuts, it's yours
		state = "play"
		slip_v = start_page.driver.slip_v
		hold_lock = true  # still holding from the start: no drift (and no scrub) until that hold is let go
		prev_y = pos.y
		pause_btn.visible = true
		start_page.leave()


func _follow(delta: float) -> void:
	cam_rot = 0.0
	Prop.view_rot = 0.0
	if state == "home":
		# the start page (or its settings), eased; from the drive out on, the follow below eases on from it
		cam_goal_pos = start_page.cam_pos
		cam.position = cam.position.lerp(cam_goal_pos, 1.0 - exp(-delta * 3.5))
		cam_goal_zoom = cam.zoom.x + (start_page.cam_zoom - cam.zoom.x) * (1.0 - exp(-delta * 3.5))
		cam.zoom = Vector2.ONE * cam_goal_zoom
		return
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
	if start_page == null and progress_i < 200:  # a quick restart: never shows the empty paper below the line
		cam_goal_pos.y = minf(cam_goal_pos.y, _restart_floor())
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
	var col: Color = sk.get("col", Color(0.2, 0.2, 0.22, 0.45))
	n.draw_polyline(sk["pts"], Color(col, col.a * float(sk["a"])), float(sk.get("w", 5.0)), false)  # no antialiasing: soft enough, and it batches


func _draw_live(n: Node2D) -> void:
	for k in 4:
		if live_skid[k] != null:  # drawn on to the tyre itself, so the end doesn't jump as points are added
			var tip: Dictionary = (live_skid[k] as Dictionary).duplicate()
			var pts: PackedVector2Array = (tip["pts"] as PackedVector2Array).duplicate()
			if pts[pts.size() - 1].distance_to(skid_tip[k]) > 0.5:
				pts.append(skid_tip[k])
			tip["pts"] = pts
			if pts.size() >= 2:
				_draw_skid(n, tip)
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
			_draw_chad(n, c["p"], int(c["v"]), 0, float(c["a"]), 1.0, 1.0, 1.0)


## One piece of punched confetti: a soft contact shadow (further away when it's in the air), then the
## paper at the given tumble frame.
func _draw_chad(n: Node2D, p: Vector2, v: int, frame: int, ang: float, scale: float, alpha: float, lift: float) -> void:
	var tex: Texture2D = _tex("chads")
	var src := Rect2(frame * 48, v * 48, 48, 48)
	var sz := Vector2.ONE * CHAD_SIZE / 44.0 * 48.0 * scale
	# Curled up off the page: a tight dark shadow right under it and a wider soft one beside it.
	var sh := Vector2(-2.5, 3.5) * lift
	n.draw_set_transform(p + sh * 1.8, ang, Vector2(1.0, 0.85))
	n.draw_circle(Vector2.ZERO, CHAD_SIZE * 0.56 * scale, Color(0, 0, 0, 0.07 * alpha / lift), true, -1.0, false)  # no antialiasing: it batches
	n.draw_set_transform(p + sh, ang, Vector2(1.0, 0.85))
	n.draw_circle(Vector2.ZERO, CHAD_SIZE * 0.46 * scale, Color(0, 0, 0, 0.17 * alpha / lift), true, -1.0, false)
	n.draw_set_transform(p, ang, Vector2.ONE)
	n.draw_texture_rect_region(tex, Rect2(-sz * 0.5, sz), src, Color(1, 1, 1, alpha))
	n.draw_set_transform(Vector2.ZERO)


func _draw_top(n: Node2D) -> void:
	# Collected confetti: kicked up, tumbling through its 3D frames, then gone.
	var keep: Array = []
	for ch in chads_up:
		var t := (clock - float(ch["t"])) / 0.6
		if t >= 1.0:
			continue
		keep.append(ch)
		var up := sin(t * PI) * 34.0
		var p: Vector2 = Vector2(ch["p"]) + Vector2(ch["dir"]) * t * 55.0 + Vector2(0, -up)
		_draw_chad(n, p, int(ch["v"]), int(t * 32.0) % 16, float(ch["a"]) + t * 3.0, 1.0 + 0.35 * sin(t * PI), 1.0 - smoothstep(0.6, 1.0, t), 1.0 + up * 0.08)
	chads_up = keep
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
	if state in ["home", "intro"]:
		return
	var font: Font = ui_font()
	var ink := Color(0.15, 0.15, 0.19, 0.92)
	var red := Color(0.75, 0.16, 0.15, 0.9)
	var x0 := 30.0
	var top_y := _top() + 58.0
	var live := Vector2(view.x * 0.5, _top() + 150.0)  # the chain being driven: top centre, a little down, where a glance reaches
	# stamps that have flown up are counted into the total
	var keep: Array = []
	var counted_in := 0
	for st in stamps:
		if clock - float(st["t"]) >= STAMP_HOLD + 0.45:
			counted_in += int(st["pts"])
		else:
			keep.append(st)
	stamps = keep
	var total := int(score - _stamped(stamps))
	if counted_in > 0:  # just counted in: the old total is what it was before these stamps
		merged_from = total - counted_in
		merged_t = clock
		total_t = clock
		if state == "play":
			_play("coin", -4.0, 1.15)  # counted in
	# the total: small and quiet in the corner; when a stamp lands the old number is crossed out
	var age := clock - merged_t
	if age < 1.0:
		var old := str(merged_from)
		var ow := font.get_string_size(old, HORIZONTAL_ALIGNMENT_LEFT, -1, 37).x
		var fade := 1.0 - smoothstep(0.6, 1.0, age)
		_text(n, font, old, Vector2(x0, top_y), 37, Color(ink, ink.a * fade))
		n.draw_line(Vector2(x0 - 3, top_y - 12), Vector2(x0 + ow + 3, top_y - 19), Color(ink, 0.8 * fade), 2.4, true)
		_text_pulse(n, font, str(total), Vector2(x0 + (ow + 18) * fade, top_y), 37, ink, clock - total_t, 0.0)
	else:
		_text_pulse(n, font, str(total), Vector2(x0, top_y), 37, Color(ink, 0.8), clock - total_t, 0.0)
	# confetti won by clips flying up to the counter: they land one by one, each popping it
	var ic := Vector2(x0 + 18, top_y + 34)
	var pending := 0
	var in_air: Array = []
	for ch in chads_fly:
		var u := (clock - float(ch["t"])) / CHAD_FLY
		if u >= 1.0:
			pop_t = clock
			continue
		in_air.append(ch)
		pending += int(ch["n"])
		if u < 0.0:
			continue
		var e := u * u * (3.0 - 2.0 * u)
		var from: Vector2 = ch["from"]
		var mid := from.lerp(ic, 0.5) + Vector2(90.0 * float(ch["side"]), -70.0)
		var at := from.lerp(mid, e).lerp(mid.lerp(ic, e), e)
		_draw_chad(n, at, int(ch["v"]), int(u * 40.0) % 16, float(ch["a"]) + u * 5.0, lerpf(1.1, 0.55, e), 1.0, 1.0 + 3.0 * sin(u * PI))
	chads_fly = in_air
	# confetti: hidden until the first piece, then always shown; it pops each time one comes in
	var pt := clock - pop_t
	if coins_got > 0:
		var pop := sin(clampf(pt / 0.28, 0.0, 1.0) * PI) if pt < 0.28 else 0.0
		var a := 1.0
		var isz := 34.0 * (1.0 + 0.32 * pop)
		n.draw_texture_rect(_tex("handful"), Rect2(ic - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, a))
		_text(n, font, "%d" % (coins_got - pending), ic + Vector2(22, 10), int(28 + 6 * pop), Color(ink, 0.7 * a))
	# the chain being driven, top centre: points, the grace running out, the combo and its meter in red
	if chain_on and chain_pts >= 1.0:
		var flying := 0
		var still: Array = []
		for fl in flights:
			if clock - float(fl["t"]) < FLIGHT:
				flying += int(fl["pts"])
				still.append(fl)
			else:
				live_t = clock  # landed: the chain number pops
		flights = still
		var txt := "+%d" % int(chain_pts - flying)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
		_text_pulse(n, font, txt, live + Vector2(-tw * 0.5, 0), 54, ink, clock - live_t, tw * 0.5)
		for fl in flights:  # clip points arcing up from the cone or box to the chain
			var u := clampf((clock - float(fl["t"])) / FLIGHT, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var from: Vector2 = fl["from"]
			var to := live + Vector2(0, -18)
			var mid := from.lerp(to, 0.5) + Vector2((to.x - from.x) * 0.15 + 60.0, -40.0)
			var at := from.lerp(mid, e).lerp(mid.lerp(to, e), e)
			var ft := "+%d" % int(fl["pts"])
			var sz := int(lerpf(40.0, 28.0, e))
			var fw := font.get_string_size(ft, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			_text(n, font, ft, at - Vector2(fw * 0.5, 0), sz, Color(fl["col"], 1.0 - 0.3 * e))
		var g := clampf(chain_grace / (SWAP_GRACE if swap_wait else CHAIN_GRACE), 0.0, 1.0)  # a pencil line that shrinks as the grace runs out
		n.draw_line(live + Vector2(-90.0 * g, 16), live + Vector2(90.0 * g, 18), Color(ink, 0.7), 3.0, true)
		# the combo below it, with its own meter: a red line growing from the middle as this side's drift
		# earns its way to the next step; full = ready, the switch to the other side cashes it
		var mt := "MAX" if mult >= 9 else "x%d" % mult
		var my := live + Vector2(0, 62)
		var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		_text_pulse(n, font, mt, my + Vector2(-mw * 0.5, 0), 40, red if mult > 1 else Color(red, 0.55), clock - mult_t, mw * 0.5)
		var f := 1.0 if mult >= 9 else clampf(side_pts / SWITCH_PTS, 0.0, 1.0)
		if f > 0.0:
			var ready := f >= 1.0
			var half := 70.0 * f * (1.0 + (0.08 * sin(clock * 14.0) if ready and mult < 9 else 0.0))
			n.draw_line(my + Vector2(-half, 14), my + Vector2(half, 16), Color(red, 0.95 if ready else 0.6), 4.0 if ready else 3.0, true)
	# the stamps: thumped down where the chain was, then flown up into the total
	for k in stamps.size():
		var st: Dictionary = stamps[k]
		var sa := clock - float(st["t"])
		var fly := smoothstep(STAMP_HOLD, STAMP_HOLD + 0.45, sa)
		var thump := 1.0 + 0.45 * (1.0 - smoothstep(0.0, 0.12, sa))
		var at := (live + Vector2(k * 22.0, -20.0 + k * 10.0)).lerp(Vector2(x0 + 60.0, top_y - 14.0), fly)
		_stamp(n, font, st, at, thump * (1.0 - 0.45 * fly), 1.0 - smoothstep(0.75, 1.0, fly))


func _stamped(list: Array) -> float:
	var t := 0.0
	for st in list:
		t += float(st["pts"])
	return t


## A rubber stamp in red ink: a double rough border and the number, the ink a little patchy.
## A rubber stamp pressed by hand: a wobbly double frame with rounded corners, the ink heavier on the side
## pressed hardest and broken where the rubber missed, small caps above and below the number, the number
## struck a touch double, paper specks showing through and a few spatters. Each stamp has its own seed.
func _stamp(n: Node2D, font: Font, st: Dictionary, at: Vector2, k: float, a: float) -> void:
	var sd := int(st.get("seed", 0))
	var big := int(st["pts"]) > 1500
	var text := "+%d" % int(st["pts"])
	var red := Color(0.72, 0.13, 0.12, 0.9 * a)
	var size_px := 58 if big else 50
	var small := 20 if big else 18
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var label := String(st.get("label", "DRIFT"))
	var foot := "x%d COMBO" % int(st.get("combo", 1)) if int(st.get("combo", 1)) > 1 else ""
	w = maxf(w, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 10.0)
	n.draw_set_transform(at, float(st["rot"]), Vector2(k, k))
	var r := Rect2(-w * 0.5 - 20.0, -size_px * 0.62 - small - 8.0, w + 40.0, size_px * 1.05 + small * (2.0 if foot != "" else 1.0) + 22.0)
	var press := Vector2.from_angle(_h(sd, 1) * TAU)  # the side pressed hardest gets the most ink
	_stamp_frame(n, r, 9.0, 3.6, red, press, sd)
	_stamp_frame(n, r.grow(-6.5), 5.0, 1.6, Color(red, red.a * 0.75), press, sd + 7)
	var ink := func(p: Vector2) -> Color:  # heavier towards the pressed side
		var d := clampf(p.dot(press) / (r.size.x * 0.5), -1.0, 1.0)
		return Color(red, red.a * (0.78 + 0.22 * d))
	# small caps above and below the number
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	n.draw_string(font, Vector2(-lw * 0.5, r.position.y + small + 7.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, small, ink.call(Vector2(0, r.position.y)))
	if foot != "":
		var fw := font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		n.draw_string(font, Vector2(-fw * 0.5, r.end.y - 12.0), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, small, ink.call(Vector2(0, r.end.y)))
	# the number: struck slightly double where the stamp rocked
	var tp := Vector2(-w * 0.5 + (w - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x) * 0.5, size_px * 0.28)
	n.draw_string(font, tp + press * 1.6, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(red, red.a * 0.28))
	n.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, ink.call(-press * 10.0))
	# paper showing through where the rubber didn't take ink, more on the light side
	var paper := Color(0.97, 0.965, 0.95, 0.8 * a)
	for i in 34:  # soft round flecks, a few streaked along the press
		var p := r.position + Vector2(_h(sd, 10 + i) * r.size.x, _h(sd, 50 + i) * r.size.y)
		if p.dot(press) > 0.0 and _h(sd, 90 + i) < 0.6:
			continue
		var sz := 0.6 + _h(sd, 130 + i) * _h(sd, 140 + i) * 2.4
		if _h(sd, 150 + i) < 0.2:
			n.draw_line(p, p + press.orthogonal() * (3.0 + sz * 2.0), paper, sz, true)
		else:
			n.draw_circle(p, sz, paper)
	# a few spatters just outside, on the pressed side
	for i in 5:
		var ang := press.angle() + (_h(sd, 170 + i) - 0.5) * 1.6
		var dist := r.size.x * 0.5 + 6.0 + _h(sd, 180 + i) * 14.0
		var p := Vector2.from_angle(ang) * Vector2(dist, dist * r.size.y / r.size.x)
		n.draw_circle(p, 0.8 + _h(sd, 190 + i) * 1.6, Color(red, red.a * 0.7))
	n.draw_set_transform(Vector2.ZERO)


## A stamp's frame: a rounded rectangle traced in short pieces that wobble a little, thicker and darker
## on the pressed side, with small gaps where the rubber didn't print.
func _stamp_frame(n: Node2D, r: Rect2, rad: float, width: float, col: Color, press: Vector2, sd: int) -> void:
	var pts := PackedVector2Array()
	var c := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for q in 4:  # each corner's arc, then the straight run to the next one
		for j in 5:
			var ang := PI + q * PI * 0.5 + j * PI * 0.125
			pts.append(c[q] + Vector2.from_angle(ang) * rad)
		var nxt: Vector2 = c[(q + 1) % 4] + Vector2.from_angle(PI + (q + 1) * PI * 0.5) * rad
		var last := pts[pts.size() - 1]
		var steps := int(last.distance_to(nxt) / 9.0)
		for j in range(1, steps):
			pts.append(last.lerp(nxt, float(j) / steps))
	var m := pts.size()
	for i in m:
		var p0 := pts[i] + Vector2(sin(i * 0.9 + sd), cos(i * 0.7 + sd * 0.3)) * 0.9
		var p1 := pts[(i + 1) % m] + Vector2(sin((i + 1) * 0.9 + sd), cos((i + 1) * 0.7 + sd * 0.3)) * 0.9
		if _h(sd, 300 + i) < 0.07:
			continue  # the rubber missed here
		var d := clampf(p0.dot(press) / (r.size.x * 0.5), -1.0, 1.0)
		n.draw_line(p0, p1, Color(col, col.a * (0.7 + 0.3 * d)), width * (0.8 + 0.35 * d), true)


## A steady hash in 0..1 for (seed, i): the same stamp always looks the same.
func _h(sd: int, i: int) -> float:
	var f := sin(float(sd) * 12.9898 + float(i) * 78.233) * 43758.5453
	return f - floorf(f)


## Text that pops when something just happened (`age` seconds ago): swells and settles in 0.35 s, a little
## overshoot, scaled around `pivot_x` along its baseline.
func _text_pulse(n: Node2D, font: Font, s: String, p: Vector2, size: int, col: Color, age: float, pivot_x: float) -> void:
	if age < 0.0 or age > 0.35:
		_text(n, font, s, p, size, col)
		return
	var k := 1.0 + 0.55 * sin(age / 0.35 * PI) * (1.0 - age / 0.35 * 0.5)
	var o := p + Vector2(pivot_x, -size * 0.35)
	n.draw_set_transform(o, 0.0, Vector2(k, k))
	_text(n, font, s, p - o, size, col)
	n.draw_set_transform(Vector2.ZERO)


func _text(n: Node2D, font: Font, s: String, p: Vector2, size: int, col: Color) -> void:
	n.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1, 1, 1, 0.7))
	n.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---------------------------------------------------------------- pause and summary

## The phone's back button: in a run it pauses (paused, hold to start again); on the start page it closes
## the settings if they are open, else asks before quitting. (The proper screens come with the UI phases.)
func _back() -> void:
	match state:
		"play":
			_pause()
		"crashed", "summary":
			_home()
		"home":
			if overlay != null:  # back again on the question: stay
				_stay()
			elif start_page.mode == "settings":
				start_page._close()
			else:
				overlay = _panel("QUIT?", ["Do you want to quit?"], [["Quit", func(): get_tree().quit()], ["Stay", _stay]])


func _stay() -> void:
	if overlay:
		overlay.queue_free()
	overlay = null


## Pause (the drawn sign, the back button): slow motion into a frozen pencil sketch of the moment, with
## the pause written beside the car (pause_note.gd). `instant` when the app is being left: straight to frozen.
func _pause(instant := false) -> void:
	if overlay != null or state != "play":
		return
	touches.clear()
	var note := PauseNote.new()
	overlay = note
	ui.add_child(note)
	note.setup(self, instant)
	pause_btn.visible = false


## The pause note has eased time back up: the run carries on.
## The pause sign: two bars in a ring, drawn in pencil (a button, at least 48 dp to tap).
class PauseSign extends Button:
	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(84, 84)
		size = Vector2(84, 84)

	func _draw() -> void:
		var c := size * 0.5
		var ink := Color(0.15, 0.15, 0.19, 0.85)
		var ring := PackedVector2Array()
		for i in 31:
			var a := 0.6 + TAU * 1.08 * i / 30.0
			var r := 26.0 * (1.0 + 0.05 * i / 30.0) + sin(i * 2.7) * 0.6
			ring.append(c + Vector2(cos(a), sin(a)) * r)
		draw_polyline(ring, ink, 2.6, true)
		draw_polyline(PackedVector2Array([c + Vector2(-7, -11), c + Vector2(-7.6, 0), c + Vector2(-7.2, 11)]), ink, 4.2, true)
		draw_polyline(PackedVector2Array([c + Vector2(7, -11), c + Vector2(7.5, 0), c + Vector2(7.1, 11.5)]), ink, 4.2, true)


func pause_done(note: Node) -> void:
	note.queue_free()
	overlay = null
	pause_btn.visible = true


func pause_start_over() -> void:
	again_requested.emit()  # main.gd turns the page to a fresh run


func drive_again() -> void:
	again_requested.emit()


func _resume() -> void:
	get_tree().paused = false
	touches.clear()
	if overlay:
		overlay.queue_free()
	overlay = null


func _home() -> void:
	get_tree().paused = false
	home_requested.emit()


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
	Engine.time_scale = 1.0  # never leave the game slowed or muffled (a pause may be mid-way)
	AudioServer.playback_speed_scale = 1.0
	if scrib:
		scrib.save_seen()  # remember the notes seen, however the run ended
		inks.save()
	get_viewport().canvas_cull_mask = 0xFFFFFFFF  # a 3D camera hid the flat world; the title screen needs it back
