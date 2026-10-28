extends SceneTree
## Inside runs: who makes the tackle on the stuffed ones, and was he blocked?
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Balanced")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var n := 0
	var stuffed := 0
	var by := {}
	var blocked := {"was blocked": 0, "never blocked": 0}
	var gains := []
	while n < 250:
		var g := PlayGen.offense(rng)
		var op: Play = g["play"]
		if op.kind != "run" or String(op.assigns.get("QB", {}).get("kind", "")) == "carry":
			continue
		if absf(float(op.assigns.get("RB", {}).get("gap_x", 0.0))) > 3.0:
			continue
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		s.setup(red, blue, op, Library.play(defs[rng.randi() % defs.size()]), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		var ever := {}
		var k := 0
		while not s.over and k < 600:
			s.step()
			k += 1
			for e in s.dfn:
				if e.engaged != null:
					ever[e.slot] = true
		n += 1
		var res: Dictionary = s.result
		var gain := 0.0 if res["incomplete"] else float(res["y"])
		gains.append(gain)
		if gain <= 1.0 and res["why"] == "tackle":
			stuffed += 1
			var tk := String(res["stat"].get("tackler", "?"))
			var grp: String = Play.SLOT_GROUP.get(tk, tk)
			by[grp] = int(by.get(grp, 0)) + 1
			blocked["was blocked" if ever.has(tk) else "never blocked"] += 1
	gains.sort()
	print("inside runs %d, stuffed (<=1 yd) %d%%, median %.1f" % [n, 100 * stuffed / n, gains[n / 2]])
	print("stuffed by group ", by)
	print("tackler blocked during the play? ", blocked)
	quit()
