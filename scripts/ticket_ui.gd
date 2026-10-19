class_name TicketUI
extends CanvasLayer
## Fenêtre de contrôle : réplique du passager + titre de transport + décision.

signal decided(passenger: Passenger, decision: String)
signal closed

var passenger: Passenger
var line: Dictionary
var bubble: Label
var buttons: HBoxContainer
var _done := false


func open(p: Passenger, l: Dictionary) -> void:
	passenger = p
	line = l
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var who := Label.new()
	who.text = p.data.name + ("  ★" if p.data.special else "")
	who.add_theme_font_size_override("font_size", 28)
	v.add_child(who)
	bubble = Label.new()
	bubble.text = "« %s »" % p.data.greet
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_theme_font_size_override("font_size", 22)
	bubble.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	v.add_child(bubble)
	v.add_child(_ticket_card(p.data.ticket))
	var hint := Label.new()
	hint.text = "Aujourd'hui : %s — %s %s (%s → %s)" % [Game.date_str(Game.today), l.type, l.name, l.from, l.to]
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	v.add_child(hint)
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)
	_btn("[1] Titre valide", Color(0.3, 0.75, 0.4), func(): _decide("valide"))
	_btn("[2] Amende 50 €", Color(0.85, 0.3, 0.3), func(): _decide("amende"))
	_btn("[Échap] Plus tard", Color(0.5, 0.5, 0.55), _close)


func _btn(text: String, color: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 50)
	b.add_theme_font_size_override("font_size", 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate()
	sh.bg_color = color
	b.add_theme_stylebox_override("hover", sh)
	b.pressed.connect(cb)
	buttons.add_child(b)


func _ticket_card(t: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.96, 0.9) if t.kind != "Aucun titre" else Color(0.3, 0.3, 0.32)
	sb.set_corner_radius_all(10)
	sb.border_color = line.color
	sb.set_border_width_all(4)
	sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	card.add_child(v)
	var dark := Color(0.12, 0.12, 0.15)
	if t.kind == "Aucun titre":
		var l := Label.new()
		l.text = "— Le passager ne présente aucun titre de transport —"
		l.add_theme_font_size_override("font_size", 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		return card
	var head := Label.new()
	head.text = "RÉSEAU AZIMOV — TITRE DE TRANSPORT"
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", line.color.darkened(0.3))
	v.add_child(head)
	var kind := Label.new()
	kind.text = t.kind
	kind.add_theme_font_size_override("font_size", 30)
	kind.add_theme_color_override("font_color", dark)
	v.add_child(kind)
	var ln := Label.new()
	ln.text = "Valable : " + ("toutes lignes" if t.line == 0 else "Ligne %d uniquement" % t.line)
	ln.add_theme_font_size_override("font_size", 20)
	ln.add_theme_color_override("font_color", dark)
	v.add_child(ln)
	if t.detail != "":
		var d := Label.new()
		d.text = t.detail
		d.add_theme_font_size_override("font_size", 20)
		d.add_theme_color_override("font_color", Color(0.75, 0.1, 0.1) if t.detail == "NON COMPOSTÉ" else dark)
		v.add_child(d)
	return card


func _decide(dec: String) -> void:
	if _done:
		return
	_done = true
	for b in buttons.get_children():
		b.disabled = true
	var d := passenger.data
	var reply: String = d.ok if dec == "valide" else d.fine_reaction
	if dec == "valide" and d.truth == "fraude" and d.ticket.kind != "Aucun titre":
		reply = d.ok   # le fraudeur est ravi
	bubble.text = "« %s »" % reply
	decided.emit(passenger, dec)
	await get_tree().create_timer(1.6).timeout
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("valider"):
		_decide("valide")
	elif event.is_action_pressed("amende"):
		_decide("amende")
	elif event.is_action_pressed("pause"):
		_close()
	get_viewport().set_input_as_handled()
