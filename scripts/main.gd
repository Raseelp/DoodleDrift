extends Node
## Switches between the home screen and a game.

const Loading = preload("res://scripts/loading.gd")
const Home = preload("res://scripts/home.gd")
const SEA_PATH := "res://scripts/swarm.gd"

var current: Node


func _ready() -> void:
	var screen := Loading.new()
	screen.paths = [SEA_PATH]
	if ResourceLoader.exists(Game.BOAT_MODEL):
		screen.paths.append(Game.BOAT_MODEL)
	screen.loaded.connect(func():
		show_home()  # underneath the loading screen, which lifts once the home screen has drawn
		for i in 2:
			await RenderingServer.frame_post_draw
		if is_instance_valid(screen):
			screen.map_up = true)
	add_child(screen)
	# The loading screen's first frame goes up before anything heavy starts.
	await RenderingServer.frame_post_draw
	ResourceLoader.load_threaded_request(SEA_PATH)
	Game.start_loading()


func show_home() -> void:
	var h := Home.new()
	h.play_requested.connect(start_run)
	_swap(h)


func start_run() -> void:
	var script: GDScript = ResourceLoader.load_threaded_get(SEA_PATH)
	if script == null:
		script = load(SEA_PATH)
	var s: Node = script.new()
	s.home_requested.connect(show_home)
	s.again_requested.connect(start_run)
	_swap(s)


func _swap(n: Node) -> void:
	get_tree().paused = false
	if current != null:
		current.queue_free()
	current = n
	add_child.call_deferred(n)
