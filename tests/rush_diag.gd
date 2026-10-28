extends SceneTree
## How quickly does the rush get home, by D-line quality (O-line average)?
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var ls = load("res://tests/_ls_side.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var offs: Array = Library.plays_for("offense").filter(func(n): return Library.play(n).kind != "run")
	var defs: Array = Library.plays_for("defense")
	for pair in [["average", "great"], ["average", "average"], ["average", "poor"], ["great", "average"], ["poor", "average"], ["great", "poor"], ["poor", "great"]]:
		var dl: String = "OL %s vs DL %s" % pair
		var off: Dictionary = ls.side(0, pair[0], "average", rng)
		var dfn: Dictionary = ls.side(1, "average", pair[1], rng)
		var n := 0
		var reached := 0
		var t_sum := 0.0
		var sheds := 0
		var sacks := 0
		var yds := 0.0
		var by := {}
		var sack_t := 0.0
		for i in 150:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			s.setup(off, dfn, Library.play(offs[rng.randi() % offs.size()]), Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var qb = s.by_slot["o:QB"]
			var first := -1.0
			var was_eng := {}
			var k := 0
			while not s.over and k < 600:
				s.step()
				k += 1
				for e in s.dfn:
					if e.group == "DL":
						if e.engaged != null:
							was_eng[e.idx] = true
						elif was_eng.has(e.idx):
							sheds += 1
							was_eng.erase(e.idx)
						if first < 0.0 and not s.thrown and e.pos.distance_to(qb.pos) < 2.0:
							first = s.t
			n += 1
			if first > 0.0:
				reached += 1
				t_sum += first
			if s.result["sack"]:
				sacks += 1
				var tk := String(s.result["stat"].get("tackler", "?"))
				var grp: String = Play.SLOT_GROUP.get(tk, tk)
				by[grp] = int(by.get(grp, 0)) + 1
				sack_t += s.t
			yds += (0.0 if s.result["incomplete"] else float(s.result["y"])) if s.result["turnover"] == "" else -10.0
		print("%-26s rush within 2 yds of QB before the throw: %d%% (avg at %.2fs)  DL sheds/play %.2f  sacks %d%%  yds/pass play %.1f  sacked by %s at %.1fs" % [dl, 100 * reached / n, t_sum / maxf(reached, 1), float(sheds) / n, 100 * sacks / n, yds / n, by, sack_t / maxf(sacks, 1)])
	quit()
