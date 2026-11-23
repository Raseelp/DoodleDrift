extends Node
## Background music that lives for the whole session, like a radio: it keeps playing across runs and the
## title screen, and when a track nears its end the next one (random, never the same twice running) fades
## in over it. Pauses with the game.

const FADE := 3.0  # seconds of crossfade between tracks
const VOLUME := -9.0  # under the tyres and rips

var tracks := {}  # key -> path
var off := false
var players: Array[AudioStreamPlayer] = []
var cur := 0
var last := ""
var fading := false


func setup(p_tracks: Dictionary, first: String) -> void:
	tracks = p_tracks
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		players.append(p)
	_start(first if tracks.has(first) else "")


## A dev setting change: "off" silences it; a track key starts that track next; anything else keeps going.
func choose(pick: String) -> void:
	off = pick == "off" or not Game.music_on
	if off:
		for p in players:
			p.stop()
		return
	if not players[cur].playing:
		_start(pick if tracks.has(pick) else "")


func _start(key: String) -> void:
	if off or tracks.is_empty():
		return
	if key == "":
		var keys := tracks.keys().filter(func(k): return k != last)
		key = keys[randi() % keys.size()]
	last = key
	cur = 1 - cur
	var p := players[cur]
	p.stream = load(tracks[key])
	p.volume_db = -40.0
	p.play()
	fading = true


func _process(delta: float) -> void:
	if off or players.is_empty():
		return
	var p := players[cur]
	var other := players[1 - cur]
	# Fade the new track up and the old one out.
	p.volume_db = move_toward(p.volume_db, VOLUME, delta * 40.0 / FADE)
	if other.playing:
		other.volume_db = move_toward(other.volume_db, -60.0, delta * 50.0 / FADE)
		if other.volume_db <= -59.0:
			other.stop()
	# Near the end, bring in the next one.
	if p.playing and p.stream != null and p.stream.get_length() - p.get_playback_position() < FADE:
		_start("")
