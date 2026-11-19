class_name Jetty
extends RefCounted
## A wooden jetty built from a seed, so every lake gets its own and new lakes need only two points.
##
## Seen from above like a real one: a dark underside showing through the gaps between deck boards, two
## stringers under the boards, boards of slightly different lengths and shades (some weathered grey,
## the odd new one, now and then one missing), nail heads, a rim board along each edge, pilings at the
## edges (sometimes as posts standing above the deck), its shadow on the water, and a few things people
## leave on a jetty. The shape (straight, L, T or a platform at the end) is picked from the seed, and only
## if it stays on the water clear of lanterns, rocks, reeds and the boat's mooring spot.

const SHAPES := ["straight", "L", "T", "platform"]

var shape := "straight"
var lamp = null  # where a lamp post stands (Vector2), or null
var _parts: Array = []  # deck sections: {"a": Vector2, "b": Vector2, "w": float}, boards run across a→b
var _piles: Array = []  # [position, radius]
var _wet: PackedVector2Array = PackedVector2Array()  # pilings standing in the water, for their rings
var _posts := false  # pilings carried up above the deck as posts
var _boards: Array = []  # [polygon, colour, grain from, grain to, nails]
var _extras: Array = []  # [kind, ...] drawn on top
var _wood: Color


## a: the shore end, b: the water end (where the boat is moored). hint: a shape to prefer, or "".
## avoid: [[position, radius], ...] that extra decking must keep clear of.
static func build(a: Vector2, b: Vector2, hint: String, seed: int, wood: Color, water: PackedVector2Array,
		avoid: Array, want_lamp: bool) -> Jetty:
	var j := Jetty.new()
	j._wood = wood
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dir := (b - a).normalized()
	var across := dir.orthogonal()
	var w := rng.randf_range(17.0, 23.0)
	var length := a.distance_to(b)

	# The shape: the hint first, then the rest in a seeded order, each L on either side; straight always fits.
	var order: Array = []
	if hint in SHAPES:
		order.append(hint)
	var pool: Array = SHAPES.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[k]
		pool[k] = t
	for s in pool:
		if not s in order:
			order.append(s)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var arm := rng.randf_range(30.0, 46.0)
	var head := rng.randf_range(24.0, 34.0)
	var plat_w := rng.randf_range(38.0, 50.0)
	var plat_d := rng.randf_range(24.0, 34.0)
	for s in order:
		var tries: Array = []
		match s:
			"straight":
				tries = [[{"a": a, "b": b, "w": w}]]
			"L":
				for sd in [side, -side]:
					var w2 := w * 0.92
					var root: Vector2 = b - dir * (w2 * 0.5) + across * float(sd) * (w * 0.5)
					tries.append([{"a": a, "b": b, "w": w}, {"a": root, "b": root + across * float(sd) * arm, "w": w2}])
			"T":
				var w2 := w * 0.95
				var mid := b - dir * (w2 * 0.5)
				if length > w2 + 16.0:
					tries.append([{"a": a, "b": b - dir * w2, "w": w},
						{"a": mid - across * head, "b": mid + across * head, "w": w2}])
			"platform":
				if length > plat_d + 16.0:
					tries.append([{"a": a, "b": b - dir * plat_d, "w": w}, {"a": b - dir * plat_d, "b": b, "w": plat_w}])
		for parts in tries:
			if s == "straight" or _fits(parts.slice(1), water, avoid):
				j.shape = s
				j._parts = parts
				break
		if not j._parts.is_empty():
			break

	j._build_detail(rng, water, want_lamp)
	return j


static func _corners(p: Dictionary) -> PackedVector2Array:
	var a: Vector2 = p["a"]
	var b: Vector2 = p["b"]
	var s: Vector2 = (b - a).normalized().orthogonal() * float(p["w"]) * 0.5
	return PackedVector2Array([a - s, b - s, b + s, a + s])


## Extra decking must sit on the water (with a margin), clear of everything in `avoid`.
static func _fits(parts: Array, water: PackedVector2Array, avoid: Array) -> bool:
	for p in parts:
		var c := _corners(p)
		for i in 4:
			var e0 := c[i]
			var e1 := c[(i + 1) % 4]
			var steps := maxi(1, int(e0.distance_to(e1) / 5.0))
			for k in steps + 1:
				var q := e0.lerp(e1, float(k) / steps)
				if not Geometry2D.is_point_in_polygon(q, water):
					return false
				for av in avoid:
					if q.distance_to(av[0]) < float(av[1]):
						return false
	return true


