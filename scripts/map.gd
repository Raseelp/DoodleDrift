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
var card: Control
var settings: Control
var celebrating := false
var rings: Array = []  # gold ripples spreading from lakes during the chapter-complete moment

# Time of day on the map follows the chapter: bright morning with no lake lit, golden afternoon,
# dusk near the end, and night once every lake is bright (so the lanterns shine). 0 = morning, 1 = night.
const DAY_STOPS := [
	{"t": 0.0, "base": "a4c47a", "dark": "93b56c", "ink": "1f3324", "tint": "ffffff"},
	{"t": 0.25, "base": "9dbd70", "dark": "8aab61", "ink": "1f3324", "tint": "fff8ec"},
	{"t": 0.5, "base": "bba465", "dark": "a68f55", "ink": "2e2416", "tint": "ffe9cc"},
	{"t": 0.75, "base": "6f6a5c", "dark": "5f5a50", "ink": "f4efe6", "tint": "d9c9d6"},
	{"t": 1.0, "base": "23313a", "dark": "1c2830", "ink": "f1f3f2", "tint": "b8bfd8"},
]
var day_t := 0.0  # 0 morning .. 1 night
var ink := Color.WHITE  # text colour that reads on today's ground
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

	var done := 0
	for i in Game.lake_count():
		if Game.lake_done(i):
			done += 1
	day_t = clampf(float(done) / Game.lake_count(), 0.0, 1.0) if not has_meta("day_t") else float(get_meta("day_t"))
	var stop := _day_stop(day_t)
	ink = Color("1f3324") if day_t < 0.62 else Color("f1f3f2")

	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in 26:
		flies.append({"p": Vector2(rng.randf() * view_size.x, rng.randf() * view_size.y),
			"ph": rng.randf() * TAU, "v": Vector2(rng.randf_range(-6, 6), rng.randf_range(-8, -2))})

	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2.ZERO, Vector2(view_size.x, 0), view_size, Vector2(0, view_size.y)])
	var m := ShaderMaterial.new()
	m.shader = LandShader
	m.set_shader_parameter("base", stop["base"])
	m.set_shader_parameter("dark", stop["dark"])
	bg.material = m
	add_child(bg)
	var tint := CanvasModulate.new()
	tint.color = stop["tint"]
	add_child(tint)

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

	_build_ui()
	Sfx.start_ambience(0.84, false)
	Sfx.set_mood(day_t, 0.0, false)
	if Game.chapter_done() and not Game.chapter_seen:
		_celebrate.call_deferred()


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

	# Settings, top right: sound, music, vibration, credits and the developer options live there.
	var gear := Game.square_button(Game.icon("settings"), 64, 30)
	gear.position = Vector2(view_size.x - 32 - 64, top_inset + 24)
	gear.pressed.connect(func():
		Sfx.tap()
		_open_settings())
	root.add_child(gear)
	gear.reset_size()

	var title := Label.new()
	title.text = "WAKE"
	title.add_theme_font_override("font", Game.title_font)
	title.add_theme_font_size_override("font_size", 84)
	map_labels.append(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top_inset + off.y * 0.5 + 70)
	title.size = Vector2(view_size.x, 110)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Chapter one  ·  The still lakes"
	sub.add_theme_font_size_override("font_size", 23)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.75
	map_labels.append(sub)
	sub.position = Vector2(0, top_inset + off.y * 0.5 + 180)
	sub.size = Vector2(view_size.x, 40)
	root.add_child(sub)

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
		root.add_child(l)
	# Labels take the day's ink colour; in daylight the dark drop shadow becomes a faint light one.
	for lb in map_labels:
		lb.add_theme_color_override("font_color", ink)
		if day_t < 0.62:
			lb.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.22))


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
	draw_node.queue_redraw()
	glow_node.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if dev_panel != null or card != null or settings != null or celebrating:
		return
	if event is InputEventScreenTouch and event.pressed:
		var best := -1
		var best_d := 120.0
		for i in Game.lake_count():
			var d: float = event.position.distance_to(SPOTS[i] + off)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			if Game.is_unlocked(best):
				Sfx.tap()
				_open_card(best)
			else:
				Sfx.reject()
				_toast("Light every lantern on %s to open it" % Game.lakes[best - 1]["name"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if card != null:
			_close_card()
		elif settings != null:
			_close_settings()
		elif dev_panel != null:
			reload_requested.emit()
		else:
			get_tree().quit()


## The lake card: same size as before, polished. The lake picture is the button: tap it to set off.
## All spacing is on an 8 px grid (padding 40 at the sides and bottom, 32 at the top), and every row is centred.
const CARD_PAD_X := 40.0
const CARD_PAD_TOP := 32.0
const CARD_PAD_BOTTOM := 40.0 + 10.0  # 40 px of space above the card's 10 px base edge
const ART_H := 264.0
const GOAL_H := 128.0


func _open_card(i: int) -> void:
	var lake: Dictionary = Game.lakes[i]
	var pal: Dictionary = lake["pal"]
	var light: Color = pal["light"]
	var m := int(Game.marks[i])
	var total: int = lake["lanterns"].size()
	var par := int(lake["par"])
	var card_w := minf(620.0, view_size.x - 48.0)
	var inner_w := card_w - CARD_PAD_X * 2.0

	card = Control.new()
	card.size = view_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(card)
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.047, 0.063, 0.66)
	dim.size = view_size
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed:
			_close_card())
	card.add_child(dim)

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
	card.add_child(panel)

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

	# Header: lake number left, close right, both centred on one 64 px row.
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(inner_w, 64)
	col.add_child(head)
	var kick := Label.new()
	kick.text = "LAKE %d" % (i + 1)
	kick.add_theme_font_override("font", Game.heading_font)
	kick.add_theme_font_size_override("font_size", 22)
	kick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kick.size_flags_vertical = Control.SIZE_FILL
	kick.modulate.a = 0.55
	head.add_child(kick)
	var close := Game.square_button(Game.icon("close"), 64, 26)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		Sfx.tap()
		_close_card())
	head.add_child(close)
	gap.call(8)

	# The lake itself is the button. A ripple spreads from it and the boat waits at its start.
	var th: Dictionary = thumbs[i]
	var art := Control.new()
	art.custom_minimum_size = Vector2(inner_w, ART_H)
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	art.set_meta("k", 0.0)
	art.set_meta("bob", 0.0)
	var sc := 0.2
	art.draw.connect(func():
		var mid := Vector2(inner_w * 0.5, ART_H * 0.5)
		var k: float = art.get_meta("k")
		art.draw_arc(mid, 112.0 * (0.75 + 0.5 * k), 0.0, TAU, 64, Color(light, 0.5 * (1.0 - k)), 3.0, true)
		art.draw_set_transform(mid - LAKE_CENTER * sc, 0.0, Vector2(sc, sc))
		for p in th["sand"]:
			art.draw_colored_polygon(p, pal["sand"])
		art.draw_colored_polygon(th["water"], pal["shallow"])
		for p in th["mid"]:
			art.draw_colored_polygon(p, pal["mid"])
		for p in th["deep"]:
			art.draw_colored_polygon(p, pal["deep"])
		for l in lake["lanterns"]:
			art.draw_circle(Vector2(l[0], l[1]), 22.0, light if m & Game.MARK_ALL else light.darkened(0.45), true, -1.0, true)
		var st: Array = lake["start"]
		var bob: float = art.get_meta("bob")
		art.draw_set_transform(mid + (Vector2(st[0], st[1]) - LAKE_CENTER) * sc + Vector2(0, bob), float(st[2]), Vector2(1.1, 1.1))
		art.draw_colored_polygon(PackedVector2Array(HULL), Color("efe6d6"))
		art.draw_rect(Rect2(-9, -4.5, 11, 9), Color("c9bca5"))
		art.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	art.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed:
			_set_off(i))
	col.add_child(art)
	var ripple := art.create_tween().set_loops()
	ripple.tween_method(func(v: float):
		art.set_meta("k", v)
		art.set_meta("bob", sin(v * TAU) * 2.0)
		art.queue_redraw(), 0.0, 1.0, 2.6)
	gap.call(24)

	var name_l := Label.new()
	name_l.text = String(lake["name"]).to_upper()
	name_l.add_theme_font_override("font", Game.title_font)
	name_l.add_theme_font_size_override("font_size", 40)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.custom_minimum_size = Vector2(inner_w, 56)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(name_l)
	gap.call(32)

	# Goals: three equal cells between thin rules, icon over label, earned in the lake's light colour.
	var goals := [["lantern", "All %d lanterns" % total, Game.MARK_ALL],
		["sun", "Before dusk", Game.MARK_TIME],
		["loop", "Max %d loop%s" % [par, "" if par == 1 else "s"], Game.MARK_LOOPS]]
	var rule := Color(1, 1, 1, 0.08)
	var grid := Control.new()
	grid.custom_minimum_size = Vector2(inner_w, GOAL_H)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(func():
		grid.draw_line(Vector2(0, 1), Vector2(inner_w, 1), rule, 2.0)
		grid.draw_line(Vector2(0, GOAL_H - 1), Vector2(inner_w, GOAL_H - 1), rule, 2.0)
		for k in [1, 2]:
			var x := roundf(inner_w * k / 3.0)
			grid.draw_line(Vector2(x, 24), Vector2(x, GOAL_H - 24), rule, 2.0))
	col.add_child(grid)
	for k in 3:
		var on: bool = m & int(goals[k][2]) != 0
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.position = Vector2(inner_w * k / 3.0, 0)
		cell.size = Vector2(inner_w / 3.0, GOAL_H)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)
		var kind: String = goals[k][0]
		var ic := TextureRect.new()
		ic.texture = Game.icon(kind)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var isz := 48.0 * float(Game.ICON_OPTICAL.get(kind, 1.0))
		ic.custom_minimum_size = Vector2(48, 48)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.modulate = light if on else Color(1, 1, 1, 0.24)
		ic.scale = Vector2.ONE * (isz / 48.0)
		ic.pivot_offset = Vector2(24, 24)
		cell.add_child(ic)
		var gl := Label.new()
		gl.text = String(goals[k][1])
		gl.add_theme_font_size_override("font_size", 20)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.modulate.a = 0.8 if on else 0.45
		cell.add_child(gl)
	gap.call(24)

	var best := float(Game.stats[i]["best"])
	var facts := Label.new()
	facts.text = ("Best  %d s      Daylight  %d s" % [roundi(best), int(Game.lake_duration(i))]) if best > 0.0 else "Daylight  %d s" % int(Game.lake_duration(i))
	facts.add_theme_font_size_override("font_size", 24)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	facts.custom_minimum_size = Vector2(inner_w, 40)
	facts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	facts.modulate.a = 0.7
	col.add_child(facts)
	gap.call(24)

	var hint := Label.new()
	hint.text = "TAP THE LAKE TO SET OFF"
	hint.add_theme_font_override("font", Game.heading_font)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", light)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(inner_w, 32)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(hint)

	col.reset_size()
	var card_h := CARD_PAD_TOP + col.get_combined_minimum_size().y + CARD_PAD_BOTTOM
	panel.size = Vector2(card_w, card_h)
	panel.position = ((view_size - panel.size) * 0.5).floor()
	card.modulate.a = 0.0
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.2)


