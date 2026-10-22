extends RefCounted
## Marche visuelle : suit les déplacements locaux ; ne pilote ni trajet ni collision.
var passenger: Node3D
var previous := Vector3.ZERO
var seated := true
var phase := 0.0
var amount := 0.0
var active := false
var rest_y := 0.0
var fallback: Node3D
var hidden_legs: Array[Node3D] = []
var fallback_limbs: Array[Node3D] = []
var ordinary_nodes: Array[Node3D] = []
var ordinary_rest: Array[Transform3D] = []

func _init(p: Node3D) -> void:
	passenger=p
	previous=p.position

func set_seated(value: bool) -> void:
	seated=value
	previous=passenger.position
	if value:
		reset()

func reset() -> void:
	if active:passenger.visual.position.y=rest_y
	active=false
	amount=0.0
	passenger.visual.rotation.y=0.0
	passenger.visual.rotation.z=0.0
	if passenger.fit:
		passenger.fit.walk_reset()
	if passenger.ordinary_visual:
		passenger.ordinary_visual.position.y=0.0
		for i in ordinary_nodes.size():
			if is_instance_valid(ordinary_nodes[i]):ordinary_nodes[i].transform=ordinary_rest[i]
		ordinary_nodes.clear()
		ordinary_rest.clear()
	if fallback:
		fallback.visible=false
		for node in hidden_legs:node.visible=true

func update(delta: float) -> void:
	var displacement: Vector3=passenger.position-previous
	previous=passenger.position
	var vertical:=absf(displacement.y)
	displacement.y=0.0
	if seated or delta<=0.0:return
	var distance:=displacement.length()
	# Placement initial / téléportation : pas un pas de marche.
	var moving:=distance>0.0005 and distance<0.35 and vertical<maxf(0.015,distance*0.6)
	var target:=clampf(distance/maxf(delta,0.001)/0.65,0.0,1.0) if moving else 0.0
	if passenger.has_meta("no_walk_animation"):target=0.0
	if moving and not active:
		rest_y=passenger.visual.position.y
		active=true
	amount=lerpf(amount,target,1.0-exp(-12.0*delta))
	if moving:
		phase=fposmod(phase+distance/1.05*TAU,TAU)
		var yaw:=atan2(-displacement.x,-displacement.z)-passenger.rotation.y
		passenger.visual.rotation.y=lerp_angle(passenger.visual.rotation.y,yaw,1.0-exp(-14.0*delta))
	else:
		passenger.visual.rotation.y=lerp_angle(passenger.visual.rotation.y,0.0,1.0-exp(-8.0*delta))
		if amount<0.002:
			if amount>0.0:reset()
			return
	passenger.visual.rotation.z=sin(phase)*0.012*amount
	if active:passenger.visual.position.y=rest_y-support_drop()
	if passenger.fit:
		passenger.fit.walk_update(phase,amount)
	elif passenger.ordinary_visual:
		var root: Node3D=passenger.ordinary_visual
		var pose:=root.get_node("Pose")
		if ordinary_nodes.is_empty():
			for child in pose.get_children():
				ordinary_nodes.append(child as Node3D)
				ordinary_rest.append((child as Node3D).transform)
		animate_limbs(ordinary_nodes,phase,amount,1.0,0.0)
		root.position.y=0.0
	else:
		_fallback_update()

