extends SceneTree
func _init() -> void:
	Library.ensure()
	var t0 := Time.get_ticks_msec()
	var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 5)
	print("one game %d ms, %d-%d" % [Time.get_ticks_msec() - t0, g.score[0], g.score[1]])
	quit()
