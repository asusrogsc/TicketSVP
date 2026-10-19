class_name Player
extends CharacterBody3D
## Contrôleur FPS : souris pour regarder, ZQSD pour marcher, Maj pour courir, E pour interagir.

signal interacted(target: Node)

const WALK := 3.2
const RUN := 5.5
const JUMP := 4.2
const SENS := 0.0025

var camera: Camera3D
var ray: RayCast3D
var frozen := false        # bloqué pendant les menus
var hud: Hud


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
	add_child(col)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 75
	camera.near = 0.03
	add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.2)
	ray.collide_with_areas = true
	ray.collision_mask = 1 | 2          # décor + passagers
	collision_mask = 1                  # les passagers ne bloquent pas
	ray.add_exception(self)
	camera.add_child(ray)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENS)
		camera.rotate_x(-event.relative.y * SENS)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	elif event.is_action_pressed("interagir"):
		var t := looked_at()
		if t:
			interacted.emit(t)
	elif event.is_action_pressed("clic") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## L'objet visé qui sait interagir (méthode `interact_label`).
func looked_at() -> Node:
	if not ray.is_colliding():
		return null
	var n: Node = ray.get_collider()
	while n and not n.has_method("interact_label"):
		n = n.get_parent()
	return n


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var dir := Vector3.ZERO
	if not frozen:
		if Input.is_action_just_pressed("sauter") and is_on_floor():
			velocity.y = JUMP
		var v := Input.get_vector("gauche", "droite", "avancer", "reculer")
		dir = (transform.basis * Vector3(v.x, 0, v.y)).normalized()
	var speed := RUN if Input.is_action_pressed("courir") else WALK
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
	if hud:
		var t := looked_at() if not frozen else null
		hud.set_prompt(t.interact_label() if t else "")
