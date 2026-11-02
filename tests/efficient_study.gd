extends SceneTree
## Which coach plan buys the most team overall per dollar? (several fresh careers)
func _init() -> void:
	var tot := {}
	for seed in 6:
		for focus in Career.FOCUS:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
			Career.loaded = false
			seed(1000 + seed)
			Career.ensure()
			var t0 := Career._team_avg(Career.team(0))
			var plan := Career.coach_plan(0, true, 400, focus, 77)
			Career.coach_spend(0, true, 400, focus, 77)
			var gain := Career._team_avg(Career.team(0)) - t0
			var a: Array = tot.get(focus, [0.0, 0.0])
			a[0] += gain
			a[1] += float(plan["cost"])
			tot[focus] = a
	for f in tot:
		print("%-28s team OVR +%.2f for $%d  ->  %.3f per $100" % [Career.FOCUS[f]["label"], tot[f][0] / 6.0, int(tot[f][1] / 6.0), 100.0 * tot[f][0] / maxf(tot[f][1], 1)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	quit()
