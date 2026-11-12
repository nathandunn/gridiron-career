extends SceneTree
## Pay during the game adds up to the same as pay at the end.
func _init() -> void:
	Library.ensure()
	for live in [false, true]:
		Career.data = {}
		Career.loaded = false
		Career.ensure()
		var before := [Career.money(0), Career.money(1)]
		var g := Game.new()
		g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 180.0, 77)
		var guard := 0
		var live_sum := [0, 0]
		while not g.over and guard < 400:
			var snap := g.next_snap()
			if snap["kind"] == "play":
				var sim := g.make_sim()
				sim.run_to_end()
				g.finish(sim)
			if live:
				for t in 2:
					for x in Career.pay_live(g, t):
						live_sum[t] += int(x[1])
			guard += 1
		var slips := Career.pay_game(g)
		for t in 2:
			var got := Career.money(t) - int(before[t])
			# the rival also repairs and shops after the game: compare the pay itself
			assert(t == 1 or got == int(slips[t]["total"]), "team %d live=%s: purse +%d vs slip %d" % [t, live, got, int(slips[t]["total"])])
		print("live=%s ok: slip %d, paid during %d" % [live, int(slips[0]["total"]), live_sum[0]])
	quit()
