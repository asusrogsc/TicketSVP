extends Node3D
## Gare du terminus : temps libre, PNJ qui attendent le bus retour, rapport au chef de gare.
## Le rapport signé ouvre la porte du bus retour ; les passagers du quai montent avec toi.

const QUALITY_HIGH := true          # passe à false si le PC rame
const WAIT_NORMAL_MIN := 8          # passagers ordinaires sur le quai
const WAIT_NORMAL_MAX := 12
const WAIT_SPECIAL_MIN := 2         # personnages spéciaux sur le quai
const WAIT_SPECIAL_MAX := 3
const WAIT_LINES := [
	"J'attends le bus pour %s.",
	"Il part quand, le prochain ?",
	"Toujours en retard, ce bus...",
	"Vous êtes le contrôleur ? Bon courage !",
	"Enfin une pause, j'ai mal aux pieds.",
	"Il fait bon aujourd'hui, hein ?",
]

var player: Player
var hud: Hud
var menu: CanvasLayer
var rng := RandomNumberGenerator.new()
var line: Dictionary                # ligne de l'aller
var back_line: Dictionary           # même ligne, sens retour
var waiting: Array[Passenger] = []
var report_done := false
var bus_door: Interactable
var board_label: Label3D


func _ready() -> void:
	rng.randomize()
	line = Game.selected_line if not Game.selected_line.is_empty() else Game.lines[0]
	back_line = Game.reversed_line(line)

	Build.environment(self, Color(0.35, 0.5, 0.8), Color(0.75, 0.8, 0.9), 0.5, 1.0)
	_setup_rendering()
	_build_station()
	_build_backdrop()
	_build_chef()
	_build_parked_bus()
	_spawn_waiting()

	hud = Hud.new()
	add_child(hud)
	player = Player.new()
	player.position = Vector3(0, 0.05, 17.0)
	player.hud = hud
	add_child(player)
	player.interacted.connect(_on_interact)
	_update_info()
	hud.show_toast("Terminus %s — Va faire ton rapport au chef de gare" % line.to, Color(1, 0.95, 0.7), 6.0)


func _update_info() -> void:
	hud.set_info("Gare — %s (terminus)   |   Score aller : %d   |   Rapport : %s   |   Sur le quai : %d" % [
		line.to, int(Game.aller_result.get("score", 0)), "signé ✔" if report_done else "à faire", waiting.size()])


# ------------------------------------------------------------------ décor

