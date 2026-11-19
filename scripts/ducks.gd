class_name DuckFamily
extends RefCounted
## A mallard hen and her ducklings living on a lake, behaving the way a real family does:
## - The hen swims slowly from place to place. On the way she stops to feed (dabbling: she tips forward,
##   tail up, then rights herself), and now and then rests near the shore and preens.
## - The ducklings follow her in a loose, wobbly line, each behind the one in front. When she stops they
##   bunch round her. Now and then one darts off after an insect, then peeps and hurries back.
## - When the boat comes at them she gives an alarm call, turns away from its path and leads them off
##   faster, and they close up tight behind her.
## - Where they go: mostly round the lanterns (where a player loops), keeping off the lake's edges.
## - Driving close past them at speed startles them, and running into them does too (the boat is slowed):
##   either way the family is split up: she flaps off across the water in a panic and
##   the ducklings dive and come up scattered, each somewhere else. Lost, each paddles about in short bursts,
##   stopping to look round and peeping, while she swims towards their peeps giving her gathering call. Each
##   call turns the lost ones her way (roughly at first, better the longer they search); once she is close
##   they make straight for her and fall back into line. Nobody is hurt, but the lost ducklings criss-cross
##   the lake and cut the trail: at least once each time they are split (one of them bolts across the
##   trail if none happens to), often several times. Each duck cuts it once per split: after that only a
##   duckling on its way back to her can cut it again, until the family is back together. A family already
##   split can't be split again until it has regrouped.
## - Where any of them swims across the boat's trail, the trail is cut there (level.gd _snap_trail).
## Drawn in code from above: a mottled brown hen with her blue wing patch and orange bill, and downy
## dark brown and yellow ducklings.

const HEN_SPEED := 22.0
const ALARM_SPEED := 50.0
const FLEE_SPEED := 120.0
const KID_GAP := 12.0  # how far each duckling keeps behind the one in front
const ALARM_NEAR := 125.0  # the hen reacts when the boat comes this close and heads her way
const HIT := 24.0  # the boat touching a duck
const STARTLE := 46.0  # the boat rushing past this close splits them up too

var lv  # the lake (level.gd)
var rng := RandomNumberGenerator.new()
var pool := PackedVector2Array()  # the water they swim on, kept a little off the shore
var hen := {}
var kids: Array = []
var state := "swim"  # swim, feed, rest, alarm, flee, search (gathering her scattered ducklings)
var call_t := -10.0  # her last gathering call
var peep_any := -10.0  # the family's last peep (so a scattered brood doesn't peep all at once)
var until := 0.0
var target := Vector2.ZERO
var alarm_t := -10.0  # her last alarm call
var hit_cool := -10.0
var snap_t := -10.0
var marks: Array = []  # the hen's feather mottling: [position, size, angle]
var heart := PackedVector2Array()  # the open water they head for, well off the shore
var split_t := -10.0  # when they were last split up
var split_cuts := 0  # trail cuts since then
var hen_cut := false  # she has cut the trail since they were split


static func make(level, at: Vector2, n_kids: int, seed: int) -> DuckFamily:
	var f := DuckFamily.new()
	f.lv = level
	f.rng.seed = seed
	f.pool = Game.offset_largest(level.water, -12.0)
	f.heart = Game.offset_largest(level.water, -50.0)
	var d0 := f.rng.randf() * TAU
	f.hen = {"p": at, "v": Vector2.ZERO, "dir": d0, "ph": f.rng.randf() * TAU, "tip": 0.0, "rip": 0.0}
	for i in n_kids:
		var p: Vector2 = at - Vector2.from_angle(d0) * KID_GAP * (i + 1)
		if not f._ok(p):
			p = at
		f.kids.append({"p": p, "v": Vector2.ZERO, "dir": d0, "ph": f.rng.randf() * TAU,
			"slot": Vector2.from_angle(f.rng.randf() * TAU) * f.rng.randf_range(10.0, 20.0),
			"dart_until": -1.0, "dart_to": Vector2.ZERO, "peep": -10.0, "dive_until": -1.0, "rip": 0.0,
			"size": f.rng.randf_range(0.9, 1.08), "lost": false, "lost_t": 0.0, "head": d0})
	for k in 16:
		f.marks.append([Vector2(f.rng.randf_range(-10.0, 5.0), f.rng.randf_range(-4.2, 4.2)), f.rng.randf_range(1.2, 2.0), f.rng.randf_range(-0.4, 0.4)])
	f.target = f._new_target()
	return f


