extends Node3D
## Gare du terminus : temps libre, PNJ qui attendent le bus retour, rapport au chef de gare.
## Le rapport signé ouvre la porte du bus retour ; les passagers du quai montent avec toi.

const QUALITY_HIGH := true          # passe à false si le PC rame
const WAIT_NORMAL_MIN := 8          # passagers ordinaires sur le quai
const WAIT_NORMAL_MAX := 12
const WAIT_SPECIAL_MIN := 2         # personnages spéciaux sur le quai
const WAIT_SPECIAL_MAX := 3
const WAIT_LINES := [
	"J'attends le bus pour %s.",
	"Il part quand, le prochain ?",
	"Toujours en retard, ce bus...",
	"Vous êtes le contrôleur ? Bon courage !",
	"Enfin une pause, j'ai mal aux pieds.",
	"Il fait bon aujourd'hui, hein ?",
]

var player: Player
var hud: Hud
var menu: CanvasLayer
var rng := RandomNumberGenerator.new()
var line: Dictionary                # ligne de l'aller
var back_line: Dictionary           # même ligne, sens retour
var waiting: Array[Passenger] = []
var report_done := false
var bus_door: Interactable
var board_label: Label3D


func _ready() -> void:
	rng.randomize()
	line = Game.selected_line if not Game.selected_line.is_empty() else Game.lines[0]
	back_line = Game.reversed_line(line)

	Build.environment(self, Color(0.35, 0.5, 0.8), Color(0.75, 0.8, 0.9), 0.5, 1.0)
	_setup_rendering()
	_build_station()
	_build_chef()
	_build_parked_bus()
	_spawn_waiting()

	hud = Hud.new()
	add_child(hud)
	player = Player.new()
	player.position = Vector3(0, 0.05, 17.0)
	player.hud = hud
	add_child(player)
	player.interacted.connect(_on_interact)
	_update_info()
	hud.show_toast("Terminus %s — Va faire ton rapport au chef de gare" % line.to, Color(1, 0.95, 0.7), 6.0)


func _update_info() -> void:
	hud.set_info("Gare — %s (terminus)   |   Score aller : %d   |   Rapport : %s   |   Sur le quai : %d" % [
		line.to, int(Game.aller_result.get("score", 0)), "signé ✔" if report_done else "à faire", waiting.size()])


# ------------------------------------------------------------------ décor

