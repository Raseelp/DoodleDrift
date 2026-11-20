class_name SwanPair
extends RefCounted
## A pair of mute swans guarding their nest at the water's edge (one pair per lake), away from the lanterns:
## they only trouble a boat that troubles them. Rendered in 3D from the boat's camera angle (swan3d.gd).
## How they behave, as real mute swans do in spring:
## - The pen sits on the eggs. When the boat comes into their water she stands up over the eggs, wings
##   raised, and hisses; she never leaves the nest.
## - The cob guards. Left alone he patrols the water round the nest, now and then stopping to preen.
## - Watching: when the boat comes near he stops and turns to face it, neck up.
## - Warning ("busking"): when it comes close he raises his wings in an arch over his back, draws his
##   neck back, hisses and pushes towards it in surges.
## - Chasing: if the boat stays in their water (or heads for the nest) he runs across the water beating his
##   wings, takes off and flies after it low over the water: flapping, gliding, banking into turns, his
##   shadow falling away below him. Faster than the boat in a straight line but he turns wide, so a fast
##   boat that turns sharply can shake him; a slow one (in reeds) gets caught. In the air he leaves the
##   trail alone. When he gives up he comes down onto the water, displays (wings raised, hissing) for a
##   moment where he landed, then swims home.
## - If he reaches it he beats at it: the boat is nearly stopped for a moment.
## - If the boat's bow runs into him at speed (even mid-charge), he is killed: he collapses, feathers fly, and he sinks out
##   of sight. The pen rises from the nest with her wings raised, calling, then settles low and still.
## - Wherever he swims across the boat's trail, it is cut.

const Swan3D = preload("res://scripts/swan3d.gd")
const COB_PX_PER_M := 32.0  # how big the cob is drawn: about 40 px long
const NEST_PX_PER_M := 38.0
const RENDER := 256
const PATROL_SPEED := 16.0
const FLY_SPEED := 178.0  # a little faster than the boat in a straight line...
const FLY_TURN := 1.6  # ...but he turns much wider (rad/s; the boat turns at 2.5)
const TAKEOFF := 0.75  # seconds of running across the water before he is up
const LANDING := 0.8
const DISPLAY := 2.5  # the victory display after a chase
const CHARGE_TIME := 5.0  # how long he keeps chasing
const WATCH_MARGIN := 110.0  # he starts watching this far outside their water
const WARN_MARGIN := 40.0  # and hissing, wings up, this far outside it
const STRIKE := 30.0  # he reaches the boat
const RAM := 30.0  # the boat's bow reaching him (generous: steering straight at him is enough)
const LANTERN_KEEP := 70.0  # he keeps this far from the lantern floats

var lv  # the lake (level.gd)
var rng := RandomNumberGenerator.new()
var nest := Vector2.ZERO
var territory := 150.0
var temper := 1.6  # seconds the boat may stay in their water before he charges
var out_dir := 0.0  # from the nest out over the water
var pool := PackedVector2Array()
var cob := {"p": Vector2.ZERO, "v": Vector2.ZERO, "dir": 0.0}
var state := "patrol"  # patrol, groom, watch, warn, charge, strike, return, dead
var alive := true
var until := 0.0
var target := Vector2.ZERO
var warn_t := 0.0  # when the boat came into their water
var hiss_t := -10.0
var calm_t := -10.0  # he won't charge again before this
var snap_t := -10.0
var stuck := 0.0  # seconds he has been unable to move where he wants
var dead_t := -10.0
var pen_sit := 1.0
var alt := 0.0  # 0 on the water, 1 flying
var fly_speed := 0.0
var flap_t := 0.0  # flap / glide rhythm
var beat_t := -10.0
var air_turn := 0.0  # how hard he is banking
var cob_view: SubViewport
var nest_view: SubViewport
# After the cob is killed the pen leaves the nest onto the bank and wanders there in distress.
var pen_view: SubViewport = null
var pen := {"p": Vector2.ZERO, "dir": 0.0, "target": Vector2.ZERO, "until": 0.0, "act": ""}


