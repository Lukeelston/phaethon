## Raid score (the stage 1 plan, task 11): the raid on the skill score. "Jolt and points": a hit costs points,
## never health. Raids pinned on, the Network.
##   kill       each raider shot: RAIDER DOWN +250 (x the chain's multiplier), the chain grows. Each kind is paid from the
##              director's kills_by (on_kill counts a kill by its kind; kills is their sum, and this test sets both so)
##   flyers     check_flyer_awards (the stage 2 plan, task 4): a drone shot DRONE DOWN +100, the gunship GUNSHIP DOWN
##              +1500, neither paid as a raider; a frame's kills of all three kinds each paid as its own; a re-basing
##              and a restart mid-raid pay none of them twice, and the next raid's drones are each paid
##   cleared    RAID CLEARED +2000 and +20 for each of the 60 commuters not lost (x the multiplier)
##   lost       "RAID LOST" flashed, no award
##   deduct     a commuter run down -40, a hit taken -100, a commuter struck by your fire during a raid -150 (once
##              for each car); only the hit breaks the chain (and holds the next skill off, as an impact does); each
##              says what it was for; the total never goes below 0; the best is untouched
##   off-screen the commuters lost off-screen (the director's lost_off) are charged once, all together ("COMMUTERS
##              LOST x3", -120), at the arrival or at the raid's end, never while it is called
##   free       a commuter struck with no raid on costs nothing
##   tone       skill_audio plays its own low tone for a penalty, not the "near" one
## Prints RAID SCORE PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Raids := preload("res://view/network_raids.gd")
const Audio := preload("res://audio/skill_audio.gd")
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"
	View.best_dir = OS.get_user_data_dir().path_join("test_raid_score_")
	DirAccess.remove_absolute(View.best_dir + "skills_network.json")
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The director's own end of a raid: its result and its tally, as _end leaves them.
func _end(R, how: String) -> void:
	R.result = how
	R.tally[how] = int(R.tally[how]) + 1


## The director's kills as on_kill leaves them: this raid's kills by kind (kills_by), and kills their sum.
func _set_kills(R, raider: int, drone := 0, gunship := 0) -> void:
	R.kills_by.raider = raider
	R.kills_by.drone = drone
	R.kills_by.gunship = gunship
	R.kills = raider + drone + gunship


## Drones and the gunship on the score: each paid as its own kind, from kills_by; none paid twice.
func check_flyer_awards(v) -> void:
	var S = v.skill_score
	var R = v.raids
	var P: Dictionary = Raids.RAID_POINTS
	_fresh(v)
	R.state = "on"
	_set_kills(R, 0, 1)
	v._raid_sync()
	var drone_pays: int = S.total
	var drone_said: String = S.award_text
	v._raid_sync()
	var drone_once: bool = S.total == drone_pays
	_fresh(v)
	R.state = "on"
	_set_kills(R, 0, 0, 1)
	v._raid_sync()
	var gunship_pays: int = S.total
	var gunship_said: String = S.award_text
	_check("a drone shot: +%d \"%s\" (want 100, DRONE DOWN; paid once: %s); the gunship: +%d \"%s\" (want 1500, GUNSHIP DOWN); RAID_POINTS drone %s, gunship %s" % [drone_pays, drone_said, drone_once, gunship_pays, gunship_said, P.get("drone"), P.get("gunship")],
		drone_pays == 100 and drone_said.begins_with("DRONE DOWN") and drone_once and gunship_pays == 1500 and gunship_said.begins_with("GUNSHIP DOWN")
		and P.get("drone") == 100 and P.get("gunship") == 1500)
	# a frame's kills of all three kinds: a raider, two drones, the gunship (the chain 1, 2, 3, 4: x1, x1, x1.5, x1.5)
	_fresh(v)
	R.state = "on"
	_set_kills(R, 1, 2, 1)
	v._raid_sync()
	var points: Array = S.feedback.map(func(f): return int(f.points))
	var mixed: int = S.total
	_check("one frame's kills, a raider, two drones and the gunship: each paid as its own kind, %s (want [250, 100, 150, 2250]), %d in all" % [points, mixed],
		points == [250, 100, 150, 2250] and mixed == 2750 and S.award_text.begins_with("GUNSHIP DOWN"))
	# a re-basing with the director's counts standing pays none of them again; nor the restart path
	v._raid_reset_score()
	v._raid_sync()
	var rebased: int = S.total
	v._respawn()
	v._raid_sync()
	var restarted: int = S.total
	var zeroed: bool = R.kills == 0 and int(R.kills_by.raider) == 0 and int(R.kills_by.drone) == 0 and int(R.kills_by.gunship) == 0
	R.state = "on"
	_set_kills(R, 0, 3)      # (more drones than the old raid's two: each paid, the paid counts re-based by kind)
	v._raid_sync()
	var next_raid: Array = S.feedback.map(func(f): return int(f.points))
	_check("a re-basing mid-raid pays none again (%d, was %d); the restart (v._respawn) clears the run's total with none re-paid (%d; the director's kills by kind zeroed: %s), and the next raid's three drones pay %s (want [100, 100, 150]), %d" % [rebased, mixed, restarted, zeroed, next_raid, S.total],
		rebased == mixed and restarted == 0 and zeroed and next_raid == [100, 100, 150] and S.total == 350 and S.award_text.begins_with("DRONE DOWN"))


