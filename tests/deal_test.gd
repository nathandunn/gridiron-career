extends SceneTree
## Best lineups (the worst sit), scrapping, selling and trading robots.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	var tm := Career.team(0)
	# every bench man is no better than the starters at his position
	var bad := 0
	for b in tm["bench"]:
		var g := String(b["group"])
		for s in Career._slots_of(g):
			if Career._lineup_score(b, g) > Career._lineup_score(tm["starters"][s], g):
				bad += 1
	print("bench men better than a starter: ", bad)
	assert(bad == 0)
	# scrap a bench robot
	var m0 := Career.money(0)
	var b0: Dictionary = tm["bench"][0]
	var sv := Career.scrap_value(b0)
	assert(Career.scrap(0, b0) == sv and Career.money(0) == m0 + sv)
	print("scrapped for $", sv)
	# sell a starter to a club: his place is filled
	var clubs := Career.dealers()
	assert(not clubs.is_empty())
	var c: Dictionary = clubs[0]
	c["money"] = 99999
	var wr: Dictionary = tm["starters"]["WR1"]
	var why := Career.cant_part_with(0, wr)
	print("selling WR1 %s: %s" % [wr["name"], "ok" if why == "" else why])
	if why == "":
		var offer := Career.sell_offer(wr, c)
		assert(Career.sell_to(0, wr, c))
		assert(not (tm["starters"]["WR1"] as Dictionary).is_empty())
		assert(c["bench"].has(wr) or c["starters"].values().has(wr))
		print("sold for $%d; WR1 now %s" % [offer, tm["starters"]["WR1"]["name"]])
	# the only QB can't go
	var qb_ok := Career.cant_part_with(0, tm["starters"]["QB"])
	print("QB: ", qb_ok)
	# trade a bench LB for their best LB
	Career.add_money(0, 50000)
	var lb: Dictionary = {}
	for b in tm["bench"]:
		if String(b["group"]) == "LB":
			lb = b
	if not lb.is_empty():
		var theirs: Dictionary = c["starters"]["MLB"]
		var gap := Career.trade_gap(lb, theirs)
		assert(Career.trade(0, lb, c, theirs))
		var have: bool = tm["starters"].values().has(theirs) or tm["bench"].has(theirs)
		assert(have)
		print("traded %s for %s (+$%d)" % [lb["name"], theirs["name"], gap])
	# every slot still filled
	for s in tm["starters"]:
		assert(not (tm["starters"][s] as Dictionary).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	print("OK")
	quit()
