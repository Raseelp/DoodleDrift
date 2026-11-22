extends Node
## Global state: lake data, saved progress, settings and shared helpers.

const SAVE_PATH := "user://save.cfg"
const LAKE_SIZE := Vector2(720, 1280)
const DAY_SLACK := 1.45  # how much longer than a clean run the sun stays up
const MIN_DAY := 20.0  # the first lakes stay gentle
const MARK_ALL := 1
const MARK_TIME := 2
const MARK_LOOPS := 4

var lakes: Array = []
var unlocked := 1
var chapter_seen := false  # the "still lakes are bright again" moment has played
var dev_victory := false  # dev: play the chapter victory on the next map, as a test (never saved)
# Where the pickup is parked on the map (-1: by the first open lake not yet lit), and a lake a win has
# just opened, which it drives to the next time the map is on screen (-1: none).
var rig_lake := -1
var rig_pending := -1
var marks: Array = []
var stats: Array = []  # per lake: tries, wins, fails, crashes, revives, best, last fails
var sound_on := true
var music_on := true
var vibration_on := true
var dev := {"life": true, "fading": false,
	"crash": true, "unlock_all": false, "boat3d": true}
## Daylight tuning from the Dev panel: a multiplier on the automatic time, or a fixed time (0 = automatic).
var day_mult := 1.0
var day_fixed := 0
var boat_tilt := 35.0  # Dev: camera tilt of the 3D boat in degrees (0 = straight down)

var ui_theme: Theme
var title_font: FontVariation
var heading_font: FontVariation
var glow_tex: GradientTexture2D
var beam_tex: ImageTexture  # a headlight beam: apex at the left middle, pointing right

var _water_cache := {}
const HitButton = preload("res://scripts/hit_button.gd")
## The 3D boat model, loaded once in the background at start-up and kept, so starting a lake
## doesn't stop to load it again.
const BOAT_MODEL := "res://models/fishing_boat.glb"
var _boat_scene: PackedScene
const PICKUP_MODEL := "res://models/pickup_low.glb"
const TRAILER_MODEL := "res://models/trailer_low.glb"
const SWAN_MODEL := "res://models/swan.glb"
const FONT_PATH := "res://fonts/JosefinSans-Variable.ttf"
var _scenes := {}  # the pickup and trailer, loaded once like the boat
## The storm lantern pictures (scripts/lantern_art.gd), rendered once shortly after start-up.
## anchor: where the float meets the water in the picture; glass: the flame. Null until ready.
const LANTERN_SCALE := 0.34  # the lantern pictures on a lake, in lake units: about 46 px tall
var lantern_unlit: Texture2D
var lantern_lit: Texture2D
var lantern_anchor := Vector2.ZERO
var lantern_glass := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_lakes()
	marks.resize(lakes.size())
	marks.fill(0)
	for i in lakes.size():
		stats.append(_new_stat())
	_load()
	_build_theme()
	glow_tex = _make_glow()
	beam_tex = _make_beam()


## The heavy start-up work, begun once the loading screen's first frame is up (main.gd): all four models
## load in the background (started later, with the map already up, their textures going to the GPU would
## stall a visible frame) and the lantern art renders.
func start_loading() -> void:
	for path in [PICKUP_MODEL, TRAILER_MODEL, BOAT_MODEL, SWAN_MODEL]:
		_request(path)
	_make_lantern_art()


func _make_lantern_art() -> void:
	var art: SubViewport = load("res://scripts/lantern_art.gd").new()
	art.done.connect(func(unlit: ImageTexture, lit: ImageTexture, anchor: Vector2, glass: Vector2):
		lantern_unlit = unlit
		lantern_lit = lit
		lantern_anchor = anchor
		lantern_glass = glass)
	add_child(art)


# ---------------------------------------------------------------- lakes

