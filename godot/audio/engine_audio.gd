## EngineAudio: one voice per pod engine, built from the piano-baked loops in res://audio/engines
## (tools/engine_bake.py). Each voice is two stages. The first is the piston pair: a big, bassy
## cross-plane V8 that carries the low end with a V12 held well back behind it, over a roar that
## opens up with the spool. The second is the turbines: a whine that rides the spool. The
## afterburner and ramjet add a burner rumble on top.
## The turbines are off from a standstill. They light when the craft reaches turbine_mph[0]
## (the cluster's TURBINES lamp comes on with them: turbines_at()), wind up to pitch, come all
## the way in by turbine_mph[1], and shut down under turbine_off_mph.
## The V8's temper is whatever of that stage is not in yet. On pistons alone it leads, behind
## a fixed chest EQ and a low muffler (its weight sits at 80-350 Hz, which a headset's speakers
## can play back), and snarls on a lever stab. As the turbines come in it steps down and darkens
## and the V12 comes up to full, so at speed the craft sounds precise. (Its first angry version
## missed, banged and dropped beats live; in the headset that was crackle: Luke, 2026-11-19.)
## Every layer is one master performance played at the engine's speed (pitch = rpm / rate_at),
## so a ramp is one continuous signal. (Per-RPM bands crossfaded into each other "stepped
## through selected tones": every band had its own timbre.) Pitching up to 15x would alias, so
## each master comes as anti-alias levels, sample-aligned copies an octave of pitch apart, and
## crossfading them only fades the top octave. The muffler is a fixed low-pass per layer and the
## roar's low-pass follows the spool, so neither moves with pitch. The left engine pans left and
## the right engine pans right, so a lever split or a dead engine is something you hear.
## The second engine is a big-bang four that lights once the craft passes second_on_mph: each
## side cranks and coughs, catches with a bang (left first, right a beat later), runs on its
## lever behind a fixed throat EQ, and backfires and winds down below second_off_mph. Its rpm
## also lifts with speed above that, so it winds up as you accelerate on a steady lever. Sound
## only for now: it adds no thrust.
## Under it all, the bass rotor: the first engine's low end, wound up by airspeed like a big
## turbine. A ~28 Hz rumble at a standstill climbs three octaves by second_on_mph behind a
## low-pass that opens with it, swells with each side's lever, and steps back for the second
## engine once that side is running.
## Polish: the right engine runs a hair off the left (wandering), so equal levers beat slowly
## like twin engines that never quite sync. Lifting off at high revs spits pops and crackle
## for a moment. The spool is a spring: a lever stab revs up in ~0.15 s, flares ~11% past the
## lever and barks (+3 dB for a moment); lifting settles clean, with no undershoot.
## With a gearbox, each higher gear has a higher reference note and a slower rise. Fifth
## continues beyond that note with speed. Only upward spool speed is limited: lifts and
## upshifts still drop the note on the same spring.
## flat (tests) switches all three off: it isolates the crossfader.
## The ramjet has a voice of its own (Luke, 2026-11-22: "the ram jet needs its own sound signifier. First gut
## is saying an actual rocket engine - just a low screaming roar"; and when he had flown its first cut, "I
## like the ramjet sound, but I feel like it's a few octaves too high. It's correct on the ripping/shredding
## sound", with a launch's raw sound for what he meant; and of that second cut, on headphones, "It sounds
## better, but it could be deeper still"): recordings of real rocket engines, baked by
## tools/ramjet_bake.py into res://audio/ramjet. Two loops an engine: the roar (the Space Shuttle's stack
## climbing away, run 1.65 times slower: half its energy under 55 Hz), which carries the voice, and 6 dB
## under it the tear (a shuttle main engine's crackle from NASA's test stand run four octaves down: 45 to
## 300 Hz, most of what a headset's own speakers can play of the voice). In this third cut the voice has
## the profile of the launch he pointed at: at 7,000 mph half its energy lies under 64 Hz and 90% under
## 310 Hz (the launch: 70 and 284), and it tears as hard by the same measure.
## They sound only while the sim is on the ramjet (armed, the burner's gate through) and that engine is
## alight. It catches: a shot (the shuttle's ignition thump, the test engine's crackle) and the loops
## straight in, a few dB over where they settle. Then it follows the speed (louder, the tear more than the
## roar, and both played faster) and that engine's thrust, and each stage of the boost pushes it harder.
## Disarmed, or the gate left, it dies in a tenth of a second with its note falling, under a shot of the
## test engine's cut-off running down. The voice lives where the pistons, the second engine and the noise
## beds live, so under a lit ramjet those step back to give it room (TUNE.ram_duck): the V8, the second
## engine, the turbines' roar and the burner's rumble. The turbines' whine and the V12, which carry the
## gear's note higher up, play on as they did. Unlit, its loops are paused: nothing of it is mixed.
##   add_child(audio); audio.setup(sim)    once, inside the tree
##   audio.update(inp, delta)              every frame, after the sim steps
class_name EngineAudio
extends Node

const PilotCraft := preload("res://sim/pilot_craft.gd")
const FleetPitchGlide := preload("res://audio/fleet_pitch_glide.gd")
# All voices with a sustained note must move together, including the quiet V12
# under the main drive and the second bank that takes over at speed.
const FLEET_GLIDE_LAYERS := ["v8", "v12", "turbine", "second", "rotor"]
const OVERDRIVE_LAYERS := ["v8", "v12", "second", "turbine"]
const FLEET_DIR := "res://audio/fleet/%s/"
const DIR := "res://audio/engines/"
const RAM_DIR := "res://audio/ramjet/"   # the ramjet's voice has its own bank and manifest (tools/ramjet_bake.py)
const LAYERS := ["v8", "v12", "turbine", "roar", "burner", "second", "rotor", "ramjet", "ramtear"]
const RAM_LAYERS := ["ramjet", "ramtear"]   # the ramjet's loops: its roar, its tear
const OWN_LEVEL := ["second", "rotor", "ramjet", "ramtear"]   # layers that carry their own level (not level_db's)
const FILTERED := ["v8", "v12", "roar", "second", "rotor"]   # layers with their own low-pass bus under each engine
const SECOND_STATES := ["off", "wait", "crank", "run", "stop"]

