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
	"red": ["Red lines are walls.\nIf your car goes fully over one, the run ends."],
	"marked": ["Cones and boxes give bonus points.\nDrift past them as close as you can."],
	"wax": ["crayon is slippery.\nyou'll slide further. enjoy it.", "someone coloured in here.\nwax. no grip. very fun."],
	"puddle": ["spilled ink. harmless.\nyou'll just slide, and paint the page.", "ink puddle. go through it.\nyour tyres will remember."],
}

var g: Node
var layer: Node2D  # on the page, over the road ink
var gloss: Node2D  # puddle shine, redrawn as the camera moves
var guide_node: Node2D  # the teaching note, written in a bend
var chapters: Array = [[-INF, "plain"]]  # [start len, kind], in order
var zones: Array = []  # highlighter: {a, b (len), side, node}
const RING_PERFECT := 30.0  # the car's nose this close to the cone: PERFECT
const RING_CLIP := 60.0  # this close: CLIP
const CONE_HIT := 12.0  # touching it tips it over (no points, no penalty)
const BOX_W := 32.0  # the outer box's depth inside the road edge
const BOX_EDGE := 8.0  # the tail this close to the edge line (or just over it): PERFECT
const BOX_OVER := 12.0  # further over the edge than this is too far: nothing
var dots: Array = []  # a cone at the inside of each corner and a box on its outside: see _dot
var waxes: Array = []  # {poly, len}
var puddles: Array = []  # {p, r, col, poly, len, node, track}
var marks: Array = []  # red X where a run went out
var taught := {}
var guide := {}  # {text, p, len, t, kind}
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
	for d in dots:
		if float(d["len"]) < behind - 400.0 and d.has("node") and is_instance_valid(d["node"]):
			(d["node"] as Node).queue_free()
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


## The clips, checked every frame: `nose` are points on the car's front, `tails` its rear corners, `body`
## its outline (any of it touching a cone tips it over), `l` how far along the road the car is. Each cone and box scores once, at its best moment (1 = CLIP, 2 = PERFECT),
## only while drifting. Returns what just scored: [{kind, grade, p}].
func clip_check(nose: Array, tails: Array, body: Array, l: float, drifting: bool) -> Array:
	var out: Array = []
	for d in dots:
		if absf(l - float(d["len"])) > 500.0:
			continue
		if int(d["cone_res"]) < 0:
			var cp: Vector2 = d["p"]
			var near := INF
			for q in nose:
				near = minf(near, cp.distance_to(q))
			var touch := INF
			var by: Vector2 = nose[0]
			for q in body:
				if cp.distance_to(q) < touch:
					touch = cp.distance_to(q)
					by = q
			if touch < CONE_HIT and not d["tipped"]:
				d["tipped"] = true
				d["tip"] = (cp - by).angle()  # knocked away from whatever hit it
				(d["node"] as Node2D).queue_redraw()
			if drifting:
				d["best"] = minf(float(d["best"]), near)
			if l > float(d["len"]) + 60.0:
				var grade := 0
				if not d["tipped"]:
					grade = 2 if float(d["best"]) < RING_PERFECT else (1 if float(d["best"]) < RING_CLIP else 0)
				d["cone_res"] = grade
				if grade > 0:
					d["hit"] = true
					out.append({"kind": "cone", "grade": grade, "p": cp})
				(d["node"] as Node2D).queue_redraw()
		if int(d["box_res"]) < 0:
			if l >= float(d["a"]) and l <= float(d["b"]) and drifting:
				var i := _idx(l)
				var no := Vector2.from_angle(g._dir_at(i) + PI * 0.5) * float(d["out"])
				for q in tails:
					var e: float = (Vector2(q) - g.road[i]).dot(no) - g.widths[i] * 0.5  # past the edge (+) or inside (-)
					if e > -BOX_W and e < BOX_OVER:
						var grade := 2 if e > -BOX_EDGE else 1
						if grade > int(d["box_best"]):
							d["box_best"] = grade
							d["box_p"] = q
			if l > float(d["b"]):
				d["box_res"] = int(d["box_best"])
				if int(d["box_res"]) > 0:
					(d["node"] as Node2D).queue_redraw()
					out.append({"kind": "box", "grade": int(d["box_res"]), "p": d["box_p"]})
	return out


## A red pen X where the run went over.
func mark_out(p: Vector2) -> void:
	marks.append(p)
	dots_node.queue_redraw()


