## The tactical display (Luke, 2026-11-22: "a switch that adds a 'tactical speed display' hud over the whole
## windscreen ... a physical overlay onto the world. Traffic could have lines running up from each car, exits
## could have an arrow animation ... a driving display to help handle decision making at speed").
## At 3,000 to 5,000 mph a bend, an exit or a vehicle goes from a dot to on top of him in a second or two, and
## the road itself tells him nothing in time: his eye rides 2.7 m over it, so a hundred metres of road a
## kilometre off is a hundredth of a degree high. What is flat on the road cannot be seen coming. So everything
## here STANDS on the thing it describes, at that thing's own place and depth (nothing is glued to the head or
## the glass), and is drawn as tall as the eye needs it, not as tall as it is:
##   the road ahead   a rail of light along each edge of the road he is on, from half a second's flying out
##                    to twelve seconds' (1.5 to 28 km): a line over the road's edge with a faint curtain
##                    under it, and the line stands higher in the view the further off it is (0.3 degrees
##                    where it begins, 3 at its far end). On a straight road the two rails close to a point
##                    over the road's far end; where the road bends the point swings off to that side and
##                    the rails lean after it, long before the surface shows. (Held at one height they were
##                    a sliver on the horizon, bend or no bend.) Its colour is the bend's ask (what the road
##                    asks of the craft at the speed she is doing now, as a share of what she can hold) set
##                    against how Luke flies (below): a blue violet for what he takes in his stride, violet
##                    as it climbs past what he usually asks, magenta past nearly all of it, and the line along
##                    its top thicker as it goes. A family of its own (Luke, 2026-11-23: "the walls should be a
##                    different color scheme than the traffic indicators"): a wall is never the vehicles' cyan,
##                    amber or red, nor an exit's green.
##   the vehicles     a line of light standing on each vehicle he is closing on and would reach within eight
##                    seconds, 1.6 degrees tall: over a crest, over the traffic in front of it. Those in his way
##                    (his lane and the next) are coloured by the seconds left, cyan, amber, red (they ask him to
##                    act now); the rest are short and cyan, and go when the road is busy. A raider (Raids: a hostile
##                    car) has one wherever it is in the rails' reach, gaining on it or not, full height, in the
##                    hostile red whatever its seconds, and is never the one left out.
##   the exits        over an exit's lane, a row of upright chevrons pointing the way the lane leaves, a wave of
##                    light running along them into the ramp, and a gate standing across the lane at its mouth,
##                    the row's end. Begun seven seconds before the mouth (never less than 8 km, where the lane's
##                    own paint begins): the gate from then, the row from two and a half seconds on to the mouth.
##                    Held at one size as the eye sees it, a row looked the same for miles and then the lane left
##                    out of nowhere (Luke, 2026-11-23). So the row is laid in seconds, at the speed she was doing
##                    when it was laid: a big chevron at each whole second before the mouth, a smaller one at each
##                    half, and over the last two seconds one at each quarter, the row tightening toward the
##                    mouth (he can count the seconds left by its big ones). Far off a chevron is held to 0.4
##                    degrees as the eye sees it, and dimmer; from two and a half seconds off it is a thing of its
##                    own size (about a lane's width at 3,500 mph) and grows as she nears as such a thing does, so
##                    how fast it grows says how soon she is there. The gate likewise: a frame across the lane, no
##                    narrower than it nor than a big chevron, a little taller than wide, seen from where it begins. A join: five chevrons past its mouth,
##                    pointing in, cyan (vehicles come in there), sized as the exits' are; no gate.
##   the speed        one number, in the sky over the road's far end: 60 m ahead on the craft's own way, 4.5
##                    degrees over the horizon. It takes the rails' colour for the hardest bend in six seconds.
## What the craft can hold is the sim's own: its engines' and its pod's grip caps by their masses (CraftSim P
## gripCapG, podCapG: 13.8 g as a SPEEDCRAFT, 46.6 g as a STARFIGHTER), and on a banked road the bank's own
## share (CraftSim step: g tan(bank) + bankDown v^2 sin(bank)). Nothing is guessed. The road is read through
## the views' own accessor (CraftSim.surface_at: its height and its bank), a station at a time as it comes
## into reach, so the rails stand on whatever surface the sims have.
## The colours' scale is not "near or past what she can hold": the roads are 400 m wide, and past her grip she
## slides wide and stays on (with damage off, as he flies). It is set against his own flying: his six flights of
## 2026-11-23 (3,276 s at speed on the Network, all as a SPEEDCRAFT, 13.8 g), where a bend asked of what she
## holds under 0.79 a quarter of the time, under 1.29 half, 1.81 three quarters, 2.21 nine tenths, 2.72 for 95%
## (18, 25, 30, 38 g), at speeds over 4,100 mph half the time, 5,700 a quarter, 7,300 a tenth. So the rails are
## calm under 1.8 (88% of his flying), amber by 2.2, red from 2.7 and wholly red by 3.0 (2.5%): CALM_AT ..
## HOT_FULL. On the old scale (0.62 .. 1.12, the autopilot's margin to the grip cap) they were red 31% of the
## time. To set it again, measure his flights afresh and set those four. `pace` scales all four, live (1: these;
## lower warns sooner; 0.345 puts calm's end where it was, 0.62); `dim` is its strength (1 full, lower dimmer).
## While it is on, a line a second goes to the log, from what the frame already has, so the vehicles' scale can
## be set from his flights the same way: TAC: rails <the hardest ask within six seconds> <calm|warm|hot> |
## vehicles <lines drawn> nearest <seconds> | exit <seconds to the mouth> (- for none).
## Drawn through the world, as a display on the glass is: the bank, the fin or the hill on the inside of a
## bend is exactly what hides the road he needs to see (tested against the world's depth, the rails were gone
## behind the first fin). So that it is never drawn across the cockpit's own frame, which is a metre from the
## eye where the display is kilometres off, it is kept to within 24 degrees of the cockpit's nose from the
## seated eye (gone by 30; the A-pillars stand 35 out): inside the windscreen for any lean of the head.
## It is drawn after the world's own see-through things (under the craft's haze it was washed out).
## Quiet: nothing in the first fifth of a second's flying (the road itself is plain there), nothing over
## the lanes dead ahead, nothing flashes; a thing begins far enough off to be seen for two seconds or it is
## not begun; a far row of chevrons, seen end on, is thinned to its whole seconds and the gate; at night it is at a little
## over half its strength. Nothing is drawn standing still, at a pad, in the Aurora tube, from an outside
## camera; up a shaft, on Mount Hyperion's wall, on the shade line and off the roads, the number alone.
## Cost: the world is read once a frame, in the view. The rails are one mesh whose stations are added as they
## come into reach and sent to the renderer six at a time (the vertex shader stands them up and colours
## them: a frame sets a handful of numbers); the traffic is looked through a sixth a frame; the vehicles'
## lines and the chevrons are a MultiMesh each; the number is a Label3D (its type and its outline). Five
## draws. Beside 218 vehicles at 5,000 mph it took a tenth of a millisecond of the main thread a frame (0.10 ms
## with the exits laid in seconds and the log, 2026-11-23, against 0.08 before: one run each, within their noise).
## The quick menu's OPTIONS pages switch it (TACTICAL DISPLAY, saved; off unless switched on). Off, there is
## no node: nothing is drawn and nothing runs but the cockpit's one test of `wanted`.
##   tactical = TacticalDisplay.frame(view, tactical, delta, flow)      the cockpit's one call a frame
## tests/test_tactical_display.gd holds it to the above; tests/render_tactical.gd is the pictures and the cost.
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")
const Hour := preload("res://view/outlook.gd")
const Pilot := preload("res://view/autopilot.gd")      # (the junctions' own map: across())
const Traffic := preload("res://view/network_traffic.gd")
const MPH := 2.236936
const G := 9.81

static var wanted := false                  # the switch
static var pace := 1.0                      # the rails' scale: 1 is CALM_AT .. HOT_FULL as set from his flights; lower warns sooner (0.345: calm ends at the old 0.62). Read every frame.
static var dim := 1.0                       # its strength: 1 full, lower dimmer. Read every frame.
static var tac_lines := 0                   # (tests: the TAC lines printed since this was last set to 0)
static var drawn := true                    # (timings only: false builds and runs it all and draws none of it)
static var probe_usec := 0                  # (timings only: the microseconds its frames have taken since this was last set to 0)

# --- when ---
const SPEED_MPH := Vector2(60.0, 200.0)     # nothing under the first, all of it from the second
const FADE_T := 0.4                         # s: it comes and goes over this
const NIGHT := 0.55                         # its strength at night, of the day's (Outlook.darkness)
const HALL := 0.6                           # ... and under a city's roof
const PRIORITY := 1                         # drawn after the world's own see-through things (the craft's haze, the clouds, the canopy's glass: under them it was washed out), before the map, the menu and the fade
const PANE := Vector2(24.0, 30.0)           # degrees off the cockpit's nose, from the seated eye: all of it inside the first, none of it past the second (the A-pillars stand 35 degrees out)

