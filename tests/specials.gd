extends Node
## Fait monter les personnages avec modèle 3D près du joueur et prend des captures.
var out := ""
func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
	print("CAPTURE ", n)

func _ready() -> void:
	var a := OS.get_cmdline_user_args(); out = a[a.find("--specialtest") + 1]
	await get_tree().create_timer(0.5).timeout
	Game.start_line(Game.lines[0])
	await get_tree().create_timer(1.0).timeout
	var bus := get_tree().current_scene
	var want := ["tiph", "tiph_enfant", "tiph_chinese", "marie_rose"]
	var seats_wanted := [1, 2, 4, 5]
	var made := []
	for sp in People.specials(bus.line):
		if sp.id in want:
			var si: int = seats_wanted[made.size()]
			if bus.seats[si].p != null:
				bus.passengers.erase(bus.seats[si].p); bus.seats[si].p.queue_free(); bus.seats[si].p = null
			made.append(bus._spawn(sp, si, true))
	for i in [0, 3, 6, 7]:
		if bus.seats[i].p is Passenger:
			bus.seats[i].p.visible = false
	bus.set_process(false)
	bus.player.set_physics_process(false)
	var cam: Camera3D = bus.player.camera
	for v in [["a", Vector3(0.0, 1.5, -2.2), Vector3(-0.5, 0.7, -3.4)], ["b", Vector3(0.0, 1.5, -2.2), Vector3(0.6, 0.7, -3.4)],
			["c", Vector3(0.0, 1.3, -5.0), Vector3(0.0, 0.8, -3.0)]]:
		cam.global_position = bus.to_global(v[1]); cam.look_at(bus.to_global(v[2]))
		await get_tree().create_timer(0.3).timeout
		await _shot("modele_" + v[0])
	# un passager qui monte (debout)
	made[0].set_seated(false)
	cam.global_position = bus.to_global(Vector3(0.0, 1.4, -1.0)); cam.look_at(bus.to_global(made[0].position + Vector3(0, 0.9, 0)))
	await get_tree().create_timer(0.3).timeout
	await _shot("modele_debout")
	get_tree().quit()