func _build_station() -> void:
	var steel := Color(0.24, 0.27, 0.32)

	# sol : pelouse, voie des bus, trottoir d'en face, quai (surface du quai à y = 0)
	_tiles(Build.box(self, Vector3(160, 0.1, 160), Vector3(0, -0.45, 0), Color.WHITE, false),
		Vector2(1.5, 1.5), 0.0, 0.0, Color(0.3, 0.5, 0.26), Color.BLACK, 0.06, 0.35, 1.0)
	_tiles(Build.box(self, Vector3(8, 0.1, 80), Vector3(8, -0.35, 0), Color.WHITE), 
		Vector2(4, 4), 0.0, 0.0, Color(0.21, 0.21, 0.23), Color.BLACK, 0.0, 0.5, 0.92)
	_tiles(Build.box(self, Vector3(3, 0.25, 80), Vector3(13.5, -0.2, 0), Color.WHITE),
		Vector2(0.6, 0.6), 0.0, 0.012, Color(0.62, 0.61, 0.58), Color(0.42, 0.41, 0.4), 0.1, 0.25, 0.9)
	_tiles(Build.box(self, Vector3(8.5, 0.3, 40), Vector3(-0.25, -0.15, 0), Color.WHITE),
		Vector2(0.5, 0.5), 0.0, 0.01, Color(0.7, 0.69, 0.66), Color(0.45, 0.44, 0.42), 0.12, 0.2, 0.85)
	# bord du quai : bande podotactile jaune (picots) + bordure béton
	_tiles(Build.box(self, Vector3(0.45, 0.012, 40), Vector3(3.55, 0.006, 0), Color.WHITE, false),
		Vector2(0.06, 0.06), 0.0, 0.015, Color(0.95, 0.78, 0.08), Color(0.7, 0.55, 0.05), 0.05, 0.1, 0.7)
	_rough(Build.box(self, Vector3(0.15, 0.32, 40), Vector3(3.95, -0.15, 0), Color(0.82, 0.82, 0.8), false), 0.8)
	# marquage de la voie : ligne d'arrêt « BUS » + pointillés
	for z in range(-36, 37, 6):
		Build.box(self, Vector3(0.15, 0.01, 3), Vector3(10.6, -0.295, z), Color(0.95, 0.95, 0.9), false)
	Build.box(self, Vector3(0.15, 0.01, 18), Vector3(4.6, -0.295, 0), Color(0.95, 0.8, 0.1), false)
	var bus_mark := Build.label3d(self, "BUS", Vector3(7.6, -0.29, -9.5), 200, Color(0.95, 0.95, 0.9))
	bus_mark.rotation_degrees = Vector3(-90, 0, 0)
	bus_mark.pixel_size = 0.008

	_build_station_building()

	# marquise : toit, sous-face claire, chéneau, poteaux sur platines
	_metal(Build.box(self, Vector3(8.4, 0.12, 32), Vector3(-0.6, 3.78, 0), Color(0.2, 0.24, 0.32), false), 0.5, null, 0.6)
	_rough(Build.box(self, Vector3(8.2, 0.03, 31.8), Vector3(-0.6, 3.705, 0), Color(0.86, 0.87, 0.88), false), 0.6)
	_metal(Build.box(self, Vector3(0.18, 0.35, 32.2), Vector3(3.55, 3.62, 0), steel, false), 0.4)
	for z in range(-15, 16, 6):
		for x in [-3.6, 2.9]:
			_metal(Build.cylinder(self, 0.11, 3.7, Vector3(x, 1.85, z), steel), 0.35)
			_metal(Build.box(self, Vector3(0.4, 0.03, 0.4), Vector3(x, 0.015, z), steel.darkened(0.2), false), 0.4)
			_metal(Build.box(self, Vector3(0.08, 0.5, 0.08), Vector3(x, 3.45, z), steel, false), 0.35)
		# poutre transversale
		_metal(Build.box(self, Vector3(6.6, 0.2, 0.12), Vector3(-0.35, 3.6, z), steel, false), 0.35)
	for z in [-12, -4, 4, 12]:
		var lamp := Build.box(self, Vector3(0.25, 0.04, 2.0), Vector3(-0.6, 3.67, z), Color(1, 1, 0.97), false)
		_glow(lamp, Color(1, 0.96, 0.9), 2.5)
		var o := Build.light(self, Vector3(-0.6, 3.3, z), Color(1, 0.94, 0.86), 0.9, 10.0)
		o.shadow_enabled = QUALITY_HIGH

	# panneau des départs suspendu (lisible)
	_metal(Build.box(self, Vector3(3.4, 1.0, 0.12), Vector3(0, 2.85, 6), Color(0.04, 0.04, 0.05), false), 0.35)
	_glow(Build.box(self, Vector3(3.2, 0.82, 0.01), Vector3(0, 2.85, 6.065), Color(0.02, 0.02, 0.03), false), Color(0.02, 0.02, 0.04), 0.3)
	for x in [-1.4, 1.4]:
		_metal(Build.cylinder(self, 0.015, 0.5, Vector3(x, 3.45, 6), steel), 0.4)
	board_label = Build.label3d(self, "", Vector3(0, 2.85, 6.08), 44, Color(1, 0.68, 0.15))
	board_label.pixel_size = 0.0032
	board_label.line_spacing = 4
	_update_board()

	# panneau « QUAI 1 » suspendu
	_glow(Build.box(self, Vector3(1.4, 0.4, 0.06), Vector3(1.6, 3.2, -6), Color(0.1, 0.3, 0.65), false), Color(0.1, 0.3, 0.65), 0.4)
	for k in [-1, 1]:
		var q := Build.label3d(self, "QUAI 1", Vector3(1.6, 3.2, -6 + k * 0.035), 60, Color.WHITE)
		q.rotation_degrees.y = 0 if k > 0 else 180

	# horloge suspendue à double face
	_metal(Build.cylinder(self, 0.015, 0.4, Vector3(-0.6, 3.5, -3), steel), 0.4)
	var face := Build.cylinder(self, 0.32, 0.08, Vector3(-0.6, 3.05, -3), Color(0.97, 0.97, 0.95))
	face.rotation_degrees.x = 90
	_glow(face, Color(1, 1, 0.97), 0.4)
	var t := Time.get_time_dict_from_system()
	for k in [-1, 1]:
		var lc := Build.label3d(self, "%02d:%02d" % [t.hour, t.minute], Vector3(-0.6, 3.05, -3 + k * 0.045), 56, Color(0.08, 0.08, 0.1))
		lc.rotation_degrees.y = 0 if k > 0 else 180

	# mobilier : bancs, abris vitrés, automate, distributeur, plan du réseau, bacs à fleurs, vélos
	for z in [-12.0, -6.0, 3.0, 8.0]:
		_bench(Vector3(-3.0, 0, z))
	for z in [-9.0, 5.5]:
		_windscreen(Vector3(-2.6, 0, z))
	_ticket_machine(Vector3(-4.1, 0, 2.2))
	_vending_machine(Vector3(-4.05, 0, -2.4))
	_map_panel(Vector3(-4.42, 1.6, -15.0))
	for z in [-17.5, 15.5]:
		_planter(Vector3(-3.6, 0, z))
	_bike_rack(Vector3(-3.4, 0, -18.5))

	# bureau du chef de gare (kiosque)
	_tiles(Build.box(self, Vector3(2.0, 2.6, 2.6), Vector3(-3.4, 1.3, 12.5), Color.WHITE),
		Vector2(0.3, 0.3), 0.0, 0.006, Color(0.92, 0.88, 0.78), Color(0.8, 0.76, 0.68), 0.04, 0.15, 0.85)
	_metal(Build.box(self, Vector3(2.4, 0.1, 3.0), Vector3(-3.3, 2.65, 12.5), Color(0.2, 0.24, 0.32), false), 0.45, null, 0.6)
	Build.box(self, Vector3(0.06, 1.15, 1.75), Vector3(-2.39, 1.5, 12.5), Color(0.9, 0.9, 0.88), false)   # cadre
	var win := Build.box(self, Vector3(0.05, 1.0, 1.6), Vector3(-2.37, 1.5, 12.5), Color(1, 0.9, 0.7), false)
	_glow(win, Color(1, 0.88, 0.65), 0.9)
	_rough(Build.box(self, Vector3(0.3, 0.05, 1.7), Vector3(-2.3, 0.97, 12.5), Color(0.5, 0.33, 0.18), false), 0.5)  # comptoir
	var ks := Build.label3d(self, "CHEF DE GARE", Vector3(-2.36, 2.3, 12.5), 44, Color(0.12, 0.18, 0.45))
	ks.rotation_degrees.y = 90