# --- the road ahead ---
const LOOK_S := 12.0                        # s of flying that the rails run ahead ...
const REACH := Vector2(1500.0, 28000.0)     # ... never less or more than these, m
const NEAR_S := Vector2(0.2, 0.6)           # s of flying ahead: nothing before the first, all of it from the second ...
const NEAR_MIN := Vector2(60.0, 200.0)      # ... and never nearer than these, m
const STEP_NET := 4                         # samples between stations on the Network (96 m) ...
const STEP_COURSE := 2                      # ... and on a course (24 m)
const RAIL_INSET := 2.5                     # m inside the road's edge
const RAIL_RISE := Vector2(0.3, 3.0)        # degrees: a rail's height as the eye sees it, where it begins and at its far end (it rises with the distance between)
const RAIL_H := Vector2(0.6, 2600.0)        # ... never lower or higher than these, m
const RAIL_LINE := 4.0                      # pixels: the line along a rail's top ...
const RAIL_HOT_LINE := 1.75                 # ... this many times that where the bend is red
const RAIL_CURTAIN := Vector3(0.09, 0.15, 0.3)     # the curtain under it: its strength where the bend is calm, amber, red
const CALM_AT := 1.8                        # of what she can hold, times `pace`: a bend under this is calm (3 in 4 of his bends, 88% of his flying: see the header) ...
const WARM_AT := 2.2                        # ... amber by this (9 in 10 of his bends ask less) ...
const HOT_AT := 2.7                         # ... red from this (19 in 20 ask less) ...
const HOT_FULL := 3.0                       # ... and wholly red by this
const GROW_USEC := 250                      # the most of a frame spent reading road that has come into reach
const MAX_STATIONS := 448
const TRIM_AT := 64                         # stations behind her before they are dropped
const AHEAD_SPARE := 10                     # stations kept laid beyond what shows ...
const SEND_EVERY := 6                       # ... so the mesh is sent to the renderer once for this many added, not for each
const REANCHOR := 60000.0                   # m from where the rails' own places are measured before they are laid again
const RAIL_CALM := Color(0.5, 0.42, 1.0)    # the rails' own: a blue violet (darker than the vehicles' cyan, so it stands off a pale sky) ...
const RAIL_WARM := Color(0.8, 0.3, 1.0)     # ... violet ...
const RAIL_HOT := Color(1.0, 0.18, 0.86)    # ... magenta: none of them the vehicles' cyan, amber or red, nor the exits' green
# The right-hand rail's own (Luke, 2026-11-23: "make the tac hud lane guides different colors on each side? the purple
# and purple are hard to see together"): the left rail keeps the violets above, the right runs rose to pink, and both
# meet in the same magenta where a bend is red, so a hot bend reads the same whichever wall it is on. Left and right
# are hers, the way she flies the road, not the way its samples run.
const RAIL_CALM_RIGHT := Color(1.0, 0.42, 0.62)   # a rose: as far from the left's blue violet as the vehicles' and exits' colours leave room for ...
const RAIL_WARM_RIGHT := Color(1.0, 0.3, 0.75)    # ... a hot pink ...
const CALM := Color(0.0, 0.8, 1.0)          # the vehicles': a cyan that stands off a pale sky and a dark road alike ...
const WARM := Color(1.0, 0.7, 0.1)          # ... amber ...
const HOT := Color(1.0, 0.16, 0.08)         # ... red

# --- the vehicles ---
const LOOK_T := 8.0                         # s: a vehicle she would reach within this, at the speed she is closing on it now
const BEGIN_T := 2.0                        # s: a line is not begun for one nearer in time than this, unless it is in her way
const CORRIDOR := 60.0                      # m either side of her own line: in her way (her lane and half the next: the lanes are 45 m apart)
const CAR_NEAR := Vector2(60.0, 220.0)      # m: a line is gone by the first, whole from the second (the vehicle itself is plain by then)
const MAX_LINES := 12
const SCAN_FRAMES := 6                      # the traffic is looked through a share a frame: all of it in this many frames (a twentieth of a second at 120 Hz)
const THIN := Vector2i(4, 6)                # more candidates than the second: only those in her way keep a line; back at the first
const LINE_ANGLE := 1.6                     # degrees: a line's height as the eye sees it ...
const LINE_H := Vector2(5.0, 700.0)         # ... never lower or higher than these, m
const LINE_W := Vector2(2.0, 4.5)           # its half width: m, and never under this many pixels
const LINE_FADE := 0.3                      # s
const SIDE_LINE := Vector2(0.6, 0.5)        # a vehicle not in her way: its line this much of the height, and of the strength
const SOON := Vector3(5.0, 2.5, 1.2)        # s to reach it: calm from the first, amber at the second, red by the third
const NEAR_REACH := 2500.0                  # m: a vehicle on another road is looked at inside this (a ramp running into hers)
const ALONG := 0.8                          # ... and counts if it is going along her road (the cosine: within 37 degrees) ...
const SAME_DECK := 12.0                     # ... on her road's own level, to this many metres (not on a road crossing overhead)

# --- the exits ---
const EXIT_LEAD_S := 7.0                    # s before an exit's mouth that its gate and chevrons begin ...
const EXIT_LEAD := Vector2(8000.0, 24000.0) # ... never less or more than these, m (the lane's own paint begins 8 km out)
const EXIT_CLEAR_S := 2.5                   # ... and no chevron nearer her, when they are laid, than this many seconds
const EXIT_GREEN := Color(0.25, 1.0, 0.55)  # (the lanes' own green: view/network_world.gd)
const CHEV_EVERY := Vector2(0.25, 0.5)      # s apart, at the speed she was doing when they were laid: over the last CHEV_TIGHT before the mouth, and before that ...
const CHEV_TIGHT := 2.0                     # s
const CHEV_GAP := 144.0                     # ... and never nearer one another than this, m (slower, the quarters go, then the halves; the whole seconds stay)
const CHEV_TIER := Vector3(1.3, 1.0, 0.72)  # a chevron's size: at a whole second before the mouth, at a half, at a quarter
const CHEV_ON := 6                          # ... and this many on along the exit itself, 240 m apart
const JOIN_LOOK := 6000.0                   # m: a join ahead is marked inside this ...
const JOIN_COUNT := 5                       # ... with this many chevrons past its mouth ...
const JOIN_EVERY := 12                      # ... this many samples apart (288 m)
const MAX_CHEVRONS := 96
const CHEV_THIN := Vector2(3000.0, 6000.0)  # m (and CHEV_THIN_S): the quarters are drawn within the first, the halves within the second, the whole seconds and the gate from any way off (end on, a far row's lie one over another)
const CHEV_THIN_S := Vector2(2.0, 4.0)      # ... or within these seconds' flying, if further
const CHEV_ANGLE := 0.4                     # degrees: a far chevron's half size as the eye sees it (times its tier) ...
const CHEV_OWN_S := 2.5                     # ... and from this many seconds off (at the speed it was laid for) it is a thing of its own size, and grows as she nears ...
const CHEV_OWN := Vector2(14.0, 36.0)       # ... that size (its half) never under or over these, m (a lane is 52 m wide)
const CHEV_FAR_DIM := 0.6                   # far off, at twice the distance where it is its own size, its strength is halfway from this to all of it
const CHEV_SIZE := Vector2(2.5, 220.0)      # m: never under or over these
const CHEV_FOOT := 1.5                      # m over the road
const GATE_ANGLE := 0.55                    # the gate at an exit's mouth: its half width as the eye sees it, far off ...
const GATE_OWN := 30.0                      # ... and its own: never under this, m (the lane's rails stand 26 m either side of its middle), nor under a whole second's chevron's
const GATE_TALL := 2.2                      # ... as tall as this many half widths (a little taller than wide: taller, near the mouth it stood over the number)
const CHEV_RATE := 1.1                      # the wave: this many crests a second pass a place ...
const CHEV_WAVE := 1400.0                   # ... this far apart, m

# --- the speed ---
const NUMBER_AHEAD := 60.0                  # m ahead of the seated eye, on the craft's own way
const NUMBER_ELEVATION := 4.5               # degrees over level
const NUMBER_HEIGHT := 2.0                  # degrees: a figure's height
const NUMBER_STEP := 10                     # mph it is rounded to ...
const NUMBER_EVERY := 0.1                   # ... and s between its readings
const NUMBER_LOOK_S := 6.0                  # it takes the colour of the hardest bend within this many seconds

var view
var sim
var amount := 0.0                           # 0 off .. 1 on, eased
var rails: MeshInstance3D
var rail_mesh: ArrayMesh
var rail_mat: ShaderMaterial
var lines: MultiMeshInstance3D
var line_mat: ShaderMaterial
var chevrons: MultiMeshInstance3D
var chev_mat: ShaderMaterial
var number: Label3D
var number_load := 0.0                      # the hardest bend's ask within NUMBER_LOOK_S, of what she can hold
var marks := {}                             # a vehicle's id -> its Mark: the lines, eased in and out
var exits: Array = []                       # the exits and joins whose chevrons are laid: [{key, join, mouth, side, to}]
var chevron_count := 0
var chev_laid: Array = []                   # the chevrons as they were laid: [the exit's key, its place and facing (scaled by its tier), m still to the mouth, "chevron" "gate" or "join", its tier, its own half size m, what the shader is given] (tests read it: a headless renderer gives nothing back)
var line_count := 0                         # the lines drawn this frame ...
var _line_way := PackedByteArray()
var line_tints := PackedColorArray()        # ... and each one's colour and strength (tests read them: a headless renderer gives nothing back)
var thinned := false
var _found: Array = []                      # the vehicles that could matter, found so far this pass through the traffic
var _scan_at := 0                           # ... and how far through it the pass is

