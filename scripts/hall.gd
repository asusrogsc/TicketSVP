extends Node3D
## Hall d'entrée de la maison du joueur. Le planning au mur permet de choisir sa ligne.
## Version « HD max » : fenêtre avec rayons de soleil (brouillard volumétrique), éclairage global SDFGI,
## papier peint, tapis persan et plâtre procéduraux, mobilier détaillé, jardin visible dehors.

const QUALITY_HIGH := true    # passe à false si le PC rame

var player: Player
var hud: Hud
var menu: CanvasLayer

var _walls: Array = []        # nœuds renvoyés par Build.box (mesh ou corps physique)
var _ceiling: Node = null
var _woods: Array = []


func _ready() -> void:
	Build.environment(self, Color(0.35, 0.5, 0.8), Color(0.75, 0.8, 0.9), 0.12, 0.0)
	_setup_rendering()
	_build_room()
	_build_details()
	_build_window_and_garden()
	_build_hd_extras()
	_upgrade_materials()
	_upgrade_lights()
	_setup_sun()
	_bevel_all(_shader_cache.values())
	_hd_render_settings()

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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	# éclairage global : la lumière du jour entre par la fenêtre et rebondit partout
	env.sdfgi_enabled = QUALITY_HIGH
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.0
	env.sdfgi_cascades = 2
	env.sdfgi_min_cell_size = 0.08
	# brouillard volumétrique : rayons de soleil visibles dans la poussière
	env.volumetric_fog_enabled = QUALITY_HIGH
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(1, 0.97, 0.92)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 25.0 # Augmenté la distance du brouillard
	env.volumetric_fog_ambient_inject = 0.0
	# occlusion ambiante : coins et dessous de meubles plus sombres
	env.ssao_enabled = true
	env.ssao_radius = 1.0 # Augmenté le rayon SSAO
	env.ssao_intensity = 1.8 # Augmenté l'intensité SSAO
	# éclairage indirect : la lumière rebondit sur le parquet et les murs
	env.ssil_enabled = QUALITY_HIGH
	env.ssil_intensity = 1.0 # Augmenté l'intensité SSIL
	# reflets à l'écran (parquet ciré, miroir)
	env.ssr_enabled = QUALITY_HIGH
	env.ssr_max_steps = 128 # Augmenté les étapes SSR
	env.ssr_fade_in = 0.1
	# léger halo autour des lampes
	env.glow_enabled = true
	env.glow_intensity = 0.5 # Augmenté l'intensité du halo
	env.glow_bloom = 0.07 # Augmenté le bloom
	env.glow_hdr_threshold = 1.1 # Ajustement du seuil HDR
	# couleurs un peu plus riches
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1 # Augmenté le contraste
	env.adjustment_saturation = 1.15 # Augmenté la saturation
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sm: ProceduralSkyMaterial = env.sky.sky_material
		sm.sky_top_color = Color(0.28, 0.46, 0.78)
		sm.sky_horizon_color = Color(0.8, 0.84, 0.9)
		sm.ground_bottom_color = Color(0.25, 0.3, 0.2)
		sm.ground_horizon_color = Color(0.7, 0.75, 0.75)


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
		_apply_shader(n, WALLPAPER_SHADER, {})
	if _ceiling:
		_apply_shader(_ceiling, PLASTER_SHADER, {})
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
		o.light_volumetric_fog_energy = 0.25     # pas de « halo brouillard » autour des lampes


# ------------------------------------------------------------------ pièce

func _build_room() -> void:
	var wall := Color(0.82, 0.76, 0.66)
	var wood := Color(0.55, 0.36, 0.2)
	# sol, plafond, murs (pièce de 5 x 7 m)
	_build_oak_floor()
	_ceiling = Build.box(self, Vector3(5, 0.1, 7), Vector3(0, 2.85, 0), Color(0.96, 0.95, 0.92))
	_walls.append(Build.box(self, Vector3(0.1, 2.8, 7), Vector3(-2.5, 1.4, 0), wall))
	# mur droit, percé d'une fenêtre (z 0.8 → 2.3, y 1.1 → 2.4)
	_walls.append(Build.box(self, Vector3(0.1, 2.8, 4.3), Vector3(2.5, 1.4, -1.35), wall))
	_walls.append(Build.box(self, Vector3(0.1, 2.8, 1.2), Vector3(2.5, 1.4, 2.9), wall))
	_walls.append(Build.box(self, Vector3(0.1, 1.1, 1.5), Vector3(2.5, 0.55, 1.55), wall))
	_walls.append(Build.box(self, Vector3(0.1, 0.4, 1.5), Vector3(2.5, 2.6, 1.55), wall))
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
	_apply_shader(rug, RUG_SHADER, {"size": Vector2(1.6, 3.2)})
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
	_make_emissive(Build.box(board, Vector3(1.5, 0.2, 0.025), Vector3(0, 0.35, 0.035), Color(0.12, 0.22, 0.45), false), Color(0.12, 0.22, 0.45), 0.15)
	var head := Build.label3d(board, "PLANNING DU JOUR", Vector3(0, 0.35, 0.05), 40, Color(1, 1, 1))
	head.pixel_size = 0.003
	for px in [-0.7, 0.7]:
		_make_metal(Build.cylinder(board, 0.015, 0.02, Vector3(px, 0.42, 0.05), Color(0.85, 0.2, 0.2)), Color(0.85, 0.2, 0.2), 0.3)
	# une entrée par ligne, sur deux rangs : « Bus Ligne 1 » puis le trajet, en plus gros
	var y := 0.17
	for l in Game.lines:
		Build.box(board, Vector3(0.08, 0.08, 0.01), Vector3(-0.66, y - 0.01, 0.045), l.color, false)   # pastille couleur de ligne
		var name_l := Build.label3d(board, "%s %s" % [l.type, l.name], Vector3(-0.59, y + 0.02, 0.05), 30, l.color.darkened(0.35))
		name_l.pixel_size = 0.0029
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.outline_size = 0
		var route := "%s → %s%s" % [l.from, l.to, "" if l.unlocked else "   (bientôt)"]
		var route_l := Build.label3d(board, route, Vector3(-0.59, y - 0.05, 0.05), 24, Color(0.2, 0.2, 0.25))
		route_l.pixel_size = 0.0026
		route_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		route_l.outline_size = 0
		y -= 0.22
	var hint := Build.label3d(board, "[E] pour choisir", Vector3(0, -0.36, 0.05), 22, Color(0.35, 0.35, 0.38))
	hint.pixel_size = 0.0028
	hint.outline_size = 0
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

	# Plantes : feuilles courbes et pots creux, sans collision supplémentaire.
	_hall_plant_build(Vector3(-2.15, 0.0, 2.9), false)
	# Appui de fenêtre : le pot repose à y=1.10 et reste en retrait de la vitre.
	_hall_plant_build(Vector3(2.35, 1.10, 1.55), true)

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


