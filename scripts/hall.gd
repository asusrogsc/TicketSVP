extends Node3D
## Hall d'entrée de la maison du joueur. Le planning au mur permet de choisir sa ligne.

var player: Player
var hud: Hud
var menu: CanvasLayer


func _ready() -> void:
	Build.environment(self, Color(0.35, 0.5, 0.8), Color(0.75, 0.8, 0.9), 0.12, 0.0)
	_build_room()
	hud = Hud.new()
	add_child(hud)
	player = Player.new()
	player.position = Vector3(0, 0.05, 2.6)
	player.hud = hud
	add_child(player)
	player.interacted.connect(_on_interact)
	hud.set_info("Maison — Trajets : %d   Argent : %d €   Meilleur score : %d" % [
		Game.career.trajets, Game.career.argent, Game.career.meilleur_score])
	hud.show_toast("Consulte le planning au mur pour prendre ton service", Color(1, 0.95, 0.7), 5.0)


func _build_room() -> void:
	var wall := Color(0.82, 0.76, 0.66)
	var wood := Color(0.55, 0.36, 0.2)
	# sol, plafond, murs (pièce de 5 x 7 m)
	_build_oak_floor()
	Build.box(self, Vector3(5, 0.1, 7), Vector3(0, 2.85, 0), Color(0.96, 0.95, 0.92))
	Build.box(self, Vector3(0.1, 2.8, 7), Vector3(-2.5, 1.4, 0), wall)
	Build.box(self, Vector3(0.1, 2.8, 7), Vector3(2.5, 1.4, 0), wall)
	Build.box(self, Vector3(5, 2.8, 0.1), Vector3(0, 1.4, 3.5), wall)
	# mur du fond avec la porte d'entrée
	Build.box(self, Vector3(1.9, 2.8, 0.1), Vector3(-1.55, 1.4, -3.5), wall)
	Build.box(self, Vector3(1.9, 2.8, 0.1), Vector3(1.55, 1.4, -3.5), wall)
	Build.box(self, Vector3(1.2, 0.7, 0.1), Vector3(0, 2.45, -3.5), wall)
	var door := Interactable.new()
	door.label = "Sortir (prends d'abord ton service au planning)"
	door.action = func(): hud.show_toast("Choisis d'abord une ligne sur le planning !", Color(1, 0.8, 0.5))
	door.position = Vector3(0, 1.05, -3.48)
	add_child(door)
	Build.box(door, Vector3(1.1, 2.1, 0.08), Vector3.ZERO, wood)
	Build.box(door, Vector3(0.06, 0.06, 0.12), Vector3(0.42, 0, 0.05), Color(0.85, 0.75, 0.3), false)
	# plinthes
	for x in [-2.44, 2.44]:
		Build.box(self, Vector3(0.02, 0.1, 7), Vector3(x, 0.05, 0), Color(0.45, 0.3, 0.18), false)
	# tapis, meuble à chaussures, porte-manteau, miroir, lampe
	Build.box(self, Vector3(1.6, 0.02, 3.2), Vector3(0, 0.01, -0.6), Color(0.55, 0.15, 0.18), false)
	Build.box(self, Vector3(0.45, 0.9, 1.4), Vector3(2.2, 0.45, -1.6), wood)
	Build.box(self, Vector3(0.5, 0.04, 1.5), Vector3(2.2, 0.92, -1.6), Color(0.35, 0.22, 0.12))
	var rack := Build.cylinder(self, 0.035, 1.85, Vector3(-2.1, 0.92, -2.7), Color(0.25, 0.18, 0.12))
	Build.cylinder(self, 0.25, 0.03, Vector3(-2.1, 0.02, -2.7), Color(0.25, 0.18, 0.12))
	# la casquette de contrôleur posée sur le meuble
	Build.cylinder(self, 0.13, 0.08, Vector3(2.2, 0.98, -1.3), Color(0.1, 0.18, 0.4))
	Build.box(self, Vector3(0.22, 0.015, 0.12), Vector3(2.2, 0.95, -1.15), Color(0.08, 0.08, 0.1), false)
	Build.box(self, Vector3(0.05, 1.0, 0.7), Vector3(2.44, 1.6, -1.6), Color(0.75, 0.85, 0.9), false, 0.05)
	Build.light(self, Vector3(0, 2.6, 0), Color(1, 0.88, 0.7), 0.55, 7.0)
	Build.light(self, Vector3(0, 2.3, -3.0), Color(1, 0.85, 0.7), 0.4, 4.0)
	# planning des lignes au mur de gauche
	var board := Interactable.new()
	board.label = "Consulter le planning des lignes"
	board.action = _open_menu
	board.position = Vector3(-2.42, 1.55, -0.6)
	board.rotation_degrees.y = 90
	add_child(board)
	Build.box(board, Vector3(1.6, 1.0, 0.05), Vector3.ZERO, Color(0.2, 0.22, 0.25))
	Build.box(board, Vector3(1.5, 0.9, 0.02), Vector3(0, 0, 0.03), Color(0.95, 0.95, 0.9), false)
	Build.label3d(board, "PLANNING DU JOUR", Vector3(0, 0.33, 0.05), 40, Color(0.1, 0.1, 0.15))
	var y := 0.12
	for l in Game.lines:
		var t := "%s  %s  —  %s → %s" % [l.type, l.name, l.from, l.to]
		if not l.unlocked:
			t += "  (bientôt)"
		var lab := Build.label3d(board, t, Vector3(0, y, 0.05), 26, l.color.darkened(0.2))
		y -= 0.16
	Build.label3d(board, "[E] pour choisir", Vector3(0, -0.36, 0.05), 22, Color(0.3, 0.3, 0.3))


