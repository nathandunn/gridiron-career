extends SceneTree
## How open are the receivers against each coverage? At the throw: the target's separation (nearest
## defender), how often he is wide open (5+ yds), how often any WR is, and what the pass gains.
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 400
	var offs: Array = Library.plays_for("offense").filter(func(x): return (Library.play(x) as Play).kind != "run")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var off := Side.side(0, "average", "average", rng)
	var dfn := Side.side(1, "average", "average", rng)
	var defs := {}
	for nm in Library.plays_for("defense"):
		defs[nm] = [Library.play(nm)]
	# the dealt families too
	var gr := RandomNumberGenerator.new()
	gr.seed = 9
	for i in 400:
		var d: Dictionary = PlayGen.defense(gr)
		var fam := "dealt " + String((d["play"] as Play).about).split(":")[0]
		if not defs.has(fam):
			defs[fam] = []
		defs[fam].append(d["play"])
	for nm in defs:
		if OS.get_environment("ONLY") != "" and not (nm in OS.get_environment("ONLY").split(",")):
			continue
		var sep := 0.0
		var wide := 0
		var any_wide := 0
		var throws := 0
		var yds := 0.0
		var comp := 0
		for i in n:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			var dp: Play = defs[nm][rng.randi() % defs[nm].size()]
			s.setup(off, dfn, Library.play(offs[rng.randi() % offs.size()]), dp,
				{"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var guard := 0
			var done := false
			while not s.over and guard < 2000:
				if s.thrown and not done:
					done = true
					throws += 1
					var who := String(s.stat.get("target", ""))
					var best_any := 0.0
					for slot in ["WR1", "WR2", "WR3", "TE", "RB"]:
						var rp: PlaySim.P = s.by_slot.get("o:" + slot)
						if rp == null:
							continue
						var bd := 1e9
						for d: PlaySim.P in s.dfn:
							bd = minf(bd, d.pos.distance_to(rp.pos))
						if slot.begins_with("WR"):
							best_any = maxf(best_any, bd)
						if slot == who:
							if bd >= 5.0 and OS.get_environment("DIAG") == nm and i < 40:
								var nd := ""
								var ndd := 1e9
								for d: PlaySim.P in s.dfn:
									if d.pos.distance_to(rp.pos) < ndd:
										ndd = d.pos.distance_to(rp.pos)
										nd = "%s(%s) at %.0f,%.0f" % [d.slot, d.assign.get("zone", d.assign.get("kind", "")), d.pos.x, d.pos.y]
								print("  open %s at %.0f,%.0f t=%.1f  nearest %s %.1f" % [slot, rp.pos.x, rp.pos.y, s.t, nd, ndd])
						if slot == who:
							sep += bd
							if bd >= 5.0:
								wide += 1
					if best_any >= 5.0:
						any_wide += 1
				s.step()
				guard += 1
			if done:
				yds += float(s.result.get("y", 0.0))
		var t := maxf(throws, 1)
		print("%-28s throws %3d  target sep %.1f  target wide-open %2d%%  a WR wide-open %2d%%  yds/throw %.1f" % [nm, throws, sep / t, int(100.0 * wide / t), int(100.0 * any_wide / t), yds / t])
	quit()
