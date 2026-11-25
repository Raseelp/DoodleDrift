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
	s.again_requested.connect(start_run)
	_swap(s)


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
