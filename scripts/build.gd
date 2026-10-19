class_name Build
## Petits utilitaires pour construire les décors en code (boîtes, lumières, textes 3D).

static func mat(color: Color, rough := 0.8, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


## Boîte visible, avec collision si `solid`.
static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, solid := true, rough := 0.8) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat(color, rough)
	if not solid:
		mesh.position = pos
		parent.add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.add_child(mesh)
	parent.add_child(body)
	return body


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mesh.mesh = cm
	mesh.material_override = mat(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


static func label3d(parent: Node, text: String, pos: Vector3, size := 48, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 8
	l.position = pos
	parent.add_child(l)
	return l


static func light(parent: Node, pos: Vector3, color := Color(1, 0.95, 0.85), energy := 1.5, rng := 8.0) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.shadow_enabled = true
	parent.add_child(o)
	return o


static func environment(parent: Node, sky_top: Color, sky_horizon: Color, ambient := 0.6, sun_energy := 0.9) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = sky_horizon
	sm.ground_horizon_color = sky_horizon
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	if sun_energy > 0.0:
		parent.add_child(sun)
	else:
		sun.free()