func _build_detail(rng: RandomNumberGenerator, water: PackedVector2Array, want_lamp: bool) -> void:
	var weather := rng.randf_range(0.2, 0.75)  # how grey and worn this jetty is
	var grey := Color.from_hsv(0.0, 0.0, _wood.get_luminance() * 1.05)
	_posts = rng.randf() < 0.5
	var pile_gap := rng.randf_range(22.0, 30.0)
	var pitch := rng.randf_range(4.4, 5.2)
	for pi in _parts.size():
		var p: Dictionary = _parts[pi]
		var a: Vector2 = p["a"]
		var b: Vector2 = p["b"]
		var w: float = p["w"]
		var axis := (b - a).normalized()
		var side := axis.orthogonal()
		var length := a.distance_to(b)
		# Pilings along both edges, from end to end.
		var n := maxi(1, int(round(length / pile_gap)))
		for k in n + 1:
			if pi > 0 and k == 0 and shape == "L":
				continue  # the arm joins the main deck there
			for s in [-1.0, 1.0]:
				var q: Vector2 = a + axis * (length * k / n) + side * s * (w * 0.5 - 1.0)
				var r := rng.randf_range(2.6, 3.5)
				_piles.append([q, r])
				if Geometry2D.is_point_in_polygon(q, water):
					_wet.append(q)
		# Deck boards across the section, each a little different.
		var d := 0.0
		var count := int(length / pitch)
		for k in count:
			var bw := pitch - rng.randf_range(0.8, 1.2)
			if k > 1 and k < count - 2 and rng.randf() < 0.025 + 0.03 * weather:
				d += pitch
				continue  # a missing board
			var c := _wood.lerp(grey, weather * rng.randf_range(0.3, 1.0))
			c = c.lightened(rng.randf_range(0.0, 0.1)) if rng.randf() < 0.5 else c.darkened(rng.randf_range(0.0, 0.12))
			if rng.randf() < 0.04:
				c = _wood.lightened(0.2).lerp(Color("c89a64"), 0.3)  # a new board
			var e0 := w * 0.5 + rng.randf_range(-0.8, 0.5)
			var e1 := w * 0.5 + rng.randf_range(-0.8, 0.5)
			var tilt := rng.randf_range(-0.35, 0.35)
			var p0 := a + axis * d
			var poly := PackedVector2Array([p0 - side * e0, p0 + side * e1,
				p0 + axis * (bw + tilt) + side * e1, p0 + axis * (bw - tilt) - side * e0])
			var g := rng.randf_range(0.3, 0.7) * bw
			var nails := PackedVector2Array()
			for s in [-0.3, 0.3]:
				nails.append(p0 + axis * bw * 0.5 + side * w * s)
			_boards.append([poly, c, p0 + axis * g - side * (e0 - 1.5), p0 + axis * g + side * (e1 - 1.5), nails])
			d += pitch

	# Things left on the jetty, placed on the deck near the water end.
	var main: Dictionary = _parts[0]
	var end: Dictionary = _parts[_parts.size() - 1]
	var ma: Vector2 = main["a"]
	var mb: Vector2 = main["b"]
	var md := (mb - ma).normalized()
	var ms := md.orthogonal()
	var mw: float = main["w"]
	var ml := ma.distance_to(mb)
	var spot := func(t: float, s: float) -> Vector2: return ma + md * ml * t + ms * mw * s
	if want_lamp:
		lamp = mb + ms * (mw * 0.5 - 2.0) - md * 3.0
		_extras.append(["lamp", lamp])
	for k in rng.randi_range(1, 2):
		var t := rng.randf_range(0.55, 0.95)
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		_extras.append(["cleat", spot.call(t, s * 0.4), md])
	if rng.randf() < 0.6:
		_extras.append(["coil", spot.call(rng.randf_range(0.6, 0.9), rng.randf_range(-0.25, 0.25))])
	if rng.randf() < 0.55:
		# A ladder down into the water off the end or a side.
		var ea: Vector2 = end["a"]
		var eb: Vector2 = end["b"]
		var ed := (eb - ea).normalized()
		var es := ed.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := eb - ed * rng.randf_range(4.0, 10.0) + es * float(end["w"]) * 0.5
		if Geometry2D.is_point_in_polygon(at + es * 10.0, water):
			_extras.append(["ladder", at, es, ed])
	if rng.randf() < 0.45:
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var t0 := rng.randf_range(0.45, 0.7)
		for k in rng.randi_range(2, 3):
			var q: Vector2 = spot.call(t0 + k * 0.12, s * 0.5) + ms * s * 2.5
			if Geometry2D.is_point_in_polygon(q, water):
				_extras.append(["tyre", q])
	if rng.randf() < 0.4:
		# A mooring rope from the end out into the water, sagging a little.
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var from: Vector2 = spot.call(0.97, s * 0.45)
		var to := from + ms * s * rng.randf_range(10.0, 16.0) + md * rng.randf_range(4.0, 10.0)
		if Geometry2D.is_point_in_polygon(to, water):
			_extras.append(["rope", from, to])
	if rng.randf() < 0.35 and _posts:
		_extras.append(["ring", spot.call(rng.randf_range(0.4, 0.8), 1.0 if rng.randf() < 0.5 else -1.0) ])
	var roomy := _parts.size() > 1
	if rng.randf() < (0.6 if roomy else 0.25):
		var host: Dictionary = end if roomy else main
		var ha: Vector2 = host["a"]
		var hb: Vector2 = host["b"]
		var q := ha.lerp(hb, rng.randf_range(0.35, 0.7)) + (hb - ha).normalized().orthogonal() * float(host["w"]) * rng.randf_range(-0.2, 0.2)
		_extras.append(["crate", q, rng.randf_range(-0.4, 0.4) + (hb - ha).angle(), rng.randf_range(0.0, 0.08)])
	if rng.randf() < 0.3:
		_extras.append(["bucket", spot.call(rng.randf_range(0.3, 0.8), rng.randf_range(-0.3, 0.3))])
	if shape == "platform" and rng.randf() < 0.7:
		var pa: Vector2 = end["a"]
		var pb: Vector2 = end["b"]
		var pd := (pb - pa).normalized()
		_extras.append(["bench", pa.lerp(pb, 0.55) + pd.orthogonal() * float(end["w"]) * 0.36, pd])


