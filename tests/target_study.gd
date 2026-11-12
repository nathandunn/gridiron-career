extends SceneTree
## Who does the QB throw to, and who is covering him? Everyone an average robot.
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var n := 600
	var offs: Array = Library.plays_for("offense").filter(func(x): return (Library.play(x) as Play).kind != "run")
	var defs: Array = Library.plays_for("defense")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var off := Side.side(0, "average", "average", rng)
	var dfn := Side.side(1, "average", "average", rng)
	var tgt := {}
	var cover := {}
	var routes := {}
	var firsts := {}
	for i in n:
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		var op: Play = Library.play(offs[rng.randi() % offs.size()])
		s.setup(off, dfn, op, Library.play(defs[rng.randi() % defs.size()]),
			{"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		for slot in ["WR1", "WR2", "WR3", "TE", "RB"]:
			var rr: PlaySim.P = s.by_slot.get("o:" + slot)
			if rr != null and not rr.route.is_empty():
				routes[slot] = float(routes.get(slot, 0.0)) + absf((rr.route[-1] as Vector2).y) / n
		if not s.reads.is_empty():
			firsts[String(s.reads[0])] = int(firsts.get(String(s.reads[0]), 0)) + 1
		var guard := 0
		var who := ""
		while not s.over and guard < 2000:
			if s.thrown and who == "":
				who = String(s.stat.get("target", ""))
				var rp: PlaySim.P = s.by_slot.get("o:" + who)
				if rp != null:
					var near := ""
					var bd := 1e9
					for d: PlaySim.P in s.dfn:
						if d.pos.distance_to(rp.pos) < bd:
							bd = d.pos.distance_to(rp.pos)
							near = d.slot
					cover[near] = int(cover.get(near, 0)) + 1
			s.step()
			guard += 1
		if who != "":
			tgt[who] = int(tgt.get(who, 0)) + 1
	print("reads first: ", firsts)
	print("targets: ", tgt)
	print("average route depth: ", routes)
	print("nearest defender at the throw: ", cover)
	quit()