## Tapping the lake: a short press on the picture, then the lake starts.
func _set_off(i: int) -> void:
	if card == null or card.has_meta("leaving"):
		return
	card.set_meta("leaving", true)
	Sfx.tap()
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): lake_chosen.emit(i))


func _close_card() -> void:
	if card != null:
		card.queue_free()
		card = null


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
	# Dotted path between the lakes.
	var acc := 0.0
	for i in range(1, path_pts.size()):
		var a := path_pts[i - 1]
		var b := path_pts[i]
		var seg := a.distance_to(b)
		while acc < seg:
			var p := a.lerp(b, acc / seg)
			n.draw_circle(p, 2.4, Color(ink, 0.28))
			acc += 15.0
		acc -= seg

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
		var open := Game.is_unlocked(i)
		var alpha := 1.0 if open else 0.3
		var spot: Vector2 = SPOTS[i] + off
		var origin := spot - LAKE_CENTER * THUMB
		var bob := sin(clock * 0.9 + i) * 2.0
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
		var done := Game.lake_done(i)
		for l in lake["lanterns"]:
			var c := Color(pal["light"], alpha) if done else Color(pal["light"].darkened(0.45), alpha)
			n.draw_circle(Vector2(l[0], l[1]), 34.0, c)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Goals under the name, as the same icons used everywhere else. Each sits on a small dark disc,
		# like the lock, so it reads on every ground from morning green to night: earned ones in the
		# lake's light, the rest a dim white.
		var left_side := spot.x < 360.0 + off.x
		var m := int(Game.marks[i])
		for k in 3:
			var x := spot.x + 108 + k * 38 if left_side else spot.x - 108 - (2 - k) * 38
			var gp := Vector2(x, spot.y + 26)
			var kind: String = ["lantern", "sun", "loop"][k]
			var on := m & (1 << k) != 0
			n.draw_circle(gp, 17.0, Color(0.03, 0.06, 0.08, (0.62 if on else 0.42) * (1.0 if open else 0.6)), true, -1.0, true)
			Game.draw_icon(n, kind, gp, 24, Color(pal["light"]) if on else Color(1, 1, 1, 0.5 if open else 0.3))
		if not open:
			n.draw_circle(spot, 30.0, Color(0.03, 0.06, 0.08, 0.75), true, -1.0, true)
			Game.draw_icon(n, "lock", spot, 30, Color(1, 1, 1, 0.85))

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

	# Chapter-complete ripples.
	for r in rings:
		var rk := (clock - float(r["t"])) / 1.2
		if rk >= 0.0 and rk <= 1.0:
			n.draw_arc(r["p"], 40.0 + rk * 90.0, 0.0, TAU, 48, Color(r["c"], 0.9 * (1.0 - rk)), 4.0, true)

	# The boat waits by the current lake.
	var cs: Vector2 = SPOTS[current] + off
	var side := 1.0 if cs.x < 360.0 + off.x else -1.0
	var bp := cs + Vector2(side * 66.0, 62.0 + sin(clock * 1.7) * 3.0)
	n.draw_set_transform(bp, -PI / 2 + sin(clock * 0.8) * 0.15, Vector2(1.1, 1.1))
	n.draw_colored_polygon(PackedVector2Array(HULL), Color("efe6d6"))
	n.draw_rect(Rect2(-9, -4.5, 11, 9), Color("c9bca5"))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wings(n: Node2D, flap: float, col: Color) -> void:
	var w := 4.0 + 6.0 * flap
	for side in [-1.0, 1.0]:
		n.draw_colored_polygon(PackedVector2Array([Vector2(0, -2), Vector2(side * w, -7), Vector2(side * w * 0.9, 1), Vector2(0, 2)]), col)
		n.draw_colored_polygon(PackedVector2Array([Vector2(0, 1), Vector2(side * w * 0.7, 3), Vector2(side * w * 0.5, 7), Vector2(0, 4)]), col)