func _build_station_building() -> void:
	var brick := Color(0.6, 0.33, 0.25)
	# corps du bâtiment (2 niveaux) en briques, socle en pierre, corniche
	_tiles(Build.box(self, Vector3(10, 8, 40), Vector3(-9.5, 3.85, 0), Color.WHITE),
		Vector2(0.24, 0.075), 0.5, 0.012, brick, Color(0.8, 0.76, 0.7), 0.3, 0.12, 0.9)
	_tiles(Build.box(self, Vector3(0.1, 0.7, 40), Vector3(-4.50, 0.35, 0), Color.WHITE, false),
		Vector2(0.6, 0.35), 0.5, 0.01, Color(0.72, 0.7, 0.66), Color(0.55, 0.53, 0.5), 0.08, 0.2, 0.9)
	_rough(Build.box(self, Vector3(10.6, 0.45, 40.6), Vector3(-9.5, 7.9, 0), Color(0.88, 0.85, 0.8), false), 0.8)
	_rough(Build.box(self, Vector3(0.25, 0.15, 40), Vector3(-4.41, 4.0, 0), Color(0.88, 0.85, 0.8), false), 0.8)   # bandeau d'étage
	# fenêtres : rez-de-chaussée (sous la marquise) et étage
	for z in range(-17, 18, 4):
		if abs(z) >= 2:
			_window(Vector3(-4.47, 2.2, z), Vector2(1.4, 1.7), rng.randf() < 0.45)
		_window(Vector3(-4.47, 5.6, z), Vector2(1.1, 1.5), rng.randf() < 0.3)
	# entrée principale vitrée + auvent
	Build.box(self, Vector3(0.08, 2.9, 2.7), Vector3(-4.48, 1.45, 0), Color(0.88, 0.85, 0.8), false)
	var entry := Build.box(self, Vector3(0.05, 2.6, 2.4), Vector3(-4.43, 1.3, 0), Color(1, 0.9, 0.7), false)
	_glow(entry, Color(1, 0.88, 0.65), 1.0)
	Build.box(self, Vector3(0.06, 2.6, 0.05), Vector3(-4.41, 1.3, 0), Color(0.2, 0.2, 0.22), false)   # séparation des portes
	# enseigne et grande horloge de façade
	var sign_l := Build.label3d(self, "GARE — " + str(line.to).to_upper(), Vector3(-4.38, 6.95, 0), 120, Color(1, 1, 1))
	sign_l.rotation_degrees.y = 90
	sign_l.pixel_size = 0.006
	var clock := Build.cylinder(self, 0.5, 0.1, Vector3(-4.43, 5.6, 0), Color(0.97, 0.96, 0.92))
	clock.rotation_degrees.z = 90
	_glow(clock, Color(1, 0.98, 0.9), 0.5)
	var rim := Build.cylinder(self, 0.54, 0.06, Vector3(-4.46, 5.6, 0), Color(0.15, 0.15, 0.17))
	rim.rotation_degrees.z = 90
	_metal(rim, 0.4)
	var t := Time.get_time_dict_from_system()
	var ha := deg_to_rad((t.hour % 12) * 30.0 + t.minute * 0.5)
	var ma := deg_to_rad(t.minute * 6.0)
	for hand in [[ha, 0.28, 0.04], [ma, 0.42, 0.025]]:
		var h := Build.box(self, Vector3(0.02, hand[1], hand[2]), Vector3.ZERO, Color(0.08, 0.08, 0.1), false)
		h.rotation = Vector3(-hand[0], 0, 0)
		h.position = Vector3(-4.37, 5.6, 0) + Vector3(0, cos(hand[0]), -sin(hand[0])) * hand[1] * 0.5


func _window(at: Vector3, size: Vector2, lit: bool) -> void:
	Build.box(self, Vector3(0.06, size.y + 0.2, size.x + 0.2), at, Color(0.9, 0.88, 0.84), false)                # cadre
	var g := Build.box(self, Vector3(0.05, size.y, size.x), at + Vector3(0.02, 0, 0), Color(0.45, 0.58, 0.72), false)
	if lit:
		_glow(g, Color(1, 0.86, 0.62), 0.7)
	else:
		_metal(g, 0.06, Color(0.4, 0.52, 0.66), 0.4)
	Build.box(self, Vector3(0.07, 0.04, size.x), at + Vector3(0.03, 0, 0), Color(0.9, 0.88, 0.84), false)        # traverse
	Build.box(self, Vector3(0.22, 0.07, size.x + 0.3), at + Vector3(0.08, -size.y / 2 - 0.1, 0), Color(0.86, 0.84, 0.8), false)  # appui


