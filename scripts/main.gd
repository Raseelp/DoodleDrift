extends Node
## Switches between the Doodle Drift title screen and a run.

const Home = preload("res://scripts/drift_home.gd")
const Drift = preload("res://scripts/drift.gd")

var current: Node


func _ready() -> void:
	show_home()


func show_home() -> void:
	var h := Home.new()
	h.play_requested.connect(start_run)
	_swap(h)


func start_run() -> void:
	var s: Node = Drift.new()
	s.home_requested.connect(show_home)
	s.again_requested.connect(start_run)
	_swap(s)


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