static func make(level, at: Vector2, size: float, temper_s: float, seed: int) -> SwanPair:
	var s := SwanPair.new()
	s.lv = level
	s.rng.seed = seed
	s.nest = at
	s.territory = size
	s.temper = temper_s
	s.pool = Game.offset_largest(level.water, -14.0)
	# "Out over the water": the way from the nest with the most open water (the middle of the lake can lie
	# across land from a nest on a bend).
	var best_run := -1.0
	for k in 36:
		var a := TAU * k / 36.0
		var run := 0.0
		for r in range(10, 400, 6):
			if not s._ok(at + Vector2.from_angle(a) * r):
				if r > 30:
					break
				continue  # the first few px are the nest's own bank
			run = r
		if run > best_run:
			best_run = run
			s.out_dir = a
	s.cob["p"] = s._ring_point(s.out_dir)
	s.cob["dir"] = s.out_dir + PI * 0.5
	s.target = s._ring_point(s.out_dir + 0.8)
	s.cob_view = Swan3D.new()
	s.cob_view.render_px = RENDER
	level.add_child(s.cob_view)
	s.nest_view = Swan3D.new()
	s.nest_view.render_px = RENDER
	s.nest_view.nest = true
	level.add_child(s.nest_view)
	s.nest_view.set_sit(1.0)
	return s


## A point of his water near the nest, round from the nest by angle a.
func _ring_point(a: float) -> Vector2:
	var r := territory * rng.randf_range(0.3, 0.5)
	for k in 12:
		var q := nest + Vector2.from_angle(a) * r
		if _ok(q):
			return q
		a = lerp_angle(a, out_dir, 0.3)
	# Nothing open there: the nearest open water straight out from the nest.
	for k in range(4, 60):
		var q := nest + Vector2.from_angle(out_dir) * k * 6.0
		if _ok(q):
			return q
	return nest + Vector2.from_angle(out_dir) * territory * 0.4


func _ok(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, pool):
		return false
	for r in lv.rocks:
		if p.distance_to(r["c"]) < float(r["r"]) + 12.0:
			return false
	if lv.jet and float(lv.jet.nearest(p)[0]) < 8.0:
		return false
	for l in lv.lanterns:
		if p.distance_to(l["p"]) < LANTERN_KEEP:
			return false
	return true


# ---------------------------------------------------------------- behaviour

