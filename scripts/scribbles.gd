extends Node2D
## Everything the person who drew the track left on the page: notes, doodles, abandoned roads, corrections
## and sticky notes. Nothing is a fixed picture or a fixed sentence: text comes from a small grammar with
## word banks, drawings from shape algorithms with random parameters, all done in the hand of a "writer"
## (font, pen, slant, size, how sloppy) that changes from page to page. Finished notes are remembered
## (saved between sessions) so the same one doesn't turn up again.

const DrawNode = preload("res://scripts/draw_node.gd")
const NARRATOR := false  # the narrator's notes are switched off for now (Raseel will say when to bring them back)
const FONTS := ["res://fonts/hand/Caveat.ttf", "res://fonts/hand/PatrickHand.ttf", "res://fonts/hand/GochiHand.ttf", "res://fonts/hand/ReenieBeanie.ttf"]
const PENS := [  # colour, stroke width, weight
	[Color(0.2, 0.2, 0.23, 0.82), 2.0, 5.0],  # pencil
	[Color(0.13, 0.22, 0.58, 0.9), 1.6, 3.0],  # blue ballpoint
	[Color(0.08, 0.08, 0.1, 0.9), 1.8, 2.0],  # black pen
	[Color(0.72, 0.12, 0.12, 0.88), 1.7, 0.6],  # red pen (rare)
	[Color(0.12, 0.45, 0.25, 0.88), 1.7, 0.5],  # green (rare)
]
const STICKY := [Color(0.99, 0.93, 0.48), Color(0.99, 0.75, 0.82), Color(0.68, 0.87, 0.99), Color(0.75, 0.95, 0.65)]
const SAVE := "user://drift.cfg"

