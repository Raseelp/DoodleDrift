extends Control
## The home screen: the painted lake (title painted in) covering the screen, a big Play button and the
## records.

signal play_requested

const ART := "res://art/loading.png"
const ART_SIZE := Vector2(941, 1672)


func _ready() -> void:
	theme = Game.ui_theme
	size = get_viewport_rect().size
	var art := TextureRect.new()
	art.texture = load(ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.size = size
	add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.35)
	shade.size = size
	add_child(shade)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 16)
	box.position = Vector2(0, size.y * 0.6)
	box.size = Vector2(size.x, size.y * 0.32)
	add_child(box)
	var cfg := ConfigFile.new()
	cfg.load("user://swarm.cfg")
	var best := int(cfg.get_value("best", "size", 0))
	if best > 0:
		var rec := Label.new()
		rec.text = "Biggest swarm  %d   ·   Most swarms taken  %d" % [best, int(cfg.get_value("best", "taken", 0))]
		rec.add_theme_font_size_override("font_size", 24)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(rec)
	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(360, 96)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.add_theme_font_override("font", Game.title_font)
	play.add_theme_font_size_override("font_size", 40)
	play.pressed.connect(func():
		Sfx.tap()
		play_requested.emit())
	box.add_child(play)
