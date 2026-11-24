## A horizontal annular transducer on a telescoping belly spindle.
## The two keel doors are the original painted lower skin, divided on its centreline.
extends "res://view/arms/hull_hatches.gd"

const HATCHES := "res://art/arms/vesper_hatches.glb"
const CENTER_Z := -0.12
const RADIUS := 0.44
const CERAMIC := Color("#c8ccd9")
var _ring: MeshInstance3D
var _stem: MeshInstance3D


func build(hull: Node3D) -> void:
	if is_instance_valid(_skin):
		return
	var pivots: Array[Vector3] = [Vector3(-.68,-.55,CENTER_Z), Vector3(.68,-.55,CENTER_Z)]
	install(hull, hull as MeshInstance3D, load(HATCHES), pivots)
	var well := [[Finish.beveled_plate(Vector3(1.32,.035,1.37),.014),
			Kit.at(Vector3(0,-.505,CENTER_Z)),GRAPHITE]]
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Shallow stamped ribs join the rolled inner liner to the original outer skin.
		var lining := [[Finish.beveled_plate(Vector3(.57,.018,1.29),.008),
				Kit.at(Vector3(-side*.345,.013,0)), Color("#635e70")]]
		for z in [-.48,0.0,.48]:
			lining.append([Finish.beveled_plate(Vector3(.44,.013,.035),.005),
					Kit.at(Vector3(-side*.345,.026,z)), SILVER])
		piece(hinges[i],&"PressedLiner",Kit.compound(lining,null,true),Finish.powder_coat())
		well.append([Finish.beveled_plate(Vector3(.065,.036,1.14),.012),
				Kit.at(Vector3(side*.54,-.534,CENTER_Z)),BRONZE])
	well.append([Kit.cyl(.12,.095,.078,20),Kit.at(Vector3(0,-.54,CENTER_Z)),SILVER])
	piece(self,&"SpindleWell",Kit.compound(well,null,true),Finish.powder_coat())
	var fins := []
	var lamps := []
	var backing := Finish.washer(.314,.424,.060,48)
	fins.append([backing, Transform3D.IDENTITY, GRAPHITE])
	for y in [-.033,.033]:
		fins.append([Finish.washer(.394,.439,.015,48),Kit.at(Vector3(0,y,0)),SILVER])
	fins.append([Kit.cyl(.090,.086,.093,24),Transform3D.IDENTITY,GRAPHITE])
	fins.append([Kit.cyl(.070,.070,.024,24),Kit.at(Vector3(0,-.055,0)),BRONZE])
	var window := _segment()
	for i in 8:
		var angle := TAU * i / 8.0
		var sector := Transform3D(Basis(Vector3.UP,angle), Vector3.ZERO)
		if i % 2 == 0:
			fins.append([Finish.beveled_plate(Vector3(.058,.025,.285),.008),
					sector * Kit.at(Vector3(0,-.005,-.205)),BRONZE])
		# Pale ceramic interrupts each window and bridges the upper and lower rolled rims.
		fins.append([Finish.beveled_plate(Vector3(.061,.084,.052),.009),
				sector * Kit.at(Vector3(0,0,-.416)),CERAMIC])
		lamps.append([window,sector,Color.WHITE])
	_ring = piece(self, &"PulseRing", Kit.compound(fins,null,true), Finish.machined())
	_ring.scale = Vector3(1.12,1.0,1.12)
	piece(_ring,&"EightWindows",Kit.compound(lamps,null,true),luminous(Color("#74579c"),Color("#fbc8ff")))
	var stem_parts := [[Kit.cyl(.060,.060,.31,14),Kit.at(Vector3(0,.145,0)),SILVER],
			[Kit.cyl(.079,.077,.055,18),Kit.at(Vector3(0,.02,0)),BRONZE]]
	_stem = piece(self, &"Spindle",Kit.compound(stem_parts,null,true),Finish.machined())
	muzzle(_ring,&"PulseOrigin",Vector3(0,0,-RADIUS))
	set_deploy(0.0)


## Curved glass in the outer face of the transducer. Four bevel bands share
## a normal around the sweep so the ring highlights continue through each window.
static func _segment() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(.422,-.024),Vector2(.431,-.021),Vector2(.434,-.014),
			Vector2(.434,.014),Vector2(.431,.021),Vector2(.422,.024)]
	for band in profile.size()-1:
		var p: Vector2 = profile[band]
		var q: Vector2 = profile[band+1]
		var local_normal := Vector2(q.y-p.y, p.x-q.x).normalized()
		for i in 6:
			for vertex in [Vector2i(i,0),Vector2i(i+1,0),Vector2i(i+1,1),
					Vector2i(i,0),Vector2i(i+1,1),Vector2i(i,1)]:
				var a := lerpf(.099,TAU/8.0-.099,float(vertex.x)/6.0)
				var radial := Vector3(sin(a),0,-cos(a))
				var v := p if vertex.y == 0 else q
				st.set_normal(radial*local_normal.x + Vector3.UP*local_normal.y)
				st.add_vertex(radial*v.x + Vector3.UP*v.y)
	st.index()
	return st.commit()


func set_deploy(t: float) -> void:
	if not pose(t):
		return
	var lift := smoothstep(.35,1.0,_deployed)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		hinges[i].rotation.z = side * deg_to_rad(158.0) * smoothstep(0.0,.72,_deployed)
	_ring.position = Vector3(0,lerpf(-.43,-.82,lift),CENTER_Z)
	_stem.position = _ring.position
	_ring.visible = _deployed > .35
	_stem.visible = _ring.visible