# the route: the road ahead, a station at a time
var route_road := -1                        # the road it was laid from, and which way along it
var route_dir := 0
var route_done := false                     # it has run out of road
var st_road := PackedInt32Array()
var st_i := PackedInt32Array()
var st_x := PackedFloat64Array()            # the road's middle there (the sims' metres) ...
var st_y := PackedFloat64Array()
var st_tx := PackedFloat64Array()           # ... the way it runs, the way she flies it ...
var st_ty := PackedFloat64Array()
var st_half := PackedFloat64Array()         # ... its half width ...
var st_h := PackedFloat64Array()            # ... its middle's height ...
var st_s := PackedFloat64Array()            # ... how far along the route ...
var st_k := PackedFloat64Array()            # ... its curvature, 1/m (+: a left-hander the way she flies it): the harder of the bends into and out of it ...
var st_bank := PackedFloat64Array()         # ... and its bank into that bend, radians
var spans := {}                             # road -> [first sample, its s, way, last sample]: where the route runs on each road
var pod_s := 0.0                            # where she is along it, m
var pod_left := 0.0                         # ... and across it, m left of the road's middle the way she flies
var at := 0                                 # the last station she has passed
var _ax := 0.0                              # the rails' anchor (the sims' metres): their own places are measured from it
var _ay := 0.0
var _verts := PackedVector3Array()
var _uv := PackedVector2Array()             # x: 0 the rail's foot, 1 its top; y: the bank into the bend
var _uv2 := PackedVector2Array()            # x: m along the route; y: the curvature, 1/m
var _side := PackedColorArray()             # r: 0 her left-hand rail, 1 her right (the rails' colours differ by side)
var _index := PackedInt32Array()
var _dirty := false
var _net := false
var _step := STEP_NET
var _clock := 0.0
var _tick := 0
var _route_age := 0.0
var _number_t := 0.0
var _number_tint := Color(0, 0, 0, 0)
var _unsent := 0                            # stations added at the far end since the mesh was last sent to the renderer
var _chev_ax := 0.0
var _chev_ay := 0.0
var _pace_sent := -1.0                      # the scale the rails' shader has
var _tac_t := 0.0                           # s since the last TAC line ...
var last_tac := ""                          # ... and it (tests read it)
var _px := 0.0                              # (a sample, read: _sample)
var _py := 0.0
var _tx := 0.0
var _ty := 0.0
var _nx := 0.0
var _ny := 0.0
var _w := 0.0

## A vehicle's line.
class Mark:
	var id := 0
	var car: Traffic.Car
	var a := 0.0             # its strength now, 0..1 ...
	var to := 1.0            # ... and where that is going
	var seconds := 0.0       # till she reaches it, as the last pass through the traffic found
	var way := false         # in her way
	var tint := Color.WHITE  # its colour, for those seconds


const RAIL_SHADER := """
// The tactical display's rails (view/tactical_display.gd). Each station of the road ahead is four vertices: a
// foot and a top at each edge, both at the edge's place on the road. The top is stood up here by what the
// eye needs (rail_tan of its distance), and the colour is the bend's ask against what the craft holds at the
// speed she is doing: UV2.y the curvature, UV.y the bank into the bend.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform mat4 to_seat = mat4(1.0);      // the world to the cockpit's own frame at the seated eye (-Z its nose)
uniform vec2 pane = vec2(0.42, 0.52);   // radians off the nose, from the seated eye: all of it inside the first, none past the second

float through_glass(vec3 world_place) {
	vec3 d = (to_seat * vec4(world_place, 1.0)).xyz;
	return d.z < -1.0 ? 1.0 - smoothstep(pane.x, pane.y, abs(atan(d.x, -d.z))) : 0.0;
}
uniform float pod_s = 0.0;
uniform float reach = 12000.0;
uniform vec2 fade_in = vec2(250.0, 900.0);
uniform float speed2 = 0.0;
uniform float grip = 135.0;
uniform vec2 bank_law = vec2(1.0, 0.00039);
uniform vec2 rail_rise = vec2(0.0052, 0.0524);
uniform vec2 rail_h = vec2(0.6, 2600.0);
uniform float rail_line = 4.0;
uniform float hot_line = 1.75;
uniform vec3 curtain = vec3(0.09, 0.15, 0.3);
uniform vec4 at_load = vec4(1.8, 2.2, 2.7, 3.0);
uniform vec3 calm : source_color = vec3(0.5, 0.42, 1.0);
uniform vec3 warm : source_color = vec3(0.8, 0.3, 1.0);
uniform vec3 hot : source_color = vec3(1.0, 0.18, 0.86);
uniform vec3 calm_right : source_color = vec3(1.0, 0.42, 0.62);   // the right-hand rail's calm and amber (COLOR.r 1: her right) ...
uniform vec3 warm_right : source_color = vec3(1.0, 0.3, 0.75);    // ... meeting the left's in `hot`
uniform float gain = 1.0;
varying float ask;
varying float fade;
varying float right_side;

void vertex() {
	right_side = COLOR.r;
	float along = UV2.x - pod_s;
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float hold = grip + bank_law.x * (9.81 * tan(UV.y) + bank_law.y * speed2 * sin(UV.y));
	ask = UV2.y * speed2 / max(hold, 0.1);
	fade = gain * smoothstep(fade_in.x, fade_in.y, along) * (1.0 - smoothstep(reach * 0.85, reach, along)) * through_glass((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	// as tall as the eye needs it: a far station stands higher in the view than a near one
	float tall = clamp(dist * max(rail_rise.x, rail_rise.y * clamp(along / reach, 0.0, 1.0)), rail_h.x, rail_h.y);
	VERTEX.y += UV.x * tall * step(0.002, fade);      // (nothing to fill where it is not shown)
}

void fragment() {
	float amber = smoothstep(at_load.x, at_load.y, ask);
	float red = smoothstep(at_load.z, at_load.w, ask);
	float r_side = step(0.5, right_side);
	vec3 colour = mix(mix(mix(calm, calm_right, r_side), mix(warm, warm_right, r_side), amber), hot, red);
	float t = clamp(UV.x, 0.0, 1.0);
	float edge = clamp(rail_line * mix(1.0, hot_line, red) * fwidth(UV.x), 0.004, 0.6);      // the line along its top, a few pixels of it (more where it is red)
	float line = smoothstep(1.0 - edge, 1.0 - 0.5 * edge, t);
	float under = mix(mix(curtain.x, curtain.y, amber), curtain.z, red) * (0.35 + 0.65 * t * t);
	ALBEDO = colour;
	ALPHA = clamp(fade * max(line, under), 0.0, 1.0);
}
"""

const LINE_SHADER := """
// The tactical display's lines on the vehicles (view/tactical_display.gd). An instance stands at a vehicle's
// lamps; the quad has no shape of its own (UV is its corner, -1..1). It is stood straight up, turned to the
// eye, line_tan of its distance tall and never thinner than a few pixels. COLOR: its colour and strength;
// INSTANCE_CUSTOM.x: its height, of the full one.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform mat4 to_seat = mat4(1.0);      // the world to the cockpit's own frame at the seated eye (-Z its nose)
uniform vec2 pane = vec2(0.42, 0.52);   // radians off the nose, from the seated eye: all of it inside the first, none past the second

float through_glass(vec3 world_place) {
	vec3 d = (to_seat * vec4(world_place, 1.0)).xyz;
	return d.z < -1.0 ? 1.0 - smoothstep(pane.x, pane.y, abs(atan(d.x, -d.z))) : 0.0;
}
uniform float line_tan = 0.0175;
uniform vec2 line_h = vec2(5.0, 420.0);
uniform vec2 line_w = vec2(2.0, 2.5);
uniform vec2 fade_in = vec2(60.0, 220.0);
uniform float gain = 1.0;
varying vec3 tint;
varying float lit;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float dist = max(length(c), 1.0);
	vec3 side = cross(up, -c / dist);
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float pixel = max(-c.z, 0.5) * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float tall = clamp(dist * line_tan, line_h.x, line_h.y) * INSTANCE_CUSTOM.x;
	float wide = max(line_w.x, line_w.y * pixel);
	lit = COLOR.a * gain * smoothstep(fade_in.x, fade_in.y, dist) * through_glass(MODEL_MATRIX[3].xyz);
	tint = pow(COLOR.rgb, vec3(2.2));      // authored sRGB
	vec3 p = c;
	if (lit > 0.004) {
		p += up * ((UV.y * 0.5 + 0.5) * tall) + side * (UV.x * wide);
	}
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	float x = abs(UV.x);
	float y = UV.y * 0.5 + 0.5;
	float stem = (1.0 - smoothstep(0.22, 0.46, x)) * smoothstep(0.0, 0.04, y) * 0.8;
	float head = 1.0 - smoothstep(0.75, 1.0, x + abs(y - 0.95) / 0.05);      // a small diamond at its top
	ALBEDO = tint;
	ALPHA = clamp(lit * max(stem, head), 0.0, 1.0);
}
"""

