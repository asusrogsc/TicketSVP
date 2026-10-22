extends Node3D
## Le bus : intérieur, décor qui défile, arrêts, montées / descentes, contrôles et score.

const CRUISE := 13.0          # m/s (~47 km/h)
const LEG_TIME := 30.0        # route par défaut entre deux arrêts (réglable par arrêt dans game.gd)
const BRAKE_TIME := 3.0
const STOP_TIME := 8.0        # arrêt par défaut, portes ouvertes (réglable par arrêt dans game.gd)
const WRAP_BACK := 80.0
const WRAP_LEN := 320.0
const DOOR_Z := 0.0           # porte du milieu (côté droit, +X)
const BOARD_MIN := 2          # passagers qui montent à chaque arrêt (min)   — avant : 2
const BOARD_MAX := 4          # passagers qui montent à chaque arrêt (max)   — avant : 4
const ALIGHT_MIN := 1         # passagers qui descendent à chaque arrêt (min) — avant : 1
const ALIGHT_MAX := 2         # passagers qui descendent à chaque arrêt (max) — avant : 2
const SPECIALS_MIN := 15       # personnages spéciaux par trajet (minimum)
const QUALITY_HIGH := true    # passe à false si le PC rame
const SPECIALS_MAX := 20       # personnages spéciaux par trajet (maximum)
const CHATTY_IDS := ["oldman", "male1", "male2"]

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
# personnages bavards : ils cherchent une place à côté d'un spécial et lancent la conversation
const OLDMAN_LINES := [
	"De mon temps, le ticket coûtait 3 francs !",
	"Vous savez, j'ai conduit cette ligne pendant 30 ans...",
	"Ils ont encore changé les horaires, hein ?",
	"Mon genou annonce de la pluie pour demain.",
	"Avant, il y avait un poinçonneur. Un vrai !",
	"Le chauffeur, là, Gérard ? Je l'ai connu tout petit.",
	"Vous savez pourquoi on dit « composter » ? Moi non plus.",
]
## Répliques des bavards (clé = id). Sans entrée, le bavard utilise OLDMAN_LINES.
const TALKER_LINES := {
	"homme1": [
		"Vous avez vu le match hier soir ?",
		"Encore des travaux sur la ligne, c'est infernal.",
		"Il paraît que le tram va être prolongé jusqu'au stade.",
		"Je fais ce trajet tous les jours depuis dix ans.",
		"Le contrôleur, là, il a l'air sévère aujourd'hui...",
	],
}
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
	# même schéma que hall.gd : HUD d'abord, puis le joueur relié au HUD
	Build.environment(self, Color(0.35, 0.5, 0.8), Color(0.75, 0.8, 0.9), 0.12, 0.0)
	_setup_rendering()
	if hud == null:
		hud = _find_child_of_type(self, "Hud") as Hud
	if hud == null:
		hud = Hud.new()
		add_child(hud)
	if player == null:
		player = _find_child_of_type(self, "Player") as Player
	if player == null:
		player = Player.new()
		player.position = Vector3(0, 0.05, 2.0)   # debout dans l'allée, derrière la porte du milieu
		player.hud = hud
		add_child(player)
	if not player.interacted.is_connected(_on_interact):
		player.interacted.connect(_on_interact)
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
	_decorate_bus()
	_build_city()
	_upgrade_lights()

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

	state_t = stop_wait(0) if line.stops[0] is Dictionary and line.stops[0].has("arret") else 5.0

	var retour: bool = Game.trip_leg == "retour"
	var boarders: Array = Game.station_boarders if retour else []
	if retour and boarders.size() > 0:
		# les spéciaux déjà montés à la gare ne reviennent pas une 2e fois en route
		var ids := boarders.map(func(d): return str(d.get("id", "")))
		specials_pool = specials_pool.filter(func(d): return not str(d.get("id", "")) in ids)
		# les passagers qui attendaient sur le quai montent un par un
		var gap := 0.7
		var i := 0
		for d in boarders:
			var seat := -1
			if str(d.get("id", "")) in CHATTY_IDS:
				seat = _seat_next_to_special()
			if seat < 0:
				seat = _free_seat(d.get("special", false))
			if seat < 0:
				continue
			seats[seat].p = "réservé"
			get_tree().create_timer(0.6 + i * gap).timeout.connect(_spawn.bind(d, seat, false))
			i += 1
		state_t = maxf(state_t, 2.5 + i * gap)
	else:
		# passagers du départ
		for k in 7:
			_spawn(People.random_passenger(line, rng), _free_seat(), true)

	hud.show_toast("%s %s — %s de %s. Contrôle les titres avec [E] !" % [line.type, line.name,
		"Retour, départ" if retour else "Départ", stop_name(0)], Color(0.8, 0.95, 1), 5.0)
	set_process(true)


# ------------------------------------------------------------------ décor extérieur

func _build_city() -> void:
	var asphalt := Color(0.2, 0.2, 0.22)
	var pavement := Color(0.62, 0.61, 0.58)
	# chaussée, bordures, trottoirs, pelouses (fixes, très longs)
	_tiles(Build.box(self, Vector3(14, 0.1, 400), Vector3(0, -0.8, -100), asphalt, false),
		Vector2(4, 4), 0.0, 0.0, asphalt, asphalt, 0.0, 0.55, 0.92, true)
	for side in [-1, 1]:
		_rough(Build.box(self, Vector3(0.25, 0.3, 400), Vector3(side * 7.1, -0.65, -100), Color(0.75, 0.75, 0.72), false), 0.8)   # bordure
		_tiles(Build.box(self, Vector3(4, 0.25, 400), Vector3(side * 9, -0.65, -100), pavement, false),
			Vector2(0.6, 0.6), 0.0, 0.012, pavement, pavement.darkened(0.3), 0.1, 0.25, 0.9, true)                 # trottoir
		_tiles(Build.box(self, Vector3(30, 0.1, 400), Vector3(side * 26, -0.75, -100), Color.WHITE, false),
			Vector2(1.5, 1.5), 0.0, 0.0, Color(0.3, 0.5, 0.26), Color.BLACK, 0.06, 0.4, 1.0, true)                  # pelouse
		Build.box(self, Vector3(0.12, 0.02, 400), Vector3(side * 6.6, -0.745, -100), Color(0.92, 0.92, 0.88), false)              # ligne de rive

	var z := -240.0
	while z < WRAP_BACK:
		# marquage central en pointillés
		_mover(Build.box(world, Vector3(0.15, 0.02, 3), Vector3(0, -0.74, z), Color(0.95, 0.95, 0.9), false))
		# joints du trottoir
		for side in [-1, 1]:
			_mover(Build.box(world, Vector3(3.9, 0.005, 0.03), Vector3(side * 9, -0.52, z), pavement.darkened(0.15), false))
		if int(z) % 24 == 0:
			for side in [-1, 1]:
				_mover(_street_lamp(side, z))
		elif int(z) % 36 == 6:
			_mover(_bench(rng.randf() < 0.5, z))
		z += 6.0

	z = -240.0
	while z < WRAP_BACK:
		for side in [-1, 1]:
			var w := rng.randf_range(8, 16)
			_mover(_building(side, z, w))
			if rng.randf() < 0.55:
				_mover(_tree(side, z + w / 2))
		z += 16.0