## The jetty itself. It never changes, so it is drawn once into its own node.
func draw(ci: CanvasItem, shade: Color) -> void:
	var dark := _wood.darkened(0.68)
	var pile_col := _wood.darkened(0.5)
	# Shadows on the water.
	for p in _parts:
		var c := _corners(p)
		var sh := PackedVector2Array()
		for q in c:
			sh.append(q + Vector2(5, 7))
		ci.draw_colored_polygon(sh, shade)
	for pl in _piles:
		ci.draw_circle(Vector2(pl[0]) + Vector2(5, 7), float(pl[1]), shade, true, -1.0, true)
	if not _posts:
		for pl in _piles:
			ci.draw_circle(pl[0], float(pl[1]), pile_col, true, -1.0, true)
	# The underside and the stringers, seen through the gaps.
	for p in _parts:
		ci.draw_colored_polygon(_corners(p), dark)
		var a: Vector2 = p["a"]
		var b: Vector2 = p["b"]
		var s: Vector2 = (b - a).normalized().orthogonal() * float(p["w"])
		for f in [-0.3, 0.3]:
			ci.draw_line(a + s * f, b + s * f, _wood.darkened(0.45), 2.4)
	for bd in _boards:
		var c: Color = bd[1]
		ci.draw_colored_polygon(bd[0], c)
		ci.draw_line(bd[2], bd[3], Color(c.darkened(0.18), 0.6), 0.7, true)
		for nl in bd[4]:
			ci.draw_circle(nl, 0.6, c.darkened(0.5))
	# Rim boards along the edges.
	for p in _parts:
		var c := _corners(p)
		ci.draw_line(c[0], c[1], _wood.darkened(0.3), 1.5, true)
		ci.draw_line(c[3], c[2], _wood.darkened(0.3), 1.5, true)
	if _posts:
		for pl in _piles:
			var r := float(pl[1]) + 0.4
			ci.draw_circle(pl[0], r, pile_col, true, -1.0, true)
			ci.draw_arc(pl[0], r * 0.55, 0.0, TAU, 12, pile_col.lightened(0.18), 0.7, true)  # end grain
			ci.draw_circle(pl[0], 0.7, pile_col.darkened(0.3))
	for e in _extras:
		_draw_extra(ci, e, shade)


