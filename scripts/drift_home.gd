extends Control
## Doodle Drift title screen: a sheet of paper, the name on it, PLAY, the records, and dev settings.

signal play_requested

const Drift = preload("res://scripts/drift.gd")

var ink := Color(0.16, 0.16, 0.2)
var dev: Control


func _ready() -> void:
	theme = Game.ui_theme
	size = get_viewport_rect().size
	var cfg := Drift._load()
	var pap: Dictionary = Drift.PAPERS.get(String(cfg.get_value("dev", "paper", "white")), Drift.PAPERS["white"])
	var paper := TextureRect.new()
	paper.texture = load(pap["tex"])
	paper.stretch_mode = TextureRect.STRETCH_TILE
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.size = size
	add_child(paper)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	box.size = size
	add_child(box)
	for word in ["DOODLE", "DRIFT"]:
		box.add_child(_label(word, 96, Game.title_font))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 60)
	box.add_child(gap)
	var best := int(cfg.get_value("best", "score", 0))
	if best > 0:
		box.add_child(_label("Best  %d   ·   %d m   ·   x%d combo" % [best, int(cfg.get_value("best", "dist", 0)), int(cfg.get_value("best", "combo", 1))], 26))
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
	var dev_btn := Button.new()
	dev_btn.text = "Dev settings"
	dev_btn.custom_minimum_size = Vector2(240, 64)
	dev_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dev_btn.add_theme_font_size_override("font_size", 24)
	dev_btn.pressed.connect(_open_dev)
	box.add_child(dev_btn)


func _label(text: String, font_size: int, font: Font = null, col: Color = ink) -> Label:
	var l := Label.new()
	l.text = text
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Car, paper, and how long a side must be held before the car flicks into a drift. Saved straight away.
func _open_dev() -> void:
	Sfx.tap()
	var cfg := Drift._load()
	dev = Control.new()
	dev.size = size
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.82)
	dim.size = size
	dev.add_child(dim)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.size = size
	dev.add_child(box)
	var white := Color(0.96, 0.96, 0.96)
	box.add_child(_label("DEV SETTINGS", 48, Game.title_font, white))
	box.add_child(_label("Car", 26, null, white))
	box.add_child(_choice(Drift.CARS, String(cfg.get_value("dev", "car", "evo")), "car"))
	box.add_child(_label("Paper", 26, null, white))
	box.add_child(_choice(Drift.PAPERS, String(cfg.get_value("dev", "paper", "white")), "paper"))
	var hold := float(cfg.get_value("dev", "hold", Drift.DEFAULT_HOLD))
	var hold_l := _label("", 26, null, white)
	box.add_child(hold_l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 0.6
	slider.step = 0.01
	slider.value = hold
	slider.custom_minimum_size = Vector2(minf(520.0, size.x - 80.0), 56)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var show_hold := func(v: float): hold_l.text = "Hold before full drift  %.2f s" % v
	show_hold.call(hold)
	slider.value_changed.connect(func(v: float):
		show_hold.call(v)
		_set_dev("hold", v))
	box.add_child(slider)
	box.add_child(_label("Before that the car only slides lightly. 0 = straight into a drift", 20, null, Color(0.75, 0.75, 0.75)))
	var crash := CheckButton.new()
	crash.text = "Hitting an object ends the run"
	crash.button_pressed = bool(cfg.get_value("dev", "crash", true))
	crash.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crash.add_theme_font_size_override("font_size", 24)
	crash.toggled.connect(func(on: bool): _set_dev("crash", on))
	box.add_child(crash)
	var close := Button.new()
	close.text = "Done"
	close.custom_minimum_size = Vector2(280, 76)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(func():
		Sfx.tap()
		get_tree().reload_current_scene())  # redraws the title on the chosen paper
	box.add_child(close)
	add_child(dev)


func _choice(options: Dictionary, current: String, key: String) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(minf(420.0, size.x - 80.0), 64)
	o.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	o.add_theme_font_size_override("font_size", 26)
	var ids := options.keys()
	for k in ids.size():
		o.add_item(options[ids[k]]["name"], k)
		if ids[k] == current:
			o.select(k)
	o.item_selected.connect(func(idx: int): _set_dev(key, ids[idx]))
	return o


func _set_dev(key: String, value: Variant) -> void:
	var cfg := Drift._load()
	cfg.set_value("dev", key, value)
	cfg.save(Drift.SAVE)
