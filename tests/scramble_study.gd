extends SceneTree
## QB mobility: a slow, an average and a quick, strong quarterback (average lines, everyone else
## normal). How often he scrambles, what comes of it (throw on the run, reset and throw, run it,
## sack), sacks, completion and yards a dropback.   -- [--n=400] [--k=v]
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var n := int(PlaySim.K.get("n", 400))
	var offs: Array = Library.plays_for("offense").filter(func(x): return (Library.play(x) as Play).kind != "run")
	var defs: Array = Library.plays_for("defense")
	for lvl in [["slow", 35, 40], ["average", 55, 50], ["mobile", 88, 75]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 51
		var off := Side.side(0, "average", "average", rng)
		var dfn := Side.side(1, "average", "average", rng)
		off["roster"]["QB"]["ratings"]["speed"] = lvl[1]
		off["roster"]["QB"]["ratings"]["strength"] = lvl[2]
		var st := {"scr": 0, "run_throw": 0, "reset": 0, "ran": 0, "sack": 0, "comp": 0, "att": 0, "yds": 0.0, "scr_yds": 0.0}
		for i in n:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			s.setup(off, dfn, Library.play(offs[rng.randi() % offs.size()]), Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var scr := false
			var thrown_scr := false
			var guard := 0
			while not s.over and guard < 3000:
				var was := s.scrambling
				var was_thrown := s.thrown
				s.step()
				guard += 1
				if s.scrambling:
					scr = true
				if s.thrown and not was_thrown and was:
					thrown_scr = true
			var res := s.result
			var y := 0.0 if res["incomplete"] else float(res["y"])
			st["yds"] += y
			if res["sack"]:
				st["sack"] += 1
				if scr:
					st["sack_scr"] = int(st.get("sack_scr", 0)) + 1
				var how := String(s.stat.get("sack_how", "?"))
				st["how_" + how] = int(st.get("how_" + how, 0)) + 1
			if bool(res["pass"]) and not s.air.get("away", false):
				st["att"] += 1
				if not res["incomplete"] and res["turnover"] == "":
					st["comp"] += 1
			if scr:
				st["scr"] += 1
				st["scr_yds"] += y
				if res["carrier"] == "QB" and not bool(res["pass"]) and not res["sack"]:
					st["ran"] += 1
				elif thrown_scr:
					st["run_throw"] += 1
				elif bool(res["pass"]):
					st["reset"] += 1
		var N := float(n)
		print("%-8s QB: scrambles %3.0f%% (threw on the run %d, reset and threw %d, ran %d) %4.1f yds when he scrambles | sacks %4.1f%%  comp %3.0f%%  %4.1f yds a dropback" % [lvl[0],
			100.0 * st["scr"] / N, st["run_throw"], st["reset"], st["ran"], st["scr_yds"] / maxf(st["scr"], 1), 100.0 * st["sack"] / N, 100.0 * st["comp"] / maxf(st["att"], 1), st["yds"] / N])
		var hows := {}
		for k in st:
			if String(k).begins_with("how_"):
				hows[String(k).substr(4)] = st[k]
		print("      sacks while scrambling %d; how: %s" % [int(st.get("sack_scr", 0)), hows])
	print("OK")
	quit()
