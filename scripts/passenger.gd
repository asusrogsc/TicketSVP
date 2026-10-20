class_name Passenger
extends StaticBody3D
## Un passager : silhouette simple (ou modèle res://models/<model>.glb s'il existe), assis ou debout.

var data: Dictionary
var controlled := false
var decision := ""           # "valide" / "amende"
var seat_index := -1
var mark: Label3D
var name_tag: Label3D
var visual: Node3D
var ordinary_visual: Node3D
var ordinary_seated := true
var base_y := 0.0           # remonte les petits gabarits pour qu'ils restent sur le siège
var fit: ModelFit          # modèle .glb (s'il existe dans res://models/)


func setup(d: Dictionary) -> void:
	data = d


func _ready() -> void:
	# couche 2 : visé par le rayon de contrôle, mais ne bloque pas le joueur
	collision_layer = 2
	collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.3
	col.shape = cap
	col.position.y = 0.75
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	var model_path := "res://models/%s.glb" % data.get("model", "")
	if data.has("model") and ResourceLoader.exists(model_path):
		fit = ModelFit.new(model_path, visual, float(data.get("model_height", 0.0)))
	else:
		_build_figure()
	name_tag = Build.label3d(self, data.name, Vector3(0, 1.62, 0), 30, Color(1, 0.95, 0.6) if data.special else Color.WHITE)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.visible = false
	mark = Build.label3d(self, "★" if data.special else "", Vector3(0, 1.75, 0), 48, Color(1, 0.85, 0.3))
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	set_seated(true)


## Silhouette assise : jambes, buste, tête, cheveux (+ détails des personnages spéciaux)
func _build_figure() -> void:
	if not data.get("special", false) and str(data.get("id", "")) != "driver":
		ordinary_visual = preload("res://scripts/ordinary_visual.gd").build(visual, data)
		return
	var s: float = data.get("scale", 0.9 if data.get("small", false) else 1.0)
	base_y = 0.5 * (1.0 - s)
	if data.get("cactus", false):
		var body := Build.cylinder(visual, 0.2, 1.1, Vector3(0, 0.95, 0), data.body)
		for side in [-1, 1]:
			var arm := Build.cylinder(visual, 0.07, 0.4, Vector3(0.3 * side, 1.15 + 0.15 * side, 0), data.body)
			arm.rotation_degrees.z = 70 * side
		Build.box(visual, Vector3(0.05, 0.05, 0.02), Vector3(-0.07, 1.25, -0.2), Color.BLACK, false)
		Build.box(visual, Vector3(0.05, 0.05, 0.02), Vector3(0.07, 1.25, -0.2), Color.BLACK, false)
		Build.box(visual, Vector3(0.04, 0.12, 0.02), Vector3(0, 1.08, -0.2), Color.BLACK, false)
		return
	Build.box(visual, Vector3(0.36, 0.16, 0.5) * s, Vector3(0, 0.5, -0.2), data.legs, false)     # cuisses
	Build.box(visual, Vector3(0.34, 0.48, 0.14) * s, Vector3(0, 0.24, -0.42), data.legs, false)  # tibias
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.2 * s
	tm.height = 0.7 * s
	torso.mesh = tm
	torso.material_override = Build.mat(data.body)
	torso.position = Vector3(0, 0.9 * s, 0)
	visual.add_child(torso)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13 * s
	hm.height = 0.27 * s
	head.mesh = hm
	head.material_override = Build.mat(data.skin)
	head.position = Vector3(0, 1.38 * s, 0)
	visual.add_child(head)
	var hair := MeshInstance3D.new()
	var hr := SphereMesh.new()
	hr.radius = 0.14 * s
	hr.height = 0.2 * s
	hair.mesh = hr
	hair.material_override = Build.mat(data.hair)
	hair.position = Vector3(0, 1.44 * s, 0.03)
	visual.add_child(hair)
	if data.get("twintails", false):
		for side in [-1, 1]:
			var tail := MeshInstance3D.new()
			var tc := CapsuleMesh.new()
			tc.radius = 0.05
			tc.height = 0.45
			tail.mesh = tc
			tail.material_override = Build.mat(data.hair)
			tail.position = Vector3(0.17 * side, 1.3 * s, 0.05)
			tail.rotation_degrees.z = 15 * side
			visual.add_child(tail)
		Build.box(visual, Vector3(0.36, 0.05, 0.05), Vector3(0, 1.52 * s, 0.0), Color(0.95, 0.4, 0.6), false)
	if data.get("long_hair", false):   # cheveux longs dans le dos
		Build.box(visual, Vector3(0.26, 0.55, 0.06) * s, Vector3(0, 1.2 * s, 0.13 * s), data.hair, false)
	if data.get("braid", false):       # tresse
		var br := Build.cylinder(visual, 0.04 * s, 0.5 * s, Vector3(0, 1.15 * s, 0.16 * s), data.hair)
		Build.box(visual, Vector3(0.09, 0.06, 0.09) * s, Vector3(0, 0.88 * s, 0.16 * s), Color(0.9, 0.85, 0.3), false)
	if data.get("hat", false):         # chapeau de cow-girl
		Build.cylinder(visual, 0.24 * s, 0.03 * s, Vector3(0, 1.48 * s, 0), Color(0.85, 0.72, 0.45))
		Build.cylinder(visual, 0.13 * s, 0.14 * s, Vector3(0, 1.55 * s, 0), Color(0.85, 0.72, 0.45))
	if data.get("gloves", false):      # gants de combat
		for side in [-1, 1]:
			Build.box(visual, Vector3(0.09, 0.09, 0.12) * s, Vector3(0.2 * side * s, 0.62 * s, -0.25 * s), Color(0.15, 0.12, 0.1), false)
	if data.get("sunglasses", false):
		Build.box(visual, Vector3(0.24, 0.05, 0.03), Vector3(0, 1.4, -0.12), Color.BLACK, false)
	# yeux (le passager regarde vers -Z)
	for side in [-1, 1]:
		Build.box(visual, Vector3(0.03, 0.03, 0.01), Vector3(0.045 * side * s, 1.4 * s, -0.125 * s), Color(0.05, 0.05, 0.05), false)


func set_seated(seated: bool) -> void:
	if ordinary_visual != null:
		if ordinary_seated != seated:
			preload("res://scripts/ordinary_visual.gd").set_pose(ordinary_visual, seated)
			ordinary_seated = seated
		visual.position.y = 0.0
		mark.position.y = 1.75 if seated else 2.05
		name_tag.position.y = 1.62 if seated else 1.92
		return
	# debout : on relève la silhouette pour que les jambes ne flottent pas
	if fit:
		fit.set_seated(seated)
		visual.position.y = 0.0
		var top: float = fit.box.end.y * fit.k
		if seated:
			top = ModelFit.SEAT_HIP.y + (fit.box.end.y - fit.hip.y) * fit.k
		mark.position.y = top + 0.15
		name_tag.position.y = top + 0.05
		return
	visual.position.y = base_y + (0.0 if seated else 0.25)


func interact_label() -> String:
	if has_meta("waiting"):          # sur le quai de la gare : on discute, pas de contrôle
		return "Parler à %s" % data.name
	if controlled:
		return "%s — déjà contrôlé" % data.name
	return "Contrôler %s" % ("le titre de " + data.name if data.special else "ce passager")


func set_result(dec: String, correct: bool) -> void:
	controlled = true
	decision = dec
	name_tag.visible = true
	mark.text = "✔" if dec == "valide" else "€"
	mark.modulate = Color(0.3, 1, 0.4) if correct else Color(1, 0.35, 0.3)
