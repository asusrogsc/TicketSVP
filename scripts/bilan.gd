extends Control
## Bilan du trajet.

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var r := Game.last_result
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_l(v, "Fin de service", 36, Color(1, 0.9, 0.6))
	_l(v, r.get("line", ""), 20, Color(0.8, 0.85, 0.95))
	_l(v, " ", 8)
	_l(v, "Passagers transportés : %d" % r.get("passagers", 0), 22)
	_l(v, "Contrôles : %d  (dont %d corrects)" % [r.get("controles", 0), r.get("justes", 0)], 22)
	_l(v, "Amendes justifiées : %d  (%d €)" % [r.get("amendes", 0), r.get("amendes_euros", 0)], 22, Color(0.5, 1, 0.55))
	_l(v, "Amendes injustes : %d" % r.get("erreurs_amende", 0), 22, Color(1, 0.55, 0.5))
	_l(v, "Fraudeurs laissés passer : %d" % r.get("fraudes_laissees", 0), 22, Color(1, 0.55, 0.5))
	_l(v, "Fraudeurs descendus sans contrôle : %d" % r.get("fraudeurs_partis", 0), 22, Color(1, 0.7, 0.5))
	var sp: Array = r.get("speciaux", [])
	if sp.size() > 0:
		_l(v, "Rencontre spéciale : " + ", ".join(sp) + " ★", 22, Color(1, 0.75, 1))
	_l(v, " ", 8)
	_l(v, "SCORE : %d" % r.get("score", 0), 40, Color(1, 0.95, 0.5))
	_l(v, "Carrière — trajets : %d   argent : %d €   meilleur score : %d" % [
		Game.career.trajets, Game.career.argent, Game.career.meilleur_score], 18, Color(0.75, 0.75, 0.8))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var again := Button.new()
	again.text = "Refaire la ligne"
	again.custom_minimum_size = Vector2(220, 52)
	again.pressed.connect(func(): Game.start_line(Game.current_line))
	h.add_child(again)
	var home := Button.new()
	home.text = "Rentrer à la maison"
	home.custom_minimum_size = Vector2(220, 52)
	home.pressed.connect(Game.go_home)
	h.add_child(home)


func _l(parent: Node, t: String, size: int, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
