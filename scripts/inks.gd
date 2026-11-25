extends Node2D
## Phase 4: what the pens mean. The road runs in chapters that change at page edges; each chapter is drawn
## with one pen that brings a rule:
##   plain   - pencil: crossing the line just slows you (as always)
##   red     - red ballpoint edges: go fully past one and the run is over
##   marked  - highlighter swipes on the outside of corners pay double; blue pen dots on the inside apex
##             are clipping points
## In any chapter: crayon coloured in over bits of the page (waxy: less grip) and spilled ink (harmless:
## a slide, and your skids come out in that ink for a while). The first time each appears, a handwritten
## note rides along beside the road and explains it, then fades. Everything is drawn as hand strokes.

const DrawNode = preload("res://scripts/draw_node.gd")
const SAVE := "user://drift.cfg"
## Switched off for now (the page felt crowded); the code stays so they can come back.
const USE_HIGHLIGHT := false
const USE_WAX := false
const USE_PUDDLES := false
const STEP := 8.0
const RED := Color(0.74, 0.1, 0.12, 0.92)
const CRAYONS := [Color(0.93, 0.36, 0.2), Color(0.3, 0.62, 0.92), Color(0.98, 0.78, 0.18), Color(0.45, 0.78, 0.35), Color(0.82, 0.42, 0.85)]
const INKS := [Color(0.08, 0.12, 0.42), Color(0.06, 0.06, 0.08), Color(0.05, 0.25, 0.2)]
const TEACH := {
	"red": ["red pen = wall.\ngo fully over it and you're done.\nnot joking. (a bit joking.)", "red lines now.\ncross one completely: game over.\ndon't make me use the red pen on you"],
	"marked": ["cones on the inside of corners:
get close to them while sideways.", "see the cones?
clip them sideways. extra points."],
	"wax": ["crayon is slippery.\nyou'll slide further. enjoy it.", "someone coloured in here.\nwax. no grip. very fun."],
	"puddle": ["spilled ink. harmless.\nyou'll just slide, and paint the page.", "ink puddle. go through it.\nyour tyres will remember."],
}

var g: Node
var layer: Node2D  # on the page, over the road ink
var gloss: Node2D  # puddle shine, redrawn as the camera moves
var guide_node: Node2D  # the travelling note
var chapters: Array = [[-INF, "plain"]]  # [start len, kind], in order
var zones: Array = []  # highlighter: {a, b (len), side, node}
var dots: Array = []  # {p, len, hit}
var waxes: Array = []  # {poly, len}
var puddles: Array = []  # {p, r, col, poly, len, node, track}
var marks: Array = []  # red X where a run went out
var taught := {}
var guide := {}  # {text, t, side}
var wet_t := -9.0
var wet_col := Color.BLACK
var next_wax := 900.0
var next_puddle := 1400.0
var dots_node: Node2D


func setup(game: Node, p_layer: Node2D) -> void:
	g = game
	layer = p_layer
	dots_node = DrawNode.new()
	dots_node.draw_fn = _draw_dots
	layer.add_child(dots_node)
	gloss = DrawNode.new()
	gloss.draw_fn = _draw_gloss
	layer.add_child(gloss)
	guide_node = DrawNode.new()
	guide_node.draw_fn = _draw_guide
	guide_node.z_index = 5
	g.world.add_child(guide_node)
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	var t = cfg.get_value("notes", "taught", {})
	taught = t if t is Dictionary else {}


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	cfg.set_value("notes", "taught", taught)
	cfg.save(SAVE)


# ---------------------------------------------------------------- chapters

## A new page has started at road length `at`: pick its pen (a saved deck, so the order never feels set).
func new_page(at: float) -> void:
	var kind: String = g.scrib._cycle("chapter", ["plain", "red", "marked", "plain"])
	if kind == chapters[chapters.size() - 1][1]:
		return
	chapters.append([at, kind])
	if kind != "plain":
		_teach(kind, at)


func kind_at(l: float) -> String:
	var k: String = "plain"
	for c in chapters:
		if l >= float(c[0]):
			k = c[1]
		else:
			break
	return k


## Red ink for the road edges in a red chapter (the chunk asks before drawing).
func edge_ink(l: float) -> Array:
	if kind_at(l) == "red":
		return ["ballpoint", RED, 3.3, 0.25, 0.0]
	return []


## Called after each piece of road: highlighter and dots for corners in a marked chapter, now and then a
## crayon patch or an ink spill.
func on_block(from: int, new_corners: Array) -> void:
	var L: float = g.lens[g.lens.size() - 1]
	for c in new_corners:
		if kind_at(float(c["len"])) == "marked":
			if USE_HIGHLIGHT:
				_highlight(c)
			_dot(c)
	if USE_WAX and L >= next_wax:
		next_wax = L + g.rng.randf_range(1400.0, 2600.0)
		_wax(from)
	if USE_PUDDLES and L >= next_puddle:
		next_puddle = L + g.rng.randf_range(2200.0, 3800.0)
		_puddle(from)


func prune(behind: float) -> void:
	for arr in [zones, puddles]:
		for it in arr.filter(func(x): return float(x["len"]) < behind - 400.0):
			if it.has("node") and is_instance_valid(it["node"]):
				(it["node"] as Node).queue_free()
	zones = zones.filter(func(x): return float(x["len"]) >= behind - 400.0)
	puddles = puddles.filter(func(x): return float(x["len"]) >= behind - 400.0)
	dots = dots.filter(func(x): return float(x["len"]) >= behind - 400.0)
	var keep: Array = []
	for w in waxes:
		if float(w["len"]) >= behind - 400.0:
			keep.append(w)
		elif is_instance_valid(w["node"]):
			(w["node"] as Node).queue_free()
	waxes = keep
	while chapters.size() > 2 and float(chapters[1][0]) < behind - 3000.0:
		chapters.remove_at(0)
	dots_node.queue_redraw()


# ---------------------------------------------------------------- rules (asked by the game)

func red_here(l: float) -> bool:
	return kind_at(l) == "red"


## Grip multiplier where the car is: waxy crayon, or tyres still wet from an ink puddle.
func grip_mul(p: Vector2) -> float:
	var m := 1.0
	for w in waxes:
		if Geometry2D.is_point_in_polygon(p, w["poly"]):
			m = 0.55
			break
	for pd in puddles:
		if p.distance_to(pd["p"]) < float(pd["r"]):
			wet_t = g.clock
			wet_col = pd["col"]
			var tr: PackedVector2Array = pd["track"]
			if tr.is_empty() or tr[tr.size() - 1].distance_to(p) > 6.0:
				tr.append(p)
				pd["track"] = tr
				(pd["node"] as Node2D).queue_redraw()
	if g.clock - wet_t < 0.6:
		m = minf(m, 0.4)
	return m


## Skids come out in ink for a few seconds after a puddle.
func skid_col() -> Color:
	if g.clock - wet_t < 3.0:
		return Color(wet_col, 0.55)
	return Color(0.09, 0.09, 0.11, 0.72)  # dark graphite, close to rubber black


## Points multiplier for drifting at road point i with the car at `p` (x2 inside a highlighter swipe).
func score_mul(l: float, p: Vector2) -> float:
	for z in zones:
		if l >= float(z["a"]) and l <= float(z["b"]):
			var poly: PackedVector2Array = z["poly"]
			if Geometry2D.is_point_in_polygon(p, poly):
				return 2.0
	return 1.0


## A blue dot clipped while sideways: returns how many were clipped just now.
func clip(p: Vector2, sliding: bool) -> int:
	if not sliding:
		return 0
	var n := 0
	for d in dots:
		if not d["hit"] and p.distance_to(d["p"]) < 34.0:
			d["hit"] = true
			n += 1
	if n > 0:
		dots_node.queue_redraw()
	return n


## A red pen X where the run went over.
func mark_out(p: Vector2) -> void:
	marks.append(p)
	dots_node.queue_redraw()


func update() -> void:
	gloss.queue_redraw()
	if not guide.is_empty():
		guide_node.queue_redraw()


# ---------------------------------------------------------------- teaching

func _teach(kind: String, at: float) -> void:
	if taught.has(kind):
		return
	var arr: Array = TEACH[kind]
	guide = {"text": arr[g.rng.randi() % arr.size()], "at": at, "t": -1.0, "kind": kind}


## The note rides beside the car for a few seconds once the car reaches where it applies, then fades.
func _draw_guide(c: Node2D) -> void:
	if guide.is_empty():
		return
	var here: float = g.lens[mini(g.progress_i, g.lens.size() - 1)]
	if float(guide["t"]) < 0.0:
		if here < float(guide["at"]) - 300.0:
			return
		guide["t"] = g.clock
		taught[guide.get("kind", "")] = true  # only counts as taught once it has actually been shown
	var age: float = g.clock - float(guide["t"])
	if age > 9.0:
		guide = {}
		return
	var a := smoothstep(0.0, 0.4, age) * (1.0 - smoothstep(8.0, 9.0, age))
	var w: Dictionary = g.scrib.writer
	var font: Font = g.scrib.fonts[int(w.get("font", 0))]
	var col: Color = Color(w.get("col", Color(0.15, 0.15, 0.2)), a)
	var at: Vector2 = g.pos + Vector2(110, -170)
	var y := 0.0
	for line in String(guide["text"]).split("\n"):
		c.draw_set_transform(at + Vector2(0, y), -0.05, Vector2.ONE)
		c.draw_string(font, Vector2.ZERO, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
		y += 34.0
	c.draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- drawing (all hand strokes)

func _idx(l: float) -> int:
	var lens: PackedFloat32Array = g.lens
	var i := clampi(int((l - lens[0]) / STEP), 0, lens.size() - 1)
	return i


## A highlighter swipe along the outside of a corner: two or three overlapping passes with a chisel tip,
## translucent, the pencil showing through, darker where the passes cross.
func _highlight(c: Dictionary) -> void:
	var r: RandomNumberGenerator = g.rng
	var i := _idx(float(c["len"]))
	var span := int(clampf(float(c["r"]) / STEP, 12.0, 28.0))
	var a := maxi(0, i - span)
	var b := mini(g.road.size() - 1, i + span)
	var out: float = -float(c["side"])
	var col: Color = [Color(1.0, 0.93, 0.1, 0.28), Color(0.55, 1.0, 0.35, 0.26), Color(1.0, 0.6, 0.85, 0.26)][r.randi() % 3]
	var n := Node2D.new()
	layer.add_child(n)
	var poly := PackedVector2Array()
	var inner := PackedVector2Array()
	for pass_k in r.randi_range(2, 3):
		var pts := PackedVector2Array()
		var off := r.randf_range(0.18, 0.42)
		var start := a + r.randi_range(0, 3)
		var stop := b - r.randi_range(0, 3)
		for k in range(start, stop + 1):
			var nrm := Vector2.from_angle(g._dir_at(k) + PI * 0.5) * out
			var hw: float = g.widths[k] * 0.5
			pts.append(g.road[k] + nrm * hw * (off + 0.04 * sin(k * 0.4 + pass_k)) + Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.6, 0.6)))
		var l := Line2D.new()
		l.points = pts
		l.width = r.randf_range(24.0, 30.0)
		l.default_color = col
		l.texture = g._tex("marker")
		l.texture_mode = Line2D.LINE_TEXTURE_TILE
		l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		l.begin_cap_mode = Line2D.LINE_CAP_NONE  # a chisel tip: square ends
		l.end_cap_mode = Line2D.LINE_CAP_NONE
		n.add_child(l)
	for k in range(a, b + 1):  # the zone itself: the outer half of the road along the swipe
		var nrm := Vector2.from_angle(g._dir_at(k) + PI * 0.5) * out
		var hw: float = g.widths[k] * 0.5
		poly.append(g.road[k] + nrm * hw * 1.05)
		inner.append(g.road[k] - nrm * hw * 0.05)
	inner.reverse()
	poly.append_array(inner)
	zones.append({"a": g.lens[a], "b": g.lens[b], "poly": poly, "len": g.lens[b], "node": n})


