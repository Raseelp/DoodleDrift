extends Node2D
## Tyre particles. Whenever the rear tyres lay a skid, even a light one: pale tyre smoke and dark rubber bits, as in Absolute Drift.
## While it tears the paper, a soft graphite smudge and rolled eraser crumbs as well.
## Each kind is one MultiMesh, so each is one draw call however many particles are alive.
## This node sits under the car (smudge, rubber, crumbs); `over` sits above it (smoke).

const CAP := {"smoke": 135, "rubber": 240, "smudge": 135, "crumbs": 255}
const CRUMB_COLS := [Color("e9a4ad"), Color("e4949f"), Color("bdb8b3"), Color("c9c3bd"), Color("9a9694"), Color("d8b0b5")]
const DIRTY := Color("8f8a88")  # a crumb that picked up graphite
const RUBBER := Color("1d1d21")

var over := Node2D.new()
var parts := {}  # per kind: a fixed ring of slots (null = empty), so a particle keeps its place in the buffer
var head := {}  # the slot the next particle takes (the oldest one is replaced when all are taken)
var alive := {}
var mm := {}
var bufs := {}  # per kind: 12 floats an instance (2D transform, then colour), sent in one call
var acc := {"smoke": 0.0, "rubber": 0.0, "smudge": 0.0, "crumbs": 0.0}
var rng := RandomNumberGenerator.new()
static var sprites := {}  # made once per app run (about 34 ms on PC), not again on every "Drive again"


func _init() -> void:
	rng.randomize()
	for kind in CAP:
		parts[kind] = []
		parts[kind].resize(CAP[kind])
		head[kind] = 0
		alive[kind] = 0
	if sprites.is_empty():
		sprites = {"smudge": _smudge_tex(), "rubber": _round_tex(0.7), "crumbs": _crumb_tex(), "smoke": _puff_tex()}
	_layer("smudge", self, sprites["smudge"])  # graphite lies on the page, under the bits
	_layer("rubber", self, sprites["rubber"])
	_layer("crumbs", self, sprites["crumbs"])
	_layer("smoke", over, sprites["smoke"])  # smoke rises over the car


func _layer(kind: String, parent: Node2D, tex: Texture2D) -> void:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_2D
	m.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	m.mesh = q
	m.instance_count = CAP[kind]
	# Particles are written straight into the buffer, which does not move the bounds Godot culls with: left alone they
	# stayed round the start line and the layer stopped drawing once the car drove away. Bounds that cover the sheet.
	m.custom_aabb = AABB(Vector3(-1e7, -1e7, -1.0), Vector3(2e7, 2e7, 2.0))
	m.visible_instance_count = 0
	var b := PackedFloat32Array()
	b.resize(CAP[kind] * 12)  # all zero: every slot starts see-through
	bufs[kind] = b
	m.buffer = b
	var n := MultiMeshInstance2D.new()
	n.multimesh = m
	n.texture = tex
	n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # sprites drawn far smaller than made don't shimmer
	parent.add_child(n)
	mm[kind] = m


## Called every frame while playing: `wheels` are the two rear tyres (each particle picks one at random:
## most frames make only one, so counting through them always picked the same tyre).
func emit(delta: float, wheels: Array, vdir: float, speed: float, slip: float, top_speed: float, marking: bool, ripping: bool) -> void:
	if not marking or speed <= 40.0:
		return
	var light := 0.3  # a light slide still makes this share of a full one
	var sp := speed / top_speed
	var back := vdir + PI
	var carry := Vector2.from_angle(vdir) * speed * 0.15
	for _n in _rate("smoke", 39.0 * maxf(light, smoothstep(0.2, 0.9, slip)) * sp, delta):
		var a := back + rng.randf_range(-0.6, 0.6)
		_push("smoke", {"p": wheels[rng.randi() % 2], "v": Vector2.from_angle(a) * rng.randf_range(20, 60) + carry, "t": 0.0, "life": rng.randf_range(2.6, 4.0),
			"s0": rng.randf_range(14, 22), "s1": rng.randf_range(70, 110), "rot": rng.randf() * TAU, "vr": rng.randf_range(-0.4, 0.4), "peak": 0.7})  # 0.7: a denser smoke than the lab's 0.5
	for _n in _rate("rubber", 60.0 * maxf(light, slip) * sp, delta):
		var a := back + rng.randf_range(-1.0, 1.0)
		_push("rubber", {"p": wheels[rng.randi() % 2], "v": Vector2.from_angle(a) * rng.randf_range(80, 220), "t": 0.0, "life": rng.randf_range(5, 8), "r": rng.randf_range(1, 2.4)})
	if ripping:  # tearing adds the graphite and eraser on top
		for _n in _rate("smudge", 27.0 * smoothstep(0.2, 0.9, slip) * (0.5 + sp * 0.5), delta):
			var a := back + rng.randf_range(-0.5, 0.5)
			_push("smudge", {"p": wheels[rng.randi() % 2], "v": Vector2.from_angle(a) * rng.randf_range(10, 35), "t": 0.0, "life": rng.randf_range(3.8, 5.5),
				"s0": rng.randf_range(18, 26), "s1": rng.randf_range(60, 95), "rot": rng.randf() * TAU, "vr": rng.randf_range(-0.25, 0.25),
				"peak": rng.randf_range(0.16, 0.24) * smoothstep(0.2, 1.0, slip) + 0.05})
		for _n in _rate("crumbs", 45.0 * slip * sp, delta):
			var a := back + rng.randf_range(-1.1, 1.1)
			var col: Color = DIRTY if rng.randf() < 0.35 else CRUMB_COLS[rng.randi() % CRUMB_COLS.size()]
			_push("crumbs", {"p": wheels[rng.randi() % 2], "v": Vector2.from_angle(a) * rng.randf_range(70, 200), "t": 0.0, "life": rng.randf_range(8, 12),
				"l": rng.randf_range(3.5, 8), "w": rng.randf_range(2, 3.4), "rot": rng.randf() * TAU, "vr": rng.randf_range(-14, 14), "col": col})