const CHEVRON_SHADER := """
// The tactical display's chevrons over an exit's lane (view/tactical_display.gd). An instance stands on the
// lane, its x the way the lane leaves, its scale its tier (a whole second's chevron is bigger than a half's);
// the quad has no shape of its own (UV is its corner, -1..1). Upright. INSTANCE_CUSTOM: x the metres still to
// the mouth (less than none past it), y the clock when it was laid, z how far off it is still drawn (far off a
// row is seen end on and its chevrons lie one over another: level 1 is drawn within thin.y metres, level 2
// within thin.x, level 0 from any way off), w its own half size, m. Its half size is that, or chev_tan of its
// distance where that is more (far off): near, it grows as she nears as a thing of its size does; far, it
// keeps one size to the eye and is dimmer. w under 0: the gate at the mouth, a frame across the lane
// gate_tall half widths tall, never under gate_tan of its distance, steady.
// A wave of light runs along the row toward the mouth and on.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform mat4 to_seat = mat4(1.0);      // the world to the cockpit's own frame at the seated eye (-Z its nose)
uniform vec2 pane = vec2(0.42, 0.52);   // radians off the nose, from the seated eye: all of it inside the first, none past the second

float through_glass(vec3 world_place) {
	vec3 d = (to_seat * vec4(world_place, 1.0)).xyz;
	return d.z < -1.0 ? 1.0 - smoothstep(pane.x, pane.y, abs(atan(d.x, -d.z))) : 0.0;
}
uniform float chev_tan = 0.00698;
uniform float gate_tan = 0.0096;
uniform float gate_tall = 2.2;
uniform float far_dim = 0.6;
uniform vec2 chev_size = vec2(2.5, 220.0);
uniform float foot = 1.5;
uniform vec2 fade_in = vec2(250.0, 900.0);
uniform float clock = 0.0;
uniform float rate = 1.1;
uniform float wave = 1400.0;
uniform vec2 thin = vec2(3000.0, 6000.0);
uniform float gain = 1.0;
varying vec3 tint;
varying float lit;
varying float gate;
varying float tall;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 across = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	float tier = length(across);
	vec3 out_way = across / max(tier, 1e-6);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float dist = length(c);
	gate = INSTANCE_CUSTOM.w < 0.0 ? 1.0 : 0.0;
	float own = abs(INSTANCE_CUSTOM.w);
	float least = dist * mix(chev_tan, gate_tan, gate);
	float size = tier * clamp(max(own, least), chev_size.x, chev_size.y);
	float near = clamp(own / max(least, 0.001), 0.0, 1.0);      // 1 from where it is its own size
	float crest = 0.5 + 0.5 * sin(6.2831853 * (clock * rate + INSTANCE_CUSTOM.x / wave));
	float far_off = INSTANCE_CUSTOM.z < 0.5 ? 1.0 : 1.0 - smoothstep(0.8, 1.0, dist / (INSTANCE_CUSTOM.z < 1.5 ? thin.y : thin.x));
	lit = COLOR.a * gain * far_off * smoothstep(fade_in.x, fade_in.y, dist) * smoothstep(0.0, 0.5, clock - INSTANCE_CUSTOM.y)
		* mix(mix(0.45, 1.0, crest), 1.0, gate) * mix(far_dim, 1.0, max(near, gate)) * through_glass(MODEL_MATRIX[3].xyz);
	tint = pow(COLOR.rgb, vec3(2.2));      // authored sRGB
	tall = mix(2.0, gate_tall, gate);      // its height, in half sizes
	vec3 p = c;
	if (lit > 0.004) {
		p += out_way * (UV.x * size) + up * (foot + 0.5 * tall * size * (1.0 + UV.y));
	}
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	float shape;
	if (gate > 0.5) {
		// a frame: two posts and the lintel over them, as thick as one another, never under a few pixels
		vec2 soft = max(vec2(0.01), fwidth(UV));
		vec2 bar = max(vec2(0.16, 0.32 / tall), 3.0 * soft);
		float posts = smoothstep(1.0 - bar.x - soft.x, 1.0 - bar.x + soft.x, abs(UV.x));
		float lintel = smoothstep(1.0 - bar.y - soft.y, 1.0 - bar.y + soft.y, UV.y);
		shape = max(posts, lintel);
	} else {
		float c = UV.x + 0.7 * abs(UV.y);
		float soft = max(0.02, fwidth(c));
		float arms = max(1.0 - smoothstep(0.13 - soft, 0.13 + soft, abs(c - 0.55)), 1.0 - smoothstep(0.13 - soft, 0.13 + soft, abs(c + 0.05)));
		shape = arms * (1.0 - smoothstep(0.9, 1.0, abs(UV.y)));
	}
	ALBEDO = tint;
	ALPHA = clamp(lit * shape, 0.0, 1.0);
}
"""


# ---------------------------------------------------------------- what the craft can hold

## What the craft holds across her path with no brake on, m/s^2: the sim's own grip caps, her engines' and
## her pod's, by their masses (CraftSim.step: each body's sideways force is capped at its mass times its cap).
static func grip(s) -> float:
	var P: Dictionary = s.P
	var engines: float = s.eL.m + s.eR.m
	var pod: float = s.pod.m
	return G * (engines * float(P.gripCapG) + pod * float(P.podCapG)) / (engines + pod)


## ... and with the road banked `bank_in` radians into the bend, at `speed` m/s: the bank's own push toward
## the bend's middle added, as the sims add it (CraftSim.step: gravity's g tan(bank), the downforce's
## bankDown v^2 sin(bank)).
static func hold(s, speed: float, bank_in := 0.0) -> float:
	var P: Dictionary = s.P
	return grip(s) + float(P.bank) * (G * tan(bank_in) + float(P.bankDown) * speed * speed * sin(bank_in))


## A bend's ask at `speed` m/s, of what the craft holds there: under 1 she makes it, over 1 she does not.
static func load_of(s, curvature: float, speed: float, bank_in := 0.0) -> float:
	return absf(curvature) * speed * speed / maxf(hold(s, speed, bank_in), 0.1)


## The rails' scale now: CALM_AT, WARM_AT, HOT_AT, HOT_FULL times `pace`.
static func thresholds() -> Vector4:
	var p := maxf(pace, 0.01)
	return Vector4(CALM_AT * p, WARM_AT * p, HOT_AT * p, HOT_FULL * p)


## The colour that goes with it (the rails' shader's own, and the number's).
static func tint(ask: float) -> Color:
	var at := thresholds()
	return RAIL_CALM.lerp(RAIL_WARM, smoothstep(at.x, at.y, ask)).lerp(RAIL_HOT, smoothstep(at.z, at.w, ask))


## ... in a word (the TAC line's): calm under CALM_AT, warm from it, hot from HOT_AT (times `pace`).
static func heat(ask: float) -> String:
	var p := maxf(pace, 0.01)      # (in doubles: a Vector4's floats would put 2.7 itself under HOT_AT)
	return "hot" if ask >= HOT_AT * p else ("warm" if ask >= CALM_AT * p else "calm")


## A vehicle's line: by the seconds till she reaches it.
static func soon_tint(seconds: float) -> Color:
	return HOT.lerp(WARM, smoothstep(SOON.z, SOON.y, seconds)).lerp(CALM, smoothstep(SOON.y, SOON.x, seconds))


## How far ahead the rails run at `speed` m/s.
static func reach_at(speed: float) -> float:
	return clampf(speed * LOOK_S, REACH.x, REACH.y)


## Where the rails begin ahead of her at `speed` m/s: nothing before x, all of it from y (m).
static func near_at(speed: float) -> Vector2:
	return Vector2(maxf(speed * NEAR_S.x, NEAR_MIN.x), maxf(speed * NEAR_S.y, NEAR_MIN.y))


## How far before an exit's mouth its chevrons begin at `speed` m/s.
static func exit_lead(speed: float) -> float:
	return clampf(speed * EXIT_LEAD_S, EXIT_LEAD.x, EXIT_LEAD.y)


## A chevron's own half size, m, laid at `speed` m/s: from CHEV_OWN_S seconds off it is no smaller to the eye
## than a far one.
static func chev_own(speed: float) -> float:
	return clampf(speed * CHEV_OWN_S * tan(deg_to_rad(CHEV_ANGLE)), CHEV_OWN.x, CHEV_OWN.y)


## Its half size, m, at `dist` m from the eye (the chevrons' shader's own rule): its own, or far off, a set angle
## of the distance; times its tier. The gate's half width likewise, by its own angle.
static func chev_half(dist: float, own: float, tier := 1.0, gate := false) -> float:
	var least := dist * tan(deg_to_rad(GATE_ANGLE if gate else CHEV_ANGLE))
	return tier * clampf(maxf(own, least), CHEV_SIZE.x, CHEV_SIZE.y)


static func _wrap(a: float) -> float:
	return atan2(sin(a), cos(a))


# ---------------------------------------------------------------- the cockpit's one call

