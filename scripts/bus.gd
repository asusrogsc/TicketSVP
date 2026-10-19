extends Node3D
## Le bus : intérieur, décor qui défile, arrêts, montées / descentes, contrôles et score.

const CRUISE := 13.0          # m/s (~47 km/h)
const LEG_TIME := 30.0        # route par défaut entre deux arrêts (réglable par arrêt dans game.gd)
const BRAKE_TIME := 3.0
const STOP_TIME := 8.0        # arrêt par défaut, portes ouvertes (réglable par arrêt dans game.gd)
const WRAP_BACK := 80.0
const WRAP_LEN := 320.0
const DOOR_Z := 0.0           # porte du milieu (côté droit, +X)
const SPECIALS_MIN := 2       # personnages spéciaux par trajet (minimum)
const SPECIALS_MAX := 6       # personnages spéciaux par trajet (maximum)

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

var _started := false

# Pépé Raymond tape la discute avec son voisin
const CHAT_INTERVAL := 3.0
const OLDMAN_LINES := [
	"De mon temps, le ticket coûtait 3 francs !",
	"Vous savez, j'ai conduit cette ligne pendant 30 ans...",
	"Ils ont encore changé les horaires, hein ?",
	"Mon genou annonce de la pluie pour demain.",
	"Avant, il y avait un poinçonneur. Un vrai !",
	"Le chauffeur, là, Gérard ? Je l'ai connu tout petit.",
	"Vous savez pourquoi on dit « composter » ? Moi non plus.",
]
const PARTNER_LINES := {
	"pampa": ["...........!", "...♪", "(agite ses bras)"],
	"agent": ["Intéressant. Je note.", "Hmm. Pour mon rapport.", "Continuez, monsieur."],
	"mamie": ["Oh Raymond, tu radotes !", "C'est vrai qu'avant c'était mieux...", "Tu as pris tes cachets ?"],
	"touriste": ["Sorry, I don't understand... but yes!", "Oh, very interesting!", "Ah, French history!"],
	"_": ["Ah bon ?", "Hmm hmm...", "Vraiment ?", "(sourit poliment)", "Je descends bientôt, hein...", "Passionnant..."],
}
var _chat_old: Passenger = null
var _chat_partner: Passenger = null
var _chat_t := 0.0
var _chat_turn := 0
var _chat_old_label: Label3D = null
var _chat_partner_label: Label3D = null


# ------------------------------------------------------------------ démarrage

func _ready() -> void:
	set_process(false)
	rng.randomize()

	# la ligne choisie dans le hall (Game.start_line) ; ligne 1 si on lance bus.tscn directement (F6)
	line = Game.current_line
	if line.is_empty() or line.get("stops", []).is_empty():
		line = Game.lines[0]

	_create_player_and_hud()
	start()


## Crée le joueur (et donc sa caméra) et le HUD s'ils ne sont pas déjà dans la scène.
func _create_player_and_hud() -> void:
	# joueur : réutilise celui de bus.tscn s'il existe, sinon en crée un
	if player == null:
		player = _find_child_of_type(self, "Player") as Player
	if player == null:
		player = Player.new()
		add_child(player)
		player.position = Vector3(0, 0, 2.0)   # debout dans l'allée, derrière la porte du milieu
	# touche [E] -> _on_interact (le nom du signal dépend de player.gd)
	for sig in ["interact", "interacted", "interaction", "interact_pressed", "target_interacted"]:
		if player.has_signal(sig):
			if not player.is_connected(sig, _on_interact):
				player.connect(sig, _on_interact)
			break

	# HUD : réutilise celui de bus.tscn s'il existe, sinon en crée un
	if hud == null:
		hud = _find_child_of_type(self, "Hud") as Hud
	if hud == null:
		hud = Hud.new()
		add_child(hud)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _find_child_of_type(root: Node, type_name: String) -> Node:
	for c in root.get_children():
		var scr = c.get_script()
		if scr and scr.get_global_name() == type_name:
			return c
		var found := _find_child_of_type(c, type_name)
		if found:
			return found
	return null