func _street_lamp(side: int, z: float) -> Node3D:
	var pole := Node3D.new()
	pole.position = Vector3(side * 7.6, -0.55, z)
	world.add_child(pole)
	var metal := Color(0.22, 0.24, 0.27)
	_metal(Build.cylinder(pole, 0.09, 0.5, Vector3(0, 0.25, 0), metal), 0.5)        # socle
	_metal(Build.cylinder(pole, 0.06, 6, Vector3(0, 3, 0), metal), 0.45)
	_metal(Build.box(pole, Vector3(1.3, 0.08, 0.12), Vector3(-side * 0.6, 5.95, 0), metal, false), 0.45)
	var head := Build.box(pole, Vector3(0.5, 0.1, 0.25), Vector3(-side * 1.15, 5.88, 0), Color(1, 0.95, 0.8), false)
	_glow(head, Color(1, 0.93, 0.78), 1.2)
	return pole


func _bench(left: bool, z: float) -> Node3D:
	var side := -1 if left else 1
	var b := Node3D.new()
	b.position = Vector3(side * 10.2, -0.52, z)
	b.rotation_degrees.y = 90 * side
	world.add_child(b)
	var wood := Color(0.5, 0.33, 0.18)
	for k in 3:
		Build.box(b, Vector3(1.6, 0.04, 0.1), Vector3(0, 0.45, -0.12 + k * 0.12), wood, false)
	Build.box(b, Vector3(1.6, 0.3, 0.04), Vector3(0, 0.7, 0.2), wood, false)
	for x in [-0.7, 0.7]:
		_metal(Build.box(b, Vector3(0.05, 0.45, 0.4), Vector3(x, 0.22, 0), Color(0.15, 0.15, 0.17), false), 0.5)
	# poubelle à côté
	_metal(Build.cylinder(b, 0.2, 0.7, Vector3(1.2, 0.35, 0), Color(0.15, 0.35, 0.2)), 0.6)
	return b


func _building(side: int, z: float, w: float) -> Node3D:
	var h := rng.randf_range(6, 22)
	var depth := 10.0
	var col := Color.from_hsv(rng.randf_range(0.02, 0.14) if rng.randf() < 0.7 else rng.randf(),
		rng.randf_range(0.08, 0.3), rng.randf_range(0.55, 0.88))
	var b := Node3D.new()
	b.position = Vector3(side * rng.randf_range(16, 22), -0.6, z)
	world.add_child(b)
	var face := -side * (depth / 2 + 0.02)      # façade tournée vers la rue
	if rng.randf() < 0.55:      # briques
		_tiles(Build.box(b, Vector3(depth, h, w * 0.9), Vector3(0, h / 2, 0), col, false),
			Vector2(0.24, 0.075), 0.5, 0.012, col, col.lightened(0.35), 0.3, 0.12, 0.9, false, true)
	else:                        # enduit
		_tiles(Build.box(b, Vector3(depth, h, w * 0.9), Vector3(0, h / 2, 0), col, false),
			Vector2(3, 3), 0.0, 0.0, col, col, 0.04, 0.3, 0.95, false, true)
	# corniche de toit + rebord
	_rough(Build.box(b, Vector3(depth + 0.4, 0.35, w * 0.9 + 0.4), Vector3(0, h + 0.17, 0), col.darkened(0.25), false), 0.85)
	# rez-de-chaussée : vitrine de magasin + auvent
	var shop := rng.randf() < 0.6
	if shop:
		_rough(Build.box(b, Vector3(0.1, 2.6, w * 0.9), Vector3(face, 1.3, 0), col.darkened(0.4), false), 0.8)
		var vitrine := Build.box(b, Vector3(0.05, 1.8, w * 0.7), Vector3(face * 1.004, 1.2, 0), Color(0.85, 0.8, 0.6), false)
		_glow(vitrine, Color(1, 0.9, 0.7), 0.35)
		var awn := Color.from_hsv(rng.randf(), 0.6, 0.7)
		var a := Build.box(b, Vector3(1.4, 0.08, w * 0.75), Vector3(face * 1.0 + -side * 0.7, 2.8, 0), awn, false)
		a.rotation_degrees.z = 12 * side
	# étages : fenêtres avec cadre, certaines éclairées
	var fy := 3.4 if shop else 2.0
	var n_cols := maxi(int(w * 0.9 / 2.2), 1)
	var span := w * 0.9
	while fy < h - 1.2:
		for c in n_cols:
			var wz := -span / 2 + (c + 0.5) * span / n_cols
			Build.box(b, Vector3(0.06, 1.25, 1.05), Vector3(face * 1.002, fy, wz), Color(0.92, 0.9, 0.86), false)   # cadre
			var glass := Build.box(b, Vector3(0.06, 1.1, 0.9), Vector3(face * 1.006, fy, wz), Color(0.45, 0.58, 0.72), false)
			if rng.randf() < 0.18:
				_glow(glass, Color(1, 0.85, 0.6), 0.5)
			else:
				_metal(glass, 0.08, Color(0.45, 0.58, 0.72), 0.3)
			# rebord de fenêtre (qualité haute seulement : beaucoup d'objets)
			if QUALITY_HIGH:
				Build.box(b, Vector3(0.18, 0.06, 1.1), Vector3(face * 1.01, fy - 0.62, wz), Color(0.85, 0.83, 0.8), false)
		fy += 3.0
	return b


