extends RefCounted
## Décor uniquement : aucune modification du trafic ou des passagers.

static func detail_box(root: Node3D, size: Vector3, pos: Vector3, color: Color, rough := 0.65) -> MeshInstance3D:
	return Build.box(root, size, pos, color, false, rough) as MeshInstance3D

static func rod(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var mesh := Build.cylinder(root, radius, a.distance_to(b), (a + b) * 0.5, color)
	mesh.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	mesh.material_override = Build.mat(color, 0.32)

static func seat(root: Node3D, x: float, z: float) -> void:
	var shell := Color(0.19, 0.23, 0.27)
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://shaders/bus_surface.gdshader")
	fabric.set_shader_parameter("base_color", Color(0.13, 0.29, 0.39))
	fabric.set_shader_parameter("fabric", true)
	# Les deux volumes porteurs conservent exactement leurs collisions d'origine.
	Build.box(root, Vector3(0.44, 0.08, 0.45), Vector3(x, 0.45, z), shell)
	Build.box(root, Vector3(0.44, 0.55, 0.08), Vector3(x, 0.75, z + 0.24), shell)
	var cushion := detail_box(root, Vector3(0.385, 0.025, 0.385), Vector3(x, 0.502, z - 0.005), Color.WHITE)
	cushion.material_override = fabric
	var back := detail_box(root, Vector3(0.365, 0.43, 0.018), Vector3(x, 0.77, z + 0.189), Color.WHITE)
	back.material_override = fabric
	rod(root, Vector3(x, 0.02, z), Vector3(x, 0.40, z), 0.027, shell)
	rod(root, Vector3(x - 0.14, 0.96, z + 0.24), Vector3(x + 0.14, 0.96, z + 0.24), 0.019, Color(0.9, 0.68, 0.13))
	# Petite étiquette au dos, sans texte flottant.
	detail_box(root, Vector3(0.08, 0.035, 0.003), Vector3(x, 0.91, z + 0.282), Color(0.78, 0.8, 0.77))

static func build(bus: Node3D, line: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "BusVisualDetails"
	bus.add_child(root)
	var dark := Color(0.12, 0.15, 0.18)
	var metal := Color(0.43, 0.48, 0.50)
	var ivory := Color(0.78, 0.8, 0.78)
	var yellow := Color(0.94, 0.70, 0.12)
	var paint: Color = line.color
	# Revêtement antidérapant : texture procédurale, sans image externe.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 11.9)
	floor_mesh.mesh = plane
	floor_mesh.position.y = 0.001
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = preload("res://shaders/bus_surface.gdshader")
	floor_mat.set_shader_parameter("base_color", Color(0.27, 0.29, 0.29))
	floor_mesh.material_override = floor_mat
	root.add_child(floor_mesh)
	for side in [-1.0, 1.0]:
		# Seuils, joints de vitrage et habillage extérieur.
		detail_box(root, Vector3(0.025, 0.065, 11.9), Vector3(side * 1.185, 0.07, 0), dark)
		detail_box(root, Vector3(0.025, 0.055, 11.95), Vector3(side * 1.19, 0.94, 0), dark)
		detail_box(root, Vector3(0.025, 0.045, 11.95), Vector3(side * 1.19, 2.0, 0), dark)
		detail_box(root, Vector3(0.025, 0.66, 11.9), Vector3(side * 1.31, 0.47, 0), ivory, 0.35)
		detail_box(root, Vector3(0.028, 0.15, 11.9), Vector3(side * 1.33, 0.35, 0), paint, 0.32)
		# Main courante longitudinale et supports au plafond.
		rod(root, Vector3(side * 0.48, 2.14, -4.1), Vector3(side * 0.48, 2.14, 5.35), 0.024, yellow)
		for z in [-3.0, -1.0, 1.5, 3.5]:
			rod(root, Vector3(side * 0.48, 2.14, z), Vector3(side * 0.48, 2.42, z), 0.014, metal)
			# Poignée suspendue : bride courte et anneau.
			rod(root, Vector3(side * 0.48, 2.14, z + 0.35), Vector3(side * 0.48, 1.99, z + 0.35), 0.012, dark)
			var handle := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = 0.055
			ring.outer_radius = 0.072
			ring.rings = 16
			ring.ring_segments = 8
			handle.mesh = ring
			handle.material_override = Build.mat(yellow, 0.5)
			handle.position = Vector3(side * 0.48, 1.93, z + 0.35)
			handle.rotation_degrees.x = 90
			root.add_child(handle)
		# Habillage des passages de roues, à l'extérieur uniquement.
		for z in [-3.9, 3.7]:
			var tire := Build.cylinder(root, 0.46, 0.22, Vector3(side * 1.29, -0.27, z), Color(0.035, 0.04, 0.045))
			tire.rotation_degrees.z = 90
			var hub := Build.cylinder(root, 0.25, 0.235, Vector3(side * 1.30, -0.27, z), metal)
			hub.rotation_degrees.z = 90
		# Boîtiers de rétroviseur.
		rod(root, Vector3(side * 1.22, 1.95, -5.6), Vector3(side * 1.57, 1.95, -5.8), 0.023, dark)
		detail_box(root, Vector3(0.16, 0.34, 0.09), Vector3(side * 1.57, 1.79, -5.8), dark)
		detail_box(root, Vector3(0.13, 0.29, 0.012), Vector3(side * 1.57, 1.79, -5.748), Color(0.54, 0.66, 0.72), 0.12)
	# Luminaires visibles : matériaux émissifs, sans lumières supplémentaires.
	for x in [-0.76, 0.76]:
		for z in [-3.5, 0.0, 3.5]:
			detail_box(root, Vector3(0.16, 0.035, 1.65), Vector3(x, 2.375, z), dark)
			var diffuser := detail_box(root, Vector3(0.12, 0.012, 1.57), Vector3(x, 2.35, z), Color.WHITE)
			diffuser.material_override = Build.mat(Color(0.92, 0.96, 1.0), 0.5, 1.2)
	# Aérations du plafond.
	for z in [-2.0, 2.5]:
		detail_box(root, Vector3(0.5, 0.025, 0.3), Vector3(0, 2.38, z), ivory)
		for i in range(7):
			detail_box(root, Vector3(0.38, 0.008, 0.012), Vector3(0, 2.363, z - 0.105 + i * 0.035), dark)
	# Marquages au sol près des portes et boutons d'arrêt.
	for z in [-4.9, 0.0]:
		for edge in [-0.58, 0.58]:
			detail_box(root, Vector3(0.64, 0.003, 0.025), Vector3(0.85, 0.003, z + edge), yellow)
		detail_box(root, Vector3(0.025, 0.003, 1.16), Vector3(0.53, 0.003, z), yellow)
		var button := detail_box(root, Vector3(0.06, 0.10, 0.085), Vector3(1.16, 1.23, z - 0.77), Color(0.7, 0.1, 0.07))
		button.name = "StopButtonDecor"
	# Cadres ajoutés aux panneaux mobiles : suivent leur animation existante.
	for door in bus.get("doors"):
		for offset in [-0.285, 0.285]:
			detail_box(door, Vector3(0.075, 2.0, 0.025), Vector3(0, 0, offset), dark)
		for y in [-0.96, 0.96, -0.18]:
			detail_box(door, Vector3(0.075, 0.035, 0.58), Vector3(0, y, 0), dark)
	# Poste chauffeur, sans collision pour ne pas bloquer les interactions.
	detail_box(root, Vector3(0.75, 0.16, 0.42), Vector3(-0.72, 0.93, -5.7), dark)
	var screen := detail_box(root, Vector3(0.29, 0.12, 0.014), Vector3(-0.72, 1.03, -5.477), Color(0.13, 0.36, 0.39))
	screen.material_override = Build.mat(Color(0.15, 0.42, 0.46), 0.4, 0.35)
	for i in range(5):
		detail_box(root, Vector3(0.032, 0.025, 0.012), Vector3(-0.96 + i * 0.10, 0.94, -5.477), yellow if i == 0 else metal)
	# Face avant et arrière : pare-chocs, optiques, girouette extérieure.
	for z in [-6.18, 6.08]:
		detail_box(root, Vector3(2.35, 0.14, 0.10), Vector3(0, 0.12, z), dark)
		for x in [-0.92, 0.92]:
			var lamp := detail_box(root, Vector3(0.24, 0.13, 0.035), Vector3(x, 0.45, z), Color.WHITE)
			lamp.material_override = Build.mat(Color(1.0, 0.93, 0.78) if z < 0 else Color(0.85, 0.08, 0.045), 0.25, 0.5)
	detail_box(root, Vector3(1.9, 0.27, 0.035), Vector3(0, 2.17, -6.135), dark)
	var destination := Build.label3d(root, str(line.get("name", "")) + "  " + str(line.get("to", "")), Vector3(0, 2.17, -6.16), 27, Color(1, 0.66, 0.14))
	destination.rotation_degrees.y = 180
	destination.pixel_size = 0.0016
	destination.outline_size = 0
