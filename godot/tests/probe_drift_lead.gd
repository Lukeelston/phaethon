## Who moves first into a turn: the engines' lean, or the cockpit stepping out?
## (Luke, 2026-11-23, flying push 41 with the drift slider at its new stop: "I think the cockpit lists before
## the engines do. It feels like the pilot leads the engines.")
## A turn is put on at once and held (30 g hard, 10 g gentle, at 3,350 mph), and three things are followed at
## 90 frames a second: the engines' lean as CraftModel eases it (ease_bank), the cockpit's slide as it was
## until push 41 (the cornering load through 0.18 s of smoothing, then the spring: written out again here),
## and the cockpit's slide now (vr_cockpit.gd's own _ease_slide). For each: when it has come to a tenth, a
## half and nine tenths of where it ends, and how far each has got at a few moments. Then the pod's extra
## nose-down pitch for the slide it ends at, at the slider's notch and at its stop.
##   --headless --xr-mode off -s res://tests/probe_drift_lead.gd -- --mute
extends SceneTree
const CM := preload("res://view/craft_model.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Drift := preload("res://vr/drift_slider.gd")
class Seat extends "res://vr/vr_cockpit.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
const SPEED := 1500.0      # m/s along the engines' heading (about 3,350 mph)
const FRAME := 1.0 / 90.0
const OLD_T := 0.18        # s: the smoothing the slide read the load through until push 41
var seat: Seat


func _load(g: float) -> void:
	var sim = seat.sim
	sim.pod.vx = SPEED * cos(sim.pair_th)
	sim.pod.vy = SPEED * sin(sim.pair_th)
	sim.eL.w = g * 9.81 / SPEED
	sim.eR.w = sim.eL.w


## When a run of values first comes to `share` of its last value, s.
func _when(run: PackedFloat64Array, share: float) -> float:
	var last := run[run.size() - 1]
	for k in run.size():
		if absf(run[k]) >= absf(last) * share:
			return (k + 1) * FRAME
	return -1.0


func _initialize() -> void:
	seat = Seat.new()
	seat.sim = Sim.new({"track": "range"})
	var was_amount: float = Seat.slide_amount
	var was_feel: bool = Seat.slide_feel
	Seat.slide_feel = true
	for g: float in [30.0, 10.0]:
		for amount: float in [1.0, Drift.AMOUNT_MAX]:
			Seat.slide_amount = amount
			seat._slide = 0.0
			seat._slide_rate = 0.0
			seat._slide_load = 0.0
			seat._slide_lean = 0.0
			seat._slide_ask = 0.0
			seat._slide_stop = 0.0
			_load(g)
			var lean := 0.0
			var lat := 0.0
			var old_load := 0.0
			var old := 0.0
			var old_rate := 0.0
			var leans := PackedFloat64Array()
			var olds := PackedFloat64Array()
			var news := PackedFloat64Array()
			for k in int(4.0 / FRAME):
				# the engines' own lean
				var e: Array = CM.ease_bank(lean, lat, g, FRAME)
				lean = e[0]
				lat = e[1]
				leans.append(lean)
				# the slide as it was
				old_load += (seat.turn_load() - old_load) * (1.0 - exp(-FRAME / OLD_T))
				var target: float = signf(old_load) * smoothstep(Seat.SLIDE_LOAD.x, Seat.SLIDE_LOAD.y, absf(old_load)) * Seat.SLIDE_MAX * amount
				var w := TAU * Seat.SLIDE_HZ
				var remaining := FRAME
				while remaining > 0.000001:
					var step := minf(remaining, 1.0 / 240.0)
					old_rate = clampf(old_rate + (w * w * (target - old) - 2.0 * Seat.SLIDE_ZETA * w * old_rate) * step, -Seat.SLIDE_RATE, Seat.SLIDE_RATE)
					old = old + old_rate * step
					remaining -= step
				olds.append(old)
				# the slide now
				news.append(seat._ease_slide(FRAME))
			print("TURN %.0f g, slider at %.2f: the engines lean to %.1f deg; the cockpit steps out to %.2f deg (as it was: %.2f)" % [
				g, amount, rad_to_deg(leans[leans.size() - 1]), rad_to_deg(news[news.size() - 1]), rad_to_deg(olds[olds.size() - 1])])
			print("   reaches a tenth / a half / nine tenths of that, s:   engines' lean %.2f / %.2f / %.2f   |   cockpit as it was %.2f / %.2f / %.2f   |   cockpit now %.2f / %.2f / %.2f" % [
				_when(leans, 0.1), _when(leans, 0.5), _when(leans, 0.9), _when(olds, 0.1), _when(olds, 0.5), _when(olds, 0.9), _when(news, 0.1), _when(news, 0.5), _when(news, 0.9)])
			var rows := []
			for at: float in [0.1, 0.2, 0.3, 0.5, 0.75, 1.0]:
				var k := int(at / FRAME) - 1
				rows.append("%.2f s: %3.0f%% | %3.0f%% | %3.0f%%" % [at, 100.0 * leans[k] / leans[leans.size() - 1], 100.0 * olds[k] / olds[olds.size() - 1], 100.0 * news[k] / news[news.size() - 1]])
			print("   how far along (engines' lean | cockpit as it was | cockpit now):   " + "   ".join(rows))
			print("   the pod's nose for that slide: %.1f deg down in all (%.1f at rest, %.1f more for the slide)" % [
				rad_to_deg(Seat.POD_PITCH + Seat.drift_pitch_for(news[news.size() - 1])), rad_to_deg(Seat.POD_PITCH), rad_to_deg(Seat.drift_pitch_for(news[news.size() - 1]))])
			# ... and let go: when each is back to a half and to a tenth of what it held
			_load(0.0)
			var held := [lean, old, news[news.size() - 1]]
			var back := [[-1.0, -1.0], [-1.0, -1.0], [-1.0, -1.0]]
			var fastest := 0.0
			var before: float = news[news.size() - 1]
			for k in int(3.0 / FRAME):
				var e: Array = CM.ease_bank(lean, lat, 0.0, FRAME)
				lean = e[0]
				lat = e[1]
				old_load += (0.0 - old_load) * (1.0 - exp(-FRAME / OLD_T))
				var target: float = signf(old_load) * smoothstep(Seat.SLIDE_LOAD.x, Seat.SLIDE_LOAD.y, absf(old_load)) * Seat.SLIDE_MAX * amount
				var w := TAU * Seat.SLIDE_HZ
				var remaining := FRAME
				while remaining > 0.000001:
					var step := minf(remaining, 1.0 / 240.0)
					old_rate = clampf(old_rate + (w * w * (target - old) - 2.0 * Seat.SLIDE_ZETA * w * old_rate) * step, -Seat.SLIDE_RATE, Seat.SLIDE_RATE)
					old = old + old_rate * step
					remaining -= step
				var now: float = seat._ease_slide(FRAME)
				fastest = maxf(fastest, absf(now - before) / FRAME)
				before = now
				var values := [lean, old, now]
				for i in 3:
					for j in 2:
						if back[i][j] < 0.0 and absf(values[i]) <= absf(held[i]) * [0.5, 0.1][j]:
							back[i][j] = (k + 1) * FRAME
			print("   let go, back to a half / a tenth of it, s:   engines' lean %.2f / %.2f   |   cockpit as it was %.2f / %.2f   |   cockpit now %.2f / %.2f   (the cockpit's fastest now: %.0f deg/s)" % [
				back[0][0], back[0][1], back[1][0], back[1][1], back[2][0], back[2][1], rad_to_deg(fastest)])
	Seat.slide_amount = was_amount
	Seat.slide_feel = was_feel
	seat.free()
	print("DRIFT LEAD PROBE DONE")
	quit(0)
