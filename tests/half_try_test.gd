extends SceneTree
## A touchdown as the clock runs out still gets its try: at the half (then the second-half
## kickoff), and at the end of regulation when the try can change the result.
func _game() -> Game:
	var g := Game.new()
	g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 5)
	g.kick_due = {}
	return g


func _init() -> void:
	Library.ensure()
	# end of the half: pick six on the last play
	var g := _game()
	g.quarter = 2
	g.clock = 0.4
	g._touchdown(1)
	g._tick(6.0, true)
	assert(g.quarter == 3 and not g.try_due.is_empty() and g.kick_due.is_empty(), "the try comes before the second-half kickoff")
	g._after_try(1)
	assert(int(g.kick_due.get("receiver", -1)) == 1 - g.opened, "then the second half kicks off as it should")
	# end of regulation, down 12-7: the touchdown makes it 13-12 - the try still matters
	g = _game()
	g.quarter = 4
	g.clock = 0.4
	g.score = [7, 12]
	g._touchdown(0)
	g._tick(6.0, true)
	assert(not g.over and not g.try_due.is_empty(), "a try that can decide it is played")
	g._after_try(0)
	assert(g.over, "then the final whistle")
	# down 12-6: TD ties it 12-12; a missed try sends it to overtime
	g = _game()
	g.quarter = 4
	g.clock = 0.4
	g.score = [6, 12]
	g._touchdown(0)
	g._tick(6.0, true)
	assert(not g.over and not g.try_due.is_empty())
	g.try_due = {}
	g._after_try(0)
	assert(not g.over and g.quarter == 5 and not g.kick_due.is_empty(), "tied after the try: overtime")
	# up big: a try that can't matter isn't played
	g = _game()
	g.quarter = 4
	g.clock = 0.4
	g.score = [20, 3]
	g._touchdown(0)
	g._tick(6.0, true)
	assert(g.over and g.try_due.is_empty())
	print("half_try_test OK")
	quit()
