extends SubViewportContainer
## The behind-the-car camera (Tilt). The game itself stays flat: a second 2D viewport films the
## paper around the car from straight above, and that picture is laid on a 3D ground plane. The real 3D car
## model sits on it, and a perspective camera follows from behind. Beyond the filmed patch, a plain sheet
## of the same paper runs out to the horizon, and the patch fades into it at its edges.

const UNIT := 100.0  # world pixels per 3D unit
const PATCH := 1024  # the filmed patch, in pixels
const FILM_SCALE := 0.6  # film pixels per world pixel (the patch covers PATCH / FILM_SCALE of the world)
const AHEAD := 520.0  # the patch is centred this far ahead of the car, where the camera looks
const VIEWS := {
	"tilt": {"back": 3.4, "up": 3.0, "look": 1.6, "fov": 60.0},
}

var game: Node2D
var film: SubViewport  # the flat world, seen from above
var stage: SubViewport  # the 3D scene
var ground: MeshInstance3D
var car: Node3D
var cam: Camera3D
var mode := "tilt"
var cam_dir := 0.0
var center := Vector2.ZERO


func setup(p_game: Node2D, world_2d: World2D, paper_tex: Texture2D, car_model: PackedScene, car_len: float) -> void:
	game = p_game
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = get_viewport_rect().size
	film = SubViewport.new()
	film.size = Vector2i(PATCH, PATCH)
	film.world_2d = world_2d
	film.canvas_cull_mask = 0xFFFFFFFF
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	film.disable_3d = true
	game.add_child(film)  # outside the container, which would show it on screen too
	stage = SubViewport.new()
	stage.own_world_3d = true
	stage.msaa_3d = Viewport.MSAA_DISABLED  # cheaper on phones; the car edges are small
	stage.handle_input_locally = false
	stage.gui_disable_input = true
	add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.92, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 0.97, 0.92)
	e.ambient_light_energy = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.93, 0.92, 0.9)
	e.fog_density = 0.018
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 40, 0)
	stage.add_child(sun)
	# The endless sheet under everything.
	var sheet := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	sheet.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = paper_tex
	sm.uv1_scale = Vector3(400.0 * UNIT / 1024.0, 400.0 * UNIT / 1024.0, 1)
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	sheet.material_override = sm
	sheet.position.y = -0.003
	stage.add_child(sheet)
	sheet.set_meta("follow", true)
	sheet.name = "Sheet"
	# The filmed patch, fading into the sheet at its edges.
	ground = MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2.ONE * PATCH / FILM_SCALE / UNIT
	ground.mesh = gm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D patch : source_color, filter_linear;
void fragment() {
	vec4 c = texture(patch, UV);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	ALBEDO = c.rgb;
	ALPHA = smoothstep(0.0, 0.1, edge);
}
"""
	mat.shader = sh
	mat.set_shader_parameter("patch", film.get_texture())
	ground.material_override = mat
	stage.add_child(ground)
	# The car.
	car = Node3D.new()
	stage.add_child(car)
	var m: Node3D = car_model.instantiate()
	car.add_child(m)
	var box := _bounds(m, Transform3D.IDENTITY)
	var turn := box.size.z > box.size.x  # make its long side run along +x (heading 0), as the baked pictures do
	var length := maxf(box.size.x, box.size.z)
	var k := car_len / UNIT / maxf(length, 0.001)
	m.scale = Vector3.ONE * k
	var c := box.get_center()
	m.position = Vector3(-c.x * k, -box.position.y * k, -c.z * k)
	if turn:
		m.rotation.y = PI * 0.5
		m.position = Vector3(-c.z * k, m.position.y, c.x * k)
	_low_detail(m)
	cam = Camera3D.new()
	cam.far = 120.0
	cam.near = 0.05
	stage.add_child(cam)
	cam.make_current()


func _exit_tree() -> void:
	if is_instance_valid(film):
		film.queue_free()


func set_mode(m: String, car_dir: float) -> void:
	mode = m
	cam_dir = car_dir
	cam.fov = VIEWS[mode]["fov"]


## Called every frame by the game with the car's place, nose and travel.
func follow(delta: float, pos: Vector2, heading: float, travel: float) -> void:
	stage.size = Vector2i(size)
	cam_dir = lerp_angle(cam_dir, travel, 1.0 - exp(-delta * 2.2))
	var d := Vector2.from_angle(cam_dir)
	center = pos + d * AHEAD
	film.canvas_transform = Transform2D(0.0, Vector2.ONE * FILM_SCALE, 0.0, Vector2(PATCH, PATCH) * 0.5 - center * FILM_SCALE)
	ground.position = Vector3(center.x / UNIT, 0.0, center.y / UNIT)
	var p := Vector3(pos.x / UNIT, 0.0, pos.y / UNIT)
	car.position = p
	car.rotation.y = -heading
	var v: Dictionary = VIEWS[mode]
	var d3 := Vector3(d.x, 0.0, d.y)
	cam.position = p - d3 * float(v["back"]) + Vector3.UP * float(v["up"])
	cam.look_at(p + d3 * float(v["look"]), Vector3.UP)
	var sheet := stage.get_node("Sheet") as Node3D
	sheet.position = Vector3(snappedf(p.x, 10.24), -0.003, snappedf(p.z, 10.24))  # keeps the grain still


## Uses the model's lighter versions (made on import): this car is very detailed for a phone.
func _low_detail(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).lod_bias = 0.05
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_low_detail(ch)


func _bounds(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		box = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for ch in n.get_children():
		var cb := _bounds(ch, t)
		if cb.size == Vector3.ZERO:
			continue
		if first:
			box = cb
			first = false
		else:
			box = box.merge(cb)
	return box