## Everything that shapes the sound. Spool s: -0.33 stopped, 0 idle, 1 full lever; the
## afterburner and ramjet push past 1. Mix curves are [s, gain] knots, piecewise linear.
const TUNE := {
	"windmill": 1.6,                 # spool time constant winding down from a flameout, s
	"relight": 0.8,                  # spool-up time constant while still below idle (reignite)
	# The spool is a spring: [rising, falling]. Rising is snappy and flares ~11% past the lever
	# (90% of a stab in 0.14 s); falling is critically damped, so a lift settles clean.
	"rev_w": [16.0, 7.0], "rev_z": [0.65, 1.0],
	# Audio only: progressively higher reference notes and longer wind-ups in gears 1-5.
	# Fifth accepts an uncapped gearSpool target. Inputs without gearIndex keep the original
	# spring. Boost adds above the gear's current rev target.
	"gear_spool": [0.60, 0.70, 0.80, 0.90, 1.0],
	"gear_rise": [0.55, 0.38, 0.27, 0.19, 0.13],   # maximum positive spool change per second
	"bark_db": 3.0, "bark_s": 0.15,  # a quick stab barks: up to +3 dB, gone in 0.15 s
	"crank": 0.3,                    # pistons bottom out at this fraction of idle RPM
	"burner_spool": 0.15, "ramjet_spool": 0.3, "boost_spool": 0.1,
	# The V8 turns slower than it did (850-7,600): the same lever is a lower note, firing at 47 Hz
	# at idle and 373 Hz flat out.
	"v8_rpm": [700.0, 5600.0], "v12_rpm": [1100.0, 11800.0], "turbine_n": [0.25, 1.0],
	# The V8 holds its level through the rev. Over 1 at idle: the fixed high-pass takes the
	# infrasound the loop was levelled with, and the idle came out 3 dB down. The V12's curve is
	# its full, precise self; while the V8 is angry it plays at angry_v12 of this.
	# (3 dB up on what it was, 1.2 / 1.3 / 1.3 / 1.25: Luke, after the twelfth flight, "the rumbly v8 sound
	# mix should be louder".)
	"mix_v8": [[0.0, 1.7], [0.35, 1.84], [0.8, 1.84], [1.3, 1.77]],
	"mix_v12": [[0.0, 0.12], [0.3, 0.45], [0.7, 0.95], [1.3, 1.0]],
	# The second stage: the turbines light at turbine_mph[0], are all the way in by turbine_mph[1] and
	# shut down under turbine_off_mph. (It was 2,000 to 3,000 mph, off under 1,700: Luke's "maybe the
	# turbine turns on at 2-3k also". After the twelfth flight: the rumbly V8 mix should "persist to 4500
	# mph before fading out to the turbines". The craft tops out a little over 5,000 on full levers, so
	# the stage is all in by 5,300. The cluster's TURBINES lamp lights by the same rule, so it moved too.)
	"turbine_mph": [4500.0, 5300.0], "turbine_off_mph": 4200.0,
	# As the turbines engage the pistons shift: their note drops as on an upshift, then climbs with the
	# speed until they have faded out under the turbines (Luke, hearing the mix swept against speed: "it
	# should shift when turbines are engaged, then continue to pitch up until it fades out, instead of
	# just staying at a constant pitch"). The note against its revs: turbine_shift as they light,
	# turbine_climb by turbine_mph[1]; the shift itself takes turbine_shift_s. Back to 1 when they stop.
	"turbine_shift": 0.76, "turbine_climb": 1.22, "turbine_shift_s": 0.1,
	"turbine_light": 0.4,            # this much of the stage is in as soon as they light; the rest comes with speed
	"turbine_tau": [0.9, 1.6],       # the stage coming in, going out: time constants, s
	"turbine_start": 0.4,            # the whine starts this far down its pitch
	"turbine_wind": [0.6, 1.0],      # and winds up, down: time constants, s
	"turbine_full": 1.2,             # the whine's level with the stage all in (x mix_turbine)
	"roar_piston": 0.45,             # the roar on pistons alone (x its level with the turbines in)
	# The V8's temper is whatever of the stage is not in yet.
	"calm_v8": 0.16,                 # the V8's level once it has calmed down (x mix_v8; 0.28 before its chest EQ, which lifted it level with the V12)
	"calm_v8_hz": 1500.0,            # and its muffler then (muffler_hz.v8 is the angry one)
	"angry_v12": 0.4,                # the V12's level while the V8 is angry (x mix_v12)
	"snarl_db": 2.5,                 # a lever stab barks this much harder on the angry V8
	"mix_turbine": [[-0.33, 0.0], [0.0, 0.3], [0.6, 0.5], [1.0, 0.7], [1.3, 0.9]],
	"burner_gain": 0.8, "burner_fade": 0.25,
	"muffler_hz": {"v8": 1800.0, "v12": 7000.0, "second": 1200.0},   # fixed: the exhaust colour doesn't ride the pitch
	# The V8's master keeps its low orders (its own high-pass is at 5 Hz, so they survive being
	# pitched up): this fixed one takes the idle's infrasound back out.
	"v8_hp_hz": 28.0,
	# The V8's chest: a fixed EQ6 at 32/100/320/1k/3.2k/10k Hz. It does not ride the pitch, so the
	# body stays put through the rev the way an exhaust's own resonances do.
	"v8_eq_db": [-2.0, 7.0, 5.0, -3.0, -10.0, -18.0],
	"roar_hz": [250.0, 3450.0],      # roar low-pass, turbine spool 0 -> 1
	"roar_gain": [0.35, 1.0],        # roar level relative to the whine, spool 0 -> 1
	"level_db": [-15.0, -8.0],       # whole voice, idle -> full lever
	"lp_hz": [700.0, 16000.0],       # bus low-pass, off-load (lifting) -> on-load (pulling)
	"pan": 0.6,
	"cough_s": 0.7,                  # after a reignite, combustion catches in fits for this long
	# The start-up's staged start (Luke, after the seventeenth flight: "a staged supercar style start - Brief
	# pre-starter whine, then starter engage"; the sounds themselves are audio/startup_audio.gd's, laid out by
	# tools/startup_audio_bake.py on the same clock, its PRIME_S). For start_prime_s after its start is asked
	# for an engine is on its electrics and does not turn. Then its starter spins it clean: no fits, it is not
	# an old V8 that might not go. At the catch it comes straight up through idle (start_catch, a time
	# constant) and flares start_flare of the way to full lever, back at idle start_flare_s later.
	"start_prime_s": 0.80, "start_catch": 0.09, "start_flare": 0.24, "start_flare_s": 1.1,
	# The second engine (sound only): lights above second_on_mph, dies below second_off_mph.
	"second_on_mph": 1500.0, "second_off_mph": 1300.0,
	"second_rpm": [600.0, 3800.0],   # low and slow: ~63 Hz doublets at full lever, the lope at half that
	"second_stagger": 0.3,           # the right side lights this long after the left
	"second_crank_s": 0.7,           # cranking and coughing before it catches
	"second_wind": 1.2,              # winding down once it stops, s (it revs on the same spring)
	"second_level_db": [-15.0, -7.0],   # its own level, idle -> full lever: leads the mix by ~6 dB when lit
	"second_eq_db": [6.0, 8.0, 2.0, -2.0, -8.0, -14.0],   # EQ6 at 32/100/320/1k/3.2k/10k Hz: chest and throat
	"bang_db": [-2.0, -8.0],         # catching, backfiring on the way down
	"second_lift": 0.7, "second_lift_mph": 4500.0,   # rpm x (1 + lift) from second_on_mph to this
	# The bass rotor: pitch 2^(rotor_oct * (speed / second_on_mph)^rotor_curve).
	"rotor_oct": 3.0,                # octaves it climbs from a standstill to second_on_mph
	"rotor_curve": 0.8,              # under 1: it climbs quicker off the line
	"rotor_tau": 0.3,                # follows airspeed with this lag, s
	"rotor_lever_pitch": 0.06,       # each side's lever lifts its rotor this much more
	"rotor_lp_hz": [160.0, 3000.0],  # its low-pass, standstill -> second_on_mph: boomy, then singing
	"rotor_db": [-5.0, -11.0],       # standstill -> second_on_mph: bassiest down low
	"rotor_lever": [0.4, 1.0],       # level scale, lever 0 -> 1
	"rotor_handover_db": -10.0,      # once that side's second engine is running
	# Twin engines never quite sync: the right one runs this much fast, wandering, so equal
	# levers beat slowly (pistons, second engine, rotor; the 2.4 kHz whine would just go rough).
	"twin_detune": 0.0035, "twin_wander": [0.0015, 17.0],   # [amplitude, period s]
	# Overrun: lifting off from above pop_rpm spool, pop_lift or more over the lever, spits
	# pops and crackle for pop_s, tapering from pop_rate per second.
	"pop_rpm": 0.5, "pop_lift": 0.2, "pop_s": 1.2, "pop_rate": 14.0,
	"pop_db": -9.0,                  # first engine; the randomizer varies each pop by 8 dB
	"pop2_pitch": 0.65, "pop2_db": -7.0,   # the second engine's pops, deeper, through its throat
	# The ramjet's voice (this file's header). Its loops are baked at -18 dB rms, as the others are; these are
	# their levels, set by measuring the game's recorded mix with and without them at 3,000, 5,000 and 7,000 mph
	# (tests/record_ramjet.gd; the figures are in godot/audio/ramjet/CREDITS.md), not by ear. In its second cut
	# (lowered) the mix's rms is held where Luke flew the first: the voice is 2.5 to 4 dB up on the first cut's,
	# most of that under 90 Hz, and the layers in its band are stepped back for it (ram_duck). In its third
	# (deep) the roar carries it and the tear sits 6 to 8 dB under the roar; the voice's own rms is held where
	# the second cut's was (-12.6 / -12.5 / -12.0 dB at 3,000 / 5,000 / 7,000 mph), and what it has over 90 Hz
	# (-17.8 / -17.5 / -16.6 dB) is 2.1 to 2.8 dB under the second cut's: the weight went under 90 Hz.
	"ram_mph": [2500.0, 8000.0],     # its level, brightness and note run with the speed over this (fourth gear has no top speed)
	"ram_body_db": [0.6, 1.0],       # the roar, at ram_mph[0] -> ram_mph[1]
	"ram_tear_db": [-7.4, -5.0],     # the tear: it comes up more than the roar does, so the voice brightens
	"ram_slow_db": -6.0,             # both, at a standstill (a ramjet lit on the line is a weak thing), gone by ram_mph[0]
	"ram_pitch": [0.92, 1.08],       # the roar's speed of playing, ram_mph[0] -> ram_mph[1]
	"ram_tear_pitch": [0.85, 1.2],   # the tear's: the frequency half its energy lies under runs from 70 to 98 Hz
	"ram_tau": [0.04, 0.1],          # it catches, it dies: time constants, s
	"ram_fall": 0.55,                # dying, its note falls to this of where it was
	"ram_kick_db": [3.0, 4.0],       # the light-up: the roar and the tear this much over where they settle ...
	"ram_kick_s": 0.6,               # ... gone with this time constant
	"ram_boost_db": [2.0, 3.5],      # each stage of the boost: the roar, the tear
	# (the voice alone is at the Engines bus's limiter, so a stage harder is heard as pace more than as level)
	"ram_boost_pitch": 0.25,         # ... and the tear played this much faster (the roar by half as much)
	"ram_boost_tau": 0.1,
	"ram_thrust": [0.4, 1.0],        # level scale, this engine's thrust 0 -> the ramjet's full (the tear takes it twice)
	"ram_light_db": 2.0,             # the light-up's shot, over the roar's level at that speed
	"ram_out_db": -5.5,              # the shut-down's shot, against the roar's level as it was (under it: the loops are still falling)
	"ram_shot_max_db": 1.0,          # ... neither played over this (the shots peak at -3 dBFS; the Engines bus limits at -1)
	"ram_relight_s": 0.5,            # a ramjet lit again inside this long of its last light-up gets no second shot
	# Room for it: under a lit ramjet these layers play at this much of their own level (the voice's weight is
	# 40 to 700 Hz, which is theirs: measured alone on the ramjet at 5,000 mph the second engine put -17 dB
	# into 90-180 Hz and the first cut of the voice -22, and at 3,000 mph the V8 -18 into every octave from 45
	# to 700 Hz). The turbines' whine and the V12 sit over 700 Hz and are left alone. Set for the second cut
	# and kept for the third: the deep voice needs no more room than the lowered one took (the mix peaks at
	# -0.3 dBFS with the boost held at 3,000, 5,000 and 7,000 mph, and the whine does not pump under it).
	"ram_duck": {"v8": 0.75, "second": 0.5, "roar": 0.5, "burner": 0.3},
}

