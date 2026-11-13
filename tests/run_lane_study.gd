extends SceneTree
## Called runs: how often the back crosses the line near the hole he was called to, and yards.
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for kv in OS.get_cmdline_user_args():
		var a := String(kv).trim_prefix("--")
		if "=" in a:
			PlaySim.K[a.get_slice("=", 0)] = float(a.get_slice("=", 1))
	var runs: Array = Library.plays_for("offense").filter(func(x): return (Library.play(x) as Play).kind == "run")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var off := Side.side(0, "average", "average", rng)
	var dfn := Side.side(1, "average", "average", rng)
	var n := 0
	var gen := float(PlaySim.K.get("gen", 0.0)) > 0.0
	var near := 0
	var yds := 0.0
	var behind := 0
	var per := {}
	var off_x := 0.0
	for i in (500 if not gen else 1200):
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		var op: Play = Library.play(runs[rng.randi() % runs.size()])
		if gen:
			var gg := PlayGen.offense(rng)
			op = gg["play"]
			if op.kind != "run":
				continue
		s.setup(off, dfn, op, Library.play(defs[rng.randi() % defs.size()]),
			{"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		var cs: PlaySim.P = s.by_slot.get("o:" + s.carry_slot)
		if cs == null or String(cs.assign.get("gap", "")) == "":
			continue
		var hx := s.ball_x + s.gap_x_of(cs.assign) * s.flip
		var crossed := false
		var guard := 0
		while not s.over and guard < 2000:
			s.step()
			guard += 1
			if not crossed and s.carrier == cs and cs.pos.y >= 0.0:
				crossed = true
				if absf(cs.pos.x - hx) < 2.5:
					near += 1
				var k := op.name if not gen else ("gen inside" if absf(s.gap_x_of(cs.assign)) <= 4.0 else "gen outside")
				per[k] = (per.get(k, []) as Array) + [cs.pos.x - hx]
				if absf(cs.pos.x - hx) >= 2.5 and i < 120:
					print("  %s gap %s hole %.1f crossed %.1f at t=%.2f (handoff %.2f) intent %s" % [op.name, cs.assign.get("gap", ""), hx, cs.pos.x, s.t, s.handoff_t, cs.intent])
		n += 1
		if not crossed:
			behind += 1
			off_x += absf(float(s.result.get("x", 0.0)) - hx)
		yds += float(s.result.get("y", 0.0))
	for k in per:
		var a: Array = per[k]
		var far := a.filter(func(x): return absf(x) >= 2.5).size()
		var m := 0.0
		for x in a:
			m += absf(x)
		print("  %-14s crossed %3d  avg %.1f yds from the hole, %d more than 2.5 away" % [k, a.size(), m / a.size(), far])
	print("stopped behind the line %d, on average %.1f yds sideways from the hole" % [behind, off_x / maxf(behind, 1)])
	print("runs %d: crossed within 2.5 yds of the called hole %.0f%%, %.1f yds/carry" % [n, 100.0 * near / maxf(n, 1), yds / maxf(n, 1)])
	quit()
