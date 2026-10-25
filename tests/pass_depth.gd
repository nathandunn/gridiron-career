extends SceneTree
## Where passes go and how they end: playbook offense vs generated (hand) offense, by air depth.
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Balanced")
	var offs: Array = Library.plays_for("offense")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for src in ["playbook", "generated"]:
		var b := {}
		var away := 0
		var sacks := 0
		var snaps := 0
		var passes := 0
		for i in 1500:
			var op: Play
			if src == "playbook":
				op = Library.play(offs[rng.randi() % offs.size()])
			else:
				op = PlayGen.offense(rng)["play"]
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			s.setup(red, blue, op, Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var res := s.run_to_end()
			snaps += 1
			if s.away_pressure >= 0.0:
				away += 1
			if s.stat.has("air_y"):
				passes += 1
				var y := float(s.stat["air_y"])
				var k := "behind" if y < 0 else ("0-5" if y < 5 else ("5-15" if y < 15 else ("15-25" if y < 25 else "25+")))
				var e: Dictionary = b.get(k, {"n": 0, "comp": 0, "yds": 0.0, "covered": 0, "cov_comp": 0, "out": 0})
				e["n"] += 1
				var covered := float(s.stat.get("def_d", 99)) < 2.0
				if covered:
					e["covered"] += 1
				if not res["incomplete"] and res["turnover"] == "":
					e["comp"] += 1
					e["yds"] += float(res["y"])
					if covered:
						e["cov_comp"] += 1
				if absf(float(s.air.get("to", Vector2.ZERO).x)) > PlaySim.SIDELINE:
					e["out"] += 1
				b[k] = e
			elif String(res.get("why", "")) == "sack":
				sacks += 1
		print("== %s: %d snaps, %d passes, %d throwaways, %d sacks" % [src, snaps, passes, away, sacks])
		for k in ["behind", "0-5", "5-15", "15-25", "25+"]:
			if b.has(k):
				var e: Dictionary = b[k]
				print("  %-6s %4d thrown  comp %3d%%  yds/comp %5.1f  covered %3d%% (comp when covered %3d%%)  out of bounds %d" % [k, e["n"], 100 * e["comp"] / e["n"], e["yds"] / maxf(e["comp"], 1), 100 * e["covered"] / e["n"], 100 * e["cov_comp"] / maxi(e["covered"], 1), e["out"]])
	quit()
