extends Node3D

class_name NSFWInteraction

# Types d'interaction
enum InteractionType {
    LOOK = 0,        # Regarder
    TOUCH_HAND = 1,  # Toucher la main
    TOUCH_LEG = 2,   # Toucher la jambe
    KISS = 3         # Embrasser
}

# Variables d'état
var current_target: Node3D = null
var intimacy_level: int = 0  # 0-100
var is_interacting: bool = false
var interaction_cooldown: float = 2.0
var last_interaction_time: float = 0.0

# Réactions des personnages (par ID)
const CHARACTER_REACTIONS = {
    "marie_rose": {
        "touch_hand": ["Hmm...", "Oh... euh...", "C'est... pas mal"],
        "touch_leg": ["Ah...", "Mmm...", "Tu es audacieux..."],