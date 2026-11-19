extends SubViewport
## The pickup, its boat trailer and (when it is on board) the fishing boat, as one 3D rig rendered into
## a texture the 2D map and lakes draw. Models: "Low Poly Car - Chevrolet C10 Pickup 1963" by ROH3D and
## "Boat Trailer" by BoatUS Foundation (both CC BY, see icons/CREDITS.txt), and the game's fishing boat.
## The pickup gets a few things of its own: a roof rack with fishing rods, a cool box, a fuel can and a
## coil of rope in the bed, a whip antenna and mud flaps.
## The rig turns about the tow hitch (the origin): the pickup lies along +X, the trailer along -X and
## swings by `trailer_angle`.

const BOAT_LEN := 8.4  # metres, so it sits from the bow stop to just past the trailer's end
## The pickup is drawn larger than life (its 4.9 m becomes about 8.5 m), nearly the boat's length, so it
## reads at the game's small sizes. Its extras grow with it.
const PICKUP_SCALE := 1.75

var render_px := 320
var view_m := 26.0  # metres the camera sees across
var tilt := 35.0  # camera tilt from straight down, degrees
var show_boat := true

var cam: Camera3D
var root: Node3D
var truck: Node3D
var truck_root: Node3D  # the pickup and its extras, scaled up together
var lamps: Array = []  # two markers at the pickup's headlamps
var trailer: Node3D
var boat: Node3D
var _pose := Vector2(INF, INF)


func _ready() -> void:
	size = Vector2i(render_px, render_px)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ONCE  # and again whenever the pose changes (set_pose)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_m
	cam.far = 400.0
	var t := deg_to_rad(tilt)
	cam.rotation_degrees = Vector3(-90.0 + tilt, 0, 0)
	cam.position = Vector3(0, 150.0 * cos(t), 150.0 * sin(t))
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 40, 0)
	sun.light_energy = 1.05
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 0.97, 0.92)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)

	root = Node3D.new()
	add_child(root)
	_build()


## The hitch's place in the rendered picture, for drawing the rig with its hitch on a given point.
func anchor() -> Vector2:
	return cam.unproject_position(root.global_position)


## The headlamps in the rendered picture, and the direction the light goes there: [left, right, angle].
func headlamps() -> Array:
	if lamps.is_empty():
		return []
	var a: Vector3 = lamps[0].global_position
	var b: Vector3 = lamps[1].global_position
	var fwd := root.global_transform.basis.x
	var pa := cam.unproject_position(a)
	var ahead := cam.unproject_position(a + fwd * 4.0)
	return [pa, cam.unproject_position(b), (ahead - pa).angle()]


