class_name Hud
extends CanvasLayer
## Viseur, message d'interaction, infos du trajet et petites notifications.

var prompt: Label
var info: Label
var toast: Label
var _toast_t := 0.0


func _ready() -> void:
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(cross)
	prompt = _label(22, Control.PRESET_CENTER)
	prompt.position.y += 60
	info = _label(20, Control.PRESET_TOP_LEFT)
	info.grow_horizontal = Control.GROW_DIRECTION_END
	info.position = Vector2(20, 16)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	toast = _label(26, Control.PRESET_CENTER_TOP)
	toast.position.y += 70


func _label(size: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.set_anchors_and_offsets_preset(preset)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(l)
	return l


func set_prompt(t: String) -> void:
	prompt.text = ("[E] " + t) if t != "" else ""


func set_info(t: String) -> void:
	info.text = t


func show_toast(t: String, color := Color.WHITE, secs := 2.5) -> void:
	toast.text = t
	toast.add_theme_color_override("font_color", color)
	_toast_t = secs


func _process(delta: float) -> void:
	if _toast_t > 0:
		_toast_t -= delta
		if _toast_t <= 0:
			toast.text = ""