## A blue pen dot on the inside apex: a tap of the pen, a little ink spread, sometimes a tail.
func _dot(c: Dictionary) -> void:
	var i := _idx(float(c["len"]))
	var inside: float = float(c["side"])
	var nrm := Vector2.from_angle(g._dir_at(i) + PI * 0.5) * inside
	var p: Vector2 = g.road[i] + nrm * (g.widths[i] * 0.5 - 14.0)
	dots.append({"p": p, "len": g.lens[i], "hit": false, "seed": g.rng.randi(), "t": Vector2.from_angle(g._dir_at(i))})
	dots_node.queue_redraw()


func _draw_dots(c: Node2D) -> void:
	var blue := Color(0.1, 0.18, 0.55)
	# Clipping points as a drift event marks them: a hatched clip box painted along the inside edge, and a
	# traffic cone on it, seen from above (square base, orange cone, white reflective band, its shadow).
	for d in dots:
		var r := RandomNumberGenerator.new()
		r.seed = int(d["seed"])
		var p: Vector2 = d["p"]
		var t: Vector2 = d.get("t", Vector2.RIGHT)
		var nrm := t.orthogonal()
		var box := PackedVector2Array([p - t * 34.0 - nrm * 9.0, p + t * 34.0 - nrm * 9.0, p + t * 34.0 + nrm * 9.0, p - t * 34.0 + nrm * 9.0])
		for k in 4:
			g.scrib._wobble_line(c, box[k], box[(k + 1) % 4], Color(0.25, 0.25, 0.3, 0.55), 1.6, r)
		for k in range(-4, 5):  # hatching inside the box
			var q := p + t * k * 7.0
			g.scrib._wobble_line(c, q - nrm * 7.0 - t * 4.0, q + nrm * 7.0 + t * 4.0, Color(0.25, 0.25, 0.3, 0.3), 1.2, r)
		var cone := p + Vector2(r.randf_range(-3, 3), r.randf_range(-3, 3))
		c.draw_set_transform(cone + Vector2(-3, 5), 0.0, Vector2(1.0, 0.8))
		c.draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.16), true, -1.0, false)
		var rot := r.randf_range(-0.3, 0.3)
		c.draw_set_transform(cone, rot, Vector2.ONE)
		var base := PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10), Vector2(-10, -10)])
		c.draw_colored_polygon(base, Color(0.95, 0.42, 0.12))
		c.draw_polyline(base, Color(0.45, 0.18, 0.05, 0.8), 1.4)
		c.draw_set_transform(cone, 0.0, Vector2.ONE)
		c.draw_circle(Vector2.ZERO, 7.5, Color(1.0, 0.5, 0.16))
		c.draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 20, Color(0.97, 0.97, 0.95), 2.2)  # the reflective band
		c.draw_circle(Vector2.ZERO, 2.2, Color(1.0, 0.62, 0.3))  # the cone's tip
		c.draw_arc(Vector2.ZERO, 7.5, PI * 0.9, PI * 1.6, 10, Color(1, 1, 1, 0.35), 1.4)  # light on its side
		c.draw_set_transform(Vector2.ZERO)
		if d["hit"]:  # clipped: ticked off beside it in blue pen
			var tk := cone + nrm * 22.0
			g.scrib._hand_poly(c, PackedVector2Array([tk + Vector2(-7, -1), tk + Vector2(-2, 6), tk + Vector2(9, -9)]), Color(0.1, 0.18, 0.55, 0.85), 2.2, r)
	for p in marks:  # a red X where a run went over the red line
		var r := RandomNumberGenerator.new()
		r.seed = int(p.x * 7 + p.y)
		g.scrib._wobble_line(c, p + Vector2(-18, -18), p + Vector2(18, 18), RED, 3.2, r)
		g.scrib._wobble_line(c, p + Vector2(18, -18), p + Vector2(-18, 18), RED, 3.2, r)


