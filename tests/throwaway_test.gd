extends SceneTree
## How often QBs throw it away, and how close the nearest rusher was when they did.
func _init() -> void:
	Library.ensure()
	for kv in OS.get_cmdline_user_args():
		if kv.begins_with("--k="):
			for pair in kv.substr(4).split(","):
				PlaySim.K[pair.get_slice(":", 0)] = float(pair.get_slice(":", 1))
	var passes := 0
	var away := 0
	var clean := 0
	var kinds := {}
	var miss_d: Array = []
	var why := {}
	for s in 12:
		var g := Game.new()
		g.setup(Team.build(0, "Balanced", {}, "generated"), Team.build(1, "Balanced", {}, "generated"), 300.0, 300 + s)
		var guard := 0
		while not g.over and guard < 400:
			guard += 1
			var snap := g.next_snap()
			if snap["kind"] != "play":
				continue
			var sim := g.make_sim()
			sim.run_to_end()
			if sim.pass_play:
				passes += 1
			var oob := true
			for ev in sim.events:
				var tx := String(ev["text"])
				if tx.begins_with("nobody there"):
					var dd := float(tx.get_slice(" ", tx.get_slice_count(" ") - 3))
					miss_d.append(dd)
				for k in ["nobody there", "broken up", "dropped", "caught", "INTERCEPTED"]:
					if tx.begins_with(k):
						kinds[k] = int(kinds.get(k, 0)) + 1
						oob = false
			if sim.thrown and sim.result.get("incomplete", false) and oob and sim.away_pressure < 0.0:
				kinds["sailed out of bounds"] = int(kinds.get("sailed out of bounds", 0)) + 1
			if sim.away_pressure >= 0.0:
				away += 1
				if sim.away_pressure > 3.0:
					clean += 1
			if not sim.miss_info.is_empty():
				var mk := "%s d0=%.1f T=%.2f maxrun=%.1f end=%.1f v=%.1f" % [sim.miss_info["slot"], sim.miss_info["d0"], sim.miss_info["T"], sim.miss_info["max"], sim.miss_info["d"], sim.miss_info["spd"]]
				why[mk] = int(why.get(mk, 0)) + 1
			g.finish(sim)
	print("THROWAWAYS %d of %d pass plays (%.0f%%), %d with no rusher within 3 yards" % [away, passes, 100.0 * away / maxf(passes, 1), clean])
	print("THROWS ", kinds)
	var ks := why.keys()
	ks.sort_custom(func(a, b): return why[a] > why[b])
	for k in ks.slice(0, 10):
		print("  MISS ", k, " ", why[k])
	miss_d.sort()
	if not miss_d.is_empty():
		print("MISSED BY (yd) median %.1f  p25 %.1f  p75 %.1f  p90 %.1f" % [miss_d[miss_d.size() / 2], miss_d[miss_d.size() / 4], miss_d[miss_d.size() * 3 / 4], miss_d[miss_d.size() * 9 / 10]])
	quit()