# ---------------------------------------------------------------- behaviour

func update(delta: float) -> void:
	var clock: float = lv.clock
	var boat: Vector2 = lv.boat_pos
	var bfwd := Vector2.from_angle(lv.move_dir)
	var moving_boat: bool = lv.speed > 30.0 and lv.state in ["play", "ready"]
	var hp: Vector2 = hen["p"]

	# Reacting to the boat: she leads them off when it heads her way.
	if state != "flee":
		var dist := hp.distance_to(boat)
		var coming := moving_boat and (hp - boat).normalized().dot(bfwd) > 0.3
		if (dist < ALARM_NEAR and coming) or dist < 60.0:
			if state != "alarm":
				state = "alarm"
				if clock - alarm_t > 5.0:
					alarm_t = clock
					Sfx.quack_alarm()
			until = clock + 2.2
		elif state == "alarm" and clock > until:
			state = "search" if _lost_count() > 0 else "swim"
			target = _new_target()

	# The hen: where she wants to go.
	var want := Vector2.ZERO
	match state:
		"swim":
			var to := target - hp
			if _lost_count() > 0:
				state = "search"
			elif to.length() < 18.0:
				var r := rng.randf()
				if r < 0.45:
					state = "feed"
					until = clock + rng.randf_range(4.0, 8.0)
				elif r < 0.6:
					state = "rest"
					until = clock + rng.randf_range(6.0, 10.0)
				else:
					target = _new_target()
			else:
				var wander := sin(clock * 0.7 + float(hen["ph"])) * 0.35
				want = to.normalized().rotated(wander) * HEN_SPEED
		"feed", "rest":
			want = Vector2.from_angle(float(hen["dir"])) * (3.0 if state == "rest" else 1.5)
			if clock > until:
				state = "swim"
				target = _new_target()
		"alarm":
			# Away from the boat's path, to the side she is already on.
			var off := hp - boat
			var side := signf(bfwd.cross(off))
			if side == 0.0:
				side = 1.0
			var away := (bfwd.rotated(side * PI * 0.5) * 0.7 + off.normalized() * 0.6).normalized()
			want = away * ALARM_SPEED
		"flee":
			want = Vector2(hen["v"]).normalized() * FLEE_SPEED * clampf((until - clock) / 1.1, 0.25, 1.0)
			if clock > until:
				state = "search"
		"search":
			# Gathering them: towards the nearest peep she can hear, calling every few seconds.
			var lost = _nearest_lost(hp)
			if lost == null:
				hen_cut = false
				state = "rest"  # all back: a moment bunched round her before carrying on
				until = clock + rng.randf_range(2.5, 4.0)
			else:
				var to: Vector2 = Vector2(lost["p"]) - hp
				if to.length() > 30.0:
					want = to.normalized().rotated(sin(clock * 1.1 + float(hen["ph"])) * 0.4) * 15.0
				if clock - call_t > rng.randf_range(2.6, 3.4):
					call_t = clock
					Sfx.duck_call()
					for kid in kids:
						if kid["lost"] and clock > float(kid.get("panic_until", 0.0)):
							var heard := clampf((clock - float(kid["lost_t"])) / 12.0, 0.0, 1.0)
							kid["head"] = (hp - Vector2(kid["p"])).angle() + rng.randf_range(-1.2, 1.2) * (1.0 - heard)
	# Dabbling while feeding: tipped up for a while, then upright again.
	var tip_goal := 0.0
	if state == "feed":
		tip_goal = 1.0 if fmod(clock + float(hen["ph"]), 3.0) < 1.7 else 0.0
	var was_up := float(hen["tip"]) > 0.5
	hen["tip"] = move_toward(float(hen["tip"]), tip_goal, delta * 4.0)
	if (float(hen["tip"]) > 0.5) != was_up:
		lv.ripples.append({"p": hp + Vector2.from_angle(float(hen["dir"])) * 6.0, "t": clock, "life": 1.2, "r0": 3.0, "r1": 14.0, "light": false})
	_move(hen, want + _avoid(hp, 26.0), 70.0 if state == "flee" else 40.0, delta)
	if state == "flee":
		for k in 2:
			lv._part(Vector2(hen["p"]) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)),
				-Vector2(hen["v"]).normalized() * rng.randf_range(20, 60) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)),
				rng.randf_range(0.25, 0.5), rng.randf_range(1.2, 2.2), Color(1, 1, 1, 0.8), false)

	# The ducklings.
	var bunch := state in ["feed", "rest"]
	var leader: Dictionary = hen
	for i in kids.size():
		var kid: Dictionary = kids[i]
		var kp: Vector2 = kid["p"]
		if float(kid["dive_until"]) > clock:
			continue
		if float(kid["dive_until"]) > 0.0:
			kid["dive_until"] = -1.0  # back up from the dive
			lv.ripples.append({"p": kp, "t": clock, "life": 1.0, "r0": 2.0, "r1": 10.0, "light": false})
		if kid["lost"]:
			_lost_step(kid, clock, delta, boat)
			continue
		var goal: Vector2
		if bunch:
			goal = Vector2(hen["p"]) + Vector2(kid["slot"])
		else:
			var lp: Vector2 = leader["p"]
			var ld := Vector2.from_angle(float(leader["dir"]))
			goal = lp - ld * KID_GAP + ld.orthogonal() * sin(clock * 1.3 + float(kid["ph"])) * 2.5
		# Now and then one darts off after an insect.
		if state in ["swim", "feed", "rest"] and float(kid["dart_until"]) < clock and rng.randf() < delta * 0.05:
			var to := kp + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 38.0)
			if _ok(to):
				kid["dart_until"] = clock + rng.randf_range(0.8, 1.4)
				kid["dart_to"] = to
		var top := HEN_SPEED * 2.0
		if float(kid["dart_until"]) > clock:
			goal = kid["dart_to"]
			top = 32.0
		var gap := goal.distance_to(kp)
		if state == "alarm" or state == "flee":
			top = ALARM_SPEED * 1.5
		elif gap > 28.0 and float(kid["dart_until"]) < clock:
			top = 58.0  # left behind: hurrying back
			if clock - float(kid["peep"]) > 3.0:
				kid["peep"] = clock
				Sfx.peep()
		var want_k := (goal - kp).normalized() * minf(top, gap * 2.4) if gap > 0.5 else Vector2.ZERO
		# Keep a little apart from each other.
		for j in kids.size():
			if j != i and float(kids[j]["dive_until"]) < clock:
				var away: Vector2 = kp - Vector2(kids[j]["p"])
				var dd := away.length()
				if dd < 8.0 and dd > 0.01:
					want_k += away / dd * (8.0 - dd) * 6.0
		_move(kid, want_k + _avoid(kp, 18.0), 90.0, delta)
		leader = kid  # the next one follows this one

	# Ripples as they paddle, and the boat running into them.
	_ripples(clock)
	if lv.state == "play" and clock - hit_cool > 2.5 and _lost_count() == 0 and state not in ["flee", "search"]:
		var nearest := Vector2(hen["p"]).distance_to(boat)
		var near_p: Vector2 = hen["p"]
		for kid in kids:
			var dk := Vector2(kid["p"]).distance_to(boat)
			if float(kid["dive_until"]) < clock and dk < nearest:
				nearest = dk
				near_p = kid["p"]
		if nearest < HIT and lv.speed > 20.0:  # run into (a still boat they just paddle round)
			_panic(clock, boat, true)
		elif nearest < STARTLE and lv.speed > 45.0 and clock - hit_cool > 4.0 \
				and ((near_p - boat).normalized().dot(bfwd) > -0.2 or nearest < 38.0):
			_panic(clock, boat, false)  # rushed past: startled
	if hen_cut and _lost_count() == 0 and state not in ["flee", "search"]:
		hen_cut = false  # all back together: she can cut the trail again
	_cut_trail(clock)
	_pick_crosser(clock)


