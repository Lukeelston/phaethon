## Helios (Luke, 2026-11-20: "an area of the map that just climbs an unreasonably large mountain.
## Pilot should be able to see the surrounding world as they ascend or descend"): one mountain 10.4 km
## high north of E3, between N2 and N3, and the road SHelios that winds up it, over the summit and down.
## tools/design_network.py's HELIOS and helios_z are the mountain; this mirrors them exactly, and the
## road's heights are that surface (tests/test_helios.gd holds the two together).
##   Helios.height(p)      the designer's surface at p (map metres): the road lies on this
##   Helios.land(p)        what the country stands at there: the surface, let down to the plain's floor at the foot
##   Helios.rough(p)       ridges the terrain adds away from the road (never downward)
##   Helios.far_mesh(landscape)   the whole mountain as one mesh, for when it is too far for the terrain's tiles
extends RefCounted

const CENTRE := Vector2(400000.0, 549000.0)
const HEIGHT := 10400.0
const FOOT := 36000.0            # m: its radius where it meets the plain
const FLOOR := -4.0              # the open ground everywhere else (NetworkScenic.FLOOR)
const RIDGE := 420.0             # m: the tallest of its ridges, half way up
const TREE_LINE := 3000.0        # m: nothing grows over this
const CLEARING := 0.47           # how much of the cloud deck's cover is gone over it (view/network_clouds.gdshader)
const ROCK := Color(0.37, 0.35, 0.32)
const SNOW := Color(0.90, 0.93, 0.95)
const RINGS := 56                # the far mesh: rings from the summit to the foot, and points round each
const ROUND := 112

static var _noise: FastNoiseLite


static func on(p: Vector2) -> bool:
	return p.distance_squared_to(CENTRE) < FOOT * FOOT


## How much of the regions' own relief is left at p: none on the mountain, all of it from a quarter
## of its radius beyond its foot. (The snow country's ridges, kilometres high, ran across its east
## side: they stood over its lower slopes and over the road's bench.)
static func country(p: Vector2) -> float:
	return smoothstep(0.92, 1.25, p.distance_to(CENTRE) / FOOT)


static func height(p: Vector2) -> float:
	var u := minf(p.distance_to(CENTRE) / FOOT, 1.0)
	var k := 1.0 - u * u
	return HEIGHT * k * k


static func land(p: Vector2) -> float:
	var u := minf(p.distance_to(CENTRE) / FOOT, 1.0)
	var k := 1.0 - u * u
	return HEIGHT * k * k + FLOOR * u * u


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
	return RIDGE * smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.55, 1.0, u)) * ridge * ridge * ridge


## The mountain's own colours over the country's: bare rock above the trees, snow above that, both
## lines ragged (n: the land's detail noise there, -1..1).
static func colour(base: Color, h: float, n: float) -> Color:
	var col := base.lerp(Color(ROCK.r, ROCK.g, ROCK.b, base.a), smoothstep(1500.0, 3300.0, h + n * 500.0))
	col = col.lerp(Color(SNOW.r, SNOW.g, SNOW.b, base.a), smoothstep(4700.0, 6100.0, h + n * 700.0))
	col.a = base.a * (1.0 - smoothstep(700.0, 1900.0, h))      # (no field patterns up a mountain)
	return col


## The whole mountain as one mesh about its centre (x east, y up, z south): ridges and colours as the
## terrain has them, read coarsely. Drawn only beyond where the terrain's tiles are (its shader).
static func far_mesh(landscape) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for ring in RINGS + 1:
		var r := FOOT * float(ring) / RINGS
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