## Parquet de chêne : une collision plane, lames décoratives sans collision.
## La surface reste à y = 0 pour conserver les déplacements et le mobilier.
func _build_oak_floor() -> void:
	var floor_root := Node3D.new()
	floor_root.name = "OakFloor"
	add_child(floor_root)
	# La sous-couche sombre apparaît seulement dans les joints de 1 mm.
	Build.box(floor_root, Vector3(5, 0.08, 7), Vector3(0, -0.06, 0), Color(0.32, 0.225, 0.13), false)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5, 0.1, 7)
	collision.shape = shape
	body.position.y = -0.05
	body.add_child(collision)
	floor_root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73129
	var oak_shader: Shader = preload("res://shaders/oak.gdshader")
	var board_width := 0.20
	var board_length := 1.40
	var gap := 0.001
	for row in range(25):
		var x := -2.5 + (float(row) + 0.5) * board_width
		# Trois décalages évitent les joints transversaux alignés.
		var start := -3.5 - float(row % 3) * board_length / 3.0
		while start < 3.5:
			var finish: float = minf(start + board_length, 3.5)
			var clipped_start: float = maxf(start, -3.5)
			var length := finish - clipped_start
			if length > gap:
				var plank := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(board_width - gap, 0.018, length - gap)
				plank.mesh = mesh
				plank.position = Vector3(x, -0.009, (clipped_start + finish) * 0.5)
				var material := ShaderMaterial.new()
				material.shader = oak_shader
				var tone := rng.randf_range(0.965, 1.035)
				material.set_shader_parameter("oak_color", Color(0.67 * tone, 0.485 * tone, 0.285 * tone))
				material.set_shader_parameter("grain_seed", rng.randf_range(0.0, 100.0))
				plank.material_override = material
				floor_root.add_child(plank)
			start += board_length


func _on_interact(t: Node) -> void:
	if t is Interactable:
		t.interact()


func _open_menu() -> void:
	if menu:
		return
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = CanvasLayer.new()
	add_child(menu)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Choisis ta ligne"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for l in Game.lines:
		var b := Button.new()
		b.text = "%s %s : %s → %s%s" % [l.type, l.name, l.from, l.to, "" if l.unlocked else "  (bientôt)"]
		b.disabled = not l.unlocked
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size.y = 52
		b.pressed.connect(func(): Game.start_line(l))
		box.add_child(b)
	var close := Button.new()
	close.text = "Fermer (Échap)"
	close.pressed.connect(_close_menu)
	box.add_child(close)


func _close_menu() -> void:
	if menu:
		menu.queue_free()
		menu = null
	player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and menu:
		_close_menu()