func _draw_glow(n: Node2D) -> void:
	var glow: Texture2D = Game.glow_tex
	# The sun: high in the top right in the morning, sinking toward the right edge and warming to
	# orange through the afternoon, gone at night.
	var sun_a := 1.0 - smoothstep(0.7, 0.95, day_t)
	if sun_a > 0.0:
		var sp := Vector2(view_size.x * lerpf(0.88, 1.06, day_t), lerpf(-40.0, view_size.y * 0.55, smoothstep(0.0, 0.9, day_t)))
		var sc := Color("fff4d6").lerp(Color("ffa860"), smoothstep(0.2, 0.75, day_t))
		for k in 3:
			var r: float = [620.0, 300.0, 120.0][k]
			n.draw_texture_rect(glow, Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(sc, float([0.28, 0.32, 0.55][k]) * sun_a))
	for i in Game.lake_count():
		if not Game.lake_done(i):
			continue
		var spot: Vector2 = SPOTS[i] + off
		var c: Color = Game.lakes[i]["pal"]["light"]
		var r := 80.0
		n.draw_texture_rect(glow, Rect2(spot - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c, 0.22))
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


## Settings: the same card as the lake card. Sound, music and vibration; credits; the developer options.
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
	credits.text = "Boat: \"Fishing Boat\" by CharlieCatling, Sketchfab\nIcons by Lorc and Delapouite, game-icons.net (CC BY 3.0)\nPause, play and restart icons: Phosphor Icons (MIT)\nMade with the Godot Engine"
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