## Splits the family up: hit (the boat is slowed too) or only startled by it rushing past.
func _panic(clock: float, boat: Vector2, hit: bool) -> void:
	hit_cool = clock
	split_t = clock
	split_cuts = 0
	hen_cut = false
	state = "flee"
	until = clock + 1.1
	alarm_t = clock
	var away := Vector2(hen["p"]) - boat
	if away.length() < 0.01:
		away = Vector2.from_angle(float(hen["dir"]))
	hen["v"] = away.normalized() * FLEE_SPEED
	lv.ripples.append({"p": hen["p"], "t": clock, "life": 1.4, "r0": 4.0, "r1": 30.0, "light": false})
	for kid in kids:
		# Each dives and comes up somewhere else, away from the boat and from the others: scattered.
		var kp: Vector2 = kid["p"]
		lv.ripples.append({"p": kp, "t": clock, "life": 1.0, "r0": 2.0, "r1": 12.0, "light": false})
		var out := (kp - boat).normalized().rotated(rng.randf_range(-1.3, 1.3))
		for attempt in 6:
			var q := kp + out * rng.randf_range(30.0, 60.0)
			if _ok(q):
				kid["p"] = q
				break
			out = out.rotated(rng.randf_range(-1.2, 1.2))
		kid["dive_until"] = clock + rng.randf_range(0.8, 1.6)
		kid["lost"] = true
		kid["lost_t"] = clock
		kid["panic_until"] = clock + rng.randf_range(1.5, 3.0)  # bolting away before it starts to listen for her
		kid["head"] = out.angle()
		kid["v"] = Vector2.ZERO
		kid["cross"] = false
	if hit:
		lv.speed *= 0.9
		Sfx.quack()
		Game.vibrate(30)
	else:
		Sfx.quack_alarm()
		Game.vibrate(12)


