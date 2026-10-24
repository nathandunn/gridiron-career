extends SceneTree
## The purse: games pay out, repairs cost, junk is free.
func _init() -> void:
	Library.ensure()
	Career.data = {"version": 1, "fair": false, "teams": [Career.new_team(0, 1), Career.new_team(1, 2)]}
	Career.loaded = true
	var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 7)
	var before := [Career.money(0), Career.money(1)]
	var slips := Career.pay_game(g)
	print("PAY score %s  slips %s  purses %s -> %s" % [g.score, slips, before, [Career.money(0), Career.money(1)]])
	var r: Dictionary = Career.roster(0)["QB"]
	Robot.ensure_parts(r)["lleg"]["hp"] = 0
	Robot.ensure_parts(r)["head"]["hp"] = 50
	print("REPAIR leg %d head %d all %d" % [Career.repair_cost(r, "lleg"), Career.repair_cost(r, "head"), Career.repair_all_cost(r)])
	var m := Career.money(0)
	Robot.bolt_on_junk(r, "lleg")
	print("JUNK free: ", Career.money(0) == m, "  junk then new costs ", Career.repair_cost(r, "lleg"))
	print("BUY ok: ", Career.buy_repair(0, r, "lleg"), " purse ", Career.money(0))
	quit()