var sim
# Relative layer gain and pitch at the shared lever demand. The surveyor leans
# on its rotor, the recovery tractor on the low bank, the racer on its turbine.
const FLEET_VOICES := {
	"orrery": {"rotor": Vector2(1.16, 0.79), "turbine": Vector2(1.15, 0.86), "v8": Vector2(0.63, 0.98)},
	"kiln": {"v8": Vector2(1.12, 0.82), "v12": Vector2(0.84, 0.93), "turbine": Vector2(0.72, 0.96)},
	"vesper": {"v8": Vector2(0.69, 1.06), "v12": Vector2(1.06, 1.12), "turbine": Vector2(1.17, 1.21)},
	# The gunship: a heavy low bank under a hard turbine, its V12 held back.
	"basilisk": {"v8": Vector2(1.08, 0.88), "v12": Vector2(0.78, 0.9), "turbine": Vector2(1.05, 0.92)},
}
var fleet_voice := {}
var _paired_fleet := false
var short_intakes := false
var solo := ""   # "v8", "v12", "turbine" or "burner": hear one layer alone (tests, tuning)
var flat := false   # tests: every gain held at 1 and the low-pass open, so only crossfades move the level
var voices: Array = []
var _bands := {}   # layer -> PackedFloat64Array of baked rpm / spool values
var _streams := {}   # layer -> Array[AudioStreamWAV]
var _rho := {}   # layer -> PackedFloat64Array: correlation of level i with level i + 1
var _rate_at := {}   # layer -> rpm (or spool) the master sounds at on pitch 1, 0 = pitch per band
var _bang: AudioStreamWAV
var _pops: AudioStreamRandomizer
var _ram_light: Array[AudioStreamWAV] = []   # the ramjet's light-up, a take an engine
var _ram_out: Array[AudioStreamWAV] = []     # ... and its shut-down
var _t := 0.0   # seconds of update, for the twin wander
var turbines_on := false   # craft fast enough for the turbines (with hysteresis)
var stage := 0.0   # how far the turbines are in, 0..1
var shift := 1.0   # the pistons' note against their revs: 1 until the turbines engage, then turbine_shift climbing to turbine_climb
var anger := 1.0   # the V8's temper: what is left of the stage
var _wind := 0.0   # the whine's wind-up, 0..1
var second_on := false   # craft fast enough for the second engine (with hysteresis)
# The start-up (vr/startup_sequence.gd), told by the cockpit. An engine that is `off` is silent
# and winds down as a flamed-out one does; one whose start has been asked for (`crank`) waits out
# the pre-starter whine, then turns over at cranking speed without firing; taken out of `off` it
# catches clean and flares (TUNE.start_*: the staged start). `test_stage`
# is the run-up's turbine test: that much of the second stage is in, whatever the airspeed.
var off: Array[bool] = [false, false]
var crank: Array[bool] = [false, false]
var test_stage := 0.0