## heading: the pickup's direction in 2D radians; trailer_angle: the trailer's swing from straight.
func set_pose(heading: float, trailer_angle: float) -> void:
	if root:
		root.rotation = Vector3(0, -heading, 0)
		trailer.rotation = Vector3(0, -trailer_angle, 0)
		if Vector2(heading, trailer_angle) != _pose:
			_pose = Vector2(heading, trailer_angle)
			render_target_update_mode = SubViewport.UPDATE_ONCE


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Adds a model under `parent`, turned so its front faces +X, scaled, then moved so that the point picked
## by `place` (a function of its bounds) sits at `at`.
func _place(scene: PackedScene, parent: Node3D, turn: float, scale_to: float, place: Callable, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	if scene == null:
		return pivot  # the model is missing: leave that part out
	var model: Node3D = scene.instantiate()
	pivot.add_child(model)
	pivot.rotation.y = turn
	pivot.scale = Vector3.ONE * scale_to
	var b := _bounds(pivot)
	pivot.position += at - place.call(b)
	return pivot


func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size3: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size3
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build() -> void:
	# Pickup: front to +X, its rear bumper just ahead of the hitch, wheels on the ground.
	truck_root = Node3D.new()
	root.add_child(truck_root)
	truck = _place(Game.model_scene(Game.PICKUP_MODEL), truck_root, PI * 0.5, 0.01,
		func(b: AABB) -> Vector3: return Vector3(b.position.x, b.position.y, b.get_center().z), Vector3.ZERO)
	var tb := _bounds(truck)
	_personalise(tb)
	for side in [-1.0, 1.0]:
		var m := Node3D.new()
		m.position = Vector3(tb.end.x - 0.1, tb.position.y + tb.size.y * 0.42, tb.get_center().z + side * tb.size.z * 0.33)
		truck_root.add_child(m)
		lamps.append(m)
	truck_root.scale = Vector3.ONE * PICKUP_SCALE
	truck_root.position = Vector3(0.2, 0, 0)  # its rear bumper just ahead of the hitch
	# Trailer: its tongue on the hitch, swinging about it.
	trailer = Node3D.new()
	root.add_child(trailer)
	var tr := _place(Game.model_scene(Game.TRAILER_MODEL), trailer, PI * 0.5, 1.0,
		func(b: AABB) -> Vector3: return Vector3(b.end.x, b.position.y, b.get_center().z), Vector3(0, 0, 0))
	var trb := _bounds(tr)
	if show_boat:
		var scene := Game.boat_scene()
		if scene:
			var len_now := 9.85
			boat = _place(scene, trailer, -PI * 0.5, BOAT_LEN / len_now,
				func(b: AABB) -> Vector3: return Vector3(b.end.x, b.position.y, b.get_center().z), Vector3(trb.end.x - 3.7, 1.0, trb.get_center().z))
			for a in boat.find_children("*", "AnimationPlayer", true, false):
				(a as AnimationPlayer).stop()
			# Two orange ratchet straps over the hull down to the trailer frame.
			var orange := _mat(Color("e8752a"), 0.8)
			var bb := _bounds(boat)
			for x in [bb.position.x + bb.size.x * 0.3, bb.position.x + bb.size.x * 0.68]:
				_box(trailer, Vector3(0.12, 0.04, bb.size.z * 0.98), Vector3(x, bb.position.y + bb.size.y * 0.22, bb.get_center().z), orange)


## A few things that make the pickup someone's own.
func _personalise(b: AABB) -> void:
	var len := b.size.x
	var top := b.end.y
	var front := b.end.x
	var rear := b.position.x
	var z := b.get_center().z
	var bed_x := rear + len * 0.2
	var bed_y := b.position.y + b.size.y * 0.47
	var black := _mat(Color("1b1c1e"), 0.6, 0.3)
	# Roof rack: two bars on the cab, two fishing rods along them.
	var cab_x := rear + len * 0.55
	for dx in [-0.35, 0.35]:
		_box(truck_root, Vector3(0.06, 0.05, b.size.z * 0.82), Vector3(cab_x + dx, top + 0.04, z), black)
	for dz in [-0.25, 0.1]:
		_cyl(truck_root, 0.018, 3.2, Vector3(cab_x + 0.4, top + 0.09, z + dz), Vector3(0, 0, PI * 0.5), _mat(Color("2b2b2b"), 0.4, 0.2))
		_cyl(truck_root, 0.05, 0.12, Vector3(cab_x - 0.85, top + 0.09, z + dz), Vector3(0, 0, PI * 0.5), _mat(Color("c9c9c9"), 0.3, 0.8))
	# In the bed: a white cool box with a blue lid, a red fuel can, a coil of rope.
	_box(truck_root, Vector3(0.62, 0.42, 0.42), Vector3(bed_x + 0.9, bed_y + 0.21, z - 0.42), _mat(Color("f0efe8"), 0.5))
	_box(truck_root, Vector3(0.64, 0.08, 0.44), Vector3(bed_x + 0.9, bed_y + 0.45, z - 0.42), _mat(Color("2f6fb5"), 0.5))
	_box(truck_root, Vector3(0.36, 0.46, 0.18), Vector3(bed_x + 0.2, bed_y + 0.23, z + 0.55), _mat(Color("b8322a"), 0.45, 0.2))
	var rope := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.16
	tor.outer_radius = 0.26
	rope.mesh = tor
	rope.material_override = _mat(Color("c9a46a"), 0.9)
	rope.position = Vector3(bed_x - 0.15, bed_y + 0.05, z - 0.3)
	truck_root.add_child(rope)
	# Whip antenna on the front fender, mud flaps behind the rear wheels.
	_cyl(truck_root, 0.012, 1.3, Vector3(front - len * 0.18, b.position.y + b.size.y * 0.55 + 0.65, b.end.z - 0.12), Vector3(0, 0, -0.12), black)
	for side in [b.position.z + 0.18, b.end.z - 0.18]:
		_box(truck_root, Vector3(0.03, 0.35, 0.3), Vector3(rear + len * 0.12, b.position.y + 0.3, side), black)
