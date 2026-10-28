extends SceneTree
## Every playbook offense play, N snaps against random playbook defenses: mean, median, stuffed.
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var n := 120
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Balanced")
	var offs: Array = Library.plays_for("offense")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for on in offs:
		var gs := []
		for i in n:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			s.setup(red, blue, Library.play(on), Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var res := s.run_to_end()
			var g := 0.0 if res["incomplete"] else float(res["y"])
			if res["turnover"] != "":
				g = -20.0
			gs.append(g)
		var tot := 0.0
		var stuff := 0
		for g in gs:
			tot += g
			if g <= 0.5: stuff += 1
		gs.sort()
		print("%-16s %-4s mean %5.1f median %5.1f  <=0.5: %3d%%" % [on, Library.play(on).kind, tot / n, gs[n / 2], 100 * stuff / n])
	quit()