func setup(craft_sim) -> void:
	sim = craft_sim
	short_intakes = sim.P.get("vehicle", "") == "shrike"
	fleet_voice = FLEET_VOICES.get(sim.P.get("vehicle", ""), {})
	_load_streams()
	# Engines and Wind each limit their own bus to -1 dB, but their sum lands on Master unlimited:
	# with both peaking together it could clip (engines + wind measured -0.05 dBFS on Master).
	# A last-resort limiter there touches only true overs.
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		has_limiter = has_limiter or AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter
	if not has_limiter:
		var safety := AudioEffectHardLimiter.new()
		safety.ceiling_db = -0.3
		AudioServer.add_bus_effect(0, safety)
	var engines_bus := _bus("Engines", "Master")
	_paired_fleet = PilotCraft.known(sim.P.get("vehicle", PilotCraft.STANDARD)) != PilotCraft.STANDARD
	var tonal_starts := {}
	if AudioServer.get_bus_effect_count(engines_bus) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(engines_bus, lim)
	for k in 2:
		var name: String = ["EngineL", "EngineR"][k]
		var bus := _bus(name, "Engines")
		if AudioServer.get_bus_effect_count(bus) == 0:
			AudioServer.add_bus_effect(bus, AudioEffectLowPassFilter.new())
			var pan := AudioEffectPanner.new()
			pan.pan = -TUNE.pan if k == 0 else TUNE.pan
			AudioServer.add_bus_effect(bus, pan)
		var subs := {}
		for layer in FILTERED:
			var sub := _bus("%s_%s" % [name, layer], name)
			if AudioServer.get_bus_effect_count(sub) == 0:
				AudioServer.add_bus_effect(sub, AudioEffectLowPassFilter.new())
			var lp := AudioServer.get_bus_effect(sub, 0) as AudioEffectLowPassFilter
			lp.cutoff_hz = TUNE.muffler_hz.get(layer, TUNE.roar_hz[0])
			if layer == "v8" and AudioServer.get_bus_effect_count(sub) == 1:
				var hp := AudioEffectHighPassFilter.new()
				hp.cutoff_hz = TUNE.v8_hp_hz
				AudioServer.add_bus_effect(sub, hp)
			if layer == "v8" and AudioServer.get_bus_effect_count(sub) == 2:
				var chest := AudioEffectEQ6.new()
				for band in 6:
					chest.set_band_gain_db(band, TUNE.v8_eq_db[band])
				AudioServer.add_bus_effect(sub, chest)
			if layer == "second" and AudioServer.get_bus_effect_count(sub) == 1:
				var eq := AudioEffectEQ6.new()
				for band in 6:
					eq.set_band_gain_db(band, TUNE.second_eq_db[band])
				AudioServer.add_bus_effect(sub, eq)
			subs[layer] = sub
		var bang := AudioStreamPlayer.new()
		bang.stream = _bang
		bang.bus = "%s_second" % name
		add_child(bang)
		# pops skip the load low-pass (which closes on a lift): their own bus, same pan
		var pop_bus := _bus("%s_pops" % name, "Engines")
		if AudioServer.get_bus_effect_count(pop_bus) == 0:
			var pp := AudioEffectPanner.new()
			pp.pan = -TUNE.pan if k == 0 else TUNE.pan
			AudioServer.add_bus_effect(pop_bus, pp)
		var pops := AudioStreamPlayer.new()
		pops.stream = _pops
		pops.bus = "%s_pops" % name
		pops.max_polyphony = 6
		pops.volume_db = TUNE.pop_db
		add_child(pops)
		var pops2 := AudioStreamPlayer.new()
		pops2.stream = _pops
		pops2.bus = "%s_second" % name
		pops2.max_polyphony = 6
		pops2.pitch_scale = TUNE.pop2_pitch
		pops2.volume_db = TUNE.pop2_db
		add_child(pops2)
		# the ramjet's light-up and shut-down: one shot at a time an engine, panned as it is, clear of the load
		# low-pass (which closes as the ramjet goes out, and would swallow its fall)
		var ram_shots := AudioStreamPlayer.new()
		ram_shots.bus = "%s_pops" % name
		add_child(ram_shots)
		var v := {"bus": bus, "subs": subs, "spool": 0.0, "comb": 1.0, "fire": 1.0, "load": 0.5, "burn": 0.0,
			"was_out": false, "cough_t": 0.0, "cough_k": 1.0, "cough_next": 0.0, "players": {}, "glides": {}, "at": {},
			"crank_t": 0.0, "was_held": false, "flare_t": 0.0,      # the start-up: seconds on the starter's button, and its catch's flare
			"bang": bang, "sec": {"state": "off", "t": 0.0, "spool": -0.33, "vel": 0.0, "fire": 0.0, "cough_k": 0.0, "cough_next": 0.0},
			"rotor_mph": 0.0, "rotor_p": 1.0, "sec_run": 0.0,
			"spool_v": 0.0, "lever_prev": 0.0, "bark": 0.0, "alive": 1.0,
			"pops": pops, "pops2": pops2, "pop_t": 0.0, "pop_k": 0.0, "pop2_t": 0.0, "pop2_k": 0.0, "pops_n": 0,
			# the ramjet's voice: how far it is in, lit or not, the light-up's kick, the boost's stages as heard,
			# this engine's thrust of the ramjet's full, seconds since it last lit, its shots' player, the roar's and the
			# tear's levels (dB), and how often it has lit and been shut down (with its shot)
			"ram": 0.0, "ram_lit": false, "ram_kick": 0.0, "ram_boost": 0.0, "ram_thr": 0.0, "ram_since": 9.0,
			"ram_shots": ram_shots, "ram_db": [-80.0, -80.0], "ram_n": 0, "ram_outs": 0}
		for layer in LAYERS:
			var ps: Array[AudioStreamPlayer] = []
			var start := randf()
			if _paired_fleet and layer in FLEET_GLIDE_LAYERS:
				# Equal lever settings start on the same part of the same take.
				# Textured wind, burner and exhaust beds keep independent offsets.
				if k == 0:
					tonal_starts[layer] = start
				else:
					start = tonal_starts[layer]
			var layer_bus := "%s_%s" % [name, layer] if layer in FILTERED else name
			if _paired_fleet and layer in FLEET_GLIDE_LAYERS and _rate_at[layer] > 0.0:
				var glide := FleetPitchGlide.new()
				glide.bus = layer_bus
				add_child(glide)
				var left: FleetPitchGlide = voices[0].glides.get(layer) if k == 1 else null
				if glide.configure(_streams[layer], start, left):
					v.glides[layer] = glide
					continue
				glide.free()
				push_warning("Fleet pitch glide could not load %s, using native loop players" % layer)
			for i in _streams[layer].size():
				var s: AudioStreamWAV = _streams[layer][i]
				var p := AudioStreamPlayer.new()
				p.stream = s
				p.bus = layer_bus
				p.volume_db = -80.0
				add_child(p)
				# anti-alias levels: all from the same spot, in the same frame, so in lockstep
				p.play((start if _rate_at[layer] > 0.0 else randf()) * s.get_length())
				if layer in RAM_LAYERS:
					p.stream_paused = true   # (until the ramjet lights nothing of it is mixed)
				ps.append(p)
			v.players[layer] = ps
		voices.append(v)
	var loops := 0
	for layer in LAYERS:
		loops += _streams[layer].size()
	print("AUDIO: EngineAudio up, %d voices x %d loops, driver %s at %d Hz" % [voices.size(), loops,
		AudioServer.get_driver_name(), AudioServer.get_mix_rate()])