func update(delta: float) -> void:
	var clock: float = lv.clock
	var boat: Vector2 = lv.boat_pos
	if not alive:
		_update_dead(delta, clock, boat)
		_update_pen(delta, clock, boat, false)
		return
	var cp: Vector2 = cob["p"]
	var playing: bool = lv.state == "play"
	var near_nest := boat.distance_to(nest)
	var inside := playing and near_nest < territory
	var warned := playing and near_nest < territory + WARN_MARGIN
	var near := playing and near_nest < territory + WATCH_MARGIN
	var at_nest := near_nest < territory * 0.75 and playing 			and Vector2.from_angle(lv.move_dir).dot((nest - boat).normalized()) > 0.75  # well in, heading for the nest
	var want := Vector2.ZERO
	var anim := "Idle"
	var speed_k := 1.0

	match state:
		"patrol", "groom":
			if near:
				state = "watch"
			elif state == "groom":
				anim = "Grooming"
				if clock > until:
					state = "patrol"
			else:
				var to := target - cp
				if to.length() < 14.0 or stuck > 1.0:
					if rng.randf() < 0.35 and stuck <= 1.0:
						state = "groom"
						until = clock + rng.randf_range(2.5, 4.5)
					target = _ring_point(out_dir + rng.randf_range(-1.3, 1.3))
					stuck = 0.0
				else:
					want = to.normalized() * PATROL_SPEED
		"watch":
			# Stopped, neck up, turned to face the boat.
			cob["dir"] = lerp_angle(float(cob["dir"]), (boat - cp).angle(), 1.0 - exp(-3.0 * delta))
			if warned:
				state = "warn"
				warn_t = clock
			elif not near:
				state = "patrol"
		"warn":
			# Busking: wings arched, neck back, pushing towards the boat in surges, between it and the nest.
			anim = "WalkForwardStandWing"
			if clock - hiss_t > 2.5:
				hiss_t = clock
				Sfx.hiss()
			var guard := nest + (boat - nest).normalized() * minf(territory * 0.7, maxf(30.0, near_nest - 40.0))
			var surge := pow(maxf(0.0, sin(clock * 5.0)), 2.0)
			want = (guard - cp).normalized() * (6.0 + 40.0 * surge) if guard.distance_to(cp) > 6.0 else Vector2.ZERO
			cob["dir"] = lerp_angle(float(cob["dir"]), (boat - cp).angle(), 1.0 - exp(-4.0 * delta))
			if not inside:
				warn_t = clock  # the charge counts from coming into their water
			if not warned:
				state = "watch" if near else "patrol"
			elif inside and clock > calm_t and (clock - warn_t > temper or near_nest < territory * 0.5 or at_nest):
				_take_off(clock)
		"takeoff":
			# Running across the water, wings beating hard, spray behind, lifting off.
			anim = "Flap1"
			speed_k = 1.8
			var aim := (boat - cp).angle()
			cob["dir"] = float(cob["dir"]) + clampf(wrapf(aim - float(cob["dir"]), -PI, PI), -3.0 * delta, 3.0 * delta)
			fly_speed = move_toward(fly_speed, FLY_SPEED * 0.8, 240.0 * delta)
			var k := clampf(1.0 - (until - clock) / TAKEOFF, 0.0, 1.0)
			alt = smoothstep(0.35, 1.0, k)
			cob["p"] = cp + Vector2.from_angle(float(cob["dir"])) * fly_speed * delta
			if rng.randf() < 0.8 * (1.0 - alt):
				lv._part(cp + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)),
					-Vector2.from_angle(float(cob["dir"])) * rng.randf_range(30, 80) + Vector2(rng.randf_range(-25, 25), rng.randf_range(-25, 25)),
					rng.randf_range(0.25, 0.5), rng.randf_range(1.3, 2.4), Color(1, 1, 1, 0.85), false)
			if rng.randf() < delta * 8.0 * (1.0 - alt):
				lv.ripples.append({"p": cp, "t": clock, "life": 1.0, "r0": 3.0, "r1": 14.0, "light": false})
			if k >= 1.0:
				state = "fly"
				until = clock + CHARGE_TIME
		"fly":
			# Low over the water after the boat: aiming where it is going, turning wide.
			var lead: Vector2 = boat + Vector2.from_angle(lv.move_dir) * float(lv.speed) * 0.4
			var aim := (lead - cp).angle()
			var turn := clampf(wrapf(aim - float(cob["dir"]), -PI, PI), -FLY_TURN * delta, FLY_TURN * delta)
			cob["dir"] = float(cob["dir"]) + turn
			air_turn = lerpf(air_turn, turn / maxf(delta, 0.0001) / FLY_TURN, 1.0 - exp(-6.0 * delta))
			fly_speed = move_toward(fly_speed, FLY_SPEED, 120.0 * delta)
			var np: Vector2 = cp + Vector2.from_angle(float(cob["dir"])) * fly_speed * delta
			cob["p"] = Vector2(clampf(np.x, 20.0, Game.LAKE_SIZE.x - 20.0), clampf(np.y, 20.0, Game.LAKE_SIZE.y - 20.0))
			alt = 1.0
			# Flap, flap, glide; banking into hard turns.
			flap_t += delta
			var cycle := fmod(flap_t, 1.6)
			if absf(air_turn) > 0.55:
				anim = "GlideLeft" if air_turn < 0.0 else "GlideRight"
			else:
				anim = "Flap2" if cycle < 0.9 else "GlideForward"
			if cycle < 0.9 and clock - beat_t > 0.55:
				beat_t = clock
				Sfx.wingbeat()
			if cp.distance_to(boat) < STRIKE and playing and not _bow_on(cp, boat):
				_strike(clock, boat)  # swooping onto the boat
			elif clock > until or near_nest > territory * 2.1 or cp.distance_to(nest) > territory * 1.7 or not playing:
				state = "land"
				until = clock + LANDING
		"land":
			# Coming down onto the water: over land he flies on towards the nest first.
			anim = "GlideForward"
			if not _ok(cp) and alt > 0.9:
				var home := (nest + Vector2.from_angle(out_dir) * territory * 0.4 - cp).angle()
				cob["dir"] = float(cob["dir"]) + clampf(wrapf(home - float(cob["dir"]), -PI, PI), -FLY_TURN * delta, FLY_TURN * delta)
				until = clock + LANDING
			else:
				alt = clampf((until - clock) / LANDING, 0.0, 1.0)
			fly_speed = move_toward(fly_speed, 40.0 if alt > 0.0 else 0.0, 160.0 * delta)
			cob["p"] = cp + Vector2.from_angle(float(cob["dir"])) * fly_speed * delta
			if alt <= 0.0 and _ok(cp):
				# Touchdown: a skid and a splash, then he shows off where he landed.
				for k2 in 12:
					lv._part(cp + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
						Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 70), rng.randf_range(0.3, 0.6),
						rng.randf_range(1.4, 2.4), Color(1, 1, 1, 0.85), false)
				lv.ripples.append({"p": cp, "t": clock, "life": 1.4, "r0": 6.0, "r1": 34.0, "light": false})
				Sfx.wingbeat()
				cob["v"] = Vector2.from_angle(float(cob["dir"])) * fly_speed
				state = "display"
				until = clock + DISPLAY
				calm_t = clock + DISPLAY + 3.0
			elif alt <= 0.0:
				# Can't come down here (the bank, a rock, beside a lantern): just above the water, he turns
				# for home until he is over open water.
				alt = 0.05
				var home := (nest + Vector2.from_angle(out_dir) * territory * 0.4 - cp).angle()
				cob["dir"] = float(cob["dir"]) + clampf(wrapf(home - float(cob["dir"]), -PI, PI), -FLY_TURN * delta, FLY_TURN * delta)
		"display":
			# Victory display: wings raised, neck back, hissing at where the boat went.
			anim = "WalkForwardStandWing"
			cob["dir"] = lerp_angle(float(cob["dir"]), (boat - cp).angle(), 1.0 - exp(-3.0 * delta))
			if clock - hiss_t > 1.6:
				hiss_t = clock
				Sfx.hiss()
			if clock > until:
				state = "return"
				target = _ring_point(out_dir + rng.randf_range(-1.0, 1.0))
		"strike":
			anim = "LandAttack"
			cob["dir"] = lerp_angle(float(cob["dir"]), (boat - cp).angle(), 1.0 - exp(-6.0 * delta))
			if clock > until:
				if alt > 0.0:
					state = "land"
					until = clock + LANDING
				else:
					state = "return"
		"return":
			# Gliding back to his water, wings settling.
			anim = "WalkForwardStandWing" if clock < calm_t - 2.5 else "Idle"
			if stuck > 1.0:
				target = _ring_point(out_dir + rng.randf_range(-1.2, 1.2))  # another way home
				stuck = 0.0
			want = (target - cp).normalized() * 30.0
			if inside and clock > calm_t and cp.distance_to(nest) < territory:
				_take_off(clock)  # still in their water: after it again
			elif cp.distance_to(nest) < territory * 0.55:
				state = "watch" if near else "patrol"
				target = _ring_point(out_dir + rng.randf_range(-1.0, 1.0))

	# Running into him bow first kills him, whatever he is doing (even mid-charge, head to head).
	if playing and float(lv.speed) > 40.0 and _bow_on(cp, boat):  # on the water or flying low at it
		_die(clock, boat)
		return
	var airborne := state in ["takeoff", "fly", "land"] or (state == "strike" and alt > 0.0)
	if not airborne:
		_move(want, 400.0 if state in ["return", "display"] else 50.0, delta)
	if not airborne and state != "watch" and state != "strike" and state != "display" and Vector2(cob["v"]).length() > 3.0:
		cob["dir"] = lerp_angle(float(cob["dir"]), Vector2(cob["v"]).angle(), 1.0 - exp(-5.0 * delta))
	if not airborne and Vector2(cob["v"]).length() > 8.0 and rng.randf() < delta * 1.4:
		lv.ripples.append({"p": cob["p"], "t": clock, "life": 1.3, "r0": 4.0, "r1": 18.0, "light": false})
	if not airborne:
		_cut_trail(clock)  # in the air he leaves the trail alone
	_update_pen(delta, clock, boat, inside or state in ["warn", "takeoff", "fly", "land", "strike", "display"])
	cob_view.set_pose(float(cob["dir"]))
	cob_view.play(anim, speed_k)


