extends Node3D
## Gare du terminus : temps libre, PNJ qui attendent le bus retour, rapport au chef de gare.
## Le rapport signé ouvre la porte du bus retour ; les passagers du quai montent avec toi.

const QUALITY_HIGH := true          # passe à false si le PC rame
const SOIR := true                  # ambiance fin de journée (soleil couchant, tout s'allume)
const PLUIE := true                 # pluie, sol mouillé et flaques
const BUS_ARRIVAL_TIME := 7.0       # durée de l'arrivée du bus après le rapport (s)
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
	_build_station_extras()
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
	_apply_ambiance()
	if PLUIE:
		_build_rain()
	_start_idle_behaviours()
	_bevel_all([_tile_shader, _wood_shader])
	_hd_render_settings()
	_update_info()
	hud.show_toast("Terminus %s — Va faire ton rapport au chef de gare" % line.to, Color(1, 0.95, 0.7), 6.0)


func _update_info() -> void:
	hud.set_info("Gare — %s (terminus)   |   Score aller : %d   |   Rapport : %s   |   Sur le quai : %d" % [
		line.to, int(Game.aller_result.get("score", 0)), "signé ✔" if report_done else "à faire", waiting.size()])


# ------------------------------------------------------------------ décor

func _build_station() -> void:
	var steel := Color(0.24, 0.27, 0.32)

	# sol : pelouse, voie des bus, trottoir d'en face, quai (surface du quai à y = 0)
	_ground(_tiles(Build.box(self, Vector3(160, 0.1, 160), Vector3(0, -0.45, 0), Color.WHITE, false),
		Vector2(1.5, 1.5), 0.0, 0.0, Color(0.3, 0.5, 0.26), Color.BLACK, 0.06, 0.35, 1.0), "grass")
	_ground(_tiles(Build.box(self, Vector3(8, 0.1, 80), Vector3(8, -0.35, 0), Color.WHITE), 
		Vector2(4, 4), 0.0, 0.0, Color(0.21, 0.21, 0.23), Color.BLACK, 0.0, 0.5, 0.92), "road")
	_ground(_tiles(Build.box(self, Vector3(3, 0.25, 80), Vector3(13.5, -0.2, 0), Color.WHITE),
		Vector2(0.6, 0.6), 0.0, 0.012, Color(0.62, 0.61, 0.58), Color(0.42, 0.41, 0.4), 0.1, 0.25, 0.9), "paving")
	_ground(_tiles(Build.box(self, Vector3(8.5, 0.3, 40), Vector3(-0.25, -0.15, 0), Color.WHITE),
		Vector2(0.5, 0.5), 0.0, 0.01, Color(0.7, 0.69, 0.66), Color(0.45, 0.44, 0.42), 0.12, 0.2, 0.85), "quay")
	# bord du quai : bande podotactile jaune (picots) + bordure béton
	_tiles(Build.box(self, Vector3(0.45, 0.012, 40), Vector3(3.55, 0.006, 0), Color.WHITE, false),
		Vector2(0.06, 0.06), 0.0, 0.015, Color(0.95, 0.78, 0.08), Color(0.7, 0.55, 0.05), 0.05, 0.1, 0.7)
	_rough(Build.box(self, Vector3(0.15, 0.32, 40), Vector3(3.95, -0.15, 0), Color(0.82, 0.82, 0.8), false), 0.8)
	# marquage de la voie : ligne d'arrêt « BUS » + pointillés
	for z in range(-36, 37, 6):
		Build.box(self, Vector3(0.15, 0.01, 3), Vector3(10.6, -0.295, z), Color(0.95, 0.95, 0.9), false)
	Build.box(self, Vector3(0.15, 0.01, 18), Vector3(4.6, -0.295, 0), Color(0.95, 0.8, 0.1), false)
	var bus_mark := Build.label3d(self, "BUS", Vector3(7.6, -0.29, -9.5), 200, Color(0.95, 0.95, 0.9))
	bus_mark.rotation_degrees = Vector3(-90, -90, 0)     # lisible depuis le quai
	bus_mark.pixel_size = 0.008

	_build_station_building()

	# marquise : toit, sous-face claire, chéneau, poteaux sur platines
	_metal(Build.box(self, Vector3(8.4, 0.12, 32), Vector3(-0.6, 3.78, 0), Color(0.2, 0.24, 0.32), false), 0.5, null, 0.6)
	_wood(Build.box(self, Vector3(8.2, 0.03, 31.8), Vector3(-0.6, 3.705, 0), Color.WHITE, false), Color(0.72, 0.52, 0.32), 0.12)   # lames de bois
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
	_shop_window(Vector3(-2.37, 1.5, 12.5), Vector2(1.6, 1.0), 1, "bureau")
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
	_entrance(Vector3(-4.5, 0, 0))
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
	var stone := Color(0.86, 0.83, 0.77)
	var white := Color(0.95, 0.94, 0.9)
	# encadrement en pierre en saillie : donne de la profondeur à la façade
	_tiles(Build.box(self, Vector3(0.12, 0.18, size.x + 0.4), at + Vector3(0.02, size.y / 2 + 0.09, 0), stone, false),
		Vector2(0.4, 0.18), 0.0, 0.006, stone, stone.darkened(0.2), 0.08, 0.25, 0.85)          # linteau
	for side in [-1, 1]:
		_tiles(Build.box(self, Vector3(0.12, size.y + 0.36, 0.18), at + Vector3(0.02, 0, side * (size.x / 2 + 0.09)), stone, false),
			Vector2(0.18, 0.3), 0.0, 0.006, stone, stone.darkened(0.2), 0.08, 0.25, 0.85)       # jambages
	_tiles(Build.box(self, Vector3(0.26, 0.08, size.x + 0.46), at + Vector3(0.09, -size.y / 2 - 0.12, 0), stone, false),
		Vector2(0.5, 0.08), 0.0, 0.006, stone, stone.darkened(0.2), 0.08, 0.25, 0.8)            # appui
	# vitre en retrait
	var g := Build.box(self, Vector3(0.02, size.y, size.x), at, Color(0.45, 0.58, 0.72), false)
	_night_windows.append(g)
	if lit:
		_glow(g, Color(1, 0.86, 0.62), 0.7)
	else:
		_glass(g, Color(0.22, 0.28, 0.34), 0.10)
	# rideaux de part et d'autre (couleur au hasard)
	var curtain: Color = [Color(0.88, 0.82, 0.68), Color(0.6, 0.2, 0.2), Color(0.25, 0.35, 0.55), Color(0.4, 0.5, 0.35)][rng.randi() % 4]
	for side in [-1, 1]:
		var c := Build.box(self, Vector3(0.012, size.y * 0.96, size.x * 0.2), at + Vector3(0.014, 0, side * size.x * 0.39), curtain, false)
		_rough(c, 1.0)
	# dormant et croisillons blancs
	for side in [-1, 1]:
		Build.box(self, Vector3(0.04, size.y, 0.05), at + Vector3(0.03, 0, side * (size.x / 2 - 0.025)), white, false)
		Build.box(self, Vector3(0.04, 0.05, size.x), at + Vector3(0.03, side * (size.y / 2 - 0.025), 0), white, false)
	Build.box(self, Vector3(0.035, size.y, 0.045), at + Vector3(0.032, 0, 0), white, false)              # meneau
	Build.box(self, Vector3(0.035, 0.045, size.x), at + Vector3(0.032, size.y * 0.2, 0), white, false)   # traverse


func _bench(at: Vector3) -> void:
	var wood := Color(0.56, 0.36, 0.19)
	var iron := Color(0.12, 0.13, 0.14)
	# assise : 4 lattes en bois veiné
	for k in 4:
		_wood(Build.box(self, Vector3(0.085, 0.035, 1.9), at + Vector3(0.13 - k * 0.095, 0.455, 0), wood, false), wood)
	# dossier incliné : 3 lattes
	for k in 3:
		var bs := Build.box(self, Vector3(0.028, 0.095, 1.9), at + Vector3(-0.245 - k * 0.022, 0.6 + k * 0.115, 0), wood, false)
		bs.rotation_degrees.z = 12
		_wood(bs, wood)
	# piètements en fonte (2 bouts avec accoudoirs + 1 central)
	for dz in [-0.88, 0.0, 0.88]:
		var p := at + Vector3(0, 0, dz)
		_metal(Build.box(self, Vector3(0.05, 0.44, 0.05), p + Vector3(0.15, 0.22, 0), iron, false), 0.35)          # pied avant
		var back := Build.box(self, Vector3(0.05, 0.9, 0.05), p + Vector3(-0.27, 0.45, 0), iron, false)          # pied arrière / montant
		back.rotation_degrees.z = 9
		_metal(back, 0.35)
		_metal(Build.box(self, Vector3(0.48, 0.04, 0.05), p + Vector3(-0.05, 0.42, 0), iron, false), 0.35)       # traverse d'assise
		_metal(Build.box(self, Vector3(0.4, 0.03, 0.04), p + Vector3(-0.05, 0.12, 0), iron, false), 0.35)        # entretoise basse
		if dz != 0.0:
			_metal(Build.box(self, Vector3(0.46, 0.035, 0.07), p + Vector3(-0.02, 0.68, 0), iron, false), 0.3)   # accoudoir
			_metal(Build.box(self, Vector3(0.035, 0.24, 0.035), p + Vector3(0.18, 0.56, 0), iron, false), 0.3)   # montant d'accoudoir
	_bin(at + Vector3(0.02, 0, 1.35))


func _windscreen(at: Vector3) -> void:
	var steel := Color(0.24, 0.27, 0.32)
	var g := Build.box(self, Vector3(1.6, 2.1, 0.03), at + Vector3(0, 1.15, 0), Color(0.75, 0.88, 0.95, 0.22))
	_glass(g, Color(0.88, 0.95, 0.98, 0.16), 0.08)
	for x in [-0.8, 0.8]:
		_metal(Build.box(self, Vector3(0.05, 2.2, 0.06), at + Vector3(x, 1.1, 0), steel, false), 0.35)
	_metal(Build.box(self, Vector3(1.65, 0.05, 0.06), at + Vector3(0, 2.22, 0), steel, false), 0.35)