func _load_streams() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "manifest.json"))
	var ram_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RAM_DIR + "manifest.json"))
	# Load only the selected craft's performances. All banks share the same
	# players, spool control, stereo routing and engine-failure behaviour.
	var craft_id := PilotCraft.known(sim.P.get("vehicle", PilotCraft.STANDARD))
	var fleet_dir := FLEET_DIR % PilotCraft.sound_bank(craft_id)   # (the Basilisk plays the Kiln's bank)
	var fleet_layers := {}
	var shots_dir := DIR
	var shots: Dictionary = manifest.oneshots
	if craft_id != PilotCraft.STANDARD:
		var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fleet_dir + "engine.json"))
		fleet_layers = bank.layers
		shots = bank.oneshots
		shots_dir = fleet_dir
	for layer in LAYERS:
		var ats := PackedFloat64Array()
		var list: Array[AudioStreamWAV] = []
		var rhos := PackedFloat64Array()
		var dir: String = RAM_DIR if layer in RAM_LAYERS else DIR
		var spec: Dictionary = (ram_manifest if layer in RAM_LAYERS else manifest).layers[layer]
		if fleet_layers.has(layer):
			dir = fleet_dir
			spec = fleet_layers[layer]
		for b: Dictionary in spec.bands:
			var w := (ResourceLoader.load(dir + b.file) as AudioStreamWAV).duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = w.data.size() >> 1   # 16-bit mono frames
			list.append(w)
			ats.append(b.at)
			rhos.append(b.get("rho_next", 0.0))
		_streams[layer] = list
		_bands[layer] = ats
		_rho[layer] = rhos
		_rate_at[layer] = float(spec.get("rate_at", 0.0)) if spec.get("sync", false) else 0.0
	_bang = (ResourceLoader.load(shots_dir + shots.bang) as AudioStreamWAV).duplicate() as AudioStreamWAV
	_bang.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_pops = AudioStreamRandomizer.new()
	_pops.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	_pops.random_pitch = 1.15            # each pop up to 15% up or down
	_pops.random_volume_offset_db = 8.0  # and up to 8 dB quieter
	for f: String in shots.pops:
		var w := (ResourceLoader.load(shots_dir + f) as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_pops.add_stream(-1, w)
	for pair: Array in [[ram_manifest.oneshots.light, _ram_light], [ram_manifest.oneshots.out, _ram_out]]:
		for f: String in pair[0]:
			var w := (ResourceLoader.load(RAM_DIR + f) as AudioStreamWAV).duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
			(pair[1] as Array[AudioStreamWAV]).append(w)


## Whether the turbines run at this airspeed, given whether they were running already. The
## cockpit lights its TURBINES lamp from the same rule.
static func turbines_at(mph: float, running: bool) -> bool:
	return mph >= (TUNE.turbine_off_mph if running else TUNE.turbine_mph[0])


## Get or create a bus routed into `send`.
static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


static func _curve(knots: Array, x: float) -> float:
	if x <= knots[0][0]:
		return knots[0][1]
	for i in range(1, knots.size()):
		if x <= knots[i][0]:
			var a: Array = knots[i - 1]
			var b: Array = knots[i]
			return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]))
	return knots[-1][1]


static func _follow(cur: float, target: float, tau: float, dt: float) -> float:
	return target + (cur - target) * exp(-dt / maxf(tau, 1e-4))


## The layer's RPM (or turbine spool) for engine spool s. Below idle (a flameout winding
## down, a reignite catching) the pistons sink toward cranking speed and the turbine to a stop.
func layer_at(layer: String, s: float) -> float:
	match layer:
		"v8", "v12", "second":
			var r: Array = TUNE[layer + "_rpm"]
			if s >= 0.0:
				return lerpf(r[0], r[1], s)
			return r[0] * maxf(TUNE.crank, 1.0 + s / 0.33 * (1.0 - TUNE.crank))
		"roar":
			return 0.85 + 0.25 * clampf(s, 0.0, 1.3)   # a little pitch lift; the low-pass does the rest
		_:
			return maxf(0.02, lerpf(TUNE.turbine_n[0], TUNE.turbine_n[1], s))


