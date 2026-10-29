extends SceneTree
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	Career.spend(0, 1750)
	Career.season()["week"] = Career.WEEKS + 2
	Career.season()["champion"] = "Iron Hogs"
	assert(Career.season_over())
	Career.new_season()
	print("new season ", Career.money(0), " week ", Career.season()["week"], " last ", Career.data.get("last_champion"))
	assert(Career.money(0) == 2000)
	# an old save without a season gets one, with $2,000
	Career.data.erase("season")
	Career.data["money"][0] = 250
	Career.save()
	Career.loaded = false
	Career.data = {}
	Career.ensure()
	print("migrated ", Career.money(0))
	assert(Career.money(0) == 2000)
	print("OK")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	quit()