## Up and after the boat: a run across the water first.
func _take_off(clock: float) -> void:
	state = "takeoff"
	until = clock + TAKEOFF
	fly_speed = Vector2(cob["v"]).length()
	flap_t = 0.0
	stuck = 0.0
	Sfx.hiss()
	Sfx.wingbeat()
	beat_t = clock


## Whether the boat's bow is right on him, coming at him.
func _bow_on(cp: Vector2, boat: Vector2) -> bool:
	var fwd := Vector2.from_angle(lv.move_dir)
	var bow: Vector2 = boat + fwd * 28.0
	return bow.distance_to(cp) < RAM and fwd.dot((cp - boat).normalized()) > 0.35


## The pen on the nest: standing up over the eggs, wings raised, hissing, while the boat is in their water;
## rising and calling when the cob is killed, then settling low.
func _update_pen(delta: float, clock: float, boat: Vector2, alarmed: bool) -> void:
	if not alive:
		_update_widow(delta, clock)
		return
	pen_sit = move_toward(pen_sit, 0.0 if alarmed else 1.0, delta * 1.8)
	nest_view.set_sit(pen_sit)
	nest_view.set_pose(lerp_angle(out_dir, (boat - nest).angle(), 1.0 - pen_sit))
	if alarmed:
		nest_view.play("WalkForwardStandWing")
	else:
		nest_view.play("Grooming" if fmod(clock, 14.0) < 3.0 else "Idle")