# Réutilise les 12 meshes existants de la pose ordinaire : aucune allocation de mesh par image.
static func animate_limbs(nodes: Array[Node3D], angle: float, blend: float, scale_factor: float, y_offset: float) -> void:
	if nodes.size()!=12:return
	for side_index in 2:
		var side: float=-1.0 if side_index==0 else 1.0
		var wave:=sin(angle+PI*side_index)
		var thigh:=wave*0.34*blend
		var knee_bend: float=-maxf(0.0,-wave)*0.62*blend
		var hip:=Vector3(side*0.085,0.84,0.01)
		var knee:=hip+Basis(Vector3.RIGHT,thigh)*Vector3(0,-0.38,0)
		var ankle:=knee+Basis(Vector3.RIGHT,thigh+knee_bend)*Vector3(0,-0.36,0)
		var shoulder:=Vector3(side*0.17,1.40,0)
		var arm_angle: float=-wave*0.23*blend
		var elbow:=shoulder+Basis(Vector3.RIGHT,arm_angle)*Vector3(side*0.06,-0.30,-0.025)
		var wrist:=elbow+Basis(Vector3.RIGHT,arm_angle-0.10*blend)*Vector3(-side*0.01,-0.18,-0.020)
		var offset:=Vector3(0,y_offset,0)
		var i:=side_index*6
		place_limb(nodes[i],hip*scale_factor+offset,knee*scale_factor+offset)
		place_limb(nodes[i+1],knee*scale_factor+offset,ankle*scale_factor+offset)
		nodes[i+2].position=(ankle+Vector3(0,-0.036,-0.055))*scale_factor+offset
		nodes[i+2].rotation.x=thigh*0.35
		place_limb(nodes[i+3],shoulder*scale_factor+offset,elbow*scale_factor+offset)
		place_limb(nodes[i+4],elbow*scale_factor+offset,wrist*scale_factor+offset)
		nodes[i+5].position=(wrist+Vector3(0,-0.015,-0.015))*scale_factor+offset

static func place_limb(node: Node3D,a: Vector3,b: Vector3) -> void:
	node.position=(a+b)*0.5
	node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())

func _fallback_update() -> void:
	if passenger.data.get("cactus",false):
		# Le Pampa n'a pas de jambes : petit dandinement, pas de membres inventés.
		return
	if fallback==null:
		fallback=Node3D.new()
		fallback.name="WalkingLimbs"
		var original: Array=passenger.visual.get_children()
		for i in mini(2,original.size()):
			if original[i] is MeshInstance3D:hidden_legs.append(original[i])
		passenger.visual.add_child(fallback)
		var ov=preload("res://scripts/ordinary_visual.gd")
		var s: float=passenger.data.get("scale",0.9 if passenger.data.get("small",false) else 1.0)
		for side in [-1.0,1.0]:
			ov.limb(fallback,Vector3(side*.085,.84,0)*s,Vector3(side*.085,.46,0)*s,.074*s,passenger.data.legs)
			ov.limb(fallback,Vector3(side*.085,.46,0)*s,Vector3(side*.085,.10,0)*s,.052*s,passenger.data.legs)
			ov.ellipsoid(fallback,Vector3.ZERO,Vector3(.125,.10,.25)*s,Color(.09,.085,.08))
			ov.limb(fallback,Vector3(side*.17,1.40,0)*s,Vector3(side*.23,1.10,0)*s,.057*s,passenger.data.body)
			ov.limb(fallback,Vector3(side*.23,1.10,0)*s,Vector3(side*.22,.92,0)*s,.045*s,passenger.data.body)
			ov.ellipsoid(fallback,Vector3.ZERO,Vector3(.065,.095,.042)*s,passenger.data.skin)
		for child in fallback.get_children():fallback_limbs.append(child as Node3D)
	fallback.visible=true
	for node in hidden_legs:node.visible=false
	var factor: float=passenger.data.get("scale",0.9 if passenger.data.get("small",false) else 1.0)
	# visual est déjà relevé de 0.25 m par la pose de secours existante.
	animate_limbs(fallback_limbs,phase,amount,factor,-rest_y)


# Compensation verticale approximative de la jambe d'appui, sans déplacer
# le corps physique ni imposer une IK au sol aux modèles du projet.
func support_drop() -> float:
	var leg_length:=0.74
	var amplitude:=0.34
	if passenger.fit:
		leg_length=passenger.fit.box.size.y*passenger.fit.k*0.50
		amplitude=deg_to_rad(23.0)
	elif passenger.ordinary_visual==null:
		leg_length*=float(passenger.data.get("scale",0.9 if passenger.data.get("small",false) else 1.0))
	return leg_length*(1.0-cos(sin(phase)*amplitude*amount))