func _pal(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = Color(d[k])
	return out


func _build_lakes() -> void:
	lakes = [
		{
			"name": "First Light",
			"hint": "Light every lantern before dark.",
			"par": "auto", "pitch": 1.0, "motes": "petals",
			"pal": _pal({
				"land": "7d9a72", "land_dark": "6c8964", "tree": "56755a", "tree_hi": "86a67c",
				"shadow": "3f5a48", "sand": "e3d3b0", "shallow": "86b8b2", "mid": "5f9ba3",
				"deep": "46808f", "rock": "8c8f8a", "rock_hi": "b1b4ac", "reed": "aab66f",
				"light": "ffd08a", "pair": "a5ece0", "night": "a08cbc", "mote": "f4bccb",
				"wood": "9a7b58",
			}),
			# The Lantern Isles: a hook of wooded land reaches down from the north shore with the swans' nest
			# on its shore and a quiet lagoon tucked behind it; a cove in the north-west hides behind a long
			# island and a line of stones (in by the narrow west passage or the gap in the stones); a sandbar
			# off the south shore makes a back channel; the east bay has an islet and a bed of reeds.
			"width": 1440, "goal": "dusk",
			"water": [[70, 760], [85, 520], [150, 330], [280, 220], [450, 195], [590, 225], [650, 300], [640, 420], [675, 540], [750, 615], [860, 640], [960, 600], [1010, 520], [1000, 430], [950, 470], [890, 500], [820, 480], [785, 400], [790, 290], [880, 210], [1060, 185], [1230, 200], [1350, 270], [1410, 430], [1405, 640], [1370, 850], [1290, 1050], [1150, 1180], [980, 1215], [860, 1180], [760, 1135], [650, 1160], [540, 1215], [380, 1225], [230, 1180], [120, 1060], [80, 920]],
			"islands": [[[195, 610], [255, 505], [375, 445], [470, 430], [505, 480], [455, 560], [330, 640], [230, 680]], [[700, 920], [800, 890], [930, 900], [960, 940], [880, 965], [760, 970]], [[1150, 560], [1210, 530], [1250, 580], [1210, 630], [1160, 620]]],
			"lanterns": [[180, 850, 0], [330, 320, 0], [900, 360, 0], [560, 760, 0], [830, 1060, 0], [1250, 370, 0], [1295, 790, 0], [1060, 960, 0]],
			"rocks": [[492, 405, 17], [512, 360, 16], [578, 238, 16], [1120, 300, 15]], "reeds": [[1300, 800, 78]],
			"swan": [735, 625, 150.0, 1.4],
			"start": [300, 1098, -PI / 2], "jetty": [300, 1218, 300, 1128, ""], "rig": -1, "ducks": 2,
		},
		{
			"name": "Two Coves",
			"hint": "Ducks cut your trail.\nClose your loop before they cross.",
			"par": "auto", "pitch": 1.1225, "motes": "petals",
			"pal": _pal({
				"land": "93ab6c", "land_dark": "829a5e", "tree": "66824c", "tree_hi": "a0bb7b",
				"shadow": "4b6440", "sand": "ecdcb0", "shallow": "8cc5b8", "mid": "63a9a8",
				"deep": "448992", "rock": "8d8a80", "rock_hi": "b4b0a4", "reed": "b2bd6a",
				"light": "ffd77a", "pair": "a5ece0", "night": "a691b6", "mote": "f6e6a6",
				"wood": "a07e56",
			}),
			# Two coves joined by narrows, a reed island splitting them into a north and a south channel.
			# Duck families commute between the coves on a set loop (east by the north channel, back west
			# by the south one), resting at each end, so their crossings can be learned and timed. The
			# jetty is mid south shore under the narrows; the swans nest in the east cove's far corner and
			# their egg floats out between, so it comes home across the duck route.
			"width": 1440, "goal": "egg", "teaser": "ducks",
			"water": [[70, 700], [90, 450], [180, 270], [360, 200], [540, 230], [640, 330], [690, 440],
				[760, 450], [820, 330], [940, 230], [1130, 200], [1300, 250], [1390, 420], [1400, 680],
				[1340, 930], [1200, 1110], [1000, 1170], [880, 1110], [820, 990], [760, 1060], [680, 1060],
				[620, 990], [560, 1110], [380, 1190], [200, 1130], [90, 950]],
			"islands": [[[650, 650], [720, 605], [795, 635], [800, 715], [725, 765], [655, 725]],
				[[1070, 520], [1130, 480], [1190, 510], [1180, 580], [1110, 600], [1060, 570]]],
			"lanterns": [[250, 420, 0], [300, 860, 0], [500, 640, 0], [610, 520, 0], [820, 850, 0],
				[1000, 880, 0], [1280, 720, 0], [1180, 380, 0]],
			"rocks": [], "reeds": [[725, 685, 125], [1320, 800, 70]],
			"swan": [1330, 330, 160.0, 1.1],
			# The ducks' loop: [x, y, seconds resting there]
			"duck_route": [[300, 700, 6.0], [470, 560, 0.0], [640, 515, 0.0], [820, 525, 0.0], [1000, 610, 0.0],
				[1150, 760, 6.0], [1000, 900, 0.0], [820, 880, 0.0], [640, 870, 0.0], [470, 830, 0.0]],
			"start": [720, 968, -PI / 2], "jetty": [720, 1078, 720, 998, ""], "rig": 1, "ducks": 3,
		},
		{
			"name": "Stones",
			"hint": "Swans guard their nest.\nKeep your distance.",
			"par": 2, "pitch": 0.8909, "motes": "leaves",
			"pal": _pal({
				"land": "b08a55", "land_dark": "9e7a4a", "tree": "b2603c", "tree_hi": "da8c57",
				"shadow": "6e5232", "sand": "ead1a0", "shallow": "7aaeb2", "mid": "53909c",
				"deep": "397381", "rock": "7f7f7c", "rock_hi": "aaa9a3", "reed": "c4a86a",
				"light": "ffbf6e", "pair": "a5ece0", "night": "8e72a2", "mote": "e38c4e",
				"wood": "8a6a48",
			}),
			"water": [[70, 330], [220, 210], [500, 200], [650, 330], [670, 620], [640, 900],
				[560, 1150], [330, 1210], [130, 1140], [60, 880], [90, 600]],
			"lanterns": [[250, 400, 0], [470, 380, 0], [360, 680, 0], [255, 960, 0], [545, 700, 0]],
			"rocks": [[360, 520, 40], [215, 790, 32], [495, 850, 45], [385, 1035, 28]],
			"reeds": [],
			"start": [300, 1150, -PI / 2], "jetty": [292, 1226, 296, 1182, ""], "rig": 1, "ducks": 1,
			"swan": [71, 705, 190.0, 0.8],  # nest, how far their water reaches, seconds before the cob charges
		},
		{
			"name": "Reed Bend",
			"hint": "Reeds slow the boat down.",
			"par": 3, "pitch": 0.7937, "motes": "fireflies",
			"pal": _pal({
				"land": "5f6b45", "land_dark": "535f3c", "tree": "404e34", "tree_hi": "68764b",
				"shadow": "323d29", "sand": "c9ad84", "shallow": "5f8f8f", "mid": "477b81",
				"deep": "32616f", "rock": "6e6c68", "rock_hi": "8f8c86", "reed": "a3a35c",
				"light": "ffa66e", "pair": "a5ece0", "night": "5e5a88", "mote": "ffe7a0",
				"wood": "7a5d42",
			}),
			"water": [[90, 250], [330, 190], [560, 230], [650, 380], [590, 540], [420, 600],
				[330, 680], [340, 800], [500, 860], [640, 980], [600, 1160], [380, 1220],
				[150, 1150], [70, 960], [110, 800], [150, 660], [80, 520], [70, 380]],
			"lanterns": [[200, 330, 0], [515, 340, 0], [240, 1045, 0], [560, 990, 0], [420, 1090, 0]],
			"rocks": [],
			"reeds": [[245, 690, 70], [520, 330, 60], [235, 1055, 70]],
			"start": [390, 1150, -PI * 0.6], "jetty": [384, 1242, 388, 1184, "T"], "rig": -1, "dusk_start": 0.5, "ducks": 1,
			"swan": [346, 674, 190.0, 1.0],
		},
		{
			"name": "Twin Lights",
			"hint": "Twin lanterns only light together.\nCircle both in one loop.",
			"par": 3, "pitch": 0.8409, "motes": "fireflies",
			"pal": _pal({
				"land": "2b3b3a", "land_dark": "243232", "tree": "1c2b2c", "tree_hi": "344a47",
				"shadow": "141f20", "sand": "4f5d5b", "shallow": "2d4f59", "mid": "22414d",
				"deep": "19313e", "rock": "3f4848", "rock_hi": "586464", "reed": "435a48",
				"light": "ffd98c", "pair": "8fe0ff", "night": "7a82b0", "mote": "fff1a8",
				"wood": "4a3d30",
			}),
			"water": [[80, 320], [250, 210], [480, 200], [640, 320], [670, 560], [620, 760],
				[660, 980], [560, 1170], [340, 1220], [140, 1150], [60, 940], [100, 720], [60, 520]],
			"lanterns": [[220, 380, 1], [480, 420, 1], [250, 1050, 2], [470, 1085, 2],
				[350, 510, 0], [565, 650, 0]],
			"rocks": [[360, 640, 42], [200, 880, 30]],
			"reeds": [[520, 880, 65]],
			"start": [172, 730, 0.0], "jetty": [58, 730, 142, 730, ""], "rig": 1, "night": true, "ducks": 1,
		},
	]
	for i in lakes.size():
		if str(lakes[i]["par"]) == "auto":
			lakes[i]["par"] = auto_par(i)


## A fair loop limit worked out from where the lanterns are: lanterns that one loop of a comfortable size
## (about 300 px across) could take together, with clear water between them, are grouped greedily; the
## number of groups is the fewest loops a tidy run needs, and that is the limit: no spare loops.
const PAR_LOOP := 150.0  # the farthest a lantern may be from the middle of its group
func auto_par(i: int) -> int:
	var left: Array = []
	for l in lakes[i]["lanterns"]:
		left.append(Vector2(l[0], l[1]))
	var groups := 0
	while not left.is_empty():
		var best: Array = []
		for s0 in left:
			var group: Array = [s0]
			var others := left.duplicate()
			others.sort_custom(func(a, b): return s0.distance_to(a) < s0.distance_to(b))
			for o in others:
				if o == s0:
					continue
				var trial := group.duplicate()
				trial.append(o)
				var mid := Vector2.ZERO
				for q in trial:
					mid += q
				mid /= trial.size()
				var fits := true
				for q in trial:
					if q.distance_to(mid) > PAR_LOOP or not _open_line(i, q, mid):
						fits = false
						break
				if fits:
					group = trial
			if group.size() > best.size():
				best = group
		for q in best:
			left.erase(q)
		groups += 1
	return groups


## Whether the straight way between two points stays on open water (no shore, no island).
func _open_line(i: int, a: Vector2, b: Vector2) -> bool:
	var water := water_poly(i)
	var steps := maxi(1, int(a.distance_to(b) / 16.0))
	for k in steps + 1:
		var q := a.lerp(b, float(k) / steps)
		if not Geometry2D.is_point_in_polygon(q, water):
			return false
		for isl in island_polys(i):
			if Geometry2D.is_point_in_polygon(q, isl):
				return false
	return true


## The boat model (waits for the background load the first time), or null if the file is missing.
func boat_scene() -> PackedScene:
	if _boat_scene == null and ResourceLoader.exists(BOAT_MODEL):
		_request(BOAT_MODEL)
		_boat_scene = ResourceLoader.load_threaded_get(BOAT_MODEL) as PackedScene
	return _boat_scene


## Whether these models have finished loading in the background (so using them won't wait).
func models_ready(paths: Array) -> bool:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		if path == BOAT_MODEL and _boat_scene != null or _scenes.has(path):
			continue
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false  # a failed load counts as done: that part is just left out, as before
	return true


## Starts loading a model in the background (once; asking again is harmless).
func _request(path: String) -> void:
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)