func _build_station() -> void:
	var asphalt := Color(0.2, 0.2, 0.22)
	var tiles := Color(0.66, 0.65, 0.62)
	var brick := Color(0.62, 0.36, 0.28)
	var steel := Color(0.3, 0.33, 0.37)

	# sol : pelouse, voie des bus, quai (surface du quai à y = 0)
	_rough(Build.box(self, Vector3(120, 0.1, 120), Vector3(0, -0.45, 0), Color(0.3, 0.5, 0.26), false), 1.0)
	_rough(Build.box(self, Vector3(8, 0.1, 60), Vector3(8, -0.35, 0), asphalt), 0.95)
	_rough(Build.box(self, Vector3(8.5, 0.3, 40), Vector3(-0.25, -0.15, 0), tiles), 0.85)
	# bord du quai : bande podotactile jaune + bordure
	Build.box(self, Vector3(0.4, 0.012, 40), Vector3(3.6, 0.006, 0), Color(0.95, 0.8, 0.1), false)
	_rough(Build.box(self, Vector3(0.15, 0.32, 40), Vector3(3.95, -0.15, 0), Color(0.8, 0.8, 0.78), false), 0.8)
	# joints du dallage
	var jz := -19.5
	while jz < 20:
		Build.box(self, Vector3(8.4, 0.004, 0.02), Vector3(-0.25, 0.002, jz), tiles.darkened(0.15), false)
		jz += 1.0
	# marquage au sol de la voie
	for z in range(-24, 25, 6):
		Build.box(self, Vector3(0.15, 0.01, 3), Vector3(10.5, -0.29, z), Color(0.95, 0.95, 0.9), false)

	# bâtiment de la gare (mur du fond)
	_rough(Build.box(self, Vector3(1, 6, 40), Vector3(-5, 2.85, 0), brick), 0.9)
	_rough(Build.box(self, Vector3(1.2, 0.4, 40.4), Vector3(-5, 5.95, 0), brick.darkened(0.3), false), 0.85)
	for z in range(-17, 18, 4):
		if abs(z) < 2:
			continue
		Build.box(self, Vector3(0.05, 1.9, 1.6), Vector3(-4.48, 2.2, z), Color(0.92, 0.9, 0.86), false)   # cadre
		var glass := Build.box(self, Vector3(0.05, 1.7, 1.4), Vector3(-4.46, 2.2, z), Color(0.45, 0.58, 0.72), false)
		if rng.randf() < 0.4:
			_glow(glass, Color(1, 0.88, 0.65), 0.6)
		else:
			_metal(glass, 0.08, Color(0.45, 0.58, 0.72), 0.3)
	# entrée de la gare
	var entry := Build.box(self, Vector3(0.05, 2.6, 2.4), Vector3(-4.46, 1.3, 0), Color(1, 0.9, 0.7), false)
	_glow(entry, Color(1, 0.88, 0.65), 0.8)
	var sign_l := Build.label3d(self, "GARE — " + str(line.to).to_upper(), Vector3(-4.44, 4.5, 0), 120, Color(1, 1, 1))
	sign_l.rotation_degrees.y = 90
	sign_l.pixel_size = 0.006

	# marquise : toit, poteaux, éclairage
	_metal(Build.box(self, Vector3(8.2, 0.15, 32), Vector3(-0.6, 3.7, 0), Color(0.85, 0.87, 0.9), false), 0.5, null, 0.3)
	_metal(Build.box(self, Vector3(0.1, 0.4, 32), Vector3(3.5, 3.55, 0), steel, false), 0.45)
	for z in range(-15, 16, 6):
		for x in [-3.6, 2.9]:
			_metal(Build.cylinder(self, 0.11, 3.7, Vector3(x, 1.85, z), steel), 0.4)
	for z in [-12, -4, 4, 12]:
		var lamp := Build.box(self, Vector3(0.3, 0.05, 1.6), Vector3(-0.6, 3.6, z), Color(1, 1, 0.95), false)
		_glow(lamp, Color(1, 0.96, 0.88), 2.0)
		var o := Build.light(self, Vector3(-0.6, 3.3, z), Color(1, 0.94, 0.85), 0.7, 9.0)
		o.shadow_enabled = QUALITY_HIGH

	# panneau des départs suspendu
	_metal(Build.box(self, Vector3(2.8, 0.9, 0.1), Vector3(0, 2.95, 6), Color(0.05, 0.05, 0.06), false), 0.4)
	for x in [-1.2, 1.2]:
		_metal(Build.cylinder(self, 0.015, 0.3, Vector3(x, 3.5, 6), steel), 0.4)
	board_label = Build.label3d(self, "", Vector3(0, 2.95, 6.06), 30, Color(1, 0.65, 0.15))
	board_label.pixel_size = 0.0035
	_update_board()

	# bancs + poubelles le long du mur
	for z in [-12.0, -6.0, 3.0, 8.0]:
		_bench(Vector3(-3.0, 0, z))

	# horloge sur un poteau
	var clock := Build.cylinder(self, 0.3, 0.06, Vector3(2.9, 3.0, -3), Color(0.95, 0.95, 0.92))
	clock.rotation_degrees.z = 90
	Build.label3d(self, "%02d:%02d" % [Time.get_time_dict_from_system().hour, Time.get_time_dict_from_system().minute],
		Vector3(2.85, 3.0, -3), 40, Color(0.1, 0.1, 0.1)).rotation_degrees.y = -90

	# bureau du chef de gare (kiosque)
	_rough(Build.box(self, Vector3(2.0, 2.6, 2.6), Vector3(-3.4, 1.3, 12.5), Color(0.9, 0.86, 0.76)), 0.85)
	var win := Build.box(self, Vector3(0.05, 1.0, 1.6), Vector3(-2.38, 1.5, 12.5), Color(1, 0.9, 0.7), false)
	_glow(win, Color(1, 0.88, 0.65), 0.7)
	var ks := Build.label3d(self, "CHEF DE GARE", Vector3(-2.36, 2.35, 12.5), 40, Color(0.15, 0.2, 0.45))
	ks.rotation_degrees.y = 90


