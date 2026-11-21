## Helios (Luke, 2026-11-20: "an area of the map that just climbs an unreasonably large mountain.
## Pilot should be able to see the surrounding world as they ascend or descend"; 2026-11-21: "an
## unreasonably steep mountain to climb vertically ... and plateau over the top"): one mountain north of
## E3, between N2 and N3, a dome 36 km out with a spire 16 km high on it, and the road SHelios that winds
## up the dome, straight up the spire's face, across its plateau and down. tools/design_network.py's
## HELIOS, HELIOS_SPIRE and helios_z are the mountain; this mirrors them exactly, and the road's heights
## are that surface (tests/test_helios.gd holds the two together).
##   Helios.height(p)      the designer's surface at p (map metres): the road lies on this
##   Helios.land(p)        what the country stands at there: the surface, let down to the plain's floor at the foot
##   Helios.rough(p)       ridges the terrain adds away from the road (never downward)
##   Helios.far_mesh(landscape)   the whole mountain as one mesh, for when it is too far for the terrain's tiles
extends RefCounted

const CENTRE := Vector2(400000.0, 549000.0)
const DOME := 10400.0            # m: the dome's height at its centre (HELIOS[2]; its top is inside the spire)
const FOOT := 36000.0            # m: its radius where it meets the plain
const SHOULDER := 9000.0         # m: inside this radius the dome gives way to the spire (HELIOS_SPIRE)
const PLATEAU := 3000.0          # m: the radius of the spire's level top
const CREST := 2880.0            # m: the crest's run, from the wall in to the plateau's rim
const WALL := 75.0               # degrees: the spire's pitch at the wall, its steepest (SHOULDER - PLATEAU - CREST below the shoulder)
const HEIGHT := 16046.072148083478   # m: the plateau (the designer's helios_spire()[-1]: height(CENTRE) is this)
const FLOOR := -4.0              # the open ground everywhere else (NetworkScenic.FLOOR)
const RIDGE := 420.0             # m: the tallest of its ridges, half way up
const TREE_LINE := 3000.0        # m: nothing grows over this
const CLEARING := 0.47           # how much of the cloud deck's cover is gone over it (view/network_clouds.gdshader)
const ROCK := Color(0.37, 0.35, 0.32)
const SNOW := Color(0.90, 0.93, 0.95)
const SPIRE_RINGS := 44          # the far mesh: rings from the summit out to the shoulder (close-set: the wall is 10 km high in 3 km of plan) ...
const DOME_RINGS := 34           # ... and from the shoulder to the foot
const RINGS := SPIRE_RINGS + DOME_RINGS
const ROUND := 112               # points round each
const WALL_ROCK := Color(0.17, 0.165, 0.175)   # the spire's wall: too steep for snow
const GRID := 512.0              # the terrain's grid (NetworkLandscape.STEP)
const GATE_UP := 120.0           # m over the plateau: the Sun Gate's heart (its first ring, 190 m in radius, lets the road through at ground level)
const GATE_SUN := 26.0           # m: the radius of the lamp at its heart

static var _noise: FastNoiseLite


static func on(p: Vector2) -> bool:
	return p.distance_squared_to(CENTRE) < FOOT * FOOT


## How much of the regions' own relief is left at p: none on the mountain, all of it from a quarter
## of its radius beyond its foot. (The snow country's ridges, kilometres high, ran across its east
## side: they stood over its lower slopes and over the road's bench.)
static func country(p: Vector2) -> float:
	return smoothstep(0.92, 1.25, p.distance_to(CENTRE) / FOOT)