## A lost duckling: paddling about in short bursts, stopping to look round and peeping, turning towards
## its mother's calls; once she is close it makes straight for her and falls back into line.
func _lost_step(kid: Dictionary, clock: float, delta: float, boat: Vector2) -> void:
	var kp: Vector2 = kid["p"]
	var hp: Vector2 = hen["p"]
	var d := kp.distance_to(hp)
	if d < 20.0:
		kid["lost"] = false  # back with her
		kid["cut"] = false
		kid["cross"] = false  # if it was to dash across the trail, another lost one takes that on
		return
	var panicking: bool = clock < float(kid.get("panic_until", 0.0))
	var sees := not panicking and (d < 45.0 or clock - float(kid["lost_t"]) > 20.0)
	var cross_to = _nearest_live(kp) if kid.get("cross", false) else null
	if cross_to != null:
		var through: Vector2 = cross_to
		kid["head"] = (through - kp).angle() + sin(clock * 3.0 + float(kid["ph"])) * 0.25
		sees = false
		panicking = true
	elif sees:
		kid["head"] = (hp - kp).angle()  # it can see her now (or has found its way at last)
	else:
		kid["head"] = float(kid["head"]) + rng.randf_range(-1.6, 1.6) * delta  # unsure, wandering
	var burst := maxf(0.0, sin(clock * 2.7 + float(kid["ph"]) * 3.0))
	var spd := 55.0 if sees else 50.0 * (0.25 + 0.75 * burst) * (1.4 if panicking else 1.0)
	var want := Vector2.from_angle(float(kid["head"])) * spd
	var from_boat := kp - boat
	if from_boat.length() < 70.0:
		want += from_boat.normalized() * (70.0 - from_boat.length()) * 3.0
	var before: Vector2 = kid["p"]
	_move(kid, want + _avoid(kp, 18.0), 110.0, delta)
	if Vector2(kid["p"]).distance_to(before) < spd * delta * 0.3:
		kid["head"] = float(kid["head"]) + PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)  # blocked: try another way
	if clock - float(kid["peep"]) > rng.randf_range(1.0, 1.8) and clock - peep_any > 0.35:
		kid["peep"] = clock
		peep_any = clock
		Sfx.peep()