## The pickup or trailer model (waits for its background load the first time).
func model_scene(path: String) -> PackedScene:
	if not _scenes.has(path) and ResourceLoader.exists(path):
		_request(path)  # not asked for yet: ask now (and wait for it)
		_scenes[path] = ResourceLoader.load_threaded_get(path) as PackedScene
	return _scenes.get(path)


## Night lakes run on the boat's headlight battery from the start: their time goal is "Battery to spare".
func is_night(i: int) -> bool:
	return bool(lakes[i].get("night", false))


## A lake's width in lake pixels: one screen (720) unless it is a wide lake that pans sideways.
func lake_width(i: int) -> float:
	return float(lakes[i].get("width", LAKE_SIZE.x))


## The middle of a lake's picture (lake pixels): the map centres it on its spot.
func lake_center(i: int) -> Vector2:
	return Vector2(lake_width(i) * 0.5, 705.0)


## Where the camera starts on a lake (its left edge, lake pixels): the jetty's part of it.
func start_cam_x(i: int) -> float:
	return clampf(float(lakes[i]["start"][0]) - LAKE_SIZE.x * 0.5, 0.0, lake_width(i) - LAKE_SIZE.x)


## Where the camera was when the lake was left, for the map's zoom out (set by the lake).
var exit_cam_x := 0.0