func _rate(kind: String, per_sec: float, delta: float) -> int:
	acc[kind] += per_sec * delta
	var n := int(acc[kind])
	acc[kind] -= n
	return n


func _push(kind: String, p: Dictionary) -> void:
	var a: Array = parts[kind]
	var i: int = head[kind]
	if a[i] == null:
		alive[kind] += 1
	a[i] = p
	head[kind] = (i + 1) % a.size()


## Called every frame in every state, so what is in the air settles and fades after a crash too.
## Only what changes on screen is written again: a bit that has stopped, and is not fading in or out, is skipped.
func step(delta: float) -> void:
	for kind in parts:
		var m: MultiMesh = mm[kind]
		if alive[kind] == 0:
			if m.visible_instance_count != 0:
				m.visible_instance_count = 0
			continue
		var floats: bool = kind == "smoke" or kind == "smudge"
		var f := exp(-(1.6 if floats else 4.2) * delta)  # smoke floats, bits skid to a stop
		var t_out := 1.5 if kind == "rubber" else 2.0
		var a: Array = parts[kind]
		var b: PackedFloat32Array = bufs[kind]
		for i in a.size():
			var p = a[i]
			if p == null:
				continue
			var t: float = p["t"] + delta
			p["t"] = t
			var life: float = p["life"]
			if t >= life:
				a[i] = null
				alive[kind] -= 1
				b[i * 12 + 11] = 0.0  # gone: see-through
				continue
			var v: Vector2 = p["v"]
			if floats or v.length_squared() > 0.25:
				v *= f
				p["v"] = v
				p["p"] = Vector2(p["p"]) + v * delta
				if p.has("vr"):
					p["rot"] += p["vr"] * delta * minf(1.0, v.length() / 40.0 + (1.0 if floats else 0.0))
			elif t > 0.05 and t < life - t_out:
				continue  # settled, and not fading: nothing on screen changes
			_write(kind, p, b, i * 12)
		bufs[kind] = b
		m.buffer = b
		m.visible_instance_count = a.size()


static func _fade(p: Dictionary, t_in: float, t_out: float) -> float:
	var t: float = p["t"]
	return smoothstep(0.0, t_in, t) * (1.0 - smoothstep(p["life"] - t_out, p["life"], t))


static func _write(kind: String, p: Dictionary, b: PackedFloat32Array, o: int) -> void:
	var at: Vector2 = p["p"]
	var rot := 0.0
	var sz := Vector2.ONE
	var col := Color.WHITE
	match kind:
		"smoke", "smudge":
			var u: float = p["t"] / p["life"]
			var s := lerpf(p["s0"], p["s1"], 1.0 - (1.0 - u) * (1.0 - u))
			rot = p["rot"]
			sz = Vector2(s, s)
			col.a = p["peak"] * _fade(p, 0.25, p["life"] * 0.6)
		"rubber":
			var d: float = p["r"] * 2.0
			sz = Vector2(d, d)
			col = Color(RUBBER, 0.8 * _fade(p, 0.05, 1.5))
		"crumbs":
			rot = p["rot"]
			sz = Vector2(p["l"], p["w"])
			col = Color(p["col"], _fade(p, 0.05, 2.0))
	var c := cos(rot)
	var sn := sin(rot)
	b[o] = c * sz.x
	b[o + 1] = -sn * sz.y
	b[o + 2] = 0.0
	b[o + 3] = at.x
	b[o + 4] = sn * sz.x
	b[o + 5] = c * sz.y
	b[o + 6] = 0.0
	b[o + 7] = at.y
	b[o + 8] = col.r
	b[o + 9] = col.g
	b[o + 10] = col.b
	b[o + 11] = col.a