## The narrator's voice. One person: drew this road, knows a bit too much about rally, has a job, a landlord,
## a mum who calls, plants that judge him. Lines are whole thoughts with only a few slots, so each one means
## something. {key} expands to a pick (recursively), [a|b] picks inline, ~text~ is written then struck out.
const G := {
	# --- to whoever is driving: wry, never claiming to know how they drove ---
	"tease": [
		"the lines are a suggestion. like my diet.",
		"i measured this with my thumb. it's fine.",
		"you're allowed to slow down. nobody ever does.",
		"this bit was straight until the coffee happened",
		"if you're reading this you're not looking at the road",
		"bold of you to assume i planned this",
		"i'd say take it easy but we both know",
		"it gets wider later. (it doesn't)",
		"stay inside the lines, said every teacher i ignored",
		"i drew the road around the stain, not the other way round",
		"left. no, the other left.",
		"sideways is a direction if you're stubborn enough",
		"you're steering a drawing of a car. we're both doing great.",
		"plot twist: there's no finish line",
		"nobody's coming to fix this corner. that includes me.",
		"i'd put a barrier here but i'm out of {thing}",
	],
	"thing": ["ink", "paper", "pencil lead", "graphite", "eraser"],
	# --- at the corner he just drew ---
	"hairpin": [
		"too tight? probably. leaving it.",
		"redo this one ~tomorrow~ never",
		"this corner is why i don't draw maps",
		"i turned the page halfway through this one",
		"sharp. like my landlord's emails.",
	],
	"long": [
		"long one. pack a snack.",
		"this corner goes on longer than my mum's voice notes",
		"one big lazy bend. relatable.",
		"keep it sideways and think about your life choices",
		"long enough to regret starting it",
	],
	"switch": [
		"wiggly bit. the pen slipped. twice.",
		"drew this on the bus. over speed bumps.",
		"zigzag, like my sleep schedule",
	],
	# --- his life, on the page ---
	"remind": [
		"rent due {day}. pretend not to see this.",
		"call mum back. it's been {n2} days.",
		"gym: monday. (it's thursday)",
		"do laundry before the last socks go",
		"water the plants. they look judgy.",
		"fix bike brake before it fixes me",
		"return his drill. it's been a year.",
		"{day}: bins out. both of them.",
		"pay him back. stop avoiding him in the corridor.",
		"invoice the dev ~next week~ today",
	],
	"msg": [
		"he still has my charger",
		"wifi: {pw}",
		"they said the meeting could've been an email. it could.",
		"landlord said {day}. landlord can wait.",
		"note to self: you are not a morning person. stop trying.",
	],
	"pw": ["teapot4lyf", "notyourwifi", "password123 (i know)", "Kettle_99", "ask_nicely"],
	"caption": [
		"this is me on monday|face",
		"my cat, roughly|cat",
		"self portrait (flattering)|face",
		"what the meeting felt like|figure",
		"how the car sees me|face",
		"the sun, as promised|sun",
	],
	"speech": ["is this a road?", "i only came for the snacks", "who drew this", "can we go home now", "this counts as cardio", "i'm the flag person. apparently.", "why is everything sideways", "is it lunch yet", "pay me in coffee", "not again", "i've seen worse. not much worse."],
	"think": ["what if i'm the car", "did i lock the door", "fish?", "i should've been a dentist", "tuesday again...", "the tyres know"],
	# --- rally habits he can't shake (he knows it's drifting) ---
	# --- the developer who hired him (affectionate grumbling) ---
	"dev": [
		"if you see the dev, tell him i want my {lost_item} back",
		"dev said 'just one more corner'. that was page {pg}.",
		"dev, if you're reading this: i'm not doing the {version} version",
		"dev's only note was '{dev_note}'. thanks, very helpful.",
		"dev made the car red so it looks faster. it doesn't.",
		"sent the dev three versions. he picked the first. it's always the first.",
		"dev asked if i can 'just make it pop'. i don't know what pop is.",
		"i'm a designer. this is not design. this is a road.",
		"dev wants it by friday. dev doesn't say which friday.",
	],
	"lost_item": ["eraser", "sharpener", "good pen", "stapler", "lunchbox", "chair"],
	"pg": ["3", "4", "2", "5"],
	"version": ["3D", "VR", "sequel", "multiplayer"],
	"dev_note": ["make it fun", "more drift", "just vibes", "fix later", "make it pop"],
	# --- meme captions ---
	"meh_good": [
		"braking before the corner|braking during the crash",
		"doing {hw}|drawing roads on {hw}",
		"going to bed|one more corner",
		"paying rent|buying nicer pencils",
		"staying in the lines|making the lines wider",
		"using the eraser|drawing it again, bigger",
	],
	"homework_short": ["homework", "the tax form", "the cover letter", "meeting notes"],
	"nobody_me": ["draws 40 hairpins", "adds one more corner", "erases the whole page", "names the road 'final_v2'", "redraws the coffee ring on purpose", "argues with the eraser"],
	"late": ["2am", "3am", "midnight", "4:10am"],
	"starter_who": [
		"drifter",
		"night owl",
		"notebook artist",
		"hopeless romantic",
		"designer",
	],
	"honest_word": ["work", "drifting", "pencil work", "overtime"],
	"love": [
		"crash it like i did with my feelings. full send, no brakes.",
		"she said she'll text back. that was {n2} pages ago.",
		"this corner is shaped like her handwriting. i'd know.",
		"i drew her a road once. she took the bus.",
		"she likes someone who can drive. i can draw roads. close enough?",
		"drift like nobody's watching. she isn't.",
		"you can't steer feelings. i've tried. it's all understeer.",
		"she called me 'a friend'. the road called me 'a corner'. both hurt.",
		"every hairpin on this page is a time i almost said it",
		"if she reads this: hi. if not: also hi.",
		"the eraser works on pencil. not on her.",
	],
	"letter": [
		"dear you,
the road goes on for ages.
so do i, apparently.
(not sending this)",
		"to her,
i drew {n1} hairpins today
and thought of you in all of them.
~love~ regards",
		"hi,
saw you at the {place}.
said nothing. drew this.
- me",
		"dear you,
if you ever drive this,
the coffee stain was your fault.
(it wasn't)",
		"note i won't send:
you were right about the {small_thing}.
i was right about us.",
	],
	"place": [
		"bus stop",
		"coffee place",
		"library",
		"corner shop",
		"station",
	],
	"small_thing": [
		"umbrella",
		"film",
		"weather",
		"pizza",
		"song",
	],
	"n1": [
		"3",
		"4",
		"7",
		"12",
		"40",
	],
	"proof": [
		"see? {doubter} said i can't draw a {obj}.",
		"{doubter} said this looks like a potato. it's a {obj}.",
		"a {obj}. from memory. {doubter} owes me an apology.",
		"proof i can draw a {obj}. {doubter} can stop laughing now.",
		"this is a {obj}. if you see a {wrong_obj}, that's on you.",
	],
	"doubter": [
		"he",
		"she",
		"my brother",
		"my art teacher",
		"the dev",
		"my mum",
	],
	"wrong_obj": [
		"potato",
		"cloud",
		"mistake",
		"crime scene",
		"sad sock",
	],
	"rally_aside": [
		"(old habit. this isn't rally.)",
		"(co-driver brain, sorry)",
		"(you don't need this. i know.)",
		"(i miss gravel)",
		"(drifting. right. carry on.)",
		"(i'll stop. i won't.)",
	],
	"day": ["monday", "tuesday", "wed", "thursday", "friday", "saturday", "sunday", "tmrw"],
	"clock": ["9am", "10:30", "2pm", "4pm", "8:15"],
	"n2": ["3", "4", "6", "9", "12"],
}


var g: Node  # the game (road arrays, rng, corners)
var under: Node2D  # notes and doodles on the paper, under the road ink
var over: Node2D  # sticky notes, on top
var bits: Array = []  # {node, len}
var rects: Array = []  # [Rect2, len] taken paper beside the road
var writer := {}
var writer_page := -1
var corner_done := 0
var next_item := 350.0
var placed := 0  # things put on the page so far
var last_at := {}  # kind -> when it last appeared (in things placed)

## What can appear beside the road, its share, and how many other things must come between two of the same
## kind. The longer a kind has been away past its gap, the more likely it gets (up to 3x), so nothing turns
## up back to back and nothing goes missing for long. New kinds: add a line here and a case in _put().
const MIX := {
	"tease": [3.0, 3], "remind": [2.0, 3], "msg": [1.4, 4], "dev": [1.4, 5],
	"list": [0.8, 6], "sum": [0.7, 6], "phone": [0.5, 8],
	"doodle": [2.4, 2], "big": [1.2, 4], "meme": [1.0, 6],
	"sticky": [0.7, 6], "ghost": [0.6, 7], "oops": [0.5, 8],
	"drawing": [1.0, 5],
}
var rally_left := 0
var slots := {}  # extra words for one line (e.g. the object under a drawing)
var decks := {}  # per kind: a shuffled order of its templates and how far through it we are (saved)
var fonts: Array = []


func setup(game: Node, p_under: Node2D, p_over: Node2D) -> void:
	g = game
	under = p_under
	over = p_over
	for f in FONTS:
		fonts.append(load(f))
	# The memory carries over between runs and sessions: the decks, the mixer and the rally pause.
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	var dk = cfg.get_value("notes", "decks", {})
	decks = dk if dk is Dictionary else {}  # a damaged save just starts fresh decks
	placed = int(cfg.get_value("notes", "placed", 0))
	var la = cfg.get_value("notes", "last_at", {})
	last_at = la if la is Dictionary else {}
	rally_left = int(cfg.get_value("notes", "rally_left", 0))


func save_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	cfg.set_value("notes", "decks", decks)
	cfg.set_value("notes", "placed", placed)
	cfg.set_value("notes", "last_at", last_at)
	cfg.set_value("notes", "rally_left", rally_left)
	if cfg.has_section_key("notes", "seen"):
		cfg.erase_section_key("notes", "seen")  # the old seen-list is replaced by the decks
	cfg.save(SAVE)


## Called after each new piece of road (from = first point of it).
func on_block(from: int) -> void:
	var L: float = g.lens[g.lens.size() - 1]
	if not NARRATOR or L < 3200.0:  # a clean page at the start: the first note turns up a while into the run
		corner_done = g.corners.size()
		return
	if g.page_no != writer_page:
		writer_page = g.page_no
		_new_writer()
	# Corners just laid: maybe a remark next to them.
	while corner_done < g.corners.size():
		var c: Dictionary = g.corners[corner_done]
		corner_done += 1
		if g.rng.randf() < 0.07:
			_corner_note(c)
	if L >= next_item:
		next_item = L + g.rng.randf_range(1800.0, 3200.0)  # rare: the page is for other things
		var kind := _next_kind()
		_put(kind, from)
		placed += 1
		last_at[kind] = placed


func _next_kind() -> String:
	var weights := {}
	var total := 0.0
	for k in MIX:
		var since := placed - int(last_at.get(k, -1000))
		var gap: int = MIX[k][1]
		var w := 0.0
		if since > gap:
			w = float(MIX[k][0]) * minf(3.0, 1.0 + float(since - gap * 2) / float(gap * 2) if since > gap * 2 else 1.0)
		weights[k] = w
		total += w
	var r: float = g.rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return "doodle"


func _put(kind: String, from: int) -> void:
	match kind:
		"doodle":
			_doodle(from, false)
		"big":
			_doodle(from, true)
		"meme":
			_meme(from)
		"sticky":
			_sticky(from)
		"ghost":
			_ghost_road(from)
		"oops":
			_oops(from)
		"drawing":
			_drawing(from)
		_:
			_life_note(from, kind)


func prune(behind: float) -> void:
	var keep: Array = []
	for b in bits:
		if float(b["len"]) < behind:
			(b["node"] as Node).queue_free()
		else:
			keep.append(b)
	bits = keep
	rects = rects.filter(func(rr): return float(rr[1]) >= behind)


# ---------------------------------------------------------------- writers and text

## A new person picks up the pen: their handwriting, pen, slant, size and how messy they are.
func _new_writer() -> void:
	var rng: RandomNumberGenerator = g.rng
	var total := 0.0
	for p in PENS:
		total += p[2]
	var r := rng.randf() * total
	var pen: Array = PENS[0]
	for p in PENS:
		r -= p[2]
		if r <= 0.0:
			pen = p
			break
	writer = {
		"font": rng.randi() % fonts.size(),
		"col": pen[0],
		"w": pen[1],
		"size": rng.randf_range(24.0, 34.0),
		"slant": rng.randf_range(-0.22, 0.08),
		"mess": rng.randf_range(0.2, 1.0),
		"caps": rng.randf() < 0.15,
		"tilt": rng.randf_range(-0.12, 0.12),
	}


## A line of the given kind: the next template from that kind's deck, filled in.
func _say(sym: String) -> String:
	var arr: Array = G[sym]
	return _expand(arr[_card(sym, arr.size())], 0)


## The next card from a kind's deck. Each deck is every template of that kind in a random order; it is only
## reshuffled once every card has been used, and the last few used never land on top of the new deck, so a
## joke never comes back until all the others of its kind have had their turn. Kept across runs and sessions.
func _card(key: String, count: int) -> int:
	if count <= 0:
		return 0
	var d = decks.get(key, {})
	if not d is Dictionary:
		d = {}
	var order = d.get("order", [])
	if not order is Array:
		order = []
	var at := int(d.get("at", 0))
	if order.size() != count or at >= count:  # new deck (or the templates changed in an update)
		var last: Array = order.slice(maxi(0, at - 3), at) if order.size() == count else []
		order = range(count)
		for k in range(count - 1, 0, -1):
			var j: int = g.rng.randi_range(0, k)
			var tmp = order[k]
			order[k] = order[j]
			order[j] = tmp
		var guard := 0
		while count > 4 and guard < 8 and order.slice(0, 3).any(func(x): return last.has(x)):
			order.push_back(order.pop_front())  # keep the last ones used away from the top
			guard += 1
		at = 0
	var pick := clampi(int(order[at]), 0, count - 1)
	decks[key] = {"order": order, "at": at + 1}
	return pick


func _expand(s: String, depth: int) -> String:
	var rng: RandomNumberGenerator = g.rng
	var out := s
	# [a|b] choices
	while out.contains("["):
		var a := out.find("[")
		var b := out.find("]", a)
		if b < 0:
			break
		var opts := out.substr(a + 1, b - a - 1).split("|")
		out = out.substr(0, a) + opts[rng.randi() % opts.size()] + out.substr(b + 1)
	# {symbol} expansions
	var guard := 0
	while out.contains("{") and guard < 30:
		guard += 1
		var a := out.find("{")
		var b := out.find("}", a)
		var key := out.substr(a + 1, b - a - 1)
		var pick := "?"
		if slots.has(key):
			pick = slots[key]
		elif G.has(key) and depth < 6:
			var arr: Array = G[key]
			pick = _expand(arr[rng.randi() % arr.size()], depth + 1)
		out = out.substr(0, a) + pick + out.substr(b + 1)
	return out


# ---------------------------------------------------------------- notes

func _corner_note(c: Dictionary) -> void:
	var rng: RandomNumberGenerator = g.rng
	var kind: String = c["kind"]
	var text := ""
	var arrow := 0.0
	if rally_left <= 0 and rng.randf() < 0.34 and kind != "esses":
		# A pace note, as a co-driver would call it: grade 1 (tightest) to 6 (fastest) from the radius, the
		# direction, "long" for a long corner, a caution, and the distance (m) into the next corner. Then he
		# remembers this is drifting.
		rally_left = rng.randi_range(3, 6)
		var r: float = float(c["r"]) / g.road_k  # grade by shape, whatever the road size
		var grade := 1 if r < 140.0 else 2 if r < 170.0 else 3 if r < 210.0 else 4 if r < 260.0 else 5 if r < 350.0 else 6
		text = "%d%s%s" % [grade, "R" if c["side"] > 0.0 else "L", " long" if kind in ["constant", "pad", "decreasing"] else ""]
		var caution: String = ["dont cut", "keep in", "tightens" if kind == "decreasing" else "opens", "caution"][rng.randi() % 4]
		text += " " + caution
		var idx: int = g.corners.find(c)
		if idx >= 0 and idx + 1 < g.corners.size():
			var nx: Dictionary = g.corners[idx + 1]
			var gap := (float(nx["len"]) - float(c["len"])) / 10.0
			var nr: float = float(nx["r"]) / g.road_k
			var ng := 1 if nr < 140.0 else 2 if nr < 170.0 else 3 if nr < 210.0 else 4 if nr < 260.0 else 5 if nr < 350.0 else 6
			text += "\n%s %d%s" % [("into" if gap < 15.0 else str(int(roundf(gap / 10.0) * 10.0))), ng, "R" if nx["side"] > 0.0 else "L"]
		if rng.randf() < 0.75:
			text += "\n" + _say("rally_aside")
		arrow = c["side"]
	else:
		rally_left -= 1
		var sym: String = {"hairpin": "hairpin", "constant": "long", "pad": "long", "switchback": "switch", "esses": "switch", "double_apex": "long", "decreasing": "long"}.get(kind, "tease")
		text = _say(sym if rng.randf() < 0.65 else "tease")
	var out: float = -c["side"]  # write on the outside of the corner
	_place_text(c["apex"], out, text, c["len"], arrow)


func _life_note(from: int, kind: String) -> void:
	var rng: RandomNumberGenerator = g.rng
	var text := ""
	match kind:
		"list":  # a shopping list: one item crossed out, one squeezed in later
			var items := ["milk", "eggs", "bread", "AA batteries", "rice", "onions", "tea", "biscuits", "dish soap", "bananas", "printer ink", "glue stick", "coffee", "chilli", "birthday card", "bin bags", "toothpaste", "lemons", "yoghurt"]
			for k in range(items.size() - 1, 0, -1):  # shuffle, then take from the top: no item twice
				var j := rng.randi_range(0, k)
				var tmp: String = items[k]
				items[k] = items[j]
				items[j] = tmp
			var head: String = ["shopping", "get:", "buy", "list", "mum's list"][rng.randi() % 5]
			var lines := PackedStringArray([head])
			var n := rng.randi_range(3, 5)
			for i in n:
				var it: String = items[i]
				lines.append(("~%s~" % it) if i == 1 and rng.randf() < 0.5 else ("- " + it))
			if rng.randf() < 0.5:
				lines.append("+ " + items[n] + "??")
			text = "\n".join(lines)
		"sum":  # half a maths problem, sometimes wrong and fixed
			var a := rng.randi_range(2, 9)
			var x := rng.randi_range(2, 12)
			var b := rng.randi_range(1, 20)
			var c := a * x + b
			text = "%dx + %d = %d\n%dx = %d" % [a, b, c, a, c - b]
			match rng.randi() % 3:
				0:
					text += "\nx = %d" % x
				1:
					text += "\nx = ~%d~ %d" % [x + rng.randi_range(1, 3), x]
				_:
					text += "\nx = ??"
		"phone":
			var num := "%d%d%d %d%d%d %d%d%d%d" % [9, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10, rng.randi() % 10]
			text = _expand("[her number|his number|the plumber|landlord|old number]", 0) + "\n" + num
			if rng.randf() < 0.45:
				text = "\n".join(Array(text.split("\n")).map(func(l): return "~" + l + "~"))
		_:
			text = _say(kind)
	var i := rng.randi_range(from, g.road.size() - 1)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	_place_text(g.road[i], side, text, g.lens[i], 0.0, i)


## Puts handwriting on free paper beside the road near `at`, on side `out` of the road.
func _place_text(at: Vector2, out: float, text: String, at_len: float, arrow: float, idx := -1) -> void:
	var rng: RandomNumberGenerator = g.rng
	var size: float = writer["size"] * rng.randf_range(0.9, 1.1)
	# wrap long lines the way a hand would, at about 16-24 letters
	var wrap := rng.randi_range(16, 24)
	var lines := PackedStringArray()
	for raw in text.split("\n"):
		var cur := ""
		for wd in raw.split(" "):
			if cur != "" and (cur + " " + wd).replace("~", "").length() > wrap and cur.count("~") % 2 == 0:
				lines.append(cur)
				cur = wd
			else:
				cur = wd if cur == "" else cur + " " + wd
		lines.append(cur)
	var wmax := 0.0
	for l in lines:
		wmax = maxf(wmax, l.length() * size * 0.42)
	var box := Vector2(wmax + 20.0, lines.size() * size * 1.15 + 10.0 + (40.0 if arrow != 0.0 else 0.0))
	var p := _free_spot(at, out, box, idx)
	if p == Vector2.INF:
		return
	var w := writer.duplicate()
	var seed := rng.randi()
	var n := DrawNode.new()
	n.position = p
	n.rotation = float(w["tilt"]) + rng.randf_range(-0.05, 0.05)
	n.draw_fn = func(c: Node2D): _draw_text(c, lines, w, size, seed, arrow)
	under.add_child(n)
	bits.append({"node": n, "len": at_len + 900.0})


func _draw_text(c: Node2D, lines: PackedStringArray, w: Dictionary, size: float, seed: int, arrow: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var font: Font = fonts[int(w["font"])]
	var col: Color = w["col"]
	var mess: float = w["mess"]
	var y := 0.0
	for line in lines:
		var x := r.randf_range(-4.0, 4.0) * mess
		var strike := false
		var strike_from := 0.0
		var baseline_drift := r.randf_range(-0.04, 0.04) * mess
		var txt := line.to_upper() if w["caps"] else line
		var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
		# one wobble per word (not per letter): the hand still shows, and the phone draws far less
		for word in txt.split(" "):
			if word == "":
				continue
			if word == "↓":
				_arrow(c, Vector2(x + 6, y - size * 0.7), Vector2(x + 6, y + 2), col, float(w["w"]), r)
				x += size * 0.5 + space
				continue
			var starts := word.begins_with("~")
			var ends := word.ends_with("~") and word.length() > 1
			var plain := word.replace("~", "")
			if starts:
				strike = true
				strike_from = x
			var cy := y + x * baseline_drift + r.randf_range(-1.2, 1.2) * mess
			c.draw_set_transform_matrix(Transform2D(r.randf_range(-0.035, 0.035) * mess, Vector2.ONE, float(w["slant"]), Vector2(x, cy)))
			c.draw_string(font, Vector2.ZERO, plain, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), Color(col, col.a * r.randf_range(0.88, 1.0)))
			c.draw_set_transform(Vector2.ZERO)
			x += font.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x * r.randf_range(0.98, 1.04)
			if ends and strike:
				_wobble_line(c, Vector2(strike_from - 2, y - size * 0.3), Vector2(x + 2, y - size * 0.3 + r.randf_range(-2, 2)), col, float(w["w"]) * 1.2, r)
				strike = false
			x += space * r.randf_range(0.9, 1.2)
		y += size * r.randf_range(1.05, 1.25)
	if arrow != 0.0:  # a curved arrow bending the way the corner goes
		var pts := PackedVector2Array()
		for k in 9:
			var t := k / 8.0
			pts.append(Vector2(14.0 + arrow * 26.0 * (1.0 - cos(t * 1.4)), y + 30.0 - 30.0 * sin(t * 1.4)))
		_hand_poly(c, pts, col, float(w["w"]), r)
		var tip := pts[pts.size() - 1]
		var d := (tip - pts[pts.size() - 2]).normalized()
		_wobble_line(c, tip, tip - d.rotated(0.5) * 9.0, col, float(w["w"]), r)
		_wobble_line(c, tip, tip - d.rotated(-0.5) * 9.0, col, float(w["w"]), r)


# ---------------------------------------------------------------- hand strokes

## A line drawn by hand: slightly bowed, a little wobble, a small overshoot.
func _wobble_line(c: Node2D, a: Vector2, b: Vector2, col: Color, w: float, r: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array()
	var n := maxi(3, int(a.distance_to(b) / 8.0))
	var nrm := (b - a).normalized().orthogonal()
	var bow := r.randf_range(-0.04, 0.04) * a.distance_to(b)
	for k in n + 1:
		var t := float(k) / n
		pts.append(a.lerp(b, t * 1.03) + nrm * (bow * sin(t * PI) + r.randf_range(-0.5, 0.5)))
	c.draw_polyline(pts, col, w, true)


func _hand_poly(c: Node2D, pts: PackedVector2Array, col: Color, w: float, r: RandomNumberGenerator) -> void:
	var q := PackedVector2Array()
	for p in pts:
		q.append(p + Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.6, 0.6)))
	c.draw_polyline(q, col, w, true)