## Crayon coloured in over part of the page and the road: back-and-forth waxy strokes, paper tooth showing
## through, overshooting the shape here and there, pressing harder in places.
func _wax(from: int) -> void:
	var r: RandomNumberGenerator = g.rng
	var i := r.randi_range(from, g.road.size() - 1)
	var center: Vector2 = g.road[i] + Vector2.from_angle(g._dir_at(i) + PI * 0.5) * r.randf_range(-40.0, 40.0)
	var rx := r.randf_range(80.0, 130.0)
	var ry := r.randf_range(50.0, 80.0)
	var rot := r.randf() * TAU
	var poly := PackedVector2Array()
	for k in 20:
		var t := TAU * k / 20.0
		poly.append(center + Vector2(cos(t) * rx, sin(t) * ry).rotated(rot) * (1.0 + r.randf_range(-0.12, 0.1)))
	var col: Color = CRAYONS[r.randi() % CRAYONS.size()]
	var n := Node2D.new()
	layer.add_child(n)
	var dir := Vector2.from_angle(rot + r.randf_range(0.6, 1.0))
	var across := dir.orthogonal()
	var strokes := PackedVector2Array()
	var t := -maxf(rx, ry) * 1.1
	var flip := 1.0
	while t < maxf(rx, ry) * 1.1:  # zig-zag fill, each sweep reaching a little past the edge
		var base := center + across * t
		var reach := _chord(poly, base, dir)
		if reach.x < reach.y:
			var p0 := base + dir * (reach.x - r.randf_range(-2.0, 8.0))
			var p1 := base + dir * (reach.y + r.randf_range(-2.0, 8.0))
			strokes.append(p0 if flip > 0.0 else p1)  # back and forth, like a hand colouring in
			strokes.append(p1 if flip > 0.0 else p0)
		t += r.randf_range(3.5, 6.0)  # strokes overlap: the wax builds up unevenly
		flip = -flip
		dir = dir.rotated(r.randf_range(-0.05, 0.05)).normalized()  # the hand drifts a little each sweep
		across = dir.orthogonal()
	var l := Line2D.new()
	l.points = strokes
	l.width = 10.0
	l.default_color = Color(col, 0.42)
	l.texture = g._tex("pencil_soft")
	l.texture_mode = Line2D.LINE_TEXTURE_TILE
	l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	var curve := Curve.new()  # uneven pressure
	for k in 9:
		curve.add_point(Vector2(k / 8.0, r.randf_range(0.75, 1.1)))
	l.width_curve = curve
	n.add_child(l)
	var l2 := l.duplicate() as Line2D  # a second, lighter go over part of it, slightly off
	l2.position = Vector2(r.randf_range(-4, 4), r.randf_range(-4, 4))
	l2.rotation = r.randf_range(-0.04, 0.04)
	l2.default_color = Color(col, 0.22)
	var cut := l2.points.slice(0, int(l2.points.size() * r.randf_range(0.4, 0.75)))
	l2.points = cut
	n.add_child(l2)
	var edge := Line2D.new()  # a firmer outline pass, like a kid going round the edge first
	var ring := poly.duplicate()
	ring.append(poly[0])
	edge.points = ring
	edge.width = 4.0
	edge.default_color = Color(col.darkened(0.1), 0.55)
	edge.texture = g._tex("pencil_soft")
	edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	n.add_child(edge)
	waxes.append({"poly": poly, "len": g.lens[i] + 200.0, "node": n})
	if not taught.has("wax"):
		_teach("wax", g.lens[i])