## Whether a lake's second goal is the swans' egg (else before dusk, or battery to spare at night). Swans
## can be on any lake; only lakes marked "egg" (or older lakes with swans and no goal set) ask for it.
func egg_goal(i: int) -> bool:
	return lakes[i].has("swan") and String(lakes[i].get("goal", "egg")) == "egg"


## The time goal's icon and name for a lake.
func time_goal(i: int) -> Array:
	# A lake with an egg goal swaps this goal for returning their egg (daylight still ends the run).
	if egg_goal(i):
		return ["egg", "Return the egg"]
	return ["battery", "Battery to spare"] if is_night(i) else ["sun", "Before dusk"]


## Chapter two opens at this many goals of the chapter's 15, with every swans' egg returned.
const CH2_GOALS := 12


func goals_earned() -> int:
	var n := 0
	for i in lakes.size():
		var m := int(marks[i])
		n += int(m & MARK_ALL != 0) + int(m & MARK_TIME != 0) + int(m & MARK_LOOPS != 0)
	return n


## [eggs returned, egg goals in the chapter].
func eggs_returned() -> Array:
	var got := 0
	var all := 0
	for i in lakes.size():
		if egg_goal(i):
			all += 1
			if int(marks[i]) & MARK_TIME != 0:
				got += 1
	return [got, all]


