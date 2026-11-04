extends SceneTree
## The next season keeps every club's robots and adds $5,000; only a new career is levelled.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	var my_ids: Array = (Career.data["teams"][0]["starters"] as Dictionary).values().map(func(r): return r["id"])
	var club_ids: Array = (Career.season()["clubs"][1]["starters"] as Dictionary).values().map(func(r): return r["id"])
	var m0 := Career.money(0)
	Career.season()["week"] = Career.WEEKS + 2
	Career.season()["champion"] = "Somebody"
	Career.next_season()
	assert(Career.season()["week"] == 1 and Career.season()["results"].is_empty())
	assert(Career.money(0) == m0 + Career.SEASON_MONEY)
	assert((Career.data["teams"][0]["starters"] as Dictionary).values().map(func(r): return r["id"]) == my_ids)
	assert((Career.season()["clubs"][1]["starters"] as Dictionary).values().map(func(r): return r["id"]) == club_ids)
	print("purse %d -> %d, same robots, clubs %s" % [m0, Career.money(0), Career.season()["clubs"].map(func(c): return "%s $%d" % [c["name"], c["money"]])])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	print("OK")
	quit()
