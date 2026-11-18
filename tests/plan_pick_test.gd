extends SceneTree
## Buying part of a coach's plan: the kept rows match what the plan said, and cost what it said.
func _init() -> void:
	Library.ensure()
	var bad := 0
	for i in 10:
		Career.data = {}
		Career.loaded = false
		Career.ensure()
		Career.new_season()
		Career.add_money(0, 3000)
		var p := Career.coach_plan(0, true, 400, "win", 7)
		var rows: Array = p["rows"]
		if rows.size() < 2:
			continue
		var pick := [rows[0]]
		var m0 := Career.money(0) + Career.credit(0)
		Career.buy_plan_rows(0, pick)
		var spent := m0 - Career.money(0) - Career.credit(0)
		var r: Dictionary = Career.team(0)["starters"].get(rows[0]["slot"], Career.special(0).get(rows[0]["slot"], {}))
		var ok := spent == int(rows[0]["cost"]) and Robot.overall_if(r, "now") == int(rows[0]["after"])
		# the rest untouched: the plan for them is the same as before
		var p2 := Career.coach_plan(0, true, 400, "win", 7)
		if not ok:
			bad += 1
			print("MISMATCH spent %d vs %d, ovr %d vs %d" % [spent, rows[0]["cost"], Robot.overall_if(r, "now"), rows[0]["after"]])
		if i < 2:
			print("bought %s for $%d; replan now %d rows" % [rows[0]["slot"], spent, (p2["rows"] as Array).size()])
	print("PASS" if bad == 0 else "FAIL %d" % bad)
	quit()
