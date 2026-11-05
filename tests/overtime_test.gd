extends SceneTree
## Tied after four quarters: sudden-death overtime - a kickoff, and the first score ends it.
func _init() -> void:
	Library.ensure()
	var ot := 0
	var decided := 0
	var still_tied := 0
	for i in 40:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 90.0, 4000 + i)
		if g.quarter <= 4 and (g.line[0] as Array).size() == 4:
			continue
		ot += 1
		var ot0: int = g.line[0][4]
		var ot1: int = g.line[1][4]
		assert(ot0 == 0 or ot1 == 0, "only one side scores in sudden death")
		if ot0 + ot1 > 0:
			decided += 1
			assert(g.winner() >= 0)
			# regulation ended level
			assert(g.score[0] - ot0 == g.score[1] - ot1)
		else:
			still_tied += 1
	print("overtime games %d: decided %d, still tied %d" % [ot, decided, still_tied])
	assert(ot > 0)
	print("OK")
	quit()
