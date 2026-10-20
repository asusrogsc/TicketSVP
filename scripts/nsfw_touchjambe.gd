extends Node3D

class_name TouchInteraction

# Variables d'état
var current_target: CharacterBody3D = null
var is_touching: bool = false
var touch_progress: float = 0.0
var intimacy_level: int = 0
var reaction_type: String = ""

# Timings
const TOUCH_DURATION = 2.0  # secondes pour toucher la jambe
const HOLD_DURATION = 1.5   # secondes à tenir
const PULL_BACK_DURATION = 1.0  # secondes pour retirer

# Zones de contact sur la jambe (de bas en haut)
enum TouchZone {
    ANKLE = 0,      # Cheville
    CALF = 1,       # Mollet