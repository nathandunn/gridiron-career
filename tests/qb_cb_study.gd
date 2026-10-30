extends SceneTree
## QB reads and corner coverage. Everyone a plain 60 with stock parts except the QB's IQ.
## Per pass play: was a receiver wide open (margin > 1.5 for 0.4 s+) while the QB held the
## ball, and did the QB throw to someone that open? And for corners in man coverage: when
## their receiver breaks off (slows from a run), how far past him do they carry (yards
## deeper than him, worst in the next second), and the separation that gives.
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var n := int(PlaySim.K.get("n", 300))
	var offs: Array = Library.plays_for("offense").filter(func(x): return (Library.play(x) as Play).kind != "run")
	var defs: Array = Library.plays_for("defense")
	var verbose := "--v" in OS.get_cmdline_user_args()
	for iq in [45, 72, 99]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var off := Side.side(0, "average", "average", rng)
		var dfn := Side.side(1, "average", "average", rng)
		off["roster"]["QB"]["ratings"]["iq"] = iq
		var st := {"plays": 0, "open_win": 0, "threw_open": 0, "missed": 0, "comp": 0, "att": 0, "sack": 0, "away": 0, "yds": 0.0,
			"miss_why": {}, "breaks": 0, "over": 0.0, "over_big": 0, "sep": 0.0}
		for i in n:
			var s := PlaySim.new()
			var r := RandomNumberGenerator.new()
			r.seed = rng.randi()
			s.setup(off, dfn, Library.play(offs[rng.randi() % offs.size()]), Library.play(defs[rng.randi() % defs.size()]),
				{"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
			var qb: PlaySim.P = s.by_slot["o:QB"]
			var open_for := {}
			var was_wide := {}
			var thrown_to := ""
			var brk := {}      # receiver idx -> {t, cb}
			var guard := 0
			while not s.over and guard < 2000:
				var holding := s.carrier == qb and s.ball_state == "held" and not s.thrown
				if holding and s.t > 0.6:
					for slot in ["WR1", "WR2", "WR3", "TE", "RB"]:
						var rr: PlaySim.P = s.by_slot["o:" + slot]
						var o := s._open(qb, rr)
						open_for[slot] = (float(open_for.get(slot, 0.0)) + PlaySim.DT) if o > 1.5 else 0.0
						if float(open_for[slot]) >= 0.4:
							was_wide[slot] = true
				# corners: watch each receiver's cut (heading turns 50+ degrees at speed)
				for d: PlaySim.P in s.dfn:
					if d.group != "CB":
						continue
					var m: PlaySim.P = d.cover
					if m == null:
						# zone: the receiver nearest him
						var bd := 1e9
						for o: PlaySim.P in s.off:
							if o.group in ["WR", "TE"] and o.pos.distance_to(d.pos) < bd:
								bd = o.pos.distance_to(d.pos)
								m = o
					if m == null or m.hist.size() < 10:
						continue
					var key := "%d-%d" % [d.idx, m.idx]
					var v_old: Vector2 = (m.hist[m.hist.size() - 6] as Vector2) - (m.hist[m.hist.size() - 10] as Vector2)
					var v_new: Vector2 = m.pos - (m.hist[m.hist.size() - 4] as Vector2)
					if not brk.has(key) and m.pos.y > 3.0 and v_old.length() > 0.6 and (v_new.length() < 0.25 or v_old.normalized().dot(v_new.normalized()) < 0.64):
						brk[key] = {"t": s.t, "dir": v_old.normalized(), "over": -99.0, "sep": 0.0, "man": d.cover != null}
					if brk.has(key) and s.t - float(brk[key]["t"]) <= 1.0:
						var b: Dictionary = brk[key]
						# how far he carries on along the receiver's old line, past the receiver
						b["over"] = maxf(float(b["over"]), (d.pos - m.pos).dot(b["dir"]))
						b["sep"] = maxf(float(b["sep"]), d.pos.distance_to(m.pos))
				s.step()
				guard += 1
				if s.thrown and thrown_to == "":
					thrown_to = String(s.stat.get("target", "away"))
			var res := s.result
			st["plays"] += 1
			st["ints"] = int(st.get("ints", 0)) + (1 if res["turnover"] == "int" else 0)
			if bool(res["pass"]) and not s.air.get("away", false) and s.stat.has("throw_open"):
				var mo := float(s.stat["throw_open"])
				var dep := float(s.stat["throw_depth"])
				var mb := "covered(<0)" if mo < 0.0 else ("tight(0-1.5)" if mo < 1.5 else "open(1.5+)")
				var db := "short(<10)" if dep < 10.0 else "deep(10+)"
				var bk := db + " " + mb
				var md: Dictionary = st.get("mb", {})
				var ma: Array = md.get(bk, [0, 0, 0, 0.0])
				md[bk] = [int(ma[0]) + 1, int(ma[1]) + (1 if not res["incomplete"] and res["turnover"] == "" else 0), int(ma[2]) + (1 if res["turnover"] == "int" else 0), float(ma[3]) + (float(res["y"]) if not res["incomplete"] and res["turnover"] == "" else 0.0)]
				st["mb"] = md
			if bool(res["pass"]) and not s.air.get("away", false):
				var pk := String(s.stat.get("path", "rule"))
				var pd: Dictionary = st.get("paths", {})
				var pa: Array = pd.get(pk, [0, 0, 0.0])
				pd[pk] = [int(pa[0]) + 1, int(pa[1]) + (1 if res["turnover"] == "int" else 0), float(pa[2]) + (float(res["y"]) if not res["incomplete"] and res["turnover"] == "" else 0.0)]
				st["paths"] = pd
			if res["sack"]:
				st["sack"] += 1
			if bool(res["pass"]):
				st["att"] += 1
				if not res["incomplete"] and res["turnover"] == "":
					st["comp"] += 1
					st["yds"] += float(res["y"])
			if s.air.get("away", false):
				st["away"] += 1
			if not was_wide.is_empty():
				st["open_win"] += 1
				if was_wide.has(thrown_to):
					st["threw_open"] += 1
				else:
					st["missed"] += 1
					var why := "sack" if res["sack"] else ("away" if s.air.get("away", false) else ("ran" if not bool(res["pass"]) else "threw to covered"))
					st["miss_why"][why] = int(st["miss_why"].get(why, 0)) + 1
					if verbose and iq == 99 and int(st["missed"]) <= 6:
						print("   missed: open %s, threw %s, %s, events %s" % [was_wide.keys(), thrown_to, why, (s.events as Array).slice(0, 14).map(func(e): return e.get("what", e) if e is Dictionary else e)])
			for k in brk:
				var b: Dictionary = brk[k]
				var tag := "man" if b["man"] else "zone"
				st["%s_n" % tag] = int(st.get("%s_n" % tag, 0)) + 1
				st["%s_over" % tag] = float(st.get("%s_over" % tag, 0.0)) + float(b["over"])
				st["%s_sep" % tag] = float(st.get("%s_sep" % tag, 0.0)) + float(b["sep"])
				if float(b["over"]) > 3.0:
					st["%s_big" % tag] = int(st.get("%s_big" % tag, 0)) + 1
				st["breaks"] += 1
				st["over"] += float(b["over"])
				st["sep"] += float(b["sep"])
				if float(b["over"]) > 3.0:
					st["over_big"] += 1
		print("QB IQ %d: comp %.0f%% (%d/%d) %.1f y/att, sacks %.0f%%, throwaways %d | plays with a man wide open %d: threw to him %d, missed %d %s" % [iq,
			100.0 * st["comp"] / maxf(st["att"], 1), st["comp"], st["att"], st["yds"] / maxf(st["att"], 1), 100.0 * st["sack"] / st["plays"], st["away"],
			st["open_win"], st["threw_open"], st["missed"], st["miss_why"]])
		var mbs: Dictionary = st.get("mb", {})
		var ks := mbs.keys()
		ks.sort()
		for k2 in ks:
			var a2: Array = mbs[k2]
			print("     %-24s %4d throws  comp %3.0f%%  int %4.1f%%  %5.1f yds/throw" % [k2, a2[0], 100.0 * a2[1] / a2[0], 100.0 * a2[2] / a2[0], a2[3] / a2[0]])
		print("   interceptions %d, by path [throws, ints, yds]: %s" % [int(st.get("ints", 0)), st.get("paths", {})])
		for tag in ["man", "zone"]:
			var nn := float(st.get("%s_n" % tag, 0))
			print("   corners (%s) at a cut, %d cuts: carry on past him %.1f yds avg, >3 yds %.0f%%, worst separation in the next second %.1f" % [tag, int(nn),
				float(st.get("%s_over" % tag, 0.0)) / maxf(nn, 1), 100.0 * float(st.get("%s_big" % tag, 0)) / maxf(nn, 1), float(st.get("%s_sep" % tag, 0.0)) / maxf(nn, 1)])
	print("OK")
	quit()