## A frame, from the cockpit: built when it is first wanted, freed when it is not. `node` is what the last
## call gave back (null at first); `flow` the craft's own way in the view's space (its origin the seated eye,
## its -Z the way she is going, level: the speed rush's frame); `in_seat`: the pilot is looking out of the
## cockpit and the craft is his to fly (not an outside camera, not a start-up). -> the display, or null while
## it is off.
static func frame(v, node, delta: float, flow: Transform3D, in_seat := true):
	if not wanted:
		if node != null and is_instance_valid(node):
			node.queue_free()
		return null
	if node == null or not is_instance_valid(node):
		node = new()
		v.add_child(node)
		node.build(v)
	var began := Time.get_ticks_usec()
	node.sync(delta, flow, in_seat)
	probe_usec += Time.get_ticks_usec() - began
	return node


func build(v) -> void:
	view = v
	sim = v.sim
	name = "TacticalDisplay"
	_net = String(sim.kind) == "network"
	_step = STEP_NET if _net else STEP_COURSE
	var bounds := AABB(Vector3(-400000.0, -3000.0, -400000.0), Vector3(800000.0, 40000.0, 800000.0))
	# the rails
	var rail_shader := Shader.new()
	rail_shader.code = RAIL_SHADER
	rail_mat = ShaderMaterial.new()
	rail_mat.shader = rail_shader
	rail_mat.set_shader_parameter("rail_rise", Vector2(tan(deg_to_rad(RAIL_RISE.x)), tan(deg_to_rad(RAIL_RISE.y))))
	rail_mat.set_shader_parameter("rail_h", RAIL_H)
	rail_mat.set_shader_parameter("rail_line", RAIL_LINE)
	rail_mat.set_shader_parameter("hot_line", RAIL_HOT_LINE)
	rail_mat.set_shader_parameter("curtain", RAIL_CURTAIN)
	rail_mat.set_shader_parameter("at_load", thresholds())
	_pace_sent = pace
	rail_mat.set_shader_parameter("calm", RAIL_CALM)
	rail_mat.set_shader_parameter("warm", RAIL_WARM)
	rail_mat.set_shader_parameter("hot", RAIL_HOT)
	rail_mat.set_shader_parameter("calm_right", RAIL_CALM_RIGHT)
	rail_mat.set_shader_parameter("warm_right", RAIL_WARM_RIGHT)
	rail_mesh = ArrayMesh.new()
	rails = MeshInstance3D.new()
	rails.name = "tactical_rails"
	rails.mesh = rail_mesh
	rails.material_override = rail_mat
	_dress(rails, bounds)
	for material: ShaderMaterial in [rail_mat]:
		material.set_shader_parameter("pane", Vector2(deg_to_rad(PANE.x), deg_to_rad(PANE.y)))
	_index.resize((MAX_STATIONS - 1) * 12)
	for k in MAX_STATIONS - 1:      # the two rails between station k and the next: the same for any number of stations
		var a := 4 * k
		var b := a + 4
		var o := 12 * k
		for n in 2:
			_index[o + 6 * n] = a + 2 * n
			_index[o + 6 * n + 1] = a + 2 * n + 1
			_index[o + 6 * n + 2] = b + 2 * n
			_index[o + 6 * n + 3] = a + 2 * n + 1
			_index[o + 6 * n + 4] = b + 2 * n + 1
			_index[o + 6 * n + 5] = b + 2 * n
	# the vehicles' lines
	var line_shader := Shader.new()
	line_shader.code = LINE_SHADER
	line_mat = ShaderMaterial.new()
	line_mat.shader = line_shader
	line_mat.set_shader_parameter("line_tan", tan(deg_to_rad(LINE_ANGLE)))
	line_mat.set_shader_parameter("line_h", LINE_H)
	line_mat.set_shader_parameter("line_w", LINE_W)
	line_mat.set_shader_parameter("fade_in", CAR_NEAR)
	line_mat.set_shader_parameter("pane", Vector2(deg_to_rad(PANE.x), deg_to_rad(PANE.y)))
	lines = _batch("tactical_lines", MAX_LINES, line_mat, bounds)
	line_tints.resize(MAX_LINES)
	_line_way.resize(MAX_LINES)
	_line_way.fill(255)
	# the exits' chevrons
	var chev_shader := Shader.new()
	chev_shader.code = CHEVRON_SHADER
	chev_mat = ShaderMaterial.new()
	chev_mat.shader = chev_shader
	chev_mat.set_shader_parameter("chev_tan", tan(deg_to_rad(CHEV_ANGLE)))
	chev_mat.set_shader_parameter("gate_tan", tan(deg_to_rad(GATE_ANGLE)))
	chev_mat.set_shader_parameter("gate_tall", GATE_TALL)
	chev_mat.set_shader_parameter("far_dim", CHEV_FAR_DIM)
	chev_mat.set_shader_parameter("chev_size", CHEV_SIZE)
	chev_mat.set_shader_parameter("foot", CHEV_FOOT)
	chev_mat.set_shader_parameter("rate", CHEV_RATE)
	chev_mat.set_shader_parameter("wave", CHEV_WAVE)
	chev_mat.set_shader_parameter("thin", CHEV_THIN)
	chev_mat.set_shader_parameter("pane", Vector2(deg_to_rad(PANE.x), deg_to_rad(PANE.y)))
	chevrons = _batch("tactical_chevrons", MAX_CHEVRONS, chev_mat, bounds)
	# the speed
	number = Label3D.new()
	number.name = "tactical_speed"
	number.font_size = 160
	number.pixel_size = NUMBER_AHEAD * tan(deg_to_rad(NUMBER_HEIGHT)) / 112.0      # (a figure is about 0.7 of the font's size)
	number.outline_size = 28
	number.outline_modulate = Color(0.0, 0.03, 0.05, 0.8)
	number.shaded = false
	number.double_sided = false
	number.fixed_size = false
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	number.no_depth_test = true      # (nothing of the cockpit is where it stands; a bridge going by overhead must not blink it)
	number.render_priority = PRIORITY + 1
	number.outline_render_priority = PRIORITY
	number.visible = false
	add_child(number)


func _dress(node: GeometryInstance3D, bounds: AABB) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = bounds
	(node.material_override as ShaderMaterial).render_priority = PRIORITY
	node.visible = false
	add_child(node)


