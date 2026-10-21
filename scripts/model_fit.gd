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
var _judith_rig := false
var _fany_rig := false
var _fany_animator: AnimationPlayer
var _mzelle_rig := false
var _mzelle_animator: AnimationPlayer
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
		_judith_rig = path.get_file().to_lower() == "judith.glb"
		if path.get_file().to_lower() == "fany.glb":
			var players := root.find_children("*", "AnimationPlayer", true, false)
			for animator in players:
				if animator.has_animation("Fany_Seated") and animator.has_animation("Fany_Standing"):
					_fany_animator = animator as AnimationPlayer
					_fany_rig = true
					break
		_mzelle_rig = skel.find_bone("MzelleRoot") >= 0
		if _mzelle_rig:
			var animators := root.find_children("*", "AnimationPlayer", true, false)
			if not animators.is_empty():
				_mzelle_animator = animators[0] as AnimationPlayer
		_rel_skel = root.global_transform.affine_inverse() * skel.global_transform
		_find_bones()
		box = _fany_rest_box() if _fany_rig else (_mzelle_rest_box() if _mzelle_rig else _skinned_box())
		hip = _rel_skel * skel.get_bone_global_rest(_bones.hip).origin if _bones.has("hip") else box.get_center()
	else:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh:
				_static_meshes.append({"mi": mi, "rest": mi.mesh, "rel": root.global_transform.affine_inverse() * mi.global_transform})
		box = _static_box()
		_measure_static()
		hip = Vector3(_body.x, box.position.y + 0.52 * box.size.y, _body.z)
	if height <= 0.0:
		height = 1.65 if _fany_rig else (box.size.y if skel else 1.65)
	k = height / max(box.size.y, 0.001)
	root.scale = Vector3.ONE * k
	_cache_key = path


var _cache_key := ""

# Réglages appliqués uniquement au GLB de Marie Rose.
const MARIE_KNEE_WIDTH := 0.65
const MARIE_FOREARM_BEND := 52.0


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
	if _judith_rig:
		_pose_judith(seated)
		return
	if _fany_rig and _fany_animator != null:
		var pose_name := "Fany_Seated" if seated else "Fany_Standing"
		_fany_animator.play(pose_name)
		_fany_animator.advance(0.0)
		_fany_animator.seek(0.0, true)
		_fany_animator.pause()
		return
	if _mzelle_rig and _mzelle_animator != null:
		var target := "Mzelle_Seated" if seated else "Mzelle_Standing"
		for animation_name in _mzelle_animator.get_animation_list():
			if str(animation_name).ends_with(target):
				_mzelle_animator.play(animation_name)
				_mzelle_animator.advance(0.0)
				_mzelle_animator.seek(0.0, true)
				_mzelle_animator.pause()
				return
		push_warning("Mzelle : animation de pose introuvable : " + target)
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
		"mzelle": _cache_key.get_file().get_basename().to_lower() == "mzelle",
		"julie": _cache_key.get_file().get_basename().to_lower() == "julie",
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
			var julie_parts := PackedInt32Array()
			if P.get("julie", false) and seated:
				julie_parts = _julie_parts(v, arr[Mesh.ARRAY_INDEX], rel)
			for i in v.size():
				var p: Vector3 = rel * v[i]
				if not julie_parts.is_empty(): P["julie_part"] = julie_parts[i]
				var r := _deform(p, P)
				v[i] = inv * (r * p)
				if has_n:
					if P.mzelle or (P.get("julie", false) and seated):
						var local_basis: Basis = inv.basis * r.basis * rel.basis
						n[i] = (local_basis.inverse().transposed() * n[i]).normalized()
					else:
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
	if P.seated and P.get("julie", false):
		return _julie_seated(p, P)
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
	if P.seated and P.get("mzelle", false):
		t = _relax_marie(p, P, t)
	return t


