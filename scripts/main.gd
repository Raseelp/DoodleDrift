extends Node
## Starts Doodle Drift: home is the start line of a fresh page (drift.gd with start_home), and a run goes
## straight on from there. "Drive again" starts a new run directly.

const Drift = preload("res://scripts/drift.gd")

var current: Node


func _ready() -> void:
	show_home()


func show_home() -> void:
	start_run(true)


func start_run(home := false) -> void:
	var s: Node = Drift.new()
	s.start_home = home
	s.home_requested.connect(show_home)
	s.again_requested.connect(_again)
	_swap(s)


## Drive again (after a crash, or "start over"): the screen as it is now is kept as a picture, the new run
## is laid under it straight away, and the picture is rubbed out from the top right down to the bottom in
## zigzag strokes, uncovering the new page.
func _again() -> void:
	if turning:
		return
	turning = true
	var shot := ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var wipe := EraseWipe.new()
	wipe.shot = shot
	wipe.finished = func():
		layer.queue_free()
		turning = false
	layer.add_child(wipe)
	start_run(false)


var turning := false


## The old screen (a picture) rubbed out the way a hand rubs a page clean: six strokes from the top right,
## right to left then back, each a little lower, bowing down in the middle the way an arm swings. Each
## stroke picks up speed, slows into the turn and pauses there a moment before the next. The cleared swath
## has a round leading end and a ragged edge, with a faint grey smudge just behind it that is gone a moment
## later. Real time, so it runs the same whatever the game's time scale.
class EraseWipe extends Control:
	const TIME := 1.0
	const ROWS := 6.0
	const WAIT := 0.15  # a beat before the first stroke (the new run draws its first frame under the picture)
	var shot: Texture2D
	var finished: Callable
	var t := 0.0
	var last_us := 0
	var mat: ShaderMaterial
	static var _shader: Shader

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # the hold carries on into the new run
		size = get_viewport_rect().size
		last_us = Time.get_ticks_usec()
		if _shader == null:
			_shader = Shader.new()
			_shader.code = """
shader_type canvas_item;
uniform float prog = 0.0;
uniform float rows = 6.0;
uniform float aspect = 0.5;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float s = prog * rows;
	float r = min(floor(s), rows - 1.0);
	float local = s >= rows ? 1.0 : fract(s);
	float f = smoothstep(0.0, 0.85, local);  // speeds up, slows into the turn, rests there a moment
	bool even = mod(r, 2.0) < 0.5;
	float hx = even ? 1.0 - f : f;  // even strokes go right to left, odd ones back
	hx = mix(-0.12, 1.12, hx);  // each stroke runs off both edges of the page
	// the swath: bowed down in the middle like an arm's swing, running a little downhill, edges ragged
	float bow = sin(clamp(UV.x, 0.0, 1.0) * 3.14159) * 0.18;
	float hill = (even ? 1.0 - UV.x : UV.x) * 0.2;
	float rag = (noise(UV * vec2(7.0, 3.0)) - 0.5) * 0.35 + (noise(UV * vec2(70.0, 45.0)) - 0.5) * 0.12;
	float py = UV.y * rows - bow + hill + rag - 0.05;
	float pr = floor(py);
	float erased = 0.0;
	float fresh = 0.0;
	if (pr < r || s >= rows) {
		erased = 1.0;
	} else if (pr == r) {
		float along = (even ? UV.x - hx : hx - UV.x) * aspect * rows;  // behind the leading end, in rows
		float dy = fract(py) - 0.5;
		float tip = length(vec2(min(along, 0.0), dy));  // the leading end is round
		float rim = 0.5 + (noise(UV * vec2(40.0, 40.0)) - 0.5) * 0.12;
		erased = along > 0.0 ? 1.0 : 1.0 - smoothstep(rim - 0.04, rim + 0.04, tip);
		fresh = (1.0 - smoothstep(0.0, 0.8, max(along, 0.0))) * erased;
	}
	// just rubbed: a faint graphite smudge left for a moment behind the leading end
	vec4 smudge = vec4(0.5, 0.5, 0.53, 0.15 * fresh);
	COLOR = vec4(mix(c.rgb, smudge.rgb, erased), mix(c.a, smudge.a, erased));
}
"""
		mat = ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("rows", ROWS)
		mat.set_shader_parameter("aspect", size.x / size.y)
		var pic := TextureRect.new()
		pic.texture = shot
		pic.size = size
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.material = mat
		add_child(pic)

	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		t += minf(0.05, (now - last_us) / 1000000.0)
		last_us = now
		mat.set_shader_parameter("prog", clampf((t - WAIT) / TIME, 0.0, 1.0))
		if t >= WAIT + TIME + 0.05:
			finished.call()


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
