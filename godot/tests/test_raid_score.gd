## Raid score (the stage 1 plan, task 11): the raid on the skill score. "Jolt and points": a hit costs points,
## never health. Raids pinned on, the Network.
##   kill       each raider shot: RAIDER DOWN +250 (x the chain's multiplier), the chain grows
##   cleared    RAID CLEARED +2000 and +20 for each of the 60 commuters not lost (x the multiplier)
##   lost       "RAID LOST" flashed, no award
##   deduct     a commuter lost -40 (off-screen ticks and run down alike, each exactly once), a hit taken -100, a
##              commuter struck by your fire during a raid -150 (once for each car); each resets the chain; the total
##              never goes below 0; the best is untouched
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
	R.kills = 1
	v._raid_sync()
	var one: int = S.total
	R.kills = 3
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
	var reset_chain: bool = S.chain == 0 and S.multiplier == 1.0
	R.hit_taken.emit("raider")
	var b: int = S.total
	var car := RefCounted.new()
	v._raid_struck(car)
	var c: int = S.total
	v._raid_struck(car)      # (the same car again: once)
	var again: int = S.total
	v._raid_struck(RefCounted.new())
	var pen: Array = S.feedback.filter(func(f): return f.kind == "penalty")
	_check("a commuter lost -40 (%d), a hit -100 (%d), a commuter struck -150 (%d), the same one again nothing (%d), another -150 (%d); chain reset %s; feedback %s; \"%s\"" % [a, b, c, again, S.total, reset_chain, pen, S.award_text],
		a == 960 and b == 860 and c == 710 and again == 710 and S.total == 560 and reset_chain and pen.size() == 4 and pen[0].points == -40 and pen[1].points == -100 and S.award_text.begins_with("COMMUTER STRUCK"))

	# off-screen losses: counted by R.lost with no signal, each exactly once; a new raid starts the count again
	_fresh(v)
	R.state = "called"
	S.total = 500
	R.lost = 2
	v._raid_sync()
	R.lost = 3
	v._raid_sync()
	v._raid_sync()
	var off: int = S.total
	R.reset()
	R.state = "called"
	R.lost = 1
	v._raid_sync()
	_check("3 commuters lost off-screen: 500 - 120 = 380 (%d); after a new raid, 1 more: 340 (%d)" % [off, S.total], off == 380 and S.total == 340)

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
	R.kills = 3
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
	R.kills = 3
	R.lost = 2
	v._raid_sync()
	var kept: int = S.total
	v._raid_reset_score()      # (no raids.reset(): its counts stand)
	v._raid_sync()
	_check("a re-basing without the director's reset does not pay or charge again (%d, was %d)" % [S.total, kept], S.total == kept)
	# the real restart path, with a raid on
	_fresh(v)
	R.state = "on"
	R.kills = 3
	R.lost = 2
	v._raid_sync()
	v._respawn()
	v._raid_sync()
	var after_restart: int = S.total
	R.state = "on"
	R.kills = 1
	v._raid_sync()
	_check("the restart (v._respawn) clears the run's total with nothing re-paid or re-charged for the old raid (%d), and a new raid's kill pays 250 (%d)" % [after_restart, S.total],
		after_restart == 0 and S.total == 250 and R.lost == 0)
	# a crash mid-raid: the director sets the raid aside itself (inside update, when the sim's respawn comes)
	_fresh(v)
	R.state = "called"
	R.city = 0
	R.arrive_r = 0.0
	R.tick_every = 1.0e9
	R.kills = 3
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
	R.kills = 1
	v._raid_sync()
	_check("a crash mid-raid: the director sets it aside (%s), the sync pays and charges nothing more (%d, was %d), and the next raid's kill pays 250 (%d)" % [reset_by_crash, after_crash, before_crash, S.total],
		reset_by_crash and after_crash == before_crash and S.total == before_crash + 250)

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
