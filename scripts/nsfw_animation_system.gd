# nsfw_animation_system.gd
extends Node3D

class_name NSFWAnimationSystem

# Types d'animations
enum AnimationType {
    IDLE = 0,
    LOOK_AT_TARGET = 1,
    LEAN_FORWARD = 2,
    REACH_HAND = 3,
    TOUCH_HAND = 4,
    REACH_LEG = 5,
    TOUCH_LEG = 6,
    KISS_APPROACH = 7,
    KISS = 8,
    PULL_BACK = 9,
    FLUSHED = 10,
    SHY = 11,
    EXCITED = 12
}

# Variables d'état
var current_animation: AnimationType = AnimationType.IDLE
var animation_progress: float = 0.0
var is_animating: bool = false
var target_character: Node3D = null
var intimacy_level: int = 0

# Timings des animations (en secondes)
const ANIMATION_TIMINGS = {