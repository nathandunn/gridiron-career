extends SceneTree
## First and goal: stopped short never earns a new first down.
func _init() -> void:
	Library.ensure()
	var g := Game.new()
	g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 3)
	g.yl = 97.0
	g.to_go = 3.0
	g.down = 1
	var goal := g.yl + g.to_go >= 99.9
	g.yl = clampf(g.yl + 3.2, 0.5, 99.5)
	g._advance_down(3.2, goal)
	print("after a 3.2-yd gain short of a TD: down %d, to go %.1f, at %.1f" % [g.down, g.to_go, g.yl])
	assert(g.down == 2 and g.to_go <= 0.5 + 0.01)
	# a full game: count first downs given inside the 1
	var bad := 0
	for i in 20:
		var gg := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, i)
		for e in gg.log:
			if String(e.get("down_event", "")) == "first_down" and float(e.get("yl", 0)) >= 99.0:
				bad += 1
	print("first downs at the goal line in 20 games: ", bad)
	print("OK")
	quit()