func _bench(at: Vector3) -> void:
	var wood := Color(0.5, 0.33, 0.18)
	for k in 3:
		Build.box(self, Vector3(0.12, 0.04, 1.8), at + Vector3(-0.12 + k * 0.12, 0.45, 0), wood, false)
	Build.box(self, Vector3(0.04, 0.35, 1.8), at + Vector3(-0.24, 0.72, 0), wood, false)
	for dz in [-0.8, 0.8]:
		_metal(Build.box(self, Vector3(0.45, 0.45, 0.05), at + Vector3(-0.05, 0.22, dz), Color(0.15, 0.15, 0.17), false), 0.5)
	_metal(Build.cylinder(self, 0.2, 0.7, at + Vector3(0, 0.35, 1.3), Color(0.15, 0.35, 0.2)), 0.6)


func _build_parked_bus() -> void:
	# le bus du retour, garé le long du quai (portes côté quai)
	var body: Color = line.color
	var bx := 5.6
	_rough(Build.box(self, Vector3(2.5, 2.9, 12), Vector3(bx, 1.15, 0), body), 0.4)
	_metal(Build.box(self, Vector3(2.55, 0.1, 12.05), Vector3(bx, 2.62, 0), Color(0.85, 0.85, 0.85), false), 0.4, null, 0.2)
	for side in [-1, 1]:
		var w := Build.box(self, Vector3(0.02, 1.0, 10.5), Vector3(bx + side * 1.26, 1.5, 0.3), Color(0.2, 0.3, 0.38), false)
		_glow(w, Color(0.95, 0.92, 0.8), 0.25)
	for z in [-5.95, 5.95]:
		var g := Build.box(self, Vector3(2.3, 1.3, 0.02), Vector3(bx, 1.5, z * 1.0 + signf(z) * 0.02), Color(0.2, 0.3, 0.38), false)
		_glow(g, Color(0.95, 0.92, 0.8), 0.2)
	for z in [-4.0, 4.0]:
		for side in [-1, 1]:
			var wheel := Build.cylinder(self, 0.45, 0.3, Vector3(bx + side * 1.2, -0.05, z), Color(0.08, 0.08, 0.08))
			wheel.rotation_degrees.z = 90
	# girouette : destination
	var dest := "%s  %s" % [line.name, back_line.to]
	var front := Build.label3d(self, dest, Vector3(bx, 2.35, -6.05), 40, Color(1, 0.65, 0.15))
	front.rotation_degrees.y = 180
	var side_l := Build.label3d(self, dest, Vector3(bx - 1.28, 2.35, -3.5), 34, Color(1, 0.65, 0.15))
	side_l.rotation_degrees.y = -90
	# porte (côté quai)
	bus_door = Interactable.new()
	bus_door.position = Vector3(bx - 1.27, 1.05, 0)
	bus_door.action = _try_board
	add_child(bus_door)
	Build.box(bus_door, Vector3(0.06, 2.1, 1.2), Vector3.ZERO, Color(0.3, 0.35, 0.4, 0.7))
	_update_door()


func _update_door() -> void:
	bus_door.label = ("Monter dans le bus retour → " + back_line.to) if report_done \
		else "Bus retour (fais d'abord ton rapport au chef de gare)"


func _update_board() -> void:
	board_label.text = "QUAI 1\n%s %s  →  %s\n%s" % [line.type, line.name, back_line.to,
		"Embarquement en cours" if report_done else "Départ après le rapport de service"]


# ------------------------------------------------------------------ chef de gare

