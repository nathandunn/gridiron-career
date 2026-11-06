extends SceneTree
## Every kind of punt is played: a coffin corner goes out at the sideline, a pooch is downed
## deep, a normal one is run back; the receiving side always ends with the ball.
func _init() -> void:
	Library.ensure()
	var out := {}
	for kind in ["punt", "coffin", "pooch"]:
		for i in 12:
			var g := Game.new()
			g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 50 + i)
			g.kick_due = {}
			g.return_due = {}
			g.poss = 0
			g.yl = 55.0
			g.down = 4
			g.to_go = 8.0
			g._punt(kind)
			var snap := g.next_snap({})
			assert(snap["kind"] == "play" and snap.has("return"))
			var sim := g.make_sim()
			var guard := 0
			while not sim.over and guard < 4000:
				sim.step()
				guard += 1
			var e := g.finish(sim)
			assert(g.poss == 1, "the receiving side has it")
			var k := "%s -> %s" % [kind, String(sim.result["why"])]
			var a: Array = out.get(k, [0, 0.0])
			a[0] += 1
			a[1] += g.yl
			out[k] = a
	for k in out:
		print("%-24s x%d  ball at their %.0f on average" % [k, out[k][0], out[k][1] / out[k][0]])
	print("OK")
	quit()