func update(inp: Dictionary, delta: float) -> void:
	var dt := minf(delta, 0.1)
	_t += dt
	var gate: float = sim.P.gate
	var boost: float = {"burner": TUNE.burner_spool, "ramjet": TUNE.ramjet_spool}.get(sim.mode, 0.0)
	boost += TUNE.boost_spool * float(sim.boost)      # the held boost, a power-up's surge: the spool pushed past, the burner's rumble under it
	var ceiling := 1.0
	var rise_rate := INF
	var gear := int(inp.get("gearIndex", -1))
	if gear >= 0:
		gear = mini(gear, TUNE.gear_spool.size() - 1)
		ceiling = TUNE.gear_spool[gear]
		rise_rate = TUNE.gear_rise[gear]
	var overdrive := bool(inp.get("gearOverdrive", false)) and gear == TUNE.gear_spool.size() - 1
	var duck := 0.0 if sim.crash_t > 0.0 else 1.0   # crash: the engines go with the picture
	var bodies := [sim.eL, sim.eR]
	var thr := [inp.thrL, inp.thrR]
	# (the speed of the air the craft meets: half its ground speed on the Aurora Line, so there the turbines,
	# the second engine and the rotor come in at twice the speed over the ground)
	var mph: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.23694 / (float(sim.line_speed()) if sim.has_method("line_speed") else 1.0)
	if not second_on and mph >= TUNE.second_on_mph:
		second_on = true
	elif second_on and mph < TUNE.second_off_mph:
		second_on = false
	turbines_on = turbines_at(mph, turbines_on)
	var want := 0.0
	if turbines_on:
		want = lerpf(TUNE.turbine_light, 1.0, smoothstep(TUNE.turbine_mph[0], TUNE.turbine_mph[1], mph))
	want = maxf(want, clampf(test_stage, 0.0, 1.0))   # the run-up's turbine test, on the brake
	var spinning := turbines_on or test_stage > 0.02
	stage = _follow(stage, want, TUNE.turbine_tau[0] if want > stage else TUNE.turbine_tau[1], dt)
	_wind = _follow(_wind, 1.0 if spinning else 0.0, TUNE.turbine_wind[0] if spinning else TUNE.turbine_wind[1], dt)
	# the pistons' shift as the turbines engage at speed (not for the run-up's test on the brake)
	var shifted: float = lerpf(TUNE.turbine_shift, TUNE.turbine_climb, smoothstep(TUNE.turbine_mph[0], TUNE.turbine_mph[1], mph)) if turbines_on else 1.0
	shift = 1.0 if flat else _follow(shift, shifted, TUNE.turbine_shift_s, dt)
	# flat holds everything open (turbines in, temper full): only the crossfader may move anything there
	var turbines := 1.0 if flat else stage
	anger = 1.0 if flat else 1.0 - stage
	for k in 2:
		var v: Dictionary = voices[k]
		var e = bodies[k]
		var lever := minf(thr[k], gate) / gate
		var rev_target: float = float(inp.get("gearSpoolL" if k == 0 else "gearSpoolR", lever)) if overdrive else lever
		if inp.get("repair", false):
			lever = minf(lever, 0.6)
			rev_target = minf(rev_target, 0.6)
		var running_target: float = rev_target * ceiling + boost
		var held: bool = off[k]                      # the start-up: this engine is not running
		var cranking: bool = held and crank[k]       # ... and its start has been asked for
		v.crank_t = v.crank_t + dt if cranking else 0.0
		var turning: bool = cranking and v.crank_t >= TUNE.start_prime_s   # (until then it is on its electrics: the pre-starter whine)
		var out: bool = e.flameout or held
		if v.was_held and not held and not e.flameout:   # the start-up's catch: up through idle at once, and a flare
			v.flare_t = TUNE.start_flare_s
		v.was_held = held
		if v.flare_t > 0.0:
			v.flare_t = maxf(0.0, v.flare_t - dt)
			running_target = maxf(running_target, TUNE.start_flare * minf(1.0, v.flare_t / (0.7 * TUNE.start_flare_s)))
		var target: float = (-0.15 if turning else -0.33) if out else running_target
		if out or v.spool < 0.0:
			# winding down from a flameout, turning over on the starter, or relighting from below idle: no flare
			# (a start-up's catch is the one that does not hang about down there)
			var tau: float = (0.3 if cranking else TUNE.windmill) if out else (TUNE.start_catch if v.flare_t > 0.0 else TUNE.relight)
			v.spool = _follow(v.spool, target, tau, dt)
			v.spool_v = 0.0
		else:
			_rev(v, "spool", "spool_v", target, dt, rise_rate)
		# a quick stab barks; the bark dies away in bark_s
		var stab: float = clampf((lever - v.lever_prev) / maxf(dt, 1e-4) * 0.12, 0.0, 1.0)
		v.lever_prev = lever
		v.bark = maxf(v.bark * exp(-dt / TUNE.bark_s), stab)

		# Combustion: off at a flameout, in fits for a moment after a reignite, and the sim's
		# own sputter (a damaged engine misfiring) chops it on top.
		if v.was_out and not out:
			v.cough_t = 0.0 if v.flare_t > 0.0 else TUNE.cough_s   # (a start-up's catch is clean; a relight in flight still comes in fits)
		v.was_out = out
		if cranking:                 # on its electrics, then on the starter: it turns and does not fire until it catches
			v.cough_k = 0.0          # (it used to fire now and then all the way: an old V8 that might not go)
		elif v.cough_t > 0.0:
			v.cough_t -= dt
			v.cough_next -= dt
			if v.cough_next <= 0.0:
				v.cough_next = randf_range(0.04, 0.12)
				v.cough_k = 0.15 if randf() < 0.5 else 1.0
		else:
			v.cough_k = 1.0
		var fire: float = v.cough_k if cranking else (0.0 if out else v.cough_k)
		v.alive = _follow(v.alive, 0.0 if held else 1.0, 0.25 if held else 0.5, dt)   # everything of it that is not combustion
		v.fire = _follow(v.fire, fire, 0.05 if fire < v.fire else 0.12, dt)
		v.comb = _follow(v.comb, e.sputter, 0.02, dt)
		var burning: float = v.fire * v.comb

		# Load: pulling (lever ahead of spool) opens the low-pass, lifting closes it.
		var load := clampf(0.35 + 0.65 * lever + 3.0 * (target - v.spool), 0.0, 1.0)
		v.load = _follow(v.load, load, 0.12, dt)
		var lp: float = TUNE.lp_hz[1] if flat else TUNE.lp_hz[0] * pow(TUNE.lp_hz[1] / TUNE.lp_hz[0], v.load)
		AudioServer.get_bus_effect(v.bus, 0).cutoff_hz = lp

		var s: float = v.spool
		var level := db_to_linear(TUNE.level_db[1] if flat else lerpf(TUNE.level_db[0], TUNE.level_db[1], clampf(s, 0.0, 1.0))) * duck
		var bark := 1.0 if flat else db_to_linear(TUNE.bark_db * v.bark)
		# Overrun: lifting off at high revs spits pops and crackle for a moment.
		var over: float = v.spool - target
		if not flat and not out and v.spool > TUNE.pop_rpm and over > TUNE.pop_lift and v.pop_t <= 0.0:
			v.pop_t = TUNE.pop_s
			v.pop_k = clampf(over / 0.5, 0.3, 1.0)
		_pop(v, "pops", "pop_t", "pop_k", dt, duck)
		v.burn = _follow(v.burn, 1.0 if boost > 0.0 and not out else 0.0, TUNE.burner_fade, dt)
		# The ramjet's voice: lit while the sim is on the ramjet and this engine is alight.
		var ram_on: bool = sim.mode == "ramjet" and not out and duck > 0.0
		var ram_q := clampf((mph - TUNE.ram_mph[0]) / (TUNE.ram_mph[1] - TUNE.ram_mph[0]), 0.0, 1.0)
		var ram_base: float = lerpf(TUNE.ram_body_db[0], TUNE.ram_body_db[1], ram_q) + lerpf(TUNE.ram_slow_db, 0.0, smoothstep(0.0, TUNE.ram_mph[0], mph))
		var ram_thrust: float = clampf(float(e.thrust) / (float(sim.P.ramjetMult) * pow(float(sim.P.boostMult), float(sim.boost))), 0.0, 1.0)
		v.ram_since += dt
		if ram_on != v.ram_lit:
			v.ram_lit = ram_on
			if ram_on:               # it catches: the loops straight in and over their mark, and (unless it only blinked) the shot
				v.ram_kick = 1.0
				v.ram_thr = ram_thrust
				v.ram_n += 1
				if v.ram_since >= TUNE.ram_relight_s:
					_ram_shot(v, k, _ram_light, ram_base + TUNE.ram_light_db)
				v.ram_since = 0.0
			elif duck > 0.0:         # it dies: the shot, as loud as what it leaves (not into a crash: the engines go with the picture)
				v.ram_outs += 1
				_ram_shot(v, k, _ram_out, ram_base + TUNE.ram_boost_db[0] * v.ram_boost + TUNE.ram_out_db + linear_to_db(maxf(v.ram * lerpf(TUNE.ram_thrust[0], TUNE.ram_thrust[1], v.ram_thr), 0.05)))
		v.ram = _follow(v.ram, 1.0 if ram_on else 0.0, TUNE.ram_tau[0] if ram_on else TUNE.ram_tau[1], dt)
		v.ram_kick *= exp(-dt / TUNE.ram_kick_s)
		v.ram_boost = _follow(v.ram_boost, float(sim.boost) if ram_on else 0.0, TUNE.ram_boost_tau, dt)
		if ram_on:                   # (as it dies it keeps the thrust it had: the sim's is the burner's by then)
			v.ram_thr = _follow(v.ram_thr, ram_thrust, 0.06, dt)
		var ram_k: float = lerpf(TUNE.ram_thrust[0], TUNE.ram_thrust[1], v.ram_thr)
		var ram_g: float = v.ram * ram_k * v.alive * duck
		var ram_fall: float = 1.0 if ram_on else lerpf(TUNE.ram_fall, 1.0, v.ram)
		v.ram_db = [ram_base + TUNE.ram_boost_db[0] * v.ram_boost + TUNE.ram_kick_db[0] * v.ram_kick,
			ram_base - lerpf(TUNE.ram_body_db[0], TUNE.ram_body_db[1], ram_q) + lerpf(TUNE.ram_tear_db[0], TUNE.ram_tear_db[1], ram_q)
				+ TUNE.ram_boost_db[1] * v.ram_boost + TUNE.ram_kick_db[1] * v.ram_kick]
		var n_spool := clampf(layer_at("turbine", s), 0.0, 1.0)
		var turb := _curve(TUNE.mix_turbine, s)
		var snarl := 1.0 if flat else db_to_linear(TUNE.snarl_db * anger * v.bark)
		(AudioServer.get_bus_effect(v.subs.v8, 0) as AudioEffectLowPassFilter).cutoff_hz = lerpf(
			TUNE.calm_v8_hz, TUNE.muffler_hz.v8, anger)
		var gains := {
			"v8": _curve(TUNE.mix_v8, s) * lerpf(TUNE.calm_v8, 1.0, anger) * burning * bark * snarl,
			"v12": _curve(TUNE.mix_v12, s) * lerpf(1.0, TUNE.angry_v12, anger) * burning * bark,
			"turbine": turb * turbines * lerpf(1.0, TUNE.turbine_full, turbines) * (0.55 + 0.45 * burning) * v.alive,
			"roar": turb * lerpf(TUNE.roar_piston, 1.0, turbines) * lerpf(TUNE.roar_gain[0], TUNE.roar_gain[1], n_spool)
				* (0.4 + 0.6 * burning) * v.alive,
			"burner": TUNE.burner_gain * v.burn * burning,
			"ramjet": db_to_linear(v.ram_db[0]) * ram_g,
			"ramtear": db_to_linear(v.ram_db[1]) * ram_g * ram_k,
		}
		var sec_gain := _second(v, k, running_target, dt, duck, rise_rate)
		gains["second"] = sec_gain * bark * v.alive
		gains["rotor"] = _rotor(v, lever, mph, dt, duck) * v.alive
		for layer: String in TUNE.ram_duck:      # under a lit ramjet the layers in its band step back and give it room
			gains[layer] *= lerpf(1.0, TUNE.ram_duck[layer], v.ram)
		if short_intakes:
			# The smaller compressor comes through as the lever opens. Keeping the
			# low bank under it leaves the relight, brake and overrun cues audible.
			gains.v8 *= 0.64
			gains.v12 *= 1.10
			gains.rotor *= lerpf(0.94, 1.22, lever)
			gains.roar *= 0.86
		if flat:
			gains = {"v8": burning, "v12": burning, "turbine": 1.0, "roar": 1.0, "burner": v.burn * burning,
				"second": v.sec.fire, "rotor": 1.0, "ramjet": v.ram, "ramtear": v.ram}
		var roar_lp := AudioServer.get_bus_effect(v.subs.roar, 0) as AudioEffectLowPassFilter
		roar_lp.cutoff_hz = TUNE.roar_hz[1] if flat else lerpf(TUNE.roar_hz[0], TUNE.roar_hz[1], n_spool)
		var lift: float = 1.0 + TUNE.second_lift * clampf((mph - TUNE.second_on_mph)
			/ (TUNE.second_lift_mph - TUNE.second_on_mph), 0.0, 1.0)
		var twin := 1.0
		if k == 1 and not flat and not _paired_fleet:
			twin += TUNE.twin_detune + TUNE.twin_wander[0] * sin(TAU * _t / TUNE.twin_wander[1])
		for layer in LAYERS:
			# the second engine, the rotor and the ramjet's voice carry their own levels
			var own: float = level if not layer in OWN_LEVEL or flat else 1.0
			var g: float = gains[layer] * own if solo == "" or solo == layer or (solo == "ramjet" and layer in RAM_LAYERS) else 0.0
			var at: float
			match layer:
				"second":
					at = layer_at("second", v.sec.spool) * lift * twin
				"rotor":
					at = v.rotor_p * twin
					if short_intakes:
						at *= lerpf(1.08, 1.20, lever)
				"burner":
					at = 1.0 + 0.1 * maxf(0.0, s - 1.0)
				"ramjet":
					at = lerpf(TUNE.ram_pitch[0], TUNE.ram_pitch[1], ram_q) * (1.0 + 0.5 * TUNE.ram_boost_pitch * v.ram_boost) * ram_fall
				"ramtear":
					at = lerpf(TUNE.ram_tear_pitch[0], TUNE.ram_tear_pitch[1], ram_q) * (1.0 + TUNE.ram_boost_pitch * v.ram_boost) * ram_fall
				"v8", "v12":
					at = layer_at(layer, s) * twin * shift
					if short_intakes and layer == "v12":
						at *= 1.145
				"turbine":
					at = layer_at(layer, s) * (1.0 if flat else lerpf(TUNE.turbine_start, 1.0, _wind))
				_:
					at = layer_at(layer, s)
			if not flat and fleet_voice.has(layer):
				var trim: Vector2 = fleet_voice[layer]
				g *= trim.x
				at *= trim.y
			v.at[layer] = at
			var uncapped: bool = overdrive and layer in OVERDRIVE_LAYERS
			if v.glides.has(layer):
				var glide: FleetPitchGlide = v.glides[layer]
				var pitch := maxf(0.01, at / float(_rate_at[layer]))
				# Two matched takes sum coherently on return to equal drive. Leave
				# 3 dB of headroom for that sum ahead of the stereo engine buses.
				glide.drive(pitch if uncapped else minf(pitch, 16.0), g*sqrt(0.5), crossfade(_bands[layer], _rho[layer], at))
				continue
			if layer in RAM_LAYERS:
				# unlit and died away, the ramjet's loops are paused: nothing of them is mixed, and nothing is sent them
				var quiet: bool = g <= 1e-4
				var loops: Array = v.players[layer]
				if quiet and (loops[0] as AudioStreamPlayer).stream_paused:
					continue
				_drive(loops, layer, at, g)
				for p: AudioStreamPlayer in loops:
					if p.stream_paused != quiet:
						p.stream_paused = quiet
				continue
			_drive(v.players[layer], layer, at, g, uncapped)