## Chapter complete, shown once: each lake sends out a gold ripple with a stamp and a rising chime,
## then "THE STILL LAKES ARE BRIGHT AGAIN" over the map. Tap to carry on.
func _celebrate() -> void:
	celebrating = true
	var notes := [1.0, 1.125, 1.25, 1.5, 1.6667]
	var tw := create_tween()
	tw.tween_interval(0.6)
	for i in Game.lake_count():
		var lp: Dictionary = Game.lakes[i]["pal"]
		tw.tween_callback(func():
			rings.append({"p": SPOTS[i] + off, "t": clock, "c": lp["light"]})
			Sfx.stamp(true)
			Sfx.chime(0.84 * 2.0 * float(notes[i]))
			Game.vibrate(18))
		tw.tween_interval(0.45)
	tw.tween_callback(func():
		Sfx.chord(0.84 * 2.0)
		_show_chapter_card())


func _show_chapter_card() -> void:
	var c := Control.new()
	c.size = view_size
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(c)
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.047, 0.063, 0.9)
	dim.size = view_size
	c.add_child(dim)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.size = view_size
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(col)
	var kick := Label.new()
	kick.text = "CHAPTER ONE COMPLETE"
	kick.add_theme_font_override("font", Game.heading_font)
	kick.add_theme_font_size_override("font_size", 24)
	kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kick.modulate.a = 0.6
	col.add_child(kick)
	var title := Label.new()
	title.text = "THE STILL LAKES\nARE BRIGHT AGAIN"
	title.add_theme_font_override("font", Game.title_font)
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var lights := HBoxContainer.new()
	lights.alignment = BoxContainer.ALIGNMENT_CENTER
	lights.add_theme_constant_override("separation", 20)
	lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lights)
	for i in Game.lake_count():
		var ic := TextureRect.new()
		ic.texture = Game.icon("lantern")
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(52, 52)
		ic.modulate = Game.lakes[i]["pal"]["light"]
		lights.add_child(ic)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	col.add_child(spacer)
	var tap := Label.new()
	tap.text = "TAP TO CONTINUE"
	tap.add_theme_font_override("font", Game.title_font)
	tap.add_theme_font_size_override("font_size", 24)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.modulate.a = 0.0
	col.add_child(tap)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.6)
	tw.tween_interval(1.0)
	tw.tween_property(tap, "modulate:a", 0.8, 0.4)
	tw.tween_callback(func():
		dim.gui_input.connect(func(e: InputEvent):
			if e is InputEventScreenTouch and not e.pressed:
				Sfx.tap()
				Game.mark_chapter_seen()
				celebrating = false
				var out := c.create_tween()
				out.tween_property(c, "modulate:a", 0.0, 0.3)
				out.tween_callback(c.queue_free)))


func _setting(key: String) -> bool:
	match key:
		"sound": return Game.sound_on
		"music": return Game.music_on
	return Game.vibration_on