func _build_chef() -> void:
	var chef := Interactable.new()
	chef.label = "Faire ton rapport au chef de gare"
	chef.action = _open_report
	chef.position = Vector3(-1.7, 0, 12.5)
	chef.rotation_degrees.y = 180          # regarde vers l'arrivée du joueur
	add_child(chef)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	chef.add_child(col)
	var uniform := Color(0.12, 0.16, 0.32)
	var skin := Color(0.92, 0.76, 0.64)
	Build.box(chef, Vector3(0.34, 0.85, 0.22), Vector3(0, 0.43, 0), uniform.darkened(0.3), false)     # jambes
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.21
	tm.height = 0.75
	torso.mesh = tm
	torso.material_override = Build.mat(uniform)
	torso.position.y = 1.18
	chef.add_child(torso)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.27
	head.mesh = hm
	head.material_override = Build.mat(skin)
	head.position.y = 1.68
	chef.add_child(head)
	Build.cylinder(chef, 0.15, 0.09, Vector3(0, 1.81, 0), uniform)                                  # casquette
	Build.cylinder(chef, 0.152, 0.03, Vector3(0, 1.78, 0), Color(0.8, 0.12, 0.12))                  # bandeau rouge
	Build.box(chef, Vector3(0.2, 0.015, 0.12), Vector3(0, 1.765, -0.15), Color(0.05, 0.05, 0.05), false)  # visière
	Build.box(chef, Vector3(0.1, 0.025, 0.01), Vector3(0, 1.62, -0.128), Color(0.55, 0.55, 0.55), false)  # moustache
	for side in [-1, 1]:
		Build.box(chef, Vector3(0.03, 0.03, 0.01), Vector3(0.045 * side, 1.7, -0.127), Color(0.05, 0.05, 0.05), false)
	_metal(Build.box(chef, Vector3(0.06, 0.06, 0.01), Vector3(0.1, 1.35, -0.21), Color(0.95, 0.8, 0.3), false), 0.3)  # insigne
	var tag := Build.label3d(chef, "Chef de gare", Vector3(0, 2.1, 0), 32, Color(1, 0.9, 0.6))
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _chef_comment(r: Dictionary) -> String:
	var score := int(r.get("score", 0))
	var missed := int(r.get("fraudes_laissees", 0)) + int(r.get("fraudeurs_partis", 0))
	if r.is_empty():
		return "« Pas de rapport ? Bon, on fera sans pour cette fois. »"
	if score >= 60:
		return "« Excellent travail ! La direction va entendre parler de toi. »"
	if score >= 20:
		return "« Du bon boulot. Continue comme ça au retour. »"
	if int(r.get("erreurs_amende", 0)) >= 2:
		return "« Trop d'amendes injustes... J'ai déjà deux réclamations sur le bureau. »"
	if missed >= 3:
		return "« Beaucoup de resquilleurs passés entre les mailles. Ouvre l'œil au retour. »"
	return "« Hmm. Ça peut aller. On attend mieux au retour. »"


func _open_report() -> void:
	if menu:
		return
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = CanvasLayer.new()
	add_child(menu)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var r: Dictionary = Game.aller_result
	_l(box, "Rapport de service — aller", 30, Color(1, 0.9, 0.6))
	_l(box, "%s %s : %s → %s" % [line.type, line.name, line.from, line.to], 18, Color(0.8, 0.85, 0.95))
	_l(box, " ", 6)
	_l(box, "Passagers transportés : %d" % r.get("passagers", 0), 20)
	_l(box, "Contrôles : %d  (dont %d corrects)" % [r.get("controles", 0), r.get("justes", 0)], 20)
	_l(box, "Amendes justifiées : %d  (%d €)" % [r.get("amendes", 0), r.get("amendes_euros", 0)], 20, Color(0.5, 1, 0.55))
	_l(box, "Amendes injustes : %d" % r.get("erreurs_amende", 0), 20, Color(1, 0.55, 0.5))
	_l(box, "Fraudeurs laissés passer : %d" % r.get("fraudes_laissees", 0), 20, Color(1, 0.55, 0.5))
	_l(box, "Fraudeurs descendus sans contrôle : %d" % r.get("fraudeurs_partis", 0), 20, Color(1, 0.7, 0.5))
	_l(box, "Score de l'aller : %d" % r.get("score", 0), 26, Color(1, 0.95, 0.5))
	_l(box, " ", 6)
	_l(box, "Chef de gare : " + _chef_comment(r), 19, Color(0.85, 0.95, 1))
	if not report_done:
		var sign_btn := Button.new()
		sign_btn.text = "Signer le rapport"
		sign_btn.add_theme_font_size_override("font_size", 22)
		sign_btn.custom_minimum_size.y = 50
		sign_btn.pressed.connect(_sign_report)
		box.add_child(sign_btn)
	var close := Button.new()
	close.text = "Fermer (Échap)"
	close.pressed.connect(_close_menu)
	box.add_child(close)


func _sign_report() -> void:
	report_done = true
	_close_menu()
	_update_door()
	_update_board()
	_update_info()
	hud.show_toast("Chef de gare : « Rapport signé. Ton bus pour %s est à quai, monte quand tu veux ! »" % back_line.to,
		Color(0.7, 1, 0.75), 6.0)


func _try_board() -> void:
	if not report_done:
		hud.show_toast("Fais d'abord ton rapport au chef de gare !", Color(1, 0.8, 0.5))
		return
	player.frozen = true
	hud.show_toast("Embarquement... Les voyageurs du quai montent avec toi.", Color(0.8, 0.95, 1), 3.0)
	var boarders: Array = []
	for p in waiting:
		boarders.append(p.data)
	get_tree().create_timer(1.2).timeout.connect(Game.start_return.bind(boarders))