## One side of the second engine: off, waiting its turn (the right side lights a beat after the
## left), cranking in coughs, running on its lever, or stopping. Returns its gain, level included.
func _second(v: Dictionary, k: int, target_run: float, dt: float, duck: float, rise_rate := INF) -> float:
	var sc: Dictionary = v.sec
	match sc.state:
		"off":
			if second_on:
				sc.state = "wait"
				sc.t = TUNE.second_stagger * k
		"wait":
			sc.t -= dt
			if not second_on:
				sc.state = "off"
			elif sc.t <= 0.0:
				sc.state = "crank"
				sc.t = TUNE.second_crank_s
		"crank":
			sc.t -= dt
			sc.cough_next -= dt
			if sc.cough_next <= 0.0:
				sc.cough_next = randf_range(0.05, 0.14)
				sc.cough_k = 1.0 if randf() < 0.45 else 0.0
			if not second_on:
				sc.state = "stop"
			elif sc.t <= 0.0:
				sc.state = "run"
				_play_bang(v, TUNE.bang_db[0], duck)
		"run":
			if not second_on:
				sc.state = "stop"
				_play_bang(v, TUNE.bang_db[1], duck)
			elif not flat and sc.spool > TUNE.pop_rpm and sc.spool - target_run > TUNE.pop_lift and v.pop2_t <= 0.0:
				v.pop2_t = TUNE.pop_s
				v.pop2_k = clampf((sc.spool - target_run) / 0.5, 0.3, 1.0)
		"stop":
			if second_on:
				sc.state = "crank"
				sc.t = TUNE.second_crank_s
			elif sc.spool < -0.3:
				sc.state = "off"
	var target := -0.33
	var tau: float = TUNE.second_wind
	var fire := 0.0
	match sc.state:
		"crank":
			target = -0.15   # turning over on the starter
			tau = 0.3
			fire = sc.cough_k
		"run":
			target = target_run
			fire = 1.0
	if sc.state == "run" and sc.spool >= 0.0:
		_rev(sc, "spool", "vel", target, dt, rise_rate)
	else:
		sc.spool = _follow(sc.spool, target, tau, dt)
		sc.vel = 0.0
	_pop(v, "pops2", "pop2_t", "pop2_k", dt, duck)
	sc.fire = _follow(sc.fire, fire, 0.05 if fire > sc.fire else 0.08, dt)
	var lvl := db_to_linear(lerpf(TUNE.second_level_db[0], TUNE.second_level_db[1], clampf(sc.spool, 0.0, 1.0)))
	return sc.fire * lvl * duck


