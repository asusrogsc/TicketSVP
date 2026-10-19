extends Node3D
## Hall d'entrée de la maison du joueur. Le planning au mur permet de choisir sa ligne.
## Version « HD » : anticrénelage, ombres, occlusion ambiante, éclairage indirect,
## matériaux plus réalistes, miroir réfléchissant et décor plus détaillé.

const QUALITY_HIGH := true    # passe à false si le PC rame

var player: Player
var hud: Hud
var menu: CanvasLayer

var _walls: Array = []        # nœuds renvoyés par Build.box (mesh ou corps physique)
var _woods: Array = []


func _ready() -> void:
	Build.environment(self, Color(0.35, 0.5, 0.8), Color(0.75, 0.8, 0.9), 0.12, 0.0)
	_setup_rendering()
	_build_room()
	_build_details()
	_upgrade_materials()
	_upgrade_lights()

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


# ------------------------------------------------------------------ rendu

func _setup_rendering() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if QUALITY_HIGH else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true

	var we := _find_world_environment(self)
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# occlusion ambiante : coins et dessous de meubles plus sombres
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	# éclairage indirect : la lumière rebondit sur le parquet et les murs
	env.ssil_enabled = QUALITY_HIGH
	env.ssil_intensity = 0.8
	# reflets à l'écran (parquet ciré, miroir)
	env.ssr_enabled = QUALITY_HIGH
	env.ssr_max_steps = 48
	# léger halo autour des lampes
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	# couleurs un peu plus riches
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08


func _find_world_environment(root: Node) -> WorldEnvironment:
	for c in root.get_children():
		if c is WorldEnvironment:
			return c
		var found := _find_world_environment(c)
		if found:
			return found
	return null


func _upgrade_materials() -> void:
	for n in _walls:
		var mat := _std_mat(n)
		if mat:
			mat.roughness = 0.88
	for n in _woods:
		var mat := _std_mat(n)
		if mat:
			mat.roughness = 0.45
			mat.metallic_specular = 0.6


func _upgrade_lights() -> void:
	for l in find_children("*", "OmniLight3D", true, false):
		var o := l as OmniLight3D
		o.shadow_enabled = true
		o.shadow_bias = 0.03
		o.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if QUALITY_HIGH else OmniLight3D.SHADOW_DUAL_PARABOLOID
		o.light_specular = 0.6


# ------------------------------------------------------------------ pièce

