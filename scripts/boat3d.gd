extends SubViewport
## Test: the boat as a small 3D model, rendered from straight above into a texture the 2D lake draws.
## The model is built from code: a lofted wooden hull with ribs, a seat, two oars and a bow lamp.
## It leans into turns, lifts its bow with speed and bobs; on a crash it splits in two and sinks.

const SIZE := 448  # pixels; the camera sees 110 units, about 4 px per unit
const VIEW := 110.0
## The boat model: "Fishing Boat" by CharlieCatling (Sketchfab, Free Standard licence), used as it comes.
## If the file is missing, the code-built rowboat is used instead.
const MODEL_PATH := "res://models/fishing_boat.glb"
const MODEL_LEN := 60.0  # model length in render units
const LENGTH_FROM := -20.0
const LENGTH_TO := 24.0
const CUT := 2.0  # where the hull breaks in a wreck

var root: Node3D
var front: Node3D
var back: Node3D
var oars: Array[Node3D] = []
var lamp: MeshInstance3D
var wrecking := false
var wreck_t := 0.0
var _mats: Array[StandardMaterial3D] = []  # every material, so a wreck can make them fade
var _front_mats: Array[StandardMaterial3D] = []
var _back_mats: Array[StandardMaterial3D] = []
var _oar_mats: Array[StandardMaterial3D] = []
var model: Node3D  # the imported boat, when the file is there
var model_anim: AnimationPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps sinking under the game over screen
	size = Vector2i(SIZE, SIZE)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_4X

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW
	var tilt := deg_to_rad(Game.boat_tilt)
	cam.far = 400.0
	cam.rotation_degrees = Vector3(-90.0 + Game.boat_tilt, 0, 0)  # 0 tilt: straight down, screen right = +X, screen down = +Z
	cam.position = Vector3(0, 150.0 * cos(tilt), 150.0 * sin(tilt))
	add_child(cam)

	# Sun from the top right like the map, soft enough to sit with the drawn lake.
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


func _build() -> void:
	for c in root.get_children():
		c.queue_free()
	model = null
	if ResourceLoader.exists(MODEL_PATH):
		# The model's bow points to -Z and it is 8.6 units long: turn the bow to +X and scale it up.
		model = (load(MODEL_PATH) as PackedScene).instantiate()
		var pivot := Node3D.new()
		pivot.rotation.y = -PI * 0.5  # the model's bow points to -Z; turn it to +X
		pivot.add_child(model)
		root.add_child(pivot)
		var box := AABB()
		var first := true
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m
			var b: AABB = mi.transform * mi.get_aabb()
			var n: Node = mi.get_parent()
			while n != model and n is Node3D:
				b = (n as Node3D).transform * b
				n = n.get_parent()
			box = b if first else box.merge(b)
			first = false
		var length := maxf(box.size.x, box.size.z)
		model.position = Vector3(-box.get_center().x, 0.0, -box.get_center().z)
		pivot.scale = Vector3.ONE * (MODEL_LEN / length)
		front = pivot
		back = pivot
		# The file furls the sail with a shape key (morph_2 = 1); open it: every shape key at 0.
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m
			var mat := mi.mesh.surface_get_material(0)
			if mat and "Sail" in mat.resource_name:
				for i in mi.mesh.get_blend_shape_count():
					mi.set_blend_shape_value(i, 0.0)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			model_anim = players[0]
			var anim_name: StringName = model_anim.get_animation_list()[0]
			var anim := model_anim.get_animation(anim_name)
			# Keep the oars and rudder moving; drop the tracks that furl the sail.
			for t in range(anim.get_track_count() - 1, -1, -1):
				var path := String(anim.track_get_path(t))
				if "morph" in path or "Sail" in path or anim.track_get_type(t) == Animation.TYPE_BLEND_SHAPE:
					anim.remove_track(t)
			anim.loop_mode = Animation.LOOP_LINEAR
			model_anim.play(anim_name)
		return
	oars.clear()
	_mats.clear()
	_front_mats.clear()
	_back_mats.clear()
	_oar_mats.clear()
	front = Node3D.new()
	back = Node3D.new()
	root.add_child(back)
	root.add_child(front)
	back.add_child(_hull_mesh(LENGTH_FROM, CUT, _back_mats))
	front.add_child(_hull_mesh(CUT, LENGTH_TO, _front_mats))

	var wood := _mat(Color("7a5230"), _front_mats)
	var seat := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(3.4, 0.8, 16.0)
	seat.mesh = sb
	seat.material_override = wood
	seat.position = Vector3(7.5, -0.4, 0)
	front.add_child(seat)
	var transom := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.2, 4.0, 14.0)
	transom.mesh = tb
	transom.material_override = _mat(Color("6b4626"), _back_mats)
	transom.position = Vector3(-19.4, -1.6, 0)
	back.add_child(transom)

	for side in [-1.0, 1.0]:
		var oar := Node3D.new()
		oar.position = Vector3(2, 0.6, side * 11.6)
		oar.rotation.y = -side * 0.12
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.35
		cm.height = 22.0
		shaft.mesh = cm
		shaft.rotation.z = PI * 0.5
		shaft.material_override = _mat(Color("7a5634"), _oar_mats)
		oar.add_child(shaft)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(5.5, 0.3, 2.2)
		blade.mesh = bm
		blade.position = Vector3(12.5, 0, 0)
		blade.material_override = shaft.material_override
		oar.add_child(blade)
		root.add_child(oar)
		oars.append(oar)

	lamp = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 2.6
	lamp.mesh = sm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color("ffe7a6")
	lamp.material_override = lm
	lamp.position = Vector3(17.5, 1.8, 0)
	front.add_child(lamp)