func update() -> void:
	gloss.queue_redraw()
	if not guide.is_empty():
		guide_node.queue_redraw()


# ---------------------------------------------------------------- teaching

const TEACH_SIZE := 34
const TEACH_LINE := 38.0


## Write the note once, standing still on the paper in the last bend before the rule starts (the inside of
## a hairpin if it fits, else the outside), so it is read while the car slides past. Never follows the car.
func _teach(kind: String, at: float) -> void:
	if taught.has(kind):
		return
	var arr: Array = TEACH[kind]
	var text: String = arr[g.rng.randi() % arr.size()]
	var font: Font = g.ui_font()
	var lines := text.split("\n")
	var size := Vector2(0, TEACH_LINE * lines.size())
	for line in lines:
		size.x = maxf(size.x, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, TEACH_SIZE).x)
	var here: float = g.lens[mini(g.progress_i, g.lens.size() - 1)]
	# The tightest bend in the last stretch before the rule (far enough ahead to still be read).
	var pick := {}
	for c in g.corners:
		var l := float(c["len"])
		if l < here + 500.0 or l > at - 150.0 or l < at - 1800.0:
			continue
		if pick.is_empty() or float(c["r"]) < float(pick["r"]):
			pick = c
	var i := _idx(float(pick["len"]) if not pick.is_empty() else at - 400.0)
	var side := float(pick.get("side", 1.0))
	var spot := Vector2.INF
	for out in [side, -side]:  # inside of the bend first (the curve wraps round it), then outside
		spot = g.scrib._free_spot(g.road[i], out, size, i)
		if spot != Vector2.INF:
			break
	if spot == Vector2.INF:
		return  # no paper free: try again on the next page of this pen
	guide = {"text": text, "p": spot, "len": g.lens[i], "t": -1.0, "kind": kind}


## Fades in as the car comes up to the bend, stays put, fades once the car is well past.
func _draw_guide(c: Node2D) -> void:
	if guide.is_empty():
		return
	var here: float = g.lens[mini(g.progress_i, g.lens.size() - 1)]
	var l := float(guide["len"])
	if float(guide["t"]) < 0.0:
		if here < l - 1100.0:
			return
		guide["t"] = g.clock
		taught[guide.get("kind", "")] = true  # only counts as taught once it has actually been shown
	if here > l + 900.0:
		guide = {}
		return
	var a := smoothstep(0.0, 0.5, g.clock - float(guide["t"])) * (1.0 - smoothstep(l + 500.0, l + 900.0, here))
	var w: Dictionary = g.scrib.writer
	var font: Font = g.ui_font()
	var col: Color = Color(w.get("col", Color(0.15, 0.15, 0.2)), a)
	var at: Vector2 = guide["p"]
	var y := 0.0
	for line in String(guide["text"]).split("\n"):
		c.draw_set_transform(at + Vector2(0, y), -0.03, Vector2.ONE)
		c.draw_string(font, Vector2.ZERO, line, HORIZONTAL_ALIGNMENT_LEFT, -1, TEACH_SIZE, col)
		y += TEACH_LINE
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
## Clipping for one drift corner, placed the way a drift event lays out a course: a clipping point (cone)
## at the inside apex and an outer zone (box) along the outside from just before the apex to the exit.
## Next to the corner before it:
## - the same way again soon after (a double apex): one long outer zone covering both, and a second cone
##   only if the apexes are far enough apart for the two rings not to touch;
## - the other way soon after (a switch): the earlier box stops before the new cone's rings, the new box
##   starts after the old cone's rings, and a box left too short is dropped (not every corner has one).
func _dot(c: Dictionary) -> void:
	var i := _idx(float(c["len"]))
	var inside: float = float(c["side"])
	var nrm := Vector2.from_angle(g._dir_at(i) + PI * 0.5) * inside
	var p: Vector2 = g.road[i] + nrm * (g.widths[i] * 0.5 - 14.0)
	var l: float = g.lens[i]
	var d := {"p": p, "len": l, "hit": false, "seed": g.rng.randi(), "t": Vector2.from_angle(g._dir_at(i)),
		"tipped": false, "tip": 0.0, "best": INF, "cone": true, "cone_res": -1,
		"a": 0.0, "b": 0.0, "out": -inside, "edge": PackedVector2Array(), "inner": PackedVector2Array(),
		"box_best": 0, "box_res": 0, "box_p": Vector2.ZERO}
	var box_a := l - 60.0
	var box_b := l + 170.0
	var prev: Dictionary = dots[dots.size() - 1] if not dots.is_empty() else {}
	var gap := l - float(prev.get("len", -INF))
	var holder := {}  # the latest box still open (a double apex's shared box sits on its first apex)
	for k in range(dots.size() - 1, maxi(-1, dots.size() - 4), -1):
		if int(dots[k]["box_res"]) == -1:
			holder = dots[k]
			break
	dots.append(d)  # in the list first, so boxes trimmed below keep clear of this cone too
	var node := DrawNode.new()
	node.draw_fn = func(cv: Node2D): _draw_dot(cv, d)
	layer.add_child(node)
	d["node"] = node
	if not prev.is_empty() and gap < 420.0 and float(prev["out"]) == -inside:  # the same way again: a double apex
		if not holder.is_empty() and float(holder["out"]) == -inside:  # its box stretches on through this apex too
			_box(holder, float(holder["a"]), box_b)
		else:
			_box(d, box_a, box_b)
		if p.distance_to(prev["p"]) < RING_CLIP * 2.0 + 20.0:
			d["cone"] = false  # too close to the last cone: this apex shares it
			d["cone_res"] = 0
	else:
		if not prev.is_empty() and gap < 420.0:  # a switch: keep each box clear of the other corner's cone
			var cone_reach := RING_CLIP + 30.0
			if not holder.is_empty() and float(holder["b"]) > l - cone_reach:
				_box(holder, float(holder["a"]), l - cone_reach)
			box_a = maxf(box_a, float(prev["len"]) + cone_reach)
		_box(d, box_a, box_b)
	node.queue_redraw()
	if not holder.is_empty() and holder.has("node"):
		(holder["node"] as Node2D).queue_redraw()