# ---- the sprites, drawn once in code

static func _puff_tex() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color8(205, 210, 218, 230), Color8(214, 218, 224, 115), Color8(220, 224, 230, 0)])
	return _radial(g, 128)


static func _round_tex(solid: float) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, solid, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	return _radial(g, 16)


static func _radial(g: Gradient, size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)  # made on the CPU so mipmaps can be built
	var h := size * 0.5
	for y in size:
		for x in size:
			img.set_pixel(x, y, g.sample(minf(1.0, Vector2(x + 0.5 - h, y + 0.5 - h).length() / h)))
	return _mipped(img)


static func _mipped(img: Image) -> Texture2D:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A rolled crumb, white so each takes its own colour: a soft-edged capsule, a little darker below
## and with a lighter line along one side where it catches the light.
static func _crumb_tex() -> Texture2D:
	var w := 32
	var h := 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5 - 0.5
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, r + 0.5, w - r - 0.5)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - h * 0.5).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var yy := (y + 0.5) / h
			var v := 0.72 + 0.2 * (1.0 - yy)
			if yy > 0.18 and yy < 0.36 and x > 4 and x < w - 5:
				v = 1.0
			img.set_pixel(x, y, Color(v, v, v, a))
	return _mipped(img)


## Pencil shading rubbed with a finger: two layers of hatching, blurred, under a soft round mask.
static func _smudge_tex() -> Texture2D:
	var S := 128
	var acc := PackedFloat32Array()
	acc.resize(S * S)
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	var base := r.randf() * PI
	for k in 90:
		var ang := base + (0.5 if k % 2 else 0.0) + (r.randf() - 0.5) * 0.35
		var c := Vector2(64 + (r.randf() - 0.5) * 70, 64 + (r.randf() - 0.5) * 70)
		var l := 18.0 + r.randf() * 40.0
		var alpha := 0.18 + r.randf() * 0.22
		var rad := (1.0 + r.randf() * 2.2) * 0.5
		var d := Vector2.from_angle(ang) * l * 0.5
		var bend := c + Vector2(r.randf() - 0.5, r.randf() - 0.5) * 6.0
		var steps := int(l)
		var stroke := {}  # cell -> coverage: a stroke does not darken itself where its stamps overlap
		for i in steps + 1:
			var t := float(i) / steps
			var p := (c - d).lerp(bend, t).lerp(bend.lerp(c + d, t), t)
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var x := int(p.x) + ox
					var y := int(p.y) + oy
					if x < 0 or y < 0 or x >= S or y >= S:
						continue
					var cover := clampf(rad + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(p), 0.0, 1.0)
					if cover > 0.0:
						var j := y * S + x
						stroke[j] = maxf(stroke.get(j, 0.0), alpha * cover)
		for j in stroke:  # strokes build up over each other like layers of pencil
			acc[j] = acc[j] + stroke[j] * (1.0 - acc[j])
	acc = _blur(_blur(acc, S), S)
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var dist := Vector2(x + 0.5 - 64, y + 0.5 - 64).length()
			var m := 1.0
			if dist > 6.0:
				var u := (dist - 6.0) / 56.0
				m = lerpf(1.0, 0.55, u / 0.55) if u < 0.55 else lerpf(0.55, 0.0, minf(1.0, (u - 0.55) / 0.45))
			# 1.85: about as dark as the Particle Lab's smudge (mean alpha ~0.12)
			img.set_pixel(x, y, Color8(52, 54, 62, int(clampf(acc[y * S + x] * m * 1.85, 0.0, 1.0) * 255)))
	return _mipped(img)


static func _blur(src: PackedFloat32Array, S: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(S * S)
	var out := PackedFloat32Array()
	out.resize(S * S)
	for y in S:
		for x in S:
			var s := 0.0
			for o in range(-2, 3):
				s += src[y * S + clampi(x + o, 0, S - 1)]
			tmp[y * S + x] = s / 5.0
	for y in S:
		for x in S:
			var s := 0.0
			for o in range(-2, 3):
				s += tmp[clampi(y + o, 0, S - 1) * S + x]
			out[y * S + x] = s / 5.0
	return out
