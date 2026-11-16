extends SceneTree
## A game cut short by a reload goes back to kickoff: the purse and the robots as they were.
func _init() -> void:
	Library.ensure()
	Career.data = {}
	Career.loaded = false
	Career.ensure()
	var m0 := Career.money(0)
	var r: Dictionary = Career.team(0)["starters"]["QB"]
	var hp0 := float(Robot.ensure_parts(r)["head"]["hp"])
	Career.begin_game()
	Career.add_money(0, 750)                      # paid during the game
	Robot.ensure_parts(r)["head"]["hp"] = 0.0     # and his head knocked off
	Career.save()
	# the page reloads
	Career.loaded = false
	Career.data = {}
	Career.ensure()
	assert(Career.interrupted, "noticed the cut-short game")
	assert(Career.money(0) == m0, "purse back to kickoff: %d vs %d" % [Career.money(0), m0])
	assert(float(Robot.ensure_parts(Career.team(0)["starters"]["QB"])["head"]["hp"]) == hp0, "robots back to kickoff")
	assert(not Career.data.has("in_game"))
	# a finished game sticks
	Career.begin_game()
	Career.add_money(0, 500)
	Career.end_game()
	Career.loaded = false
	Career.data = {}
	Career.ensure()
	assert(Career.money(0) == m0 + 500)
	print("resume_test OK")
	quit()
