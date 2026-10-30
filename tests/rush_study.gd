extends SceneTree
## Pass rush by D-line quality (O-line average, everyone else 60): time to throw, how often a
## rusher gets within 3 yds before the throw (pressure), sacks, throw-aways, hurried throws,
## completion %, yards an attempt.   -- --n=400 [--k=v]
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
	for dl in ["great", "average", "poor"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 33
		var off := Side.side(0, "average", "average", rng)
		var dfn := Side.side(1, "average", dl, rng)
		var st := {"n": 0, "tt": 0.0, "thr": 0, "press": 0, "sack": 0, "away": 0, "hurry": 0, "att": 0, "comp": 0, "yds": 0.0, "net": 0.0, "int": 0, "shed": 0.0}
		for i in n:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			s.setup(off, dfn, Library.play(offs[rng.randi() % offs.size()]), Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var qb: PlaySim.P = s.by_slot["o:QB"]
			var pressed := false
			var guard := 0
			var first_free := -1.0
			while not s.over and guard < 3000:
				s.step()
				guard += 1
				if not s.thrown and s.carrier == qb and not s.qb_runner:
					for e: PlaySim.P in s.dfn:
						if e.group == "DL" and e.blockers.is_empty() and e.engaged == null and s.t > 0.5 and first_free < 0.0:
							first_free = s.t
						if not e.down and e.pos.distance_to(qb.pos) < 3.0:
							pressed = true
			var res := s.result
			st["n"] += 1
			if first_free > 0.0:
				st["shed"] += first_free
			if pressed:
				st["press"] += 1
			if res["sack"]:
				st["sack"] += 1
				st["net"] += float(res["y"])
			elif bool(res["pass"]):
				if s.air.get("away", false):
					st["away"] += 1
				st["att"] += 1
				st["tt"] += float(s.air.get("t0", 0.0))
				st["thr"] += 1
				if s.away_pressure < 0.0 and s.stat.has("throw_open") and pressed:
					st["hurry"] += 1
				if not res["incomplete"] and res["turnover"] == "":
					st["comp"] += 1
					st["yds"] += float(res["y"])
					st["net"] += float(res["y"])
				if res["turnover"] == "int":
					st["int"] += 1
		var N := float(st["n"])
		print("D-line %-7s pressure %3.0f%%  sacks %4.1f%%  throw-aways %3.0f%%  time to throw %.2fs  comp %3.0f%%  %4.1f yds/att  net %4.1f yds/dropback  INT %3.1f%%" % [dl,
			100.0 * st["press"] / N, 100.0 * st["sack"] / N, 100.0 * st["away"] / N, st["tt"] / maxf(st["thr"], 1), 100.0 * st["comp"] / maxf(st["att"], 1),
			st["yds"] / maxf(st["att"], 1), st["net"] / N, 100.0 * st["int"] / maxf(st["att"], 1)])
	print("OK")
	quit()