# ------------------------------------------------------------------ fenêtre, soleil et jardin

func _build_window_and_garden() -> void:
	var white := Color(0.95, 0.94, 0.9)
	var wx := 2.5
	# dormant, croisillons, vitres
	for zz in [0.8, 2.3]:
		Build.box(self, Vector3(0.14, 1.4, 0.07), Vector3(wx - 0.03, 1.75, zz), white, false)
	for yy in [1.1, 2.4]:
		Build.box(self, Vector3(0.14, 0.07, 1.57), Vector3(wx - 0.03, yy, 1.55), white, false)
	Build.box(self, Vector3(0.08, 1.3, 0.05), Vector3(wx, 1.75, 1.55), white, false)       # meneau
	Build.box(self, Vector3(0.08, 0.05, 1.5), Vector3(wx, 1.95, 1.55), white, false)       # traverse
	var glass := Build.box(self, Vector3(0.015, 1.3, 1.5), Vector3(wx, 1.75, 1.55), Color(0.85, 0.92, 1.0, 0.08), false)
	_make_glass(glass)
	# appui de fenêtre + radiateur dessous
	_woods.append(Build.box(self, Vector3(0.28, 0.04, 1.7), Vector3(wx - 0.14, 1.08, 1.55), Color(0.92, 0.9, 0.86), false))
	# radiateur en fonte : éléments serrés, collecteurs haut/bas, pieds, robinet
	var rad_col := Color(0.93, 0.93, 0.91)
	for k in 16:
		var fin := Build.box(self, Vector3(0.1, 0.56, 0.055), Vector3(wx - 0.13, 0.48, 1.0 + k * 0.073), rad_col, false)
		_make_metal(fin, rad_col, 0.45)
	for yy in [0.22, 0.74]:
		_make_metal(Build.box(self, Vector3(0.06, 0.05, 1.16), Vector3(wx - 0.13, yy, 1.55), rad_col, false), rad_col, 0.45)
	for zz in [1.05, 2.05]:
		_make_metal(Build.box(self, Vector3(0.06, 0.2, 0.05), Vector3(wx - 0.13, 0.1, zz), rad_col, false), rad_col, 0.45)
	_make_metal(Build.cylinder(self, 0.012, 0.22, Vector3(wx - 0.13, 0.11, 0.9), Color(0.85, 0.85, 0.85)), Color(0.85, 0.85, 0.85), 0.3)
	_make_metal(Build.cylinder(self, 0.025, 0.05, Vector3(wx - 0.13, 0.8, 0.95), Color(0.85, 0.7, 0.35)), Color(0.85, 0.7, 0.35), 0.25)
	# tringle et rideaux à plis
	var rod := Build.cylinder(self, 0.015, 2.3, Vector3(wx - 0.12, 2.6, 1.55), Color(0.7, 0.55, 0.3))
	rod.rotation_degrees.x = 90
	_make_metal(rod, Color(0.75, 0.6, 0.32), 0.3)
	for side in [-1, 1]:
		var cz: float = 1.55 + side * 0.95
		for k in 6:
			var fold := Build.box(self, Vector3(0.05, 2.0, 0.09), Vector3(wx - 0.1 - (k % 2) * 0.04, 1.6, cz + (k - 2.5) * 0.075),
				Color(0.62, 0.18, 0.2).darkened(0.06 * (k % 2)), false)
			_make_fabric(fold)
		# embrasse dorée
		_make_metal(Build.box(self, Vector3(0.1, 0.03, 0.5), Vector3(wx - 0.1, 1.2, cz), Color(0.85, 0.7, 0.3), false), Color(0.85, 0.7, 0.3), 0.3)

	# le jardin dehors : pelouse, haie, arbres, maison d'en face
	var outside := Node3D.new()
	add_child(outside)
	var grass := Build.box(outside, Vector3(40, 0.1, 40), Vector3(22.6, -0.1, 0), Color(0.32, 0.52, 0.26), false)
	_make_fabric(grass)
	Build.box(outside, Vector3(1.2, 0.04, 6), Vector3(3.4, -0.03, 1.5), Color(0.7, 0.68, 0.64), false)   # allée
	var hedge := Build.box(outside, Vector3(0.8, 1.3, 30), Vector3(9.0, 0.65, 0), Color(0.18, 0.38, 0.18), false)
	_make_fabric(hedge)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for tz in [-6.0, 1.0, 7.5]:
		var trunk := Build.cylinder(outside, 0.18, 3.0, Vector3(7.0, 1.5, tz), Color(0.36, 0.25, 0.15))
		_make_fabric(trunk)
		for k in 5:
			var leaves := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(1.0, 1.5)
			sm.height = sm.radius * 1.8
			leaves.mesh = sm
			leaves.material_override = Build.mat(Color(0.22, 0.46 + rng.randf() * 0.12, 0.2), 1.0)
			leaves.position = Vector3(7.0 + rng.randf_range(-0.7, 0.7), 3.6 + rng.randf_range(-0.3, 0.9), tz + rng.randf_range(-0.7, 0.7))
			outside.add_child(leaves)
	var house := Build.box(outside, Vector3(8, 7, 14), Vector3(18, 3.5, 1), Color(0.88, 0.8, 0.68), false)
	_make_fabric(house)
	var roof := Build.box(outside, Vector3(8.6, 0.4, 14.6), Vector3(18, 7.2, 1), Color(0.55, 0.25, 0.2), false)
	_make_fabric(roof)
	for wz in [-3.5, 1.0, 5.5]:
		for wy in [1.8, 4.8]:
			Build.box(outside, Vector3(0.05, 1.3, 1.1), Vector3(13.97, wy, wz), white, false)
			var g := Build.box(outside, Vector3(0.05, 1.15, 0.95), Vector3(13.95, wy, wz), Color(0.4, 0.5, 0.62), false)
			_make_metal(g, Color(0.4, 0.5, 0.62), 0.08)


