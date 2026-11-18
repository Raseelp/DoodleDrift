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

	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in 26:
		flies.append({"p": Vector2(rng.randf() * view_size.x, rng.randf() * view_size.y),
			"ph": rng.randf() * TAU, "v": Vector2(rng.randf_range(-6, 6), rng.randf_range(-8, -2))})

	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2.ZERO, Vector2(view_size.x, 0), view_size, Vector2(0, view_size.y)])
	var m := ShaderMaterial.new()
	m.shader = LandShader
	m.set_shader_parameter("base", Color("1d2a31"))
	m.set_shader_parameter("dark", Color("18232a"))
	bg.material = m
	add_child(bg)

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
	Sfx.start_ambience(0.84)


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

	var dev_btn := Button.new()
	dev_btn.text = "Dev"
	dev_btn.add_theme_font_size_override("font_size", 19)
	dev_btn.custom_minimum_size = Vector2(84, 54)
	dev_btn.position = Vector2(view_size.x - 108, top_inset + 22)
	dev_btn.modulate.a = 0.5
	dev_btn.pressed.connect(_open_dev)
	root.add_child(dev_btn)

	var title := Label.new()
	title.text = "WAKE"
	title.add_theme_font_override("font", Game.title_font)
	title.add_theme_font_size_override("font_size", 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top_inset + off.y * 0.5 + 70)
	title.size = Vector2(view_size.x, 110)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Chapter one  ·  The still lakes"
	sub.add_theme_font_size_override("font_size", 23)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.7
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
		l.modulate.a = 1.0 if Game.is_unlocked(i) else 0.35
		root.add_child(l)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.position = Vector2(0, view_size.y - 110 - off.y * 0.3)
	row.size = Vector2(view_size.x, 64)
	root.add_child(row)
	for key in ["sound", "music", "vibration"]:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(0, 62)
		_label_setting(b, key)
		b.pressed.connect(func():
			Game.set_setting(key, not _setting(key))
			_label_setting(b, key)
			Sfx.tap())
		row.add_child(b)

	var credit := Label.new()
	credit.text = "Icons by Lorc and Delapouite, game-icons.net (CC BY 3.0)"
	credit.add_theme_font_size_override("font_size", 15)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.modulate.a = 0.35
	credit.position = Vector2(0, row.position.y + 70)
	credit.size = Vector2(view_size.x, 24)
	root.add_child(credit)


func _process(delta: float) -> void:
	clock += delta
	for f in flies:
		var p: Vector2 = f["p"] + (f["v"] + Vector2(sin(clock * 0.6 + f["ph"]) * 10.0, 0.0)) * delta
		if p.y < -20.0:
			p.y = view_size.y + 20.0
		p.x = wrapf(p.x, -20.0, view_size.x + 20.0)
		f["p"] = p
	draw_node.queue_redraw()
	glow_node.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if dev_panel != null or card != null:
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if card != null:
			_close_card()
		elif dev_panel != null:
			reload_requested.emit()
		else:
			get_tree().quit()


