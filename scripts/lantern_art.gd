extends SubViewport
## The storm lantern: a small 3D model built in code (painted tank, brass rims, a glass globe in a wire
## guard, cap and chimney, a wire handle, on a wooden float), rendered once from the boat's camera angle,
## unlit and lit, into two textures the lakes draw. Rendering only twice keeps it free during play.

signal done(unlit: ImageTexture, lit: ImageTexture, anchor: Vector2, glass: Vector2)

const SIZE := 192  # pixels; the camera sees VIEW units
const VIEW := 13.0
const GLASS_Y := 4.2  # height of the globe's centre, where the flame burns
## Camera tilt from straight down. Lower than the boat's, so the lantern shows its side: from above,
## the cap hides the glass and it stops reading as a lantern.
const TILT := 62.0

var cam: Camera3D
var glass_mat: StandardMaterial3D
var flame: MeshInstance3D
var inner_light: OmniLight3D
var _mats := {}


func _ready() -> void:
	size = Vector2i(SIZE, SIZE)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW
	cam.far = 200.0
	var tilt := deg_to_rad(TILT)
	cam.rotation_degrees = Vector3(-90.0 + TILT, 0, 0)
	var look := Vector3(0, 4.3, 0)
	cam.position = look + Vector3(0, 80.0 * cos(tilt), 80.0 * sin(tilt))
	add_child(cam)

	# The same light as the boat: sun from the top right, soft ambient.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
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

	_build()
	_render.call_deferred()


func _mat(key: String, col: Color, metal: float, rough: float) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = metal
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


func _add(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _cyl(r_top: float, r_bot: float, h: float, y: float, mat: Material) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 32
	return _add(m, Vector3(0, y + h * 0.5, 0), mat)


func _ring(r: float, thick: float, y: float, mat: Material) -> void:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 40
	t.ring_segments = 8
	_add(t, Vector3(0, y, 0), mat)


## A thin rod from a to b (the wire guard and the handle are made of these).
func _rod(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = a.distance_to(b)
	m.radial_segments = 6
	m.rings = 1
	var mi := _add(m, (a + b) * 0.5, mat)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	mi.basis = Basis(side, up, side.cross(up).normalized()).orthonormalized()


func _build() -> void:
	var wood := _mat("wood", Color("6b4a2f"), 0.0, 0.85)
	var wood_dark := _mat("wood_dark", Color("4a3220"), 0.0, 0.9)
	var paint := _mat("paint", Color("2b3833"), 0.45, 0.42)
	var brass := _mat("brass", Color("b98a3e"), 0.85, 0.32)
	var wire := _mat("wire", Color("1d2622"), 0.6, 0.45)

	# Float: two planks of wood under a round deck.
	_cyl(2.9, 3.0, 0.5, 0.0, wood_dark)
	_cyl(2.7, 2.8, 0.25, 0.5, wood)
	# Tank, brass band, burner.
	_cyl(1.85, 2.15, 1.5, 0.75, paint)
	_ring(1.95, 0.09, 2.25, brass)
	_cyl(0.55, 0.65, 0.45, 2.25, brass)
	# Glass globe, a little bulged.
	var globe := SphereMesh.new()
	globe.radius = 1.75
	globe.height = 3.9
	globe.radial_segments = 32
	globe.rings = 16
	glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.78, 0.88, 0.9, 0.3)
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.1
	_add(globe, Vector3(0, GLASS_Y, 0), glass_mat)
	# Flame (shown when lit).
	var fm := SphereMesh.new()
	fm.radius = 0.38
	fm.height = 1.4
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.93, 0.7)
	flame = _add(fm, Vector3(0, 3.35, 0), fmat)
	flame.visible = false
	# Wire guard: bowed bars round the glass, a ring at its waist.
	for k in 6:
		var a := TAU * k / 6.0 + 0.26
		var d := Vector3(cos(a), 0, sin(a))
		var pts := [Vector3(0, 2.3, 0) + d * 1.9, Vector3(0, 3.3, 0) + d * 2.2, Vector3(0, 4.3, 0) + d * 2.25,
			Vector3(0, 5.3, 0) + d * 2.05, Vector3(0, 6.05, 0) + d * 1.55]
		for i in pts.size() - 1:
			_rod(pts[i], pts[i + 1], 0.07, wire)
	_ring(2.24, 0.06, 4.3, wire)
	# Cap with its brass rim, chimney and top.
	_ring(1.9, 0.08, 6.1, brass)
	_cyl(1.0, 2.0, 0.9, 6.1, paint)
	_cyl(0.5, 0.55, 0.65, 7.0, paint)
	_cyl(0.85, 0.85, 0.12, 7.65, paint)
	# Bail handle: a wire arc over the top, pinned at the guard ring.
	var prev := Vector3(-2.3, 4.3, 0)
	for k in range(1, 17):
		var ang := PI * float(k) / 16.0
		var pt := Vector3(-2.3 * cos(ang), 4.3 + 4.4 * sin(ang), 0)
		_rod(prev, pt, 0.075, wire)
		prev = pt
	# A warm light inside, used for the lit picture: it catches the cap, the guard and the float.
	inner_light = OmniLight3D.new()
	inner_light.position = Vector3(0, 3.8, 0)
	inner_light.light_color = Color(1.0, 0.72, 0.4)
	inner_light.light_energy = 2.2
	inner_light.omni_range = 7.0
	inner_light.visible = false
	add_child(inner_light)


func _render() -> void:
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var unlit := get_texture().get_image()
	# Lit: glowing glass, the flame and the inner light.
	glass_mat.albedo_color = Color(1.0, 0.66, 0.3, 0.85)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.5, 0.16)
	glass_mat.emission_energy_multiplier = 1.25
	flame.visible = true
	inner_light.visible = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var lit := get_texture().get_image()
	for img in [unlit, lit]:
		img.generate_mipmaps()
	var anchor := cam.unproject_position(Vector3.ZERO)
	var glass := cam.unproject_position(Vector3(0, GLASS_Y, 0))
	done.emit(ImageTexture.create_from_image(unlit), ImageTexture.create_from_image(lit), anchor, glass)
	queue_free()