func _tree(side: int, z: float) -> Node3D:
	var tree := Node3D.new()
	tree.position = Vector3(side * 10.5, -0.55, z)
	world.add_child(tree)
	_rough(Build.cylinder(tree, 0.15, 2.2, Vector3(0, 1.1, 0), Color(0.36, 0.25, 0.15)), 1.0)
	# grille au pied
	_metal(Build.box(tree, Vector3(1.0, 0.03, 1.0), Vector3(0, 0.03, 0), Color(0.2, 0.2, 0.22), false), 0.6)
	var green := Color(0.22 + rng.randf() * 0.08, 0.48 + rng.randf() * 0.1, 0.22)
	for k in 4:
		var leaves := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.8, 1.15)
		sm.height = sm.radius * 1.8
		leaves.mesh = sm
		var mat := Build.mat(green.darkened(k * 0.06))
		if mat is StandardMaterial3D:
			mat.roughness = 1.0
		leaves.material_override = mat
		leaves.position = Vector3(rng.randf_range(-0.5, 0.5), 2.6 + rng.randf_range(-0.2, 0.7), rng.randf_range(-0.5, 0.5))
		tree.add_child(leaves)
	return tree


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
	_tiles(Build.box(self, Vector3(W, 0.1, L), Vector3(0, H + 0.05, 0), Color(0.9, 0.9, 0.88)),
		Vector2(0.62, 1.2), 0.0, 0.012, Color(0.92, 0.92, 0.9), Color(0.6, 0.6, 0.6), 0.02, 0.05, 0.6, false, true)   # plafond
	# arrière : cadre autour de la lunette (la route qui défile est visible derrière)
	Build.box(self, Vector3(W, 1.2, 0.1), Vector3(0, 0.6, L / 2), Color(0.72, 0.74, 0.77))
	Build.box(self, Vector3(W, H - 2.0, 0.1), Vector3(0, 2.0 + (H - 2.0) / 2, L / 2), Color(0.72, 0.74, 0.77))
	for sx in [-1, 1]:
		Build.box(self, Vector3(0.2, 0.8, 0.1), Vector3(sx * 1.15, 1.6, L / 2), Color(0.72, 0.74, 0.77))
	# avant : pare-brise + tableau de bord
	Build.box(self, Vector3(W, 0.9, 0.3), Vector3(0, 0.45, -L / 2), Color(0.15, 0.15, 0.17))
	_bus_finish_window(Build.box(self, Vector3(W, H - 0.9, 0.05), Vector3(0, 0.9 + (H - 0.9) / 2, -L / 2 - 0.1), Color(0.7, 0.85, 0.95, 0.15), true, 0.05))
	# côtés : soubassement, vitres, bandeau haut, montants
	for side in [-1, 1]:
		var x: float = side * W / 2
		_tiles(Build.box(self, Vector3(0.1, 0.95, L), Vector3(x, 0.475, 0), Color(0.72, 0.74, 0.77)),
			Vector2(1.5, 0.95), 0.0, 0.01, Color(0.78, 0.79, 0.81), Color(0.45, 0.46, 0.48), 0.02, 0.08, 0.55, false, true)
		Build.box(self, Vector3(0.1, 0.45, L), Vector3(x, H - 0.225, 0), body.darkened(0.35))
		_bus_finish_window(Build.box(self, Vector3(0.04, 1.05, L), Vector3(x, 1.475, 0), Color(0.75, 0.88, 0.97, 0.18), true, 0.05))
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
			_bus_finish_door(d)
		_metal(Build.box(self, Vector3(0.05, 1.0, 0.05), Vector3(W / 2 - 0.35, 0.5, dz - 0.85), Color(0.6, 0.62, 0.65), false), 0.3)   # pied du composteur
		_rough(Build.box(self, Vector3(0.22, 0.4, 0.18), Vector3(W / 2 - 0.37, 1.0, dz - 0.85), Color(0.2, 0.21, 0.23), false), 0.45)   # boîtier
		Build.box(self, Vector3(0.012, 0.36, 0.16), Vector3(W / 2 - 0.255, 1.0, dz - 0.85), Color(0.95, 0.75, 0.1), false)              # façade jaune
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
			_seat(sx, sz)
			Build.box(self, Vector3(0.06, 0.45, 0.06), Vector3(sx, 0.2, sz), Color(0.3, 0.3, 0.3), false)
			seats.append({"pos": Vector3(sx, 0, sz - 0.02), "p": null, "standing": false})
		sz += 1.0
	# banquette arrière : 5 places assises
	_rear_bench(L)
	# places debout (seulement quand toutes les places assises sont prises) :
	# devant la banquette arrière, dans l'allée et sur la plateforme de la porte du milieu
	for spot in [Vector2(-0.55, 4.98), Vector2(0, 4.98), Vector2(0.55, 4.98), Vector2(0, 3.95), Vector2(0.8, -0.45), Vector2(0.8, 0.45)]:
		seats.append({"pos": Vector3(spot.x, 0, spot.y), "p": null, "standing": true})
	# chauffeur
	var drv_data := {"id": "driver", "special": false, "name": "Gérard (chauffeur)", "body": Color(0.2, 0.3, 0.5),
		"legs": Color(0.15, 0.15, 0.2), "skin": Color(0.9, 0.72, 0.6), "hair": Color(0.4, 0.4, 0.4), "greet": ""}
	var drv := Passenger.new()
	drv.setup(drv_data)
	drv.position = Vector3(-0.75, 0, -5.2)
	add_child(drv)
	drv.controlled = true
	Build.box(self, Vector3(0.5, 0.08, 0.5), Vector3(-0.75, 0.45, -5.2), Color(0.1, 0.1, 0.1), false)
	_bus_finish_wheel()
	# afficheur de ligne
	Build.box(self, Vector3(1.6, 0.25, 0.08), Vector3(0.3, 2.03, -5.45), Color(0.05, 0.05, 0.05), false)
	display = Build.label3d(self, "", Vector3(0.3, 2.03, -5.4), 26, Color(1, 0.6, 0.1))
	display.pixel_size = 0.0025
	# éclairage intérieur
	for lz in [-3.5, 0, 3.5]:
		Build.light(self, Vector3(0, H - 0.1, lz), Color(0.95, 0.97, 1), 0.35, 5.0)


## Place libre au hasard : d'abord assise ; debout seulement si allow_standing et plus de place assise.
# ------------------------------------------------------------------ finitions « HD » du bus

