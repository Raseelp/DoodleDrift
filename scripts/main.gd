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


## Drive again (after a crash, or "start over"): the page turns to a fresh one, and the new run is laid
## under it while it's covered.
func _again() -> void:
	if turning:
		return
	turning = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var turn := PageTurn.new()
	var cfg := Drift._load()
	var papers: Dictionary = Drift.PAPERS
	turn.paper = load(papers.get(String(cfg.get_value("dev", "paper", "white")), papers["white"])["tex"])
	turn.covered = func(): start_run(false)
	turn.finished = func():
		layer.queue_free()
		turning = false
	layer.add_child(turn)


var turning := false


## A fresh sheet slides in over the page from the right edge, its edge curled and shadowed like a page
## being turned; once it covers the screen the new run is put under it, then it lifts away.
class PageTurn extends Control:
	const IN := 0.38
	const OUT := 0.3
	var paper: Texture2D
	var covered: Callable
	var finished: Callable
	var t := 0.0
	var last_us := 0
	var swapped := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		size = get_viewport_rect().size
		last_us = Time.get_ticks_usec()

	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		t += minf(0.1, (now - last_us) / 1000000.0)
		last_us = now
		if not swapped and t >= IN:
			swapped = true
			covered.call()
		if t >= IN + OUT + 0.05:
			finished.call()
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if t < IN:  # turning in: the sheet's edge sweeps from the right to the left
			var e := w * (1.0 - smoothstep(0.0, IN, t))
			var r := Rect2(e, 0, w - e + 2.0, h)
			draw_texture_rect_region(paper, r, Rect2(r.position, r.size), Color(1, 1, 1, 1))
			for k in 8:  # the shadow the lifted page throws on the one below
				draw_rect(Rect2(e - (k + 1) * 6.0, 0, 6.0, h), Color(0, 0, 0, 0.05 * (1.0 - k / 8.0)))
			draw_line(Vector2(e, 0), Vector2(e + 10.0, h), Color(0.4, 0.4, 0.42, 0.5), 2.0, true)  # the curled edge
		else:  # covered: the new page is under it now; it lifts away
			var a := 1.0 - smoothstep(IN, IN + OUT, t)
			draw_texture_rect_region(paper, Rect2(Vector2.ZERO, size), Rect2(Vector2.ZERO, size), Color(1, 1, 1, a))


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
