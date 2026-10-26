extends SceneTree
## Season: six weeks against three clubs, pay = damage + result share, a champion. Exhibition: $2,000 each, no pay.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.data = {}
	Career.loaded = false
	Career.ensure()
	assert(not Career.exhibition())
	print("start purse ", Career.money(0), " week ", Career.season()["week"], " opp ", Career.opponent_name(), " (", Career.opponent_coach(), ")")
	var opps := {}
	while not Career.season_over():
		Career.note_kickoff()
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, Career.opponent_coach()), 120.0, randi())
		var bill := Career.damage_bill(0)
		var before := Career.money(0)
		var slips := Career.pay_game(g)
		opps[g.teams[1]["club"]] = int(opps.get(g.teams[1]["club"], 0)) + 1
		print("wk %d %s %d-%d  damage $%d  paid $%d  (%s)" % [Career.season()["week"], g.teams[1]["club"], g.score[0], g.score[1], bill, Career.money(0) - before, slips[0]["lines"]])
		for l in Career.finish_week(g):
			print("   ", l)
		Career.coach_spend(0, true)
	for r in Career.standings():
		print(r["text"])
	assert(opps.size() == 3)
	for k in opps:
		assert(opps[k] == 2)
	print("market ", Career.market().map(func(r): return "%s %s $%d" % [r["group"], r["name"], r["price"]]))
	var m0: int = Career.market()[0]["price"]
	Career.add_money(0, m0)
	var nb: int = Career.team(0)["bench"].size()
	assert(Career.buy_robot(0, Career.market()[0]["id"]))
	assert(Career.team(0)["bench"].size() == nb + 1)
	Career.set_mode("exhibition")
	assert(Career.exhibition())
	print("exhibition purses ", Career.money(0), " / ", Career.money(1), "  rival ", Career.team(1)["name"])
	assert(Career.money(0) == 2000)
	assert(Career.money(1) < 2000)
	Career.set_mode("season")
	Career.new_season()
	assert(Career.season()["week"] == 1 and Career.money(0) == 2000)
	print("OK")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	quit()
