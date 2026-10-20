extends Node
## Données globales : lignes, carrière du joueur, résultat du dernier trajet, touches.

const SAVE_PATH := "user://carriere.json"

var lines := [
	{
		"id": 1, "name": "Ligne 1", "type": "Bus", "color": Color(0.1, 0.55, 0.95),
		"from": "Gare Centrale", "to": "Université",
		# Chaque arrêt :  nom,  route = secondes de trajet pour y arriver depuis l'arrêt précédent,
		#                 arret = secondes portes ouvertes (pour le 1er arrêt : attente avant le départ).
		# Sans "route" / "arret", les valeurs par défaut de bus.gd (LEG_TIME / STOP_TIME) s'appliquent.
		"stops": [
			{"nom": "Gare Centrale",      "arret": 5},
			{"nom": "Place du Marché",    "route": 30, "arret": 8},
			{"nom": "Hôpital Saint-Luc",  "route": 25, "arret": 12},
			{"nom": "Parc des Cerisiers", "route": 35, "arret": 6},
			{"nom": "Université",         "route": 30},
		],
		"unlocked": true,
	},
	{
		"id": 2, "name": "Ligne 2", "type": "Tram", "color": Color(0.9, 0.35, 0.2),
		"from": "Port", "to": "Stade", "stops": [], "unlocked": false,
	},
]
var current_line: Dictionary = {}      # ligne jouée par bus.gd (aller, ou aller inversé pour le retour)
var last_result: Dictionary = {}
var selected_line: Dictionary = {}     # ligne choisie dans le hall
var trip_leg := "aller"                # "aller" ou "retour"
var aller_result: Dictionary = {}      # stats de l'aller, présentées au chef de gare
var station_boarders: Array = []       # passagers qui attendaient à la gare et montent au retour
var career := {"trajets": 0, "argent": 0, "meilleur_score": 0}

# date du jour du jeu (jour, mois, année)
var today := {"d": 19, "m": 10, "y": 2026}


func _ready() -> void:
	_setup_inputs()
	_load()
	if "--keytest" in OS.get_cmdline_user_args():
		add_child(load("res://tests/keys.gd").new())
	if "--specialtest" in OS.get_cmdline_user_args():
		add_child(load("res://tests/specials.gd").new())
	if "--inspect" in OS.get_cmdline_user_args():
		add_child(load("res://tests/inspect.gd").new())
	if "--autotest" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/autotest.gd").new())


func _setup_inputs() -> void:
	# touches physiques : sur un clavier AZERTY, ZQSD tombent sur les emplacements WASD
	var map := {
		"avancer": [KEY_W, KEY_UP], "reculer": [KEY_S, KEY_DOWN],
		"gauche": [KEY_A, KEY_LEFT], "droite": [KEY_D, KEY_RIGHT],
		"sauter": [KEY_SPACE], "courir": [KEY_SHIFT], "interagir": [KEY_E],
		"valider": [KEY_1, KEY_V], "amende": [KEY_2, KEY_F], "pause": [KEY_ESCAPE],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("clic"):
		InputMap.add_action("clic")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("clic", mb)


func start_line(line: Dictionary) -> void:
	selected_line = line
	trip_leg = "aller"
	aller_result = {}
	station_boarders = []
	current_line = line
	get_tree().change_scene_to_file("res://scenes/bus.tscn")


## Appelé par bus.gd au terminus : aller -> gare, retour -> bilan.
func end_leg(result: Dictionary) -> void:
	if trip_leg == "aller":
		aller_result = result
		get_tree().change_scene_to_file("res://scenes/gare.tscn")
	else:
		finish_trip(_merge_results(aller_result, result))


## Appelé par gare.gd après le rapport : trajet retour avec les passagers de la gare.
func start_return(boarders: Array) -> void:
	station_boarders = boarders
	trip_leg = "retour"
	current_line = reversed_line(selected_line if not selected_line.is_empty() else lines[0])
	get_tree().change_scene_to_file("res://scenes/bus.tscn")


## La même ligne dans l'autre sens (arrêts inversés, temps de route recalculés).
func reversed_line(line: Dictionary) -> Dictionary:
	var r := line.duplicate(true)
	r.from = line.to
	r.to = line.from
	r.retour = true
	var s: Array = line.stops
	var n := s.size()
	var out := []
	for k in n:
		var src = s[n - 1 - k]
		var d: Dictionary = src.duplicate() if src is Dictionary else {"nom": str(src)}
		d.erase("route")
		if k > 0 and s[n - k] is Dictionary and s[n - k].has("route"):
			d.route = s[n - k].route        # temps entre les deux mêmes arrêts qu'à l'aller
		if k == 0:
			d.arret = 5                     # attente au départ du retour (embarquement)
		out.append(d)
	r.stops = out
	return r


func _merge_results(a: Dictionary, b: Dictionary) -> Dictionary:
	var m := a.duplicate(true)
	for k in b:
		var v = b[k]
		if m.has(k) and (m[k] is int or m[k] is float) and (v is int or v is float):
			m[k] += v
		elif m.has(k) and m[k] is Array and v is Array:
			m[k] = m[k] + v
		else:
			m[k] = v
	m.aller_score = int(a.get("score", 0))
	m.retour_score = int(b.get("score", 0))
	var l := selected_line if not selected_line.is_empty() else current_line
	m.line = "%s %s : %s ⇄ %s (aller-retour)" % [l.type, l.name, l.from, l.to]
	return m


func finish_trip(result: Dictionary) -> void:
	last_result = result
	career.trajets += 1
	career.argent += int(result.get("amendes_euros", 0)) / 10 + 25   # salaire du trajet + prime
	career.meilleur_score = max(career.meilleur_score, int(result.get("score", 0)))
	_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/bilan.tscn")


func go_home() -> void:
	get_tree().change_scene_to_file("res://scenes/hall.tscn")


func date_str(d: Dictionary) -> String:
	return "%02d/%02d/%d" % [d.d, d.m, d.y]


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(career))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			for k in data:
				career[k] = data[k]
				
# À ajouter dans game.gd
var nsfw_unlocked := false          # ou débloqué en carrière
var nsfw_settings := {
	"enabled": true,
	"explicit_level": 1,            # 0 off, 1 suggestif, 2 explicite
}

func start_nsfw(scene_path: String, return_to: String = "res://scenes/bus.tscn") -> void:
	last_result["nsfw_return"] = return_to
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # ou capturé selon la scène
	get_tree().change_scene_to_file(scene_path)

func end_nsfw() -> void:
	var path: String = last_result.get("nsfw_return", "res://scenes/hall.tscn")
	get_tree().change_scene_to_file(path)
