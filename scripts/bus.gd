extends Node3D
## Le bus : intérieur, décor qui défile, arrêts, montées / descentes, contrôles et score.

const CRUISE := 13.0          # m/s (~47 km/h)
const LEG_TIME := 30.0        # route par défaut entre deux arrêts (réglable par arrêt dans game.gd)
const BRAKE_TIME := 3.0
const STOP_TIME := 8.0        # arrêt par défaut, portes ouvertes (réglable par arrêt dans game.gd)
const WRAP_BACK := 80.0
const WRAP_LEN := 320.0
const DOOR_Z := 0.0           # porte du milieu (côté droit, +X)

var line: Dictionary
var rng := RandomNumberGenerator.new()
var player: Player
var hud: Hud
var world: Node3D             # tout ce qui défile dehors
var movers: Array[Node3D] = []
var seats: Array = []         # [{pos: Vector3, p: Passenger}]
var passengers: Array[Passenger] = []
var display: Label3D
var doors: Array[Node3D] = []
var ticket_ui: TicketUI

var state := "depart"
var state_t := 5.0
var speed := 0.0
var stop_index := 0           # arrêt où l'on se trouve / d'où l'on part
var special_stops: Array[int] = []
var specials_pool: Array = []
var stats := {"score": 0, "controles": 0, "justes": 0, "amendes": 0, "amendes_euros": 0,
	"erreurs_amende": 0, "fraudes_laissees": 0, "fraudeurs_partis": 0, "passagers": 0, "speciaux": []}


func _ready() -> void:
	rng.randomize()
	line = Game.current_line if not Game.current_line.is_empty() else Game.lines[0]
	Build.environment(self, Color(0.3, 0.55, 0.9), Color(0.8, 0.86, 0.95), 0.5, 0.85)
	world = Node3D.new()
	add_child(world)
	_build_city()
	_build_bus()
	hud = Hud.new()
	add_child(hud)
	player = Player.new()
	player.position = Vector3(0, 0.05, -3.6)
	player.hud = hud
	add_child(player)
	player.interacted.connect(_on_interact)
	# passagers du départ
	for i in 7:
		_spawn(People.random_passenger(line, rng), _free_seat(), true)
	specials_pool = People.specials(line)
	specials_pool.shuffle()
	# un ou deux personnages spéciaux par trajet, à des arrêts différents
	for k in (2 if rng.randf() < 0.5 else 1):
		special_stops.append(rng.randi_range(1, line.stops.size() - 2))
	state_t = stop_wait(0) if line.stops[0] is Dictionary and line.stops[0].has("arret") else 5.0
	hud.show_toast("%s %s — Départ de %s. Contrôle les titres avec [E] !" % [line.type, line.name, stop_name(0)], Color(0.8, 0.95, 1), 5.0)


# ------------------------------------------------------------------ décor extérieur