## The designer's helios_z, term for term. Outside the shoulder the dome: DOME (1 - u^2)^2. Inside it the
## spire: the climb, whose pitch is the dome's at the shoulder (ts) and grows by `a` a metre in to the
## wall's (tm); the crest, whose pitch falls by `b` a metre to nothing at the rim; the plateau, level.
## (A slope tan(t0 + a s) has height ln(cos t0 / cos(t0 + a s)) / a.) Height and slope are continuous.
static func height(p: Vector2) -> float:
	var r := p.distance_to(CENTRE)
	if r >= SHOULDER:
		var u := minf(r / FOOT, 1.0)
		var k := 1.0 - u * u
		return DOME * k * k
	var us := SHOULDER / FOOT
	var ks := 1.0 - us * us
	var zs := DOME * ks * ks
	var ts := atan(4.0 * DOME * us * ks / FOOT)
	var tm := deg_to_rad(WALL)
	var rw := PLATEAU + CREST
	var a := (tm - ts) / (SHOULDER - rw)
	var b := tm / CREST
	var zw := zs + log(cos(ts) / cos(tm)) / a
	if r >= rw:
		return zs + log(cos(ts) / cos(ts + a * (SHOULDER - r))) / a
	if r > PLATEAU:
		return zw + log(cos(b * (r - PLATEAU)) / cos(tm)) / b
	return zw - log(cos(tm)) / b


static func land(p: Vector2) -> float:
	var u := minf(p.distance_to(CENTRE) / FOOT, 1.0)
	return height(p) + FLOOR * u * u


## Is p on the spire (inside the shoulder, with a little of the dome round it)?
static func spire(p: Vector2) -> bool:
	return p.distance_squared_to(CENTRE) < (SHOULDER + 1500.0) * (SHOULDER + 1500.0)


## The surface's pitch at p, radians: how steeply it climbs toward the centre.
static func pitch(p: Vector2) -> float:
	var out := (p - CENTRE).normalized() if p.distance_squared_to(CENTRE) > 1.0 else Vector2.RIGHT
	return atan((height(p - out * 10.0) - height(p + out * 10.0)) / 20.0)


## 0 where snow lies, 1 where the surface is a wall (over 60 degrees); between from 38.
static func steep(p: Vector2) -> float:
	return smoothstep(deg_to_rad(38.0), deg_to_rad(60.0), pitch(p)) if spire(p) else 0.0


## How far a straight edge of the terrain's 512 m grid can stand over the surface at p. The spire's
## climb curves upward (its pitch grows all the way in), so a chord between two of the grid's corners
## passes over the surface between them: by 300 m at the wall. Nothing off the spire.
static func sag(p: Vector2) -> float:
	if not spire(p):
		return 0.0
	var out := (p - CENTRE).normalized() if p.distance_squared_to(CENTRE) > 1.0 else Vector2.RIGHT
	return maxf(0.0, 0.5 * (height(p + out * GRID) + height(p - out * GRID)) - height(p))


## What the terrain's grid shows at p where no road has a say: its corners stand on the land, and it
## is flat between them (the same two triangles a square as NetworkLandscape.surface_at).
static func grid(p: Vector2) -> float:
	var c := (p / GRID).floor()
	var f := p / GRID - c
	var a := land(c * GRID)
	var b := land((c + Vector2(1, 0)) * GRID)
	var d := land((c + Vector2(0, 1)) * GRID)
	if f.x + f.y <= 1.0:
		return a + (b - a) * f.x + (d - a) * f.y
	var e := land((c + Vector2(1, 1)) * GRID)
	return e + (d - e) * (1.0 - f.x) + (b - e) * (1.0 - f.y)


## Ridges and gullies: none at the foot or on the summit, tallest between. Never below the surface,
## so nothing that lies under the surface (the far mesh, the road's own land) can show through it.
static func rough(p: Vector2) -> float:
	var u := p.distance_to(CENTRE) / FOOT
	if u >= 1.0:
		return 0.0
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 4117
		_noise.frequency = 1.0 / 5200.0
		_noise.fractal_octaves = 3
	var ridge := 1.0 - absf(_noise.get_noise_2dv(p))
	# (none on the spire or its plateau: they came 390 m high at the shoulder and stood on the summit)
	return RIDGE * smoothstep(SHOULDER + 500.0, SHOULDER + 5000.0, u * FOOT) * (1.0 - smoothstep(0.55, 1.0, u)) * ridge * ridge * ridge


