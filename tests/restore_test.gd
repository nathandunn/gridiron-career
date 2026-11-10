extends SceneTree
## Fix (where it's at) and Restore (to original) after a Mk III arm is lost and a junk spare goes on.
func _init() -> void:
	Library.ensure()
	Career.data = {}
	Career.loaded = false
	Career.ensure()
	Career.add_money(0, 50000)
	var r: Dictionary = Career.team(0)["starters"]["WR1"]
	var p := Robot.ensure_parts(r)
	p["larm"] = {"tier": "Mk III", "hp": 0}
	p["rleg"] = {"tier": "Junk", "hp": 10}          # junk he started with, worn
	assert(Career.fix_cost(r, "larm") == Career.PART_PRICE["larm"])
	assert(Career.restore_cost(r, "larm") == Career.upgrade_price("larm", "Mk III"))
	assert(Career.fix_cost(r, "rleg") > 0)          # worn junk is fixable now (it kept its "!" before)
	Robot.bolt_on_junk(r, "larm")
	assert(Robot.original_tier(r, "larm") == "Mk III")
	assert(Career.restore_cost(r, "larm") == Career.upgrade_price("larm", "Mk III"))
	Career.buy_fix(0, r, "rleg")
	assert(String(p["rleg"]["tier"]) == "Junk" and float(p["rleg"]["hp"]) == 50.0)
	Career.buy_restore(0, r, "larm")
	assert(String(p["larm"]["tier"]) == "Mk III" and float(p["larm"]["hp"]) == 180.0 and not p["larm"].has("spare"))
	print("restore_test OK  fix arm $%d, restore Mk III arm $%d" % [Career.PART_PRICE["larm"], Career.upgrade_price("larm", "Mk III")])
	quit()
