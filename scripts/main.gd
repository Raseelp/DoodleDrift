extends Node
## Switches between the lake map and a lake.

const MapScript = preload("res://scripts/map.gd")
const LevelScript = preload("res://scripts/level.gd")

var current: Node


func _ready() -> void:
	show_map()


func show_map() -> void:
	var m := MapScript.new()
	m.lake_chosen.connect(start_level)
	m.reload_requested.connect(show_map)
	_swap(m)


func start_level(index: int) -> void:
	var l := LevelScript.new()
	l.lake_index = index
	l.exit_requested.connect(show_map)
	l.level_requested.connect(start_level)
	_swap(l)


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
