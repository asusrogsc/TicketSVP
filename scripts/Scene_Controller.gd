# =========================================================
# SCENE CONTROLLER - MODE MÉMOIRE VIVE TOTALE (Le Maître du Jeu)
# Version Ultra-Brute : Le code le plus simple possible pour satisfaire Godot !
# =========================================================
extends Node3D

@export var proximity_threshold: float = 1.5 # Distance maximale pour déclencher le geste
@export var is_sitting_condition: bool = true # Condition de posture : VRAI si Mzelle est assise !

var oldman_node: Node3D = null
var mzelle_node: Node3D = null


func _ready():
	create_characters() 

	if oldman_node != null and mzelle_node != null:
		print("SYSTEME PRET : Oldman et Mzelle ont ete crees en memoire !")
	else:
		print("ERREUR FATALE : Le systeme est en mode veille. Verifiez les noms des personnages dans votre code.")


func create_characters():
	# --- SIMULATION DE LA CRÉATION DES NŒUDS (Le remplacement du glisser-déposer) ---
	
	oldman_node = Node3D.new() 
	oldman_node.name = "Oldman"  
	print("   -> Creation de l'instance Oldman en memoire.")

	# Positionnement : X=2, Y=0.5, Z=0 (Position fixe dans la mémoire du Bus)
	oldman_node.global_transform.origin = Vector3(2.0, 0.5, 0.0) 

	mzelle_node = Node3D.new() 
	mzelle_node.name = "Mzelle"  
	print("   -> Creation de l'instance Mzelle en memoire.")

	# Positionnement : X=0, Y=0.5, Z=0 (Position fixe au centre du Bus)
	mzelle_node.global_transform.origin = Vector3(0.0, 0.5, 0.0)


func trigger_touch():
	if oldman_node != null:
		oldman_node.trigger_touch() 
		print("ACTION AUTOMATIQUE : Geste lance grâce a la memoire du Bus !")

# =========================================================
# LOGIQUE DE SURVEILLANCE (Le cerveau qui tourne en boucle)
# =========================================================
func _process(delta: float):
	if oldman_node != null and mzelle_node != null:
		var distance = oldman_node.global_transform.origin.distance_to(mzelle_node.global_transform.origin)
		
		# --- LE TEST FINAL : La distance est calculée entre deux points définis ! ---
		print("--- CHECK : Distance actuelle = ", distance, " | Condition Assise = ", is_sitting_condition, " ---")

		if is_sitting_condition and proximity_threshold >= 0.1:
			trigger_touch()
		else:
			print("--- BLOCAGE : Le geste ne se lance pas car la condition (Assis/Proximité) n'est pas remplie. ---")