## The pen after the cob is killed: a moment later she stands, steps off the nest onto the bank (away from
## the water), flings her wings up once, then wanders the bank near the nest in distress: walking with
## her wings half raised, stopping to flinch or slump, never back onto the water.
func _update_widow(delta: float, clock: float) -> void:
	var t := clock - dead_t
	if pen_view == null:
		pen_sit = move_toward(pen_sit, 0.0, delta * 2.0)  # rising off the eggs
		nest_view.set_sit(pen_sit)
		nest_view.set_pose(lerp_angle(out_dir, (Vector2(cob["p"]) - nest).angle(), 1.0 - pen_sit))
		nest_view.play("Idle")
		if t < 0.8:
			return
		pen_view = Swan3D.new()
		pen_view.render_px = RENDER
		pen_view.on_land = true
		lv.add_child(pen_view)
		nest_view.empty_nest()
		nest_view.render_target_update_mode = SubViewport.UPDATE_ONCE  # just the nest now: still
		pen["p"] = nest
		pen["dir"] = out_dir + PI
		pen["target"] = _bank_point(out_dir + PI, 34.0, 48.0)
		pen["act"] = "out"
	var pp: Vector2 = pen["p"]
	var to: Vector2 = Vector2(pen["target"]) - pp
	match String(pen["act"]):
		"out", "walk":
			pen_view.play("WalkForwardStandWing", 0.8)
			if to.length() > 3.0:
				pen["dir"] = lerp_angle(float(pen["dir"]), to.angle(), 1.0 - exp(-4.0 * delta))
				pen["p"] = pp + to.normalized() * minf(14.0 * delta, to.length())
			elif pen["act"] == "out":
				pen["act"] = "cry"  # off the nest: wings flung up, once
				pen_view.play("Rebirth", 1.0, false)
				Sfx.hiss()
				pen["until"] = clock + 1.8
			else:
				# Stop: a flinch or a slump, then on again.
				var r := rng.randf()
				pen["act"] = "flinch" if r < 0.45 else "slump"
				pen_view.play("LandHit" if r < 0.45 else "down", 0.8, false)
				pen["until"] = clock + rng.randf_range(1.6, 2.8)
		"cry", "flinch", "slump":
			pen["dir"] = lerp_angle(float(pen["dir"]), (Vector2(cob["p"]) - pp).angle(), 1.0 - exp(-1.5 * delta))
			if clock > float(pen["until"]) and not pen_view.playing_once():
				pen["act"] = "walk"
				pen["target"] = _bank_point(out_dir + PI + rng.randf_range(-1.3, 1.3), 26.0, 70.0)
	pen_view.set_pose(float(pen["dir"]))