func _setup_sun() -> void:
	# soleil d'après-midi qui entre par la fenêtre et dessine les croisillons au sol
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 68, 0)
	sun.light_color = Color(1, 0.88, 0.7)
	sun.light_energy = 2.2
	sun.light_volumetric_fog_energy = 2.5
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


# ------------------------------------------------------------------ mobilier et décor supplémentaires

func _build_hd_extras() -> void:
	var wood := Color(0.42, 0.26, 0.14)
	var brass := Color(0.85, 0.7, 0.35)
	var cream := Color(1, 0.94, 0.82)

	# rosace au plafond autour de la suspension
	_woods.append(Build.cylinder(self, 0.3, 0.03, Vector3(0, 2.785, 0), Color(0.96, 0.95, 0.92)))
	_woods.append(Build.cylinder(self, 0.2, 0.05, Vector3(0, 2.77, 0), Color(0.96, 0.95, 0.92)))

	# --- mur du fond (côté joueur) : console, lampe, grande affiche, appliques
	var cz := 3.25
	_woods.append(Build.box(self, Vector3(1.4, 0.05, 0.38), Vector3(0, 0.8, cz), wood))
	for lx in [-0.64, 0.64]:
		for lz in [cz - 0.15, cz + 0.15]:
			_woods.append(Build.box(self, Vector3(0.04, 0.78, 0.04), Vector3(lx, 0.39, lz), wood, false))
	_woods.append(Build.box(self, Vector3(1.3, 0.03, 0.32), Vector3(0, 0.25, cz), wood, false))   # tablette basse
	for k in 3:   # livres sur la tablette
		Build.box(self, Vector3(0.05, 0.22, 0.2), Vector3(-0.5 + k * 0.06, 0.375, cz), Color.from_hsv(0.1 + k * 0.3, 0.5, 0.55), false)
	# lampe de table
	_make_metal(Build.cylinder(self, 0.07, 0.03, Vector3(0.45, 0.84, cz), brass), brass, 0.3)
	_make_metal(Build.cylinder(self, 0.015, 0.35, Vector3(0.45, 1.0, cz), brass), brass, 0.3)
	var shade := Build.cylinder(self, 0.15, 0.2, Vector3(0.45, 1.24, cz), cream)
	_make_emissive(shade, Color(1, 0.86, 0.62), 1.6)
	Build.light(self, Vector3(0.45, 1.2, cz - 0.1), Color(1, 0.82, 0.58), 0.45, 3.5)
	# vide-poche et clés, petite plante
	_make_metal(Build.cylinder(self, 0.1, 0.03, Vector3(-0.2, 0.84, cz), Color(0.3, 0.45, 0.6)), Color(0.3, 0.45, 0.6), 0.2)
	_make_metal(Build.box(self, Vector3(0.06, 0.01, 0.02), Vector3(-0.2, 0.86, cz), brass, false), brass, 0.25)
	Build.cylinder(self, 0.06, 0.1, Vector3(-0.5, 0.88, cz), Color(0.9, 0.9, 0.88))
	var succ := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 0.08
	ss.height = 0.12
	succ.mesh = ss
	succ.material_override = Build.mat(Color(0.3, 0.55, 0.35), 0.9)
	succ.position = Vector3(-0.5, 0.97, cz)
	add_child(succ)
	# grande affiche rétro du réseau
	_woods.append(Build.box(self, Vector3(1.0, 0.75, 0.03), Vector3(0, 1.75, 3.43), Color(0.15, 0.1, 0.06), false))
	var poster := Build.box(self, Vector3(0.9, 0.65, 0.01), Vector3(0, 1.75, 3.41), Color(0.95, 0.88, 0.7), false)
	_make_fabric(poster)
	Build.box(self, Vector3(0.9, 0.18, 0.012), Vector3(0, 1.55, 3.405), Color(0.85, 0.35, 0.2), false)        # soleil couchant
	var bus_shape := Build.box(self, Vector3(0.5, 0.16, 0.014), Vector3(0, 1.7, 3.4), Color(0.1, 0.45, 0.85), false)
	_make_fabric(bus_shape)
	for wx in [-0.17, -0.06, 0.05, 0.16]:
		Build.box(self, Vector3(0.08, 0.06, 0.016), Vector3(wx, 1.73, 3.398), Color(0.9, 0.95, 1.0), false)
	for wx in [-0.15, 0.15]:
		Build.cylinder(self, 0.035, 0.018, Vector3(wx, 1.61, 3.398), Color(0.1, 0.1, 0.1)).rotation_degrees.x = 90
	var pt := Build.label3d(self, "LIGNE 1 — DEPUIS 1962", Vector3(0, 1.98, 3.395), 30, Color(0.15, 0.15, 0.25))
	pt.rotation_degrees.y = 180
	pt.pixel_size = 0.0022
	pt.outline_size = 0
	# appliques murales
	for sx in [-1.95, 1.95]:
		_make_metal(Build.box(self, Vector3(0.12, 0.2, 0.04), Vector3(sx, 2.0, 3.43), brass, false), brass, 0.3)
		var tulip := Build.cylinder(self, 0.08, 0.14, Vector3(sx, 2.12, 3.36), cream)
		_make_emissive(tulip, Color(1, 0.85, 0.6), 1.4)
		Build.light(self, Vector3(sx, 2.2, 3.3), Color(1, 0.84, 0.6), 0.3, 3.0)

	# --- côté porte : imposte lumineuse, interrupteur, porte-parapluies, banc à chaussures
	var fan := Build.box(self, Vector3(1.0, 0.3, 0.02), Vector3(0, 2.42, -3.44), Color(0.95, 0.97, 1.0), false)
	_make_emissive(fan, Color(0.95, 0.97, 1.0), 1.2)
	for k in 4:
		Build.box(self, Vector3(0.025, 0.3, 0.025), Vector3(-0.36 + k * 0.24, 2.42, -3.43), Color(0.95, 0.94, 0.9), false)
	Build.box(self, Vector3(0.08, 0.12, 0.015), Vector3(0.8, 1.1, -3.44), Color(0.96, 0.96, 0.94), false)   # interrupteur
	Build.box(self, Vector3(0.12, 0.2, 0.02), Vector3(0.8, 1.45, -3.44), Color(0.2, 0.2, 0.22), false)      # interphone
	_make_emissive(Build.box(self, Vector3(0.06, 0.04, 0.005), Vector3(0.8, 1.5, -3.428), Color(0.3, 0.8, 1), false), Color(0.3, 0.8, 1), 0.8)
	_make_metal(Build.cylinder(self, 0.13, 0.5, Vector3(1.05, 0.25, -3.1), Color(0.2, 0.3, 0.35)), Color(0.2, 0.3, 0.35), 0.3)
	for k in 2:
		var umb := Build.cylinder(self, 0.035, 0.8, Vector3(1.0 + k * 0.08, 0.6, -3.1), [Color(0.1, 0.1, 0.12), Color(0.7, 0.15, 0.15)][k])
		umb.rotation_degrees.z = 8 - k * 14
	_woods.append(Build.box(self, Vector3(0.9, 0.04, 0.35), Vector3(-1.4, 0.45, -3.2), wood))
	for bx in [-1.8, -1.0]:
		_woods.append(Build.box(self, Vector3(0.04, 0.45, 0.33), Vector3(bx, 0.225, -3.2), wood, false))
	for k in 2:   # chaussures de service rangées dessous
		Build.box(self, Vector3(0.11, 0.08, 0.28), Vector3(-1.55 + k * 0.14, 0.04, -3.2), Color(0.06, 0.06, 0.07), false)

	# --- porte-manteau : veste de contrôleur et écharpe
	_build_coat(Vector3(-1.93, 0, -2.7))
	# casquette de rechange accrochée à la patère côté fenêtre
	var cap := Build.cylinder(self, 0.12, 0.07, Vector3(-2.1, 1.7, -2.55), Color(0.1, 0.16, 0.36))
	cap.rotation_degrees.x = -70
	_make_fabric(cap)
	var visor := Build.box(self, Vector3(0.18, 0.012, 0.1), Vector3(-2.1, 1.62, -2.49), Color(0.05, 0.05, 0.06), false)
	visor.rotation_degrees.x = -70
	var band := Build.cylinder(self, 0.122, 0.02, Vector3(-2.1, 1.7, -2.555), Color(0.95, 0.8, 0.1))
	band.rotation_degrees.x = -70
	# écharpe sur la patère arrière
	for k in 2:
		var scarf := Build.box(self, Vector3(0.025, 0.55, 0.11), Vector3(-2.1 + (k - 0.5) * 0.04, 1.5, -2.82), Color(0.72, 0.18, 0.2), false)
		scarf.rotation_degrees.z = (k - 0.5) * 8
		_make_fabric(scarf)
	for k in 3:   # franges
		Build.box(self, Vector3(0.02, 0.05, 0.1), Vector3(-2.12 + k * 0.02, 1.2, -2.82), Color(0.6, 0.12, 0.15), false)

	# --- meuble à chaussures : tiroirs et boutons
	for dy in [0.25, 0.6]:
		Build.box(self, Vector3(0.01, 0.006, 1.3), Vector3(1.973, dy + 0.17, -1.6), Color(0.25, 0.15, 0.08), false)
		for dz in [-1.9, -1.3]:
			var knob := Build.cylinder(self, 0.018, 0.03, Vector3(1.965, dy, dz), brass)
			knob.rotation_degrees.z = 90
			_make_metal(knob, brass, 0.25)

	# --- horloge murale au-dessus du planning
	var clock := Build.cylinder(self, 0.18, 0.04, Vector3(-2.43, 2.35, -0.6), Color(0.97, 0.96, 0.92))
	clock.rotation_degrees.z = 90
	var rim := Build.cylinder(self, 0.2, 0.03, Vector3(-2.44, 2.35, -0.6), Color(0.2, 0.12, 0.06))
	rim.rotation_degrees.z = 90
	var t := Time.get_time_dict_from_system()
	for hand in [[deg_to_rad((t.hour % 12) * 30.0 + t.minute * 0.5), 0.1, 0.014], [deg_to_rad(t.minute * 6.0), 0.15, 0.009]]:
		var h := Build.box(self, Vector3(0.006, hand[1], hand[2]), Vector3.ZERO, Color(0.08, 0.08, 0.1), false)
		h.rotation = Vector3(-hand[0], 0, 0)
		h.position = Vector3(-2.405, 2.35, -0.6) + Vector3(0, cos(hand[0]), -sin(hand[0])) * hand[1] * 0.5