func _ticket_machine(at: Vector3) -> void:
	var blue := Color(0.1, 0.27, 0.55)
	var dark := Color(0.07, 0.08, 0.1)
	var fx := at.x + 0.3
	# corps en deux tons + plinthe + bande couleur de ligne sur les côtés
	_metal(Build.box(self, Vector3(0.6, 1.75, 0.78), at + Vector3(0, 0.95, 0), blue), 0.35, null, 0.6)
	_metal(Build.box(self, Vector3(0.62, 0.55, 0.8), at + Vector3(0, 0.36, 0), blue.darkened(0.35), false), 0.4, null, 0.5)
	_metal(Build.box(self, Vector3(0.64, 0.08, 0.82), at + Vector3(0, 0.04, 0), Color(0.12, 0.12, 0.14), false), 0.4)
	for side in [-1, 1]:
		Build.box(self, Vector3(0.62, 0.05, 0.005), at + Vector3(0, 1.62, side * 0.393), line.color, false)
	# fronton lumineux + logo rond
	_glow(Build.box(self, Vector3(0.02, 0.2, 0.74), Vector3(fx + 0.01, 1.72, at.z), Color(0.95, 0.95, 0.95), false), Color(1, 1, 1), 0.8)
	Build.box(self, Vector3(0.022, 0.03, 0.74), Vector3(fx + 0.012, 1.61, at.z), line.color, false)
	_lbl("TICKETS · ABONNEMENTS", Vector3(fx + 0.025, 1.72, at.z + 0.05), 24, Color(0.1, 0.2, 0.45), 0.002)
	var logo := Build.cylinder(self, 0.05, 0.01, Vector3(fx + 0.025, 1.72, at.z - 0.29), line.color)
	logo.rotation_degrees.z = 90
	_glow(logo, line.color, 0.5)
	_lbl("R", Vector3(fx + 0.032, 1.72, at.z - 0.29), 32, Color.WHITE, 0.0022)
	# capot autour de l'écran (l'écran est encastré, plus « flottant »)
	_metal(Build.box(self, Vector3(0.12, 0.03, 0.58), Vector3(fx + 0.05, 1.53, at.z), dark, false), 0.4)          # visière
	for side in [-1, 1]:
		_metal(Build.box(self, Vector3(0.12, 0.42, 0.03), Vector3(fx + 0.05, 1.32, at.z + side * 0.29), dark, false), 0.4)
	var bezel := Build.box(self, Vector3(0.05, 0.4, 0.55), Vector3(fx + 0.02, 1.32, at.z), dark, false)
	bezel.rotation_degrees.z = -10
	var scr := Build.box(self, Vector3(0.01, 0.32, 0.46), Vector3(fx + 0.048, 1.325, at.z), Color(0.2, 0.45, 0.8), false)
	scr.rotation_degrees.z = -10
	_glow(scr, Color(0.25, 0.5, 0.9), 0.9)
	# textes et boutons posés SUR le plan incliné de l'écran (sinon ils passent derrière)
	var on_screen := func(y: float, lift: float) -> float:
		return fx + 0.054 + lift + (y - 1.325) * tan(deg_to_rad(10.0))
	var ui := _lbl("Choisissez votre titre", Vector3(on_screen.call(1.445, 0.004), 1.445, at.z), 20, Color.WHITE, 0.0018)
	ui.rotation_degrees.x = 10          # incliné comme l'écran (autour de l'axe du texte, pas en biais)
	var opts := [["Ticket 1 trajet   1,80 €", Color(0.3, 0.8, 0.5)], ["Carnet 10   15,00 €", Color(0.95, 0.75, 0.2)], ["Abonnement   45,00 €", Color(0.9, 0.4, 0.3)]]
	for k in 3:
		var by := 1.375 - k * 0.07
		var btn := Build.box(self, Vector3(0.006, 0.055, 0.38), Vector3(on_screen.call(by, 0.0), by, at.z), opts[k][1], false)
		btn.rotation_degrees.z = -10
		_glow(btn, opts[k][1], 0.6)
		var bl := _lbl(opts[k][0], Vector3(on_screen.call(by, 0.006), by, at.z), 16, Color(0.08, 0.08, 0.1), 0.0016)
		bl.rotation_degrees.x = 10
	# tablette de commande en saillie
	_metal(Build.box(self, Vector3(0.1, 0.03, 0.66), Vector3(fx + 0.05, 1.1, at.z), Color(0.7, 0.72, 0.75), false), 0.25)
	_metal(Build.box(self, Vector3(0.05, 0.14, 0.12), Vector3(fx + 0.025, 1.0, at.z + 0.22), Color(0.15, 0.15, 0.17), false), 0.3)   # lecteur de carte
	_glow(Build.box(self, Vector3(0.01, 0.015, 0.05), Vector3(fx + 0.051, 1.055, at.z + 0.22), Color(0.2, 1, 0.4), false), Color(0.2, 1, 0.4), 2.0)
	Build.box(self, Vector3(0.012, 0.006, 0.09), Vector3(fx + 0.051, 0.96, at.z + 0.22), Color(0.02, 0.02, 0.02), false)          # fente carte
	_metal(Build.box(self, Vector3(0.03, 0.1, 0.07), Vector3(fx + 0.015, 1.0, at.z - 0.22), Color(0.7, 0.72, 0.75), false), 0.25) # monnayeur
	Build.box(self, Vector3(0.01, 0.06, 0.008), Vector3(fx + 0.031, 1.0, at.z - 0.22), Color(0.02, 0.02, 0.02), false)
	for r in 4:
		for c in 3:
			_metal(Build.box(self, Vector3(0.015, 0.035, 0.035), Vector3(fx + 0.012, 1.04 - r * 0.045, at.z - 0.05 + c * 0.045), Color(0.75, 0.76, 0.78), false), 0.3)
	# mode d'emploi 1-2-3
	_glow(Build.box(self, Vector3(0.006, 0.12, 0.6), Vector3(fx + 0.004, 0.82, at.z), Color(0.95, 0.95, 0.92), false), Color(1, 1, 0.97), 0.25)
	_lbl("1 Choisir   2 Payer   3 Retirer", Vector3(fx + 0.009, 0.82, at.z), 18, Color(0.1, 0.2, 0.45), 0.0017)
	# sortie des tickets éclairée
	_metal(Build.box(self, Vector3(0.06, 0.12, 0.34), Vector3(fx + 0.025, 0.6, at.z), dark, false), 0.4)
	_glow(Build.box(self, Vector3(0.01, 0.012, 0.24), Vector3(fx + 0.056, 0.64, at.z), Color(1, 0.85, 0.4), false), Color(1, 0.85, 0.4), 1.5)
	# logos de paiement
	for k in 3:
		Build.box(self, Vector3(0.008, 0.035, 0.06), Vector3(fx + 0.005, 0.46, at.z - 0.08 + k * 0.08), [Color(0.1, 0.2, 0.6), Color(0.9, 0.5, 0.1), Color(0.85, 0.15, 0.15)][k], false)


