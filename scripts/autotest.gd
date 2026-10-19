extends Node
## Test automatique (lancé seulement avec l'argument « -- --autotest <dossier> ») : parcourt le jeu et prend des captures.

var out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autotest")
	if i >= 0 and i + 1 < args.size():
		out = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("CAPTURE ", name)


func _run() -> void:
	await _frames(60)
	var hall := get_tree().current_scene
	hall.player.rotation_degrees.y = 60
	await _frames(5)
	await _shot("1_hall")
	hall._open_menu()
	await _frames(10)
	await _shot("2_planning")
	Game.start_line(Game.lines[0])
	await _frames(90)
	var bus := get_tree().current_scene
	bus.player.rotation_degrees.y = 180
	await _frames(5)
	await _shot("3_bus_depart")
	# contrôle du passager le plus proche
	var best: Passenger = null
	for p in bus.passengers:
		if best == null or p.position.distance_to(bus.player.position) < best.position.distance_to(bus.player.position):
			best = p
	bus.open_ticket(best)
	await _frames(15)
	await _shot("4_ticket")
	bus.ticket_ui._decide("amende" if best.data.truth == "fraude" else "valide")
	await _frames(20)
	await _shot("5_decision")
	await get_tree().create_timer(2.0).timeout
	print("ETAT ", bus.state, " score ", bus.stats.score)
	# accélère jusqu'au premier arrêt
	Engine.time_scale = 8.0
	while bus.state != "stop":
		await get_tree().process_frame
	Engine.time_scale = 1.0
	bus.player.rotation_degrees.y = -115
	bus.player.position = Vector3(-0.3, 0.05, -2.2)
	await get_tree().create_timer(3.5).timeout
	await _shot("6_arret")
	# fin du trajet en accéléré, avec un passager spécial forcé si possible
	Engine.time_scale = 12.0
	while get_tree().current_scene == bus:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	await _frames(30)
	await _shot("7_bilan")
	print("BILAN ", Game.last_result)
	get_tree().quit()