func _make_glass(n: Node) -> void:
	var m := _mesh_of(n)
	if m == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.92, 1.0, 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.2
	mat.roughness = 0.02
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ matériaux procéduraux

const WALLPAPER_SHADER := """
shader_type spatial;
uniform vec4 col_a : source_color = vec4(0.86, 0.8, 0.7, 1.0);
uniform vec4 col_b : source_color = vec4(0.8, 0.73, 0.62, 1.0);
uniform vec4 col_motif : source_color = vec4(0.72, 0.62, 0.5, 1.0);
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float motif(vec2 uv) {
	float s = fract(uv.x / 0.24);
	vec2 m = vec2(s - 0.25, fract(uv.y / 0.16) - 0.5);
	float d = abs(m.x) * 3.0 + abs(m.y) * 2.0;
	return (s < 0.5) ? 1.0 - smoothstep(0.14, 0.2, d) : 0.0;
}
// papier gaufré : motif en relief + fibres
float height(vec2 uv) {
	return motif(uv) + noise(uv * 10.0) * 0.08;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = abs(wnrm);
	bool xface = n.x > n.z;
	vec2 uv = xface ? wpos.zy : wpos.xy;
	vec3 A = xface ? vec3(0, 0, 1) : vec3(1, 0, 0);
	vec3 B = vec3(0, 1, 0);
	float s = fract(uv.x / 0.24);
	vec3 col = s < 0.5 ? col_a.rgb : col_b.rgb;
	col = mix(col, col_b.rgb * 0.92, step(0.48, s) * step(s, 0.52));
	col = mix(col, col_motif.rgb, motif(uv) * 0.7);
	col *= 0.97 + 0.03 * noise(uv * 30.0) + 0.02 * noise(uv * 4.0);
	ALBEDO = col;
	ROUGHNESS = 0.88 - motif(uv) * 0.25;      // motif légèrement satiné
	float e = 0.001;
	float h = height(uv);
	vec2 g = vec2(height(uv + vec2(e, 0.0)) - h, height(uv + vec2(0.0, e)) - h) / e;
	vec3 nw = normalize(wnrm - 0.0009 * (g.x * A + g.y * B));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
"""

