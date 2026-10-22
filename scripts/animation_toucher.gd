# --- Contenu de Animation_Toucher.gd ---
extends Node3D # Ou autre type de nœud si Oldman est un CharacterBody3D, etc.

# Fonction qui sera appelée par Scene_Controller quand il détecte la proximité !
func trigger_touch():
	print("--- [Oldman] ✋ Geste lancé : La main se lève pour toucher Mzelle ! ---")
	# ICI, vous mettez le code de votre animation (ex: $AnimationPlayer.play("Toucher"))