func _batch(named: String, count: int, material: ShaderMaterial, bounds: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = corner_mesh()
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = named
	node.multimesh = mm
	node.material_override = material
	_dress(node, bounds)
	return node


## A quad with all four corners at one point, its corner in UV (-1..1): the shaders spread it.
static func corner_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------- a frame

## What of it applies where the craft is: {all, road, number}. `all` 0 leaves nothing; `road` is the rails, the
## vehicles' lines and the chevrons.
func applies(in_seat := true) -> Dictionary:
	var out := {"all": 0.0, "road": false, "number": true}
	var P = sim.pod
	if sim.crash_t > 0.0 or not in_seat:      # (an outside camera has its own readout; on the pad she is still being started)
		return out
	var mph: float = sqrt(P.vx * P.vx + P.vy * P.vy) * MPH
	out.all = smoothstep(SPEED_MPH.x, SPEED_MPH.y, mph)
	if _net:
		if P.off_road or P.path < 0 or P.path >= sim.roads.size():
			return out      # (in the air off a lip, on the open ground: her speed alone)
		if sim.in_pressure(P.path, P.hint):
			out.all = 0.0      # the Aurora tube: nothing
			return out
		var R = sim.roads[P.path]
		out.road = not (R.shaft or R.deck)
	else:
		out.road = sim.N > 8 and int(P.path) == 0      # a circuit's own road: not the range, not the shade line's twist
	return out


func sync(delta: float, flow: Transform3D, in_seat := true) -> void:
	var dt := clampf(delta, 0.0, 0.05)
	_clock += dt
	_tick += 1
	var what := applies(in_seat)
	amount = move_toward(amount, float(what.all), dt / FADE_T)
	var shown: bool = amount > 0.002
	if not shown and float(what.all) <= 0.0:
		rails.visible = false
		lines.visible = false
		chevrons.visible = false
		number.visible = false
		return
	var P = sim.pod
	var speed: float = sqrt(P.vx * P.vx + P.vy * P.vy)
	var strength := amount * lerpf(1.0, NIGHT, Hour.darkness()) * clampf(dim, 0.0, 1.0)
	if "terminal_lighting" in view and view.terminal_lighting != null:
		strength *= lerpf(1.0, HALL, clampf(float(view.terminal_lighting.enclosure), 0.0, 1.0))
	# the cockpit's own frame at the seated eye: what is drawn is kept inside the windscreen by it
	# (in the world's own space, as the shaders have their places: the view itself is lowered when she is far aloft)
	var seat: Transform3D = (view as Node3D).global_transform * flow
	if "rig" in view and view.rig != null:
		seat = Transform3D((view.rig as Node3D).global_transform.basis.orthonormalized(), seat.origin)
	var to_seat := seat.affine_inverse()
	rail_mat.set_shader_parameter("to_seat", to_seat)
	line_mat.set_shader_parameter("to_seat", to_seat)
	chev_mat.set_shader_parameter("to_seat", to_seat)
	var on_road: bool = what.road
	if on_road:
		_follow(speed)
	else:
		route_road = -1
	rails.visible = shown and on_road and st_s.size() >= 2
	if rails.visible:
		_route_age = minf(_route_age + dt / 0.25, 1.0)
		rails.position = Vector3(_ax - float(view.org_x), 0.0, -(_ay - float(view.org_y)))
		rail_mat.set_shader_parameter("pod_s", pod_s)
		rail_mat.set_shader_parameter("reach", reach_at(speed))
		rail_mat.set_shader_parameter("fade_in", near_at(speed))
		rail_mat.set_shader_parameter("speed2", speed * speed)
		rail_mat.set_shader_parameter("grip", grip(sim))
		rail_mat.set_shader_parameter("bank_law", Vector2(float(sim.P.bank), float(sim.P.bankDown)))
		rail_mat.set_shader_parameter("gain", strength * _route_age)
		if pace != _pace_sent:
			_pace_sent = pace
			rail_mat.set_shader_parameter("at_load", thresholds())
	_lines_frame(dt, speed, shown and on_road, strength)
	_chevrons_frame(speed, shown and on_road, strength)
	_number_frame(dt, speed, shown and bool(what.number), strength, flow)
	if shown:
		_tac_frame(dt, speed)
	if not drawn:      # (timings: all of its work, none of its drawing)
		rails.visible = false
		lines.visible = false
		chevrons.visible = false
		number.visible = false


# ---------------------------------------------------------------- the road ahead

## A sample of road r, read into _px.. (the Network's roads, or a circuit's own).
func _sample(r: int, i: int) -> void:
	if _net:
		var R = sim.roads[r]
		_px = R.px[i]; _py = R.py[i]; _tx = R.tx[i]; _ty = R.ty[i]; _nx = R.nx[i]; _ny = R.ny[i]; _w = R.w[i]
	else:
		_px = sim.tpx[i]; _py = sim.tpy[i]; _tx = sim.ttx[i]; _ty = sim.tty[i]; _nx = sim.tnx[i]; _ny = sim.tny[i]; _w = sim.tw[i]


func _count(r: int) -> int:
	return int(sim.roads[r].N) if _net else int(sim.N)


## Which way along her road she is going: her travel, or standing her facing.
func way() -> int:
	if _net:
		return Pilot.way(sim)
	var i := posmod(int(sim.pod.hint), int(sim.N))
	var along: float = sim.pod.vx * sim.ttx[i] + sim.pod.vy * sim.tty[i]
	if absf(along) < 1.0:
		along = cos(sim.pod.th) * sim.ttx[i] + sin(sim.pod.th) * sim.tty[i]
	return 1 if along >= 0.0 else -1


## The route kept up with her: laid again when she is on another road or going the other way, grown at its
## far end as road comes into reach, and where she is along it found.
func _follow(speed: float) -> void:
	var P = sim.pod
	var road := int(P.path) if _net else 0
	var dir := way()
	var n := _count(road)
	var here := clampi(int(P.hint), 0, n - 1) if _net else posmod(int(P.hint), n)
	var off: float = absf(float(view.org_x) - _ax) + absf(float(view.org_y) - _ay)
	if road != route_road or dir != route_dir or off > REANCHOR or st_s.is_empty():
		_lay(road, here, dir)
	# where she is along it
	var m := st_s.size()
	var j := clampi(at, 0, m - 1)
	var along: float = (P.x - st_x[j]) * st_tx[j] + (P.y - st_y[j]) * st_ty[j]
	while j + 1 < m:
		var next: float = (P.x - st_x[j + 1]) * st_tx[j + 1] + (P.y - st_y[j + 1]) * st_ty[j + 1]
		if next < 0.0:
			break
		j += 1
		along = next
	if along < -400.0 or (j == m - 1 and along > 400.0 and not route_done):      # knocked back down it, or off its end: again
		_lay(road, here, dir)
		j = 0
		along = (P.x - st_x[0]) * st_tx[0] + (P.y - st_y[0]) * st_ty[0]
	at = j
	pod_s = st_s[j] + along
	pod_left = -(P.x - st_x[j]) * st_ty[j] + (P.y - st_y[j]) * st_tx[j]
	# the road that has come into reach, a station at a time, inside the frame's allowance
	var want: float = pod_s + reach_at(speed) + float(_step * AHEAD_SPARE) * (float(sim.NET_STEP) if _net else 12.0)
	var t0 := Time.get_ticks_usec()
	var added := 0
	while not route_done and st_s[st_s.size() - 1] < want and st_s.size() < MAX_STATIONS and (added < 2 or Time.get_ticks_usec() - t0 < GROW_USEC):
		_grow()
		added += 1
	if at > TRIM_AT:
		_trim(at - 2)
		_unsent = SEND_EVERY
	# (what has been added is past where the rails fade out: it can wait; a route still being laid cannot)
	if _dirty and (_unsent >= SEND_EVERY or route_done or st_s[st_s.size() - 1] < want or _route_age < 1.0):
		_upload()


## The route laid again from sample `here` of `road`, going `dir`.
func _lay(road: int, here: int, dir: int) -> void:
	route_road = road
	route_dir = dir
	route_done = false
	_route_age = 0.0
	at = 0
	spans.clear()
	st_x.clear(); st_y.clear(); st_tx.clear(); st_ty.clear(); st_half.clear(); st_h.clear(); st_s.clear(); st_k.clear(); st_bank.clear()
	st_road.clear()
	st_i.clear()
	_verts.clear()
	_side.clear()
	_uv.clear()
	_uv2.clear()
	_ax = float(view.org_x)
	_ay = float(view.org_y)
	var first := here - posmod(here, _step)      # (on the road's own grid: the same stations whoever lays it)
	if dir > 0 and not _net:
		first = posmod(first, _count(road))
	_station(road, clampi(first, 0, _count(road) - 1), dir)
	_dirty = true


## One more station at the route's far end: the next on its road, or where that road runs out the road it
## runs into. Sets route_done where there is no more.
func _grow() -> void:
	var m := st_s.size()
	var r := st_road[m - 1]
	var d: int = spans[r][2]
	var i := st_i[m - 1] + d * _step
	var n := _count(r)
	if not _net:
		_station(r, posmod(i, n), d)
		return
	if i >= 0 and i <= n - 1:
		_station(r, i, d)
		return
	# off the road's end: the road it is one with there (a junction's samples), the way that road is entered
	var end := n - 1 if d > 0 else 0
	for k in sim.roads[r].jx:
		var J: Array = sim.junctions[k]
		var on_a := int(J[0]) == r
		var lo := int(J[1]) if on_a else int(J[4])
		var hi := int(J[2]) if on_a else int(J[5])
		if end < lo or end > hi:
			continue
		var q := int(J[3]) if on_a else int(J[0])
		var dq := d * int(J[6])
		var iq: int = Pilot.across(J, on_a, end) + dq * _step
		if spans.has(q) or iq < 0 or iq > int(sim.roads[q].N) - 1:
			continue
		_station(q, iq, dq)
		return
	route_done = true


## A station at sample i of road r, flown the way d: its place, its surface (the views' own accessor), the
## bend into it, and its four vertices.
func _station(r: int, i: int, d: int) -> void:
	_sample(r, i)
	var m := st_s.size()
	var tx := _tx * d
	var ty := _ty * d
	var s := 0.0
	var bend := 0.0
	if m > 0:
		var gap := Vector2(_px - st_x[m - 1], _py - st_y[m - 1]).length()
		s = st_s[m - 1] + gap
		bend = _wrap(atan2(ty, tx) - atan2(st_ty[m - 1], st_tx[m - 1])) / maxf(gap, 1.0)
	var path := r if _net else 0
	var middle: Vector2 = sim.surface_at(_px, _py, i, path)
	var half := _w / 2.0
	var lat := maxf(half - RAIL_INSET, 1.0)
	st_road.append(r)
	st_i.append(i)
	st_x.append(_px)
	st_y.append(_py)
	st_tx.append(tx)
	st_ty.append(ty)
	st_half.append(half)
	st_h.append(middle.x)
	st_s.append(s)
	st_k.append(bend)
	# the bank, + down to the left the way the samples run: into the bend when it leans the way she turns
	st_bank.append(middle.y * d)
	if not spans.has(r):
		spans[r] = [i, s, d, i]
	else:
		spans[r][3] = i
	for side in [1.0, -1.0]:      # the road's left edge, then its right, the way its samples run
		var ex: float = _px + _nx * lat * side
		var ey: float = _py + _ny * lat * side
		var foot := Vector3(ex - _ax, float(sim.surface_at(ex, ey, i, path).x) + 0.3, -(ey - _ay))
		var hers := Color(0.0 if side * d > 0.0 else 1.0, 0.0, 0.0, 1.0)      # (flown against its samples, the road's left is her right)
		for top in 2:
			_verts.append(foot)
			_side.append(hers)
			_uv.append(Vector2(float(top), 0.0))
			_uv2.append(Vector2(s, 0.0))
	_unsent += 1
	_shade(m)
	if m > 0:
		if absf(bend) > absf(st_k[m - 1]):      # the station before takes the harder of the bends either side of it
			st_k[m - 1] = bend
		_shade(m - 1)
	_dirty = true


## A station's vertices given its bend and its bank into it.
func _shade(k: int) -> void:
	var bend := st_k[k]
	var leans := st_bank[k] * (1.0 if bend >= 0.0 else -1.0)
	for v in 4:
		_uv[4 * k + v] = Vector2(_uv[4 * k + v].x, leans)
		_uv2[4 * k + v] = Vector2(_uv2[4 * k + v].x, absf(bend))


## The bank into station k's own bend, radians.
func lean_at(k: int) -> float:
	return st_bank[k] * (1.0 if st_k[k] >= 0.0 else -1.0)


## The first `count` stations dropped (she is past them).
func _trim(count: int) -> void:
	if count <= 0:
		return
	st_x = st_x.slice(count); st_y = st_y.slice(count); st_tx = st_tx.slice(count); st_ty = st_ty.slice(count); st_half = st_half.slice(count)
	st_h = st_h.slice(count); st_s = st_s.slice(count); st_k = st_k.slice(count); st_bank = st_bank.slice(count)
	st_road = st_road.slice(count)
	st_i = st_i.slice(count)
	_verts = _verts.slice(4 * count)
	_side = _side.slice(4 * count)
	_uv = _uv.slice(4 * count)
	_uv2 = _uv2.slice(4 * count)
	at -= count
	_dirty = true


func _upload() -> void:
	_dirty = false
	_unsent = 0
	rail_mesh.clear_surfaces()
	var m := st_s.size()
	if m < 2:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_COLOR] = _side
	arrays[Mesh.ARRAY_INDEX] = _index.slice(0, (m - 1) * 12)
	rail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## The hardest bend's ask within `seconds` of flying at `speed` m/s, of what she holds.