func _draw_extra(ci: CanvasItem, e: Array, shade: Color) -> void:
	match String(e[0]):
		"lamp":
			ci.draw_circle(Vector2(e[1]) + Vector2(3, 4), 4.0, shade, true, -1.0, true)
			ci.draw_circle(e[1], 4.2, Color("2e2a26"), true, -1.0, true)
			ci.draw_circle(e[1], 2.4, Color("ffe7a6"), true, -1.0, true)
		"cleat":
			var p: Vector2 = e[1]
			var d: Vector2 = e[2]
			ci.draw_line(p - d * 3.2 + Vector2(1, 1.5), p + d * 3.2 + Vector2(1, 1.5), shade, 2.4, true)
			ci.draw_line(p - d * 3.2, p + d * 3.2, Color("4d4f4e"), 2.2, true)
			ci.draw_line(p - d * 2.4, p + d * 2.4, Color("8a8c88"), 0.8, true)
		"coil":
			for r in [3.8, 2.6, 1.4]:
				ci.draw_arc(e[1], r, 0.0, TAU, 16, Color("c2a06a"), 1.1, true)
		"ladder":
			var at: Vector2 = e[1]
			var out: Vector2 = e[2]
			var along: Vector2 = e[3]
			for s in [-2.6, 2.6]:
				ci.draw_line(at + along * s - out * 2.0, at + along * s + out * 9.0, Color(0.62, 0.65, 0.64, 0.9), 1.3, true)
			for k in 3:
				var q := at + out * (1.0 + k * 3.0)
				ci.draw_line(q - along * 2.6, q + along * 2.6, Color(0.6, 0.63, 0.62, 0.85 - k * 0.25), 1.0, true)
		"tyre":
			ci.draw_arc(e[1], 3.2, 0.0, TAU, 14, Color("23211f"), 2.2, true)
		"rope":
			var a: Vector2 = e[1]
			var b: Vector2 = e[2]
			var mid := a.lerp(b, 0.5) + (b - a).orthogonal().normalized() * 2.0
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for k in 9:
				var t := k / 8.0
				pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
				cols.append(Color(0.78, 0.66, 0.46, 1.0 - t * 0.85))  # going under the water
			ci.draw_polyline_colors(pts, cols, 1.1, true)
		"ring":
			ci.draw_arc(e[1], 3.6, 0.0, TAU, 20, Color("e5603a"), 2.2, true)
			for k in 4:
				var a0 := k * TAU / 4.0
				ci.draw_arc(e[1], 3.6, a0, a0 + 0.45, 4, Color("f1ece2"), 2.2, true)
		"crate":
			var c := Color("b08a5a").darkened(float(e[3]))
			ci.draw_set_transform(Vector2(e[1]) + Vector2(2.5, 3.5), float(e[2]), Vector2.ONE)
			ci.draw_rect(Rect2(-4.5, -4.5, 9, 9), shade)
			ci.draw_set_transform(e[1], float(e[2]), Vector2.ONE)
			ci.draw_rect(Rect2(-4.5, -4.5, 9, 9), c)
			for k in [-1.5, 1.5]:
				ci.draw_line(Vector2(-4.5, k), Vector2(4.5, k), c.darkened(0.25), 0.7)
			ci.draw_rect(Rect2(-4.5, -4.5, 9, 9), c.darkened(0.35), false, 0.8)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"bucket":
			ci.draw_circle(Vector2(e[1]) + Vector2(1.5, 2), 2.8, shade, true, -1.0, true)
			ci.draw_circle(e[1], 2.8, Color("5d7b86"), true, -1.0, true)
			ci.draw_circle(e[1], 1.9, Color("2f4048"), true, -1.0, true)
		"bench":
			var p: Vector2 = e[1]
			var d: Vector2 = e[2].orthogonal()
			ci.draw_line(p - d * 8.0 + Vector2(2, 3), p + d * 8.0 + Vector2(2, 3), shade, 5.0)
			ci.draw_line(p - d * 8.0, p + d * 8.0, _wood.lightened(0.08), 5.0)
			ci.draw_line(p - d * 8.0, p + d * 8.0, _wood.darkened(0.2), 0.7)


## How far p is from the nearest deck section (0 on it), and the way out from it: [distance, normal].
func nearest(p: Vector2) -> Array:
	var best := INF
	var out := Vector2.ZERO
	for part in _parts:
		var a: Vector2 = part["a"]
		var b: Vector2 = part["b"]
		var axis := (b - a).normalized()
		var side := axis.orthogonal()
		var half_l := a.distance_to(b) * 0.5
		var half_w := float(part["w"]) * 0.5
		var d := p - (a + b) * 0.5
		var u := d.dot(axis)
		var v := d.dot(side)
		var du := maxf(0.0, absf(u) - half_l)
		var dv := maxf(0.0, absf(v) - half_w)
		var dist := Vector2(du, dv).length()
		if dist < best:
			best = dist
			var n := axis * signf(u) * du + side * signf(v) * dv
			if n.length() < 0.001:
				n = side * (1.0 if v >= 0.0 else -1.0)
			out = n.normalized()
	return [best, out]


## The water moving round the pilings that stand in it.
func draw_water(ci: CanvasItem, clock: float) -> void:
	for i in _wet.size():
		var q := _wet[i]
		var r := 4.6 + 0.9 * sin(clock * 1.7 + i * 1.3)
		ci.draw_arc(q, r, 0.0, TAU, 14, Color(1, 1, 1, 0.13), 1.0, true)