## Ajustement doux sur la pose existante, sans modifier le modèle au repos.
func _relax_marie(p: Vector3, P: Dictionary, current: Transform3D) -> Transform3D:
	var H: float = P.H
	var c: Vector3 = P.c
	var dx := p.x - c.x
	# Hanches stables ; rapprochement progressif sous le bassin.
	var lower := 1.0 - smoothstep(P.hip - 0.13 * H, P.hip + 0.01 * H, p.y)
	var leg_zone := 1.0 - smoothstep(0.17 * H, 0.23 * H, absf(dx))
	var narrowing := lerpf(1.0, MARIE_KNEE_WIDTH, lower * leg_zone)
	var compression := Basis.from_scale(Vector3(narrowing, 1.0, 1.0))
	var center := Vector3(c.x, 0, 0)
	var result := Transform3D(compression, center - compression * center) * current
	# Le modèle est en T : on repère les avant-bras avant leur abaissement.
	if P.tpose:
		var sx: float = P.sh_x
		var arm_line: float = P.sh_y - (absf(dx) - sx) * _arm_tan
		var band := 1.0 - smoothstep(0.055 * H, 0.09 * H, absf(p.y - arm_line))
		var forearm := smoothstep(0.18 * H, 0.255 * H, absf(dx)) * band
		if forearm > 0.0:
			var side := signf(dx)
			var shoulder := Vector3(c.x + side * sx, P.sh_y, c.z)
			var elbow_rest := Vector3(c.x + side * 0.205 * H, P.sh_y - (0.205 * H - sx) * _arm_tan, c.z)
			var drop := _rot_about(shoulder, Vector3(0, 0, 1), -side * _arm_drop)
			var elbow := drop * elbow_rest
			result = _rot_about(elbow, Vector3(1, 0, 0), -MARIE_FOREARM_BEND * forearm) * result
			result.origin.x -= side * 0.025 * H * forearm
	return result


## Mesure du maillage au repos : les os ne couvrent ni cheveux ni semelles.
func _mzelle_rest_box() -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var relative := root.global_transform.affine_inverse() * mi.global_transform
		var bounds: AABB = relative * mi.mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result


## Bornes réelles au repos après skinning, pas les AABB locales non déformées.
func _fany_rest_box() -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := -low
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		var transforms: Array[Transform3D] = []
		for bind in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(bind)
			var bind_name := mi.skin.get_bind_name(bind)
			if not bind_name.is_empty():
				bone = skel.find_bone(bind_name)
			var transform := Transform3D.IDENTITY
			if bone >= 0:
				transform = _rel_skel * skel.get_bone_global_rest(bone) * mi.skin.get_bind_pose(bind)
			transforms.append(transform)
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = weights.size() / maxi(vertices.size(), 1)
			for i in vertices.size():
				var point := Vector3.ZERO
				for slot in influences:
					var index := i * influences + slot
					if weights[index] > 0 and indices[index] < transforms.size():
						point += (transforms[indices[index]] * vertices[i]) * weights[index]
				low = low.min(point)
				high = high.max(point)
	return AABB(low, high - low)