func _arrow(c: Node2D, a: Vector2, b: Vector2, col: Color, w: float, r: RandomNumberGenerator) -> void:
	_wobble_line(c, a, b, col, w, r)
	var d := (b - a).normalized()
	_wobble_line(c, b, b - d.rotated(0.55) * 8.0, col, w, r)
	_wobble_line(c, b, b - d.rotated(-0.55) * 8.0, col, w, r)


# ---------------------------------------------------------------- doodles

## A doodle: picks a shape family and draws it with random proportions, in the current writer's pen.
func _doodle(from: int, big: bool) -> void:
	var rng: RandomNumberGenerator = g.rng
	var i := rng.randi_range(from, g.road.size() - 1)
	var size := rng.randf_range(110.0, 160.0) if big else rng.randf_range(40.0, 90.0)
	var box := Vector2(size * 1.8, size * 1.5) if big else Vector2(size, size) * 1.3
	var p := _free_spot(g.road[i], 1.0 if rng.randf() < 0.5 else -1.0, box, i)
	if p == Vector2.INF:
		return
	p += box * 0.5 - Vector2(0, 21)  # doodles are drawn around their middle: centre them in their space
	if big:
		var bkind: String = _cycle("big_kind", ["speech", "think", "caption"])
		var line := _say("speech" if bkind == "speech" else "think" if bkind == "think" else "caption")
		var wb := writer.duplicate()
		var sb := rng.randi()
		var nb := DrawNode.new()
		nb.position = p
		nb.draw_fn = func(c: Node2D): _draw_big(c, bkind, size, wb, sb, line)
		under.add_child(nb)
		bits.append({"node": nb, "len": g.lens[i] + 900.0})
		return
	var kind: String = ["figure", "spiral", "sun", "cube", "star", "face", "tally", "grid", "heart", "bolt", "flag", "cloud", "waves", "cat"][rng.randi() % 14]
	var w := writer.duplicate()
	var seed := rng.randi()
	var n := DrawNode.new()
	n.position = p
	n.rotation = rng.randf_range(-0.3, 0.3)
	n.draw_fn = func(c: Node2D): _draw_doodle(c, kind, size, w, seed)
	under.add_child(n)
	bits.append({"node": n, "len": g.lens[i] + 900.0})