func _lost_count() -> int:
	var n := 0
	for kid in kids:
		if kid["lost"]:
			n += 1
	return n


func _nearest_lost(p: Vector2):
	var best = null
	var bd := INF
	for kid in kids:
		if kid["lost"] and float(kid["dive_until"]) < lv.clock:
			var d := p.distance_to(kid["p"])
			if d < bd:
				bd = d
				best = kid
	if best == null and _lost_count() > 0:
		for kid in kids:
			if kid["lost"]:
				return kid  # still under water
	return best


## Where a duck swims over the boat's trail, the trail is cut (only while playing).
func _cut_trail(clock: float) -> void:
	if lv.state != "play":
		return
	var cut := -1
	var at := Vector2.ZERO
	var who = null
	var split := state in ["flee", "search"] or _lost_count() > 0
	var members: Array = []
	if not (split and hen_cut):
		members.append([hen, 10.0])
	for kid in kids:
		if float(kid["dive_until"]) >= clock:
			continue
		if kid["lost"] and kid.get("cut", false) and not _heading_home(kid, clock):
			continue  # it has had its cut this time
		members.append([kid, 7.0])
	var wp: PackedVector2Array = lv.wp
	var wc: PackedFloat32Array = lv.wc
	for m in members:
		var p: Vector2 = m[0]["p"]
		var r: float = m[1]
		for i in wp.size():
			if i > cut and wc[i] > 1e8 and wp[i].distance_to(p) < r:
				cut = i
				at = p
				who = m[0]
	if cut >= 0:
		var loud := clock - snap_t > 0.8
		lv._snap_trail(cut, at, loud)
		snap_t = clock
		split_cuts += 1
		if split:
			if who == hen:
				hen_cut = true
			elif who["lost"]:
				who["cut"] = true


## A lost duckling making its way back to her (past its panic, swimming towards her).
func _heading_home(kid: Dictionary, clock: float) -> bool:
	if clock < float(kid.get("panic_until", 0.0)):
		return false
	var v: Vector2 = kid["v"]
	var to: Vector2 = Vector2(hen["p"]) - Vector2(kid["p"])
	return v.length() > 5.0 and to.length() > 1.0 and v.normalized().dot(to.normalized()) > 0.7


## Split up and the trail not cut yet: one lost duckling bolts across it, so a split always costs a cut.
func _pick_crosser(clock: float) -> void:
	if split_cuts > 0 or clock - split_t > 12.0 or lv.state != "play":
		for kid in kids:
			kid["cross"] = false
		return
	for kid in kids:
		if kid.get("cross", false):
			return
	var best = null
	var bd := 260.0
	for kid in kids:
		if kid["lost"] and not kid.get("cut", false):
			var q = _nearest_live(kid["p"])
			if q != null and Vector2(kid["p"]).distance_to(q) < bd:
				bd = Vector2(kid["p"]).distance_to(q)
				best = kid
	if best != null:
		best["cross"] = true


