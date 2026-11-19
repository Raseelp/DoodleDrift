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
var marks: Array = []
var stats: Array = []  # per lake: tries, wins, fails, crashes, revives, best, last fails
var sound_on := true
var music_on := true
var vibration_on := true
var dev := {"chains": true, "life": true, "fading": false,
	"crash": true, "boost": true, "unlock_all": false, "boat3d": true}
## Daylight tuning from the Dev panel: a multiplier on the automatic time, or a fixed time (0 = automatic).
var day_mult := 1.0
var day_fixed := 0
var boat_tilt := 35.0  # Dev: camera tilt of the 3D boat in degrees (0 = straight down)

var ui_theme: Theme
var title_font: FontVariation
var heading_font: FontVariation
var glow_tex: GradientTexture2D

var _water_cache := {}
const HitButton = preload("res://scripts/hit_button.gd")
## The 3D boat model, loaded once in the background at start-up and kept, so starting a lake
## doesn't stop to load it again.
const BOAT_MODEL := "res://models/fishing_boat.glb"
var _boat_scene: PackedScene


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(BOAT_MODEL):
		ResourceLoader.load_threaded_request(BOAT_MODEL)
	_build_lakes()
	marks.resize(lakes.size())
	marks.fill(0)
	for i in lakes.size():
		stats.append(_new_stat())
	_load()
	_build_theme()
	glow_tex = _make_glow()


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
			"par": 1, "pitch": 1.0, "motes": "petals",
			"pal": _pal({
				"land": "7d9a72", "land_dark": "6c8964", "tree": "56755a", "tree_hi": "86a67c",
				"shadow": "3f5a48", "sand": "e3d3b0", "shallow": "86b8b2", "mid": "5f9ba3",
				"deep": "46808f", "rock": "8c8f8a", "rock_hi": "b1b4ac", "reed": "aab66f",
				"light": "ffd08a", "pair": "a5ece0", "night": "a08cbc", "mote": "f4bccb",
				"wood": "9a7b58",
			}),
			"water": [[90, 420], [200, 230], [380, 190], [560, 250], [650, 430], [660, 700],
				[620, 960], [520, 1140], [340, 1200], [170, 1130], [80, 920], [60, 650]],
			"lanterns": [[330, 600, 0], [430, 690, 0], [320, 790, 0]],
			"rocks": [], "reeds": [],
			"start": [360, 1095, -PI / 2], "jetty": [362, 1215, 362, 1130],
		},
		{
			"name": "Two Coves",
			"hint": "",
			"par": 2, "pitch": 1.1225, "motes": "petals",
			"pal": _pal({
				"land": "93ab6c", "land_dark": "829a5e", "tree": "66824c", "tree_hi": "a0bb7b",
				"shadow": "4b6440", "sand": "ecdcb0", "shallow": "8cc5b8", "mid": "63a9a8",
				"deep": "448992", "rock": "8d8a80", "rock_hi": "b4b0a4", "reed": "b2bd6a",
				"light": "ffd77a", "pair": "a5ece0", "night": "a691b6", "mote": "f6e6a6",
				"wood": "a07e56",
			}),
			"water": [[110, 300], [260, 190], [470, 195], [620, 300], [630, 470], [520, 610],
				[600, 760], [640, 950], [560, 1140], [360, 1210], [170, 1150], [80, 960],
				[130, 780], [210, 630], [90, 470]],
			"lanterns": [[300, 380, 0], [440, 455, 0], [290, 905, 0], [445, 965, 0]],
			"rocks": [], "reeds": [],
			"start": [365, 650, -PI / 2], "jetty": [],
		},
		{
			"name": "Stones",
			"hint": "Stones block the boat.\nSteer around them.",
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
			"start": [300, 1150, -PI / 2], "jetty": [292, 1224, 296, 1182],
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
			"start": [390, 1150, -PI * 0.6], "jetty": [384, 1240, 388, 1184],
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
			"start": [330, 780, PI], "jetty": [],
		},
	]


## The boat model (waits for the background load the first time), or null if the file is missing.
func boat_scene() -> PackedScene:
	if _boat_scene == null and ResourceLoader.exists(BOAT_MODEL):
		_boat_scene = ResourceLoader.load_threaded_get(BOAT_MODEL) as PackedScene
	return _boat_scene


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
	return {"tries": 0, "wins": 0, "fails": 0, "crashes": 0, "revives": 0, "best": 0.0, "last_fails": []}


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
	marks.fill(0)
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
	var base := ThemeDB.fallback_font
	var body := FontVariation.new()
	body.base_font = base
	body.spacing_glyph = 1
	title_font = FontVariation.new()
	title_font.base_font = base
	title_font.spacing_glyph = 14
	heading_font = FontVariation.new()
	heading_font.base_font = base
	heading_font.spacing_glyph = 3

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

