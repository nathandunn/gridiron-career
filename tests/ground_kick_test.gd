extends SceneTree
## Squib and onside kicks are played out on the turf: where they end up and who has the ball.
func _init() -> void:
	Library.ensure()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			PlaySim.K[kv[0]] = float(kv[1])
	var verbose := "--v" in OS.get_cmdline_user_args()
	for kind in ["squib", "onside"]:
		var out := {}
		var start := 0.0
		var hops := 0
		var n := 150
		for i in n:
			var g := Game.new()
			g.setup(Team.build(0, "Balanced"), Team.build(1, "By the Numbers"), 300.0, 500 + i)
			g._kickoff(0)
			g.next_snap({"kickoff": kind})
			var snap := g.next_snap({"return": "middle"})
			assert(String(snap["kind"]) == "play")
			var sim := g.make_sim()
			var was_up := false
			var guard := 0
			while not sim.over and guard < 3000:
				sim.step()
				guard += 1
				if sim.ball_state == "bounce":
					var up := sim.ball_h > 0.3
					if up and not was_up:
						hops += 1
					was_up = up
			if verbose and i < 25:
				var st: Dictionary = sim.stat
				print("    %s field_y %.1f by %s/%s t %.1f end %s y %.1f" % [kind, float(st.get("field_y", 99)), st.get("fielder", "-"), st.get("kick_rec", "-"), sim.t, sim.result["why"], float(sim.result["y"])])
			var e := g.finish(sim)
			var key := String(e.get("why", "?"))
			if String(e.get("text", "")).find("RECOVER") >= 0:
				key = "kicking side recovers"
			elif key in ["tackle", "out", "whistle", "down", "td"]:
				key = "fielded + returned"
			out[key] = int(out.get(key, 0)) + 1
			if g.poss == 0:
				start += g.yl
			if i < 3:
				print("  ", e.get("text", ""))
		print("%s: %s  receiving start avg %.1f  hops/kick %.1f" % [kind, out, start / maxf(n - int(out.get("kicking side recovers", 0)), 1), float(hops) / n])
	print("OK")
	quit()