func _draw_doodle(c: Node2D, kind: String, s: float, w: Dictionary, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var col: Color = w["col"]
	var lw: float = w["w"]
	match kind:
		"figure":  # a stick figure, arms anywhere from waving to cheering
			var head := s * r.randf_range(0.14, 0.2)
			_circle(c, Vector2(0, -s * 0.45), head, col, lw, r)
			var neck := Vector2(0, -s * 0.45 + head)
			var hip := neck + Vector2(r.randf_range(-3, 3), s * 0.38)
			_wobble_line(c, neck, hip, col, lw, r)
			for side in [-1.0, 1.0]:
				var arm_up := r.randf_range(-1.3, 0.6)
				_wobble_line(c, neck + Vector2(0, s * 0.08), neck + Vector2(0, s * 0.08) + Vector2(side * s * 0.3, 0).rotated(side * arm_up), col, lw, r)
				_wobble_line(c, hip, hip + Vector2(side * s * r.randf_range(0.12, 0.22), s * 0.32), col, lw, r)
			if r.randf() < 0.4:  # holding a little flag
				var hand := neck + Vector2(s * 0.3, s * 0.08).rotated(-0.9)
				_wobble_line(c, hand, hand + Vector2(0, -s * 0.35), col, lw, r)
				_hand_poly(c, PackedVector2Array([hand + Vector2(0, -s * 0.35), hand + Vector2(s * 0.22, -s * 0.28), hand + Vector2(0, -s * 0.2)]), col, lw, r)
		"spiral":
			var pts := PackedVector2Array()
			var turns := r.randf_range(2.5, 5.0)
			var steps := int(turns * 24)
			for k in steps:
				var t := float(k) / steps
				pts.append(Vector2.from_angle(t * turns * TAU) * t * s * 0.5 + Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.6, 0.6)))
			c.draw_polyline(pts, col, lw, true)
		"sun":
			var rr := s * r.randf_range(0.18, 0.26)
			_circle(c, Vector2.ZERO, rr, col, lw, r)
			var rays := r.randi_range(6, 12)
			for k in rays:
				var a := TAU * k / rays + r.randf_range(-0.1, 0.1)
				_wobble_line(c, Vector2.from_angle(a) * (rr + 4), Vector2.from_angle(a) * (rr + s * r.randf_range(0.15, 0.3)), col, lw, r)
		"cube":
			var a := s * r.randf_range(0.35, 0.5)
			var off := Vector2(a * r.randf_range(0.3, 0.5), -a * r.randf_range(0.3, 0.5))
			var q := [Vector2(-a, -a) * 0.5, Vector2(a, -a) * 0.5, Vector2(a, a) * 0.5, Vector2(-a, a) * 0.5]
			for k in 4:
				_wobble_line(c, q[k], q[(k + 1) % 4], col, lw, r)
				_wobble_line(c, q[k] + off, q[(k + 1) % 4] + off, col, lw, r)
				_wobble_line(c, q[k], q[k] + off, col, lw, r)
		"star":
			var pts := r.randi_range(5, 6)
			var big := s * 0.45
			var small := big * r.randf_range(0.38, 0.5)
			var poly := PackedVector2Array()
			for k in pts * 2 + 1:
				poly.append(Vector2.from_angle(-PI / 2 + PI * k / pts) * (big if k % 2 == 0 else small))
			_hand_poly(c, poly, col, lw, r)
		"face":
			var rr := s * 0.4
			_circle(c, Vector2.ZERO, rr, col, lw, r)
			for side in [-1.0, 1.0]:
				_wobble_line(c, Vector2(side * rr * 0.35, -rr * 0.2), Vector2(side * rr * 0.35, -rr * 0.05), col, lw, r)
			var mood := r.randf_range(-1.0, 1.0)  # smile .. frown
			var m := PackedVector2Array()
			for k in 9:
				var t := k / 8.0 - 0.5
				m.append(Vector2(t * rr, rr * 0.35 + mood * (0.25 - t * t) * rr * 0.6))
			_hand_poly(c, m, col, lw, r)
		"tally":
			var n := r.randi_range(3, 12)
			for k in n:
				var x := (k % 5) * 8.0 + (k / 5) * 52.0
				if k % 5 == 4:
					_wobble_line(c, Vector2(x - 36, s * 0.3), Vector2(x + 4, -s * 0.05), col, lw, r)
				else:
					_wobble_line(c, Vector2(x, -s * 0.1), Vector2(x + r.randf_range(-2, 2), s * 0.32), col, lw, r)
		"grid":  # a noughts and crosses game nobody finished
			var a := s * 0.33
			for k in [-0.5, 0.5]:
				_wobble_line(c, Vector2(k * a, -a * 1.5), Vector2(k * a, a * 1.5), col, lw, r)
				_wobble_line(c, Vector2(-a * 1.5, k * a), Vector2(a * 1.5, k * a), col, lw, r)
			for k in r.randi_range(2, 6):
				var cell := Vector2((r.randi() % 3 - 1) * a, (r.randi() % 3 - 1) * a)
				if k % 2 == 0:
					_wobble_line(c, cell + Vector2(-a, -a) * 0.3, cell + Vector2(a, a) * 0.3, col, lw, r)
					_wobble_line(c, cell + Vector2(a, -a) * 0.3, cell + Vector2(-a, a) * 0.3, col, lw, r)
				else:
					_circle(c, cell, a * 0.3, col, lw, r)
		"heart":
			var pts := PackedVector2Array()
			for k in 33:
				var t := TAU * k / 32.0
				pts.append(Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * s * 0.022)
			_hand_poly(c, pts, col, lw, r)
		"bolt":
			var pts := PackedVector2Array([Vector2(s * 0.1, -s * 0.5), Vector2(-s * 0.15, 0), Vector2(s * 0.08, 0), Vector2(-s * 0.1, s * 0.5)])
			_hand_poly(c, pts, col, lw, r)
		"flag":
			_wobble_line(c, Vector2(0, s * 0.5), Vector2(0, -s * 0.5), col, lw, r)
			var f := PackedVector2Array()
			for k in 7:
				var t := k / 6.0
				f.append(Vector2(t * s * 0.45, -s * 0.5 + sin(t * TAU) * 3.0))
			for k in range(6, -1, -1):
				var t := k / 6.0
				f.append(Vector2(t * s * 0.45, -s * 0.2 + sin(t * TAU) * 3.0))
			_hand_poly(c, f, col, lw, r)
		"cloud":
			var bumps := r.randi_range(4, 7)
			var pts := PackedVector2Array()
			for k in bumps * 6 + 1:
				var a := TAU * k / (bumps * 6)
				pts.append(Vector2(cos(a) * s * 0.5, sin(a) * s * 0.28) * (1.0 + 0.18 * absf(sin(a * bumps * 0.5))))
			_hand_poly(c, pts, col, lw, r)
		"waves":
			for row in r.randi_range(2, 4):
				var pts := PackedVector2Array()
				for k in 21:
					var t := k / 20.0
					pts.append(Vector2((t - 0.5) * s, row * 10.0 + sin(t * TAU * 2.0 + row) * 4.0))
				_hand_poly(c, pts, col, lw, r)
		_:  # a cat, in a few loose strokes
			var rr := s * 0.3
			_circle(c, Vector2.ZERO, rr, col, lw, r)
			for side in [-1.0, 1.0]:
				_hand_poly(c, PackedVector2Array([Vector2(side * rr * 0.55, -rr * 0.75), Vector2(side * rr * 0.75, -rr * 1.35), Vector2(side * rr * 0.15, -rr * 0.95)]), col, lw, r)
				for k in 2:
					_wobble_line(c, Vector2(side * rr * 0.4, rr * 0.2 + k * 6), Vector2(side * rr * 1.3, rr * 0.05 + k * 12), col, lw * 0.7, r)
				c.draw_circle(Vector2(side * rr * 0.35, -rr * 0.1), 2.0, col)


