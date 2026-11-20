extends SubViewport
## A mute swan rendered live from the same tilted camera as the boat, so it has the same depth: "Animated
## Swan - Rigged & Optimized Game Ready" by GAMICO (Sketchfab, CC BY, see icons/CREDITS.txt). Its legs are
## folded away every frame (the animations are made for land; on the water only the body shows).
## With `nest` on, a nest is built in code round her: a mound of twigs and reed stems with a hollow and
## four pale green-grey eggs. Sitting, she is low in the hollow and the rim hides her body and the eggs;
## standing (set_sit), she rises up out of it and the eggs show.

const VIEW := 3.0  # metres the camera sees across (the spread wings fit)
const LEG_BONES := ["L_Femur_10", "R_Femur_21"]

var render_px := 256
var nest := false
var on_land := false  # walking on the bank: the legs show
var fold: SkeletonModifier3D
var root: Node3D
var swan: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var legs: Array[int] = []
var eggs: Node3D
var _anim := ""
var _sit := 0.0
var _pose := Vector3(INF, INF, INF)  # heading, sit, playing: re-render when it changes


func _ready() -> void:
	size = Vector2i(render_px, render_px)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW
	var tilt := deg_to_rad(Game.boat_tilt)
	cam.rotation_degrees = Vector3(-90.0 + Game.boat_tilt, 0, 0)
	cam.position = Vector3(0, 20.0 * cos(tilt), 20.0 * sin(tilt))
	cam.far = 60.0
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 40, 0)
	sun.light_energy = 1.0
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 0.97, 0.92)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	root = Node3D.new()
	add_child(root)
	var scene := Game.model_scene(Game.SWAN_MODEL)
	if scene:
		swan = scene.instantiate()
		var pivot := Node3D.new()
		pivot.rotation.y = PI * 0.5  # the model faces +Z; turn it to +X like the boat
		pivot.add_child(swan)
		root.add_child(pivot)
		var aps := swan.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			anim = aps[0]
		var sks := swan.find_children("*", "Skeleton3D", true, false)
		if not sks.is_empty():
			skel = sks[0]
			for b in LEG_BONES:
				var i := skel.find_bone(b)
				if i >= 0:
					legs.append(i)
			fold = LegFold.new()
			fold.bones = legs
			fold.active = not on_land
			skel.add_child(fold)
	if nest:
		_build_nest()
	play("Idle")


## Folds the legs right up under the body, after each animated pose.
class LegFold extends SkeletonModifier3D:
	var bones: Array[int] = []

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk:
			for i in bones:
				sk.set_bone_pose_scale(i, Vector3.ONE * 0.001)


## Plays one of the model's animations, looping (Idle, Grooming, WalkForwardStandWing, Flap1, LandAttack…).
func play(name: String, speed := 1.0, loop := true) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if name != _anim:
		_anim = name
		anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		anim.play(name, 0.25)
	anim.speed_scale = speed


## Whether a one-shot animation is still playing.
func playing_once() -> bool:
	return anim != null and anim.is_playing() and anim.current_animation != "" \
		and anim.get_animation(anim.current_animation).loop_mode == Animation.LOOP_NONE


## The nest without her: she has left it, the eggs show.
func empty_nest() -> void:
	if swan:
		swan.get_parent().visible = false
	if eggs:
		eggs.visible = true


## heading: the way the swan faces, in 2D radians.
func set_pose(heading: float) -> void:
	root.rotation = Vector3(0, -heading, 0)


## 1 = sitting low in the nest, 0 = standing up over the eggs.
func set_sit(f: float) -> void:
	_sit = f
	if swan:
		swan.get_parent().position.y = -0.5 * f
	if eggs:
		eggs.visible = f < 0.85


## Where a point on the water (the swan's or the nest's centre) is in the picture.
func anchor() -> Vector2:
	return get_camera_3d().unproject_position(Vector3.ZERO)


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A swan's nest: a broad, low mound of sticks and reed stems with a hollow lined with down, and eggs.
func _build_nest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	var base := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.62
	c.bottom_radius = 0.82
	c.height = 0.22
	c.radial_segments = 24
	base.mesh = c
	base.material_override = _mat(Color("6b5638"))
	base.position = Vector3(0, -0.05, 0)
	add_child(base)
	var hollow := MeshInstance3D.new()
	var h := CylinderMesh.new()
	h.top_radius = 0.34
	h.bottom_radius = 0.3
	h.height = 0.03
	h.radial_segments = 20
	hollow.mesh = h
	hollow.material_override = _mat(Color("cfc6b4"))  # lined with pale down
	hollow.position = Vector3(0, 0.07, 0)
	add_child(hollow)
	# Sticks and reed stems laid round it, in rings, each a little different.
	var colors := [Color("7a6142"), Color("8c7650"), Color("5e4a30"), Color("a08c62"), Color("6f5a3a")]
	for ring in 4:
		var r := 0.38 + ring * 0.13
		var n := 26 + ring * 6
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.1, 0.1)
			var st := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			var rad := rng.randf_range(0.012, 0.024)
			cy.top_radius = rad
			cy.bottom_radius = rad
			cy.height = rng.randf_range(0.3, 0.55)
			cy.radial_segments = 5
			cy.rings = 1
			st.mesh = cy
			st.material_override = _mat(colors[rng.randi() % colors.size()])
			st.position = Vector3(cos(a) * r, 0.06 + 0.07 * (3 - ring) + rng.randf_range(-0.03, 0.03), sin(a) * r)
			# Lying roughly round the ring (tangent), tilted a little.
			st.rotation = Vector3(PI * 0.5 + rng.randf_range(-0.25, 0.25), -a + rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.2))
			add_child(st)
	eggs = Node3D.new()
	add_child(eggs)
	for k in 4:
		var egg := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.075
		s.height = 0.2
		s.radial_segments = 14
		s.rings = 8
		egg.mesh = s
		egg.material_override = _mat(Color("d9dccb"), 0.6)
		var a := TAU * k / 4.0 + 0.4
		egg.position = Vector3(cos(a) * 0.11, 0.12, sin(a) * 0.11)
		egg.rotation = Vector3(PI * 0.5, a, 0)
		eggs.add_child(egg)