func start() -> void:
	if _started:
		return
	if line.is_empty() or not line.has("stops"):
		push_error("bus.gd : 'line' est vide ou sans 'stops'.")
		return
	if hud == null:
		push_error("bus.gd : 'hud' est vide.")
		return
	_started = true

	# construction
	world = Node3D.new()
	add_child(world)
	_build_bus()
	_build_city()

	# personnages spéciaux, ordre aléatoire
	specials_pool = People.specials(line)
	specials_pool.shuffle()

	# personnages spéciaux du trajet : SPECIALS_MIN à SPECIALS_MAX, répartis sur les arrêts intermédiaires
	special_stops.clear()
	if line.stops.size() > 2:
		var count: int = mini(rng.randi_range(SPECIALS_MIN, SPECIALS_MAX), specials_pool.size())
		for k in count:
			special_stops.append(rng.randi_range(1, line.stops.size() - 2))
	print("Spéciaux prévus aux arrêts : ", special_stops)

	# passagers du départ
	for i in 7:
		_spawn(People.random_passenger(line, rng), _free_seat(), true)

	state_t = stop_wait(0) if line.stops[0] is Dictionary and line.stops[0].has("arret") else 5.0
	hud.show_toast("%s %s — Départ de %s. Contrôle les titres avec [E] !" % [line.type, line.name, stop_name(0)], Color(0.8, 0.95, 1), 5.0)
	set_process(true)


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


func _spawn_shelter(at_z: float, label_text: String) -> void:
	var s := Node3D.new()
	s.set_meta("once", true)
	s.position = Vector3(5.2, -0.55, at_z)
	world.add_child(s)
	Build.box(s, Vector3(1.4, 0.1, 4), Vector3(0.4, 2.5, 0), line.color, false)
	Build.box(s, Vector3(0.05, 2.4, 4), Vector3(1.1, 1.2, 0), Color(0.7, 0.85, 0.95, 0.4), false)
	Build.box(s, Vector3(0.5, 0.08, 2.5), Vector3(0.8, 0.5, 0), Color(0.4, 0.4, 0.45), false)
	Build.cylinder(s, 0.05, 2.8, Vector3(-0.2, 1.4, 2.2), Color(0.3, 0.3, 0.3))
	var sign_label := Build.label3d(s, "■ " + label_text, Vector3(-0.2, 2.9, 2.2), 64, Color.WHITE)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mover(s)


# ------------------------------------------------------------------ intérieur du bus

func _build_bus() -> void:
	var L := 12.0; var W := 2.5; var H := 2.45
	var body: Color = line.color
	Build.box(self, Vector3(W, 0.2, L), Vector3(0, -0.1, 0), Color(0.35, 0.36, 0.38))          # plancher
	Build.box(self, Vector3(W, 0.1, L), Vector3(0, H + 0.05, 0), Color(0.88, 0.88, 0.86))     # plafond
	Build.box(self, Vector3(W, H, 0.1), Vector3(0, H / 2, L / 2), Color(0.72, 0.74, 0.77))    # arrière
	# avant : pare-brise + tableau de bord
	Build.box(self, Vector3(W, 0.9, 0.3), Vector3(0, 0.45, -L / 2), Color(0.15, 0.15, 0.17))
	Build.box(self, Vector3(W, H - 0.9, 0.05), Vector3(0, 0.9 + (H - 0.9) / 2, -L / 2 - 0.1), Color(0.7, 0.85, 0.95, 0.15), true, 0.05)
	# côtés : soubassement, vitres, bandeau haut, montants
	for side in [-1, 1]:
		var x: float = side * W / 2
		Build.box(self, Vector3(0.1, 0.95, L), Vector3(x, 0.475, 0), Color(0.72, 0.74, 0.77))
		Build.box(self, Vector3(0.1, 0.45, L), Vector3(x, H - 0.225, 0), body.darkened(0.35))
		Build.box(self, Vector3(0.04, 1.05, L), Vector3(x, 1.475, 0), Color(0.75, 0.88, 0.97, 0.18), true, 0.05)
		var pz := -L / 2 + 0.75
		while pz < L / 2:
			Build.box(self, Vector3(0.12, 1.05, 0.1), Vector3(x, 1.475, pz), Color(0.3, 0.32, 0.36), false)
			pz += 1.5
	# portes (côté droit) : panneaux vitrés qui glissent
	for dz in [-4.9, DOOR_Z]:
		for k in [-1, 1]:
			var d := Build.box(self, Vector3(0.06, 2.0, 0.6), Vector3(W / 2 - 0.12, 1.0, dz + 0.3 * k), Color(0.3, 0.35, 0.4, 0.6), false)
			d.set_meta("closed_z", dz + 0.3 * k)
			d.set_meta("dir", k)
			doors.append(d)
		Build.box(self, Vector3(0.25, 1.1, 0.2), Vector3(W / 2 - 0.35, 0.55, dz - 0.85), Color(0.95, 0.75, 0.1), false)  # composteur
	# barres de maintien
	for bz in [-3.0, -1.0, 1.5, 3.5]:
		for bx in [-0.32, 0.32]:
			Build.cylinder(self, 0.025, H, Vector3(bx, H / 2, bz), Color(0.95, 0.8, 0.1))
	# sièges : 2 de chaque côté, sauf zones des portes
	var sz := -3.6
	while sz < 5.4:
		for sx in [-1.0, -0.57, 0.57, 1.0]:
			if sx > 0 and abs(sz - DOOR_Z) < 0.9:
				continue
			Build.box(self, Vector3(0.44, 0.08, 0.45), Vector3(sx, 0.45, sz), Color(0.15, 0.25, 0.55))
			Build.box(self, Vector3(0.44, 0.55, 0.08), Vector3(sx, 0.75, sz + 0.24), Color(0.15, 0.25, 0.55))
			Build.box(self, Vector3(0.06, 0.45, 0.06), Vector3(sx, 0.2, sz), Color(0.3, 0.3, 0.3), false)
			seats.append({"pos": Vector3(sx, 0, sz - 0.02), "p": null, "standing": false})
		sz += 1.0
	# places debout dans l'allée (utilisées seulement quand toutes les places assises sont prises)
	for az in [-2.5, -1.5, 1.0, 2.0, 3.0, 4.5]:
		seats.append({"pos": Vector3(0, 0, az), "p": null, "standing": true})
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