## The nearest point of the boat's live trail to p, or null.
func _nearest_live(p: Vector2):
	var best = null
	var bd := INF
	var wp: PackedVector2Array = lv.wp
	var wc: PackedFloat32Array = lv.wc
	for i in wp.size():
		if wc[i] > 1e8:
			var d := p.distance_squared_to(wp[i])
			if d < bd:
				bd = d
				best = wp[i]
	return best


func _ripples(clock: float) -> void:
	var all: Array = [hen]
	all.append_array(kids)
	for i in all.size():
		var m: Dictionary = all[i]
		if i > 0 and float(m["dive_until"]) > clock:
			continue
		var gap := 0.75 if i == 0 else 1.0
		if clock - float(m["rip"]) > gap and (Vector2(m["v"]).length() > 6.0 or (i == 0 and float(m["tip"]) > 0.5)):
			m["rip"] = clock
			lv.ripples.append({"p": m["p"], "t": clock, "life": 1.2, "r0": 2.0, "r1": 14.0 if i == 0 else 8.0, "light": false})


func _move(m: Dictionary, want: Vector2, accel: float, delta: float) -> void:
	var v: Vector2 = Vector2(m["v"]).move_toward(want, accel * delta)
	var p: Vector2 = m["p"]
	var np := p + v * delta
	if not _ok(np):
		var moved := false
		for a in [0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]:
			var v2: Vector2 = v.rotated(a)
			if _ok(p + v2 * delta):
				v = v2
				np = p + v2 * delta
				moved = true
				break
		if not moved:
			v *= 0.3
			np = p
	m["v"] = v
	m["p"] = np
	if v.length() > 2.0:
		m["dir"] = lerp_angle(float(m["dir"]), v.angle(), 1.0 - exp(-6.0 * delta))


## Steering away from rocks, lantern floats, the jetty and the shore when close.
func _avoid(p: Vector2, near: float) -> Vector2:
	var push := Vector2.ZERO
	for r in lv.rocks:
		var d: Vector2 = p - Vector2(r["c"])
		var gap := d.length() - float(r["r"])
		if gap < near and d.length() > 0.01:
			push += d.normalized() * (near - gap) * 2.0
	for l in lv.lanterns:
		var d: Vector2 = p - Vector2(l["p"])
		var keep := near + 14.0  # the lantern floats are wide
		if d.length() < keep and d.length() > 0.01:
			push += d.normalized() * (keep - d.length()) * 2.0
	if lv.jet:
		var jn: Array = lv.jet.nearest(p)
		if float(jn[0]) < near:
			push += Vector2(jn[1]) * (near - float(jn[0])) * 2.0
	return push


## Inside the water they keep to, clear of rocks and the jetty.
func _ok(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, pool):
		return false
	for r in lv.rocks:
		if p.distance_to(r["c"]) < float(r["r"]) + 6.0:
			return false
	if lv.jet and float(lv.jet.nearest(p)[0]) < 4.0:
		return false
	return true


## Somewhere else on the water to swim to, not too near the boat.
func _new_target() -> Vector2:
	var hp: Vector2 = hen["p"]
	for attempt in 40:
		var q: Vector2
		if rng.randf() < 0.75 and not lv.lanterns.is_empty():
			# Round a lantern, where the boat loops.
			var l: Dictionary = lv.lanterns[rng.randi() % lv.lanterns.size()]
			q = Vector2(l["p"]) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(45.0, 110.0)
		else:
			q = hp + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(100.0, 260.0)
		if Geometry2D.is_point_in_polygon(q, heart) and _ok(q) and q.distance_to(hp) > 60.0 \
				and q.distance_to(lv.boat_pos) > 120.0:
			return q
	return hp


# ---------------------------------------------------------------- drawing