## Julie : pose assise dédiée. Les bras d'origine sont asymétriques ;
## ne pas les traiter comme une T-pose (les cheveux faussent cette détection).
func _julie_seated(p: Vector3, P: Dictionary) -> Transform3D:
	var H: float = P.H
	var c: Vector3 = P.c
	var y0: float = box.position.y
	var q := (p - Vector3(c.x, y0, c.z)) / H
	var part: int = P.get("julie_part", 0)
	if part == 10:
		var original := P.duplicate()
		original["julie"] = false
		return _deform(p, original)
	var side := -1.0 if part < 0 else 1.0
	var shoulder := Vector3(-0.065, 0.795, -0.025) if side < 0.0 else Vector3(0.065, 0.80, 0.025)
	var elbow := Vector3(-0.115, 0.645, -0.025) if side < 0.0 else Vector3(0.17, 0.715, -0.005)
	var arm_w := 1.0 if part != 0 else 0.0
	if absi(part) == 1:
		var axis := elbow - shoulder
		arm_w *= smoothstep(0.0, 0.65, (q - shoulder).dot(axis) / axis.length_squared())
	var fore_w := 1.0 if absi(part) in [2, 3] else (0.25 if absi(part) == 4 else 0.0)
	var origin := Vector3(c.x, y0, c.z)
	var sh := origin + shoulder * H
	var el := origin + elbow * H
	var arm := _rot_about(sh, Vector3.RIGHT, -8.0)
	arm = arm * _rot_about(sh, Vector3.BACK, 10.0 if side < 0.0 else -55.0)
	arm = arm * _rot_about(el, Vector3.RIGHT, (-40.0 if side < 0.0 else -40.0) * fore_w)
	arm = arm * _rot_about(el, Vector3.BACK, (40.0 if side < 0.0 else 90.0) * fore_w)
	var knee := y0 + 0.355 * H
	var lx: float = max(_legs_x, 0.1 * H)
	var wx := 1.0 - smoothstep(lx + 0.02 * H, lx + 0.06 * H, absf(p.x - c.x))
	var wh := smoothstep(P.hip + 0.02 * H, P.hip - 0.06 * H, p.y) * wx
	var wk := smoothstep(knee + 0.015 * H, knee - 0.025 * H, p.y) * wx
	var leg := _rot_about(Vector3(p.x, P.hip, c.z), Vector3.RIGHT, -88.0 * wh) * _rot_about(Vector3(p.x, knee, c.z + 0.01 * H), Vector3.RIGHT, 88.0 * wk)
	var lower := 1.0 - smoothstep(0.42, 0.55, q.y)
	var width := lerpf(1.0, 0.82, lower * wx)
	var compression := Basis.from_scale(Vector3(width, 1.0, 1.0))
	var center := Vector3(c.x, 0, 0)
	leg = Transform3D(compression, center - compression * center) * leg
	return leg.interpolate_with(arm, arm_w)


## Identifier les pièces connexes évite de prendre les cheveux pour un bras.
## Le classement est refait sur les tableaux importés : aucun indice fixe
## dépendant de la version de Godot n'est stocké dans le patch.
func _julie_parts(vertices: PackedVector3Array, indices: PackedInt32Array, rel: Transform3D) -> PackedInt32Array:
	var count := vertices.size()
	var parents := PackedInt32Array()
	parents.resize(count)
	var points := PackedVector3Array()
	points.resize(count)
	var welded := {}
	for i in count:
		var q := (rel * vertices[i] - Vector3(_body.x, box.position.y, _body.z)) / box.size.y
		points[i] = q
		var key := Vector3i((q * 100000.0).round())
		parents[i] = welded.get(key, i)
		if not welded.has(key): welded[key] = i
	for i in range(0, indices.size(), 3):
		var a := _julie_find(parents, indices[i])
		for k in [1, 2]:
			var b := _julie_find(parents, indices[i + k])
			parents[b] = a
	var sums := {}
	var counts := {}
	for i in count:
		var group := _julie_find(parents, i)
		sums[group] = sums.get(group, Vector3.ZERO) + points[i]
		counts[group] = counts.get(group, 0) + 1
	var tags := {}
	for group in sums:
		var center: Vector3 = sums[group] / counts[group]
		var tag := 0
		if center.x > -0.135 and center.x < -0.065 and center.y > 0.69 and center.y < 0.76: tag = -1
		elif center.x > -0.18 and center.x < -0.12 and center.y > 0.565 and center.y < 0.62: tag = -2
		elif center.x > -0.21 and center.x < -0.14 and center.y > 0.49 and center.y < 0.55: tag = -3
		elif center.x > 0.11 and center.x < 0.17 and center.y > 0.72 and center.y < 0.78: tag = 1
		elif center.x > 0.12 and center.x < 0.18 and center.y > 0.64 and center.y < 0.685: tag = 2
		elif center.x > 0.06 and center.x < 0.12 and center.y > 0.60 and center.y < 0.64: tag = 3
		elif center.x > 0.17 and center.x < 0.215 and center.y > 0.70 and center.y < 0.75: tag = 4
		elif center.x < -0.18 and center.y > 0.64 and center.y < 0.70: tag = 10
		tags[group] = tag
	var result := PackedInt32Array()
	result.resize(count)
	for i in count: result[i] = tags[_julie_find(parents, i)]
	return result


func _julie_find(parents: PackedInt32Array, index: int) -> int:
	var current := index
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current