func _vending_machine(at: Vector3) -> void:
	var red := Color(0.62, 0.08, 0.08)
	var dark := Color(0.08, 0.08, 0.09)
	var fx := at.x + 0.4
	# caisse en deux parties : arrière plein + façade percée, pour que la vitrine soit un vrai creux
	_metal(Build.box(self, Vector3(0.7, 1.95, 1.0), at + Vector3(-0.05, 0.99, 0), red), 0.3, null, 0.5)
	for part in [[Vector3(0.1, 0.5, 1.0), Vector3(fx - 0.05, 0.27, at.z)],          # sous la vitrine
			[Vector3(0.1, 0.25, 1.0), Vector3(fx - 0.05, 1.845, at.z)],             # au-dessus
			[Vector3(0.1, 1.2, 0.04), Vector3(fx - 0.05, 1.12, at.z - 0.48)],        # montant gauche
			[Vector3(0.1, 1.2, 0.3), Vector3(fx - 0.05, 1.12, at.z + 0.35)]]:        # côté commandes
		_metal(Build.box(self, part[0], part[1], red), 0.3, null, 0.5)
	_metal(Build.box(self, Vector3(0.82, 0.08, 1.02), at + Vector3(0, 0.04, 0), dark, false), 0.5)          # plinthe
	# bandeau blanc sur les côtés (habillage de marque)
	for side in [-1, 1]:
		_glow(Build.box(self, Vector3(0.6, 0.22, 0.01), at + Vector3(0, 1.45, side * 0.505), Color(0.95, 0.95, 0.95), false), Color(1, 1, 1), 0.2)
		var sl := Build.label3d(self, "FRAIS !", at + Vector3(0, 1.45, side * 0.512), 40, Color(0.65, 0.08, 0.08))
		sl.rotation_degrees.y = 0 if side > 0 else 180
		sl.pixel_size = 0.004
		sl.outline_size = 0
	# fronton lumineux
	_glow(Build.box(self, Vector3(0.02, 0.18, 0.96), Vector3(fx + 0.01, 1.84, at.z), Color(0.95, 0.95, 0.95), false), Color(1, 1, 1), 0.8)
	_lbl("BOISSONS FRAÎCHES", Vector3(fx + 0.025, 1.84, at.z), 30, Color(0.65, 0.08, 0.08), 0.0024)
	# vitrine : caisson sombre, éclairage LED latéral, 5 étagères avec spirales
	var wz := at.z - 0.13
	var ww := 0.66
	var wy := 1.12
	var wh := 1.2
	_glow(Build.box(self, Vector3(0.01, wh, ww), Vector3(fx - 0.09, wy, wz), Color(0.75, 0.78, 0.82), false), Color(0.85, 0.9, 1.0), 0.5)
	for side in [-1, 1]:
		_glow(Build.box(self, Vector3(0.02, wh - 0.05, 0.015), Vector3(fx - 0.04, wy, wz + side * (ww / 2 - 0.02)), Color(1, 1, 1), false), Color(0.9, 0.95, 1.0), 3.0)
	for r in 5:
		var sy := wy - wh / 2 + 0.06 + r * 0.235
		_metal(Build.box(self, Vector3(0.12, 0.01, ww - 0.04), Vector3(fx - 0.035, sy, wz), Color(0.75, 0.77, 0.8), false), 0.3)
		for c in 5:
			var cz := wz - ww / 2 + 0.075 + c * 0.128
			var col := Color.from_hsv(fmod(r * 0.23 + c * 0.17, 1.0), 0.75, 0.85)
			var bottle := (r + c) % 3 == 0
			for depth in 2:                  # deux rangées : celle du fond plus sombre
				var dx := fx - 0.07 + depth * 0.04
				var tint := col.darkened(0.35 - depth * 0.35)
				if bottle:
					var b := Build.cylinder(self, 0.028, 0.15, Vector3(dx, sy + 0.08, cz), tint)
					_metal(b, 0.1, Color(tint.r, tint.g, tint.b, 0.85), 0.0)
					Build.cylinder(self, 0.012, 0.04, Vector3(dx, sy + 0.175, cz), tint)
					Build.cylinder(self, 0.013, 0.015, Vector3(dx, sy + 0.2, cz), Color(0.95, 0.95, 0.95))
				else:
					var can := Build.cylinder(self, 0.034, 0.12, Vector3(dx, sy + 0.065, cz), tint)
					_metal(can, 0.2, tint, 0.7)
					_metal(Build.cylinder(self, 0.03, 0.006, Vector3(dx, sy + 0.128, cz), Color(0.8, 0.8, 0.82)), 0.2)
			# spirale de distribution devant le produit
			for k in 3:
				var coil := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.036
				tm.outer_radius = 0.041
				tm.rings = 12
				tm.ring_segments = 6
				coil.mesh = tm
				coil.material_override = Build.mat(Color(0.8, 0.82, 0.85), 0.25)
				coil.position = Vector3(fx - 0.03 - k * 0.025, sy + 0.05, cz)
				coil.rotation_degrees.z = 90
				add_child(coil)
			# étiquette code + prix
			Build.box(self, Vector3(0.004, 0.022, 0.07), Vector3(fx - 0.022, sy - 0.012, cz), Color(1, 1, 0.92), false)
			var tag := _lbl("%s%d  %s" % ["ABCDE"[r], c + 1, "1,80" if bottle else "1,50"], Vector3(fx - 0.019, sy - 0.012, cz), 14, Color(0.1, 0.1, 0.12), 0.0011)
			tag.modulate = Color(0.1, 0.1, 0.12)
	# vitre + cadre noir autour
	var glass := Build.box(self, Vector3(0.012, wh, ww), Vector3(fx + 0.012, wy, wz), Color(0.8, 0.9, 1.0, 0.1), false)
	_glass(glass, Color(0.93, 0.97, 1.0, 0.12), 0.07)
	for side in [-1, 1]:
		Build.box(self, Vector3(0.035, wh + 0.07, 0.035), Vector3(fx + 0.012, wy, wz + side * (ww / 2 + 0.017)), dark, false)
		Build.box(self, Vector3(0.035, 0.035, ww + 0.07), Vector3(fx + 0.012, wy + side * (wh / 2 + 0.017), wz), dark, false)
	# panneau de commande
	var pz := at.z + 0.34
	_metal(Build.box(self, Vector3(0.02, 1.2, 0.22), Vector3(fx + 0.005, wy, pz), Color(0.12, 0.12, 0.13), false), 0.4)
	Build.box(self, Vector3(0.02, 0.09, 0.18), Vector3(fx + 0.016, 1.55, pz), Color(0.02, 0.04, 0.02), false)
	var disp := _lbl("1,50 €", Vector3(fx + 0.028, 1.55, pz), 26, Color(0.3, 1, 0.4), 0.0021)
	disp.modulate = Color(0.3, 1, 0.4)
	for r2 in 4:
		for c2 in 3:
			_metal(Build.box(self, Vector3(0.015, 0.035, 0.045), Vector3(fx + 0.018, 1.42 - r2 * 0.048, pz - 0.055 + c2 * 0.055), Color(0.85, 0.86, 0.88), false), 0.3)
	_metal(Build.box(self, Vector3(0.03, 0.1, 0.08), Vector3(fx + 0.02, 1.08, pz), Color(0.75, 0.76, 0.78), false), 0.25)   # monnayeur
	Build.box(self, Vector3(0.01, 0.06, 0.008), Vector3(fx + 0.036, 1.1, pz), Color(0.02, 0.02, 0.02), false)
	_glow(Build.box(self, Vector3(0.012, 0.1, 0.14), Vector3(fx + 0.018, 0.88, pz), Color(0.15, 0.3, 0.6), false), Color(0.2, 0.45, 0.95), 0.6)   # sans contact
	_lbl("◉", Vector3(fx + 0.026, 0.88, pz), 30, Color.WHITE, 0.0022)
	Build.box(self, Vector3(0.02, 0.05, 0.12), Vector3(fx + 0.016, 0.68, pz), Color(0.03, 0.03, 0.03), false)    # rendu monnaie
	# trappe de distribution
	Build.box(self, Vector3(0.04, 0.22, ww), Vector3(fx + 0.015, 0.3, wz), dark, false)
	_metal(Build.box(self, Vector3(0.012, 0.16, ww - 0.08), Vector3(fx + 0.036, 0.3, wz), Color(0.2, 0.2, 0.22), false), 0.3)
	_lbl("POUSSER", Vector3(fx + 0.045, 0.3, wz), 18, Color(0.85, 0.85, 0.85), 0.0018)


func _map_panel(at: Vector3) -> void:
	var px := at.x
	# caisson en saillie avec cadre alu
	_metal(Build.box(self, Vector3(0.08, 1.5, 2.3), Vector3(px - 0.03, at.y, at.z), Color(0.7, 0.72, 0.75), false), 0.3)
	_glow(Build.box(self, Vector3(0.02, 1.36, 2.16), Vector3(px + 0.02, at.y, at.z), Color(0.97, 0.97, 0.95), false), Color(1, 1, 0.98), 0.45)
	# bandeau titre
	_glow(Build.box(self, Vector3(0.022, 0.22, 2.16), Vector3(px + 0.023, at.y + 0.57, at.z), Color(0.12, 0.22, 0.45), false), Color(0.12, 0.22, 0.45), 0.2)
	_lbl("PLAN DU RÉSEAU", Vector3(px + 0.04, at.y + 0.57, at.z), 40, Color.WHITE, 0.0032)
	# ligne 1 : tracé + arrêts (de gauche à droite pour le lecteur, donc vers -Z)
	var stops: Array = line.stops
	var n := stops.size()
	var ly := at.y + 0.18
	_glow(Build.box(self, Vector3(0.024, 0.045, 1.7), Vector3(px + 0.03, ly, at.z), line.color, false), line.color, 0.3)
	_lbl("%s %s" % [line.type, line.name], Vector3(px + 0.04, ly + 0.2, at.z + 0.65), 26, line.color.darkened(0.3), 0.0026)
	for i in n:
		var z := at.z + 0.85 - 1.7 * float(i) / maxf(n - 1, 1)
		var dot := Build.cylinder(self, 0.045, 0.02, Vector3(px + 0.042, ly, z), Color.WHITE)
		dot.rotation_degrees.z = 90
		Build.cylinder(self, 0.03, 0.022, Vector3(px + 0.043, ly, z), line.color.darkened(0.2)).rotation_degrees.z = 90
		var nm: String = stops[i].get("nom", "?") if stops[i] is Dictionary else str(stops[i])
		_lbl(nm, Vector3(px + 0.04, ly + (-0.11 if i % 2 == 0 else 0.1), z), 18, Color(0.15, 0.15, 0.2), 0.0021)
	# « Vous êtes ici » au terminus
	var here_z := at.z + 0.85 - 1.7
	Build.cylinder(self, 0.06, 0.02, Vector3(px + 0.045, ly, here_z), Color(0.9, 0.15, 0.15)).rotation_degrees.z = 90
	_lbl("▼ VOUS ÊTES ICI", Vector3(px + 0.04, ly + 0.22, here_z + 0.12), 20, Color(0.85, 0.12, 0.12), 0.0022)
	# ligne 2 en pointillés (bientôt)
	var l2y := at.y - 0.25
	for k in 9:
		Build.box(self, Vector3(0.024, 0.035, 0.12), Vector3(px + 0.03, l2y, at.z + 0.8 - k * 0.2), Color(0.9, 0.35, 0.2), false)
	_lbl("Tram Ligne 2 — Port → Stade (bientôt)", Vector3(px + 0.04, l2y - 0.12, at.z), 18, Color(0.6, 0.25, 0.15), 0.0021)
	# légende
	_lbl("Réseau Azimov  ·  Validez à chaque montée  ·  Infos : appli Réseau", Vector3(px + 0.04, at.y - 0.6, at.z), 16, Color(0.4, 0.4, 0.45), 0.0019)


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
				_night_windows.append(g)
				if rng.randf() < 0.2:
					_glow(g, Color(1, 0.86, 0.6), 0.5)
				else:
					_glass(g, Color(0.25, 0.32, 0.39), 0.13)
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
	_bus_group = Node3D.new()
	_bus_group.position.z = -90.0          # le bus n'est pas encore là : il arrivera après le rapport
	add_child(_bus_group)
	var root := Node3D.new()
	root.position = Vector3(bx, -0.3, 0)
	_bus_group.add_child(root)
	var L := 12.0; var W := 2.5; var H := 3.0
	# phares qui éclairent la route (bien visibles le soir sous la pluie)
	for hx in [-0.95, 0.95]:
		var hl := SpotLight3D.new()
		hl.position = Vector3(hx, 0.95, L / 2 + 0.1)
		hl.rotation_degrees = Vector3(-6, 180, 0)
		hl.light_color = Color(1, 0.97, 0.88)
		hl.light_energy = 4.0
		hl.spot_range = 25.0
		hl.spot_angle = 28.0
		hl.light_volumetric_fog_energy = 1.5
		root.add_child(hl)
	var glass := Color(0.12, 0.16, 0.2)
	# caisse : jupe sombre, corps couleur ligne, toit blanc, bandeau de livrée
	Build.box(root, Vector3(W, 0.45, L), Vector3(0, 0.55, 0), Color(0.15, 0.15, 0.17), true)
	_metal(Build.box(root, Vector3(W, 1.1, L), Vector3(0, 1.32, 0), body), 0.3, null, 0.3)
	_metal(Build.box(root, Vector3(W - 0.02, 0.35, L - 0.02), Vector3(0, 2.8, 0), Color(0.93, 0.93, 0.92), false), 0.35, null, 0.2)
	_metal(Build.box(root, Vector3(W + 0.01, 0.12, L - 1), Vector3(0, 0.95, -0.3), Color.WHITE, false), 0.3, null, 0.3)
	Build.box(root, Vector3(W - 0.06, 0.85, L - 0.06), Vector3(0, 2.25, 0), Color(0.05, 0.06, 0.07), false)   # intérieur sombre
	# vitres latérales teintées avec montants
	for side in [-1, 1]:
		_glass(Build.box(root, Vector3(0.04, 0.95, L - 0.6), Vector3(side * (W / 2), 2.15, 0), glass, false), glass, 0.08)
		var mz := -L / 2 + 0.6
		while mz < L / 2 - 0.5:
			Build.box(root, Vector3(0.06, 0.95, 0.08), Vector3(side * (W / 2 + 0.01), 2.15, mz), Color(0.08, 0.08, 0.09), false)
			mz += 1.6
	# pare-brise (avant, +Z), lunette arrière, pare-chocs, phares, feux
	_glass(Build.box(root, Vector3(W - 0.15, 1.5, 0.04), Vector3(0, 2.0, L / 2 + 0.01), glass, false), glass, 0.08)
	_glass(Build.box(root, Vector3(W - 0.5, 0.7, 0.04), Vector3(0, 2.3, -L / 2 - 0.01), glass, false), glass, 0.08)
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
	_bus_group.add_child(bus_door)
	Build.box(bus_door, Vector3(0.06, 2.3, 1.3), Vector3.ZERO, Color(0.1, 0.1, 0.11))
	for k in [-1, 1]:
		var panel := Build.box(bus_door, Vector3(0.03, 1.9, 0.55), Vector3(-0.03, 0.1, k * 0.3), glass, false)
		_glass(panel, glass, 0.08)
		panel.set_meta("dir", k)
		_door_panels.append(panel)
	_update_door()