func _bench(at: Vector3) -> void:
	var wood := Color(0.52, 0.34, 0.18)
	for k in 3:
		_rough(Build.box(self, Vector3(0.12, 0.04, 1.8), at + Vector3(-0.12 + k * 0.12, 0.45, 0), wood, false), 0.55)
	for k in 2:
		_rough(Build.box(self, Vector3(0.04, 0.12, 1.8), at + Vector3(-0.24, 0.62 + k * 0.16, 0), wood, false), 0.55)
	for dz in [-0.8, 0.8]:
		_metal(Build.box(self, Vector3(0.45, 0.45, 0.05), at + Vector3(-0.05, 0.22, dz), Color(0.15, 0.15, 0.17), false), 0.45)
		_metal(Build.box(self, Vector3(0.05, 0.4, 0.05), at + Vector3(-0.25, 0.62, dz), Color(0.15, 0.15, 0.17), false), 0.45)
	_metal(Build.cylinder(self, 0.2, 0.75, at + Vector3(0, 0.375, 1.3), Color(0.12, 0.32, 0.2)), 0.5)
	_metal(Build.cylinder(self, 0.21, 0.04, at + Vector3(0, 0.76, 1.3), Color(0.1, 0.1, 0.11)), 0.5)


func _windscreen(at: Vector3) -> void:
	var steel := Color(0.24, 0.27, 0.32)
	var g := Build.box(self, Vector3(1.6, 2.1, 0.03), at + Vector3(0, 1.15, 0), Color(0.75, 0.88, 0.95, 0.22))
	_metal(g, 0.05, Color(0.75, 0.88, 0.95, 0.22), 0.2)
	for x in [-0.8, 0.8]:
		_metal(Build.box(self, Vector3(0.05, 2.2, 0.06), at + Vector3(x, 1.1, 0), steel, false), 0.35)
	_metal(Build.box(self, Vector3(1.65, 0.05, 0.06), at + Vector3(0, 2.22, 0), steel, false), 0.35)


func _ticket_machine(at: Vector3) -> void:
	_metal(Build.box(self, Vector3(0.6, 1.7, 0.75), at + Vector3(0, 0.85, 0), Color(0.12, 0.3, 0.6)), 0.4, null, 0.5)
	_glow(Build.box(self, Vector3(0.02, 0.4, 0.5), at + Vector3(0.31, 1.3, 0), Color(0.3, 0.7, 1.0), false), Color(0.35, 0.75, 1.0), 1.2)
	Build.box(self, Vector3(0.05, 0.12, 0.3), at + Vector3(0.32, 0.9, 0), Color(0.08, 0.08, 0.1), false)
	var l := Build.label3d(self, "TICKETS", Vector3(at.x + 0.33, 1.6, at.z), 30, Color.WHITE)
	l.rotation_degrees.y = 90


func _vending_machine(at: Vector3) -> void:
	_metal(Build.box(self, Vector3(0.8, 1.9, 1.0), at + Vector3(0, 0.95, 0), Color(0.75, 0.12, 0.12)), 0.4, null, 0.4)
	_glow(Build.box(self, Vector3(0.02, 1.2, 0.65), at + Vector3(0.41, 1.15, -0.1), Color(0.95, 0.95, 0.9), false), Color(1, 0.97, 0.9), 1.0)
	for r in 4:
		for c in 4:
			Build.box(self, Vector3(0.03, 0.12, 0.08), at + Vector3(0.42, 0.7 + r * 0.28, -0.35 + c * 0.17),
				Color.from_hsv(fmod(r * 0.23 + c * 0.17, 1.0), 0.7, 0.85), false)


func _map_panel(at: Vector3) -> void:
	Build.box(self, Vector3(0.08, 1.3, 2.0), at, Color(0.2, 0.22, 0.25), false)
	_glow(Build.box(self, Vector3(0.02, 1.15, 1.85), at + Vector3(0.05, 0, 0), Color(0.96, 0.96, 0.94), false), Color(1, 1, 0.97), 0.35)
	Build.box(self, Vector3(0.03, 0.04, 1.5), at + Vector3(0.07, 0.1, 0), line.color, false)
	Build.box(self, Vector3(0.03, 0.04, 1.2), at + Vector3(0.07, -0.25, 0.1), Color(0.9, 0.35, 0.2), false)
	for k in 5:
		Build.box(self, Vector3(0.035, 0.09, 0.09), at + Vector3(0.075, 0.1, -0.7 + k * 0.35), Color.WHITE, false)
	var l := Build.label3d(self, "PLAN DU RÉSEAU", Vector3(at.x + 0.08, at.y + 0.45, at.z), 34, Color(0.1, 0.12, 0.2))
	l.rotation_degrees.y = 90


func _planter(at: Vector3) -> void:
	_rough(Build.box(self, Vector3(0.9, 0.55, 0.9), at + Vector3(0, 0.275, 0), Color(0.55, 0.55, 0.53)), 0.9)
	Build.box(self, Vector3(0.8, 0.02, 0.8), at + Vector3(0, 0.56, 0), Color(0.25, 0.18, 0.12), false)
	for k in 5:
		var leaves := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.18, 0.28)
		sm.height = sm.radius * 1.7
		leaves.mesh = sm
		leaves.material_override = Build.mat(Color(0.2, 0.42 + 0.05 * k, 0.2), 1.0)
		leaves.position = at + Vector3(rng.randf_range(-0.25, 0.25), 0.75 + rng.randf() * 0.25, rng.randf_range(-0.25, 0.25))
		add_child(leaves)