## Somewhere on the bank near the nest, away from the water and out from under the trees.
func _bank_point(a: float, r0: float, r1: float) -> Vector2:
	var wet := Game.offset_largest(lv.water, 14.0)
	for k in 30:
		var q := nest + Vector2.from_angle(a + rng.randf_range(-0.6, 0.6)) * rng.randf_range(r0, r1)
		if Geometry2D.is_point_in_polygon(q, wet) or q.x < 24.0 or q.y < 24.0 \
				or q.x > Game.LAKE_SIZE.x - 24.0 or q.y > Game.LAKE_SIZE.y - 24.0:
			continue
		var shaded := false
		for tr in lv.trees:
			if q.distance_to(tr["p"]) < float(tr["r"]) + 10.0:
				shaded = true
				break
		if not shaded:
			return q
	return nest + Vector2.from_angle(out_dir + PI) * r0


func _strike(clock: float, boat: Vector2) -> void:
	state = "strike"
	until = clock + 0.9
	calm_t = clock + 3.0
	lv.speed *= 0.15  # nearly stopped
	var away: Vector2 = (boat - Vector2(cob["p"])).normalized()
	if lv._free(boat + away * 10.0):
		lv.boat_pos = boat + away * 10.0
	for k in 14:
		lv._part(boat - away * 12.0 + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
			Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, 90), rng.randf_range(0.3, 0.7),
			rng.randf_range(1.5, 3.0), Color("f4f1ea") if k % 2 == 0 else Color(1, 1, 1, 0.8), false)
	lv.ripples.append({"p": boat - away * 10.0, "t": clock, "life": 1.3, "r0": 6.0, "r1": 36.0, "light": false})
	Sfx.hiss()
	Sfx.wingbeat()
	Game.vibrate(45)


## The boat ran him down: he is knocked, collapses and sinks.
func _die(clock: float, boat: Vector2) -> void:
	alive = false
	state = "dead"
	dead_t = clock
	var push: Vector2 = Vector2.from_angle(lv.move_dir)
	cob["v"] = push * 60.0
	cob["dir"] = (Vector2(cob["p"]) - boat).angle()
	lv.speed *= 0.55  # a heavy bird: the boat is jolted
	for k in 26:
		var fc := Color("f6f3ec") if k % 4 != 0 else Color("cfc9bd")
		lv._part(Vector2(cob["p"]) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
			Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, 120), rng.randf_range(0.7, 1.5),
			rng.randf_range(1.6, 3.2), fc, false)
	lv.ripples.append({"p": cob["p"], "t": clock, "life": 1.6, "r0": 6.0, "r1": 44.0, "light": false})
	cob_view.play("LandHit", 1.2)
	Sfx.bump()
	Sfx.wingbeat()
	Game.vibrate(70)


func _update_dead(delta: float, clock: float, boat: Vector2) -> void:
	var t := clock - dead_t
	if alt > 0.0:
		# Hit in the air: he tumbles down onto the water.
		alt = move_toward(alt, 0.0, delta * 2.2)
		if alt <= 0.0:
			for k in 14:
				lv._part(Vector2(cob["p"]) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
					Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 80), rng.randf_range(0.3, 0.7),
					rng.randf_range(1.4, 2.6), Color(1, 1, 1, 0.85), false)
			lv.ripples.append({"p": cob["p"], "t": clock, "life": 1.5, "r0": 6.0, "r1": 40.0, "light": false})
	cob["v"] = Vector2(cob["v"]).move_toward(Vector2.ZERO, 60.0 * delta)
	var np: Vector2 = Vector2(cob["p"]) + Vector2(cob["v"]) * delta
	if Geometry2D.is_point_in_polygon(np, pool):
		cob["p"] = np
	if t > 0.6:
		cob_view.play("down", 0.6)
	if t > 4.5 and cob_view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		cob_view.render_target_update_mode = SubViewport.UPDATE_DISABLED  # gone: stop rendering him
	if t > 1.5 and t < 4.0 and rng.randf() < delta * 2.0:
		lv.ripples.append({"p": cob["p"], "t": clock, "life": 1.4, "r0": 4.0, "r1": 16.0, "light": false})
	cob_view.set_pose(float(cob["dir"]))