## Place libre au hasard : d'abord assise ; debout seulement si allow_standing et plus de place assise.
func _free_seat(allow_standing := false) -> int:
	var free := []
	var free_standing := []
	for i in seats.size():
		if seats[i].p != null:
			continue
		if seats[i].get("standing", false):
			free_standing.append(i)
		else:
			free.append(i)
	if free.size() > 0:
		return free[rng.randi() % free.size()]
	if allow_standing and free_standing.size() > 0:
		return free_standing[rng.randi() % free_standing.size()]
	return -1


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
	if data.get("special", false):
		stats.speciaux.append(data.get("name", "?"))
	var standing: bool = seats[seat].get("standing", false)
	if seated_now:
		p.position = seats[seat].pos
		if standing:
			p.set_seated(false)
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
		tw.tween_callback(p.set_seated.bind(not standing))
	return p


func _alight(p: Passenger) -> void:
	seats[p.seat_index].p = null
	passengers.erase(p)
	if not p.controlled and p.data.get("truth", "") == "fraude":
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
			if state_t <= 0:
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
	_update_chat(delta)


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
	var seated := passengers.filter(func(p): return not p.data.get("special", false))
	seated.shuffle()
	for i in min(rng.randi_range(1, 2), seated.size()):
		_alight(seated[i])
	# montées : les spéciaux prévus ici passent en premier
	var n_special := special_stops.count(stop_index)
	var n := maxi(rng.randi_range(2, 4), n_special)
	for i in n:
		var is_special: bool = i < n_special and specials_pool.size() > 0
		# les spéciaux peuvent rester debout ; les passagers ordinaires ne montent que s'il reste une place assise
		var seat := -1
		if is_special and str(specials_pool.back().get("id", "")) == "oldman":
			seat = _seat_next_to_special()      # Pépé va s'asseoir à côté d'un spécial s'il y a de la place
		if seat < 0:
			seat = _free_seat(is_special)
		if seat < 0:
			continue                   # plus de place : un spécial n'est pas consommé, il reste dans la réserve
		var d: Dictionary
		if is_special:
			d = specials_pool.pop_back()
			hud.show_toast("Arrêt : %s — %s monte dans le bus ★" % [name_, d.get("name", "?")], Color(1, 0.8, 1), 4.0)
		else:
			d = People.random_passenger(line, rng)
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
		hud.show_toast(p.data.get("name", "?") + " a déjà été contrôlé.", Color(0.8, 0.8, 0.8), 1.5)
		return
	open_ticket(p)


