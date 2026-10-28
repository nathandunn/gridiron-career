extends SceneTree
## With an empty purse nothing can be bought.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	Career.add_money(0, -Career.money(0))
	var r: Dictionary = Career.roster(0)["WR1"]
	Robot.ensure_parts(r)["lleg"]["hp"] = 0
	var before := JSON.stringify(r)
	print("purse ", Career.money(0))
	print("upgrade ", Career.buy_upgrade(0, r, "rarm"), " repair ", Career.buy_repair(0, r, "lleg"), " armour ", Career.buy_armor(0, r))
	print("market ", Career.buy_robot(0, String(Career.market()[0]["id"])))
	for f in Career.FOCUS:
		Career.coach_spend(0, true, 400, f)
	Career.buy_junk(0, r, "lleg")
	print("after junk: purse ", Career.money(0), " leg ", r["parts"]["lleg"])
	print("robot changed other than junk: ", JSON.stringify(r) != before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	quit()
