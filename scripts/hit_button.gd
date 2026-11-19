extends Button
## A button whose touch area reaches hit_pad pixels past its drawn edge, so small buttons
## are still easy to hit (about 48 dp) without looking any bigger.

var hit_pad := 0.0


func _has_point(point: Vector2) -> bool:
	return Rect2(-Vector2.ONE * hit_pad, size + Vector2.ONE * hit_pad * 2.0).has_point(point)