func _decorate_bus() -> void:
	var L := 12.0; var W := 2.5; var H := 2.45
	var steel := Color(0.8, 0.82, 0.85)
	# barres de maintien horizontales sous le plafond
	for x in [-0.55, 0.55]:
		var rail := Build.cylinder(self, 0.02, 9.5, Vector3(x, H - 0.25, 0.4), steel)
		rail.rotation_degrees.x = 90
		_metal(rail, 0.25)
	# boutons « arrêt demandé » rouges sur les barres verticales
	for bz in [-3.0, -1.0, 1.5, 3.5]:
		for bx in [-0.32, 0.32]:
			var btn := Build.cylinder(self, 0.036, 0.07, Vector3(bx, 1.3, bz), Color(0.85, 0.1, 0.1))
			_glow(btn, Color(1, 0.15, 0.1), 0.5)
			var cap := Build.cylinder(self, 0.02, 0.012, Vector3(bx + (0.03 if bx < 0 else -0.03), 1.3, bz), Color(1, 0.9, 0.9))
			cap.rotation_degrees.z = 90
			_glow(cap, Color(1, 0.6, 0.6), 0.8)
	# bandeaux LED au plafond
	for x in [-0.75, 0.75]:
		var led := Build.box(self, Vector3(0.12, 0.02, L - 1.5), Vector3(x, H - 0.01, 0.3), Color(1, 1, 0.97), false)
		_glow(led, Color(0.95, 0.97, 1), 1.6)
	# panneaux publicitaires au-dessus des vitres
	# [fond, couleur du texte, titre, slogan, couleur du logo]
	var ads := [
		[Color(0.55, 0.3, 0.18), Color(1, 0.95, 0.85), "CAFÉ BRÛLOT", "Le petit noir qui réveille la ville", Color(0.95, 0.8, 0.5)],
		[Color(0.95, 0.85, 0.2), Color(0.12, 0.12, 0.15), "VALIDEZ VOTRE TITRE !", "À chaque montée, même en correspondance", Color(0.1, 0.4, 0.8)],
		[Color(0.2, 0.45, 0.8), Color(1, 1, 1), "ASSURANCES TRANQUILLES", "On s'occupe de tout. Vraiment.", Color(1, 1, 1)],
		[Color(0.92, 0.92, 0.9), Color(0.15, 0.25, 0.55), "CÉDEZ VOTRE PLACE", "aux personnes âgées, enceintes ou à mobilité réduite", Color(0.15, 0.25, 0.55)],
		[Color(0.2, 0.6, 0.35), Color(1, 1, 1), "PIZZA DEL PONTE", "Livrée chaude en 30 min ou offerte", Color(0.95, 0.3, 0.2)],
		[Color(0.85, 0.2, 0.2), Color(1, 1, 1), "AMENDE : 50 €", "Voyager sans titre valable vous coûte cher", Color(1, 1, 1)],
		[Color(0.12, 0.12, 0.16), Color(1, 0.75, 0.2), "CINÉ ÉTOILE", "Nouvelle salle 4DX — ouverture samedi", Color(1, 0.75, 0.2)],
		[Color(0.3, 0.7, 0.85), Color(1, 1, 1), "APPLI RÉSEAU", "Vos tickets et horaires dans la poche", Color(1, 1, 1)],
	]
	var i := 0
	for side in [-1, 1]:
		for az in [-3.0, -0.5, 2.5, 4.5]:
			if side > 0 and abs(az - DOOR_Z) < 1.0:
				continue
			var ad: Array = ads[i % ads.size()]
			_ad_panel(Vector3(side * (W / 2 - 0.07), H - 0.24, az), side, ad)
			i += 1
	# bandes jaunes de sécurité au sol devant les portes
	for dz in [-4.9, DOOR_Z]:
		Build.box(self, Vector3(0.8, 0.012, 1.3), Vector3(W / 2 - 0.45, 0.006, dz), Color(0.95, 0.8, 0.1), false)
	# revêtement de sol : petites pastilles antidérapantes
	_bus_finish_surface(Build.box(self, Vector3(W - 0.2, 0.008, L - 0.4), Vector3(0, 0.004, 0), Color(0.3, 0.31, 0.34), false), false)
	# vitre arrière
	var rear := Build.box(self, Vector3(W - 0.4, 0.8, 0.04), Vector3(0, 1.6, L / 2 - 0.06), Color(0.7, 0.85, 0.95, 0.2), false)
	_bus_finish_window(rear)
	# tableau de bord lumineux
	var dash := Build.box(self, Vector3(0.6, 0.25, 0.02), Vector3(-0.75, 0.95, -5.82), Color(0.1, 0.3, 0.5), false)
	var dash_mat := _own_mat(dash)
	dash_mat.albedo_color = Color(0.10,0.12,0.14)
	dash_mat.roughness = 0.72
	_bus_finish_soften(dash,0.008)
	_bus_finish_dashboard()
	_decorate_bus_hd()


func _setup_rendering() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if QUALITY_HIGH else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true
	var we: WorldEnvironment = null
	for c in find_children("*", "WorldEnvironment", true, false):
		we = c
		break
	if we and we.environment:
		var env := we.environment
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 6.0
		env.ssao_enabled = true
		env.ssao_radius = 0.7
		env.ssao_intensity = 1.4
		env.ssil_enabled = QUALITY_HIGH
		env.ssil_intensity = 0.6
		env.glow_enabled = true
		env.glow_intensity = 0.45
		env.glow_hdr_threshold = 1.1
		env.fog_enabled = true                      # brume de distance : la ville se fond au loin
		env.fog_light_color = Color(0.72, 0.78, 0.88)
		env.fog_density = 0.006
		env.fog_aerial_perspective = 0.4
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.05
		env.adjustment_saturation = 1.1
	# soleil avec ombres (les bâtiments et lampadaires projettent leur ombre dans le bus)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -55, 0)
	sun.light_color = Color(1, 0.93, 0.8)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0 if QUALITY_HIGH else 30.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if QUALITY_HIGH else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


func _upgrade_lights() -> void:
	for l in find_children("*", "OmniLight3D", true, false):
		var o := l as OmniLight3D
		o.shadow_enabled = QUALITY_HIGH
		o.shadow_bias = 0.03
		o.light_specular = 0.5


## Build.box / Build.cylinder peuvent renvoyer le mesh ou un corps qui le contient.
func _mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	var found := n.find_children("*", "MeshInstance3D", true, false)
	return found[0] if found.size() > 0 else null


