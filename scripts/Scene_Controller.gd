# =========================================================
# SCENE CONTROLLER - MODE MÉMOIRE VIVE TOTALE (Le Maître du Jeu)
# Ce script est la version la plus pure. Il ne dépend de RIEN d'autre que lui-même !
# =========================================================
extends Node3D # <-- C'est probablement cette ligne 12 qui pose problème !

# --- PARAMÈTRES DE DÉTECTION (À AJUSTER dans l'Inspecteur !) ---
@export var proximity_threshold: float = 1.5 # Distance maximale pour déclencher le geste
@export var is_sitting_condition: bool = true # Condition de posture : VRAI si Mzelle est assise !

# --- VARIABLES DE DONNÉES (Les personnages créés en mémoire) ---
var oldman_node: Node3D = null
var mzelle_node: Node3D = null


func _ready():
	create_characters() # Appel de la fonction qui crée les instances en mémoire !

	if oldman_node != null and mzelle_node != null:
		print("SYSTEME PRET : Oldman et Mzelle ont ete crees en memoire !")
	else:
		print("ERREUR FATALE : Le systeme est en mode veille. Verifiez les noms des personnages dans votre code.")


func create_characters():
	# --- SIMULATION DE LA CRÉATION DES NŒUDS (Le remplacement du glisser-déposer) ---
	
	oldman_node = Node3D.new() 
	oldman_node.name = "Oldman"  
	print("   -> Creation de l'instance Oldman en memoire.")

	mzelle_node = Node3D.new() 
	mzelle_node.name = "Mzelle"  
	print("   -> Creation de l'instance Mzelle en memoire.")


func trigger_touch():
	if oldman_node != null:
		oldman_node.trigger_touch() 
		print("ACTION AUTOMATIQUE : Geste lance grâce a la memoire du Bus !")

# =========================================================
# LOGIQUE DE SURVEILLANCE (Le cerveau qui tourne en boucle)
# =========================================================
func _process(delta: float):
	if oldman_node != null and mzelle_node != null:
		var distance = global_transform.origin.distance_to(mzelle_node.global_transform.origin)
		
		if is_sitting_condition and proximity_threshold >= 0.1:
			trigger_touch()