func _update_door() -> void:
	bus_door.label = ("Monter dans le bus retour → " + back_line.to) if _bus_ready \
		else "Bus retour (fais d'abord ton rapport au chef de gare)"


func _update_board() -> void:
	var status := "Départ après le rapport de service"
	if _bus_ready:
		status = "À quai — embarquement en cours"
	elif report_done:
		status = "Bus en approche..."
	board_label.text = "QUAI 1   ·   %s %s  →  %s\n%s" % [line.type, line.name, back_line.to, status]


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
	hud.show_toast("Chef de gare : « Rapport signé. Ton bus pour %s arrive, le voilà ! »" % back_line.to,
		Color(0.7, 1, 0.75), 6.0)
	_bring_bus()


func _try_board() -> void:
	if not report_done:
		hud.show_toast("Fais d'abord ton rapport au chef de gare !", Color(1, 0.8, 0.5))
		return
	if not _bus_ready:
		hud.show_toast("Le bus arrive, patiente une seconde...", Color(1, 0.9, 0.6))
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
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.1
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
uniform float wet_level = 0.0;
uniform int ground_kind = 0; // 1 asphalt, 2 pavement, 3 grass, 4 sheltered platform
uniform float puddle_film = 0.0;
uniform float bump = 1.0;          // force du relief (joints creusés + grain)
uniform float bevel = 0.004;       // largeur de l'arrondi au bord des briques / dalles (m)
varying vec3 wpos;
varying vec3 wnrm;
varying float film_edge;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// distance (m) au bord de la brique / dalle
float edge_dist(vec2 uv) {
	vec2 b = uv / tile_size;
	b.x += mod(floor(b.y), 2.0) * stagger;
	vec2 f = fract(b);
	vec2 d = min(f, 1.0 - f) * tile_size;
	return min(d.x, d.y);
}
float groove_h(vec2 uv) {
	if (grout <= 0.0) return 1.0;
	return smoothstep(grout * 0.5, grout * 0.5 + bevel, edge_dist(uv));
}
float grain_h(vec2 uv) {
	return noise(uv * 25.0) * 0.5 + noise(uv * 6.0) * 0.5;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	film_edge = COLOR.a;
}
void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv;
	vec3 A;
	vec3 B;
	if (n.y > 0.6) { uv = wpos.xz; A = vec3(1, 0, 0); B = vec3(0, 0, 1); }
	else if (n.x > n.z) { uv = wpos.zy; A = vec3(0, 0, 1); B = vec3(0, 1, 0); }
	else { uv = wpos.xy; A = vec3(1, 0, 0); B = vec3(0, 1, 0); }
	vec2 b = uv / tile_size;
	b.x += mod(floor(b.y), 2.0) * stagger;
	vec2 id = floor(b);
	float h = groove_h(uv);
	float inside = grout > 0.0 ? step(grout * 0.5, edge_dist(uv)) : 1.0;
	float v = hash(id);
	float sp = noise(uv * 40.0) * 0.6 + noise(uv * 7.0) * 0.4;
	vec3 col = base_color.rgb * (1.0 - variation * 0.5 + variation * v) * (1.0 - speckle * 0.5 + speckle * sp);
	ALBEDO = mix(grout_color.rgb, col, inside);
	ROUGHNESS = clamp(mix(1.0, rough, inside) - sp * 0.05, 0.0, 1.0);
	float film = 0.0;
	if (ground_kind != 0 && wet_level > 0.0) {
		float exposure = 1.0;
		if (ground_kind == 4) {
			float canopy = (1.0 - smoothstep(3.25, 3.8, wpos.x)) * (1.0 - smoothstep(15.5, 16.4, abs(wpos.z)));
			exposure = 1.0 - canopy;
		}
		float wet_patch = noise(wpos.xz * 0.7 + vec2(12.7, 8.1));
		float wet = wet_level * exposure * (0.45 + 0.55 * smoothstep(0.2, 0.8, wet_patch));
		if (ground_kind == 3) {
			ALBEDO *= mix(1.0, 0.85, wet);
			ROUGHNESS = mix(ROUGHNESS, 0.95, wet);
		} else if (ground_kind != 0) {
			ALBEDO *= mix(1.0, 0.73, wet);
			ROUGHNESS = mix(ROUGHNESS, ground_kind == 1 ? 0.23 : 0.36, wet);
		}
		film = puddle_film * smoothstep(0.0, 0.28, film_edge);
		ALBEDO *= mix(1.0, 0.90, film);
		ROUGHNESS = mix(ROUGHNESS, 0.045 + wet_patch * 0.025, film);
		SPECULAR = mix(0.5, 0.25, film);
	}
	// relief : gradient de hauteur -> normale perturbée (en espace monde, puis vue)
	float e = 0.0012;
	vec2 g_groove = vec2(groove_h(uv + vec2(e, 0.0)) - h, groove_h(uv + vec2(0.0, e)) - h) / e;
	float g0 = grain_h(uv);
	vec2 g_grain = vec2(grain_h(uv + vec2(e, 0.0)) - g0, grain_h(uv + vec2(0.0, e)) - g0) / e;
	vec2 grad = g_groove * 0.003 + g_grain * 0.0012 * (0.3 + speckle);
	vec2 ripple = vec2(0.0);
	if (film > 0.0) ripple = vec2(cos(wpos.x * 34.0 + wpos.z * 19.0 + TIME * 2.8), sin(wpos.x * 17.0 - wpos.z * 31.0 + TIME * 2.1)) * 0.0015 * film;
	vec2 relief = bump * grad * mix(1.0, 0.08, film) + ripple;
	vec3 nw = normalize(wnrm - (relief.x * A + relief.y * B));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	AO = mix(0.45, 1.0, h);
	AO_LIGHT_AFFECT = 0.5;
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


# ------------------------------------------------------------------ 2e passe HD : vie et détails

var _pigeons: Array[Node3D] = []