func _bike_rack(at: Vector3) -> void:
	for k in 4:
		var hoop := Build.cylinder(self, 0.02, 0.7, at + Vector3(0, 0.35, -0.6 + k * 0.4), Color(0.6, 0.62, 0.65))
		_metal(hoop, 0.3)
		_metal(Build.cylinder(self, 0.02, 0.7, at + Vector3(0.5, 0.35, -0.6 + k * 0.4), Color(0.6, 0.62, 0.65)), 0.3)
		_metal(Build.box(self, Vector3(0.5, 0.04, 0.04), at + Vector3(0.25, 0.7, -0.6 + k * 0.4), Color(0.6, 0.62, 0.65), false), 0.3)


## Le quartier en face de la gare : trottoir, lampadaires, arbres, immeubles.
func _build_backdrop() -> void:
	var z := -40.0
	while z < 40:
		var w := rng.randf_range(8, 14)
		var h := rng.randf_range(7, 20)
		var col := Color.from_hsv(rng.randf_range(0.03, 0.13), rng.randf_range(0.1, 0.3), rng.randf_range(0.6, 0.88))
		var b := Node3D.new()
		b.position = Vector3(rng.randf_range(21, 24), -0.3, z + w / 2)
		add_child(b)
		_tiles(Build.box(b, Vector3(10, h, w * 0.92), Vector3(0, h / 2, 0), Color.WHITE, false),
			Vector2(0.24, 0.075), 0.5, 0.0, col, col, 0.08, 0.15, 0.9)
		_rough(Build.box(b, Vector3(10.4, 0.35, w * 0.92 + 0.3), Vector3(0, h + 0.17, 0), col.darkened(0.3), false), 0.85)
		var fy := 2.2
		var cols := maxi(int(w * 0.92 / 2.2), 1)
		while fy < h - 1.2:
			for c in cols:
				var wz := -w * 0.46 + (c + 0.5) * w * 0.92 / cols
				Build.box(b, Vector3(0.06, 1.25, 1.05), Vector3(-5.02, fy, wz), Color(0.92, 0.9, 0.86), false)
				var g := Build.box(b, Vector3(0.06, 1.1, 0.9), Vector3(-5.05, fy, wz), Color(0.42, 0.55, 0.7), false)
				if rng.randf() < 0.2:
					_glow(g, Color(1, 0.86, 0.6), 0.5)
				else:
					_metal(g, 0.06, Color(0.42, 0.55, 0.7), 0.4)
			fy += 3.0
		z += w
	# lampadaires et arbres le long du trottoir d'en face
	for lz in range(-36, 37, 12):
		var pole := Node3D.new()
		pole.position = Vector3(12.6, -0.1, lz)
		add_child(pole)
		_metal(Build.cylinder(pole, 0.06, 6, Vector3(0, 3, 0), Color(0.22, 0.24, 0.27)), 0.4)
		_metal(Build.box(pole, Vector3(1.3, 0.08, 0.12), Vector3(-0.6, 5.95, 0), Color(0.22, 0.24, 0.27), false), 0.4)
		_glow(Build.box(pole, Vector3(0.5, 0.1, 0.25), Vector3(-1.15, 5.88, 0), Color(1, 0.95, 0.8), false), Color(1, 0.93, 0.78), 1.2)
		var tree := Node3D.new()
		tree.position = Vector3(14.2, -0.1, lz + 6)
		add_child(tree)
		_rough(Build.cylinder(tree, 0.15, 2.4, Vector3(0, 1.2, 0), Color(0.36, 0.25, 0.15)), 1.0)
		for k in 4:
			var leaves := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(0.9, 1.25)
			sm.height = sm.radius * 1.8
			leaves.mesh = sm
			leaves.material_override = Build.mat(Color(0.22, 0.48 + rng.randf() * 0.1, 0.22).darkened(k * 0.05), 1.0)
			leaves.position = Vector3(rng.randf_range(-0.5, 0.5), 2.8 + rng.randf_range(-0.2, 0.7), rng.randf_range(-0.5, 0.5))
			tree.add_child(leaves)


