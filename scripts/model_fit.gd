class_name ModelFit
## Adapte un modèle .glb importé : taille, orientation, pose assise / debout.
##  - modèle avec squelette : on plie les os (cuisses, genoux, bras) ;
##  - modèle sans squelette : on déforme directement les sommets (hanches, genoux,
##    et bras baissés si le modèle est en « T »).
## Le modèle doit regarder vers +Z (convention glTF / Sketchfab) ; le passager, lui, regarde vers -Z.

const SEAT_HIP := Vector3(0, 0.55, 0.06)   # où placer la hanche sur un siège du bus

var root: Node3D          # le modèle instancié
var holder: Node3D        # pivot : demi-tour + mise à l'échelle
var k := 1.0              # échelle appliquée
var box: AABB             # boîte englobante dans l'espace du modèle
var hip := Vector3.ZERO   # articulation de la hanche (espace du modèle)
var skel: Skeleton3D
var _rel_skel: Transform3D
var _bones := {}
var _static_meshes := []  # [{mi, rest: ArrayMesh, rel: Transform3D}]
var _body := Vector3.ZERO # axe du corps (moyenne des sommets des jambes ; les cheveux décalent la boîte)
var _arm_drop := 0.0      # de combien de degrés baisser les bras (0 si déjà le long du corps)
static var _cache := {}


func _init(path: String, parent: Node3D, height := 0.0) -> void:
	holder = Node3D.new()
	holder.rotation_degrees.y = 180.0
	parent.add_child(holder)
	root = load(path).instantiate()
	holder.add_child(root)
	var sks := root.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if sks.size() > 0 else null
	if skel:
		_rel_skel = root.global_transform.affine_inverse() * skel.global_transform
		_find_bones()
		box = _skinned_box()
		hip = _rel_skel * skel.get_bone_global_rest(_bones.hip).origin if _bones.has("hip") else box.get_center()
	else:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh:
				_static_meshes.append({"mi": mi, "rest": mi.mesh, "rel": root.global_transform.affine_inverse() * mi.global_transform})
		box = _static_box()
		_measure_static()
		hip = Vector3(_body.x, box.position.y + 0.52 * box.size.y, _body.z)
	if height <= 0.0:
		height = box.size.y if skel else 1.65
	k = height / max(box.size.y, 0.001)
	root.scale = Vector3.ONE * k
	_cache_key = path


var _cache_key := ""


## Pose debout ou assise (hanche posée sur le siège).
func set_seated(seated: bool) -> void:
	if skel:
		_pose_skeleton(seated)
	else:
		_pose_static(seated)
	if seated:
		root.position = SEAT_HIP * Vector3(1, 1, -1) - hip * k   # (demi-tour : -Z du passager = +Z du modèle)
		root.position.x = -hip.x * k
	else:
		root.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * k


# ---------------------------------------------------------------- squelette
func _find_bones() -> void:
	var want := {
		"hip": ["C_Hip_a", "Hips", "mixamorig:Hips", "pelvis", "Pelvis"],
		"l_thigh": ["L_UpperLeg_a", "LeftUpLeg", "thigh_l", "L_Thigh"],
		"r_thigh": ["R_UpperLeg_a", "RightUpLeg", "thigh_r", "R_Thigh"],
		"l_shin": ["L_LowerLeg_a", "L_Knee_a", "LeftLeg", "calf_l", "L_Calf"],
		"r_shin": ["R_LowerLeg_a", "R_Knee_a", "RightLeg", "calf_r", "R_Calf"],
		"l_arm": ["L_UpperArm_a", "LeftArm", "upperarm_l"],
		"r_arm": ["R_UpperArm_a", "RightArm", "upperarm_r"],
		"l_fore": ["L_ForeArm_a", "L_LowerArm_a", "LeftForeArm", "lowerarm_l"],
		"r_fore": ["R_ForeArm_a", "R_LowerArm_a", "RightForeArm", "lowerarm_r"],
	}
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		for key in want:
			if _bones.has(key):
				continue
			for w in want[key]:
				if n == w or n.ends_with(":" + w) or (n.begins_with(w + "_") and not ("Spo" in n or "End" in n)):
					_bones[key] = i
					break
	# genou / avant-bras introuvables par nom : premier enfant « principal » de l'os parent
	for pair in [["l_shin", "l_thigh"], ["r_shin", "r_thigh"], ["l_fore", "l_arm"], ["r_fore", "r_arm"]]:
		if not _bones.has(pair[0]) and _bones.has(pair[1]):
			for c in skel.get_bone_children(_bones[pair[1]]):
				var cn := skel.get_bone_name(c)
				if not ("Spo" in cn or "End" in cn or "Twist" in cn or "Roll" in cn):
					_bones[pair[0]] = c
					break


