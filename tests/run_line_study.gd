extends SceneTree
## Running game by line quality: yards per run, typical run, stuffed, 10+ yard runs.
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var ls = load("res://tests/_ls_side.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var runs: Array = Library.plays_for("offense").filter(func(n): return Library.play(n).kind == "run" and n != "QB Sneak")
	var defs: Array = Library.plays_for("defense")
	for ol in ["great", "average", "poor"]:
		for dl in ["great", "average", "poor"]:
			var off: Dictionary = ls.side(0, ol, "average", rng)
			var dfn: Dictionary = ls.side(1, "average", dl, rng)
			var gs: Array = []
			var tot := 0.0
			for i in 400:
				var s := PlaySim.new()
				var r := RandomNumberGenerator.new()
				r.seed = rng.randi()
				s.setup(off, dfn, Library.play(runs[rng.randi() % runs.size()]), Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
				var res := s.run_to_end()
				var g := float(res["y"]) if res["turnover"] == "" else -5.0
				gs.append(g)
				tot += g
			gs.sort()
			var stuffed := gs.filter(func(x): return x <= 0.5).size()
			var ten := gs.filter(func(x): return x >= 10.0).size()
			print("RUN,%s,%s,%.1f,%.1f,%d,%d" % [ol, dl, tot / gs.size(), gs[gs.size() / 2], 100 * stuffed / gs.size(), 100 * ten / gs.size()])
	quit()
