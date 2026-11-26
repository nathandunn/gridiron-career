extends SceneTree
## The returner you name fields the kicks (or punts); a broken one, or none named, goes back to the coach's man.
func _init() -> void:
	Library.ensure()
	Career.loaded = false
	Career.data = {}
	Career.ensure()
	Career.new_season()
	var tm := Career.team(0)
	var pick: Dictionary = tm["bench"].filter(func(b): return String(b["group"]) in ["RB", "WR", "CB", "S"])[0]
	tm["returners"] = {"kick": String(pick["id"]), "punt": ""}
	var g := Game.new()
	g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 4)
	var ok: bool = String(g._returner(0, "kickoff").get("id", "")) == String(pick["id"])
	ok = ok and String(g._returner(0, "punt").get("id", "")) == String(g.best_returner(0).get("id", "-"))
	for k in Robot.PARTS:
		Robot.ensure_parts(pick)[k]["hp"] = 0
	ok = ok and String(g._returner(0, "kickoff").get("id", "")) != String(pick["id"])
	print("returner_pick_test ", "OK" if ok else "FAIL")
	quit()
