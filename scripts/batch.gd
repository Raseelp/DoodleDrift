extends RefCounted
## Collects shapes (polygons, circles, lines, arcs) into one triangle list and draws it with a single draw
## call: drawn one by one, every polygon, circle and line costs a draw call of its own. Edges get a 1 px
## rim that fades to clear, standing in for antialiasing. Shapes are placed through xf, like
## CanvasItem.draw_set_transform.

var verts := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var xf := Transform2D.IDENTITY


func set_transform(pos: Vector2, rot: float, scl: Vector2) -> void:
	xf = Transform2D(rot, scl, 0.0, pos)


func reset_transform() -> void:
	xf = Transform2D.IDENTITY


## A filled convex or concave polygon (triangulated), with a soft rim.
func poly(pts: PackedVector2Array, col: Color) -> void:
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri.is_empty():
		return
	var base := verts.size()
	for p in pts:
		verts.append(xf * p)
		cols.append(col)
	for t in tri:
		idx.append(base + t)
	_rim(pts, col, true)


func circle(c: Vector2, r: float, col: Color) -> void:
	if r <= 0.0:
		return
	var pts := PackedVector2Array()
	var seg := clampi(int(r * xf.get_scale().x * 0.9), 10, 32)
	for k in seg:
		pts.append(c + Vector2.from_angle(TAU * k / seg) * r)
	var base := verts.size()
	verts.append(xf * c)
	cols.append(col)
	for p in pts:
		verts.append(xf * p)
		cols.append(col)
	for k in seg:
		idx.append_array([base, base + 1 + k, base + 1 + (k + 1) % seg])
	_rim(pts, col, true)


## A line of width w (in screen pixels after xf's scale), soft at its sides.
func line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var pa := xf * a
	var pb := xf * b
	var d := pb - pa
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal()
	var hw := maxf(w * xf.get_scale().x * 0.5 - 0.5, 0.0)
	var clear := Color(col, 0.0)
	var base := verts.size()
	# outer-left, inner-left, inner-right, outer-right at each end
	for p in [pa, pb]:
		verts.append(p + n * (hw + 1.0))
		verts.append(p + n * hw)
		verts.append(p - n * hw)
		verts.append(p - n * (hw + 1.0))
		cols.append_array([clear, col, col, clear])
	for s in 3:
		idx.append_array([base + s, base + s + 1, base + 4 + s, base + s + 1, base + 5 + s, base + 4 + s])


func arc(c: Vector2, r: float, a0: float, a1: float, seg: int, col: Color, w: float) -> void:
	var prev := c + Vector2.from_angle(a0) * r
	for k in range(1, seg + 1):
		var p := c + Vector2.from_angle(lerpf(a0, a1, float(k) / seg)) * r
		line(prev, p, col, w)
		prev = p


## Draws everything collected onto ci and starts empty again.
func flush(ci: CanvasItem) -> void:
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, verts, cols)
	verts = PackedVector2Array()
	cols = PackedColorArray()
	idx = PackedInt32Array()
	xf = Transform2D.IDENTITY


## A 1 px band outside a closed outline, fading to clear (the outline's own vertices are already added).
func _rim(pts: PackedVector2Array, col: Color, closed: bool) -> void:
	var m := pts.size()
	if m < 3:
		return
	var clear := Color(col, 0.0)
	# Which way is outward: by the outline's winding.
	var area := 0.0
	for k in m:
		area += pts[k].cross(pts[(k + 1) % m])
	var out_sign := 1.0 if area < 0.0 else -1.0
	var base := verts.size()
	for k in m:
		var prev := xf * pts[(k - 1 + m) % m]
		var cur := xf * pts[k]
		var next := xf * pts[(k + 1) % m]
		var nrm := ((next - prev).orthogonal().normalized()) * out_sign
		verts.append(cur - nrm * 0.5)
		verts.append(cur + nrm * 0.6)
		cols.append(col)
		cols.append(clear)
	var last := m if closed else m - 1
	for k in last:
		var a := base + k * 2
		var b := base + ((k + 1) % m) * 2
		idx.append_array([a, a + 1, b + 1, a, b + 1, b])