func _own_mat(n: Node) -> StandardMaterial3D:
	var m := _mesh_of(n)
	if m == null:
		return null
	var mat: StandardMaterial3D
	if m.material_override is StandardMaterial3D:
		mat = m.material_override.duplicate()
	else:
		mat = StandardMaterial3D.new()
	m.material_override = mat
	return mat


func _rough(n: Node, r: float) -> Node:
	var mat := _own_mat(n)
	if mat:
		mat.roughness = r
	return n


func _metal(n: Node, rough: float, col = null, metallic := 1.0) -> Node:
	var mat := _own_mat(n)
	if mat:
		if col != null:
			mat.albedo_color = col
		mat.metallic = metallic
		mat.roughness = rough
	return n


func _glow(n: Node, col: Color, energy: float) -> Node:
	var mat := _own_mat(n)
	if mat:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
	var m := _mesh_of(n)
	if m:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


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
	_scroll_z += dz
	for m in _scroll_mats:
		m.set_shader_parameter("scroll_z", _scroll_z)
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
	_update_route_map()
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
	for i in min(rng.randi_range(ALIGHT_MIN, ALIGHT_MAX), seated.size()):
		_alight(seated[i])
	# montées : les spéciaux prévus ici passent en premier
	var n_special := special_stops.count(stop_index)
	var n := maxi(rng.randi_range(BOARD_MIN, BOARD_MAX), n_special)
	# tout le monde doit être monté avant la fermeture des portes
	var gap: float = clampf((stop_wait(stop_index) - 1.5) / maxf(n, 1), 0.45, 1.2)
	for i in n:
		var is_special: bool = i < n_special and specials_pool.size() > 0
		# les spéciaux peuvent rester debout ; les passagers ordinaires ne montent que s'il reste une place assise
		var seat := -1
		if is_special and str(specials_pool.back().get("id", "")) in CHATTY_IDS:
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
		var delay := 0.8 + i * gap
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
	if line.get("retour", false):
		where = "[Retour]  " + where
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
	Game.end_leg(stats)        # aller -> gare du terminus ; retour -> bilan


# ------------------------------------------------------------------ Pépé Raymond tape la discute

func _can_chat_with(p) -> bool:
	if not (p is Passenger) or not is_instance_valid(p):
		return false
	if not p.data.get("special", false) or p.data.get("child", false):
		return false
	return not str(p.data.get("id", "")) in ["oldman", "driver"]


