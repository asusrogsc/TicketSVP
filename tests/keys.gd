extends Node
## Simule ZQSD (AZERTY) dans le hall puis dans le bus et mesure le déplacement.
func _press(code: int, phys: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = phys
	ev.pressed = down
	Input.parse_input_event(ev)

func _walk(p: Node3D, code: int, phys: int, label: String) -> void:
	var start := p.global_position
	_press(code, phys, true)
	await get_tree().create_timer(0.7).timeout
	_press(code, phys, false)
	await get_tree().create_timer(0.2).timeout
	print(label, " deplacement ", snapped((p.global_position - start).length(), 0.01))

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	await _walk(get_tree().current_scene.player, KEY_Z, KEY_W, "HALL Z")
	Game.start_line(Game.lines[0])
	await get_tree().create_timer(1.5).timeout
	var bus := get_tree().current_scene
	var p: Node3D = bus.player
	p.rotation_degrees.y = 180   # face à l'arrière du bus, dans l'allée
	await _walk(p, KEY_Z, KEY_W, "BUS Z (avancer)")
	await _walk(p, KEY_S, KEY_S, "BUS S (reculer)")
	await _walk(p, KEY_Q, KEY_A, "BUS Q (gauche)")
	await _walk(p, KEY_D, KEY_D, "BUS D (droite)")
	print("BUS position finale ", p.global_position)
	get_tree().quit()