func _build_city() -> void:
	# chaussée fixe (très longue) sous le bus
	Build.box(self, Vector3(14, 0.1, 400), Vector3(0, -0.8, -100), Color(0.22, 0.22, 0.24), false)
	for side in [-1, 1]:
		Build.box(self, Vector3(4, 0.25, 400), Vector3(side * 9, -0.65, -100), Color(0.6, 0.6, 0.6), false)
		Build.box(self, Vector3(30, 0.1, 400), Vector3(side * 26, -0.75, -100), Color(0.35, 0.55, 0.3), false)
	var z := -240.0
	while z < WRAP_BACK:
		# marquage central
		_mover(Build.box(world, Vector3(0.15, 0.02, 3), Vector3(0, -0.74, z), Color(0.95, 0.95, 0.9), false))
		if int(z) % 24 == 0:
			for side in [-1, 1]:
				var pole := Node3D.new()
				pole.position = Vector3(side * 7.4, -0.55, z)
				world.add_child(pole)
				Build.cylinder(pole, 0.08, 6, Vector3(0, 3, 0), Color(0.3, 0.32, 0.35))
				Build.box(pole, Vector3(1.2, 0.12, 0.3), Vector3(-side * 0.5, 6, 0), Color(0.3, 0.32, 0.35), false)
				_mover(pole)
		z += 6.0
	z = -240.0
	while z < WRAP_BACK:
		for side in [-1, 1]:
			var w := rng.randf_range(8, 16)
			var h := rng.randf_range(6, 22)
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.35), rng.randf_range(0.55, 0.9))
			var b := Node3D.new()
			b.position = Vector3(side * rng.randf_range(16, 22), -0.6, z)
			world.add_child(b)
			Build.box(b, Vector3(10, h, w * 0.9), Vector3(0, h / 2, 0), col, false)
			# rangées de fenêtres
			var fy := 2.0
			while fy < h - 1:
				Build.box(b, Vector3(0.05, 1.0, w * 0.75), Vector3(-side * 5.02, fy, 0), Color(0.55, 0.7, 0.85), false)
				fy += 3.0
			_mover(b)
			if rng.randf() < 0.5:
				var tree := Node3D.new()
				tree.position = Vector3(side * 10.5, -0.55, z + w / 2)
				world.add_child(tree)
				Build.cylinder(tree, 0.15, 2, Vector3(0, 1, 0), Color(0.4, 0.28, 0.16))
				var leaves := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 1.2
				sm.height = 2.2
				leaves.mesh = sm
				leaves.material_override = Build.mat(Color(0.25, 0.55, 0.25))
				leaves.position.y = 2.6
				tree.add_child(leaves)
				_mover(tree)
		z += 16.0


func _mover(n: Node3D) -> void:
	movers.append(n)


func _spawn_shelter(at_z: float, stop_name: String) -> void:
	var s := Node3D.new()
	s.set_meta("once", true)
	s.position = Vector3(5.2, -0.55, at_z)
	world.add_child(s)
	Build.box(s, Vector3(1.4, 0.1, 4), Vector3(0.4, 2.5, 0), line.color, false)
	Build.box(s, Vector3(0.05, 2.4, 4), Vector3(1.1, 1.2, 0), Color(0.7, 0.85, 0.95, 0.4), false)
	Build.box(s, Vector3(0.5, 0.08, 2.5), Vector3(0.8, 0.5, 0), Color(0.4, 0.4, 0.45), false)
	Build.cylinder(s, 0.05, 2.8, Vector3(-0.2, 1.4, 2.2), Color(0.3, 0.3, 0.3))
	var sign := Build.label3d(s, "■ " + stop_name, Vector3(-0.2, 2.9, 2.2), 64, Color.WHITE)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mover(s)


# ------------------------------------------------------------------ intérieur du bus

