extends SceneTree
## The coach's plan changes nothing, and buying it buys exactly what it showed.
func _init() -> void:
	for focus in ["db", "", "qb", "st"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
		Career.loaded = false
		Career.ensure()
		Career.add_money(0, 3000)
		var m0 := Career.money(0)
		var plan := Career.coach_plan(0, true, 400, focus, 77)
		assert(Career.money(0) == m0)
		var plan2 := Career.coach_plan(0, true, 400, focus, 77)
		assert(JSON.stringify(plan) == JSON.stringify(plan2))   # nothing changed
		var sum := 0
		for r in plan["rows"]:
			sum += int(r["cost"])
		assert(sum == int(plan["cost"]))
		Career.coach_spend(0, true, 400, focus, 77)
		assert(Career.money(0) + mini(Career.credit(0), 0) == m0 - int(plan["cost"]) or Career.money(0) <= m0)
		for r in plan["rows"]:
			var rb: Dictionary = Career.team(0)["starters"].get(r["slot"], Career.special(0).get(r["slot"], {}))
			assert(Robot.overall_if(rb, "now") == int(r["after"]))
		print("%s: %d robots, $%d, purse %d -> %d" % [focus if focus != "" else "best", plan["rows"].size(), plan["cost"], m0, Career.money(0)])
		if focus == "db":
			for r in plan["rows"]:
				print("   ", r["slot"], " ", r["before"], "->", r["after"], " $", r["cost"], " ", r["parts"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	print("OK")
	quit()