const PLASTER_SHADER := """
shader_type spatial;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float height(vec2 p) { return noise(p * 6.0) * 0.6 + noise(p * 18.0) * 0.25; }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float h = height(wpos.xz);
	ALBEDO = vec3(0.95, 0.94, 0.91) * (0.98 + 0.03 * h);
	ROUGHNESS = 0.95;
	float e = 0.002;
	vec2 g = vec2(height(wpos.xz + vec2(e, 0.0)) - h, height(wpos.xz + vec2(0.0, e)) - h) / e;
	vec3 nw = normalize(wnrm - 0.0006 * (g.x * vec3(1, 0, 0) + g.y * vec3(0, 0, 1)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
"""

const RUG_SHADER := """
shader_type spatial;
uniform vec2 size = vec2(1.6, 3.2);
varying vec3 lpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
varying vec3 wn;
float pile(vec2 p) {
	// trame tissée + touffes de laine
	return sin(p.x * 500.0) * sin(p.y * 500.0) * 0.15 + noise(p * 220.0) * 0.6 + noise(p * 40.0) * 0.25;
}
void vertex() { lpos = VERTEX; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	vec2 p = lpos.xz;
	vec2 h = size * 0.5;
	float e = min(h.x - abs(p.x), h.y - abs(p.y));      // distance au bord (m)
	vec3 red = vec3(0.55, 0.1, 0.12);
	vec3 navy = vec3(0.1, 0.13, 0.3);
	vec3 cream = vec3(0.9, 0.82, 0.62);
	vec3 gold = vec3(0.8, 0.6, 0.25);
	vec3 col = red;
	if (e < 0.08) {
		col = navy;
	} else if (e < 0.095) {
		col = cream;
	} else if (e < 0.22) {
		// frise : petits losanges le long du bord
		float t = (abs(p.x) > h.x - 0.22 && abs(p.y) < h.y - 0.22) ? p.y : p.x;
		float f = abs(fract(t / 0.12) - 0.5) * 2.0;
		float band = abs((e - 0.157) / 0.06);
		col = (f + band < 0.9) ? gold : red * 0.85;
	} else if (e < 0.235) {
		col = cream;
	} else {
		// champ : treillis de losanges + médaillon central
		float l = min(abs(fract((p.x + p.y) * 3.0) - 0.5), abs(fract((p.x - p.y) * 3.0) - 0.5));
		col = l < 0.04 ? gold * 0.9 : red;
		float r = length(p * vec2(1.0, 0.62));
		if (r < 0.42) col = navy;
		if (r < 0.42 && r > 0.39) col = cream;
		if (r < 0.2) col = mix(red, gold, step(0.5, fract(r * 25.0)));
	}
	col *= 0.85 + 0.2 * noise(p * 140.0) + 0.05 * noise(p * 9.0);   // velours de la laine
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	float eps = 0.0008;
	float h0 = pile(p);
	vec2 g = vec2(pile(p + vec2(eps, 0.0)) - h0, pile(p + vec2(0.0, eps)) - h0) / eps;
	vec3 nw = normalize(wn - 0.0006 * (g.x * vec3(1, 0, 0) + g.y * vec3(0, 0, 1)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	AO = 0.85 + 0.15 * h0;
}
"""