func _build_parked_bus() -> void:
	# le bus du retour, garé le long du quai, avant tourné vers l'arrivée du joueur (+Z), portes côté quai (-X)
	var body: Color = line.color
	var bx := 5.6
	var root := Node3D.new()
	root.position = Vector3(bx, -0.3, 0)
	add_child(root)
	var L := 12.0; var W := 2.5; var H := 3.0
	var glass := Color(0.12, 0.16, 0.2)
	# caisse : jupe sombre, corps couleur ligne, toit blanc, bandeau de livrée
	Build.box(root, Vector3(W, 0.45, L), Vector3(0, 0.55, 0), Color(0.15, 0.15, 0.17), true)
	_metal(Build.box(root, Vector3(W, 1.1, L), Vector3(0, 1.32, 0), body), 0.3, null, 0.3)
	_metal(Build.box(root, Vector3(W - 0.02, 0.35, L - 0.02), Vector3(0, 2.8, 0), Color(0.93, 0.93, 0.92), false), 0.35, null, 0.2)
	_metal(Build.box(root, Vector3(W + 0.01, 0.12, L - 1), Vector3(0, 0.95, -0.3), Color.WHITE, false), 0.3, null, 0.3)
	Build.box(root, Vector3(W - 0.06, 0.85, L - 0.06), Vector3(0, 2.25, 0), Color(0.05, 0.06, 0.07), false)   # intérieur sombre
	# vitres latérales teintées avec montants
	for side in [-1, 1]:
		_metal(Build.box(root, Vector3(0.04, 0.95, L - 0.6), Vector3(side * (W / 2), 2.15, 0), glass, false), 0.05, glass, 0.6)
		var mz := -L / 2 + 0.6
		while mz < L / 2 - 0.5:
			Build.box(root, Vector3(0.06, 0.95, 0.08), Vector3(side * (W / 2 + 0.01), 2.15, mz), Color(0.08, 0.08, 0.09), false)
			mz += 1.6
	# pare-brise (avant, +Z), lunette arrière, pare-chocs, phares, feux
	_metal(Build.box(root, Vector3(W - 0.15, 1.5, 0.04), Vector3(0, 2.0, L / 2 + 0.01), glass, false), 0.04, glass, 0.6)
	_metal(Build.box(root, Vector3(W - 0.5, 0.7, 0.04), Vector3(0, 2.3, -L / 2 - 0.01), glass, false), 0.05, glass, 0.6)
	for zz in [L / 2 + 0.06, -L / 2 - 0.06]:
		_metal(Build.box(root, Vector3(W + 0.04, 0.3, 0.12), Vector3(0, 0.6, zz), Color(0.12, 0.12, 0.13), false), 0.5)
	for x in [-0.95, 0.95]:
		_glow(Build.box(root, Vector3(0.35, 0.16, 0.04), Vector3(x, 0.95, L / 2 + 0.03), Color(1, 1, 0.95), false), Color(1, 0.98, 0.9), 2.0)
		_glow(Build.box(root, Vector3(0.25, 0.3, 0.04), Vector3(x, 1.0, -L / 2 - 0.03), Color(0.9, 0.1, 0.08), false), Color(1, 0.12, 0.08), 1.2)
	# girouettes lumineuses (avant + côté quai)
	var dest := "%s  %s" % [line.name, back_line.to]
	_glow(Build.box(root, Vector3(W - 0.4, 0.3, 0.03), Vector3(0, 2.9, L / 2 + 0.02), Color(0.05, 0.05, 0.05), false), Color(0.03, 0.02, 0.0), 0.3)
	var front := Build.label3d(root, dest, Vector3(0, 2.9, L / 2 + 0.045), 40, Color(1, 0.65, 0.15))
	front.pixel_size = 0.004
	var side_l := Build.label3d(root, dest, Vector3(-W / 2 - 0.03, 2.85, 3.5), 34, Color(1, 0.65, 0.15))
	side_l.rotation_degrees.y = -90
	# rétroviseur, clim de toit
	_metal(Build.box(root, Vector3(0.35, 0.05, 0.05), Vector3(-W / 2 - 0.15, 2.5, L / 2 - 0.2), Color(0.1, 0.1, 0.1), false), 0.4)
	_metal(Build.box(root, Vector3(0.1, 0.3, 0.2), Vector3(-W / 2 - 0.32, 2.35, L / 2 - 0.2), Color(0.1, 0.1, 0.1), false), 0.3)
	_metal(Build.box(root, Vector3(1.6, 0.3, 2.4), Vector3(0, 3.12, -2.0), Color(0.85, 0.86, 0.87), false), 0.4, null, 0.5)
	# roues dans leurs passages
	for wz in [-3.8, 4.0]:
		for side in [-1, 1]:
			Build.box(root, Vector3(0.05, 0.75, 1.3), Vector3(side * (W / 2 + 0.005), 0.55, wz), Color(0.05, 0.05, 0.05), false)
			var wheel := Build.cylinder(root, 0.48, 0.32, Vector3(side * (W / 2 - 0.12), 0.48, wz), Color(0.07, 0.07, 0.07))
			wheel.rotation_degrees.z = 90
			var hub := Build.cylinder(root, 0.25, 0.34, Vector3(side * (W / 2 - 0.12), 0.48, wz), Color(0.7, 0.72, 0.75))
			hub.rotation_degrees.z = 90
			_metal(hub, 0.3)
	# porte double côté quai (interactive)
	bus_door = Interactable.new()
	bus_door.position = Vector3(bx - W / 2 - 0.02, 1.15, 0.5)
	bus_door.action = _try_board
	add_child(bus_door)
	Build.box(bus_door, Vector3(0.06, 2.3, 1.3), Vector3.ZERO, Color(0.1, 0.1, 0.11))
	for k in [-1, 1]:
		_metal(Build.box(bus_door, Vector3(0.03, 1.9, 0.55), Vector3(-0.03, 0.1, k * 0.3), glass, false), 0.05, glass, 0.6)
	_update_door()


func _update_door() -> void:
	bus_door.label = ("Monter dans le bus retour → " + back_line.to) if report_done \
		else "Bus retour (fais d'abord ton rapport au chef de gare)"


func _update_board() -> void:
	board_label.text = "QUAI 1   ·   %s %s  →  %s\n%s" % [line.type, line.name, back_line.to,
		"Embarquement en cours" if report_done else "Départ après le rapport de service"]


# ------------------------------------------------------------------ chef de gare

