extends SceneTree
## How long blocks last: every engagement's length (until the defender gets off it, or the play
## ends), for pass and run plays; and how many sacks / stuffed runs / yards that gives.
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var n := int(PlaySim.K.get("n", 300))
	var offs: Array = Library.plays_for("offense").filter(func(x): return x != "QB Sneak")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var lv := ["poor", "average", "great"]
	var off := Side.side(0, lv[int(PlaySim.K.get("ol", 1))], "average", rng)
	var dfn := Side.side(1, "average", lv[int(PlaySim.K.get("dl", 1))], rng)
	var acc := {"pass": {"d": [], "open": [], "n": 0, "y": 0.0, "sack": 0}, "run": {"d": [], "open": [], "n": 0, "y": 0.0, "stuff": 0}}
	for i in n:
		var op: Play = Library.play(offs[rng.randi() % offs.size()])
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		s.setup(off, dfn, op, Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		var k := "run" if op.kind == "run" else "pass"
		var start := {}
		var guard := 0
		while not s.over and guard < 3000:
			s.step()
			guard += 1
			if s.thrown and PlaySim.K.get("whole", 0.0) <= 0.0:
				if not start.has("_end"):
					start["_end"] = s.t    # once the ball is out, pass blocks stop mattering
				continue
			for e: PlaySim.P in s.dfn:
				var held := not e.blockers.is_empty()
				if held and not start.has(e.idx):
					start[e.idx] = s.t
				elif not held and start.has(e.idx):
					acc[k]["d"].append(s.t - float(start[e.idx]))
					start.erase(e.idx)
		for idx in start:
			if String(str(idx)) == "_end":
				continue
			acc[k]["open"].append(float(start.get("_end", s.t)) - float(start[idx]))   # still held when it ended
		var a: Dictionary = acc[k]
		a["n"] += 1
		var res := s.result
		a["y"] += 0.0 if res["incomplete"] else float(res["y"])
		if res["sack"]:
			a["sack"] = int(a.get("sack", 0)) + 1
		if k == "run" and float(res["y"]) <= 0.0:
			a["stuff"] = int(a.get("stuff", 0)) + 1
	for k in ["pass", "run"]:
		var a: Dictionary = acc[k]
		var d: Array = a["d"]
		d.sort()
		var o: Array = a["open"]
		o.sort()
		var long_o := o.filter(func(x): return x > 3.0).size()
		print("%s: %d plays, %.1f yds/play, %s | blocks beaten %d (median %.1fs, 90%% %.1fs) | still held at the end %d (median %.1fs, held 3s+ %d)" % [k, a["n"], a["y"] / maxf(a["n"], 1),
			("sacks %.0f%%" % (100.0 * int(a.get("sack", 0)) / maxf(a["n"], 1))) if k == "pass" else ("stuffed %.0f%%" % (100.0 * int(a.get("stuff", 0)) / maxf(a["n"], 1))),
			d.size(), d[d.size() / 2] if not d.is_empty() else 0.0, d[int(d.size() * 0.9)] if not d.is_empty() else 0.0,
			o.size(), o[o.size() / 2] if not o.is_empty() else 0.0, long_o])
	print("OK")
	quit()