## Judith arrive en A-pose, pas en T-pose : un rabattement de 72 degrés
## enfouit les bras dans le buste. Réglages réservés à ce modèle.
func _pose_judith(seated: bool) -> void:
	skel.reset_bone_poses()
	var B: Dictionary = _bones
	for side in ["l", "r"]:
		_turn(B.get(side + "_arm", -1), Vector3.BACK, -32.0 if side == "l" else 32.0)
		if seated:
			_turn(B.get(side + "_arm", -1), Vector3.RIGHT, -10.0)
			_turn(B.get(side + "_fore", -1), Vector3.BACK, -20.0 if side == "l" else 20.0)
			_turn(B.get(side + "_fore", -1), Vector3.RIGHT, -68.0)
			_turn(B.get(side + "_thigh", -1), Vector3.RIGHT, -88.0)
			_turn(B.get(side + "_shin", -1), Vector3.RIGHT, 88.0)
			_judith_pronate(side)
		else:
			_turn(B.get(side + "_fore", -1), Vector3.RIGHT, -5.0)
	if seated:
		# Les huit chaînes de la jupe accompagnent les cuisses ; la dernière
		# partie retombe au niveau des genoux plutôt que de traverser le siège.
		for i in skel.get_bone_count():
			var name := skel.get_bone_name(i)
			if "Skirt" not in name: continue
			var angle := 0.0
			if "SkirtA_a_Phy" in name: angle = -78.0
			elif "SkirtB_a_Phy" in name: angle = -75.0
			elif "SkirtC_a_Phy" in name: angle = 0.0
			elif "SkirtD_a_Phy" in name: angle = 0.0
			elif "SkirtA_c_Phy" in name or "SkirtB_c_Phy" in name: angle = 35.0
			elif "SkirtC_b_Phy" in name: angle = -80.0
			elif "SkirtD_b_Phy" in name: angle = -80.0
			if angle != 0.0 and "end" not in name.to_lower(): _turn(i, Vector3.RIGHT, angle)


## Retourner les paumes vers la robe en répartissant la torsion sur les
## os de déroulement de l'avant-bras, pas uniquement sur le poignet.
func _judith_pronate(side: String) -> void:
	var prefix := "L_" if side == "l" else "R_"
	var hand := -1
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).begins_with(prefix + "Hand_a_"): hand = i; break
	var fore: int = _bones.get(side + "_fore", -1)
	if hand < 0 or fore < 0: return
	var elbow := _rel_skel * skel.get_bone_global_pose(fore).origin
	var wrist := _rel_skel * skel.get_bone_global_pose(hand).origin
	var delta := wrist - elbow
	if delta.length_squared() < 0.000001: return
	var angle := 150.0 if side == "l" else -150.0
	_judith_twist_bone(fore, elbow, delta.normalized(), angle * 0.5)
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		if not name.begins_with(prefix): continue
		if ("Forearmroll" in name and "_Spo_" in name) or "Wrist_Spo_" in name:
			var point := _rel_skel * skel.get_bone_global_pose(i).origin
			var amount := clampf((point - elbow).dot(delta) / delta.length_squared(), 0.0, 1.0)
			_judith_twist_bone(i, elbow, delta.normalized(), angle * (amount - 0.5))
	_judith_twist_bone(hand, elbow, delta.normalized(), angle * 0.5)


func _judith_twist_bone(index: int, pivot_model: Vector3, axis_model: Vector3, degrees: float) -> void:
	var inverse := _rel_skel.affine_inverse()
	var pivot := inverse * pivot_model
	var rotation := Basis((inverse.basis * axis_model).normalized(), deg_to_rad(degrees))
	var current := skel.get_bone_global_pose(index)
	var target := Transform3D(rotation * current.basis, pivot + rotation * (current.origin - pivot))
	var parent := skel.get_bone_parent(index)
	var parent_pose := skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local := parent_pose.affine_inverse() * target
	skel.set_bone_pose_position(index, local.origin)
	skel.set_bone_pose_rotation(index, local.basis.orthonormalized().get_rotation_quaternion())
