extends SceneTree
## Where does a return leave you? Each call on a deep kickoff and on a punt: the average start,
## and how often it is fumbled away.
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 120
	var calls: Array = OS.get_environment("CALLS").split(",") if OS.get_environment("CALLS") != "" else ["middle", "left", "right", "decide", "fair"]
	var kicks: Array = OS.get_environment("KICKS").split(",") if OS.get_environment("KICKS") != "" else ["deep"]
	for what in ["kickoff", "punt"]:
		for kk in (kicks if what == "kickoff" else ["punt"]):
			for call in (calls if what == "kickoff" else calls + ["block"]):
				var tot := 0.0
				var fum := 0
				var blocked := 0
				var cnt := 0
				for i in n:
					var g := Game.new()
					g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 1000 + i)
					var ch := {"return": call, "kickoff": kk}
					if what == "kickoff":
						g.kick_due = {"receiver": 0}
						g.next_snap(ch)
					else:
						g.kick_due = {}
						g.poss = 1
						g.yl = 35.0
						g.down = 4
						g._punt("punt")
						if String(g.return_due.get("mode", "return")) != "return":
							continue
					var snap := g.next_snap(ch)
					if snap.get("kind", "") != "play":
						continue
					var sim := g.make_sim()
					sim.run_to_end()
					var why := String(sim.result.get("why", ""))
					g.finish(sim)
					cnt += 1
					if why == "punt_blocked":
						blocked += 1
					if g.poss != 0:
						fum += 1
						tot += 100.0 - g.yl
					else:
						tot += g.yl
				print("%-8s %-10s %-7s start at own %.1f  lost %d of %d  blocked %d" % [what, kk, call, tot / maxf(cnt, 1), fum, cnt, blocked])
	quit()