func _build_station_extras() -> void:
	var steel := Color(0.24, 0.27, 0.32)
	# affiches encadrées entre les fenêtres du rez-de-chaussée
	var posters := [
		[Color(0.2, 0.45, 0.8), "VISITEZ LA CÔTE", Color.WHITE],
		[Color(0.95, 0.8, 0.2), "CONCERT — PARC DES CERISIERS", Color(0.15, 0.15, 0.2)],
		[Color(0.85, 0.25, 0.2), "SOLDES D'HIVER -50%", Color.WHITE],
		[Color(0.2, 0.6, 0.35), "MARCHÉ BIO LE SAMEDI", Color.WHITE],
	]
	var k := 0
	for z in [-11.0, -7.0, 5.0, 9.0]:      # entre les fenêtres
		var pst: Array = posters[k % posters.size()]
		Build.box(self, Vector3(0.04, 1.3, 0.95), Vector3(-4.46, 2.0, z), Color(0.15, 0.15, 0.17), false)
		_glow(Build.box(self, Vector3(0.02, 1.2, 0.85), Vector3(-4.43, 2.0, z), pst[0], false), pst[0], 0.25)
		var t := Build.label3d(self, pst[1], Vector3(-4.415, 2.35, z), 34, pst[2])
		t.rotation_degrees.y = 90
		t.pixel_size = 0.0022
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.width = 340
		t.outline_size = 0
		k += 1

	# suspensions fleuries, accrochées par une potence au poteau (côté voie)
	for z in range(-15, 16, 6):
		_flower_basket(Vector3(2.9, 0, z), steel)

	# petite terrasse de café au bout du quai
	var cafe_z := 17.5
	_tiles(Build.box(self, Vector3(0.05, 2.4, 3.2), Vector3(-4.44, 1.2, cafe_z), Color.WHITE, false),
		Vector2(0.4, 2.4), 0.0, 0.01, Color(0.15, 0.3, 0.22), Color(0.1, 0.2, 0.15), 0.05, 0.2, 0.5)
	var cafe := Build.label3d(self, "CAFÉ DU TERMINUS", Vector3(-4.4, 2.75, cafe_z), 48, Color(1, 0.9, 0.6))
	cafe.rotation_degrees.y = 90
	cafe.pixel_size = 0.004
	_shop_window(Vector3(-4.39, 1.25, cafe_z), Vector2(1.8, 1.4), 1, "cafe")
	# ardoise du menu + néon « OUVERT »
	_rough(Build.box(self, Vector3(0.25, 0.9, 0.55), Vector3(-3.9, 0.45, cafe_z - 1.25), Color(0.12, 0.12, 0.12)), 0.9)
	var menu_l := Build.label3d(self, "MENU\nCafé 1,80 €\nCroissant 1,20 €\nChocolat 2,50 €", Vector3(-3.77, 0.55, cafe_z - 1.25), 22, Color(0.95, 0.95, 0.9))
	menu_l.rotation_degrees.y = 90
	menu_l.pixel_size = 0.003
	menu_l.outline_size = 0
	var neon := Build.label3d(self, "OUVERT", Vector3(-4.37, 1.72, cafe_z + 0.5), 40, Color(1, 0.35, 0.45))
	neon.rotation_degrees.y = 90
	neon.pixel_size = 0.0035
	neon.outline_size = 10
	neon.outline_modulate = Color(1, 0.2, 0.35, 0.6)
	for tz in [16.2, 18.6]:
		_cafe_table(Vector3(-1.9, 0, tz))

	# bornes anti-stationnement le long de la voie (bouts du quai)
	for z in [-19.5, -18.5, 18.5, 19.5]:
		_metal(Build.cylinder(self, 0.08, 0.9, Vector3(3.7, 0.45, z), Color(0.2, 0.22, 0.25)), 0.4)
		Build.cylinder(self, 0.082, 0.06, Vector3(3.7, 0.8, z), Color(0.95, 0.95, 0.9))

	# la ville continue aux deux bouts du quai (plus de vide à l'horizon)
	for end in [-1, 1]:
		var ez: float = end * 30.0
		var x := -14.0
		while x < 14.0:
			var w := rng.randf_range(6, 10)
			var h := rng.randf_range(8, 18)
			var col := Color.from_hsv(rng.randf_range(0.03, 0.12), rng.randf_range(0.12, 0.3), rng.randf_range(0.6, 0.85))
			if absf(x + w / 2 - 8.0) < 4.5:      # laisser la rue ouverte
				x += w
				continue
			var b := Build.box(self, Vector3(w * 0.95, h, 8), Vector3(x + w / 2, h / 2 - 0.4, ez + end * 4), col, false)
			_tiles(b, Vector2(0.24, 0.075), 0.5, 0.0, col, col, 0.08, 0.15, 0.9)
			var fy := 2.0
			while fy < h - 1.5:
				var wx := x + 1.0
				while wx < x + w - 1.0:
					var g := Build.box(self, Vector3(1.0, 1.2, 0.05), Vector3(wx + 0.5, fy, ez + end * 4 - end * 4.02), Color(0.42, 0.55, 0.7), false)
					_night_windows.append(g)
					if rng.randf() < 0.2:
						_glow(g, Color(1, 0.86, 0.6), 0.5)
					else:
						_glass(g, Color(0.25, 0.32, 0.39), 0.13)
					wx += 2.0
				fy += 3.0
			x += w

	# pigeons qui picorent sur le quai
	for i in 5:
		var pg := _pigeon(Vector3(rng.randf_range(-1.5, 2.5), 0, rng.randf_range(-14.0, 14.0)))
		_pigeons.append(pg)


func _cafe_table(at: Vector3) -> void:
	_metal(Build.cylinder(self, 0.35, 0.03, at + Vector3(0, 0.74, 0), Color(0.92, 0.92, 0.9)), 0.3, null, 0.3)
	_metal(Build.cylinder(self, 0.03, 0.72, at + Vector3(0, 0.37, 0), Color(0.2, 0.2, 0.22)), 0.4)
	for a in [0, 120, 240]:   # chaises bistrot
		var r := deg_to_rad(a)
		var p := at + Vector3(cos(r), 0, sin(r)) * 0.6
		_rough(Build.cylinder(self, 0.18, 0.04, p + Vector3(0, 0.45, 0), Color(0.5, 0.3, 0.15)), 0.6)
		_metal(Build.cylinder(self, 0.015, 0.45, p + Vector3(0, 0.22, 0), Color(0.15, 0.15, 0.16)), 0.4)
		# dossier rond en rotin tourné vers l'extérieur
		var back := Build.box(self, Vector3(0.3, 0.3, 0.03), p + Vector3(cos(r), 0, sin(r)) * 0.16 + Vector3(0, 0.66, 0), Color(0.55, 0.36, 0.18), false)
		back.rotation.y = -r + PI / 2
		_rough(back, 0.7)
		for leg in [-1, 1]:
			var bl := Build.cylinder(self, 0.01, 0.25, p + Vector3(cos(r), 0, sin(r)) * 0.16 + Vector3(-sin(r), 0, cos(r)) * 0.13 * leg + Vector3(0, 0.55, 0), Color(0.15, 0.15, 0.16))
			_metal(bl, 0.4)
	# tasse de café
	Build.cylinder(self, 0.04, 0.07, at + Vector3(0.1, 0.79, 0.05), Color(0.97, 0.97, 0.95))
	# parasol
	_metal(Build.cylinder(self, 0.02, 2.2, at + Vector3(0, 1.1, 0), Color(0.85, 0.85, 0.85)), 0.3)
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.1
	cm.height = 0.35
	top.mesh = cm
	top.material_override = Build.mat(Color(0.75, 0.2, 0.2), 0.9)
	top.position = at + Vector3(0, 2.1, 0)
	add_child(top)