func draw(ci: CanvasItem, shade: Color) -> void:
	var clock: float = lv.clock
	for kid in kids:
		if float(kid["dive_until"]) > clock:
			continue
		var sway := sin(clock * 9.0 + float(kid["ph"])) * 0.07 * clampf(Vector2(kid["v"]).length() / 20.0, 0.0, 1.0)
		_wake(ci, kid["p"], float(kid["dir"]), Vector2(kid["v"]).length(), 5.0)
		_draw_kid(ci, kid["p"], float(kid["dir"]) + sway, float(kid["size"]), shade)
	var hs := Vector2(hen["v"]).length()
	_wake(ci, hen["p"], float(hen["dir"]), hs, 11.0)
	var sway_h := sin(clock * 6.0 + float(hen["ph"])) * 0.05 * clampf(hs / 20.0, 0.0, 1.0)
	_draw_hen(ci, hen["p"], float(hen["dir"]) + sway_h, shade, clock)


## A faint V behind a paddling duck.
func _wake(ci: CanvasItem, p: Vector2, ang: float, spd: float, back: float) -> void:
	if spd < 6.0:
		return
	var f := Vector2.from_angle(ang)
	var s := f.orthogonal()
	var tail := p - f * back
	var ln := clampf(spd * 0.3, 4.0, 14.0)
	var a := clampf(spd / 60.0, 0.08, 0.18)
	for sd in [-1.0, 1.0]:
		ci.draw_line(tail, tail - f * ln + s * sd * ln * 0.5, Color(1, 1, 1, a), 1.2, true)