func open_ticket(p: Passenger) -> void:
	ticket_ui = TicketUI.new()
	add_child(ticket_ui)
	ticket_ui.open(p, line)
	if player:
		player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ticket_ui.decided.connect(_on_decided)
	ticket_ui.closed.connect(_on_ticket_closed)


func _on_ticket_closed() -> void:
	ticket_ui = null
	if player:
		player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_decided(p: Passenger, dec: String) -> void:
	var fraud: bool = p.data.get("truth", "") == "fraude"
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
			var malus := 25 if p.data.get("id", "") == "agent" else 15
			stats.score -= malus
			hud.show_toast("Erreur : son titre était valide ! (-%d)" % malus, Color(1, 0.45, 0.4))
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
	set_process(false)
	stats.line = "%s %s : %s → %s" % [line.type, line.name, line.from, line.to]
	Game.finish_trip(stats)


# ------------------------------------------------------------------ Pépé Raymond tape la discute

func _can_chat_with(p) -> bool:
	if not (p is Passenger) or not is_instance_valid(p):
		return false
	if not p.data.get("special", false) or p.data.get("child", false):
		return false
	return not str(p.data.get("id", "")) in ["oldman", "driver", "tiph_enfant"]


func _are_neighbors(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	var sa: Dictionary = seats[a]
	var sb: Dictionary = seats[b]
	if sa.get("standing", false) or sb.get("standing", false):
		return false
	return absf(sa.pos.z - sb.pos.z) < 0.05 and signf(sa.pos.x) == signf(sb.pos.x)


## Place assise libre juste à côté d'un personnage spécial déjà assis, ou -1.
func _seat_next_to_special() -> int:
	var candidates := []
	for i in seats.size():
		if seats[i].p != null or seats[i].get("standing", false):
			continue
		for j in seats.size():
			if _are_neighbors(i, j) and _can_chat_with(seats[j].p):
				candidates.append(i)
				break
	return candidates[rng.randi() % candidates.size()] if candidates.size() > 0 else -1


func _is_settled(p: Passenger) -> bool:
	return p.seat_index >= 0 and p.position.distance_to(seats[p.seat_index].pos) < 0.05


func _update_chat(delta: float) -> void:
	# conversation en cours : l'un des deux est descendu ?
	if _chat_old != null:
		if not passengers.has(_chat_old) or not passengers.has(_chat_partner):
			_stop_chat()
			return
		_chat_t -= delta
		if _chat_t <= 0:
			_chat_t = CHAT_INTERVAL
			_chat_turn += 1
			if _chat_turn % 2 == 1:
				_chat_old_label.text = OLDMAN_LINES[rng.randi() % OLDMAN_LINES.size()]
				_chat_partner_label.text = ""
			else:
				var pid := str(_chat_partner.data.get("id", ""))
				var lines: Array = PARTNER_LINES.get(pid, PARTNER_LINES["_"])
				_chat_partner_label.text = lines[rng.randi() % lines.size()]
				_chat_old_label.text = ""
		return
	# pas de conversation : Pépé est-il assis à côté d'un spécial ?
	for old in passengers:
		if str(old.data.get("id", "")) != "oldman" or not _is_settled(old):
			continue
		for other in passengers:
			if _can_chat_with(other) and _is_settled(other) and _are_neighbors(old.seat_index, other.seat_index):
				_start_chat(old, other)
				return


func _start_chat(old: Passenger, partner: Passenger) -> void:
	_chat_old = old
	_chat_partner = partner
	_chat_t = 0.5
	_chat_turn = 0
	_chat_old_label = _chat_bubble(old, Color(1, 1, 0.85))
	_chat_partner_label = _chat_bubble(partner, Color(0.85, 0.95, 1))


func _chat_bubble(p: Passenger, col: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 36
	l.pixel_size = 0.003
	l.outline_size = 8
	l.modulate = col
	l.position = Vector3(0, 1.75, 0)
	p.add_child(l)
	return l


func _stop_chat() -> void:
	for l in [_chat_old_label, _chat_partner_label]:
		if l != null and is_instance_valid(l):
			l.queue_free()
	_chat_old = null
	_chat_partner = null
	_chat_old_label = null
	_chat_partner_label = null
