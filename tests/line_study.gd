extends SceneTree
## Line study: does a great offensive line beat a bad defensive line (and the other way round)?
## Everyone else is a plain 60 with stock parts; only the five O-linemen and four D-linemen vary.
## Each pairing runs the playbook's runs and passes against random playbook defenses.
const LEVELS := {"great": [85, "Mk III"], "average": [60, "Stock"], "poor": [38, "Junk"]}

func _side(index: int, ol: String, dl: String, rng: RandomNumberGenerator) -> Dictionary:
	var tm := Team.build(index, "Balanced")
	var roster := {}
	var n := 0
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		var r := Robot.make(rng, s, 10 + n, "x%d-%d" % [index, n], false)
		n += 1
		var g := String(r["group"])
		var lvl: Array = [60, "Stock"]
		if g == "OL":
			lvl = LEVELS[ol]
		elif g == "DL":
			lvl = LEVELS[dl]
		for k in r["ratings"]:
			r["ratings"][k] = int(lvl[0])
		for k in Robot.PARTS:
			r["parts"][k] = {"tier": String(lvl[1]), "hp": Robot.TIER_HP[String(lvl[1])]}
		roster[s] = r
	tm["roster"] = roster
	tm["bench"] = []
	tm["fair"] = false
	return tm

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var n := 500
	var offs: Array = Library.plays_for("offense")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	print("CSV,ol,dl,kind,snaps,yds_per_play,median,stuffed_pct,sack_pct,pressure_pct,comp_pct,big_pct")
	for ol in ["great", "average", "poor"]:
		for dl in ["great", "average", "poor"]:
			var off := _side(0, ol, "average", rng)
			var dfn := _side(1, "average", dl, rng)
			var acc := {"run": {"n": 0, "y": 0.0, "g": [], "stuff": 0, "big": 0}, "pass": {"n": 0, "y": 0.0, "g": [], "stuff": 0, "sack": 0, "press": 0, "att": 0, "comp": 0, "big": 0}}
			for i in n:
				var op: Play = Library.play(offs[rng.randi() % offs.size()])
				if op.name == "QB Sneak":
					continue
				var s := PlaySim.new()
				var r := RandomNumberGenerator.new()
				r.seed = rng.randi()
				s.setup(off, dfn, op, Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
				var res := s.run_to_end()
				var k := "run" if op.kind == "run" else "pass"
				var gain := 0.0 if res["incomplete"] else float(res["y"])
				if res["turnover"] != "":
					gain = -10.0
				var a: Dictionary = acc[k]
				a["n"] += 1
				a["y"] += gain
				a["g"].append(gain)
				if gain <= 0.5:
					a["stuff"] += 1
				if gain >= 15.0:
					a["big"] += 1
				if k == "pass":
					if res["sack"]:
						a["sack"] += 1
					if s.away_pressure >= 0.0 or res["sack"] or s.scrambling:
						a["press"] += 1
					if res["pass"]:
						a["att"] += 1
						if not res["incomplete"] and res["turnover"] == "":
							a["comp"] += 1
			for k in ["run", "pass"]:
				var a: Dictionary = acc[k]
				var gs: Array = a["g"]
				gs.sort()
				var nn := maxi(int(a["n"]), 1)
				print("CSV,%s,%s,%s,%d,%.2f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f" % [ol, dl, k, a["n"], a["y"] / nn, gs[gs.size() / 2] if not gs.is_empty() else 0.0,
					100.0 * a["stuff"] / nn, 100.0 * a.get("sack", 0) / nn, 100.0 * a.get("press", 0) / nn,
					100.0 * a.get("comp", 0) / maxf(a.get("att", 0), 1), 100.0 * a["big"] / nn])
	quit()
