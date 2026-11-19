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
	l.map_requested.connect(_zoom_out)
	# From the map, the lake zooms in from its picture; it frees the map when it has landed.
	if is_instance_valid(current) and current.get_script() == MapScript and current.is_inside_tree():
		l.zoom_from = current
		get_tree().paused = false
		current = l
		add_child.call_deferred(l)
		return
	_swap(l)


## A lake zooms out into its picture on a new map underneath it; the map frees the lake when it lands,
## then shows any lake this win opened and sails the boat to travel_to (-1: stay).
func _zoom_out(level: Node, travel_to: int, reveal: int) -> void:
	var m := MapScript.new()
	m.lake_chosen.connect(start_level)
	m.reload_requested.connect(show_map)
	m.arrive_level = level
	m.arrive_from = level.lake_index
	m.travel_to = travel_to
	m.reveal = reveal
	get_tree().paused = false
	current = m
	add_child(m)
	move_child(m, 0)


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