## The lake card: its shape, name and the three goals with what each one asks.
func _open_card(i: int) -> void:
	var lake: Dictionary = Game.lakes[i]
	var pal: Dictionary = lake["pal"]
	var light: Color = pal["light"]
	var m := int(Game.marks[i])
	var total: int = lake["lanterns"].size()
	var par := int(lake["par"])
	card = Control.new()
	card.size = view_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(card)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.72)
	dim.size = view_size
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and not e.pressed:
			_close_card())
	card.add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("16222a")
	sb.border_color = Color(light, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(28)
	sb.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(minf(620.0, view_size.x - 48.0), 0)
	card.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var th: Dictionary = thumbs[i]
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(0, 250)
	pic.draw.connect(func():
		var sc := 0.2
		var o := Vector2(pic.size.x * 0.5, 125) - LAKE_CENTER * sc
		pic.draw_set_transform(o, 0.0, Vector2(sc, sc))
		for p in th["sand"]:
			pic.draw_colored_polygon(p, pal["sand"])
		pic.draw_colored_polygon(th["water"], pal["shallow"])
		for p in th["mid"]:
			pic.draw_colored_polygon(p, pal["mid"])
		for p in th["deep"]:
			pic.draw_colored_polygon(p, pal["deep"])
		for l in lake["lanterns"]:
			pic.draw_circle(Vector2(l[0], l[1]), 16.0, light if m & Game.MARK_ALL else light.darkened(0.45)))
	box.add_child(pic)
	var name_l := Label.new()
	name_l.text = String(lake["name"])
	name_l.add_theme_font_override("font", Game.heading_font)
	name_l.add_theme_font_size_override("font_size", 40)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)
	var goals := [["lantern", "Light all %d lanterns" % total, Game.MARK_ALL],
		["sun", "Finish before the sun is low", Game.MARK_TIME],
		["loop", "Use %d loop%s or fewer" % [par, "" if par == 1 else "s"], Game.MARK_LOOPS]]
	for g in goals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var on: bool = m & int(g[2]) != 0
		var kind: String = g[0]
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(56, 56)
		ic.draw.connect(func():
			if on:
				ic.draw_texture_rect(Game.glow_tex, Rect2(Vector2(-16, -16), Vector2(88, 88)), false, Color(light, 0.45))
			Game.draw_icon(ic, kind, Vector2(28, 28), 40, light if on else Color(1, 1, 1, 0.4)))
		row.add_child(ic)
		var l := Label.new()
		l.text = String(g[1])
		l.custom_minimum_size = Vector2(minf(440.0, view_size.x - 200.0), 0)
		l.add_theme_font_size_override("font_size", 25)
		l.modulate.a = 1.0 if on else 0.75
		row.add_child(l)
		box.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	for spec in [["Close", _close_card], ["Play", func(): lake_chosen.emit(i)]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.custom_minimum_size = Vector2(200, 72)
		b.add_theme_font_size_override("font_size", 27)
		var fn: Callable = spec[1]
		b.pressed.connect(func():
			Sfx.tap()
			fn.call())
		buttons.add_child(b)
	panel.reset_size()
	card.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.position = ((view_size - panel.size) * 0.5).floor()
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.2)


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
			n.draw_circle(p, 2.2, Color(1, 1, 1, 0.16))
			acc += 15.0
		acc -= seg

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

		# Marks under the name.
		var left_side := spot.x < 360.0 + off.x
		var m := int(Game.marks[i])
		for k in 3:
			var x := spot.x + 104 + k * 24 if left_side else spot.x - 104 - (2 - k) * 24
			var dp := Vector2(x, spot.y + 26)
			if m & (1 << k):
				n.draw_circle(dp, 7.0, pal["light"])
			else:
				n.draw_arc(dp, 6.0, 0.0, TAU, 20, Color(1, 1, 1, 0.35 * alpha), 2.0, true)

	# The boat waits by the current lake.
	var cs: Vector2 = SPOTS[current] + off
	var side := 1.0 if cs.x < 360.0 + off.x else -1.0
	var bp := cs + Vector2(side * 66.0, 62.0 + sin(clock * 1.7) * 3.0)
	n.draw_set_transform(bp, -PI / 2 + sin(clock * 0.8) * 0.15, Vector2(1.1, 1.1))
	n.draw_colored_polygon(PackedVector2Array(HULL), Color("efe6d6"))
	n.draw_rect(Rect2(-9, -4.5, 11, 9), Color("c9bca5"))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glow(n: Node2D) -> void:
	var glow: Texture2D = Game.glow_tex
	for i in Game.lake_count():
		if not Game.lake_done(i):
			continue
		var spot: Vector2 = SPOTS[i] + off
		var c: Color = Game.lakes[i]["pal"]["light"]
		var r := 80.0
		n.draw_texture_rect(glow, Rect2(spot - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c, 0.22))
	for f in flies:
		var tw := 0.5 + 0.5 * sin(clock * 2.0 + float(f["ph"]) * 3.0)
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


func _setting(key: String) -> bool:
	match key:
		"sound": return Game.sound_on
		"music": return Game.music_on
	return Game.vibration_on


func _label_setting(b: Button, key: String) -> void:
	Game.style_toggle(b, key, _setting(key))