func _close_menu() -> void:
	if menu:
		menu.queue_free()
		menu = null
	player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _l(parent: Node, t: String, size: int, color := Color.WHITE) -> void:
	var lab := Label.new()
	lab.text = t
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lab)


# ------------------------------------------------------------------ voyageurs qui attendent

func _spawn_waiting() -> void:
	var people: Array = []
	for i in rng.randi_range(WAIT_NORMAL_MIN, WAIT_NORMAL_MAX):
		people.append(People.random_passenger(back_line, rng))
	var sp: Array = People.specials(back_line)
	sp.shuffle()
	for i in mini(rng.randi_range(WAIT_SPECIAL_MIN, WAIT_SPECIAL_MAX), sp.size()):
		people.append(sp[i])
	people.shuffle()

	# places assises sur les bancs (3 par banc) et places debout près du bord du quai
	var bench_spots: Array = []
	for z in [-12.0, -6.0, 3.0, 8.0]:
		for dz in [-0.55, 0.0, 0.55]:
			bench_spots.append(Vector3(-2.98, 0, z + dz))
	bench_spots.shuffle()
	var used_standing: Array = []

	for d in people:
		var seated := bench_spots.size() > 0 and rng.randf() < 0.6
		var pos: Vector3
		if seated:
			pos = bench_spots.pop_back()
		else:
			pos = _free_standing_spot(used_standing)
			used_standing.append(pos)
		var p := Passenger.new()
		p.setup(d)
		p.set_meta("waiting", true)
		p.position = pos
		p.rotation_degrees.y = -90 + (0.0 if seated else rng.randf_range(-25, 25))   # face à la voie
		add_child(p)
		if not seated:
			p.set_seated(false)
		waiting.append(p)


func _free_standing_spot(used: Array) -> Vector3:
	for attempt in 30:
		var c := Vector3(rng.randf_range(0.8, 3.0), 0, rng.randf_range(-15.0, 9.0))
		var ok := true
		for u in used:
			if c.distance_to(u) < 0.9:
				ok = false
				break
		if ok and abs(c.z - 6.0) > 0.6:      # pas sous le panneau des départs
			return c
	return Vector3(rng.randf_range(0.8, 3.0), 0, rng.randf_range(-15.0, 9.0))


func _on_interact(t: Node) -> void:
	if t is Interactable:
		t.interact()
	elif t is Passenger:
		var p: Passenger = t
		var txt: String
		if p.data.get("special", false):
			txt = str(p.data.get("greet", "..."))
		else:
			txt = WAIT_LINES[rng.randi() % WAIT_LINES.size()]
			if "%s" in txt:
				txt = txt % back_line.to
		hud.show_toast("%s : « %s »" % [p.data.get("name", "?"), txt], Color(0.9, 0.95, 1), 3.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and menu:
		_close_menu()


# ------------------------------------------------------------------ rendu

func _setup_rendering() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if QUALITY_HIGH else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true
	for c in find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (c as WorldEnvironment).environment
		if env == null:
			continue
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 6.0
		env.ssao_enabled = true
		env.ssao_radius = 0.8
		env.ssao_intensity = 1.4
		env.ssil_enabled = QUALITY_HIGH
		env.ssil_intensity = 0.6
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_hdr_threshold = 1.1
		env.fog_enabled = true
		env.fog_light_color = Color(0.72, 0.78, 0.88)
		env.fog_density = 0.006
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.05
		env.adjustment_saturation = 1.1


func _mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	var found := n.find_children("*", "MeshInstance3D", true, false)
	return found[0] if found.size() > 0 else null


func _own_mat(n: Node) -> StandardMaterial3D:
	var m := _mesh_of(n)
	if m == null:
		return null
	var mat: StandardMaterial3D = m.material_override.duplicate() if m.material_override is StandardMaterial3D else StandardMaterial3D.new()
	m.material_override = mat
	return mat


func _rough(n: Node, r: float) -> Node:
	var mat := _own_mat(n)
	if mat:
		mat.roughness = r
	return n


func _metal(n: Node, rough: float, col = null, metallic := 1.0) -> Node:
	var mat := _own_mat(n)
	if mat:
		if col != null:
			mat.albedo_color = col
		mat.metallic = metallic
		mat.roughness = rough
	return n


func _glow(n: Node, col: Color, energy: float) -> Node:
	var mat := _own_mat(n)
	if mat:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
	var m := _mesh_of(n)
	if m:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n