func _build_bus() -> void:
	var L := 12.0; var W := 2.5; var H := 2.45
	var body: Color = line.color
	Build.box(self, Vector3(W, 0.2, L), Vector3(0, -0.1, 0), Color(0.35, 0.36, 0.38))          # plancher
	Build.box(self, Vector3(W, 0.1, L), Vector3(0, H + 0.05, 0), Color(0.88, 0.88, 0.86))     # plafond
	Build.box(self, Vector3(W, H, 0.1), Vector3(0, H / 2, L / 2), Color(0.72, 0.74, 0.77))                        # arrière
	# avant : pare-brise + tableau de bord
	Build.box(self, Vector3(W, 0.9, 0.3), Vector3(0, 0.45, -L / 2), Color(0.15, 0.15, 0.17))
	Build.box(self, Vector3(W, H - 0.9, 0.05), Vector3(0, 0.9 + (H - 0.9) / 2, -L / 2 - 0.1), Color(0.7, 0.85, 0.95, 0.15), true, 0.05)
	# côtés : soubassement, vitres, bandeau haut, montants
	for side in [-1, 1]:
		var x: float = side * W / 2
		Build.box(self, Vector3(0.1, 0.95, L), Vector3(x, 0.475, 0), Color(0.72, 0.74, 0.77))
		Build.box(self, Vector3(0.1, 0.45, L), Vector3(x, H - 0.225, 0), body.darkened(0.35))
		Build.box(self, Vector3(0.04, 1.05, L), Vector3(x, 1.475, 0), Color(0.75, 0.88, 0.97, 0.18), true, 0.05)
		var z := -L / 2 + 0.75
		while z < L / 2:
			Build.box(self, Vector3(0.12, 1.05, 0.1), Vector3(x, 1.475, z), Color(0.3, 0.32, 0.36), false)
			z += 1.5
	# portes (côté droit) : panneaux vitrés qui glissent
	for dz in [-4.9, DOOR_Z]:
		for k in [-1, 1]:
			var d := Build.box(self, Vector3(0.06, 2.0, 0.6), Vector3(W / 2 - 0.12, 1.0, dz + 0.3 * k), Color(0.3, 0.35, 0.4, 0.6), false)
			d.set_meta("closed_z", dz + 0.3 * k)
			d.set_meta("dir", k)
			doors.append(d)
		Build.box(self, Vector3(0.25, 1.1, 0.2), Vector3(W / 2 - 0.35, 0.55, dz - 0.85), Color(0.95, 0.75, 0.1), false)  # composteur
	# barres de maintien
	for z in [-3.0, -1.0, 1.5, 3.5]:
		for x in [-0.32, 0.32]:
			Build.cylinder(self, 0.025, H, Vector3(x, H / 2, z), Color(0.95, 0.8, 0.1))
	# sièges : 2 de chaque côté, sauf zones des portes
	var z := -3.6
	while z < 5.4:
		for x in [-1.0, -0.57, 0.57, 1.0]:
			if x > 0 and abs(z - DOOR_Z) < 0.9:
				continue
			Build.box(self, Vector3(0.44, 0.08, 0.45), Vector3(x, 0.45, z), Color(0.15, 0.25, 0.55))
			Build.box(self, Vector3(0.44, 0.55, 0.08), Vector3(x, 0.75, z + 0.24), Color(0.15, 0.25, 0.55))
			Build.box(self, Vector3(0.06, 0.45, 0.06), Vector3(x, 0.2, z), Color(0.3, 0.3, 0.3), false)
			seats.append({"pos": Vector3(x, 0, z - 0.02), "p": null})
		z += 1.0
	# chauffeur
	var drv_data := {"id": "driver", "special": false, "name": "Gérard (chauffeur)", "body": Color(0.2, 0.3, 0.5),
		"legs": Color(0.15, 0.15, 0.2), "skin": Color(0.9, 0.72, 0.6), "hair": Color(0.4, 0.4, 0.4), "greet": ""}
	var drv := Passenger.new()
	drv.setup(drv_data)
	drv.position = Vector3(-0.75, 0, -5.2)
	add_child(drv)
	drv.controlled = true
	Build.box(self, Vector3(0.5, 0.08, 0.5), Vector3(-0.75, 0.45, -5.2), Color(0.1, 0.1, 0.1), false)
	Build.cylinder(self, 0.2, 0.04, Vector3(-0.75, 1.05, -5.6), Color(0.1, 0.1, 0.1)).rotation_degrees.x = 60
	# afficheur de ligne
	Build.box(self, Vector3(1.6, 0.25, 0.08), Vector3(0.3, 2.2, -5.45), Color(0.05, 0.05, 0.05), false)
	display = Build.label3d(self, "", Vector3(0.3, 2.2, -5.4), 26, Color(1, 0.6, 0.1))
	display.pixel_size = 0.0025
	# éclairage intérieur
	for lz in [-3.5, 0, 3.5]:
		Build.light(self, Vector3(0, H - 0.1, lz), Color(0.95, 0.97, 1), 0.35, 5.0)


func _free_seat() -> int:
	var free := []
	for i in seats.size():
		if seats[i].p == null:
			free.append(i)
	return free[rng.randi() % free.size()] if free.size() > 0 else -1


