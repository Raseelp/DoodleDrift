extends Node
## Shared look and settings for Doodle Drift (autoloaded as Game).

const SAVE_PATH := "user://save.cfg"

var sound_on := true
var music_on := true
var vibration_on := true

var ui_theme: Theme
var title_font: FontVariation
var heading_font: FontVariation

const HitButton = preload("res://scripts/hit_button.gd")
const FONT_PATH := "res://fonts/JosefinSans-Variable.ttf"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_theme()


func set_setting(key: String, value: bool) -> void:
	match key:
		"sound": sound_on = value
		"music": music_on = value
		"vibration": vibration_on = value
	_save()
	Sfx.apply_settings()


func vibrate(ms: int) -> void:
	if vibration_on:
		Input.vibrate_handheld(ms)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	sound_on = bool(cf.get_value("settings", "sound", true))
	music_on = bool(cf.get_value("settings", "music", true))
	vibration_on = bool(cf.get_value("settings", "vibration", true))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)  # keep anything else in the file
	cf.set_value("settings", "sound", sound_on)
	cf.set_value("settings", "music", music_on)
	cf.set_value("settings", "vibration", vibration_on)
	cf.save(SAVE_PATH)


# ---------------------------------------------------------------- look

func _build_theme() -> void:
	# Josefin Sans (fonts/, SIL Open Font License): one variable font, its weight set per use. Godot's
	# built-in font only if the file were ever missing.
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	var body := FontVariation.new()
	body.base_font = base
	body.variation_opentype = {wght: 600}
	body.spacing_glyph = 1
	title_font = FontVariation.new()
	title_font.base_font = base
	title_font.variation_opentype = {wght: 700}
	title_font.spacing_glyph = 14
	heading_font = FontVariation.new()
	heading_font.base_font = base
	heading_font.variation_opentype = {wght: 600}
	heading_font.spacing_glyph = 3
	ThemeDB.fallback_font = body  # every label, themed or not, uses it

	ui_theme = Theme.new()
	ui_theme.default_font = body
	ui_theme.default_font_size = 28

	var normal := _pill(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.28))
	var hover := _pill(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.40))
	var pressed := _pill(Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.55))
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed]]:
		ui_theme.set_stylebox(state[0], "Button", state[1])
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	ui_theme.set_stylebox("disabled", "Button", _pill(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10)))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		ui_theme.set_color(c, "Button", Color(1, 1, 1, 0.95))
	ui_theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	ui_theme.set_font_size("font_size", "Button", 28)

	ui_theme.set_color("font_color", "Label", Color(1, 1, 1, 0.94))
	ui_theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.32))
	ui_theme.set_constant("shadow_offset_x", "Label", 0)
	ui_theme.set_constant("shadow_offset_y", "Label", 2)
	ui_theme.set_constant("separation", "VBoxContainer", 18)


func _pill(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(40)
	s.content_margin_left = 36
	s.content_margin_right = 36
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.anti_aliasing = true
	return s


## Icons from res://icons (white, tinted when drawn). Credits in icons/CREDITS.txt.
var _icons := {}
## Per-icon size correction so icons that fill their whole square don't look bigger than the others.
const ICON_OPTICAL := {"loop": 0.84}


func icon(kind: String) -> Texture2D:
	if not _icons.has(kind):
		_icons[kind] = load("res://icons/%s.svg" % kind)
	return _icons[kind]


## Draws an icon centred on c, about s pixels across, tinted col.
func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var sz := s * 1.1 * float(ICON_OPTICAL.get(kind, 1.0))
	ci.draw_texture_rect(icon(kind), Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col)


## A solid square game button with a darker bottom edge that it presses down into, holding one white icon.
## Buttons smaller than 96 px get an invisible touch margin so they are about 48 dp to a finger.
func square_button(tex: Texture2D, side: float, icon_w: int) -> Button:
	var b: Button = HitButton.new()
	b.hit_pad = maxf(0.0, (96.0 - side) * 0.5)
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", icon_w)
	b.custom_minimum_size = Vector2(side, side)
	b.size = Vector2(side, side)
	var edge := maxi(4, int(side * 0.065))
	for st in [["normal", Color("1d3a44")], ["hover", Color("1d3a44")], ["pressed", Color("16303a")], ["hover_pressed", Color("16303a")]]:
		var down := String(st[0]).ends_with("pressed")
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.border_color = Color("0f242c")
		sb.border_width_bottom = 0 if down else edge
		sb.content_margin_top = edge if down else 0
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_bottom = 0
		sb.set_corner_radius_all(int(side * 0.17))
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Turns a settings button into an icon toggle: dimmed with a slash when off.
func style_toggle(b: Button, key: String, on: bool) -> void:
	b.text = ""
	b.icon = icon(key)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 34)
	b.custom_minimum_size.x = 96
	b.modulate.a = 1.0 if on else 0.5
	b.set_meta("off", not on)
	if not b.has_meta("slash"):
		b.set_meta("slash", true)
		b.draw.connect(func():
			if b.get_meta("off", false):
				var c := b.size * 0.5
				b.draw_line(c + Vector2(-20, 20), c + Vector2(20, -20), Color(1, 1, 1, 0.95), 3.0, true))
	b.queue_redraw()