func _mat(c: Color, group: Array[StandardMaterial3D]) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.append(m)
	group.append(m)
	return m


## Half-beam, depth and sheer (rise of the rim) at a point along the boat.
func _beam(x: float) -> float:
	if x > 2.0:
		return 10.5 * (1.0 - pow((x - 2.0) / 22.0, 1.7))
	if x < -14.0:
		return lerpf(7.2, 10.0, (x + 20.0) / 6.0)
	return 10.5 - 0.5 * absf(x + 6.0) / 8.0


func _depth(x: float) -> float:
	if x > 2.0:
		return 5.5 * (1.0 - pow((x - 2.0) / 22.0, 2.6)) + 0.4
	return lerpf(4.8, 5.5, clampf((x + 20.0) / 10.0, 0.0, 1.0))


func _sheer(x: float) -> float:
	return 1.6 * pow(clampf((x - 4.0) / 20.0, 0.0, 1.0), 2.0) + 0.5 * clampf((-x - 14.0) / 6.0, 0.0, 1.0)


## A lofted hull section between two stations: outer planking, inner boards with ribs, and the rim.
func _hull_mesh(x0: float, x1: float, group: Array[StandardMaterial3D]) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations := int(ceil((x1 - x0) / 1.0))
	const SEG := 12
	var outer: Array = []
	var inner: Array = []
	for i in stations + 1:
		var x := lerpf(x0, x1, float(i) / stations)
		var b := _beam(x)
		var d := _depth(x)
		var h := _sheer(x)
		var ro: Array = []
		var ri: Array = []
		for k in SEG + 1:
			var th := PI * float(k) / SEG
			var s := pow(sin(th), 0.65)
			ro.append(Vector3(x, h - d * s, -b * cos(th)))
			ri.append(Vector3(x, h - 0.6 - d * 0.78 * s, -b * 0.86 * cos(th)))
		outer.append(ro)
		inner.append(ri)
	var plank_a := Color("9a6a3a")
	var plank_b := Color("8a5c32")
	var board := Color("c79a64")
	var rib := Color("7a5230")
	var rim := Color("5a3a1f")
	for i in stations:
		var xm := lerpf(x0, x1, (i + 0.5) / stations)
		var is_rib := int(floor(xm + 100.0)) % 4 == 0
		for k in SEG:
			var oc := plank_a if k % 2 == 0 else plank_b
			_quad(st, outer[i][k], outer[i + 1][k], outer[i + 1][k + 1], outer[i][k + 1], oc)
			var ic := rib if is_rib else board.darkened(0.06 if k % 2 == 0 else 0.0)
			_quad(st, inner[i][k + 1], inner[i + 1][k + 1], inner[i + 1][k], inner[i][k], ic)
		_quad(st, outer[i][0], outer[i + 1][0], inner[i + 1][0], inner[i][0], rim)
		_quad(st, inner[i][SEG], inner[i + 1][SEG], outer[i + 1][SEG], outer[i][SEG], rim)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.append(m)
	group.append(m)
	mi.material_override = m
	return mi


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## Pose from the lake every frame: heading in 2D radians, lean (roll) and pitch in radians, bob in units.
func set_pose(heading: float, lean: float, pitch: float, bob: float) -> void:
	if wrecking:
		return
	root.rotation = Vector3(0, -heading, 0)
	root.rotate_object_local(Vector3.RIGHT, lean)
	root.rotate_object_local(Vector3.BACK, pitch)
	root.position.y = bob


