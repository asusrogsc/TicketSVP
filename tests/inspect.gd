extends Node
## Chaque modèle assis / debout, vu de profil et de face.
func _ready() -> void:
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[-1]
	var root := Node3D.new()
	get_tree().root.add_child(root)
	get_tree().current_scene.queue_free()
	Build.environment(root, Color(0.4,0.5,0.7), Color(0.8,0.8,0.8), 1.0, 1.0)
	Build.box(root, Vector3(0.44, 0.08, 0.45), Vector3(0, 0.45, 0), Color(0.15, 0.25, 0.55))
	Build.box(root, Vector3(0.44, 0.55, 0.08), Vector3(0, 0.75, 0.24), Color(0.15, 0.25, 0.55))
	var cam := Camera3D.new()
	root.add_child(cam)
	var hs := {"tiph": 1.67, "marie_rose": 1.52}
	for name in ["tiph", "marie_rose", "tiph_chinese", "tiph_enfant"]:
		var v := Node3D.new(); root.add_child(v)
		var f := ModelFit.new("res://models/%s.glb" % name, v, hs.get(name, 0.0))
		print(name, " box ", f.box, " hip ", f.hip, " k ", f.k)
		for seated in [true, false]:
			f.set_seated(seated)
			for vw in [["side", Vector3(-2.6, 0.9, 0)], ["front", Vector3(0, 0.9, -2.6)]]:
				cam.position = vw[1]; cam.look_at(Vector3(0, 0.8, 0))
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, name, "assis" if seated else "debout", vw[0]])
		v.queue_free()
	get_tree().quit()
