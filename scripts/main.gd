extends Node
## Switches between the lake map and a lake.

const Loading = preload("res://scripts/loading.gd")
# The map's script is big too: it compiles in the background behind the loading screen.
const MAP_PATH := "res://scripts/map.gd"
var map_script: GDScript
# The lake's script (and the ducks, swans and jetty it uses) is big: it compiles on a background thread
# and the loading screen doesn't wait for it (the map is up long before anyone taps a lake).
const LEVEL_PATH := "res://scripts/level.gd"
var level_script: GDScript  # collected from the background load the first time a lake opens

var current: Node


func _ready() -> void:
	var screen := Loading.new()
	screen.paths = [MAP_PATH]  # not the lake's script: only needed on a tap, it goes on compiling behind the map
	for path in [Game.PICKUP_MODEL, Game.TRAILER_MODEL, Game.BOAT_MODEL, Game.SWAN_MODEL]:
		if ResourceLoader.exists(path):
			screen.paths.append(path)
	screen.loaded.connect(func():
		show_map()  # underneath the loading screen, which lifts once the map has drawn
		for i in 2:
			await RenderingServer.frame_post_draw
		if is_instance_valid(screen):
			screen.map_up = true)
	add_child(screen)
	# The loading screen's first frame goes up before anything heavy starts, so it follows Android's splash
	# (kept up until the game runs: export option splash_screen/disable_godot_boot_splash) straight away.
	await RenderingServer.frame_post_draw
	ResourceLoader.load_threaded_request(MAP_PATH)
	ResourceLoader.load_threaded_request(LEVEL_PATH)
	Game.start_loading()


func show_map() -> void:
	_get_map_script()
	var m: Node = map_script.new()
	m.lake_chosen.connect(start_level)
	m.reload_requested.connect(show_map)
	_swap(m)


func start_level(index: int) -> void:
	if level_script == null:
		level_script = ResourceLoader.load_threaded_get(LEVEL_PATH)  # ready long before a tap
		if level_script == null:
			level_script = load(LEVEL_PATH)  # the background load failed: load it here instead
	var l: Node = level_script.new()
	l.lake_index = index
	l.exit_requested.connect(show_map)
	l.level_requested.connect(start_level)
	l.map_requested.connect(_zoom_out)
	# From the map, the lake zooms in from its picture; it frees the map when it has landed.
	if is_instance_valid(current) and current.get_script() == map_script and current.is_inside_tree():
		l.zoom_from = current
		get_tree().paused = false
		current = l
		add_child.call_deferred(l)
		return
	_swap(l)


## A lake zooms out into its picture on a new map underneath it; the map frees the lake when it lands,
## then shows any lake this win opened and sails the boat to travel_to (-1: stay).
func _zoom_out(level: Node, travel_to: int, reveal: int) -> void:
	_get_map_script()
	var m: Node = map_script.new()
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


func _get_map_script() -> void:
	if map_script == null:
		map_script = ResourceLoader.load_threaded_get(MAP_PATH)
		if map_script == null:
			map_script = load(MAP_PATH)  # the background load failed: load it here instead