func _spawn(data: Dictionary, seat: int, seated_now: bool) -> Passenger:
	if seat < 0:
		return null
	var p := Passenger.new()
	p.setup(data)
	seats[seat].p = p
	p.seat_index = seat
	add_child(p)
	passengers.append(p)
	stats.passagers += 1
	if data.special:
		stats.speciaux.append(data.name)
	if seated_now:
		p.position = seats[seat].pos
	else:
		p.position = Vector3(0.9, 0, DOOR_Z)
		p.set_seated(false)
		p.rotation_degrees.y = 90
		var target: Vector3 = seats[seat].pos
		var tw := create_tween()
		tw.tween_property(p, "position", Vector3(0, 0, DOOR_Z), 0.8)
		tw.tween_property(p, "rotation_degrees:y", 0.0 if target.z < DOOR_Z else 180.0, 0.2)
		tw.tween_property(p, "position", Vector3(0, 0, target.z), abs(target.z - DOOR_Z) / 2.0 + 0.2)
		tw.tween_property(p, "rotation_degrees:y", 0.0, 0.2)
		tw.tween_property(p, "position", target, 0.5)
		tw.tween_callback(p.set_seated.bind(true))
	return p


func _alight(p: Passenger) -> void:
	seats[p.seat_index].p = null
	passengers.erase(p)
	if not p.controlled and p.data.truth == "fraude":
		stats.fraudeurs_partis += 1
		stats.score -= 5
	p.set_seated(false)
	var tw := create_tween()
	tw.tween_property(p, "position", Vector3(0, 0, p.position.z), 0.5)
	tw.tween_property(p, "position", Vector3(0, 0, DOOR_Z), abs(p.position.z - DOOR_Z) / 2.0 + 0.2)
	tw.tween_property(p, "position", Vector3(1.6, 0, DOOR_Z), 0.7)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ déroulement du trajet

func _process(delta: float) -> void:
	state_t -= delta
	match state:
		"depart":
			speed = 0.0
			_set_doors(true)
			if state_t <= 0:
				_set_doors(false)
				_goto("accel", BRAKE_TIME)
		"accel":
			speed = CRUISE * (1.0 - state_t / BRAKE_TIME)
			if state_t <= 0:
				# le freinage fait aussi partie du trajet
				_goto("drive", max(stop_route(stop_index + 1) - BRAKE_TIME * 2.0, 1.0))
		"drive":
			speed = CRUISE
			if state_t <= 0:
				_goto("brake", BRAKE_TIME)
				# l'abri arrive pile devant la porte quand le bus s'arrête
				_spawn_shelter(DOOR_Z - CRUISE * BRAKE_TIME / 2.0, stop_name(stop_index + 1))
		"brake":
			speed = CRUISE * max(state_t, 0.0) / BRAKE_TIME
			if state_t <= 0:
				speed = 0.0
				stop_index += 1
				_arrive_at_stop()
		"stop":
			speed = 0.0
			if state_t <= 0:
				_set_doors(false)
				_goto("accel", BRAKE_TIME)
		"terminus":
			speed = 0.0
			if state_t <= 0 and state != "fin":
				state = "fin"
				_finish()
	# défilement du décor
	var dz := speed * delta
	for n in movers:
		if not is_instance_valid(n):
			continue
		n.position.z += dz
		if n.position.z > WRAP_BACK:
			if n.get_parent() == world and n.has_meta("once"):
				n.queue_free()
			else:
				n.position.z -= WRAP_LEN
	_update_texts()


## Arrêt n° i : accepte "Nom" ou {"nom": ..., "route": s, "arret": s}.
func stop_name(i: int) -> String:
	var st = line.stops[i]
	return st.get("nom", "?") if st is Dictionary else str(st)


func stop_route(i: int) -> float:
	var st = line.stops[i]
	return float(st.get("route", LEG_TIME)) if st is Dictionary else LEG_TIME


func stop_wait(i: int) -> float:
	var st = line.stops[i]
	return float(st.get("arret", STOP_TIME)) if st is Dictionary else STOP_TIME


func _goto(s: String, t: float) -> void:
	state = s
	state_t = t