func lake_count() -> int:
	return lakes.size()


## Smoothed shoreline for a lake (cached).
func water_poly(i: int) -> PackedVector2Array:
	if _water_cache.has(i):
		return _water_cache[i]
	var coarse := PackedVector2Array()
	for p in lakes[i]["water"]:
		coarse.append(Vector2(p[0], p[1]))
	var poly := smooth_closed(coarse, 8)
	# A gentle wobble so the shore does not look machine-perfect.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (i + 1)
	var phase := rng.randf() * TAU
	for k in poly.size():
		var prev := poly[(k - 1 + poly.size()) % poly.size()]
		var next := poly[(k + 1) % poly.size()]
		var normal := (next - prev).orthogonal().normalized()
		var w := sin(float(k) * 0.55 + phase) * 3.0 + sin(float(k) * 1.7 + phase * 2.0) * 1.5
		poly[k] = poly[k] + normal * w
	_water_cache[i] = poly
	return poly


## A lake's islands, each a smoothed outline (cached). Land inside the lake: the boat goes round them.
func island_polys(i: int) -> Array:
	if _isle_cache.has(i):
		return _isle_cache[i]
	var out: Array = []
	for isl in lakes[i].get("islands", []):
		var coarse := PackedVector2Array()
		for p in isl:
			coarse.append(Vector2(p[0], p[1]))
		out.append(smooth_closed(coarse, 6))
	_isle_cache[i] = out
	return out


var _isle_cache := {}