func set_lamp(on: float) -> void:
	if lamp and is_instance_valid(lamp) and not model:
		(lamp.material_override as StandardMaterial3D).albedo_color = Color("ffe7a6").lerp(Color("6e4a2a"), 1.0 - on)


## Crash: the hull breaks at CUT into a bow half and a stern half that turn apart and sink.
func wreck() -> void:
	wrecking = true
	wreck_t = 0.0
	for m in _mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func reset() -> void:
	wrecking = false
	wreck_t = 0.0
	root.rotation = Vector3.ZERO
	_build()


## How sunk the boat is, 0..1, for the lake to fade it out.
func sunk() -> float:
	if not wrecking:
		return 0.0
	return clampf((wreck_t - (0.6 if model else 0.45)) / (2.2 if model else 1.3), 0.0, 1.0)


func _process(delta: float) -> void:
	var live := not get_tree().paused or (wrecking and sunk() < 1.0)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	if not wrecking:
		return
	wreck_t += delta
	var s := wreck_t
	if model:
		# Whole boat: it heels over, the bow dips and it settles; the lake fades it out as it goes under.
		var kk := 1.0 - pow(1.0 - clampf(s / 1.4, 0.0, 1.0), 3.0)
		var sink := clampf((s - 0.6) / 2.2, 0.0, 1.0)
		var p := front
		p.rotation = Vector3(0.0, -PI * 0.5, 0.0)
		p.rotate_object_local(Vector3.FORWARD, 1.1 * kk)
		p.rotate_object_local(Vector3.RIGHT, 0.5 * sink)
		p.position = Vector3(4.0 * kk, -8.0 * sink, 0.0)
		if model_anim:
			model_anim.speed_scale = maxf(0.0, 1.0 - kk)
		return
	var k := 1.0 - pow(1.0 - clampf(s / 0.9, 0.0, 1.0), 3.0)
	var sink_f := clampf((s - 0.45) / 1.3, 0.0, 1.0)
	var sink_b := clampf((s - 0.9) / 1.8, 0.0, 1.0) * 0.85
	front.position = Vector3(9.0 * k, -6.0 * sink_f, 13.0 * k)
	front.rotation = Vector3(0.5 * k, 0.9 * k, -1.0 * sink_f)
	back.position = Vector3(-8.0 * k, -5.0 * sink_b, -10.0 * k)
	back.rotation = Vector3(-0.4 * k, -0.8 * k, 0.8 * sink_b)
	for i in oars.size():
		var o: Node3D = oars[i]
		var side := -1.0 if i == 0 else 1.0
		o.position = Vector3(2.0 - 2.0 * k, 0.6, side * (11.6 + 9.0 * k))
		o.rotation.y = -side * (0.12 + 1.4 * k)
	for m in _front_mats:
		m.albedo_color.a = 1.0 - 0.92 * sink_f
	for m in _back_mats:
		m.albedo_color.a = 1.0 - 0.92 * sink_b
	for m in _oar_mats:
		m.albedo_color.a = 1.0 - 0.8 * clampf((s - 1.0) / 2.0, 0.0, 1.0)
	set_lamp(1.0 - sink_f)
