extends SceneTree
## How often passers fire bullets and defenders bat passes down, and what it does to passing.
func _init() -> void:
	Library.ensure()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var att := 0.0
	var cmp := 0.0
	var yds := 0.0
	var ints := 0.0
	var pbu := 0.0
	var bats := 0.0
	var n := 12
	for i in n:
		var g := Batch.play_game(Team.build(0, "Air Raid"), Team.build(1, "Balanced"), 300.0, 700 + i)
		for t in 2:
			att += float(g.stats[t]["pass_att"])
			cmp += float(g.stats[t]["comp"])
			yds += float(g.stats[t]["pass_yds"])
			ints += float(g.stats[t]["ints"])
			pbu += float(g.stats[t].get("pbu", 0))
			bats += float(g.stats[t].get("bats", 0))
	print("per team-game: att %.1f  comp %.0f%%  yds/att %.1f  ints %.2f  broken up %.1f  batted %.1f" % [att / (2 * n), 100.0 * cmp / att, yds / att, ints / (2 * n), pbu / (2 * n), bats / (2 * n)])
	quit()