## Lay a dot's outer box along its outside edge between road lengths a and b, its ends pulled back until
## they are clear of every other cone's rings (in tight bends the edge runs close to a cone even when the
## road length says it's far), or drop it if what's left is too short to be worth aiming for.
func _box(d: Dictionary, a: float, b: float) -> void:
	var i0 := _idx(a)
	var i1 := _idx(b)
	var clear := func(k: int) -> bool:
		var no := Vector2.from_angle(g._dir_at(k) + PI * 0.5) * float(d["out"])
		var e: Vector2 = g.road[k] + no * g.widths[k] * 0.5
		var n: Vector2 = g.road[k] + no * (g.widths[k] * 0.5 - BOX_W)
		for o in dots:
			if o != d and o.get("cone", true) and absf(float(o["len"]) - g.lens[k]) < 700.0:
				var cp: Vector2 = o["p"]
				if e.distance_to(cp) < RING_CLIP + 10.0 or n.distance_to(cp) < RING_CLIP + 10.0:
					return false
		return true
	while i0 < i1 and not clear.call(i0):
		i0 += 1
	while i1 > i0 and not clear.call(i1):
		i1 -= 1
	if g.lens[i1] - g.lens[i0] < 100.0:
		d["edge"] = PackedVector2Array()
		d["inner"] = PackedVector2Array()
		d["box_res"] = 0
		return
	var edge := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in range(i0, i1 + 1):
		var no := Vector2.from_angle(g._dir_at(k) + PI * 0.5) * float(d["out"])
		edge.append(g.road[k] + no * g.widths[k] * 0.5)
		inner.append(g.road[k] + no * (g.widths[k] * 0.5 - BOX_W))
	d["edge"] = edge
	d["inner"] = inner
	d["a"] = g.lens[i0]
	d["b"] = g.lens[i1]
	d["box_res"] = -1


## The red X marks where runs went over (each clip set draws itself: _draw_dot).
func _draw_dots(c: Node2D) -> void:
	for p in marks:  # a red X where a run went over the red line
		var r := RandomNumberGenerator.new()
		r.seed = int(p.x * 7 + p.y)
		g.scrib._wobble_line(c, p + Vector2(-18, -18), p + Vector2(18, 18), RED, 3.2, r)
		g.scrib._wobble_line(c, p + Vector2(18, -18), p + Vector2(-18, 18), RED, 3.2, r)


