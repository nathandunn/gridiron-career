extends SceneTree
## The championship game: you are top of the table after six weeks, so you play it.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	var sn := Career.season()
	sn["week"] = Career.WEEKS
	Career._set_opponent()
	sn["you"]["w"] = 9
	var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, Career.opponent_coach()), 120.0, 3)
	print(Career.finish_week(g))
	assert(Career.is_final())
	print("label ", Career.week_label(), " badge ", Career.mode_badge(), " opp ", Career.opponent_name())
	var g2 := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, Career.opponent_coach()), 120.0, 4)
	print("final ", g2.score, " ", Career.finish_week(g2))
	assert(Career.season_over())
	print("champion ", Career.season()["champion"], " / over: ", Career.week_label())
	print("OK")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	quit()