func _apply_shader(n: Node, code: String, params: Dictionary) -> void:
	var m := _mesh_of(n)
	if m == null:
		return
	if not _shader_cache.has(code):
		var sh := Shader.new()
		sh.code = code
		_shader_cache[code] = sh
	var mat := ShaderMaterial.new()
	mat.shader = _shader_cache[code]
	for k in params:
		mat.set_shader_parameter(k, params[k])
	m.material_override = mat

var _shader_cache := {}


## Veste de contrôleur suspendue, face à la pièce (+X) : épaules, buste, manches, col, boutons, bandes réfléchissantes.
func _build_coat(at: Vector3) -> void:
	var navy := Color(0.11, 0.16, 0.34)
	var yellow := Color(0.95, 0.8, 0.1)
	var root := Node3D.new()
	root.position = at
	add_child(root)
	# cintre en bois sur la patère
	var hanger := Build.box(root, Vector3(0.02, 0.025, 0.4), Vector3(0, 1.7, 0), Color(0.55, 0.38, 0.2), false)
	_make_fabric(hanger)
	# épaules arrondies
	var sh := MeshInstance3D.new()
	var shm := CapsuleMesh.new()
	shm.radius = 0.065
	shm.height = 0.46
	sh.mesh = shm
	sh.material_override = Build.mat(navy, 0.9)
	sh.position = Vector3(0, 1.64, 0)
	sh.rotation_degrees.x = 90
	root.add_child(sh)
	# buste (s'évase légèrement vers le bas) et pans
	for part in [[Vector3(0.13, 0.32, 0.4), 1.44], [Vector3(0.12, 0.3, 0.42), 1.13]]:
		var b := Build.box(root, part[0], Vector3(0, part[1], 0), navy, false)
		_make_fabric(b)
	# ouverture centrale + col
	Build.box(root, Vector3(0.005, 0.6, 0.012), Vector3(0.066, 1.28, 0), Color(0.05, 0.07, 0.15), false)
	for side in [-1, 1]:
		var col := Build.box(root, Vector3(0.02, 0.12, 0.09), Vector3(0.07, 1.6, side * 0.05), navy.darkened(0.25), false)
		col.rotation_degrees.x = side * 25
	# boutons dorés
	for k in 4:
		_make_metal(Build.box(root, Vector3(0.012, 0.022, 0.022), Vector3(0.068, 1.52 - k * 0.12, 0.025), Color(0.85, 0.7, 0.3), false), Color(0.85, 0.7, 0.3), 0.25)
	# poches
	for side in [-1, 1]:
		Build.box(root, Vector3(0.008, 0.012, 0.12), Vector3(0.064, 1.12, side * 0.12), Color(0.05, 0.07, 0.15), false)
	# manches qui pendent
	for side in [-1, 1]:
		var sl := MeshInstance3D.new()
		var slm := CapsuleMesh.new()
		slm.radius = 0.05
		slm.height = 0.6
		sl.mesh = slm
		sl.material_override = Build.mat(navy.darkened(0.05), 0.9)
		sl.position = Vector3(-0.01, 1.33, side * 0.23)
		sl.rotation_degrees.x = side * 6
		root.add_child(sl)
		Build.box(root, Vector3(0.105, 0.035, 0.105), Vector3(-0.01, 1.16, side * 0.235), yellow, false)   # bande de manche
	# bande réfléchissante autour du buste
	_make_emissive(Build.box(root, Vector3(0.125, 0.04, 0.425), Vector3(0, 1.2, 0), yellow, false), yellow, 0.15)


# ------------------------------------------------------------------ palier 1 : réglages moteur HD + arêtes biseautées

## Anticrénelage TAA, ombres douces haute résolution (PCSS), SSAO/SSIL en haute qualité.
func _hd_render_settings() -> void:
	var vp := get_viewport()
	if QUALITY_HIGH:
		vp.use_taa = true
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.msaa_3d = Viewport.MSAA_2X
	vp.positional_shadow_atlas_size = 8192 if QUALITY_HIGH else 4096
	RenderingServer.directional_shadow_atlas_set_size(8192 if QUALITY_HIGH else 4096, true)
	var sq := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if QUALITY_HIGH else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(sq)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if QUALITY_HIGH else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, not QUALITY_HIGH, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if QUALITY_HIGH else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, not QUALITY_HIGH, 0.5, 4, 50.0, 300.0)
	RenderingServer.screen_space_roughness_limiter_set_active(true, 0.25, 0.18)   # moins de scintillement sur les reflets
	# ombres douces qui s'élargissent avec la distance (comme dans la réalité)
	for l in find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).light_angular_distance = 0.6
	for l in find_children("*", "OmniLight3D", true, false):
		var o := l as OmniLight3D
		o.light_size = 0.08
		o.shadow_blur = 1.2
	for l in find_children("*", "SpotLight3D", true, false):
		(l as SpotLight3D).light_size = 0.05


var _bevel_cache := {}


## Remplace les boîtes du décor par des boîtes aux arêtes chanfreinées : la lumière accroche les angles.
## Les très grandes surfaces (sols, murs) et les matériaux inconnus (ex. parquet) ne sont pas touchés.
func _bevel_all(known_shaders: Array) -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not (mi.mesh is BoxMesh):
			continue
		var mo := mi.material_override
		if mo is ShaderMaterial and not known_shaders.has((mo as ShaderMaterial).shader):
			continue
		var sz: Vector3 = (mi.mesh as BoxMesh).size
		var mn := minf(sz.x, minf(sz.y, sz.z))
		var mx := maxf(sz.x, maxf(sz.y, sz.z))
		if mn < 0.008 or mx > 6.0:
			continue
		var r := clampf(mn * 0.18, 0.002, 0.02)
		var key := "%.4f_%.4f_%.4f_%.4f" % [sz.x, sz.y, sz.z, r]
		if not _bevel_cache.has(key):
			_bevel_cache[key] = _chamfer_box(sz, r)
		mi.mesh = _bevel_cache[key]