func _build_room() -> void:
	var wall := Color(0.82, 0.76, 0.66)
	var wood := Color(0.55, 0.36, 0.2)
	# sol, plafond, murs (pièce de 5 x 7 m)
	_build_oak_floor()
	Build.box(self, Vector3(5, 0.1, 7), Vector3(0, 2.85, 0), Color(0.96, 0.95, 0.92))
	_walls.append(Build.box(self, Vector3(0.1, 2.8, 7), Vector3(-2.5, 1.4, 0), wall))
	_walls.append(Build.box(self, Vector3(0.1, 2.8, 7), Vector3(2.5, 1.4, 0), wall))
	_walls.append(Build.box(self, Vector3(5, 2.8, 0.1), Vector3(0, 1.4, 3.5), wall))
	# mur du fond avec la porte d'entrée
	_walls.append(Build.box(self, Vector3(1.9, 2.8, 0.1), Vector3(-1.55, 1.4, -3.5), wall))
	_walls.append(Build.box(self, Vector3(1.9, 2.8, 0.1), Vector3(1.55, 1.4, -3.5), wall))
	_walls.append(Build.box(self, Vector3(1.2, 0.7, 0.1), Vector3(0, 2.45, -3.5), wall))
	var door := Interactable.new()
	door.label = "Sortir (prends d'abord ton service au planning)"
	door.action = func(): hud.show_toast("Choisis d'abord une ligne sur le planning !", Color(1, 0.8, 0.5))
	door.position = Vector3(0, 1.05, -3.48)
	add_child(door)
	_woods.append(Build.box(door, Vector3(1.1, 2.1, 0.08), Vector3.ZERO, wood))
	# panneaux moulurés de la porte
	for py in [0.45, -0.45]:
		_woods.append(Build.box(door, Vector3(0.8, 0.7, 0.02), Vector3(0, py, 0.045), wood.darkened(0.08), false))
	var knob := Build.box(door, Vector3(0.06, 0.06, 0.12), Vector3(0.42, 0, 0.05), Color(0.85, 0.75, 0.3), false)
	_make_metal(knob, Color(0.85, 0.72, 0.35), 0.25)
	# plinthes
	for x in [-2.44, 2.44]:
		_woods.append(Build.box(self, Vector3(0.02, 0.1, 7), Vector3(x, 0.05, 0), Color(0.45, 0.3, 0.18), false))
	# tapis, meuble à chaussures, porte-manteau, miroir, lampe
	var rug := Build.box(self, Vector3(1.6, 0.02, 3.2), Vector3(0, 0.01, -0.6), Color(0.55, 0.15, 0.18), false)
	_make_fabric(rug)
	Build.box(self, Vector3(1.3, 0.021, 2.9), Vector3(0, 0.011, -0.6), Color(0.62, 0.22, 0.24), false)   # bordure intérieure
	_woods.append(Build.box(self, Vector3(0.45, 0.9, 1.4), Vector3(2.2, 0.45, -1.6), wood))
	_woods.append(Build.box(self, Vector3(0.5, 0.04, 1.5), Vector3(2.2, 0.92, -1.6), Color(0.35, 0.22, 0.12)))
	Build.cylinder(self, 0.035, 1.85, Vector3(-2.1, 0.92, -2.7), Color(0.25, 0.18, 0.12))
	Build.cylinder(self, 0.25, 0.03, Vector3(-2.1, 0.02, -2.7), Color(0.25, 0.18, 0.12))
	# patères du porte-manteau
	for a in [0, 90, 180, 270]:
		var hook := Build.box(self, Vector3(0.22, 0.025, 0.025), Vector3(-2.1, 1.78, -2.7), Color(0.25, 0.18, 0.12), false)
		hook.rotation_degrees.y = a
		hook.position += Vector3(cos(deg_to_rad(a)), 0, -sin(deg_to_rad(a))) * 0.1
	# la casquette de contrôleur posée sur le meuble
	Build.cylinder(self, 0.13, 0.08, Vector3(2.2, 0.98, -1.3), Color(0.1, 0.18, 0.4))
	Build.box(self, Vector3(0.22, 0.015, 0.12), Vector3(2.2, 0.95, -1.15), Color(0.08, 0.08, 0.1), false)
	# miroir : vrai reflet + cadre
	var mirror := Build.box(self, Vector3(0.05, 1.0, 0.7), Vector3(2.44, 1.6, -1.6), Color(0.75, 0.85, 0.9), false, 0.05)
	_make_metal(mirror, Color(0.92, 0.94, 0.96), 0.02)
	_woods.append(Build.box(self, Vector3(0.04, 1.08, 0.78), Vector3(2.46, 1.6, -1.6), Color(0.3, 0.2, 0.12), false))
	var probe := ReflectionProbe.new()
	probe.size = Vector3(5, 2.9, 7)
	probe.position = Vector3(0, 1.45, 0)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
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
		Build.label3d(board, t, Vector3(0, y, 0.05), 26, l.color.darkened(0.2))
		y -= 0.16
	Build.label3d(board, "[E] pour choisir", Vector3(0, -0.36, 0.05), 22, Color(0.3, 0.3, 0.3))
	# spot qui met le planning en valeur
	var spot := SpotLight3D.new()
	spot.position = Vector3(-1.6, 2.7, -0.6)
	spot.rotation_degrees = Vector3(-60, 90, 0)
	spot.light_color = Color(1, 0.93, 0.8)
	spot.light_energy = 1.2
	spot.spot_range = 3.0
	spot.spot_angle = 32
	spot.shadow_enabled = true
	add_child(spot)


# ------------------------------------------------------------------ détails « HD »