func smooth_closed(pts: PackedVector2Array, sub: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p0 := pts[(i - 1 + n) % n]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3 := pts[(i + 2) % n]
		for s in sub:
			var t := float(s) / float(sub)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


## Largest polygon from an offset (negative delta shrinks).
func offset_largest(poly: PackedVector2Array, delta: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(poly, delta, Geometry2D.JOIN_ROUND)
	var best := PackedVector2Array()
	var best_area := -1.0
	for p in res:
		var a := absf(poly_area(p))
		if a > best_area:
			best_area = a
			best = p
	if best.is_empty() and res.size() > 0:
		best = res[0]
	return best


func poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	var n := p.size()
	for i in n:
		a += p[i].x * p[(i + 1) % n].y - p[(i + 1) % n].x * p[i].y
	return a * 0.5


# ---------------------------------------------------------------- progress

func record_result(i: int, got: int) -> void:
	marks[i] = int(marks[i]) | got
	if got & MARK_ALL and i + 1 < lakes.size():
		unlocked = maxi(unlocked, i + 2)
	_save()


func _new_stat() -> Dictionary:
	return {"tries": 0, "wins": 0, "fails": 0, "crashes": 0, "revives": 0, "best": 0.0, "last_fails": [], "water": 0.0}


func stat_add(i: int, key: String) -> void:
	stats[i][key] = int(stats[i][key]) + 1
	_save()


func stat_fail(i: int, lit: int, total: int) -> void:
	var s: Dictionary = stats[i]
	s["fails"] = int(s["fails"]) + 1
	var lf: Array = s["last_fails"]
	lf.append("%d/%d" % [lit, total])
	while lf.size() > 5:
		lf.remove_at(0)
	_save()


## Time out on the water on lake i (every try, wins or not), for the chapter's totals.
func add_water(i: int, secs: float) -> void:
	stats[i]["water"] = float(stats[i].get("water", 0.0)) + secs
	_save()


func stat_win(i: int, t: float) -> void:
	var s: Dictionary = stats[i]
	s["wins"] = int(s["wins"]) + 1
	if float(s["best"]) <= 0.0 or t < float(s["best"]):
		s["best"] = t
	_save()


func set_daylight(mult: float, fixed: int) -> void:
	day_mult = mult
	day_fixed = fixed
	_save()


func set_boat_tilt(deg: float) -> void:
	boat_tilt = deg
	_save()


func reset_stats() -> void:
	for i in stats.size():
		stats[i] = _new_stat()
	_save()


## Seconds of daylight for a lake, worked out from its layout: the boat's route from the start through
## every lantern, one loop per allowed loop, extra for reeds and rocks, then some slack for a first try.
func lake_duration(i: int) -> float:
	if day_fixed > 0:
		return float(day_fixed)
	return roundf(auto_duration(i) * day_mult)


func auto_duration(i: int) -> float:
	var lk: Dictionary = lakes[i]
	var pos := Vector2(lk["start"][0], lk["start"][1])
	var left: Array = []
	for l in lk["lanterns"]:
		left.append(Vector2(l[0], l[1]))
	var route := 0.0
	while not left.is_empty():
		var best := 0
		for k in left.size():
			if pos.distance_to(left[k]) < pos.distance_to(left[best]):
				best = k
		route += pos.distance_to(left[best])
		pos = left[best]
		left.remove_at(best)
	var loops := float(lk["par"]) * 2.0 * PI * 70.0
	var secs := (route + loops) / 150.0
	for r in lk["reeds"]:
		for l in lk["lanterns"]:
			if Vector2(l[0], l[1]).distance_to(Vector2(r[0], r[1])) < float(r[2]) + 40.0:
				secs += 2.5
	secs += lk["rocks"].size() * 1.0
	return maxf(MIN_DAY, secs * DAY_SLACK + 4.0)


func is_unlocked(i: int) -> bool:
	return i < unlocked or dev_on("unlock_all")


func dev_on(key: String) -> bool:
	return bool(dev.get(key, false))


func set_dev(key: String, value: bool) -> void:
	dev[key] = value
	_save()


func reset_progress() -> void:
	unlocked = 1
	chapter_seen = false
	rig_lake = -1
	rig_pending = -1
	marks.fill(0)
	_save()


## The pickup is now parked by lake i (it drove there, or a lake was played).
func set_rig(i: int) -> void:
	if rig_pending == i:
		rig_pending = -1
	if rig_lake == i:
		_save()
		return
	rig_lake = i
	_save()


## A win opened lake i: the pickup drives there the next time the map is on screen.
func set_rig_pending(i: int) -> void:
	rig_pending = i
	_save()


func chapter_done() -> bool:
	for i in lakes.size():
		if not lake_done(i):
			return false
	return true


func mark_chapter_seen() -> void:
	chapter_seen = true
	_save()


func lake_done(i: int) -> bool:
	return int(marks[i]) & MARK_ALL != 0


func set_setting(key: String, value: bool) -> void:
	match key:
		"sound": sound_on = value
		"music": music_on = value
		"vibration": vibration_on = value
	_save()
	Sfx.apply_settings()


func vibrate(ms: int) -> void:
	if vibration_on:
		Input.vibrate_handheld(ms)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	unlocked = clampi(int(cf.get_value("progress", "unlocked", 1)), 1, lakes.size())
	chapter_seen = bool(cf.get_value("progress", "chapter_seen", false))
	rig_lake = clampi(int(cf.get_value("progress", "rig", -1)), -1, lakes.size() - 1)
	rig_pending = clampi(int(cf.get_value("progress", "rig_pending", -1)), -1, lakes.size() - 1)
	var saved = cf.get_value("progress", "marks", [])
	if saved is Array:
		for i in mini(saved.size(), marks.size()):
			marks[i] = int(saved[i])
	sound_on = bool(cf.get_value("settings", "sound", true))
	music_on = bool(cf.get_value("settings", "music", true))
	vibration_on = bool(cf.get_value("settings", "vibration", true))
	for k in dev:
		dev[k] = bool(cf.get_value("dev", k, dev[k]))
	day_mult = clampf(float(cf.get_value("dev", "day_mult", 1.0)), 0.5, 2.0)
	day_fixed = clampi(int(cf.get_value("dev", "day_fixed", 0)), 0, 120)
	boat_tilt = clampf(float(cf.get_value("dev", "boat_tilt", 35.0)), 0.0, 60.0)
	var st = cf.get_value("stats", "lakes", [])
	if not st is Array:
		return
	for i in mini(st.size(), stats.size()):
		if st[i] is Dictionary:
			stats[i].merge(st[i], true)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "unlocked", unlocked)
	cf.set_value("progress", "chapter_seen", chapter_seen)
	cf.set_value("progress", "rig", rig_lake)
	cf.set_value("progress", "rig_pending", rig_pending)
	cf.set_value("progress", "marks", marks)
	cf.set_value("settings", "sound", sound_on)
	cf.set_value("settings", "music", music_on)
	cf.set_value("settings", "vibration", vibration_on)
	for k in dev:
		cf.set_value("dev", k, dev[k])
	cf.set_value("dev", "day_mult", day_mult)
	cf.set_value("dev", "day_fixed", day_fixed)
	cf.set_value("dev", "boat_tilt", boat_tilt)
	cf.set_value("stats", "lakes", stats)
	cf.save(SAVE_PATH)


# ---------------------------------------------------------------- look

func _build_theme() -> void:
	# Josefin Sans (fonts/, SIL Open Font License): one variable font, its weight set per use. Godot's
	# built-in font only if the file were ever missing.
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	var body := FontVariation.new()
	body.base_font = base
	body.variation_opentype = {wght: 600}
	body.spacing_glyph = 1
	title_font = FontVariation.new()
	title_font.base_font = base
	title_font.variation_opentype = {wght: 700}
	title_font.spacing_glyph = 14
	heading_font = FontVariation.new()
	heading_font.base_font = base
	heading_font.variation_opentype = {wght: 600}
	heading_font.spacing_glyph = 3
	ThemeDB.fallback_font = body  # every label, themed or not, uses it

	ui_theme = Theme.new()
	ui_theme.default_font = body
	ui_theme.default_font_size = 28

	var normal := _pill(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.28))
	var hover := _pill(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.40))
	var pressed := _pill(Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.55))
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed]]:
		ui_theme.set_stylebox(state[0], "Button", state[1])
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	ui_theme.set_stylebox("disabled", "Button", _pill(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10)))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		ui_theme.set_color(c, "Button", Color(1, 1, 1, 0.95))
	ui_theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	ui_theme.set_font_size("font_size", "Button", 28)

	ui_theme.set_color("font_color", "Label", Color(1, 1, 1, 0.94))
	ui_theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.32))
	ui_theme.set_constant("shadow_offset_x", "Label", 0)
	ui_theme.set_constant("shadow_offset_y", "Label", 2)
	ui_theme.set_constant("separation", "VBoxContainer", 18)