func _move(want: Vector2, accel: float, delta: float) -> void:
	var v: Vector2 = Vector2(cob["v"]).move_toward(want, accel * delta)
	var p: Vector2 = cob["p"]
	var np := p + v * delta
	if not _ok(np):
		var moved := false
		for a in [0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, 3.0, -3.0]:
			var v2: Vector2 = v.rotated(a)
			if _ok(p + v2 * delta):
				v = v2
				np = p + v2 * delta
				moved = true
				break
		if not moved:
			v *= 0.3
			np = p
	if want.length() > 5.0 and np.distance_to(p) < want.length() * delta * 0.25:
		stuck += delta  # held up (the shore, a rock, a lantern)
	else:
		stuck = maxf(0.0, stuck - delta)
	cob["v"] = v
	cob["p"] = np


## Wherever he swims across the boat's trail (patrolling or charging), the trail is cut there.
func _cut_trail(clock: float) -> void:
	if lv.state != "play":
		return
	var p: Vector2 = cob["p"]
	var wp: PackedVector2Array = lv.wp
	var wc: PackedFloat32Array = lv.wc
	var cut := -1
	for i in wp.size():
		if wc[i] > 1e8 and wp[i].distance_to(p) < 14.0:
			cut = i
	if cut >= 0:
		lv._snap_trail(cut, p, clock - snap_t > 0.8)
		snap_t = clock


# ---------------------------------------------------------------- drawing

func draw_nest(ci: CanvasItem) -> void:
	_draw_view(ci, nest_view, nest, NEST_PX_PER_M, Color(0.04, 0.07, 0.08, 0.3), 1.0, 0.0)
	if pen_view:
		_draw_view(ci, pen_view, pen["p"], NEST_PX_PER_M, Color(0.04, 0.07, 0.08, 0.3), 1.0, 0.0)


func draw_cob(ci: CanvasItem) -> void:
	if alt >= 0.3:
		return  # drawn up in the air layer (draw_cob_air)
	var a := 1.0
	if not alive:
		a = 1.0 - smoothstep(1.8, 4.2, lv.clock - dead_t)  # sinking out of sight
		if a <= 0.0:
			return
	_draw_view(ci, cob_view, cob["p"], COB_PX_PER_M * (1.0 + 0.3 * alt), Color(0.02, 0.06, 0.08, 0.3 * a), a, alt)


## The cob in the air, drawn above the boat and the trees.
func draw_cob_air(ci: CanvasItem) -> void:
	if alt < 0.3:
		return
	var bob := Vector2(0, sin(lv.clock * 7.0) * 1.5 * alt)
	_draw_view(ci, cob_view, Vector2(cob["p"]) + bob, COB_PX_PER_M * (1.0 + 0.3 * alt), Color(0.02, 0.06, 0.08, 0.3 * (1.0 - 0.45 * alt)), 1.0, alt)


func _draw_view(ci: CanvasItem, view: SubViewport, at: Vector2, px_per_m: float, shadow: Color, alpha: float, height: float) -> void:
	var sc := px_per_m * Swan3D.VIEW / float(RENDER)
	var tex := view.get_texture()
	var anchor: Vector2 = view.anchor()
	# The higher he is, the further his shadow falls from him on the water, and the smaller it is.
	var sh_at := at + Vector2(-5, 7) + Vector2(-22, 36) * height
	ci.draw_set_transform(sh_at, 0.0, Vector2.ONE * sc * (1.0 - 0.3 * height))
	ci.draw_texture(tex, -anchor, shadow)
	ci.draw_set_transform(at, 0.0, Vector2.ONE * sc)
	ci.draw_texture(tex, -anchor, Color(1, 1, 1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
