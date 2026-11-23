## A throttle gaiter anchored to the quadrant at the skirt and sealed to the moving
## shaft at its neck. Two rigid frames skin the intermediate folds on the GPU.
extends Skeleton3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const SIDES := 32
static var _gaiter: ArrayMesh
static var _skin: Skin
static var _shafts := {}


func fit(rubber: Color) -> void:
	for joint in ["Gate", "Shaft"]:
		add_bone(joint)
	if not _gaiter:
		# Half-width, height above pivot, fore/aft half-length and influence of
		# the moving shaft. The low rounded-rectangle lip covers the full slot.
		var rows: Array[Vector4] = [
			Vector4(.022,.040,.162,0), Vector4(.023,.041,.163,0), Vector4(.023,.043,.163,0),
			Vector4(.022,.044,.162,0), Vector4(.019,.044,.154,0),
			Vector4(.018,.046,.147,.004), Vector4(.018,.051,.114,.035),
			Vector4(.022,.054,.115,.046), Vector4(.023,.057,.113,.058),
			Vector4(.021,.060,.105,.074), Vector4(.0175,.063,.085,.098),
			Vector4(.0175,.065,.083,.125), Vector4(.0215,.068,.085,.15),
			Vector4(.022,.071,.082,.18), Vector4(.020,.074,.075,.22),
			Vector4(.0165,.077,.060,.27), Vector4(.0165,.079,.057,.30),
			Vector4(.020,.082,.058,.345), Vector4(.0205,.085,.055,.39),
			Vector4(.0185,.088,.049,.445), Vector4(.0155,.092,.036,.53),
			Vector4(.016,.095,.033,.60), Vector4(.019,.098,.032,.66),
			Vector4(.019,.101,.030,.73), Vector4(.0175,.106,.026,.84),
			Vector4(.016,.111,.0185,.95), Vector4(.0165,.114,.0165,1),
			Vector4(.0165,.117,.0165,1), Vector4(.016,.118,.016,1),
			Vector4(.014,.118,.014,1)]
		_gaiter = _turned(rows, true)
		_skin = Skin.new()
		_skin.add_bind(0, Transform3D.IDENTITY)
		_skin.add_bind(1, Transform3D.IDENTITY)
	var cover := MeshInstance3D.new()
	cover.name = "Bellows"
	cover.mesh = _gaiter
	cover.skin = _skin
	cover.skeleton = NodePath("..")
	cover.material_override = Finish.tinted("rubber", rubber)
	add_child(cover)


static func shaft(accent: Color) -> Mesh:
	if not _shafts.has(accent):
		# Flare into a turned ferrule beneath the leather grip. Start inside the
		# bellows, below the moving wiper, so there is no exposed lower end.
		var steel := Color("#a7acaf")
		var rows: Array[Vector4] = []
		for p: Vector2 in [Vector2(.014,.103),Vector2(.014,.124),Vector2(.0135,.126),
				Vector2(.0135,.277),Vector2(.014,.279),Vector2(.0175,.281),Vector2(.018,.283),
				Vector2(.018,.294),Vector2(.0175,.296),Vector2(.015,.298),
				Vector2(.015,.317)]:
			rows.append(Vector4(p.x,p.y,p.x,0))
		var body := _turned(rows, false)
		var rings: Array[Vector4] = [Vector4(.018,.285,.018,0),Vector4(.0186,.2857,.0186,0),
			Vector4(.0186,.288,.0186,0),Vector4(.018,.2887,.018,0)]
		_shafts[accent] = Kit.compound([[body, Transform3D.IDENTITY, steel], [_turned(rings, false), Transform3D.IDENTITY, accent]])
	return _shafts[accent]


## One casting around the slot. Both the outside shoulder and the return down
## the open throat are rolled; no four-way seam at the corners of the gate.
static func quadrant() -> ArrayMesh:
	var rows: Array[Vector4] = [
		Vector4(.044,-.035,.179,0), Vector4(.045,-.034,.180,0),
		Vector4(.045,.011,.180,0), Vector4(.0447,.0125,.1797,0),
		Vector4(.0438,.0139,.1788,0), Vector4(.0424,.0147,.1774,0),
		Vector4(.041,.015,.176,0), Vector4(.019,.015,.1515,0),
		Vector4(.0179,.0147,.1509,0), Vector4(.0172,.014,.1502,0),
		Vector4(.017,.013,.150,0), Vector4(.017,-.035,.150,0)]
	return _turned(rows,false,.21)


static func _turned(rows: Array[Vector4], skinned: bool, exponent := 1.0) -> ArrayMesh:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for row in rows:
		var shape := lerpf(.21, 1, smoothstep(.048,.112,row.y)) if skinned else exponent
		for j in SIDES:
			var angle := TAU * j / SIDES
			var x := snappedf(cos(angle), .000001)
			var z := snappedf(sin(angle), .000001)
			points.append(Vector3(row.x * Kit._sp(x, shape), row.y, row.z * Kit._sp(z, shape)))
			if skinned:
				bones.append_array(PackedInt32Array([0,1,0,0]))
				weights.append_array(PackedFloat32Array([1-row.w,row.w,0,0]))
	for i in rows.size():
		for j in SIDES:
			var at := i * SIDES + j
			var next := i * SIDES + (j+1) % SIDES
			var prev := i * SIDES + posmod(j-1,SIDES)
			var circum := points[prev].direction_to(points[at]) + points[at].direction_to(points[next])
			var profile := Vector3.ZERO
			if i > 0:
				profile += points[at-SIDES].direction_to(points[at])
			if i+1 < rows.size():
				profile += points[at].direction_to(points[at+SIDES])
				indices.append_array(PackedInt32Array([at,next,at+SIDES,next,next+SIDES,at+SIDES]))
			normals.append(profile.cross(circum).normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## A molded lens with a rolled perimeter and a flat top; omit the concealed base.
static func lens(width: float, height: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := minf(height*.42, minf(width,depth)*.24)
	var corner := minf(width,depth)*.24
	const STEPS := 5
	const COUNT := 4*(STEPS+1)
	for layer in 5:
		var a := maxf(0,layer-1)*PI/6
		var ring_radius := corner-radius*(1-cos(a))
		var y := -height*.5 if layer == 0 else height*.5-radius*(1-sin(a))
		for q in 4:
			var centre := Vector3(width*.5-corner,0,depth*.5-corner)
			centre.x *= 1 if q == 0 or q == 3 else -1
			centre.z *= 1 if q < 2 else -1
			for i in STEPS+1:
				var angle := (q+float(i)/STEPS)*PI*.5
				var radial := Vector3(cos(angle),0,sin(angle))
				st.set_normal(radial*cos(a)+Vector3.UP*sin(a))
				st.add_vertex(centre+radial*ring_radius+Vector3.UP*y)
	for layer in 4:
		for i in COUNT:
			var n := (i+1)%COUNT
			for index in [i,n,i+COUNT,n,n+COUNT,i+COUNT]:
				st.add_index(layer*COUNT+index)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3.UP*height*.5)
	for i in COUNT:
		for index in [5*COUNT,4*COUNT+i,4*COUNT+(i+1)%COUNT]:
			st.add_index(index)
	return st.commit()
