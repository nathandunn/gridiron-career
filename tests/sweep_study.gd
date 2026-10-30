extends SceneTree
## Runs by type, everyone a plain 60: yards per carry, how often 10+, and how the defense
## reacts to a sweep (time until the first defender is within 2 yards of the carrier, and how
## many defenders are within 5 yards of him when he turns the corner).
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var n := int(PlaySim.K.get("n", 250))
	var defs: Array = Library.plays_for("defense")
	for pn in ["Toss Sweep", "Inside Zone", "Power", "Draw"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var off := Side.side(0, "average", "average", rng)
		var dfn := Side.side(1, "average", "average", rng)
		var g: Array = []
		var first_t := 0.0
		var near_n := 0.0
		var cnt := 0
		var by_def := {}
		for i in n:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			var dn: String = defs[rng.randi() % defs.size()]
			s.setup(off, dfn, Library.play(pn), Library.play(dn), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0, "set_edge": PlaySim.K.get("set_edge", 0.0) > 0.0}, r)
			var ft := -1.0
			var corner := -1
			var guard := 0
			while not s.over and guard < 2000:
				s.step()
				guard += 1
				if s.handed and s.carrier != null and s.carrier.side == 0:
					var c: PlaySim.P = s.carrier
					var near := 0
					for d: PlaySim.P in s.dfn:
						var dd := d.pos.distance_to(c.pos)
						if dd < 2.0 and ft < 0.0:
							ft = s.t - s.handoff_t
						if dd < 5.0:
							near += 1
					if corner < 0 and c.pos.y > 0.0:
						corner = near
			var y := float(s.result["y"]) if s.result["turnover"] == "" else -10.0
			g.append(y)
			by_def[dn] = (by_def.get(dn, []) as Array) + [y]
			if ft >= 0.0:
				first_t += ft
				cnt += 1
			near_n += maxf(corner, 0)
		g.sort()
		var tot := 0.0
		var big := 0
		for y in g:
			tot += y
			if y >= 10.0:
				big += 1
		var parts: Array = []
		for dn in by_def:
			var a: Array = by_def[dn]
			var su := 0.0
			for y in a:
				su += y
			parts.append("%s %.1f" % [dn, su / a.size()])
		print("%s: %.1f ypc, median %.1f, 10+ %.0f%% | first defender within 2 yds after %.2fs, defenders within 5 yds at the line %.1f" % [pn, tot / n, g[n / 2], 100.0 * big / n, first_t / maxf(cnt, 1), near_n / n])
		print("    by defense: ", ", ".join(parts))
		print("    longest: ", g.slice(g.size() - 15).map(func(x): return int(x)))
	print("OK")
	quit()