## The mountain's own colours over the country's: bare rock above the trees, snow above that, both
## lines ragged (n: the land's detail noise there, -1..1).
static func colour(base: Color, h: float, n: float, wall := 0.0) -> Color:
	var col := base.lerp(Color(ROCK.r, ROCK.g, ROCK.b, base.a), smoothstep(1500.0, 3300.0, h + n * 500.0))
	col = col.lerp(Color(SNOW.r, SNOW.g, SNOW.b, base.a), smoothstep(4700.0, 6100.0, h + n * 700.0))
	col = col.lerp(Color(WALL_ROCK.r, WALL_ROCK.g, WALL_ROCK.b, base.a), wall * (0.86 + 0.14 * n))      # the wall: bare, dark, streaked
	col.a = base.a * (1.0 - smoothstep(700.0, 1900.0, h))      # (no field patterns up a mountain)
	return col


## The Sun Gate, on the plateau's middle: an armillary of three golden rings 400 m high with a small
## sun at its heart, the road running through the first ring. Built about the plateau's centre at road
## level (x east, y up, z south); `along` is the road's way there (a unit vector in those axes).
## -> a node with children "rings" (one mesh), "sun" (the lamp: unshaded, far over white) and "light".
static func gate(along: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "sun_gate"
	var heart := Vector3(0.0, GATE_UP, 0.0)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.76, 0.34)
	gold.metallic = 1.0
	gold.roughness = 0.24
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.62, 0.2)
	gold.emission_energy_multiplier = 0.22
	var up := Vector3.UP
	var across := up.cross(along).normalized()
	# each: its radius, how thick, and the axis it turns about
	for ring in [[190.0, 10.0, along], [232.0, 7.0, (along * cos(0.87) + across * sin(0.87)).normalized()], [262.0, 5.0, (up * cos(0.42) + across * sin(0.42)).normalized()]]:
		var mesh := TorusMesh.new()
		mesh.inner_radius = float(ring[0]) - float(ring[1])
		mesh.outer_radius = float(ring[0]) + float(ring[1])
		mesh.rings = 96
		mesh.ring_segments = 12
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = gold
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var axis: Vector3 = ring[2]      # (a torus lies about its own y)
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		mi.transform = Transform3D(Basis(side, axis, side.cross(axis)), heart)
		root.add_child(mi)
	var sun := MeshInstance3D.new()
	sun.name = "sun"
	var ball := SphereMesh.new()
	ball.radius = GATE_SUN
	ball.height = GATE_SUN * 2.0
	sun.mesh = ball
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(7.0, 4.6, 1.5)
	sun.material_override = fire
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun.position = heart
	root.add_child(sun)
	var light := OmniLight3D.new()
	light.name = "light"
	light.position = heart
	light.light_color = Color(1.0, 0.78, 0.45)
	light.light_energy = 5.0
	light.omni_range = 900.0
	light.shadow_enabled = false
	root.add_child(light)
	return root


## The whole mountain as one mesh about its centre (x east, y up, z south): ridges and colours as the
## terrain has them, read coarsely. Drawn only beyond where the terrain's tiles are (its shader).
static func far_mesh(landscape) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for ring in RINGS + 1:
		var r := SHOULDER * float(ring) / SPIRE_RINGS if ring <= SPIRE_RINGS else lerpf(SHOULDER, FOOT, float(ring - SPIRE_RINGS) / DOME_RINGS)
		for k in ROUND:
			var a := TAU * float(k) / ROUND
			var p := CENTRE + Vector2(cos(a), sin(a)) * r
			var h := land(p) + rough(p)
			verts.append(Vector3(p.x - CENTRE.x, h, -(p.y - CENTRE.y)))
			var e := 400.0
			var dx := (land(p + Vector2(e, 0.0)) + rough(p + Vector2(e, 0.0))) - (land(p - Vector2(e, 0.0)) + rough(p - Vector2(e, 0.0)))
			var dy := (land(p + Vector2(0.0, e)) + rough(p + Vector2(0.0, e))) - (land(p - Vector2(0.0, e)) + rough(p - Vector2(0.0, e)))
			normals.append(Vector3(-dx, 2.0 * e, dy).normalized())
			colours.append(landscape.color_at(p, h))
	for ring in RINGS:
		for k in ROUND:
			var a := ring * ROUND + k
			var b := ring * ROUND + (k + 1) % ROUND
			var c := a + ROUND
			var d := b + ROUND
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