func _skinned_box() -> AABB:
	# boîte d'après les os (le maillage skinné n'a pas de position fiable avant le rendu)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in skel.get_bone_count():
		var p := _rel_skel * skel.get_bone_global_rest(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## Tourne un os autour d'un axe exprimé dans l'espace du modèle (enfants entraînés).
func _turn(b: int, axis_model: Vector3, deg: float) -> void:
	if b < 0:
		return
	var axis := (_rel_skel.basis.inverse() * axis_model).normalized()
	var g := skel.get_bone_global_pose(b)
	var ng := Transform3D(Basis(axis, deg_to_rad(deg)) * g.basis, g.origin)
	var par := skel.get_bone_parent(b)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var loc := pg.affine_inverse() * ng
	skel.set_bone_pose_rotation(b, loc.basis.orthonormalized().get_rotation_quaternion())


func _pose_skeleton(seated: bool) -> void:
	skel.reset_bone_poses()
	var B: Dictionary = _bones
	var arms_down := 72.0
	# bras le long du corps (les modèles sont souvent en T ou en A)
	_turn(B.get("l_arm", -1), Vector3(0, 0, 1), -arms_down)
	_turn(B.get("r_arm", -1), Vector3(0, 0, 1), arms_down)
	if seated:
		_turn(B.get("l_arm", -1), Vector3(1, 0, 0), -20)
		_turn(B.get("r_arm", -1), Vector3(1, 0, 0), -20)
		_turn(B.get("l_fore", -1), Vector3(1, 0, 0), -55)   # mains sur les genoux
		_turn(B.get("r_fore", -1), Vector3(1, 0, 0), -55)
		_turn(B.get("l_thigh", -1), Vector3(1, 0, 0), -88)  # cuisses vers l'avant
		_turn(B.get("r_thigh", -1), Vector3(1, 0, 0), -88)
		_turn(B.get("l_shin", -1), Vector3(1, 0, 0), 85)    # tibias vers le bas
		_turn(B.get("r_shin", -1), Vector3(1, 0, 0), 85)
	else:
		_turn(B.get("l_fore", -1), Vector3(1, 0, 0), -10)
		_turn(B.get("r_fore", -1), Vector3(1, 0, 0), -10)


# ---------------------------------------------------------------- sans squelette
func _static_box() -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for e in _static_meshes:
		var mesh: Mesh = e.rest
		for s in mesh.get_surface_count():
			var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in v:
				var q: Vector3 = e.rel * p
				lo = lo.min(q)
				hi = hi.max(q)
	return AABB(lo, hi - lo)


## Repère le centre du corps et l'angle des bras (modèle en T ou en A).
func _measure_static() -> void:
	var H := box.size.y
	var y0 := box.position.y
	var sum := Vector3.ZERO
	var cnt := 0
	var far := {1: Vector3.ZERO, -1: Vector3.ZERO}
	var pts := []
	for e in _static_meshes:
		var mesh: Mesh = e.rest
		for si in mesh.get_surface_count():
			for p in mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var q: Vector3 = e.rel * p
				pts.append(q)
				if q.y > y0 + 0.1 * H and q.y < y0 + 0.4 * H:
					sum += q
					cnt += 1
	_body = sum / max(cnt, 1)
	# écart des pieds (jambes serrées ou écartées)
	for q in pts:
		if q.y < y0 + 0.08 * H:
			_legs_x = max(_legs_x, abs(q.x - _body.x))
	# main la plus éloignée de chaque côté, au-dessus des hanches
	for q in pts:
		if q.y < y0 + 0.45 * H:
			continue
		var side := 1 if q.x > _body.x else -1
		if abs(q.x - _body.x) > abs(far[side].x - _body.x):
			far[side] = q
	var sh := Vector2(0.105 * H, y0 + 0.815 * H)
	var ang := 0.0
	var n := 0
	for side in far:
		var dx: float = abs(far[side].x - _body.x) - sh.x
		if dx > 0.12 * H:     # bras écarté du corps
			ang += rad_to_deg(atan2(sh.y - far[side].y, dx))
			n += 1
	# les deux bras écartés = pose en T / en A (une mèche ou un seul bras ne suffit pas)
	_arm_drop = clamp(82.0 - ang / n, 0.0, 90.0) if n == 2 else 0.0
	_arm_tan = tan(deg_to_rad(ang / n)) if n > 0 else 0.0


var _arm_tan := 0.0
var _legs_x := 0.0


func _pose_static(seated: bool) -> void:
	var key := "%s|%s" % [_cache_key, seated]
	if not _cache.has(key):
		_cache[key] = _deform_all(seated)
	var meshes: Array = _cache[key]
	for i in _static_meshes.size():
		_static_meshes[i].mi.mesh = meshes[i]


func _deform_all(seated: bool) -> Array:
	var H := box.size.y
	var y0 := box.position.y
	var c := _body
	var tpose := _arm_drop > 5.0
	if not seated and not tpose:
		return _static_meshes.map(func(e): return e.rest)
	var P := {
		"H": H, "c": c, "seated": seated, "tpose": tpose,
		"hip": y0 + 0.52 * H, "knee": y0 + 0.285 * H,
		"sh_y": y0 + 0.815 * H, "sh_x": 0.105 * H,
	}
	var out := []
	for e in _static_meshes:
		var src: Mesh = e.rest
		var dst := ArrayMesh.new()
		var rel: Transform3D = e.rel
		var inv := rel.affine_inverse()
		for s in src.get_surface_count():
			var arr := src.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var has_n := n.size() == v.size()
			for i in v.size():
				var p: Vector3 = rel * v[i]
				var r := _deform(p, P)
				v[i] = inv * (r * p)
				if has_n:
					n[i] = (inv.basis * (r.basis * (rel.basis * n[i]))).normalized()
			arr[Mesh.ARRAY_VERTEX] = v
			if has_n:
				arr[Mesh.ARRAY_NORMAL] = n
			arr[Mesh.ARRAY_TANGENT] = null
			dst.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
			dst.surface_set_material(s, src.surface_get_material(s))
		out.append(dst)
	return out


static func _rot_about(pivot: Vector3, axis: Vector3, deg: float) -> Transform3D:
	var b := Basis(axis, deg_to_rad(deg))
	return Transform3D(b, pivot - b * pivot)


## Transformation d'un sommet : bras baissés (modèle en T), puis jambes pliées (assis).
func _deform(p: Vector3, P: Dictionary) -> Transform3D:
	var H: float = P.H
	var c: Vector3 = P.c
	var t := Transform3D()
	var dx := p.x - c.x
	if P.tpose:
		var sx: float = P.sh_x
		var w := smoothstep(sx - 0.01 * H, sx + 0.05 * H, abs(dx))
		# seulement près de la ligne du bras (pas la jupe ni les hanches)
		var line_y: float = P.sh_y - (abs(dx) - sx) * _arm_tan
		w *= 1.0 - smoothstep(0.1 * H, 0.16 * H, line_y - p.y)
		if w > 0.0:
			var side := signf(dx)
			t = _rot_about(Vector3(c.x + side * sx, P.sh_y, c.z), Vector3(0, 0, 1), -side * _arm_drop * w)
	if P.seated:
		# les mains / bras écartés ne suivent pas les jambes
		var lx: float = max(_legs_x, 0.1 * H)
		var wx := 1.0 - smoothstep(lx + 0.02 * H, lx + 0.06 * H, abs(dx))
		var w_hip := smoothstep(P.hip + 0.02 * H, P.hip - 0.06 * H, p.y) * wx
		var w_knee := smoothstep(P.knee + 0.015 * H, P.knee - 0.025 * H, p.y) * wx
		var hip_p := Vector3(p.x, P.hip, c.z)
		var knee_p := Vector3(p.x, P.knee, c.z + 0.01 * H)
		var legs := _rot_about(hip_p, Vector3(1, 0, 0), -88.0 * w_hip) * _rot_about(knee_p, Vector3(1, 0, 0), 88.0 * w_knee)
		t = legs * t
	return t
