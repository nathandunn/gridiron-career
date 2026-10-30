extends SceneTree
## Whole games, every coach against every other (equal bodies): per team per game - runs and
## yards a carry, pass attempts, completion %, yards a pass, sacks, interceptions, points.
func _init() -> void:
	Library.ensure()
	var coaches := Library.names("coach")
	var reps := int(OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0].begins_with("--reps=")) 
	var R := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reps="):
			R = int(a.substr(7))
	var tot := {"games": 0, "team_games": 0, "rush_att": 0, "rush_yds": 0.0, "pass_att": 0, "comp": 0, "pass_yds": 0.0, "sacks": 0, "sack_yds": 0.0, "ints": 0, "pts": 0, "plays": 0, "first_downs": 0}
	var per_coach := {}
	var seed := 900
	for a in coaches:
		for b in coaches:
			for r in R:
				seed += 1
				var g := Batch.play_game(Team.build(0, a), Team.build(1, b), 300.0, seed)
				tot["games"] += 1
				for t in 2:
					var st: Dictionary = g.stats[t]
					tot["team_games"] += 1
					for k in ["rush_att", "rush_yds", "pass_att", "comp", "pass_yds", "sacks", "sack_yds", "ints", "plays", "first_downs"]:
						tot[k] += st.get(k, 0)
					tot["pts"] += g.score[t]
					var c: String = a if t == 0 else b
					var pc: Dictionary = per_coach.get(c, {"g": 0, "ra": 0, "ry": 0.0, "pa": 0, "py": 0.0, "sk": 0, "pts": 0})
					pc["g"] += 1
					pc["ra"] += int(st["rush_att"])
					pc["ry"] += float(st["rush_yds"])
					pc["pa"] += int(st["pass_att"])
					pc["py"] += float(st["pass_yds"])
					pc["sk"] += int(st["sacks"])
					pc["pts"] += g.score[t]
					per_coach[c] = pc
	var tg := float(tot["team_games"])
	print("games %d (team-games %d), quarters of 5 minutes" % [tot["games"], tot["team_games"]])
	print("RUN   %.1f carries/game, %.2f yds a carry" % [tot["rush_att"] / tg, tot["rush_yds"] / maxf(tot["rush_att"], 1)])
	print("PASS  %.1f att/game, %.0f%% complete, %.2f yds an attempt, %.1f yds a completion, %.2f INT/game" % [tot["pass_att"] / tg, 100.0 * tot["comp"] / maxf(tot["pass_att"], 1), tot["pass_yds"] / maxf(tot["pass_att"], 1), tot["pass_yds"] / maxf(tot["comp"], 1), tot["ints"] / tg])
	print("SACKS %.2f a game (%.1f%% of dropbacks), %.1f yds each" % [tot["sacks"] / tg, 100.0 * tot["sacks"] / maxf(tot["pass_att"] + tot["sacks"], 1), -tot["sack_yds"] / maxf(tot["sacks"], 1)])
	print("NET   %.2f yds a dropback (sacks counted)" % [(tot["pass_yds"] + tot["sack_yds"]) / maxf(tot["pass_att"] + tot["sacks"], 1)])
	print("GAME  %.1f plays, %.1f first downs, %.1f points per team" % [tot["plays"] / tg, tot["first_downs"] / tg, tot["pts"] / tg])
	for c in per_coach:
		var pc: Dictionary = per_coach[c]
		print("   %-18s %.2f yds/carry (%.0f carries), %.2f yds/att (%.0f att), %.1f sacks, %.1f pts" % [c, pc["ry"] / maxf(pc["ra"], 1), float(pc["ra"]) / pc["g"], pc["py"] / maxf(pc["pa"], 1), float(pc["pa"]) / pc["g"], float(pc["sk"]) / pc["g"], float(pc["pts"]) / pc["g"]])
	print("OK")
	quit()