func _build_chef() -> void:
	var chef := Interactable.new()
	chef.label = "Faire ton rapport au chef de gare"
	chef.action = _open_report
	chef.position = Vector3(-1.7, 0, 12.5)
	chef.rotation_degrees.y = 180          # regarde vers l'arrivée du joueur
	add_child(chef)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	chef.add_child(col)
	var uniform := Color(0.12, 0.16, 0.32)
	var skin := Color(0.92, 0.76, 0.64)
	Build.box(chef, Vector3(0.34, 0.85, 0.22), Vector3(0, 0.43, 0), uniform.darkened(0.3), false)     # jambes
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.21
	tm.height = 0.75
	torso.mesh = tm
	torso.material_override = Build.mat(uniform)
	torso.position.y = 1.18
	chef.add_child(torso)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.27
	head.mesh = hm
	head.material_override = Build.mat(skin)
	head.position.y = 1.68
	chef.add_child(head)
	Build.cylinder(chef, 0.15, 0.09, Vector3(0, 1.81, 0), uniform)                                  # casquette
	Build.cylinder(chef, 0.152, 0.03, Vector3(0, 1.78, 0), Color(0.8, 0.12, 0.12))                  # bandeau rouge
	Build.box(chef, Vector3(0.2, 0.015, 0.12), Vector3(0, 1.765, -0.15), Color(0.05, 0.05, 0.05), false)  # visière
	Build.box(chef, Vector3(0.1, 0.025, 0.01), Vector3(0, 1.62, -0.128), Color(0.55, 0.55, 0.55), false)  # moustache
	for side in [-1, 1]:
		Build.box(chef, Vector3(0.03, 0.03, 0.01), Vector3(0.045 * side, 1.7, -0.127), Color(0.05, 0.05, 0.05), false)
	_metal(Build.box(chef, Vector3(0.06, 0.06, 0.01), Vector3(0.1, 1.35, -0.21), Color(0.95, 0.8, 0.3), false), 0.3)  # insigne
	var tag := Build.label3d(chef, "Chef de gare", Vector3(0, 2.1, 0), 32, Color(1, 0.9, 0.6))
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _chef_comment(r: Dictionary) -> String:
	var score := int(r.get("score", 0))
	var missed := int(r.get("fraudes_laissees", 0)) + int(r.get("fraudeurs_partis", 0))
	if r.is_empty():
		return "« Pas de rapport ? Bon, on fera sans pour cette fois. »"
	if score >= 60:
		return "« Excellent travail ! La direction va entendre parler de toi. »"
	if score >= 20:
		return "« Du bon boulot. Continue comme ça au retour. »"
	if int(r.get("erreurs_amende", 0)) >= 2:
		return "« Trop d'amendes injustes... J'ai déjà deux réclamations sur le bureau. »"
	if missed >= 3:
		return "« Beaucoup de resquilleurs passés entre les mailles. Ouvre l'œil au retour. »"
	return "« Hmm. Ça peut aller. On attend mieux au retour. »"


func _open_report() -> void:
	if menu:
		return
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = CanvasLayer.new()
	add_child(menu)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var r: Dictionary = Game.aller_result
	_l(box, "Rapport de service — aller", 30, Color(1, 0.9, 0.6))
	_l(box, "%s %s : %s → %s" % [line.type, line.name, line.from, line.to], 18, Color(0.8, 0.85, 0.95))
	_l(box, " ", 6)
	_l(box, "Passagers transportés : %d" % r.get("passagers", 0), 20)
	_l(box, "Contrôles : %d  (dont %d corrects)" % [r.get("controles", 0), r.get("justes", 0)], 20)
	_l(box, "Amendes justifiées : %d  (%d €)" % [r.get("amendes", 0), r.get("amendes_euros", 0)], 20, Color(0.5, 1, 0.55))
	_l(box, "Amendes injustes : %d" % r.get("erreurs_amende", 0), 20, Color(1, 0.55, 0.5))
	_l(box, "Fraudeurs laissés passer : %d" % r.get("fraudes_laissees", 0), 20, Color(1, 0.55, 0.5))
	_l(box, "Fraudeurs descendus sans contrôle : %d" % r.get("fraudeurs_partis", 0), 20, Color(1, 0.7, 0.5))
	_l(box, "Score de l'aller : %d" % r.get("score", 0), 26, Color(1, 0.95, 0.5))
	_l(box, " ", 6)
	_l(box, "Chef de gare : " + _chef_comment(r), 19, Color(0.85, 0.95, 1))
	if not report_done:
		var sign_btn := Button.new()
		sign_btn.text = "Signer le rapport"
		sign_btn.add_theme_font_size_override("font_size", 22)
		sign_btn.custom_minimum_size.y = 50
		sign_btn.pressed.connect(_sign_report)
		box.add_child(sign_btn)
	var close := Button.new()
	close.text = "Fermer (Échap)"
	close.pressed.connect(_close_menu)
	box.add_child(close)


func _sign_report() -> void:
	report_done = true
	_close_menu()
	_update_door()
	_update_board()
	_update_info()
	hud.show_toast("Chef de gare : « Rapport signé. Ton bus pour %s est à quai, monte quand tu veux ! »" % back_line.to,
		Color(0.7, 1, 0.75), 6.0)


func _try_board() -> void:
	if not report_done:
		hud.show_toast("Fais d'abord ton rapport au chef de gare !", Color(1, 0.8, 0.5))
		return
	player.frozen = true
	hud.show_toast("Embarquement... Les voyageurs du quai montent avec toi.", Color(0.8, 0.95, 1), 3.0)
	var boarders: Array = []
	for p in waiting:
		boarders.append(p.data)
	get_tree().create_timer(1.2).timeout.connect(Game.start_return.bind(boarders))