func _draw_hen(ci: CanvasItem, p: Vector2, ang: float, shade: Color, clock: float) -> void:
	var tip := float(hen["tip"])
	var alarm := state == "alarm" or state == "flee"
	var flap := state == "flee"
	ci.draw_set_transform(p + Vector2(3, 4), ang, Vector2.ONE)
	ci.draw_colored_polygon(_body(1.0 - 0.35 * tip, 1.0), Color(shade, 0.5))
	ci.draw_set_transform(p, ang, Vector2.ONE)
	if flap:
		# Wings out, beating, as she flaps off across the water.
		var beat := absf(sin(clock * 22.0))
		for sd in [-1.0, 1.0]:
			var w := PackedVector2Array([Vector2(3, 3 * sd), Vector2(-6, (6 + 12 * beat) * sd), Vector2(-12, (4 + 9 * beat) * sd), Vector2(-7, 3 * sd)])
			ci.draw_colored_polygon(w, Color("7d5c3c"))
			ci.draw_line(Vector2(-5, (5 + 9 * beat) * sd), Vector2(-9, (4 + 7 * beat) * sd), Color("3d57a6"), 2.0, true)
	var body := _body(1.0 - 0.35 * tip, 1.0)
	ci.draw_colored_polygon(body, Color("9b7a55"))
	# The darker centres of her back feathers with paler edges: the mallard hen's mottling.
	ci.draw_colored_polygon(_body(0.78 - 0.3 * tip, 0.62), Color("6f5236"))
	for mk in marks:
		var mp: Vector2 = mk[0]
		if tip > 0.5 and mp.x > -2.0:
			continue
		ci.draw_arc(mp, float(mk[1]), PI * 0.6 + float(mk[2]), PI * 1.4 + float(mk[2]), 5, Color("c9ab80"), 0.8, true)
	# Folded wings along her sides, the blue patch showing near their ends, tail at the back.
	for sd in [-1.0, 1.0]:
		ci.draw_line(Vector2(2, 4.6 * sd), Vector2(-10, 3.6 * sd), Color("5e4329"), 1.8, true)
		ci.draw_line(Vector2(-5.5, 4.7 * sd), Vector2(-8.5, 4.1 * sd), Color("2f4683"), 0.9, true)
		ci.draw_line(Vector2(-5.2, 5.2 * sd), Vector2(-8.8, 4.6 * sd), Color(1, 1, 1, 0.35), 0.5, true)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-11, -2.4), Vector2(-16, 0), Vector2(-11, 2.4)]), Color("4e3a26"))
	ci.draw_line(Vector2(-12, 0), Vector2(-15.4, 0), Color("cdb894"), 0.8, true)
	if tip > 0.5:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return  # tipped up feeding: head under the water
	# Head and bill; she stretches her neck up when alarmed, and turns her head back to preen at rest.
	var neck := 9.5 + (2.5 if alarm else 0.0)
	var head := Vector2(neck, 0)
	if state == "rest" and sin(clock * 0.6 + float(hen["ph"])) > 0.6:
		head = Vector2(-2.0, 3.5)  # preening: head turned back over her back
	ci.draw_circle(head, 4.0, Color("8a6a47"), true, -1.0, true)
	ci.draw_line(head + Vector2(-3.2, 0), head + Vector2(3.4, 0), Color("3e2c1c"), 1.5, true)  # dark crown
	for sd in [-1.0, 1.0]:
		ci.draw_line(head + Vector2(-1.5, 2.6 * sd), head + Vector2(3.2, 1.6 * sd), Color("4a3726"), 0.7, true)  # eye stripe
	if head.x > 0.0:
		ci.draw_colored_polygon(PackedVector2Array([head + Vector2(3.0, -1.5), head + Vector2(7.6, -1.2), head + Vector2(8.2, 0),
			head + Vector2(7.6, 1.2), head + Vector2(3.0, 1.5)]), Color("d38a3e"))
		ci.draw_line(head + Vector2(4.2, 0), head + Vector2(6.8, 0), Color("5b4630"), 1.2, true)  # dark saddle on the bill
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The hen's body from above: rounded at the chest, tapering to the tail. len_k shortens it (tipped up).
func _body(len_k: float, w_k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 22:
		var a := TAU * k / 22.0
		var c := cos(a)
		var x := c * (8.5 if c > 0.0 else 11.5) * len_k
		var y := sin(a) * 6.3 * w_k * (1.0 if c > 0.0 else 0.7 + 0.3 * (1.0 + c))
		pts.append(Vector2(x, y))
	return pts


func _draw_kid(ci: CanvasItem, p: Vector2, ang: float, size: float, shade: Color) -> void:
	ci.draw_set_transform(p + Vector2(2, 2.5), ang, Vector2.ONE * size)
	ci.draw_circle(Vector2(-0.5, 0), 4.6, Color(shade, 0.45), true, -1.0, true)
	ci.draw_set_transform(p, ang, Vector2.ONE * size)
	# Downy: dark brown above with yellow patches and a yellow rim, a yellow face with a dark crown.
	ci.draw_set_transform(p, ang, Vector2(1.15, 0.9) * size)
	ci.draw_circle(Vector2(-1.0, 0), 4.3, Color("c9a94e"), true, -1.0, true)
	ci.draw_circle(Vector2(-1.2, 0), 4.0, Color("4a3825"), true, -1.0, true)
	ci.draw_set_transform(p, ang, Vector2.ONE * size)
	for sd in [-1.0, 1.0]:
		ci.draw_circle(Vector2(-2.8, 1.5 * sd), 0.65, Color("e3c665"), true, -1.0, true)
		ci.draw_circle(Vector2(0.0, 1.8 * sd), 0.6, Color("e3c665"), true, -1.0, true)
	ci.draw_circle(Vector2(3.6, 0), 2.6, Color("dcbf60"), true, -1.0, true)
	ci.draw_line(Vector2(1.6, 0), Vector2(5.0, 0), Color("4a3825"), 1.9, true)
	for sd in [-1.0, 1.0]:
		ci.draw_line(Vector2(3.2, 1.5 * sd), Vector2(5.0, 1.0 * sd), Color("3a2c1e"), 0.5, true)
	ci.draw_line(Vector2(5.6, 0), Vector2(7.0, 0), Color("3a3026"), 1.2, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