## Boîte chanfreinée : 6 faces, 12 biseaux d'arête, 8 coins.
func _chamfer_box(size: Vector3, r: float) -> ArrayMesh:
	var h := size * 0.5
	var inner := h - Vector3(r, r, r)
	# point du coin s (signes ±1) sur la face perpendiculaire à l'axe a
	var P := func(a: int, s: Vector3) -> Vector3:
		var p := Vector3(s.x * inner.x, s.y * inner.y, s.z * inner.z)
		p[a] = s[a] * h[a]
		return p
	var tris: Array = []
	var add_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		tris.append([a, b, c])
		tris.append([a, c, d])
	# faces principales
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			var pts: Array = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var s := Vector3.ZERO
				s[a] = sa
				s[u] = uv.x
				s[v] = uv.y
				pts.append(P.call(a, s))
			add_quad.call(pts[0], pts[1], pts[2], pts[3])
	# biseaux d'arête
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var s1 := Vector3.ZERO
				s1[a] = sa
				s1[b] = sb
				s1[c] = -1.0
				var s2 := s1
				s2[c] = 1.0
				add_quad.call(P.call(a, s1), P.call(b, s1), P.call(b, s2), P.call(a, s2))
	# coins
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				tris.append([P.call(0, s), P.call(1, s), P.call(2, s)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var cr := (p1 - p0).cross(p2 - p0)
		if cr.length() < 1e-9:
			continue
		var centroid := (p0 + p1 + p2) / 3.0
		# Godot : faces avant en sens horaire vu de l'extérieur
		if cr.dot(centroid) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
			cr = -cr
		var nrm := (-cr).normalized()
		for p in [p0, p1, p2]:
			st.set_normal(nrm)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)
	return st.commit()


# ------------------------------------------------------------------ plantes décoratives
# Géométrie opaque, sans texture externe, animation, collision ni tirage RNG global.
const _HALL_LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
void fragment() {
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	float edge = abs(UV.x - 0.5) * 2.0;
	float rib = 1.0 - smoothstep(0.006, 0.018, abs(UV.x - 0.5));
	float phase = UV.y * 9.0 + abs(UV.x - 0.5) * 4.0;
	float veins = 1.0 - smoothstep(0.012, 0.045 + fwidth(phase), abs(fract(phase) - 0.5));
	vec3 leaf_color = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) {
		leaf_color = mix(leaf_color / 12.92, pow((leaf_color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), leaf_color));
	}
	ALBEDO = leaf_color * (1.04 - 0.12 * edge + 0.13 * rib + 0.045 * veins);
	ROUGHNESS = 0.59;
	SPECULAR = 0.25;
	BACKLIGHT = leaf_color * 0.08;
}
"""

func _hall_plant_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic_specular = 0.25
	return mat


# Profil tourné : flanc conique, lèvre arrondie et intérieur réellement creusé.
func _hall_plant_lathe(parent: Node3D, profile: PackedVector2Array, mat: Material, label: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(profile.size() - 1):
		for i in 48:
			var a := TAU * float(i) / 48.0
			var b := TAU * float(i + 1) / 48.0
			var p := profile[j]
			var q := profile[j + 1]
			var v := [Vector3(cos(a)*p.x, p.y, sin(a)*p.x), Vector3(cos(b)*p.x, p.y, sin(b)*p.x),
				Vector3(cos(a)*q.x, q.y, sin(a)*q.x), Vector3(cos(b)*q.x, q.y, sin(b)*q.x)]
			for k in [0, 1, 2, 1, 3, 2]:
				st.add_vertex(v[k])
	st.generate_normals()
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)


func _hall_plant_blade_point(start: Vector3, direction: Vector3, length: float, width: float,
		rise: float, droop: float, t: float, s: float) -> Vector3:
	var side := Vector3(-direction.z, 0.0, direction.x).normalized()
	var shape := pow(maxf(0.0, sin(PI * t)), 0.78)
	var fold := width * shape * (0.075 - 0.16 * pow(absf(s), 1.4))
	return start + direction * length * t + side * s * width * 0.5 * shape \
		+ Vector3.UP * (rise * sin(PI * t) - droop * t * t + fold)


# Une feuille est une surface courbe nervurée, pas une sphère ni un plan alpha.
func _hall_plant_blade(st: SurfaceTool, start: Vector3, direction: Vector3, length: float,
		width: float, rise: float, droop: float, color: Color) -> void:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for row in 13:
		var t := float(row) / 12.0
		for col in 5:
			var s := float(col) * 0.5 - 1.0
			var point := _hall_plant_blade_point(start, direction, length, width, rise, droop, t, s)
			var dt := _hall_plant_blade_point(start, direction, length, width, rise, droop, minf(t + 0.002, 0.999), s) \
				- _hall_plant_blade_point(start, direction, length, width, rise, droop, maxf(t - 0.002, 0.001), s)
			var ds := _hall_plant_blade_point(start, direction, length, width, rise, droop, clampf(t, 0.001, 0.999), s + 0.002) \
				- _hall_plant_blade_point(start, direction, length, width, rise, droop, clampf(t, 0.001, 0.999), s - 0.002)
			vertices.append(point)
			normals.append(ds.cross(dt).normalized())
			uvs.append(Vector2(float(col) / 4.0, t))
	for row in 12:
		for col in 4:
			var a := row * 5 + col
			for k in [a, a + 5, a + 1, a + 1, a + 5, a + 6]:
				st.set_normal(normals[k])
				st.set_uv(uvs[k])
				st.set_color(color)
				st.add_vertex(vertices[k])


# Petits tubes suivant une courbe de Bézier ; même maillage pour toutes les tiges.
func _hall_plant_stem(st: SurfaceTool, start: Vector3, control: Vector3, finish: Vector3, radius: float) -> void:
	var rings: Array[Vector3] = []
	for j in 9:
		var t := float(j) / 8.0
		var center := start * (1.0-t)*(1.0-t) + control * 2.0*t*(1.0-t) + finish * t*t
		var tangent := ((control-start)*(1.0-t) + (finish-control)*t).normalized()
		var side := tangent.cross(Vector3.FORWARD).normalized()
		if side.length_squared() < 0.01:
			side = tangent.cross(Vector3.RIGHT).normalized()
		var other := tangent.cross(side).normalized()
		for i in 8:
			var a := TAU * float(i) / 8.0
			rings.append(center + (side*cos(a) + other*sin(a)) * radius * (1.0 - 0.35*t))
	for j in 8:
		for i in 8:
			var a := j*8+i
			var b := j*8+(i+1)%8
			for k in [a, a+8, b, b, a+8, b+8]:
				st.add_vertex(rings[k])


func _hall_plant_finish_mesh(parent: Node3D, st: SurfaceTool, mat: Material, label: String, normals: bool) -> void:
	if normals:
		st.generate_normals()
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)


func _hall_plant_build(origin: Vector3, window_plant: bool) -> void:
	var root := Node3D.new()
	root.name = "PlanteFenetre" if window_plant else "PlanteCoin"
	root.position = origin
	add_child(root)
	var radius := 0.13 if window_plant else 0.18
	var height := 0.28 if window_plant else 0.35
	var ceramic := _hall_plant_material(Color(0.72, 0.69, 0.59) if window_plant else Color(0.67, 0.36, 0.23), 0.46 if window_plant else 0.79)
	var profile := PackedVector2Array([
		Vector2(radius*0.64, height*0.05), Vector2(radius*0.69, height*0.09),
		Vector2(radius*0.92, height*0.86), Vector2(radius*0.99, height*0.93),
		Vector2(radius, height*0.98), Vector2(radius*0.97, height),
		Vector2(radius*0.88, height), Vector2(radius*0.86, height*0.95),
		Vector2(radius*0.86, height*0.86)])
	_hall_plant_lathe(root, profile, ceramic, "PotCreux")
	_hall_plant_lathe(root, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(radius*1.04, 0.0), Vector2(radius*1.08, 0.009),
		Vector2(radius*1.08, 0.022), Vector2(radius*1.01, 0.022),
		Vector2(radius*0.96, 0.014), Vector2(0.0, 0.014)]), ceramic, "Soucoupe")
	var soil := CylinderMesh.new()
	soil.top_radius = radius*0.865
	soil.bottom_radius = radius*0.865
	soil.height = 0.014
	soil.radial_segments = 40
	var earth := MeshInstance3D.new()
	earth.name = "Terreau"
	earth.mesh = soil
	earth.position.y = height*0.89
	earth.material_override = _hall_plant_material(Color(0.105, 0.065, 0.033), 1.0)
	root.add_child(earth)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	if window_plant:
		# Deux cannes fines ; feuillage déporté vers l'intérieur, jamais dans la vitre.
		for head in 2:
			var foot := Vector3(-0.025 + head*0.052, height*0.89, -0.018 + head*0.045)
			var crown := Vector3(-0.055 + head*0.025, 0.94 - head*0.23, -0.01 + head*0.07)
			_hall_plant_stem(stems, foot, (foot+crown)*0.5 + Vector3(-0.018,0,0), crown, 0.009)
			for i in 13:
				var angle := i*2.39996 + head*1.2
				var direction := Vector3(cos(angle), 0.0, sin(angle))
				if direction.x > 0.0:
					direction.x *= 0.25
				var start := crown + Vector3(0.0, float(i%4)*0.009, 0.0)
				_hall_plant_blade(leaves, start, direction, 0.27 + float(i%4)*0.032,
					0.037 + float(i%3)*0.008, 0.07 + float(i%3)*0.018, 0.12 + float(i%4)*0.025,
					Color(0.23 + float(i%3)*0.018, 0.40 + float(i%4)*0.023, 0.14 + float(i%2)*0.02))
	else:
		# Touffe de feuilles larges : pétioles distincts, hauteurs et angles irréguliers.
		for i in 11:
			var angle := i*2.39996 + 0.35
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			if direction.x < 0.0:
				direction.x *= 0.60
			var tier := float(i%4)
			var foot := Vector3(sin(i*1.7)*0.035, height*0.89, cos(i*1.7)*0.035)
			var start := direction*(0.035 + tier*0.014) + Vector3(0, 0.49 + tier*0.10, 0)
			_hall_plant_stem(stems, foot, foot + Vector3(0, (start.y-foot.y)*0.7, 0), start, 0.005)
			_hall_plant_blade(leaves, start, direction, 0.21 + float(i%3)*0.032,
				0.105 + float(i%3)*0.023, 0.08 + tier*0.009, 0.065 + float(i%3)*0.018,
				Color(0.16 + float(i%3)*0.02, 0.34 + float(i%4)*0.025, 0.13 + float(i%3)*0.014))
	var shader := Shader.new()
	shader.code = _HALL_LEAF_SHADER
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = shader
	_hall_plant_finish_mesh(root, leaves, leaf_mat, "FeuillageCourbe", false)
	_hall_plant_finish_mesh(root, stems, _hall_plant_material(Color(0.31, 0.26, 0.14) if window_plant else Color(0.19, 0.32, 0.12), 0.8), "Tiges", true)