func _are_neighbors(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	var sa: Dictionary = seats[a]
	var sb: Dictionary = seats[b]
	if sa.get("standing", false) or sb.get("standing", false):
		# l'un des deux est debout au fond : voisins s'ils sont tout proches
		return sa.pos.distance_to(sb.pos) < 1.0
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
				var talk: Array = TALKER_LINES.get(str(_chat_old.data.get("id", "")), OLDMAN_LINES)
				_chat_old_label.text = talk[rng.randi() % talk.size()]
				_chat_partner_label.text = ""
			else:
				var pid := str(_chat_partner.data.get("id", ""))
				var lines: Array = PARTNER_LINES.get(pid, PARTNER_LINES["_"])
				_chat_partner_label.text = lines[rng.randi() % lines.size()]
				_chat_old_label.text = ""
		return
	# pas de conversation : Pépé est-il assis à côté d'un spécial ?
	for old in passengers:
		if not str(old.data.get("id", "")) in CHATTY_IDS or not _is_settled(old):
			continue
		for other in passengers:
			if other != old and _can_chat_with(other) and _is_settled(other) and _are_neighbors(old.seat_index, other.seat_index):
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


# ------------------------------------------------------------------ intérieur « HD » (2e passe)

var _route_dots: Array = []          # pastilles du plan de ligne (une par arrêt)
var _stop_sign: Node = null          # bandeau « ARRÊT DEMANDÉ »
var _scroll_mats: Array[ShaderMaterial] = []
var _scroll_z := 0.0


## Siège en tissu moucheté : assise rembourrée, dossier, coque plastique, poignée chromée.
func _seat(sx: float, sz: float) -> void:
	var finish_start := get_child_count()
	var fabric := Color(0.13, 0.22, 0.5)
	var shell := Color(0.25, 0.27, 0.3)
	# coque plastique
	_rough(Build.box(self, Vector3(0.46, 0.06, 0.47), Vector3(sx, 0.41, sz), shell), 0.4)
	_rough(Build.box(self, Vector3(0.46, 0.62, 0.05), Vector3(sx, 0.76, sz + 0.27), shell, false), 0.4)
	# coussins en tissu
	var cushion := Build.box(self, Vector3(0.42, 0.07, 0.42), Vector3(sx, 0.475, sz - 0.01), fabric)
	_bus_finish_surface(cushion, true)
	var back := Build.box(self, Vector3(0.42, 0.52, 0.06), Vector3(sx, 0.78, sz + 0.235), fabric, false)
	_bus_finish_surface(back, true)
	# appui-tête gris + poignée chromée au dos
	_headrest(Vector3(sx, 1.08, sz + 0.25), 0.3)
	_glow(Build.box(self, Vector3(0.42, 0.02, 0.065), Vector3(sx, 1.03, sz + 0.235), line.color, false), line.color, 0.15)
	var grip := Build.cylinder(self, 0.014, 0.32, Vector3(sx, 1.0, sz + 0.31), Color(0.85, 0.86, 0.88))
	grip.rotation_degrees.z = 90
	_metal(grip, 0.2)
	for i in range(finish_start,get_child_count()):
		_bus_finish_soften(get_child(i),0.012)


func _decorate_bus_hd() -> void:
	var L := 12.0; var W := 2.5; var H := 2.45
	var rubber := Color(0.06, 0.06, 0.07)
	# joints caoutchouc autour des vitres
	for side in [-1, 1]:
		var x: float = side * (W / 2 - 0.03)
		Build.box(self, Vector3(0.03, 0.04, L), Vector3(x, 0.95, 0), rubber, false)
		Build.box(self, Vector3(0.03, 0.04, L), Vector3(x, 2.0, 0), rubber, false)
	# cloison vitrée derrière le chauffeur
	var part := Build.box(self, Vector3(0.95, 1.2, 0.03), Vector3(-0.78, 1.25, -4.65), Color(0.75, 0.88, 0.95, 0.2))
	_bus_finish_window(part)
	_metal(Build.box(self, Vector3(0.95, 0.65, 0.04), Vector3(-0.78, 0.33, -4.65), Color(0.28, 0.3, 0.33)), 0.5, null, 0.3)
	# valideurs : écran vert et lecteur de carte sur chaque composteur
	for dz in [-4.9, DOOR_Z]:
		_glow(Build.box(self, Vector3(0.01, 0.1, 0.12), Vector3(W / 2 - 0.245, 1.08, dz - 0.85), Color(0.2, 0.9, 0.4), false), Color(0.25, 1, 0.45), 1.2)
		_glow(Build.box(self, Vector3(0.01, 0.08, 0.08), Vector3(W / 2 - 0.245, 0.92, dz - 0.85), Color(0.9, 0.9, 0.9), false), Color(1, 1, 1), 0.4)
	# « SORTIE » vert au-dessus des portes
	for dz in [-4.9, DOOR_Z]:
		_glow(Build.box(self, Vector3(0.03, 0.14, 0.5), Vector3(W / 2 - 0.08, 2.15, dz), Color(0.1, 0.6, 0.25), false), Color(0.15, 0.85, 0.35), 1.0)
		var sl := Build.label3d(self, "SORTIE", Vector3(W / 2 - 0.1, 2.15, dz), 22, Color.WHITE)
		sl.rotation_degrees.y = -90
		sl.pixel_size = 0.003
	# bandeau « ARRÊT DEMANDÉ » (s'allume quand le bus freine pour un arrêt)
	_stop_sign = Build.box(self, Vector3(0.9, 0.11, 0.03), Vector3(0.3, 1.83, -5.42), Color(0.25, 0.05, 0.05), false)
	_glow(_stop_sign, Color(0.25, 0.05, 0.05), 0.05)
	var asl := Build.label3d(self, "ARRÊT DEMANDÉ", Vector3(0.3, 1.83, -5.4), 22, Color(1, 0.85, 0.85))
	asl.pixel_size = 0.0028
	# plan de ligne lumineux face aux voyageurs (arrêt suivant en orange)
	_build_route_map(Vector3(0, H - 0.15, -4.55), W - 0.5)
	# poignées suspendues aux barres horizontales
	for x in [-0.55, 0.55]:
		var hz := -3.6
		while hz < 5.0:
			var strap := Build.box(self, Vector3(0.008, 0.16, 0.025), Vector3(x, H - 0.34, hz), Color(0.1, 0.1, 0.12), false)
			_rough(strap, 0.7)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.035
			tm.outer_radius = 0.048
			ring.mesh = tm
			ring.material_override = Build.mat(Color(0.95, 0.8, 0.1), 0.35)
			ring.position = Vector3(x, H - 0.46, hz)
			ring.rotation_degrees.z = 90          # anneau vertical, dans l'axe de l'allée
			add_child(ring)
			hz += 0.8
	# bouches d'aération au plafond
	for vz in [-3.0, 0.5, 3.8]:
		_rough(Build.box(self, Vector3(0.5, 0.02, 0.18), Vector3(0, H - 0.005, vz), Color(0.75, 0.76, 0.78), false), 0.5)
		for k in 4:
			Build.box(self, Vector3(0.44, 0.022, 0.015), Vector3(0, H - 0.008, vz - 0.06 + k * 0.04), Color(0.3, 0.3, 0.32), false)


func _build_route_map(at: Vector3, width: float) -> void:
	_metal(Build.box(self, Vector3(width + 0.1, 0.26, 0.05), at, Color(0.05, 0.05, 0.06), false), 0.4)
	_glow(Build.box(self, Vector3(width - 0.1, 0.025, 0.01), at + Vector3(0, 0.0, 0.03), line.color, false), line.color, 0.8)
	var n: int = line.stops.size()
	for i in n:
		var x := -width / 2 + 0.1 + (width - 0.2) * (float(i) / maxf(n - 1, 1))
		var dot := Build.box(self, Vector3(0.045, 0.045, 0.015), at + Vector3(x, 0.0, 0.035), Color.WHITE, false)
		_glow(dot, Color.WHITE, 0.6)
		_route_dots.append(dot)
		var lab := Build.label3d(self, stop_name(i), at + Vector3(x, -0.075 if i % 2 == 0 else 0.075, 0.04), 15, Color(0.95, 0.95, 0.95))
		lab.pixel_size = 0.0022


## Met à jour le plan de ligne et le bandeau « ARRÊT DEMANDÉ ».
func _update_route_map() -> void:
	var next_i: int = stop_index if state in ["stop", "depart", "terminus", "fin"] else stop_index + 1
	var blink := fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0
	for i in _route_dots.size():
		var col := Color(0.35, 0.35, 0.38)            # arrêts passés
		var e := 0.2
		if i == next_i:
			col = Color(1, 0.6, 0.1)
			e = 2.0 if blink else 0.8
		elif i > next_i:
			col = Color(1, 1, 1)
			e = 0.6
		_set_glow(_route_dots[i], col, e)
	if _stop_sign:
		var on: bool = state == "brake" or (state == "drive" and state_t < 6.0)
		_set_glow(_stop_sign, Color(0.9, 0.1, 0.1) if on else Color(0.25, 0.05, 0.05), 1.6 if on else 0.05)


## Change la lueur d'un objet déjà passé par _glow (sans recréer de matériau à chaque image).
func _set_glow(n: Node, col: Color, energy: float) -> void:
	var m := _mesh_of(n)
	if m == null or not (m.material_override is StandardMaterial3D):
		return
	var mat: StandardMaterial3D = m.material_override
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy


# ------------------------------------------------------------------ matériau procédural (tissu, dalles, briques, asphalte)

const TILE_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 grout_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec2 tile_size = vec2(0.5, 0.5);
uniform float stagger = 0.0;
uniform float grout = 0.01;
uniform float variation = 0.1;
uniform float speckle = 0.2;
uniform float rough = 0.85;
uniform bool local_space = false;
uniform float scroll_z = 0.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	if (local_space) {
		wpos = VERTEX;
		wnrm = NORMAL;
	} else {
		wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
	wpos.z -= scroll_z;
}
void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.y > 0.6 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	vec2 b = uv / tile_size;
	b.x += mod(floor(b.y), 2.0) * stagger;
	vec2 id = floor(b);
	vec2 f = fract(b);
	vec2 g = vec2(grout) / tile_size;
	float inside = step(g.x, f.x) * step(g.y, f.y);
	float v = hash(id);
	float sp = noise(uv * 40.0) * 0.6 + noise(uv * 7.0) * 0.4;
	vec3 col = base_color.rgb * (1.0 - variation * 0.5 + variation * v) * (1.0 - speckle * 0.5 + speckle * sp);
	ALBEDO = mix(grout_color.rgb, col, inside);
	ROUGHNESS = mix(1.0, rough, inside) - sp * 0.05;
	AO = mix(0.55, 1.0, inside);
	AO_LIGHT_AFFECT = 0.4;
}
"""

var _tile_shader: Shader


## scroll : la texture défile avec la vitesse du bus (sols fixes) ; local : suit l'objet (décor qui défile, intérieur).
func _tiles(n: Node, size: Vector2, stagger: float, grout: float, col: Color, grout_col: Color,
		variation: float, speckle: float, rough: float, scroll := false, local := false) -> Node:
	if _tile_shader == null:
		_tile_shader = Shader.new()
		_tile_shader.code = TILE_SHADER
	var m := _mesh_of(n)
	if m == null:
		return n
	var mat := ShaderMaterial.new()
	mat.shader = _tile_shader
	mat.set_shader_parameter("base_color", col)
	mat.set_shader_parameter("grout_color", grout_col)
	mat.set_shader_parameter("tile_size", size)
	mat.set_shader_parameter("stagger", stagger)
	mat.set_shader_parameter("grout", grout)
	mat.set_shader_parameter("variation", variation)
	mat.set_shader_parameter("speckle", speckle)
	mat.set_shader_parameter("rough", rough)
	mat.set_shader_parameter("local_space", local)
	m.material_override = mat
	if scroll:
		_scroll_mats.append(mat)
	return n


# ------------------------------------------------------------------ pubs, banquette arrière, appuis-tête

## Panneau publicitaire au-dessus des vitres, tourné vers l'allée. ad = [fond, texte, titre, slogan, logo]
func _ad_panel(at: Vector3, side: int, ad: Array) -> void:
	var bg := Build.box(self, Vector3(0.02, 0.3, 0.9), at, ad[0], false)
	_glow(bg, ad[0], 0.22)
	Build.box(self, Vector3(0.025, 0.32, 0.92), at + Vector3(side * 0.003, 0, 0), Color(0.75, 0.77, 0.8), false)   # cadre alu
	var inward := -side * 0.016
	# logo rond à gauche
	var logo := Build.cylinder(self, 0.06, 0.01, at + Vector3(inward, 0, -0.33 * -side), ad[4])
	logo.rotation_degrees.z = 90
	_glow(logo, ad[4], 0.4)
	var rot := 90.0 if side < 0 else -90.0
	var title := Build.label3d(self, ad[2], at + Vector3(inward, 0.055, 0.06 * side), 26, ad[1])
	title.rotation_degrees.y = rot
	title.pixel_size = 0.0022
	title.outline_size = 0
	var slogan := Build.label3d(self, ad[3], at + Vector3(inward, -0.06, 0.06 * side), 15, ad[1])
	slogan.rotation_degrees.y = rot
	slogan.pixel_size = 0.0018
	slogan.outline_size = 0
	slogan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slogan.width = 330


## Banquette du fond : un seul coussin sur toute la largeur, 5 places assises.
func _rear_bench(L: float) -> void:
	var finish_start := get_child_count()
	var fabric := Color(0.13, 0.22, 0.5)
	var z := L / 2 - 0.47
	_rough(Build.box(self, Vector3(2.3, 0.42, 0.5), Vector3(0, 0.21, z), Color(0.25, 0.27, 0.3)), 0.4)          # coffre
	var cushion := Build.box(self, Vector3(2.26, 0.08, 0.46), Vector3(0, 0.46, z - 0.01), fabric)
	_bus_finish_surface(cushion, true)
	var back := Build.box(self, Vector3(2.26, 0.6, 0.08), Vector3(0, 0.8, z + 0.25), fabric, false)
	_bus_finish_surface(back, true)
	_glow(Build.box(self, Vector3(2.26, 0.02, 0.085), Vector3(0, 1.1, z + 0.25), line.color, false), line.color, 0.15)
	for x in [-0.9, -0.45, 0.0, 0.45, 0.9]:
		_headrest(Vector3(x, 1.2, z + 0.27), 0.28)
		seats.append({"pos": Vector3(x, 0, z - 0.02), "p": null, "standing": false})

	for i in range(finish_start,get_child_count()):
		_bus_finish_soften(get_child(i),0.012)


## Appui-tête arrondi (capsule couchée) gris.
func _headrest(at: Vector3, width: float) -> void:
	var hr := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.055
	cm.height = width
	hr.mesh = cm
	hr.material_override = Build.mat(Color(0.55, 0.56, 0.58), 0.75)
	hr.position = at
	hr.rotation_degrees.z = 90
	add_child(hr)



# ------------------------------------------------------------------ finitions visuelles isolées
# Aucun RNG global, collider, siège logique, lumière ou timer supplémentaire.
const _BUS_FINISH_SHADER := """
shader_type spatial;
uniform vec4 color : source_color = vec4(0.13, 0.25, 0.42, 1.0);
uniform bool fabric = true;
varying vec3 pos;
varying vec3 nrm;
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {pos=VERTEX; nrm=NORMAL;}
void fragment() {
	vec3 an=abs(nrm);
	vec2 uv=an.y>0.6 ? pos.xz : (an.x>an.z ? pos.zy : pos.xy);
	float footprint=max(length(dFdx(uv)),length(dFdy(uv)));
	float detail=1.0-smoothstep(0.001,0.008,footprint);
	float grain=noise(uv*280.0);
	vec3 col=color.rgb;
	if (fabric) {
		float weave=sin(uv.x*2900.0)*sin(uv.y*2300.0);
		float fleck=step(0.88,hash(floor(uv*vec2(95.0,72.0))));
		col *= 0.97 + detail*(grain-0.5)*0.10 + detail*weave*0.022;
		col=mix(col,color.rgb*1.28,fleck*detail*0.25);
		ROUGHNESS=0.93; SPECULAR=0.18;
	} else {
		float wear=exp(-pow(pos.x/0.44,2.0));
		col *= 0.97+(noise(uv*8.0)-0.5)*0.045+detail*(grain-0.5)*0.12+wear*0.025;
		ROUGHNESS=0.93-wear*0.035; SPECULAR=0.20;
	}
	ALBEDO=col;
}
"""
var _bus_finish_shader: Shader
var _bus_finish_fabric: ShaderMaterial
var _bus_finish_glass: StandardMaterial3D
var _bus_finish_shapes := {}


func _bus_finish_surface(n: Node, fabric: bool) -> void:
	if _bus_finish_shader == null:
		_bus_finish_shader = Shader.new()
		_bus_finish_shader.code = _BUS_FINISH_SHADER
	var mat: ShaderMaterial
	if fabric and _bus_finish_fabric != null:
		mat = _bus_finish_fabric
	else:
		mat = ShaderMaterial.new()
		mat.shader = _bus_finish_shader
		mat.set_shader_parameter("fabric", fabric)
		mat.set_shader_parameter("color", Color(0.13,0.25,0.42) if fabric else Color(0.27,0.285,0.29))
		if fabric:
			_bus_finish_fabric = mat
	_mesh_of(n).material_override = mat
	_bus_finish_soften(n, 0.022, fabric)


func _bus_finish_window(n: Node) -> void:
	if _bus_finish_glass == null:
		_bus_finish_glass = StandardMaterial3D.new()
		_bus_finish_glass.albedo_color = Color(0.67,0.79,0.84,0.12)
		_bus_finish_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bus_finish_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bus_finish_glass.roughness = 0.12
		_bus_finish_glass.metallic = 0.0
		_bus_finish_glass.metallic_specular = 0.5
	var mi := _mesh_of(n)
	mi.material_override = _bus_finish_glass
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Projection sur une boîte à coins ronds, normales analytiques et maillage partagé.
# On change uniquement le mesh, jamais la CollisionShape3D de Build.box.
func _bus_finish_soften(n: Node, radius: float, cushion: bool = false) -> void:
	var mi := _mesh_of(n)
	if mi == null or not mi.mesh is BoxMesh:
		return
	var size := (mi.mesh as BoxMesh).size
	var r := minf(radius, minf(size.x,minf(size.y,size.z))*0.40)
	var bend := cushion and size.y > 0.3 and size.z < 0.1
	var key := str(size, ":", r, ":", bend)
	if _bus_finish_shapes.has(key):
		mi.mesh = _bus_finish_shapes[key]
		return
	var h := size*0.5
	var core := h-Vector3.ONE*r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis+1)%3
		var v := (axis+2)%3
		var us := [-h[u],-h[u]+r*0.25,-h[u]+r*0.5,-core[u],0.0,core[u],h[u]-r*0.5,h[u]-r*0.25,h[u]]
		var vs := [-h[v],-h[v]+r*0.25,-h[v]+r*0.5,-core[v],0.0,core[v],h[v]-r*0.5,h[v]-r*0.25,h[v]]
		for side in [-1.0,1.0]:
			for row in 8:
				for col in 8:
					var corners: Array[Vector3] = []
					var normals: Array[Vector3] = []
					for ij in [Vector2i(col,row),Vector2i(col+1,row),Vector2i(col+1,row+1),Vector2i(col,row+1)]:
						var p := Vector3.ZERO
						p[axis]=side*h[axis]; p[u]=us[ij.x]; p[v]=vs[ij.y]
						var q := p.clamp(-core,core)
						var normal := (p-q).normalized()
						p=q+normal*r
						if bend:
							var x := p.x/h.x
							var y := p.y/h.y
							p.z += 0.008*(1.0-x*x)*(1.0-y*y)
							normal=Vector3(normal.x+normal.z*0.016*x/h.x*(1.0-y*y),normal.y+normal.z*0.016*y/h.y*(1.0-x*x),normal.z).normalized()
						corners.append(p); normals.append(normal)
					var order := [0,2,1,0,3,2] if side > 0 else [0,1,2,0,2,3]
					for k in order:
						st.set_normal(normals[k]); st.set_uv(Vector2(corners[k][u],corners[k][v])); st.add_vertex(corners[k])
	st.index()
	var mesh := st.commit()
	_bus_finish_shapes[key]=mesh
	mi.mesh=mesh


func _bus_finish_door(door: Node3D) -> void:
	_bus_finish_window(door)
	var rubber := Color(0.075,0.085,0.095)
	for z in [-0.282,0.282]:
		_bus_finish_soften(Build.box(door,Vector3(0.075,1.98,0.034),Vector3(0,0,z),rubber,false,0.73),0.006)
	for y in [-0.965,0.965,-0.42]:
		_bus_finish_soften(Build.box(door,Vector3(0.075,0.038,0.57),Vector3(0,y,0),rubber,false,0.73),0.006)
	_bus_finish_soften(Build.box(door,Vector3(0.067,0.51,0.53),Vector3(0,-0.70,0),Color(0.25,0.28,0.30),false,0.6),0.012)


func _bus_finish_wheel() -> void:
	var root := Node3D.new()
	root.name = "VolantDetail"
	root.position = Vector3(-0.75,1.05,-5.6)
	root.rotation_degrees.x = 60
	add_child(root)
	var mi := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius=0.163; ring.outer_radius=0.20
	ring.rings=32; ring.ring_segments=10
	mi.mesh=ring
	mi.material_override=Build.mat(Color(0.08,0.085,0.09),0.73)
	root.add_child(mi)
	Build.cylinder(root,0.054,0.034,Vector3.ZERO,Color(0.15,0.16,0.17))
	for i in 3:
		var a := TAU*float(i)/3.0
		var tip := Vector3(cos(a),0,sin(a))*0.17
		var rod := Build.cylinder(root,0.013,tip.length(),tip*0.5,Color(0.16,0.17,0.18))
		rod.quaternion=Quaternion(Vector3.UP,tip.normalized())


func _bus_finish_dashboard() -> void:
	var screen := Build.box(self,Vector3(0.33,0.10,0.007),Vector3(-0.75,0.98,-5.805),Color(0.035,0.08,0.09),false)
	_glow(screen,Color(0.045,0.15,0.16),0.24)
	_bus_finish_soften(screen,0.003)
	for i in 3:
		var bar := Build.box(self,Vector3(0.048,0.008,0.003),Vector3(-0.85+i*0.10,0.984,-5.800),Color(0.47,0.72,0.65),false)
		_glow(bar,Color(0.47,0.72,0.65),0.32)
	for i in 5:
		_bus_finish_soften(Build.box(self,Vector3(0.025,0.017,0.008),Vector3(-0.91+i*0.08,0.89,-5.804),Color(0.2,0.23,0.25),false),0.004)
