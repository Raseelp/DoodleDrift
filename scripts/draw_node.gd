extends Node2D
## A Node2D whose drawing is done by a callback, so one script can draw several layers.

var draw_fn: Callable


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
