extends Node
## Données globales : lignes, carrière du joueur, résultat du dernier trajet, touches.

const SAVE_PATH := "user://carriere.json"

var lines := [
	{
		"id": 1, "name": "Ligne 1", "type": "Bus", "color": Color(0.1, 0.55, 0.95),
		"from": "Gare Centrale", "to": "Université",
		"stops": ["Gare Centrale", "Place du Marché", "Hôpital Saint-Luc", "Parc des Cerisiers", "Université"],
		"unlocked": true,
	},
	{
		"id": 2, "name": "Ligne 2", "type": "Tram", "color": Color(0.9, 0.35, 0.2),
		"from": "Port", "to": "Stade", "stops": [], "unlocked": false,
	},
]
var current_line: Dictionary = {}
var last_result: Dictionary = {}
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
	current_line = line
	get_tree().change_scene_to_file("res://scenes/bus.tscn")


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
