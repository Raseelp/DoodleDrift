extends RigidBody2D
## A desk object lying on the paper (pencil, ruler, scissors...), drawn from a sheet of 16 baked headings
## and moved by real 2D physics: the car knocks it, it shoves the others. Round things (pencils) roll
## easily sideways but hardly slide along their length; flat things slide and spin to a stop on the paper.

signal hit_car

const FRAMES := 16

## The camera's turn (rotating cameras): pictures are picked against it so the lighting and the tilt stay
## true on screen, and the shadow keeps falling down-left of the screen.
static var view_rot := 0.0
## Outlines per sheet, worked out once: reading a sheet back is slow and used to stall every spawn.
static var outlines := {}

var info: Dictionary
var sheet: Texture2D
var px := 128
var roller := false
var near := false  # a near miss was already counted
var car: PhysicsBody2D
var spr: Sprite2D
var shadow: Sprite2D
var _frame := -1
var _rot_seen := 0.0


func setup(p_info: Dictionary, p_sheet: Texture2D, p_car: PhysicsBody2D) -> void:
	info = p_info
	sheet = p_sheet
	car = p_car
	px = int(info["px"])
	roller = info["kind"] == "roll"
	var length := float(info["len"])
	var wid := float(info["wid"])
	gravity_scale = 0.0
	mass = clampf(length * wid / 1200.0, 0.25, 5.0)  # bigger things are heavier
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0  # friction with the paper is worked out below
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 5.0 if roller else 3.5
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	mat.friction = 0.4
	physics_material_override = mat
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(func(b: Node):
		if b == car:
			hit_car.emit(self))
	var shape := CollisionShape2D.new()
	if roller:
		var cap := CapsuleShape2D.new()
		cap.radius = maxf(3.0, wid * 0.5)
		cap.height = length
		shape.shape = cap
		shape.rotation = PI * 0.5  # a capsule stands along y; the object lies along x
	else:
		var hull := ConvexPolygonShape2D.new()
		var key := sheet.resource_path
		if not outlines.has(key):
			outlines[key] = _outline(float(info["scale"]))
		hull.points = outlines[key]
		shape.shape = hull
	add_child(shape)
	shadow = _sprite(Color(0.1, 0.08, 0.05, 0.28))
	shadow.show_behind_parent = true
	spr = _sprite(Color.WHITE)
	_show()


func _sprite(col: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = sheet
	s.region_enabled = true
	s.scale = Vector2.ONE * float(info["scale"])
	s.modulate = col
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(s)
	return s


## The object's outline from its first picture: the hull of its solid pixels, in world units.
func _outline(k: float) -> PackedVector2Array:
	var img := sheet.get_image()
	if img.is_compressed():
		img.decompress()
	var pts := PackedVector2Array()
	var step := maxi(2, px / 48)
	for y in range(0, px, step):
		for x in range(0, px, step):
			if img.get_pixel(x, y).a > 0.5:
				pts.append((Vector2(x, y) - Vector2(px, px) * 0.5) * k)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)  # convex_hull repeats the first point
	if hull.size() < 3:
		var h := float(info["len"]) * 0.5
		var w := float(info["wid"]) * 0.5
		hull = PackedVector2Array([Vector2(-h, -w), Vector2(h, -w), Vector2(h, w), Vector2(-h, w)])
	return hull


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var v := state.linear_velocity
	var dt := state.step
	if roller:
		var ax := state.transform.x
		var along := ax * v.dot(ax)
		state.linear_velocity = along * exp(-7.0 * dt) + (v - along) * exp(-0.9 * dt)
	else:
		state.linear_velocity = v * exp(-3.2 * dt)


func _process(_delta: float) -> void:
	if not sleeping or view_rot != _rot_seen:
		_show()


## The baked picture nearest its heading, turned the last few degrees; the shadow falls down-left.
func _show() -> void:
	_rot_seen = view_rot
	var i := int(roundf(fposmod(rotation - view_rot, TAU) / TAU * FRAMES)) % FRAMES
	if i != _frame:
		_frame = i
		var r := Rect2((i % 4) * px, (i / 4) * px, px, px)
		spr.region_rect = r
		shadow.region_rect = r
		spr.rotation = -TAU * i / FRAMES
		shadow.rotation = spr.rotation
	shadow.position = Vector2(-5, 7).rotated(view_rot - rotation)


## Roughly how far a point is from the object's edge (for near misses).
func gap_to(p: Vector2) -> float:
	var length := float(info["len"])
	var wid := float(info["wid"])
	var ax := Vector2.from_angle(rotation) * maxf(0.0, length - wid) * 0.5
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, global_position - ax, global_position + ax)) - wid * 0.5