func _arrive_at_stop() -> void:
	var name_: String = stop_name(stop_index)
	var last: bool = stop_index >= line.stops.size() - 1
	_set_doors(true)
	hud.show_toast("Arrêt : " + name_ + (" — Terminus !" if last else ""), Color(1, 0.9, 0.5), 3.0)
	if last:
		for p in passengers.duplicate():
			_alight(p)
		_goto("terminus", 4.0)
		return
	# descentes
	var seated := passengers.filter(func(p): return not p.data.special)
	seated.shuffle()
	for i in min(rng.randi_range(1, 2), seated.size()):
		_alight(seated[i])
	# montées
	var n := rng.randi_range(2, 4)
	for i in n:
		var d: Dictionary = People.random_passenger(line, rng)
		if i < special_stops.count(stop_index) and specials_pool.size() > 0:
			d = specials_pool.pop_back()
			hud.show_toast("Arrêt : %s — %s monte dans le bus ★" % [name_, d.name], Color(1, 0.8, 1), 4.0)
		var seat := _free_seat()
		if seat >= 0:
			var delay := 1.0 + i * 1.2
			get_tree().create_timer(delay).timeout.connect(_spawn.bind(d, seat, false))
			seats[seat].p = "réservé"   # remplacé au spawn
	_goto("stop", stop_wait(stop_index))


func _set_doors(open: bool) -> void:
	for d in doors:
		var tz: float = d.get_meta("closed_z") + (0.55 * d.get_meta("dir") if open else 0.0)
		if abs(d.position.z - tz) > 0.01:
			create_tween().tween_property(d, "position:z", tz, 0.6)


func _update_texts() -> void:
	var next_i: int = min(stop_index + 1, line.stops.size() - 1)
	var nxt: String = stop_name(next_i)
	var where := ""
	match state:
		"depart": where = "Départ dans %d s" % ceil(state_t)
		"stop": where = "À l'arrêt : " + stop_name(stop_index)
		"terminus", "fin": where = "Terminus : " + stop_name(line.stops.size() - 1)
		_: where = "Prochain arrêt : " + nxt
	display.text = "%s  %s → %s\n%s" % [line.name, line.from, line.to, where]
	var ctrl := passengers.filter(func(p): return p.controlled).size()
	hud.set_info("%s %s   |   %s   |   Contrôlés à bord : %d / %d   |   Score : %d   |   Amendes : %d €" % [
		line.type, line.name, where, ctrl, passengers.size(), stats.score, stats.amendes_euros])


# ------------------------------------------------------------------ contrôles

func _on_interact(t: Node) -> void:
	if not (t is Passenger) or ticket_ui:
		return
	var p: Passenger = t
	if p.data.get("id", "") == "driver":
		hud.show_toast("Gérard : « Bonne tournée chef ! Fais gaffe aux resquilleurs. »", Color(0.85, 0.9, 1))
		return
	if p.controlled:
		hud.show_toast(p.data.name + " a déjà été contrôlé.", Color(0.8, 0.8, 0.8), 1.5)
		return
	open_ticket(p)


func open_ticket(p: Passenger) -> void:
	ticket_ui = TicketUI.new()
	add_child(ticket_ui)
	ticket_ui.open(p, line)
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ticket_ui.decided.connect(_on_decided)
	ticket_ui.closed.connect(_on_ticket_closed)


func _on_ticket_closed() -> void:
	ticket_ui = null
	player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_decided(p: Passenger, dec: String) -> void:
	var fraud: bool = p.data.truth == "fraude"
	var correct := (dec == "amende") == fraud
	stats.controles += 1
	if correct:
		stats.justes += 1
	if dec == "amende":
		if fraud:
			stats.score += 10
			stats.amendes += 1
			stats.amendes_euros += 50
			hud.show_toast("Amende justifiée : %s (+10)" % p.data.get("reason", "fraude"), Color(0.5, 1, 0.5))
		else:
			stats.erreurs_amende += 1
			stats.score -= 25 if p.data.get("id", "") == "agent" else 15
			hud.show_toast("Erreur : son titre était valide ! (-15)", Color(1, 0.45, 0.4))
	else:
		if fraud:
			stats.fraudes_laissees += 1
			stats.score -= 10
			hud.show_toast("Raté : %s (-10)" % p.data.get("reason", "fraude"), Color(1, 0.45, 0.4))
		else:
			stats.score += 5
			hud.show_toast("Titre valide (+5)", Color(0.5, 1, 0.5), 1.5)
	p.set_result(dec, correct)


func _finish() -> void:
	stats.line = "%s %s : %s → %s" % [line.type, line.name, line.from, line.to]
	Game.finish_trip(stats)