func _build_details() -> void:
	var wood_dark := Color(0.42, 0.28, 0.16)
	var trim := Color(0.95, 0.93, 0.88)
	# soubassement en lambris sur les murs latéraux
	for side in [-1, 1]:
		var x: float = side * 2.44
		_woods.append(Build.box(self, Vector3(0.02, 0.9, 7), Vector3(x, 0.55, 0), Color(0.6, 0.45, 0.3), false))
		_woods.append(Build.box(self, Vector3(0.04, 0.04, 7), Vector3(x, 1.0, 0), wood_dark, false))      # cimaise
		var lz := -3.3
		while lz < 3.4:
			_woods.append(Build.box(self, Vector3(0.025, 0.86, 0.015), Vector3(x, 0.55, lz), wood_dark, false))  # joints des lames
			lz += 0.25
		# corniche au plafond
		Build.box(self, Vector3(0.08, 0.08, 7), Vector3(side * 2.42, 2.76, 0), trim, false)
	Build.box(self, Vector3(5, 0.08, 0.08), Vector3(0, 2.76, 3.42), trim, false)
	Build.box(self, Vector3(5, 0.08, 0.08), Vector3(0, 2.76, -3.42), trim, false)
	# encadrement de la porte
	_woods.append(Build.box(self, Vector3(0.08, 2.2, 0.14), Vector3(-0.62, 1.1, -3.45), wood_dark, false))
	_woods.append(Build.box(self, Vector3(0.08, 2.2, 0.14), Vector3(0.62, 1.1, -3.45), wood_dark, false))
	_woods.append(Build.box(self, Vector3(1.32, 0.08, 0.14), Vector3(0, 2.14, -3.45), wood_dark, false))

	# suspension au plafond : fil + abat-jour lumineux
	Build.cylinder(self, 0.008, 0.35, Vector3(0, 2.63, 0), Color(0.1, 0.1, 0.1))
	var shade := Build.cylinder(self, 0.22, 0.18, Vector3(0, 2.38, 0), Color(1, 0.95, 0.85))
	_make_emissive(shade, Color(1, 0.88, 0.7), 1.8)
	# applique près de la porte
	var sconce := Build.cylinder(self, 0.09, 0.14, Vector3(0, 2.32, -3.38), Color(1, 0.95, 0.85))
	_make_emissive(sconce, Color(1, 0.85, 0.7), 1.5)

	# deux cadres sur le mur du fond (côté joueur)
	for fx in [-1.3, 1.3]:
		_woods.append(Build.box(self, Vector3(0.7, 0.5, 0.03), Vector3(fx, 1.65, 3.43), Color(0.2, 0.14, 0.08), false))
		var pic := Build.box(self, Vector3(0.6, 0.4, 0.01), Vector3(fx, 1.65, 3.41),
			Color.from_hsv(0.08 if fx < 0 else 0.55, 0.35, 0.75), false)
		_make_fabric(pic)

	# plante verte dans le coin
	var pot := Build.cylinder(self, 0.18, 0.35, Vector3(-2.15, 0.175, 2.9), Color(0.75, 0.4, 0.25))
	_make_fabric(pot)
	for i in 5:
		var leaf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.5
		leaf.mesh = sm
		leaf.material_override = Build.mat(Color(0.2, 0.45 + 0.04 * i, 0.22))
		leaf.position = Vector3(-2.15 + sin(i * 1.3) * 0.12, 0.6 + i * 0.07, 2.9 + cos(i * 1.3) * 0.12)
		leaf.rotation_degrees = Vector3(20 * sin(i), i * 70, 15)
		add_child(leaf)

	# paillasson devant la porte
	var mat := Build.box(self, Vector3(0.9, 0.025, 0.55), Vector3(0, 0.013, -3.05), Color(0.45, 0.35, 0.22), false)
	_make_fabric(mat)


# ------------------------------------------------------------------ matériaux

## Build.box / Build.cylinder peuvent renvoyer le mesh ou un corps qui le contient.
func _mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	var found := n.find_children("*", "MeshInstance3D", true, false)
	return found[0] if found.size() > 0 else null


## Matériau standard propre à ce nœud (dupliqué pour ne pas modifier les autres objets).
func _std_mat(n: Node) -> StandardMaterial3D:
	var m := _mesh_of(n)
	if m == null or not (m.material_override is StandardMaterial3D):
		return null
	var mat: StandardMaterial3D = m.material_override.duplicate()
	m.material_override = mat
	return mat


func _make_metal(n: Node, col: Color, rough: float) -> void:
	var m := _mesh_of(n)
	if m == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 1.0
	mat.roughness = rough
	m.material_override = mat


func _make_fabric(n: Node) -> void:
	var mat := _std_mat(n)
	if mat:
		mat.roughness = 1.0
		mat.metallic_specular = 0.2


func _make_emissive(n: Node, col: Color, energy: float) -> void:
	var m := _mesh_of(n)
	if m == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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


# ------------------------------------------------------------------ interactions

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