func _close_menu() -> void:
	if menu:
		menu.queue_free()
		menu = null
	player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _l(parent: Node, t: String, size: int, color := Color.WHITE) -> void:
	var lab := Label.new()
	lab.text = t
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lab)


# ------------------------------------------------------------------ voyageurs qui attendent

func _spawn_waiting() -> void:
	var people: Array = []
	for i in rng.randi_range(WAIT_NORMAL_MIN, WAIT_NORMAL_MAX):
		people.append(People.random_passenger(back_line, rng))
	var sp: Array = People.specials(back_line)
	sp.shuffle()
	for i in mini(rng.randi_range(WAIT_SPECIAL_MIN, WAIT_SPECIAL_MAX), sp.size()):
		people.append(sp[i])
	people.shuffle()

	# places assises sur les bancs (3 par banc) et places debout près du bord du quai
	var bench_spots: Array = []
	for z in [-12.0, -6.0, 3.0, 8.0]:
		for dz in [-0.55, 0.0, 0.55]:
			bench_spots.append(Vector3(-2.98, 0, z + dz))
	bench_spots.shuffle()
	var used_standing: Array = []

	for d in people:
		var seated := bench_spots.size() > 0 and rng.randf() < 0.6
		var pos: Vector3
		if seated:
			pos = bench_spots.pop_back()
		else:
			pos = _free_standing_spot(used_standing)
			used_standing.append(pos)
		var p := Passenger.new()
		p.setup(d)
		p.set_meta("waiting", true)
		p.position = pos
		p.rotation_degrees.y = -90 + (0.0 if seated else rng.randf_range(-25, 25))   # face à la voie
		add_child(p)
		if not seated:
			p.set_seated(false)
		waiting.append(p)


func _free_standing_spot(used: Array) -> Vector3:
	for attempt in 30:
		var c := Vector3(rng.randf_range(0.8, 3.0), 0, rng.randf_range(-15.0, 9.0))
		var ok := true
		for u in used:
			if c.distance_to(u) < 0.9:
				ok = false
				break
		if ok and abs(c.z - 6.0) > 0.6:      # pas sous le panneau des départs
			return c
	return Vector3(rng.randf_range(0.8, 3.0), 0, rng.randf_range(-15.0, 9.0))


func _on_interact(t: Node) -> void:
	if t is Interactable:
		t.interact()
	elif t is Passenger:
		var p: Passenger = t
		var txt: String
		if p.data.get("special", false):
			txt = str(p.data.get("greet", "..."))
		else:
			txt = WAIT_LINES[rng.randi() % WAIT_LINES.size()]
			if "%s" in txt:
				txt = txt % back_line.to
		hud.show_toast("%s : « %s »" % [p.data.get("name", "?"), txt], Color(0.9, 0.95, 1), 3.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and menu:
		_close_menu()


# ------------------------------------------------------------------ rendu

func _setup_rendering() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if QUALITY_HIGH else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true
	for c in find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (c as WorldEnvironment).environment
		if env == null:
			continue
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 6.0
		env.ssao_enabled = true
		env.ssao_radius = 0.8
		env.ssao_intensity = 1.4
		env.ssil_enabled = QUALITY_HIGH
		env.ssil_intensity = 0.6
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_hdr_threshold = 1.1
		env.fog_enabled = true
		env.fog_light_color = Color(0.74, 0.8, 0.9)
		env.fog_density = 0.0035
		env.fog_aerial_perspective = 0.5
		# éclairage global : la lumière du soleil rebondit sous la marquise (fini le dessous tout noir)
		env.sdfgi_enabled = QUALITY_HIGH
		env.sdfgi_use_occlusion = true
		env.sdfgi_energy = 1.2
		env.ambient_light_energy = 0.7
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			sm.sky_top_color = Color(0.3, 0.48, 0.78)
			sm.sky_horizon_color = Color(0.78, 0.82, 0.88)
			sm.sun_angle_max = 20.0
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.05
		env.adjustment_saturation = 1.1
	# soleil d'après-midi, plus chaud et plus rasant (ombres longues)
	for l in find_children("*", "DirectionalLight3D", true, false):
		var sun := l as DirectionalLight3D
		sun.rotation_degrees = Vector3(-38, -55, 0)
		sun.light_color = Color(1, 0.93, 0.8)
		sun.light_energy = 1.25
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 70.0 if QUALITY_HIGH else 35.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if QUALITY_HIGH else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func _mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	var found := n.find_children("*", "MeshInstance3D", true, false)
	return found[0] if found.size() > 0 else null


func _own_mat(n: Node) -> StandardMaterial3D:
	var m := _mesh_of(n)
	if m == null:
		return null
	var mat: StandardMaterial3D = m.material_override.duplicate() if m.material_override is StandardMaterial3D else StandardMaterial3D.new()
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


# ------------------------------------------------------------------ matériau procédural (briques, dalles, asphalte, herbe)

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
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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


func _tiles(n: Node, size: Vector2, stagger: float, grout: float, col: Color, grout_col: Color,
		variation: float, speckle: float, rough: float) -> Node:
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
	m.material_override = mat
	return n
