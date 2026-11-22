extends SubViewport
## Turns a 3D ship model into a ring of flat pictures, one per heading, seen from the same tilted camera as
## the player's boat. Many ships can then be drawn as cheap sprites instead of each needing its own 3D view.
## bake() renders one heading a frame and fills `frames`; `done` is emitted when all are ready.

signal done

const VIEW := 6.0  # how much of the model the camera sees (model units, after fitting)

## Baked rings of pictures, kept for the whole session: model path -> frames.
static var cache := {}

var model_path := ""
var heading0 := 0.0  # the heading the model's bow points at in the first picture (measured per model)
var px := 128  # each picture's size
var count := 32  # headings round the circle
var frames: Array[Texture2D] = []
var _pivot: Node3D


func _ready() -> void:
	size = Vector2i(px, px)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
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
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 0.97, 0.92)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	_pivot = Node3D.new()
	add_child(_pivot)
	var scene := load(model_path) as PackedScene
	if scene == null:
		return
	var m: Node3D = scene.instantiate()
	_pivot.add_child(m)
	# Fit: the model's longest side across most of the picture, centred, sitting on the water line.
	var box := _bounds(m, Transform3D.IDENTITY)
	var longest := maxf(box.size.x, box.size.z)
	var k := VIEW * 0.82 / maxf(longest, 0.001)
	m.scale = Vector3.ONE * k
	var c := box.get_center()
	m.position = Vector3(-c.x * k, -box.position.y * k - box.size.y * k * 0.25, -c.z * k)
	# Bow along +x (the game's heading 0): the long side decides which way the hull runs.
	if box.size.z > box.size.x:
		_pivot.rotation.y = 0.0
		m.rotation.y = PI * 0.5
		m.position = Vector3(-c.z * k, m.position.y, c.x * k)


func bake() -> void:
	if cache.has(model_path):
		frames = cache[model_path]
		done.emit()
		return
	frames.clear()
	for i in count:
		_pivot.rotation.y = -TAU * i / count
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return  # freed half way (the screen it was baking for has gone)
		frames.append(ImageTexture.create_from_image(get_texture().get_image()))
	cache[model_path] = frames
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	done.emit()


## Whether every heading's picture is baked.
func is_ready() -> bool:
	return frames.size() == count


## The picture for a heading (radians, 0 = +x).
func frame(heading: float) -> Texture2D:
	if not is_ready():
		return null
	var i := int(roundf(fposmod(heading - heading0, TAU) / TAU * count)) % count
	return frames[i]


func _bounds(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		box = b
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