func worst_load(speed: float, seconds: float) -> float:
	var worst := 0.0
	var far := pod_s + speed * seconds
	for k in range(maxi(at, 0), st_s.size()):
		if st_s[k] > far:
			break
		worst = maxf(worst, load_of(sim, st_k[k], speed, lean_at(k)))
	return worst


# ---------------------------------------------------------------- the vehicles

## The vehicles that could matter, of `cars` (NetworkTraffic.cars): on the road ahead of her (or on a road
## running along it at its own level, close by), closing, and reached within LOOK_T at the speed she is
## closing now. [{car, along (m ahead by the road), left (m left of her), seconds, way (in her way)}].
## Not a vehicle she is not gaining on, one going across her road, or one on a road over or under it. A raider (Raids:
## hostile) is, wherever it is in reach, gaining on it or not ({..., hostile: true}; seconds INF if she is not).
func pick(cars: Array, speed: float) -> Array:
	var out: Array = []
	_pick_into(out, cars, 0, cars.size(), speed)
	return out


## ... of cars[first] to cars[last - 1], added to `out`.
func _pick_into(out: Array, cars: Array, first: int, last: int, speed: float) -> void:
	var m := st_s.size()
	if m < 2 or speed < 1.0:
		return
	var reach := reach_at(speed)
	var step_m: float = sim.NET_STEP if _net else 12.0
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	for k in range(first, last):
		var c: Traffic.Car = cars[k]
		var along := 0.0
		var left := 0.0
		var its := 0.0
		if spans.has(c.road):
			var sp: Array = spans[c.road]
			var d := int(sp[2])
			if (c.f - float(sp[0])) * d < -2.0 or (c.f - float(sp[3])) * d > float(_step):
				continue
			along = float(sp[1]) + (c.f - float(sp[0])) * d * step_m - pod_s
			left = c.lat * d
			its = c.v * (1.0 if c.dir == d else -1.0)
		else:
			var dx: float = c.x - px
			var dy: float = c.y - py
			if absf(dx) > NEAR_REACH or absf(dy) > NEAR_REACH:
				continue
			var j := clampi(at, 0, m - 1)
			var ahead: float = dx * st_tx[j] + dy * st_ty[j]
			if ahead <= 0.0 or ahead > NEAR_REACH:
				continue
			# by the route's own line where the vehicle is
			j = clampi(j + roundi(ahead / maxf(1.0, st_s[mini(j + 1, m - 1)] - st_s[j])), 0, m - 1)
			var ex: float = c.x - st_x[j]
			var ey: float = c.y - st_y[j]
			its = c.hx * st_tx[j] + c.hy * st_ty[j]
			if absf(its) < ALONG:
				continue      # going across her road: over it or under it
			left = -ex * st_ty[j] + ey * st_tx[j]
			if absf(left) > st_half[j] + 10.0:
				continue      # beside her road, not on it
			if absf(float(sim.net_height(c.road, c.f)) - st_h[j]) > SAME_DECK:
				continue      # on another level
			along = st_s[j] - pod_s + ex * st_tx[j] + ey * st_ty[j]
			its *= c.v
		var closing := speed - its
		if along <= CAR_NEAR.x or along > reach:
			continue
		if c.hostile:      # a raider: in reach, it is shown, near or far, gaining on it or not
			out.append({"car": c, "along": along, "left": left - pod_left, "seconds": along / closing if closing > 1.0 else INF,
				"way": absf(left - pod_left) <= CORRIDOR, "hostile": true})
			continue
		if closing <= 1.0:
			continue
		var seconds := along / closing
		if seconds > LOOK_T:
			continue
		out.append({"car": c, "along": along, "left": left - pod_left, "seconds": seconds, "way": absf(left - pod_left) <= CORRIDOR})


func _lines_frame(dt: float, speed: float, shown: bool, strength: float) -> void:
	var traffic = view.traffic_net if "traffic_net" in view else null
	if not shown or traffic == null:
		lines.visible = false
		line_count = 0
		marks.clear()
		_found.clear()
		_scan_at = 0
		return
	# which vehicles: the traffic looked through a share a frame (their lines' places are every frame's)
	var cars: Array = traffic.cars
	var total := cars.size()
	var pass_done := _scan_at >= total
	var found := _found
	if pass_done:
		_found = []
		_scan_at = 0
	var upto := mini(total, _scan_at + maxi(8, (total + SCAN_FRAMES - 1) / SCAN_FRAMES))
	_pick_into(_found, cars, _scan_at, upto, speed)
	_scan_at = upto
	if pass_done:      # a pass is done: what it found is what there is
		if found.size() > THIN.y:
			thinned = true
		elif found.size() <= THIN.x:
			thinned = false
		for old: Mark in marks.values():
			old.to = 0.0
		# raiders first (Raids: never the ones left out, nor thinned), then those in her way (nor they), then the rest
		var raiding: bool = traffic.raids != null      # (raids off: the two passes as they were)
		for rank in range(0 if raiding else 1, 3):
			for f in found:
				var hostile: bool = raiding and bool(f.get("hostile", false))
				if (0 if hostile else (1 if bool(f.way) else 2)) != rank:
					continue
				var pass_way := rank < 2
				var id: int = f.car.id
				var mark: Mark = marks.get(id)
				if mark != null:
					mark.to = 0.0 if (thinned and not pass_way) else 1.0
				elif marks.size() < MAX_LINES and (pass_way or (not thinned and float(f.seconds) >= BEGIN_T)):
					mark = Mark.new()
					mark.id = id
					mark.car = f.car
					marks[id] = mark
				if mark != null:
					mark.seconds = f.seconds
					mark.way = pass_way
					mark.tint = Traffic.HOSTILE_COL if hostile else (soon_tint(mark.seconds) if pass_way else CALM)
	var mm := lines.multimesh
	var k := 0
	var ease := dt / LINE_FADE
	for mark: Mark in marks.values():
		mark.a = move_toward(mark.a, mark.to, ease)
		if mark.a <= 0.0 and mark.to <= 0.0:
			marks.erase(mark.id)
			continue
		var in_way := mark.way
		var colour := mark.tint
		colour.a = mark.a * (1.0 if in_way else SIDE_LINE.y)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, mark.car.lamp_position))
		if line_tints[k] != colour or _line_way[k] != int(in_way):
			mm.set_instance_color(k, colour)
			mm.set_instance_custom_data(k, Color(1.0 if in_way else SIDE_LINE.x, 0.0, 0.0, 0.0))
			line_tints[k] = colour
			_line_way[k] = int(in_way)
		k += 1
	mm.visible_instance_count = k
	line_count = k
	lines.visible = k > 0
	line_mat.set_shader_parameter("gain", strength)


# ---------------------------------------------------------------- the exits

## The exits and joins ahead on her road, from the world's own lanes (NetworkWorld.exit_lanes): an exit whose
## mouth is within its lead and still EXIT_CLEAR_S off, a join within JOIN_LOOK.
## [{key, join, road, mouth (sample), ahead (m), side (+1 leaves to the left the way she flies), mid, to}]
func exits_ahead(speed: float) -> Array:
	var out: Array = []
	if not _net or not "network_world" in view or view.network_world == null or route_road < 0:
		return out
	var lanes: Array = view.network_world.exit_lanes.get(route_road, [])
	if lanes.is_empty():
		return out
	var step_m: float = sim.NET_STEP
	var here: float = sim._road_f(sim.pod)
	var lead := exit_lead(speed)
	for lane in lanes:
		if int(lane[5]) < 0:
			continue      # (the lane's run on along the exit itself)
		var mouth := int(lane[4])
		var ahead := (float(mouth) - here) * route_dir * step_m
		var join := int(lane[2]) != route_dir
		if ahead <= 0.0 or ahead > (JOIN_LOOK if join else lead):
			continue
		var mid := float(lane[3])
		out.append({"key": "%d:%d:%d" % [route_road, mouth, int(lane[5])], "join": join, "road": route_road, "mouth": mouth, "ahead": ahead,
			"side": (1.0 if mid >= 0.0 else -1.0) * route_dir, "mid": mid, "to": int(lane[5])})
	out.sort_custom(func(a, b): return float(a.ahead) < float(b.ahead))
	return out


