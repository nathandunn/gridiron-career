extends SceneTree
## Generated runs by where they aim: how they do.
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--commit="):
			PlaySim.K["commit"] = float(a.substr(9))
		if a.begins_with("--pull="):
			PlaySim.K["gen_pull"] = float(a.substr(7))
		if a.begins_with("--ns="):
			PlaySim.K["near_shed"] = float(a.substr(5))
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Balanced")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var b := {}
	var n := 0
	while n < 600:
		var g := PlayGen.offense(rng)
		var op: Play = g["play"]
		if op.kind != "run":
			continue
		var qb: Dictionary = op.assigns.get("QB", {})
		var rb: Dictionary = op.assigns.get("RB", {})
		var hole := float(rb.get("gap_x", qb.get("gap_x", 0.0)))
		var keeper: bool = String(qb.get("kind", "")) == "carry"
		var k := ("keeper " if keeper else "") + ("inside |x|<2" if absf(hole) < 2.0 else ("off tackle 2-6" if absf(hole) < 6.0 else "outside 6+"))
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		s.setup(red, blue, op, Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		var res := s.run_to_end()
		var gain := 0.0 if res["incomplete"] else float(res["y"])
		var e: Dictionary = b.get(k, {"n": 0, "y": 0.0, "neg": 0, "big": 0, "g": []})
		e["n"] += 1
		e["y"] += gain
		e["g"].append(gain)
		if gain <= 0.5:
			e["neg"] += 1
		if gain >= 8.0:
			e["big"] += 1
		b[k] = e
		n += 1
	for k in b:
		var e: Dictionary = b[k]
		var gs: Array = e["g"]
		gs.sort()
		print("%-24s n %3d  mean %5.1f  median %5.1f  stopped (<=0.5) %3d%%  8+ %3d%%" % [k, e["n"], e["y"] / e["n"], gs[gs.size() / 2], 100 * e["neg"] / e["n"], 100 * e["big"] / e["n"]])
	quit()