## A proper little drawing (not a doodle) with a line underneath about someone who said he couldn't.
func _drawing(from: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var obj := _cycle("drawing_obj", ["house", "tree", "car", "flower", "mountains", "mug", "bicycle", "cat"])
	var i := rng.randi_range(from, g.road.size() - 1)
	var p := _free_spot(g.road[i], 1.0 if rng.randf() < 0.5 else -1.0, Vector2(240, 230), i)
	if p == Vector2.INF:
		return
	slots = {"obj": {"mountains": "mountain"}.get(obj, obj)}
	var cap := _say("proof")
	slots = {}
	var w := writer.duplicate()
	var seed := rng.randi()
	var n := DrawNode.new()
	n.position = p
	n.rotation = rng.randf_range(-0.06, 0.06)
	n.draw_fn = func(c: Node2D):
		var r := RandomNumberGenerator.new()
		r.seed = seed
		_draw_obj(c, obj, w, r)
		_wrap_text(c, fonts[int(w["font"])], cap, Vector2(-10, 125), 240.0, int(clampf(float(w["size"]) * 0.8, 20.0, 26.0)), w["col"])
	under.add_child(n)
	bits.append({"node": n, "len": g.lens[i] + 900.0})


## The drawings themselves, sketched with random proportions: no two houses (or cats) come out the same.
func _draw_obj(c: Node2D, obj: String, w: Dictionary, r: RandomNumberGenerator) -> void:
	var col: Color = w["col"]
	var lw: float = w["w"]
	var cx := 110.0
	match obj:
		"house":
			var bw := r.randf_range(90.0, 120.0)
			var bh := r.randf_range(60.0, 80.0)
			var base := Vector2(cx - bw * 0.5, 100)
			_box(c, Rect2(base - Vector2(0, bh), Vector2(bw, bh)), col, lw, r)
			_hand_poly(c, PackedVector2Array([base - Vector2(10, bh), Vector2(cx + r.randf_range(-8, 8), 100 - bh - r.randf_range(35, 55)), base + Vector2(bw + 10, -bh)]), col, lw, r)
			_box(c, Rect2(Vector2(cx - 10, 100 - 36), Vector2(20, 36)), col, lw, r)  # door
			for k in [-1.0, 1.0]:
				var win := Vector2(cx + k * bw * 0.3 - 10, 100 - bh + 14)
				_box(c, Rect2(win, Vector2(20, 18)), col, lw, r)
				_wobble_line(c, win + Vector2(10, 0), win + Vector2(10, 18), col, lw * 0.8, r)
			if r.randf() < 0.6:  # chimney and smoke
				var ch := Vector2(cx + bw * 0.25, 100 - bh - 30)
				_box(c, Rect2(ch, Vector2(12, 22)), col, lw, r)
				for k in 3:
					_circle(c, ch + Vector2(6 + k * 9, -10 - k * 12), 5.0 + k * 2.0, col, lw * 0.8, r)
		"tree":
			var th := r.randf_range(40.0, 60.0)
			_wobble_line(c, Vector2(cx - 7, 100), Vector2(cx - 5, 100 - th), col, lw, r)
			_wobble_line(c, Vector2(cx + 7, 100), Vector2(cx + 5, 100 - th), col, lw, r)
			var blobs := r.randi_range(5, 8)
			for k in blobs:
				var a := PI + PI * k / (blobs - 1)
				_circle(c, Vector2(cx, 100 - th - 25) + Vector2(cos(a) * 34, sin(a) * 26 * 0.9), r.randf_range(16, 24), col, lw, r)
		"car":
			var L := r.randf_range(130.0, 160.0)
			var x0 := cx - L * 0.5
			_hand_poly(c, PackedVector2Array([Vector2(x0, 85), Vector2(x0, 65), Vector2(x0 + L * 0.25, 62), Vector2(x0 + L * 0.38, 40), Vector2(x0 + L * 0.7, 40), Vector2(x0 + L * 0.82, 62), Vector2(x0 + L, 66), Vector2(x0 + L, 85), Vector2(x0, 85)]), col, lw, r)
			_wobble_line(c, Vector2(x0 + L * 0.55, 42), Vector2(x0 + L * 0.55, 62), col, lw * 0.8, r)
			for k in [0.22, 0.78]:
				_circle(c, Vector2(x0 + L * k, 86), 13.0, col, lw, r)
				_circle(c, Vector2(x0 + L * k, 86), 5.0, col, lw * 0.8, r)
			for k in 3:  # speed lines, because obviously
				_wobble_line(c, Vector2(x0 - 14 - k * 4, 52 + k * 11), Vector2(x0 - 40 - k * 6, 52 + k * 11), col, lw * 0.7, r)
		"flower":
			_hand_poly(c, PackedVector2Array([Vector2(cx, 100), Vector2(cx + 4, 70), Vector2(cx - 2, 45)]), col, lw, r)
			_hand_poly(c, PackedVector2Array([Vector2(cx + 2, 80), Vector2(cx + 24, 70), Vector2(cx + 3, 74)]), col, lw, r)  # leaf
			var petals := r.randi_range(5, 8)
			for k in petals:
				_circle(c, Vector2(cx - 2, 30) + Vector2.from_angle(TAU * k / petals) * 15.0, 10.0, col, lw, r)
			_circle(c, Vector2(cx - 2, 30), 7.0, col, lw, r)
		"mountains":
			var peaks := PackedVector2Array([Vector2(cx - 100, 100)])
			var x := cx - 100.0
			while x < cx + 100.0:
				x += r.randf_range(30.0, 55.0)
				peaks.append(Vector2(minf(x, cx + 100), 100 - r.randf_range(35.0, 85.0) if peaks.size() % 2 == 1 else 100 - r.randf_range(10.0, 30.0)))
			peaks.append(Vector2(cx + 100, 100))
			_hand_poly(c, peaks, col, lw, r)
			_circle(c, Vector2(cx + r.randf_range(30, 70), 8), 14.0, col, lw, r)  # sun
			for k in 2:  # birds
				var b := Vector2(cx - 60 + k * 26, 14 + k * 6)
				_hand_poly(c, PackedVector2Array([b, b + Vector2(7, 5), b + Vector2(14, 0)]), col, lw * 0.8, r)
		"mug":
			_hand_poly(c, PackedVector2Array([Vector2(cx - 30, 40), Vector2(cx - 26, 100), Vector2(cx + 26, 100), Vector2(cx + 30, 40)]), col, lw, r)
			var rim := PackedVector2Array()
			for k in 25:
				var a := TAU * k / 24.0
				rim.append(Vector2(cx + cos(a) * 30, 40 + sin(a) * 7))
			_hand_poly(c, rim, col, lw, r)
			_circle(c, Vector2(cx + 38, 66), 12.0, col, lw, r)
			for k in 3:  # steam
				var st := PackedVector2Array()
				for j in 8:
					st.append(Vector2(cx - 12 + k * 12 + sin(j * 0.9 + k) * 4, 30 - j * 5))
				_hand_poly(c, st, col, lw * 0.8, r)
		"bicycle":
			var wr := r.randf_range(22.0, 28.0)
			var a := Vector2(cx - 45, 80)
			var b := Vector2(cx + 45, 80)
			_circle(c, a, wr, col, lw, r)
			_circle(c, b, wr, col, lw, r)
			var seat := Vector2(cx - 15, 40)
			var bar := Vector2(cx + 30, 38)
			var crank := Vector2(cx - 5, 80)
			_hand_poly(c, PackedVector2Array([a, seat, crank, a]), col, lw, r)
			_hand_poly(c, PackedVector2Array([seat, bar, crank]), col, lw, r)
			_wobble_line(c, bar, b, col, lw, r)
			_wobble_line(c, seat, seat + Vector2(-8, -8), col, lw, r)
			_wobble_line(c, bar + Vector2(-6, -10), bar + Vector2(8, -10), col, lw, r)
		_:  # a cat sitting, from behind, tail curled
			_circle(c, Vector2(cx, 40), 18.0, col, lw, r)
			for sd in [-1.0, 1.0]:
				_hand_poly(c, PackedVector2Array([Vector2(cx + sd * 8, 25), Vector2(cx + sd * 16, 10), Vector2(cx + sd * 18, 30)]), col, lw, r)
			var body := PackedVector2Array()
			for k in 21:
				var t := PI * k / 20.0
				body.append(Vector2(cx + cos(t + PI) * -30.0 * 0.9, 100 - sin(t) * 46.0) if false else Vector2(cx - cos(t) * 28.0, 100 - sin(t) * 44.0))
			_hand_poly(c, body, col, lw, r)
			var tail := PackedVector2Array()
			for k in 12:
				var t := k / 11.0
				tail.append(Vector2(cx + 28 + t * 26, 100 - t * 30) + Vector2(sin(t * 4) * 4, 0))
			_hand_poly(c, tail, col, lw, r)


## A meme, redrawn by hand in the page's pen: the format cycles so none comes twice running, captions come
## from the grammar.
func _meme(from: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var fmt := _cycle("meme_fmt", ["choice", "nobody", "honest", "plan"])
	var i := rng.randi_range(from, g.road.size() - 1)
	var box := Vector2(250, 190)
	var p := _free_spot(g.road[i], 1.0 if rng.randf() < 0.5 else -1.0, box, i)
	if p == Vector2.INF:
		return
	var text := ""
	match fmt:
		"choice":
			slots = {"hw": _expand("{homework_short}", 0)}
			text = _say("meh_good")
			slots = {}
		"nobody":
			text = "nobody:\nme at %s: %s" % [_expand("{late}", 0), _say("nobody_me")]
		"starter":
			text = _expand("{starter_who}", 0) + " starter pack"
		"honest":
			text = "it ain't much, but it's honest " + _expand("{honest_word}", 0)
		_:
			text = "the plan|what happened"
	var w := writer.duplicate()
	var seed := rng.randi()
	var n := DrawNode.new()
	n.position = p
	n.rotation = rng.randf_range(-0.08, 0.08)
	n.draw_fn = func(c: Node2D): _draw_meme(c, fmt, text, w, seed)
	under.add_child(n)
	bits.append({"node": n, "len": g.lens[i] + 900.0})


## Cycles through a list using the same saved deck system.
func _cycle(key: String, items: Array) -> String:
	return items[_card(key, items.size())]


func _draw_meme(c: Node2D, fmt: String, text: String, w: Dictionary, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var col: Color = w["col"]
	var lw: float = w["w"]
	var font: Font = fonts[int(w["font"])]
	var fs := int(clampf(float(w["size"]) * 0.8, 20.0, 26.0))
	match fmt:
		"choice":  # two stacked panels: turning away from the first, pointing at the second
			var parts := text.split("|")
			for k in 2:
				var y := k * 90.0
				_box(c, Rect2(0, y, 240, 86), col, lw, r)
				_wobble_line(c, Vector2(80, y), Vector2(80, y + 86), col, lw, r)
				var head := Vector2(40, y + 26)
				_circle(c, head, 11.0, col, lw, r)
				_wobble_line(c, head + Vector2(0, 11), head + Vector2(0, 46), col, lw, r)
				if k == 0:  # hand up, face away
					_wobble_line(c, head + Vector2(0, 20), head + Vector2(-22, 2), col, lw, r)
					_wobble_line(c, head + Vector2(-22, 2), head + Vector2(-20, -14), col, lw, r)
				else:  # pointing at the good one
					_wobble_line(c, head + Vector2(0, 20), head + Vector2(30, 12), col, lw, r)
				_wrap_text(c, font, parts[k] if k < parts.size() else "", Vector2(90, y + 26), 145.0, fs, col)
		"nobody":
			_wrap_text(c, font, text, Vector2(0, 20), 230.0, fs, col)
		"starter":  # a title and four little sketches in boxes
			c.draw_string(font, Vector2(0, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			var packs := {"drifter": ["tyre", "ring", "sock", "pencil"], "night owl": ["cup", "ring", "pencil", "sock"], "notebook artist": ["pencil", "eraser", "ring", "cup"], "hopeless romantic": ["cup", "sock", "pencil", "ring"], "designer": ["pencil", "eraser", "cup", "ring"]}
			var who := text.replace(" starter pack", "")
			var pool: Array = packs.get(who, ["pencil", "eraser", "cup", "ring"])
			for k in 4:
				var cell := Rect2((k % 2) * 120.0, 30.0 + (k / 2) * 78.0, 112, 72)
				_box(c, cell, col, lw, r)
				_mini(c, pool[k], cell.get_center(), col, lw, r)
		"honest":
			var fig := Vector2(40, 60)
			_circle(c, fig, 12.0, col, lw, r)
			_wobble_line(c, fig + Vector2(0, 12), fig + Vector2(0, 52), col, lw, r)
			_wobble_line(c, fig + Vector2(0, 52), fig + Vector2(-12, 80), col, lw, r)
			_wobble_line(c, fig + Vector2(0, 52), fig + Vector2(12, 80), col, lw, r)
			_wobble_line(c, fig + Vector2(0, 24), fig + Vector2(30, 40), col, lw, r)  # proudly showing it
			for side in [-1.0, 1.0]:  # a tiny road
				var rd := PackedVector2Array()
				for k in 12:
					var t := k / 11.0
					rd.append(Vector2(90 + t * 130, 120 + side * 9 + sin(t * 5.0) * 10.0))
				_hand_poly(c, rd, col, lw, r)
			_wrap_text(c, font, text, Vector2(0, 160), 240.0, fs, col)
		_:  # the plan vs what happened
			var parts := text.split("|")
			_box(c, Rect2(0, 0, 115, 120), col, lw, r)
			_box(c, Rect2(125, 0, 115, 120), col, lw, r)
			var neat := PackedVector2Array()
			for k in 16:
				var t := k / 15.0
				neat.append(Vector2(15 + t * 85, 60 + sin(t * TAU) * 25))
			c.draw_polyline(neat, col, lw, true)
			var mess := PackedVector2Array()
			var pp := Vector2(140, 60)
			for k in 40:
				pp += Vector2(r.randf_range(-9, 12), r.randf_range(-14, 14))
				pp = pp.clamp(Vector2(132, 10), Vector2(232, 110))
				mess.append(pp)
			c.draw_polyline(mess, col, lw, true)
			c.draw_string(font, Vector2(10, 146), parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			c.draw_string(font, Vector2(132, 146), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _box(c: Node2D, rc: Rect2, col: Color, w: float, r: RandomNumberGenerator) -> void:
	var a := rc.position
	var b := rc.position + Vector2(rc.size.x, 0)
	var d := rc.end
	var e := rc.position + Vector2(0, rc.size.y)
	for seg in [[a, b], [b, d], [d, e], [e, a]]:
		_wobble_line(c, seg[0], seg[1], col, w, r)


func _wrap_text(c: Node2D, font: Font, text: String, at: Vector2, width: float, fs: int, col: Color) -> void:
	var y := at.y
	for para in text.split("\n"):
		var line := ""
		for wd in para.split(" "):
			if line != "" and font.get_string_size(line + " " + wd, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				c.draw_string(font, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				line = wd
				y += fs * 1.1
			else:
				line = wd if line == "" else line + " " + wd
		c.draw_string(font, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += fs * 1.2


## Small sketches for the starter pack.
func _mini(c: Node2D, what: String, at: Vector2, col: Color, w: float, r: RandomNumberGenerator) -> void:
	match what:
		"tyre":
			_circle(c, at, 22.0, col, w, r)
			_circle(c, at, 11.0, col, w, r)
			for k in 10:
				var a := TAU * k / 10.0
				_wobble_line(c, at + Vector2.from_angle(a) * 22.0, at + Vector2.from_angle(a) * 27.0, col, w, r)
		"ring":
			_circle(c, at, 22.0, Color(0.45, 0.28, 0.12, 0.7), w * 1.4, r)
		"eraser":
			_box(c, Rect2(at - Vector2(26, 12), Vector2(52, 24)), col, w, r)
			_wobble_line(c, at + Vector2(-4, -12), at + Vector2(-4, 12), col, w, r)
		"sock":
			_hand_poly(c, PackedVector2Array([at + Vector2(-8, -26), at + Vector2(8, -26), at + Vector2(8, 6), at + Vector2(22, 14), at + Vector2(18, 26), at + Vector2(-6, 20), at + Vector2(-8, -26)]), col, w, r)
		"pencil":
			_hand_poly(c, PackedVector2Array([at + Vector2(-34, -5), at + Vector2(24, -5), at + Vector2(34, 0), at + Vector2(24, 5), at + Vector2(-34, 5), at + Vector2(-34, -5)]), col, w, r)
		"cup":
			_hand_poly(c, PackedVector2Array([at + Vector2(-16, -18), at + Vector2(-12, 20), at + Vector2(12, 20), at + Vector2(16, -18)]), col, w, r)
			_circle(c, at + Vector2(20, 0), 8.0, col, w, r)
		_:
			_circle(c, at, 18.0, col, w, r)
			_wobble_line(c, at + Vector2(-18, 0), at + Vector2(18, 0), col, w, r)


## A bigger drawing: a stick figure saying something, a cat thinking something, or a doodle with a caption.
func _draw_big(c: Node2D, kind: String, s: float, w: Dictionary, seed: int, line: String) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var col: Color = w["col"]
	var lw: float = w["w"]
	var font: Font = fonts[int(w["font"])]
	var size := int(clampf(float(w["size"]), 24.0, 30.0))
	var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if kind == "caption":  # the doodle the caption is about, with the caption underneath
		var parts := line.split("|")
		var cap := parts[0]
		_draw_doodle(c, parts[1] if parts.size() > 1 else "face", s * 0.8, w, seed)
		var cw := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c.draw_string(font, Vector2(-cw * 0.5, s * 0.75), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		return
	_draw_doodle(c, "figure" if kind == "speech" else "cat", s * 0.8, w, seed)
	var bc := Vector2(s * 0.55 + tw * 0.5, -s * 0.85)  # bubble up and to the side
	var rx := tw * 0.5 + 18.0
	var ry := size * 0.9 + 6.0
	var pts := PackedVector2Array()
	var start := r.randf() * TAU
	for k in 37:
		var a := start + (TAU + 0.15) * k / 36.0
		pts.append(bc + Vector2(cos(a) * rx, sin(a) * ry) * (1.0 + r.randf_range(-0.03, 0.03)))
	if kind == "speech":
		c.draw_polyline(pts, col, lw, true)
		_hand_poly(c, PackedVector2Array([bc + Vector2(-rx * 0.5, ry * 0.7), Vector2(s * 0.12, -s * 0.5), bc + Vector2(-rx * 0.2, ry * 0.95)]), col, lw, r)
	else:  # thought: a cloud of bumps and two little circles down to the head
		var cloud := PackedVector2Array()
		var bumps := 9
		for k in bumps * 6 + 1:
			var a := TAU * k / (bumps * 6)
			cloud.append(bc + Vector2(cos(a) * rx, sin(a) * ry) * (1.0 + 0.1 * absf(sin(a * bumps * 0.5))))
		_hand_poly(c, cloud, col, lw, r)
		_circle(c, bc.lerp(Vector2(0, -s * 0.3), 0.55), 7.0, col, lw, r)
		_circle(c, bc.lerp(Vector2(0, -s * 0.3), 0.78), 4.0, col, lw, r)
	c.draw_string(font, bc + Vector2(-tw * 0.5, size * 0.35), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _circle(c: Node2D, at: Vector2, rr: float, col: Color, w: float, r: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array()
	var start := r.randf() * TAU
	var over := r.randf_range(0.05, 0.3)  # hand circles rarely close exactly
	var n := 28
	for k in n + 1:
		var a := start + (TAU + over) * k / n
		pts.append(at + Vector2.from_angle(a) * rr * (1.0 + r.randf_range(-0.04, 0.04)))
	c.draw_polyline(pts, col, w, true)


# ---------------------------------------------------------------- abandoned roads, corrections, sticky notes

## The road the artist first tried: a faint half-erased stub branching off, closed with a coloured-pencil
## cross or hatching, eraser crumbs about, sometimes a word.
func _ghost_road(from: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var i := rng.randi_range(from + 5, maxi(from + 6, g.road.size() - 40))
	if i >= g.road.size() - 2:
		return
	var dir: float = g._dir_at(i) + rng.randf_range(-0.7, 0.7)
	var length := rng.randf_range(260.0, 480.0)
	var half: float = g.widths[i] * 0.5
	var start: Vector2 = g.road[i]
	var end := start + Vector2.from_angle(dir) * length
	if _hits_road(end, half + 40.0, i):
		return
	var seed := rng.randi()
	var cross_col: Color = [Color(0.85, 0.2, 0.2, 0.7), Color(0.95, 0.55, 0.1, 0.7), Color(0.2, 0.5, 0.85, 0.7)][rng.randi() % 3]
	var word := "" if rng.randf() < 0.5 else _expand("[NO|dead end|closed|nope|x|wrong way|scrap this]", 0)
	var w := writer.duplicate()
	var n := DrawNode.new()
	n.draw_fn = func(c: Node2D):
		var r := RandomNumberGenerator.new()
		r.seed = seed
		var nrm := Vector2.from_angle(dir + PI * 0.5)
		for side in [-1.0, 1.0]:
			var a: Vector2 = start + nrm * side * half + Vector2.from_angle(dir) * half
			var t := 0.0
			while t < length:  # broken, faint: mostly rubbed out
				var seg := r.randf_range(20.0, 70.0)
				if r.randf() < 0.65:
					_wobble_line(c, a + Vector2.from_angle(dir) * t, a + Vector2.from_angle(dir) * minf(length, t + seg), Color(0.3, 0.3, 0.33, r.randf_range(0.08, 0.2)), 2.4, r)
				t += seg + r.randf_range(5.0, 25.0)
		for k in r.randi_range(6, 14):  # eraser crumbs
			var p := start + Vector2.from_angle(dir) * r.randf_range(half, length) + nrm * r.randf_range(-half * 1.5, half * 1.5)
			c.draw_colored_polygon(PackedVector2Array([p, p + Vector2(r.randf_range(2, 5), r.randf_range(-1, 2)), p + Vector2(r.randf_range(0, 3), r.randf_range(2, 5))]), Color(0.75, 0.55, 0.55, 0.5))
		var mouth := start + Vector2.from_angle(dir) * (half + r.randf_range(30.0, 70.0))
		if r.randf() < 0.6:  # big cross in coloured pencil, gone over twice
			for pass_k in 2:
				for sgn in [-1.0, 1.0]:
					_wobble_line(c, mouth + nrm * half * 0.9 * sgn + Vector2.from_angle(dir) * -18.0, mouth - nrm * half * 0.9 * sgn + Vector2.from_angle(dir) * 18.0, cross_col, 3.0, r)
		else:  # hatched barrier
			for k in range(-4, 5):
				var p := mouth + nrm * k * half * 0.22
				_wobble_line(c, p - Vector2.from_angle(dir) * 10.0 + nrm * 6.0, p + Vector2.from_angle(dir) * 10.0 - nrm * 6.0, cross_col, 2.6, r)
		if word != "":
			c.draw_string(fonts[int(w["font"])], mouth + nrm * (half + 14.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, int(w["size"]), cross_col.darkened(0.2))
	under.add_child(n)
	bits.append({"node": n, "len": g.lens[i] + 900.0})


## A bit of edge that went wrong: drawn, then scribbled over with a zigzag, with a word about it.
func _oops(from: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var i := rng.randi_range(from + 3, maxi(from + 4, g.road.size() - 30))
	if i + 20 >= g.road.size():
		return
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var pts := PackedVector2Array()
	var dev := rng.randf_range(18.0, 34.0)
	for k in 20:
		var j := i + k
		var nrm := Vector2.from_angle(g._dir_at(j) + PI * 0.5)
		pts.append(g.road[j] + nrm * side * (g.widths[j] * 0.5 + dev * sin(k / 19.0 * PI)))
	var word := _expand("[oops|nope|ugh|wrong|no no|whoops|ignore this|:(|my bad]", 0)
	var ref: Vector2 = g.road[i + 10]
	var w := writer.duplicate()
	var seed := rng.randi()
	var n := DrawNode.new()
	n.draw_fn = func(c: Node2D):
		var r := RandomNumberGenerator.new()
		r.seed = seed
		var col: Color = w["col"]
		c.draw_polyline(pts, Color(col, col.a * 0.7), float(w["w"]) * 1.2, true)
		var zz := PackedVector2Array()  # scribble it out: back and forth along it
		for k in 40:
			var t := k / 39.0
			var j := int(t * (pts.size() - 1))
			var nn := (pts[mini(j + 1, pts.size() - 1)] - pts[maxi(j - 1, 0)]).normalized().orthogonal()
			zz.append(pts[j] + nn * (6.0 if k % 2 == 0 else -6.0) * r.randf_range(0.6, 1.3))
		c.draw_polyline(zz, col, float(w["w"]), true)
		var mid := pts[pts.size() / 2]
		var out := (mid - ref).normalized()
		c.draw_string(fonts[int(w["font"])], mid + out * 30.0, word, HORIZONTAL_ALIGNMENT_LEFT, -1, int(w["size"]), col)
	under.add_child(n)
	bits.append({"node": n, "len": g.lens[i] + 900.0})


## A sticky note stuck beside the road. Real paper grain (the page texture, tinted), edges that aren't quite
## straight, a soft shadow that's tight under the glued top and longer where the bottom corner lifts, the curl
## shaded from its fold, the glue strip a shade darker, written in the page's pen.
func _sticky(from: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var i := rng.randi_range(from, g.road.size() - 1)
	var s := rng.randf_range(190.0, 230.0)
	var p := _free_spot(g.road[i], 1.0 if rng.randf() < 0.5 else -1.0, Vector2(s, s), i)
	if p == Vector2.INF:
		return
	var text := _say(["tease", "dev"][rng.randi() % 2])
	var col: Color = STICKY[rng.randi() % STICKY.size()]
	var w := writer.duplicate()
	var seed := rng.randi()
	var grain: Texture2D = g.paper.texture
	var n := DrawNode.new()
	n.position = p + Vector2(s * 0.5, s * 0.5)
	n.rotation = rng.randf_range(-0.25, 0.25)
	n.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	n.draw_fn = func(c: Node2D):
		var r := RandomNumberGenerator.new()
		r.seed = seed
		var h := s * 0.5
		var curl := r.randf_range(26.0, 44.0)
		# outline with a little irregularity: 6 points per side
		var outline := PackedVector2Array()
		var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h - curl), Vector2(h - curl, h), Vector2(-h, h)]
		for k in corners.size():
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % corners.size()]
			for j in 6:
				outline.append(a.lerp(b, j / 6.0) + Vector2(r.randf_range(-0.8, 0.8), r.randf_range(-0.8, 0.8)))
		# soft shadow: layers, offset more towards the lifted corner
		for k in 5:
			var sh := PackedVector2Array()
			for q in outline:
				var lift := clampf((q.x + q.y) / (s * 1.2), 0.0, 1.0)
				sh.append(q * (1.0 + k * 0.012) + Vector2(2.0, 3.0) + Vector2(5.0, 7.0) * lift * (1.0 + k * 0.3))
			c.draw_colored_polygon(sh, Color(0, 0, 0, 0.045))
		# the paper: page texture tinted, darker towards the bottom
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var off := Vector2(r.randf_range(0, 600), r.randf_range(0, 600))
		for q in outline:
			uvs.append((q + off) / 512.0)
			cols.append(col.darkened(0.07 * clampf((q.y + h) / s, 0.0, 1.0)))
		c.draw_polygon(outline, cols, uvs, grain)
		c.draw_rect(Rect2(-h, -h, s, s * 0.17), Color(0, 0, 0, 0.035))  # the glue strip
		# the curl: its underside, lighter near the fold, darker at the tip, with a crease
		var tip := Vector2(h - curl * 1.15, h - curl * 1.15)
		c.draw_polygon(PackedVector2Array([Vector2(h, h - curl), Vector2(h - curl, h), tip]), PackedColorArray([col.lightened(0.22), col.lightened(0.22), col.darkened(0.05)]), PackedVector2Array([Vector2(0, 0), Vector2(0.06, 0), Vector2(0.03, 0.06)]), grain)
		c.draw_line(Vector2(h, h - curl), Vector2(h - curl, h), Color(0, 0, 0, 0.12), 1.4, true)
		var font: Font = fonts[int(w["font"])]
		var pen: Color = w["col"]
		var words := text.replace("~", "").replace("
", " ").split(" ")
		var size := int(clampf(float(w["size"]) * 1.1, 28.0, 36.0))
		var lines := PackedStringArray()
		while true:  # shrink the writing until it fits on the note, as you would
			lines = PackedStringArray()
			var line := ""
			for wd in words:
				if line != "" and font.get_string_size(line + " " + wd, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > s * 0.82:
					lines.append(line)
					line = wd
				else:
					line = wd if line == "" else line + " " + wd
			lines.append(line)
			if lines.size() * size * 1.02 < s * 0.66 or size <= 18:
				break
			size -= 2
		var y := -h + s * 0.3
		for l in lines:
			c.draw_string(font, Vector2(-h * 0.84, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, size, pen)
			y += size * 1.02
		# Punched: this is where the confetti came from. One to three holes, anywhere (sometimes biting into
		# the edge), clear of the curled corner; through each one the page shows, shadowed by the cut edge.
		var holes := 1 if r.randf() < 0.55 else (2 if r.randf() < 0.65 else 3)
		var taken: Array = []
		for k in holes:
			for attempt in 10:
				var hp := Vector2(r.randf_range(-h * 0.95, h * 0.95), r.randf_range(-h * 0.8, h * 0.95))
				if hp.x + hp.y > s * 0.55:  # not in the curl
					continue
				if taken.any(func(q): return (q as Vector2).distance_to(hp) < 40.0):
					continue
				taken.append(hp)
				var hr := 14.0 * r.randf_range(0.95, 1.05)
				var poly := PackedVector2Array()
				for j in 24:
					poly.append(hp + Vector2.from_angle(TAU * j / 24.0) * hr * (1.0 + r.randf_range(-0.03, 0.03)))
				c.draw_colored_polygon(poly, Color(0.945, 0.94, 0.925))  # the page underneath
				c.draw_arc(hp + Vector2(1.2, 1.6), hr - 1.4, PI * 0.85, PI * 1.85, 16, Color(0, 0, 0, 0.16), 3.0, true)  # the cut edge's shadow
				c.draw_arc(hp, hr, 0.0, TAU, 28, col.darkened(0.18), 1.2, true)  # the note's own cut rim
				if r.randf() < 0.5:  # a small burr where the punch dragged
					var ba := r.randf() * TAU
					c.draw_line(hp + Vector2.from_angle(ba) * hr, hp + Vector2.from_angle(ba + 0.15) * (hr - 2.5), col.lightened(0.15), 2.0, true)
				break
	under.add_child(n)
	bits.append({"node": n, "len": g.lens[i] + 900.0})


# ---------------------------------------------------------------- free paper

## A spot for a box of `size` beside the road near `at`, on side `out`, clear of the road and of anything
## already written. Tries a few distances; INF if there's no room.
func _free_spot(at: Vector2, out: float, size: Vector2, idx: int) -> Vector2:
	var rng: RandomNumberGenerator = g.rng
	var i := idx
	if i < 0:  # find the road point nearest `at`
		var best := INF
		for k in range(maxi(0, g.road.size() - 400), g.road.size(), 3):
			var d: float = at.distance_squared_to(g.road[k])
			if d < best:
				best = d
				i = k
	i = clampi(i, 0, g.road.size() - 1)
	var nrm := Vector2.from_angle(g._dir_at(i) + PI * 0.5) * out
	var full := size + Vector2(24, 42)  # the area a piece really covers (drawn from its top-left)
	var reach := absf(nrm.x) * full.x * 0.5 + absf(nrm.y) * full.y * 0.5  # its half-depth away from the road
	for attempt in 6:
		# Right beside the edge: the near side of the piece sits at the line (a little overlap is fine), the
		# centre and most of it stay on the paper. Later tries step out a bit.
		var dist: float = g.widths[i] * 0.5 + reach - 6.0 + attempt * 26.0
		var cen: Vector2 = g.road[i] + nrm * dist + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
		var rect := Rect2(cen - full * 0.5, full)
		var p := rect.position + Vector2(12, 42)
		if _covers_road(rect, i):
			continue
		var clash := false
		for sm in g.seams:  # never written across a page edge
			if absf(rect.get_center().y - float(sm["y"])) < rect.size.y * 0.5 + 45.0:
				clash = true
		for rr in rects:
			if (rr[0] as Rect2).grow(12.0).intersects(rect):
				clash = true
				break
		if clash:
			continue
		rects.append([rect, g.lens[i] + 900.0])
		return p
	return Vector2.INF


## True if the road would run through the piece: its centre on the road, or more than a corner of it.
func _covers_road(rect: Rect2, near: int) -> bool:
	var pts := [rect.get_center(), rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.get_center() + (rect.position - rect.get_center()) * 0.5, rect.get_center() + (rect.end - rect.get_center()) * 0.5]
	var inside := 0
	for k in pts.size():
		if _hits_road(pts[k], -6.0, near):
			if k == 0 or k >= 5:
				return true  # the middle of it must stay on the paper
			inside += 1
	return inside > 1


func _hits_road(p: Vector2, clearance: float, near: int) -> bool:
	for k in range(maxi(0, near - 220), mini(g.road.size(), near + 220), 3):
		var lim: float = g.widths[k] * 0.5 + clearance
		if p.distance_squared_to(g.road[k]) < lim * lim:
			return true
	return false