## One clip set, in its own node: a cone on a painted apex cross at the inside (two pencil rings show how
## close to get) and a painted box along the outside edge for the tail.
func _draw_dot(c: Node2D, d: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(d["seed"])
	var p: Vector2 = d["p"]
	var t: Vector2 = d.get("t", Vector2.RIGHT)
	var nrm := t.orthogonal()
	var pen := Color(0.25, 0.25, 0.3)
	# the outer box: painted along the outside edge, its edge line darker (touch it for PERFECT), hatched
	# across, and a few stacks of old tyres just off the road behind it
	var edge: PackedVector2Array = d.get("edge", PackedVector2Array())
	var inner: PackedVector2Array = d.get("inner", PackedVector2Array())
	if edge.size() > 2:
		var swept := int(d["box_res"]) > 0
		for k in edge.size() - 1:
			g.scrib._wobble_line(c, edge[k], edge[k + 1], Color(pen, 0.85), 2.6, r)
			g.scrib._wobble_line(c, inner[k], inner[k + 1], Color(pen, 0.45), 1.4, r)
		g.scrib._wobble_line(c, edge[0], inner[0], Color(pen, 0.55), 1.4, r)
		g.scrib._wobble_line(c, edge[edge.size() - 1], inner[inner.size() - 1], Color(pen, 0.55), 1.4, r)
		for k in range(1, edge.size() - 1, 2):  # hatching; darker once a tail has swept through
			g.scrib._wobble_line(c, edge[k], inner[mini(k + 1, inner.size() - 1)], Color(pen, 0.5 if swept else 0.25), 1.2, r)
		for k in range(2, edge.size() - 2, maxi(3, edge.size() / 3)):  # tyre stacks behind the box
			var back := edge[k] + (edge[k] - inner[k]).normalized() * 22.0
			var along := (edge[mini(k + 1, edge.size() - 1)] - edge[k]).normalized()
			for j in 2:
				var tc := back + along * (j * 17.0 - 8.0)
				c.draw_arc(tc, 8.5, 0.0, TAU, 14, Color(pen, 0.7), 1.8)
				c.draw_arc(tc, 3.5, 0.0, TAU, 10, Color(pen, 0.45), 1.2)
	if not d.get("cone", true):
		return
	# the cone's two pencil rings: inside the small one is PERFECT, inside the big one a CLIP
	if not d["tipped"] and int(d["cone_res"]) < 0:
		for ring in [[RING_CLIP, 0.22], [RING_PERFECT, 0.35]]:
			var segs := 18
			for k in segs:
				if k % 2 == 0:
					var a0 := TAU * k / segs + r.randf() * 0.05
					c.draw_arc(p, float(ring[0]) + r.randf_range(-1.5, 1.5), a0, a0 + TAU / segs, 4, Color(pen, float(ring[1])), 1.3)
	# a painted cross on the apex, under the cone
	g.scrib._wobble_line(c, p - t * 14.0, p + t * 14.0, Color(0.95, 0.95, 0.9, 0.9), 4.0, r)
	g.scrib._wobble_line(c, p - nrm * 8.0, p + nrm * 8.0, Color(0.95, 0.95, 0.9, 0.9), 4.0, r)
	var cone := p + Vector2(r.randf_range(-3, 3), r.randf_range(-3, 3))
	if d["tipped"]:  # knocked over: lying on its side, its base square kicked off behind it
		var ta := float(d["tip"])
		c.draw_set_transform(cone + Vector2.from_angle(ta) * 10.0, ta, Vector2.ONE)
		var body := PackedVector2Array([Vector2(-9, -8), Vector2(14, -2.5), Vector2(14, 2.5), Vector2(-9, 8)])
		c.draw_colored_polygon(body, Color(1.0, 0.5, 0.16))
		c.draw_line(Vector2(-1, -6), Vector2(-1, 6), Color(0.97, 0.97, 0.95), 2.4)
		body.append(body[0])
		c.draw_polyline(body, Color(0.45, 0.18, 0.05, 0.8), 1.2)
		c.draw_set_transform(cone - Vector2.from_angle(ta) * 8.0, ta + 0.7, Vector2.ONE)
		var tb := PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10), Vector2(-10, -10)])
		c.draw_colored_polygon(tb, Color(0.95, 0.42, 0.12))
		c.draw_polyline(tb, Color(0.45, 0.18, 0.05, 0.8), 1.4)
		c.draw_set_transform(Vector2.ZERO)
		return
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