func _pill(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(40)
	s.content_margin_left = 36
	s.content_margin_right = 36
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.anti_aliasing = true
	return s


func _make_beam() -> ImageTexture:
	const W := 256
	const H := 128
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for x in W:
		var u := float(x) / (W - 1)
		var spread := 0.2 + 0.8 * u  # the beam widens as it goes
		var fall := pow(1.0 - u, 1.5) * smoothstep(0.0, 0.05, u)  # fades with distance
		for y in H:
			var v := absf((float(y) - (H - 1) * 0.5) / ((H - 1) * 0.5))
			var edge := 1.0 - smoothstep(0.45, 1.0, v / spread)  # soft edges
			var hot := exp(-pow((u - 0.08) / 0.09, 2.0) - pow(v / 0.18, 2.0)) * 0.55  # bright just ahead of the lamp
			var a := clampf(edge * fall + hot, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Draws a headlight beam from `from` pointing along `angle`, `length` long and `width` wide at its end.
func draw_beam(ci: CanvasItem, from: Vector2, angle: float, length: float, width: float, col: Color) -> void:
	ci.draw_set_transform(from, angle, Vector2(length / 256.0, width / 128.0))
	ci.draw_texture(beam_tex, Vector2(0, -64), col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.45, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18),
		Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## Icons from res://icons (white, tinted when drawn). Credits in icons/CREDITS.txt.
var _icons := {}
## Per-icon size correction so icons that fill their whole square don't look bigger than the others.
const ICON_OPTICAL := {"loop": 0.84}


func icon(kind: String) -> Texture2D:
	if not _icons.has(kind):
		_icons[kind] = load("res://icons/%s.svg" % kind)
	return _icons[kind]


## The battery icon showing how much charge is left (priorblue's set: empty, 25, 50, 75, full).
func battery_icon(charge: float) -> String:
	if charge <= 0.05:
		return "battery_0"
	if charge <= 0.3:
		return "battery_25"
	if charge <= 0.55:
		return "battery_50"
	if charge <= 0.8:
		return "battery_75"
	return "battery"


## Draws an icon centred on c, about s pixels across, tinted col.
func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var sz := s * 1.1 * float(ICON_OPTICAL.get(kind, 1.0))
	ci.draw_texture_rect(icon(kind), Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col)


## A solid square game button with a darker bottom edge that it presses down into, holding one white icon.
## Buttons smaller than 96 px get an invisible touch margin so they are about 48 dp to a finger.
func square_button(tex: Texture2D, side: float, icon_w: int) -> Button:
	var b: Button = HitButton.new()
	b.hit_pad = maxf(0.0, (96.0 - side) * 0.5)
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", icon_w)
	b.custom_minimum_size = Vector2(side, side)
	b.size = Vector2(side, side)
	var edge := maxi(4, int(side * 0.065))
	for st in [["normal", Color("1d3a44")], ["hover", Color("1d3a44")], ["pressed", Color("16303a")], ["hover_pressed", Color("16303a")]]:
		var down := String(st[0]).ends_with("pressed")
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.border_color = Color("0f242c")
		sb.border_width_bottom = 0 if down else edge
		sb.content_margin_top = edge if down else 0
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_bottom = 0
		sb.set_corner_radius_all(int(side * 0.17))
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Turns a settings button into an icon toggle: dimmed with a slash when off.
func style_toggle(b: Button, key: String, on: bool) -> void:
	b.text = ""
	b.icon = icon(key)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 34)
	b.custom_minimum_size.x = 96
	b.modulate.a = 1.0 if on else 0.5
	b.set_meta("off", not on)
	if not b.has_meta("slash"):
		b.set_meta("slash", true)
		b.draw.connect(func():
			if b.get_meta("off", false):
				var c := b.size * 0.5
				b.draw_line(c + Vector2(-20, 20), c + Vector2(20, -20), Color(1, 1, 1, 0.95), 3.0, true))
	b.queue_redraw()

