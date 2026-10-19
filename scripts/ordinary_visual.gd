extends RefCounted
## Silhouette procédurale des passagers ordinaires. Aucun lien avec le billet.

static func ellipsoid(root: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere
	mesh.scale = size
	mesh.position = pos
	mesh.material_override = Build.mat(color, 0.86)
	root.add_child(mesh)
	return mesh

static func limb(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(a.distance_to(b) + radius * 2.0, radius * 2.0)
	capsule.radial_segments = 12
	capsule.rings = 4
	mesh.mesh = capsule
	mesh.position = (a + b) * 0.5
	mesh.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	mesh.material_override = Build.mat(color, 0.9)
	root.add_child(mesh)

static func build(parent: Node3D, data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "OrdinaryPassengerVisual"
	parent.add_child(root)
	# Seed uses only appearance and name, never ticket validity or reactions.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data.get("name", "")) + str(data.get("body", Color.GRAY)) + str(data.get("hair", Color.BLACK)))
	var skin: Color = data.get("skin", Color(0.8, 0.6, 0.45))
	var hair: Color = data.get("hair", Color(0.15, 0.1, 0.07))
	var cloth: Color = data.get("body", Color(0.2, 0.3, 0.4))
	cloth = cloth.lerp(Color(0.32, 0.34, 0.35), 0.25)
	var trousers: Color = data.get("legs", Color(0.18, 0.2, 0.24))
	var width := rng.randf_range(0.95, 1.05)
	root.scale = Vector3(width, 1.0, 1.0)
	root.set_meta("skin", skin)
	root.set_meta("cloth", cloth)
	root.set_meta("trousers", trousers)
	var upper := Node3D.new()
	upper.name = "Upper"
	root.add_child(upper)
	ellipsoid(upper, Vector3(0, 0.59, 0.015), Vector3(0.31, 0.20, 0.24), trousers)
	ellipsoid(upper, Vector3(0, 0.91, 0.015), Vector3(0.37, 0.61, 0.25), cloth)
	limb(upper, Vector3(0, 1.15, 0), Vector3(0, 1.25, 0), 0.058, skin)
	ellipsoid(upper, Vector3(0, 1.39, -0.005), Vector3(0.245, 0.31, 0.235), skin)
	# Coiffures courtes ou mi-longues, positionnées pour dégager le visage.
	ellipsoid(upper, Vector3(0, 1.49, 0.025), Vector3(0.258, 0.155, 0.225), hair)
	if rng.randf() < 0.35:
		ellipsoid(upper, Vector3(0, 1.37, 0.091), Vector3(0.245, 0.29, 0.105), hair)
	else:
		ellipsoid(upper, Vector3(0, 1.43, 0.082), Vector3(0.245, 0.18, 0.12), hair)
	for side in [-1.0, 1.0]:
		ellipsoid(upper, Vector3(side * 0.12, 1.38, 0), Vector3(0.035, 0.066, 0.038), skin)
		ellipsoid(upper, Vector3(side * 0.047, 1.415, -0.112), Vector3(0.029, 0.016, 0.009), Color(0.79, 0.77, 0.72))
		ellipsoid(upper, Vector3(side * 0.047, 1.415, -0.117), Vector3(0.012, 0.012, 0.006), Color(0.10, 0.12, 0.12))
		limb(upper, Vector3(side * 0.031, 1.443, -0.108), Vector3(side * 0.065, 1.441, -0.101), 0.006, hair)
	ellipsoid(upper, Vector3(0, 1.38, -0.119), Vector3(0.032, 0.055, 0.037), skin.darkened(0.025))
	ellipsoid(upper, Vector3(0, 1.333, -0.108), Vector3(0.047, 0.008, 0.009), skin.darkened(0.30))
	# Col et ouverture de veste discrets.
	for side in [-1.0, 1.0]:
		limb(upper, Vector3(side * 0.045, 1.19, -0.04), Vector3(side * 0.085, 1.10, -0.09), 0.018, cloth.lightened(0.15))
	if rng.randf() < 0.55:
		limb(upper, Vector3(0, 1.09, -0.105), Vector3(0, 0.70, -0.105), 0.004, cloth.darkened(0.35))
	var pose := Node3D.new()
	pose.name = "Pose"
	root.add_child(pose)
	set_pose(root, true)
	return root

static func set_pose(root: Node3D, seated: bool) -> void:
	var upper := root.get_node("Upper") as Node3D
	var pose := root.get_node("Pose") as Node3D
	for child in pose.get_children():
		pose.remove_child(child)
		child.queue_free()
	var skin: Color = root.get_meta("skin")
	var cloth: Color = root.get_meta("cloth")
	var trousers: Color = root.get_meta("trousers")
	var lift := 0.0 if seated else 0.30
	upper.position.y = lift
	for side in [-1.0, 1.0]:
		var x: float = side * 0.085
		var hip := Vector3(x, 0.54 + lift, 0.01)
		var knee := Vector3(x, 0.47, -0.34) if seated else Vector3(x, 0.46, -0.015)
		var ankle := Vector3(x, 0.10, -0.35) if seated else Vector3(x, 0.10, -0.015)
		limb(pose, hip, knee, 0.074, trousers)
		limb(pose, knee, ankle, 0.052, trousers)
		ellipsoid(pose, ankle + Vector3(0, -0.036, -0.055), Vector3(0.125, 0.10, 0.25), Color(0.09, 0.085, 0.08))
		var shoulder := Vector3(side * 0.17, 1.10 + lift, 0)
		var elbow := Vector3(side * 0.23, 0.80 + lift, -0.025)
		var wrist := Vector3(side * 0.13, 0.61, -0.26) if seated else Vector3(side * 0.22, 0.92, -0.045)
		limb(pose, shoulder, elbow, 0.057, cloth)
		limb(pose, elbow, wrist, 0.045, cloth)
		ellipsoid(pose, wrist + Vector3(0, -0.015, -0.015), Vector3(0.065, 0.095, 0.042), skin)