func _pigeon(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.rotation_degrees.y = rng.randf_range(0, 360)
	add_child(root)
	var grey := Color(0.45, 0.47, 0.52)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.09
	bm.height = 0.13
	body.mesh = bm
	body.material_override = Build.mat(grey, 0.8)
	body.position = Vector3(0, 0.1, 0)
	body.scale = Vector3(0.8, 1, 1.4)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.045
	hm.height = 0.09
	head.mesh = hm
	head.material_override = Build.mat(Color(0.35, 0.4, 0.45), 0.6)
	head.position = Vector3(0, 0.17, -0.1)
	head.name = "Head"
	root.add_child(head)
	Build.box(head, Vector3(0.015, 0.012, 0.035), Vector3(0, -0.005, -0.045), Color(0.85, 0.6, 0.3), false)   # bec
	Build.box(root, Vector3(0.1, 0.02, 0.08), Vector3(0, 0.1, 0.15), Color(0.3, 0.32, 0.36), false)          # queue
	for side in [-1, 1]:
		Build.box(root, Vector3(0.008, 0.06, 0.008), Vector3(side * 0.03, 0.03, 0), Color(0.8, 0.4, 0.4), false)
	# picore en boucle
	var tw := create_tween().set_loops()
	tw.tween_interval(rng.randf_range(0.3, 1.5))
	tw.tween_property(head, "position", Vector3(0, 0.07, -0.13), 0.12)
	tw.tween_property(head, "position", Vector3(0, 0.17, -0.1), 0.15)
	tw.tween_interval(rng.randf_range(0.5, 2.0))
	tw.tween_property(root, "rotation_degrees:y", root.rotation_degrees.y + rng.randf_range(-90, 90), 0.4)
	return root


## Vitrine avec un intérieur suggéré derrière la vitre (face +X). kind : "cafe" ou "bureau".
func _shop_window(at: Vector3, size: Vector2, _dir: int, kind: String) -> void:
	var back_x := at.x - 0.015
	# fond intérieur chaud et tamisé
	_glow(Build.box(self, Vector3(0.01, size.y, size.x), Vector3(back_x, at.y, at.z), Color(0.35, 0.24, 0.16), false), Color(0.45, 0.3, 0.18), 0.35)
	if kind == "cafe":
		# étagères avec bouteilles et tasses
		for sy in [0.35, 0.05]:
			Build.box(self, Vector3(0.012, 0.025, size.x * 0.8), Vector3(back_x + 0.006, at.y + sy, at.z), Color(0.5, 0.33, 0.18), false)
			for k in 9:
				var c := Color.from_hsv(fmod(k * 0.17 + sy, 1.0), 0.55, 0.75)
				_glow(Build.box(self, Vector3(0.012, 0.13, 0.06), Vector3(back_x + 0.01, at.y + sy + 0.08, at.z - size.x * 0.38 + k * 0.095), c, false), c, 0.4)
		# comptoir + machine à café chromée
		_rough(Build.box(self, Vector3(0.014, 0.4, size.x * 0.9), Vector3(back_x + 0.012, at.y - size.y / 2 + 0.2, at.z), Color(0.25, 0.15, 0.08), false), 0.5)
		_metal(Build.box(self, Vector3(0.016, 0.22, 0.3), Vector3(back_x + 0.014, at.y - size.y / 2 + 0.5, at.z + 0.4), Color(0.8, 0.8, 0.82), false), 0.2)
		# suspensions lumineuses
		for lz in [-0.5, 0.0, 0.5]:
			_glow(Build.box(self, Vector3(0.014, 0.08, 0.12), Vector3(back_x + 0.012, at.y + size.y / 2 - 0.12, at.z + lz), Color(1, 0.85, 0.55), false), Color(1, 0.8, 0.5), 2.5)
	else:
		# bureau du chef : étagère de classeurs, horaire affiché, écran
		for k in 8:
			var c2: Color = [Color(0.2, 0.3, 0.6), Color(0.7, 0.2, 0.2), Color(0.2, 0.5, 0.3), Color(0.85, 0.7, 0.2)][k % 4]
			Build.box(self, Vector3(0.012, 0.22, 0.06), Vector3(back_x + 0.01, at.y + 0.25, at.z - 0.6 + k * 0.08), c2, false)
		_glow(Build.box(self, Vector3(0.012, 0.35, 0.45), Vector3(back_x + 0.01, at.y - 0.05, at.z + 0.35), Color(0.95, 0.95, 0.92), false), Color(1, 1, 0.97), 0.3)
		_glow(Build.box(self, Vector3(0.014, 0.2, 0.3), Vector3(back_x + 0.014, at.y - 0.25, at.z - 0.3), Color(0.3, 0.6, 0.9), false), Color(0.35, 0.65, 1.0), 1.2)
		_glow(Build.box(self, Vector3(0.012, 0.05, size.x * 0.9), Vector3(back_x + 0.012, at.y + size.y / 2 - 0.06, at.z), Color(1, 0.95, 0.85), false), Color(1, 0.95, 0.85), 2.0)
	# vitre avec reflet
	var glass := Build.box(self, Vector3(0.01, size.y, size.x), Vector3(at.x + 0.03, at.y, at.z), Color(0.8, 0.9, 1.0, 0.12), false)
	_glass(glass, Color(0.92, 0.97, 1.0, 0.14), 0.08)
	# encadrement
	for side in [-1, 1]:
		Build.box(self, Vector3(0.05, size.y + 0.1, 0.05), Vector3(at.x + 0.03, at.y, at.z + side * (size.x / 2 + 0.025)), Color(0.12, 0.12, 0.13), false)
		Build.box(self, Vector3(0.05, 0.05, size.x + 0.1), Vector3(at.x + 0.03, at.y + side * (size.y / 2 + 0.025), at.z), Color(0.12, 0.12, 0.13), false)


# ------------------------------------------------------------------ 3e passe : soir, pluie, vie, arrivée du bus

var _bus_group: Node3D
var _bus_ready := false
var _door_panels: Array = []
var _rain: GPUParticles3D


## Le bus arrive en freinant, s'arrête le long du quai et ouvre ses portes.
func _bring_bus() -> void:
	var tw := create_tween()
	tw.tween_property(_bus_group, "position:z", 0.0, BUS_ARRIVAL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	for panel in _door_panels:
		tw.parallel().tween_property(panel, "position:z", panel.position.z + 0.5 * panel.get_meta("dir"), 0.8)
	tw.tween_callback(func():
		_bus_ready = true
		_update_door()
		_update_board()
		hud.show_toast("Le bus pour %s est à quai. Monte quand tu veux !" % back_line.to, Color(0.8, 0.95, 1), 4.0)
		# les voyageurs se tournent vers le bus
		for p in waiting:
			if p.has_meta("idle_tween"):
				(p.get_meta("idle_tween") as Tween).kill()
			var tt := create_tween()
			tt.tween_property(p, "rotation_degrees", Vector3(0, -90, 0), 0.6)
	)


## Coucher de soleil : lumière orange rasante, ciel dégradé, toutes les lumières allumées.
func _apply_ambiance() -> void:
	if not SOIR and not PLUIE:
		return
	var env: Environment = null
	for c in find_children("*", "WorldEnvironment", true, false):
		env = (c as WorldEnvironment).environment
	for l in find_children("*", "DirectionalLight3D", true, false):
		var sun := l as DirectionalLight3D
		if SOIR:
			sun.rotation_degrees = Vector3(-14, 70, 0)        # bas sur l'horizon, depuis le quartier d'en face
			sun.light_color = Color(1, 0.58, 0.32)
			sun.light_energy = 0.35 if PLUIE else 1.1
		else:
			sun.light_energy = 0.4
	if env:
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			if PLUIE:
				sm.sky_top_color = Color(0.16, 0.18, 0.26) if SOIR else Color(0.4, 0.44, 0.5)
				sm.sky_horizon_color = Color(0.55, 0.42, 0.38) if SOIR else Color(0.6, 0.62, 0.65)
			else:
				sm.sky_top_color = Color(0.15, 0.18, 0.4)
				sm.sky_horizon_color = Color(0.98, 0.55, 0.32)
			sm.ground_horizon_color = sm.sky_horizon_color
		env.ambient_light_energy = 0.35 if SOIR else 0.5
		env.fog_light_color = Color(0.55, 0.45, 0.45) if SOIR else Color(0.6, 0.63, 0.68)
		env.fog_density = 0.012 if PLUIE else 0.005
		env.ssr_enabled = true                # reflets dans les flaques et le sol mouillé
		env.ssr_max_steps = 64
		env.volumetric_fog_enabled = QUALITY_HIGH and SOIR
		env.volumetric_fog_density = 0.01
		env.volumetric_fog_albedo = Color(0.9, 0.85, 0.85)
		env.glow_intensity = 0.7
	if SOIR:
		# fenêtres : environ 6 sur 10 allumées, teintes chaudes variées
		for g in _night_windows:
			if is_instance_valid(g) and rng.randf() < 0.6:
				var warm := Color(1, rng.randf_range(0.7, 0.9), rng.randf_range(0.45, 0.65))
				_glow(g, warm, rng.randf_range(0.6, 1.4))
		# lampes de la marquise plus fortes, lampadaires d'en face allumés
		for l in find_children("*", "OmniLight3D", true, false):
			var ol := l as OmniLight3D
			ol.light_energy = ol.light_energy * 1.6
		for lz in range(-36, 37, 12):
			var o := OmniLight3D.new()
			o.position = Vector3(11.4, 5.6, lz)
			o.light_color = Color(1, 0.8, 0.5)
			o.light_energy = 2.0
			o.omni_range = 12.0
			o.shadow_enabled = false
			add_child(o)
	if PLUIE:
		for kind in _ground_materials:
			var material: ShaderMaterial = _ground_materials[kind]
			material.set_shader_parameter("wet_level", 1.0)
		_puddles()


func _puddles() -> void:
	# Same opaque ground shader: joints/grain remain aligned through the film,
	# edges merge through roughness rather than alpha sorting / dark discs.
	var road: ShaderMaterial = _ground_materials["road"].duplicate()
	var paving: ShaderMaterial = _ground_materials["quay"].duplicate()
	road.set_shader_parameter("puddle_film", 1.0)
	paving.set_shader_parameter("puddle_film", 1.0)
	for i in 18:
		var radius := rng.randf_range(0.25, 0.7) if i < 14 else rng.randf_range(0.15, 0.35)
		var p := MeshInstance3D.new()
		p.mesh = _puddle_mesh(radius, float(i) * 2.39996323 + radius * 5.0)
		p.scale = Vector3(rng.randf_range(0.7, 1.3), 1, rng.randf_range(0.8, 1.8))
		p.material_override = road if i < 14 else paving
		if i < 14:
			p.position = Vector3(rng.randf_range(4.4, 6.5) if i % 2 == 0 else rng.randf_range(6.5, 11.5), -0.297, rng.randf_range(-30, 30))
		else:
			p.position = Vector3(rng.randf_range(0.5, 3.0), 0.003, rng.randf_range(17.0, 19.5) * (1 if i % 2 == 0 else -1))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.set_meta("gare_puddle", true)
		add_child(p)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(30, 10, 60)
	probe.position = Vector3(2, 3, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.intensity = 0.9
	add_child(probe)


func _puddle_mesh(radius: float, phase: float) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var colors := PackedColorArray([Color(1, 1, 1, 1)])
	var indices := PackedInt32Array()
	const SEGMENTS := 48
	for i in SEGMENTS:
		var angle := TAU * float(i) / SEGMENTS
		var irregular := 1.0 + 0.15 * sin(angle * 3.0 + phase) + 0.08 * sin(angle * 5.0 - phase * 1.7)
		vertices.append(Vector3(cos(angle), 0, sin(angle)) * radius * irregular)
		normals.append(Vector3.UP)
		colors.append(Color(1, 1, 1, 0))
	for i in SEGMENTS:
		indices.append_array(PackedInt32Array([0, i + 1, (i + 1) % SEGMENTS + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Pluie : trois zones d'émission autour de l'abri (voie + rue d'en face, et les deux bouts du quai).
## Rien n'est émis au-dessus de la marquise ni du bâtiment, donc il ne pleut jamais dessous.
func _build_rain() -> void:
	var drop := QuadMesh.new()
	drop.size = Vector2(0.008, 0.32)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.7, 0.75, 0.85, 0.22)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.billboard_keep_scale = true
	drop.material = dm
	var q := 1.0 if QUALITY_HIGH else 0.45
	# [centre de la zone, demi-taille x/z, nombre de gouttes]
	var zones := [
		[Vector3(14.0, 14, 0), Vector2(10.2, 30.0), int(9000 * q)],      # voie des bus + quartier d'en face (x 3.8 → 24)
		[Vector3(-2.0, 14, 24.0), Vector2(8.0, 7.6), int(2500 * q)],     # bout du quai côté café (z 16.4 → 31.6)
		[Vector3(-2.0, 14, -24.0), Vector2(8.0, 7.6), int(2500 * q)],    # autre bout du quai
	]
	for zdef in zones:
		var r := GPUParticles3D.new()
		r.amount = zdef[2]
		r.lifetime = 0.95                      # le temps de tomber de 14 m : les gouttes disparaissent au sol
		r.position = zdef[0]
		r.visibility_aabb = AABB(Vector3(-zdef[1].x - 1, -16, -zdef[1].y - 1), Vector3(zdef[1].x * 2 + 2, 18, zdef[1].y * 2 + 2))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(zdef[1].x, 0.3, zdef[1].y)
		pm.direction = Vector3(0, -1, 0)
		pm.spread = 0.0
		pm.initial_velocity_min = 11.0
		pm.initial_velocity_max = 13.0
		pm.gravity = Vector3(0, -9.8, 0)
		r.process_material = pm
		r.draw_pass_1 = drop
		r.preprocess = 1.0
		add_child(r)
	_rain = null
	# éclaboussures sur la voie
	var splash := GPUParticles3D.new()
	splash.amount = int(500 * q)
	splash.lifetime = 0.25
	splash.position = Vector3(8.0, -0.28, 0)
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(4.0, 0.0, 30.0)
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 40.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.2
	sp.gravity = Vector3(0, -9.8, 0)
	sp.scale_min = 0.5
	sp.scale_max = 1.0
	splash.process_material = sp
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	var sm_mat := StandardMaterial3D.new()
	sm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm_mat.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
	sm.material = sm_mat
	splash.draw_pass_1 = sm
	add_child(splash)


func _process(_delta: float) -> void:
	if player:
		for pg in _pigeons:
			if pg.has_meta("flying"):
				continue
			if pg.global_position.distance_to(player.global_position) < 1.6:
				_fly_away(pg)


## Le pigeon s'envole quand on approche, puis se repose plus loin.
func _fly_away(pg: Node3D) -> void:
	pg.set_meta("flying", true)
	var away := (pg.global_position - player.global_position)
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
	var land := Vector3(rng.randf_range(-1.5, 2.5), 0, clampf(pg.position.z + rng.randf_range(-8, 8), -14.0, 14.0))
	var tw := create_tween()
	tw.tween_property(pg, "rotation_degrees:y", rad_to_deg(atan2(-away.x, -away.z)), 0.1)
	tw.tween_property(pg, "position", pg.position + away * 4.0 + Vector3(0, 2.6, 0), 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pg, "scale", Vector3(1.3, 0.8, 1.3), 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pg, "scale", Vector3.ONE, 0.2)
	tw.tween_interval(rng.randf_range(3.0, 6.0))
	tw.tween_property(pg, "position", land + Vector3(0, 2.0, 0), 0.01)
	tw.tween_property(pg, "position", land, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): pg.remove_meta("flying"))


## Petits gestes des voyageurs qui attendent : ils se balancent, regardent autour d'eux, vers le panneau.
func _start_idle_behaviours() -> void:
	for p in waiting:
		var base := p.rotation_degrees.y
		var tw := create_tween().set_loops()
		tw.tween_interval(rng.randf_range(2.0, 6.0))
		if rng.randf() < 0.5:
			# regarde vers le panneau des départs / vers le bout du quai
			var look := base + rng.randf_range(-70, 70)
			tw.tween_property(p, "rotation_degrees:y", look, 0.8).set_trans(Tween.TRANS_SINE)
			tw.tween_interval(rng.randf_range(1.5, 3.5))
			tw.tween_property(p, "rotation_degrees:y", base, 0.8).set_trans(Tween.TRANS_SINE)
		else:
			# se balance d'un pied sur l'autre
			tw.tween_property(p, "rotation_degrees:z", 2.0, 0.7).set_trans(Tween.TRANS_SINE)
			tw.tween_property(p, "rotation_degrees:z", -2.0, 1.2).set_trans(Tween.TRANS_SINE)
			tw.tween_property(p, "rotation_degrees:z", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
		p.set_meta("idle_tween", tw)


var _night_windows: Array = []


## Suspension fleurie : potence fixée au poteau, chaîne, panier tressé, fleurs et feuillage retombant.
func _flower_basket(pole: Vector3, steel: Color) -> void:
	var at := pole + Vector3(0.5, 2.62, 0)            # 50 cm à côté du poteau, côté voie
	# potence + jambe de force
	_metal(Build.box(self, Vector3(0.6, 0.04, 0.04), pole + Vector3(0.3, 3.15, 0), steel, false), 0.4)
	var brace := Build.box(self, Vector3(0.03, 0.4, 0.03), pole + Vector3(0.18, 2.97, 0), steel, false)
	brace.rotation_degrees.z = 40
	_metal(brace, 0.4)
	_metal(Build.cylinder(self, 0.006, 0.42, at + Vector3(0, 0.33, 0), Color(0.3, 0.3, 0.32)), 0.3)   # chaîne
	# panier tressé (tronc de cône) + bord de mousse
	var basket := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.13
	cm.height = 0.2
	basket.mesh = cm
	basket.position = at
	add_child(basket)
	_tiles(basket, Vector2(0.03, 0.025), 0.5, 0.004, Color(0.45, 0.32, 0.18), Color(0.25, 0.17, 0.1), 0.3, 0.3, 0.9)
	var moss := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.235
	mm.bottom_radius = 0.235
	mm.height = 0.03
	moss.mesh = mm
	moss.material_override = Build.mat(Color(0.22, 0.38, 0.18), 1.0)
	moss.position = at + Vector3(0, 0.1, 0)
	add_child(moss)
	# dôme de petites fleurs
	var cols := [Color(0.88, 0.18, 0.38), Color(0.98, 0.78, 0.2), Color(0.97, 0.97, 0.97), Color(0.6, 0.3, 0.8), Color(0.95, 0.45, 0.2)]
	for f in 26:
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * 0.22
		var fl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.03, 0.05)
		sm.height = sm.radius * 1.4
		sm.radial_segments = 8
		sm.rings = 4
		fl.mesh = sm
		var c: Color = cols[rng.randi() % cols.size()] if f % 3 != 0 else Color(0.25, 0.5, 0.22)
		fl.material_override = Build.mat(c, 0.85)
		fl.position = at + Vector3(cos(ang) * rad, 0.12 + (0.22 - rad) * 0.5, sin(ang) * rad)
		add_child(fl)
	# feuillage qui retombe : tiges fines avec petites feuilles
	for t in 7:
		var ang := TAU * t / 7.0 + rng.randf_range(-0.2, 0.2)
		var base := at + Vector3(cos(ang) * 0.22, 0.08, sin(ang) * 0.22)
		var length := rng.randf_range(0.3, 0.65)
		var stem := Build.cylinder(self, 0.006, length, base - Vector3(0, length / 2, 0), Color(0.2, 0.42, 0.18))
		stem.rotation_degrees = Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		for lf in int(length / 0.08):
			var leaf := Build.box(self, Vector3(0.05, 0.012, 0.035), base - Vector3(0, 0.06 + lf * 0.08, 0), Color(0.24, 0.5 + rng.randf() * 0.1, 0.2), false)
			leaf.rotation_degrees = Vector3(rng.randf_range(-30, 30), rng.randf() * 360, rng.randf_range(-20, 20))



## Texte collé sur la façade de la gare (tourné vers le quai, +X), sans contour.
func _lbl(t: String, pos: Vector3, font: int, col: Color, px_size: float) -> Label3D:
	var l := Build.label3d(self, t, pos, font, col)
	l.rotation_degrees.y = 90
	l.pixel_size = px_size
	l.outline_size = 0
	return l


## Bois veiné (fil dans la longueur des lattes, axe Z).
func _wood(n: Node, col: Color, plank_width := 0.0) -> void:
	if _wood_shader == null:
		_wood_shader = Shader.new()
		_wood_shader.code = WOOD_SHADER
	var mesh := _mesh_of(n)
	if mesh == null: return
	var material := ShaderMaterial.new()
	material.shader = _wood_shader
	material.set_shader_parameter("base_color", col)
	material.set_shader_parameter("plank_width", plank_width)
	var p := (n as Node3D).global_position
	material.set_shader_parameter("board_seed", fposmod(p.x * 17.73 + p.y * 29.17 + p.z * 11.31, 93.0))
	mesh.material_override = material


## Poubelle de ville : corps perforé, cerclages, couvercle bombé avec ouverture, logo.
func _bin(at: Vector3) -> void:
	var green := Color(0.13, 0.3, 0.2)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.2
	cm.height = 0.7
	body.mesh = cm
	body.position = at + Vector3(0, 0.4, 0)
	add_child(body)
	_tiles(body, Vector2(0.035, 0.035), 0.5, 0.014, green, Color(0.03, 0.05, 0.04), 0.05, 0.15, 0.45)   # tôle perforée
	for y in [0.07, 0.42, 0.75]:
		var ring := Build.cylinder(self, 0.225, 0.035, at + Vector3(0, y, 0), green.darkened(0.3))
		_metal(ring, 0.35)
	var lid := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.23
	sm.height = 0.23
	sm.is_hemisphere = true
	lid.mesh = sm
	lid.position = at + Vector3(0, 0.77, 0)
	lid.material_override = Build.mat(green.darkened(0.15), 0.4)
	add_child(lid)
	var slot := Build.box(self, Vector3(0.05, 0.08, 0.22), at + Vector3(0.18, 0.84, 0), Color(0.02, 0.02, 0.02), false)
	slot.rotation_degrees.z = 35
	var badge := Build.cylinder(self, 0.06, 0.005, at + Vector3(0.222, 0.5, 0), Color(0.95, 0.95, 0.9))
	badge.rotation_degrees.z = 90
	_glow(badge, Color(0.9, 0.9, 0.85), 0.15)
	var logo := Build.label3d(self, "♻", at + Vector3(0.227, 0.5, 0), 40, Color(0.15, 0.45, 0.25))
	logo.rotation_degrees.y = 90
	logo.pixel_size = 0.002
	logo.outline_size = 0



## Entrée de la gare : encadrement en pierre, portes vitrées alu avec barres de poussée,
## imposte « ENTRÉE », hall éclairé visible derrière, paillasson.
func _entrance(at: Vector3) -> void:
	var stone := Color(0.86, 0.83, 0.77)
	var alu := Color(0.22, 0.23, 0.25)
	var w := 2.4
	var h := 2.6
	var fx := at.x
	# encadrement en pierre
	_tiles(Build.box(self, Vector3(0.14, 0.3, w + 0.6), Vector3(fx + 0.05, h + 0.55, at.z), stone, false),
		Vector2(0.5, 0.3), 0.0, 0.006, stone, stone.darkened(0.2), 0.08, 0.25, 0.85)
	for side in [-1, 1]:
		_tiles(Build.box(self, Vector3(0.14, h + 0.7, 0.3), Vector3(fx + 0.05, (h + 0.7) / 2, at.z + side * (w / 2 + 0.15)), stone, false),
			Vector2(0.3, 0.35), 0.0, 0.006, stone, stone.darkened(0.2), 0.08, 0.25, 0.85)
	# hall intérieur suggéré : fond chaud, sol, panneau « GUICHETS », plafonniers
	_glow(Build.box(self, Vector3(0.01, h + 0.4, w), Vector3(fx + 0.01, (h + 0.4) / 2, at.z), Color(0.55, 0.45, 0.35), false), Color(0.6, 0.48, 0.34), 0.55)
	_tiles(Build.box(self, Vector3(0.012, 0.5, w), Vector3(fx + 0.017, 0.25, at.z), Color.WHITE, false),
		Vector2(0.25, 0.25), 0.0, 0.01, Color(0.75, 0.7, 0.62), Color(0.5, 0.45, 0.4), 0.1, 0.2, 0.5)
	_glow(Build.box(self, Vector3(0.012, 0.22, 0.9), Vector3(fx + 0.02, 1.95, at.z + 0.45), Color(0.12, 0.22, 0.45), false), Color(0.12, 0.22, 0.45), 0.4)
	_lbl("GUICHETS ▸", Vector3(fx + 0.027, 1.95, at.z + 0.45), 24, Color.WHITE, 0.0022)
	for lz in [-0.7, 0.0, 0.7]:
		_glow(Build.box(self, Vector3(0.014, 0.05, 0.25), Vector3(fx + 0.02, 2.55, at.z + lz), Color(1, 0.95, 0.85), false), Color(1, 0.95, 0.85), 2.5)
	# imposte vitrée + « ENTRÉE »
	_metal(Build.box(self, Vector3(0.08, 0.06, w), Vector3(fx + 0.07, h, at.z), alu, false), 0.35)
	_glow(Build.box(self, Vector3(0.012, 0.3, w - 0.1), Vector3(fx + 0.06, h + 0.2, at.z), Color(0.05, 0.08, 0.15), false), Color(0.05, 0.08, 0.15), 0.3)
	_lbl("ENTRÉE", Vector3(fx + 0.075, h + 0.2, at.z), 40, Color(1, 0.95, 0.8), 0.0032)
	# deux vantaux vitrés
	for side in [-1, 1]:
		var cz: float = at.z + side * w / 4
		for bar in [[Vector3(0.06, h, 0.06), Vector3(0, h / 2, -w / 4 + 0.03)], [Vector3(0.06, h, 0.06), Vector3(0, h / 2, w / 4 - 0.03)],
				[Vector3(0.06, 0.18, w / 2), Vector3(0, 0.09, 0)], [Vector3(0.06, 0.06, w / 2), Vector3(0, h - 0.03, 0)]]:
			_metal(Build.box(self, bar[0], Vector3(fx + 0.07, 0, cz) + bar[1], alu, false), 0.35)
		var g := Build.box(self, Vector3(0.012, h - 0.25, w / 2 - 0.12), Vector3(fx + 0.07, h / 2 + 0.06, cz), Color(0.8, 0.9, 1.0, 0.15), false)
		_glass(g, Color(0.90, 0.95, 1.0, 0.14), 0.07)
		# barre de poussée chromée
		_metal(Build.box(self, Vector3(0.035, 0.035, w / 2 - 0.3), Vector3(fx + 0.13, 1.05, cz), Color(0.82, 0.83, 0.85), false), 0.15)
		for k in [-1, 1]:
			_metal(Build.box(self, Vector3(0.06, 0.03, 0.03), Vector3(fx + 0.1, 1.05, cz + k * (w / 4 - 0.18)), Color(0.82, 0.83, 0.85), false), 0.15)
	# détecteur d'ouverture et paillasson
	_glow(Build.box(self, Vector3(0.06, 0.05, 0.2), Vector3(fx + 0.1, h + 0.42, at.z), Color(0.15, 0.15, 0.17), false), Color(0.9, 0.2, 0.15), 0.3)
	_tiles(Build.box(self, Vector3(1.0, 0.015, w - 0.1), Vector3(fx + 0.55, 0.008, at.z), Color.WHITE, false),
		Vector2(0.02, 2.0), 0.0, 0.006, Color(0.22, 0.22, 0.24), Color(0.1, 0.1, 0.11), 0.05, 0.3, 1.0)


# ------------------------------------------------------------------ palier 1 : réglages moteur HD + arêtes biseautées

## Anticrénelage TAA, ombres douces haute résolution (PCSS), SSAO/SSIL en haute qualité.
func _hd_render_settings() -> void:
	var vp := get_viewport()
	if QUALITY_HIGH:
		vp.use_taa = true
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.msaa_3d = Viewport.MSAA_2X
	vp.positional_shadow_atlas_size = 8192 if QUALITY_HIGH else 4096
	RenderingServer.directional_shadow_atlas_set_size(8192 if QUALITY_HIGH else 4096, true)
	var sq := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if QUALITY_HIGH else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(sq)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if QUALITY_HIGH else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, not QUALITY_HIGH, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if QUALITY_HIGH else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, not QUALITY_HIGH, 0.5, 4, 50.0, 300.0)
	RenderingServer.screen_space_roughness_limiter_set_active(true, 0.25, 0.18)   # moins de scintillement sur les reflets
	# ombres douces qui s'élargissent avec la distance (comme dans la réalité)
	for l in find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).light_angular_distance = 0.6
	for l in find_children("*", "OmniLight3D", true, false):
		var o := l as OmniLight3D
		o.light_size = 0.08
		o.shadow_blur = 1.2
	for l in find_children("*", "SpotLight3D", true, false):
		(l as SpotLight3D).light_size = 0.05


var _bevel_cache := {}


## Remplace les boîtes du décor par des boîtes aux arêtes chanfreinées : la lumière accroche les angles.
## Les très grandes surfaces (sols, murs) et les matériaux inconnus (ex. parquet) ne sont pas touchés.
func _bevel_all(known_shaders: Array) -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not (mi.mesh is BoxMesh):
			continue
		var mo := mi.material_override
		if mo is ShaderMaterial and not known_shaders.has((mo as ShaderMaterial).shader):
			continue
		var sz: Vector3 = (mi.mesh as BoxMesh).size
		var mn := minf(sz.x, minf(sz.y, sz.z))
		var mx := maxf(sz.x, maxf(sz.y, sz.z))
		if mn < 0.008 or mx > 6.0:
			continue
		var r := clampf(mn * 0.18, 0.002, 0.02)
		var key := "%.4f_%.4f_%.4f_%.4f" % [sz.x, sz.y, sz.z, r]
		if not _bevel_cache.has(key):
			_bevel_cache[key] = _chamfer_box(sz, r)
		mi.mesh = _bevel_cache[key]


## Boîte chanfreinée : 6 faces, 12 biseaux d'arête, 8 coins.
func _chamfer_box(size: Vector3, r: float) -> ArrayMesh:
	var h := size * 0.5
	var inner := h - Vector3(r, r, r)
	# point du coin s (signes ±1) sur la face perpendiculaire à l'axe a
	var P := func(a: int, s: Vector3) -> Vector3:
		var p := Vector3(s.x * inner.x, s.y * inner.y, s.z * inner.z)
		p[a] = s[a] * h[a]
		return p
	var tris: Array = []
	var add_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		tris.append([a, b, c])
		tris.append([a, c, d])
	# faces principales
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			var pts: Array = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var s := Vector3.ZERO
				s[a] = sa
				s[u] = uv.x
				s[v] = uv.y
				pts.append(P.call(a, s))
			add_quad.call(pts[0], pts[1], pts[2], pts[3])
	# biseaux d'arête
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var s1 := Vector3.ZERO
				s1[a] = sa
				s1[b] = sb
				s1[c] = -1.0
				var s2 := s1
				s2[c] = 1.0
				add_quad.call(P.call(a, s1), P.call(b, s1), P.call(b, s2), P.call(a, s2))
	# coins
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				tris.append([P.call(0, s), P.call(1, s), P.call(2, s)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var cr := (p1 - p0).cross(p2 - p0)
		if cr.length() < 1e-9:
			continue
		var centroid := (p0 + p1 + p2) / 3.0
		# Godot : faces avant en sens horaire vu de l'extérieur
		if cr.dot(centroid) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
			cr = -cr
		var nrm := (-cr).normalized()
		for p in [p0, p1, p2]:
			st.set_normal(nrm)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)
	return st.commit()


# ------------------------------------------------------------------ matériaux gare : bois et verre
var _wood_shader: Shader
var _ground_materials := {}

func _ground(n: Node, kind: String) -> Node:
	var mesh := _mesh_of(n)
	if mesh and mesh.material_override is ShaderMaterial:
		mesh.set_meta("gare_ground", kind)
		var material := mesh.material_override as ShaderMaterial
		var kinds := {"road": 1, "paving": 2, "grass": 3, "quay": 4}
		material.set_shader_parameter("ground_kind", kinds[kind])
		_ground_materials[kind] = material
	return n


func _glass(n: Node, color: Color, roughness := 0.08) -> Node:
	var material := _own_mat(n)
	if material:
		material.albedo_color = color
		material.metallic = 0.0
		material.metallic_specular = 0.5
		material.roughness = roughness
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	var mesh := _mesh_of(n)
	if mesh: mesh.set_meta("gare_glass", true)
	return n


const WOOD_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.56, 0.36, 0.19, 1.0);
uniform float board_seed = 0.0;
uniform float plank_width = 0.0;
varying vec3 lp;
varying vec3 local_normal;
varying vec3 wp;
varying vec3 normal_world;
float wood_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float wood_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wood_hash(i), wood_hash(i + vec2(1,0)), f.x), mix(wood_hash(i + vec2(0,1)), wood_hash(i + vec2(1,1)), f.x), f.y);
}
void vertex() {
	lp = VERTEX;
	local_normal = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float across = abs(local_normal.y) > abs(local_normal.x) ? lp.x : lp.y;
	float seed = board_seed;
	float joint = 0.0;
	if (plank_width > 0.0) {
		float row = floor(lp.x / plank_width);
		vec2 board_uv = vec2(lp.x / plank_width, (lp.z + mod(row, 2.0) * 1.2) / 2.4);
		seed += wood_hash(floor(board_uv)) * 19.0;
		vec2 edge = min(fract(board_uv), 1.0 - fract(board_uv)) * vec2(plank_width, 2.4);
		float d = min(edge.x, edge.y);
		joint = 1.0 - smoothstep(0.0003, 0.0008 + fwidth(d), d);
	}
	float warp = wood_noise(vec2(lp.z * 1.6 + seed, across * 5.0));
	float phase = across * 400.0 + warp * 3.5 + seed * 5.0;
	float filtered = 1.0 - smoothstep(0.6, 2.2, fwidth(phase));
	float grain = mix(0.28, pow(0.5 + 0.5 * sin(phase), 4.0), filtered);
	float broad = wood_noise(vec2(across * 65.0 + seed, lp.z * 1.8));
	float pores = wood_noise(vec2(across * 250.0, lp.z * 11.0 + seed));
	float board_tone = 0.95 + wood_hash(vec2(seed, 4.7)) * 0.10;
	ALBEDO = base_color.rgb * board_tone * (0.98 + 0.12 * broad - 0.12 * grain);
	ALBEDO = mix(ALBEDO, base_color.rgb * 0.64, joint);
	ROUGHNESS = clamp(0.68 + 0.07 * broad + 0.035 * pores + joint * 0.12, 0.0, 1.0);
	SPECULAR = 0.32;
	float height = (broad * 0.5 + grain * 0.2 + pores * 0.3) * 0.00013 - joint * 0.0005;
	vec3 dx = dFdx(wp); vec3 dy = dFdy(wp);
	vec3 r1 = cross(dy, normal_world); vec3 r2 = cross(normal_world, dx);
	float det = dot(dx, r1);
	vec3 slope = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	vec3 bumped = abs(det) * normal_world - slope;
	if (dot(bumped, bumped) > 1e-16) NORMAL = normalize((VIEW_MATRIX * vec4(normalize(bumped), 0.0)).xyz);
}
"""