func _chevrons_frame(speed: float, shown: bool, strength: float) -> void:
	if not shown or not _net:
		chevrons.visible = false
		if not exits.is_empty():
			exits.clear()
			chev_laid.clear()
			chevron_count = 0
		return
	if _tick % 12 == 0:
		var ahead := exits_ahead(speed)
		# the two nearest exits (an interchange's pair) and, while the road is not busy, the nearest join
		var want: Array = []
		var taken := 0
		var joined := false
		for e in ahead:
			if bool(e.join):
				if not joined and not thinned:
					joined = true
					want.append(e)
			elif taken < 2:
				taken += 1
				want.append(e)
		var same := want.size() == exits.size()
		for k in want.size():
			same = same and k < exits.size() and String(want[k].key) == String(exits[k].key)
		if not same:
			_lay_chevrons(want, speed)
	chevrons.position = Vector3(_chev_ax - float(view.org_x), 0.0, -(_chev_ay - float(view.org_y)))
	chevrons.visible = chevron_count > 0
	chev_mat.set_shader_parameter("clock", _clock)
	chev_mat.set_shader_parameter("fade_in", near_at(speed))
	chev_mat.set_shader_parameter("thin", Vector2(maxf(CHEV_THIN.x, speed * CHEV_THIN_S.x), maxf(CHEV_THIN.y, speed * CHEV_THIN_S.y)))
	chev_mat.set_shader_parameter("gain", strength)


## The chevrons laid for these exits and joins: those already laid keep theirs (when they were laid, from where,
## and the speed they were laid for).
func _lay_chevrons(want: Array, speed: float) -> void:
	var born := {}
	for e in exits:
		born[String(e.key)] = e
	var mm := chevrons.multimesh
	_chev_ax = float(view.org_x)
	_chev_ay = float(view.org_y)
	var step_m: float = sim.NET_STEP
	chev_laid.clear()
	var k := 0
	for e in want:
		var was = born.get(String(e.key))
		e["born"] = float(was.born) if was != null else _clock
		# the nearest it began to her, in samples from the mouth: kept as it was, so a chevron once laid stays laid
		e["from"] = int(was.from) if was != null else maxi(0, int((float(e.ahead) - speed * EXIT_CLEAR_S) / step_m))
		e["v"] = float(was.v) if was != null else maxf(speed, 1.0)      # its seconds are seconds at this speed
		var v: float = e.v
		var join: bool = e.join
		if (not join and float(e.from) * step_m < v * CHEV_EVERY.x) or (was == null and float(e.ahead) < speed * BEGIN_T):
			continue      # too near to be seen for long enough: not begun
		var R = sim.roads[int(e.road)]
		var mouth := int(e.mouth)
		var mid := float(e.mid)
		var own := chev_own(v)
		var colour := CALM if join else EXIT_GREEN
		colour.a = 0.5 if join else 0.9      # (0.8 when a row lay one over another; one at a time it wants more)
		var rows: Array = []      # [road, sample, m left of its middle, m still to the mouth, its kind, tier, level (how far off it is drawn), its own half size]
		if join:
			for n in range(1, JOIN_COUNT + 1):
				rows.append([int(e.road), mouth + route_dir * n * JOIN_EVERY, mid, -float(n * JOIN_EVERY) * step_m, "join", 0.85, 0 if n == 1 or n == JOIN_COUNT else 1, own])
		else:
			# drawn far to near (nothing tests depth): on along the exit itself, from whichever of its ends is at the mouth ...
			var C = sim.roads[int(e.to)]
			var last := int(C.N) - 1
			var at_start: bool = Vector2(C.px[0] - R.px[mouth], C.py[0] - R.py[mouth]).length_squared() <= Vector2(C.px[last] - R.px[mouth], C.py[last] - R.py[mouth]).length_squared()
			for n in range(CHEV_ON, 0, -1):
				var ci := n * 10 if at_start else last - n * 10
				if ci > 0 and ci < last:
					rows.append([int(e.to), ci, 0.0, -float(n * 10) * step_m, "chevron", 0.85, 0 if n == 1 or n == CHEV_ON else 1, own])
			# ... the gate across the lane at the mouth ...
			rows.append([int(e.road), mouth, mid, 0.0, "gate", 1.0, 0, maxf(GATE_OWN, CHEV_TIER.x * own)])
			# ... and the row: a chevron at each whole second before the mouth, at the speed it is laid for, one at
			# each half between, and over the last CHEV_TIGHT one at each quarter (none nearer another than CHEV_GAP)
			var quarters := 1
			while quarters < 4 and v * CHEV_EVERY.x * quarters < CHEV_GAP:
				quarters *= 2
			var q := 1
			while true:
				var t := float(q) * CHEV_EVERY.x
				var back := roundi(t * v / step_m)
				if back > int(e.from) or k + rows.size() >= MAX_CHEVRONS:
					break
				var whole := q % 4 == 0
				var half := q % 2 == 0
				if q % quarters == 0 and (half or t <= CHEV_TIGHT + 0.001):
					rows.append([int(e.road), mouth - route_dir * back, mid, float(back) * step_m, "chevron",
						CHEV_TIER.x if whole else (CHEV_TIER.y if half else CHEV_TIER.z), 0 if whole else (1 if half else 2), own])
				q += 1
		# the way the lane leaves, across the parent road at the mouth: every chevron of the row points it
		var out_way := Vector3(R.nx[mouth], 0.0, -R.ny[mouth]) * (1.0 if mid >= 0.0 else -1.0) * (-1.0 if join else 1.0)
		for row in rows:
			var road: int = row[0]
			var i: int = row[1]
			if k >= MAX_CHEVRONS or i < 0 or i > int(sim.roads[road].N) - 1:
				continue
			var gate: bool = row[4] == "gate"
			var tier: float = row[5]
			var Q = sim.roads[road]
			var x: float = Q.px[i] + Q.nx[i] * float(row[2])
			var y: float = Q.py[i] + Q.ny[i] * float(row[2])
			var stands := Transform3D(Basis(out_way * tier, Vector3.UP * tier, out_way.cross(Vector3.UP) * tier), Vector3(x - _chev_ax, float(sim.surface_at(x, y, i, road).x), -(y - _chev_ay)))
			var tinted := colour
			if gate:
				tinted.a = 1.0
			mm.set_instance_transform(k, stands)
			mm.set_instance_color(k, tinted)
			var custom := Color(float(row[3]), float(e.born), float(row[6]), -float(row[7]) if gate else float(row[7]))
			mm.set_instance_custom_data(k, custom)
			chev_laid.append([String(e.key), stands, float(row[3]), String(row[4]), tier, float(row[7]), custom])
			k += 1
	mm.visible_instance_count = k
	chevron_count = k
	exits = want


# ---------------------------------------------------------------- the log

## A line a second while it is shown, from what the frame already has (see the header).
func _tac_frame(dt: float, speed: float) -> void:
	_tac_t += dt
	if _tac_t < 1.0:
		return
	_tac_t = fmod(_tac_t, 1.0)
	var nearest := INF
	for mark: Mark in marks.values():
		if mark.to > 0.0:
			nearest = minf(nearest, mark.seconds)
	var to_exit := INF
	if not exits.is_empty() and speed > 1.0 and _net and int(sim.pod.path) == route_road:
		var here: float = sim._road_f(sim.pod)
		for e in exits:
			if not bool(e.join):
				var ahead := (float(e.mouth) - here) * route_dir * float(sim.NET_STEP)
				if ahead > 0.0:
					to_exit = minf(to_exit, ahead / speed)
	last_tac = "TAC: rails %.2f %s | vehicles %d nearest %s | exit %s" % [number_load, heat(number_load), line_count,
		"-" if nearest == INF else "%.1f" % nearest, "-" if to_exit == INF else "%.1f" % to_exit]
	tac_lines += 1
	print(last_tac)


# ---------------------------------------------------------------- the speed

func _number_frame(dt: float, speed: float, shown: bool, strength: float, flow: Transform3D) -> void:
	number.visible = shown
	if not shown:
		return
	var rise := NUMBER_AHEAD * tan(deg_to_rad(NUMBER_ELEVATION))
	number.transform = Transform3D(flow.basis, flow * Vector3(0.0, rise, -NUMBER_AHEAD))
	_number_t -= dt
	if _number_t <= 0.0:
		_number_t = NUMBER_EVERY
		var mph := roundi(speed * MPH / float(NUMBER_STEP)) * NUMBER_STEP
		var words := Pilot._commas(mph)
		if number.text != words:
			number.text = words
		number_load = worst_load(speed, NUMBER_LOOK_S) if rails.visible else 0.0
	var colour := tint(number_load)
	colour.a = strength
	if not colour.is_equal_approx(_number_tint):      # (a Label3D is made again each time its colour is set: only when it changes)
		_number_tint = colour
		number.modulate = colour
		number.outline_modulate = Color(0.0, 0.03, 0.05, 0.8 * strength)