## Where a line through `base` along `dir` enters and leaves the polygon (distances along dir).
func _chord(poly: PackedVector2Array, base: Vector2, dir: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		var hit = Geometry2D.line_intersects_line(base, dir, a, b - a)
		if hit != null:
			var hp: Vector2 = hit
			var along := (hp - a).dot(b - a) / maxf((b - a).length_squared(), 0.001)
			if along >= 0.0 and along <= 1.0:
				var d := (hp - base).dot(dir)
				lo = minf(lo, d)
				hi = maxf(hi, d)
	return Vector2(lo, hi)


## Spilled ink: a pooled blob darker at its rim, droplets flung around it, a glossy highlight (drawn by the
## gloss layer so it moves with the light as the camera moves), and later, a tyre track through it.
func _puddle(from: int) -> void:
	var r: RandomNumberGenerator = g.rng
	var i := r.randi_range(from, g.road.size() - 1)
	var p: Vector2 = g.road[i] + Vector2.from_angle(g._dir_at(i) + PI * 0.5) * r.randf_range(-30.0, 30.0)
	var rad := r.randf_range(34.0, 52.0)
	var col: Color = INKS[r.randi() % INKS.size()]
	var poly := PackedVector2Array()
	var seed := r.randf() * 10.0
	for k in 72:
		var t := TAU * k / 72.0
		var tendril := pow(maxf(0.0, sin(t * 5.0 + seed * 3.0)), 12.0) * 0.35  # ink creeping along the fibres
		poly.append(p + Vector2.from_angle(t) * rad * (1.0 + 0.14 * sin(t * 3.0 + seed) + 0.07 * sin(t * 7.0 + seed * 2.0) + 0.03 * sin(t * 19.0 + seed) + tendril))
	var drops: Array = []
	for k in r.randi_range(6, 12):
		var t := r.randf() * TAU
		drops.append([p + Vector2.from_angle(t) * rad * r.randf_range(1.15, 1.9), r.randf_range(1.5, 4.5)])
	var pd := {"p": p, "r": rad, "col": col, "poly": poly, "len": g.lens[i], "track": PackedVector2Array()}
	var n := DrawNode.new()
	n.draw_fn = func(c: Node2D):
		# layered from the rim inwards: darkest where it pooled at the edge, a touch thinner in the middle
		for k in 5:
			var f := 1.0 - k * 0.12
			var ring := PackedVector2Array()
			for q in poly:
				ring.append(p + (q - p) * f)
			var shade := col.darkened(0.25 - k * 0.07) if k < 4 else col.lightened(0.08)
			c.draw_colored_polygon(ring, Color(shade, 0.55 if k == 0 else 0.4))
		for d in drops:
			c.draw_circle(d[0], d[1], Color(col, 0.85))
			c.draw_circle(d[0] + Vector2(d[1] * 0.3, -d[1] * 0.3), d[1] * 0.35, Color(1, 1, 1, 0.25))  # each droplet catches the light
		var tr: PackedVector2Array = pd["track"]
		if tr.size() >= 2:  # the tyres pushed the ink aside: a paler streak through it
			c.draw_polyline(tr, Color(col.lightened(0.35), 0.55), 9.0, true)
	pd["node"] = n
	layer.add_child(n)
	puddles.append(pd)
	if not taught.has("puddle"):
		_teach("puddle", g.lens[i])


func _draw_gloss(c: Node2D) -> void:
	var cam: Vector2 = g.cam.position
	for pd in puddles:
		var p: Vector2 = pd["p"]
		if p.distance_squared_to(cam) > 1400.0 * 1400.0:
			continue
		var rad: float = pd["r"]
		var shift := ((p - cam) * 0.02).limit_length(8.0)  # the reflection slides as you move past
		c.draw_arc(p + Vector2(-rad * 0.25, -rad * 0.3) + shift, rad * 0.45, PI * 1.05, PI * 1.6, 12, Color(1, 1, 1, 0.55), 4.0, true)
		c.draw_arc(p + Vector2(-rad * 0.25, -rad * 0.3) + shift, rad * 0.52, PI * 1.12, PI * 1.45, 8, Color(1, 1, 1, 0.2), 7.0, true)
		c.draw_circle(p + Vector2(-rad * 0.42, -rad * 0.12) + shift, 2.6, Color(1, 1, 1, 0.45))