func _fresh(v) -> void:
	v.skill_score.reset_run()
	v.skill_score.feedback.clear()
	v.raids.reset()
	v._raid_reset_score()
	v.flash_until = 0.0
	v.flash_msg = ""


func _run() -> void:
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var S = v.skill_score
	var R = v.raids
	if R == null or S == null:
		_check("raids pinned on: the view has a director and a score", false)
		print("RAID SCORE FAIL (%d failures)" % failures)
		quit(1)
		return

	# kill: 250 each, the chain grows and the multiplier with it (1.0, 1.0, 1.5 on the third)
	_fresh(v)
	R.state = "on"
	_set_kills(R, 1)
	v._raid_sync()
	var one: int = S.total
	_set_kills(R, 3)
	v._raid_sync()
	var kinds: Array = S.feedback.map(func(f): return f.kind)
	_check("a raider shot: +250 (%d), three shot 250+250+375 = 875 (%d), chain %d, \"%s\", feedback %s" % [one, S.total, S.chain, S.award_text, kinds],
		one == 250 and S.total == 875 and S.chain == 3 and S.award_text.begins_with("RAIDER DOWN") and kinds == ["raid", "raid", "raid"])
	v._raid_sync()
	_check("the same kills are not paid twice (%d)" % S.total, S.total == 875)

	# cleared: 2000 + 20 for each of the 60 not lost; 10 lost first: -40 each (to 0), then 3000
	_fresh(v)
	R.state = "on"
	R.lost = 10
	_end(R, "cleared")
	v._raid_sync()
	var floored: int = S.total
	v._raid_result()
	v._raid_result()      # (taken once: it is called every frame; the director's own result stays for its readers)
	_check("10 commuters lost then the raid cleared: the loss held at 0 (%d), then 2000 + 20 x 50 = 3000 once (%d), \"%s\", result left as it was (\"%s\")" % [floored, S.total, S.award_text, R.result],
		floored == 0 and S.total == 3000 and S.award_text.begins_with("RAID CLEARED") and R.result == "cleared")
	_fresh(v)
	R.state = "on"
	_end(R, "cleared")
	S.chain = 5          # (the clearing is the sixth: x2.0)
	v._raid_result()
	_check("a clean clearing in a chain of six: (2000 + 1200) x 2.0 = 6400 (%d)" % S.total, S.total == 6400 and S.multiplier == 2.0)

	# lost: flashed, no award
	_fresh(v)
	R.state = "on"
	_end(R, "lost")
	v._raid_result()
	_check("a raid lost: \"%s\" flashed, no award (%d, \"%s\")" % [v.flash_msg, S.total, S.award_text],
		v.flash_msg.begins_with("RAID LOST") and S.total == 0 and S.award_text == "" and S.feedback.is_empty())

	# deductions
	_fresh(v)
	R.state = "on"
	S.total = 1000
	S.chain = 4
	S.multiplier = 2.0
	R.lost = 1
	v._raid_sync()
	var a: int = S.total
	var kept_by_lost: bool = S.chain == 4 and S.multiplier == 2.0
	R.hit_taken.emit("raider")
	var b: int = S.total
	var broken_by_hit: bool = S.chain == 0 and S.multiplier == 1.0 and S._bad_until > S.time
	S.chain = 4
	S.multiplier = 2.0
	var car := RefCounted.new()
	v._raid_struck(car)
	var c: int = S.total
	var kept_by_struck: bool = S.chain == 4 and S.multiplier == 2.0
	v._raid_struck(car)      # (the same car again: once)
	var again: int = S.total
	v._raid_struck(RefCounted.new())
	var pen: Array = S.feedback.filter(func(f): return f.kind == "penalty")
	var fors: Array = pen.map(func(f): return f.get("for", ""))
	_check("a commuter lost -40 (%d), a hit -100 (%d), a commuter struck -150 (%d), the same one again nothing (%d), another -150 (%d); the chain kept by the loss (%s) and by a strike (%s), broken by the hit (%s); feedback %s; \"%s\"" % [a, b, c, again, S.total, kept_by_lost, kept_by_struck, broken_by_hit, pen, S.award_text],
		a == 960 and b == 860 and c == 710 and again == 710 and S.total == 560 and kept_by_lost and kept_by_struck and broken_by_hit and pen.size() == 4 and pen[0].points == -40 and pen[1].points == -100
			and fors == ["lost", "hit", "struck", "struck"] and S.award_text.begins_with("COMMUTER STRUCK"))

	# off-screen losses: counted by the director with no signal (lost, and lost_off of them), charged once and all
	# together at the arrival or the end, not while it is called; a new raid starts the count again
	_fresh(v)
	R.state = "called"
	S.total = 500
	R.lost = 2
	R.set("lost_off", 2)
	v._raid_sync()
	R.lost = 3
	R.set("lost_off", 3)
	v._raid_sync()
	var while_called: int = S.total
	var notes_called: int = S.feedback.size()
	R.state = "on"      # (arrived)
	v._raid_sync()
	v._raid_sync()
	var off: int = S.total
	var notes_on: int = S.feedback.size()
	var said: String = S.award_text
	R.reset()
	R.state = "called"
	R.lost = 1
	R.set("lost_off", 1)
	v._raid_sync()
	var second_called: int = S.total
	R.state = "over"    # (not reached: its end)
	v._raid_sync()
	_check("3 commuters lost off-screen: nothing while called (%d, %d notes), one charge at the arrival: 500 - 120 = 380 (%d, %d note, \"%s\"); after a new raid, 1 more off-screen: nothing while called (%d), 340 at its end (%d)" % [
			while_called, notes_called, off, notes_on, said, second_called, S.total],
		while_called == 500 and notes_called == 0 and off == 380 and notes_on == 1 and said == "COMMUTERS LOST x3  -120" and second_called == 380 and S.total == 340)

	# never below 0; the best untouched
	_fresh(v)
	R.state = "on"
	S.total = 120
	S.best = 9000
	R.hit_taken.emit("raider")
	R.hit_taken.emit("raider")
	_check("the total never goes below 0 (%d), the best stays (%d)" % [S.total, S.best], S.total == 0 and S.best == 9000)

	# struck outside a raid: nothing
	_fresh(v)
	S.total = 700
	v._raid_struck(RefCounted.new())
	R.state = "over"
	v._raid_struck(RefCounted.new())
	_check("a commuter struck with no raid on: nothing (%d, %d feedback)" % [S.total, S.feedback.size()], S.total == 700 and S.feedback.is_empty() and S.chain == 0)

	# the director's reset: raids.reset() zeroes kills and lost (the authoritative reset); the score's re-basing keeps
	# it from paying or charging again. First the pairing alone, with the run's total kept.
	_fresh(v)
	R.state = "on"
	_set_kills(R, 3)
	R.lost = 2
	v._raid_sync()
	var settled: int = S.total
	R.reset()
	v._raid_reset_score()
	v._raid_sync()
	_check("after 3 kills and 2 lost (%d), reset + re-base + sync: nothing paid or charged again (%d), kills %d, lost %d" % [settled, S.total, R.kills, R.lost],
		settled == 795 and S.total == settled and R.kills == 0 and R.lost == 0)
	# ... and a wrong pairing cannot double-charge: the director's counts NOT zeroed, the re-basing keeps them settled
	_fresh(v)
	R.state = "on"
	_set_kills(R, 3)
	R.lost = 2
	v._raid_sync()
	var kept: int = S.total
	v._raid_reset_score()      # (no raids.reset(): its counts stand)
	v._raid_sync()
	_check("a re-basing without the director's reset does not pay or charge again (%d, was %d)" % [S.total, kept], S.total == kept)
	# the real restart path, with a raid on
	_fresh(v)
	R.state = "on"
	_set_kills(R, 3)
	R.lost = 2
	v._raid_sync()
	v._respawn()
	v._raid_sync()
	var after_restart: int = S.total
	R.state = "on"
	_set_kills(R, 1)
	v._raid_sync()
	_check("the restart (v._respawn) clears the run's total with nothing re-paid or re-charged for the old raid (%d), and a new raid's kill pays 250 (%d)" % [after_restart, S.total],
		after_restart == 0 and S.total == 250 and R.lost == 0)
	# a crash mid-raid: the director sets the raid aside itself (inside update, when the sim's respawn comes)
	_fresh(v)
	R.state = "called"
	R.city = 0
	R.arrive_r = 0.0
	R.tick_every = 1.0e9
	_set_kills(R, 3)
	R.lost = 2
	v._raid_sync()
	var before_crash: int = S.total
	v.sim.crash_t = 1.0
	R.update(0.01)
	v.sim.crash_t = 0.0
	R.update(0.01)
	var reset_by_crash: bool = R.state == "" and R.kills == 0 and R.lost == 0
	v._raid_sync()
	var after_crash: int = S.total
	# (the losses no longer break the chain: the kill is paid at the chain's multiplier, the three kills' chain and one more)
	var pays := roundi(250.0 * minf(5.0, 1.0 + floorf((S.chain + 1) / 3.0) * 0.5))
	_set_kills(R, 1)
	v._raid_sync()
	_check("a crash mid-raid: the director sets it aside (%s), the sync pays and charges nothing more (%d, was %d), and the next raid's kill pays 250 at the chain's multiplier, %d (%d)" % [reset_by_crash, after_crash, before_crash, pays, S.total],
		reset_by_crash and after_crash == before_crash and S.total == before_crash + pays)

	check_flyer_awards(v)

	# the display: a deduction reads "-40", never "+-40", on the desktop HUD's label and in the display's own text
	_fresh(v)
	R.state = "on"
	S.total = 1000
	R.lost = 1
	v._raid_sync()
	v._update_hud()
	var shown: String = v._skill_display.update(S).award
	var label: String = v._skill_award_label.text
	_check("a deduction reads \"-40\" and never \"+-40\": display \"%s\", HUD label \"%s\"" % [shown, label],
		shown == "COMMUTER LOST  -40" and label == shown and not shown.contains("+-") and not label.contains("+-"))

	# the penalty tone
	var audio = Audio.new()
	root.add_child(audio)
	audio.setup()
	audio.update(0.1, [{"kind": "penalty", "points": -100, "multiplier": 1.0}])
	var penalty_stream = audio.player.stream
	audio.cooldown = 0.0
	audio.update(0.1, [{"kind": "mystery", "points": 10, "multiplier": 1.0}])
	_check("a penalty plays its own tone, not the near one (own %s, near %s; an unknown kind still falls to near %s)" % [audio.tones.has("penalty"), penalty_stream == audio.tones.get("near"), audio.player.stream == audio.tones.near],
		audio.tones.has("penalty") and penalty_stream == audio.tones.penalty and penalty_stream != audio.tones.near and audio.player.stream == audio.tones.near)
	audio.player.stop()

	v.queue_free()
	await process_frame
	if failures == 0:
		print("RAID SCORE PASS")
		quit(0)
	else:
		print("RAID SCORE FAIL (%d failures)" % failures)
		quit(1)