## One side's bass rotor: wound up by airspeed, swelled by its lever, stepping back once that
## side's second engine runs. Sets its pitch and low-pass; returns its gain, level included.
func _rotor(v: Dictionary, lever: float, mph: float, dt: float, duck: float) -> float:
	v.rotor_mph = _follow(v.rotor_mph, mph, TUNE.rotor_tau, dt)
	var frac: float = clampf(v.rotor_mph / TUNE.second_on_mph, 0.0, 1.4)
	v.rotor_p = pow(2.0, TUNE.rotor_oct * pow(frac, TUNE.rotor_curve)) * (1.0 + TUNE.rotor_lever_pitch * lever)
	var lp: float = TUNE.rotor_lp_hz[0] * pow(TUNE.rotor_lp_hz[1] / TUNE.rotor_lp_hz[0], clampf(frac, 0.0, 1.0))
	(AudioServer.get_bus_effect(v.subs.rotor, 0) as AudioEffectLowPassFilter).cutoff_hz = TUNE.rotor_lp_hz[1] if flat else lp
	v.sec_run = _follow(v.sec_run, 1.0 if v.sec.state == "run" else 0.0, 0.6, dt)
	var db: float = lerpf(TUNE.rotor_db[0], TUNE.rotor_db[1], clampf(frac, 0.0, 1.0)) + TUNE.rotor_handover_db * v.sec_run
	return db_to_linear(db) * lerpf(TUNE.rotor_lever[0], TUNE.rotor_lever[1], lever) * duck


## The spool spring: snappy and flaring a touch past the lever on the way up, settling clean
## on the way down. Fixed 240 Hz substeps: stepped once per frame, the flare shrank with the
## frame rate (10% at 144 fps, 5% at 45, none at 20) and one long frame kicked the revs.
## Gearing limits positive velocity only; falling remains as quick as the original spring.
func _rev(d: Dictionary, key: String, vkey: String, target: float, dt: float, rise_rate := INF) -> void:
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	for i in n:
		var up: bool = target > d[key]
		var w: float = TUNE.rev_w[0] if up else TUNE.rev_w[1]
		var z: float = TUNE.rev_z[0] if up else TUNE.rev_z[1]
		d[vkey] += (w * w * (target - d[key]) - 2.0 * z * w * d[vkey]) * h
		d[vkey] = minf(d[vkey], rise_rate)
		d[key] += d[vkey] * h


## While an overrun burst is live, fire pops at random, tapering over pop_s.
func _pop(v: Dictionary, player: String, tkey: String, kkey: String, dt: float, duck: float) -> void:
	if v[tkey] <= 0.0:
		return
	v[tkey] -= dt
	var rate: float = TUNE.pop_rate * v[kkey] * maxf(v[tkey], 0.0) / TUNE.pop_s
	if duck > 0.0 and (solo == "" or solo == "pops") and randf() < rate * dt:
		(v[player] as AudioStreamPlayer).play()
		v.pops_n += 1


func _play_bang(v: Dictionary, db: float, duck: float) -> void:
	if duck <= 0.0 or (solo != "" and solo != "second"):
		return
	var p: AudioStreamPlayer = v.bang
	p.volume_db = db
	p.play()


## One of the ramjet's shots (its light-up, its shut-down) on engine k, at `db`: the left engine's take, or
## the right's (the same sound a hair slower). A new shot takes the place of one still sounding.
func _ram_shot(v: Dictionary, k: int, takes: Array[AudioStreamWAV], db: float) -> void:
	if takes.is_empty() or (solo != "" and solo != "ramjet"):
		return
	var p: AudioStreamPlayer = v.ram_shots
	p.stream = takes[mini(k, takes.size() - 1)]
	p.volume_db = minf(db, TUNE.ram_shot_max_db)
	p.play()


## The ramjet's voice as it stands, for a log line: how far each engine's is in, the light-up's kick, the
## boost as heard, the thrust it follows, and the roar's and the tear's levels (dB) and speeds of playing.
func ram_state() -> String:
	var parts := PackedStringArray()
	for v: Dictionary in voices:
		parts.append("in %.2f kick %.2f boost %.2f thrust %.2f roar %.1f dB x%.2f tear %.1f dB x%.2f" % [v.ram, v.ram_kick, v.ram_boost, v.ram_thr,
			v.ram_db[0], v.at.get("ramjet", 1.0), v.ram_db[1], v.at.get("ramtear", 1.0)])
	return " | ".join(parts)


## Crossfade weights for the levels around `at` (log spacing): linear shapes, normalized for the
## pair's correlation so the blend holds the level (rho 0 is equal power, 1 is linear).
## Off the ends, the end level carries it alone.
static func crossfade(ats: PackedFloat64Array, rhos: PackedFloat64Array, at: float) -> PackedFloat64Array:
	var n := ats.size()
	var w := PackedFloat64Array()
	w.resize(n)
	if n == 1 or at <= ats[0]:
		w[0] = 1.0
		return w
	if at >= ats[n - 1]:
		w[n - 1] = 1.0
		return w
	var lo := 0
	while at >= ats[lo + 1]:
		lo += 1
	var t := log(at / ats[lo]) / log(ats[lo + 1] / ats[lo])
	var a := 1.0 - t
	var g := 1.0 / sqrt(a * a + t * t + 2.0 * rhos[lo] * a * t)
	w[lo] = a * g
	w[lo + 1] = t * g
	return w


## Every level of the layer is pitched every frame, audible or not. A master's levels all get
## the identical pitch, which is what keeps them in lockstep.
func _drive(players: Array, layer: String, at: float, gain: float, overdrive := false) -> void:
	var ats: PackedFloat64Array = _bands[layer]
	var w := crossfade(ats, _rho[layer], at)
	var rate_at: float = _rate_at[layer]
	for i in ats.size():
		var p: AudioStreamPlayer = players[i]
		var pitch := at / (rate_at if rate_at > 0.0 else ats[i])
		p.pitch_scale = maxf(pitch, 0.01) if overdrive else clampf(pitch, 0.01, 16.0)
		var lin := w[i] * gain
		p.volume_db = linear_to_db(lin) if lin > 1e-4 else -80.0
