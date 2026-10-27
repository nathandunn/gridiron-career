extends SceneTree
## Per-team game counts for calibrating performance pay. One line per team per game, CSV.
func _init() -> void:
	Library.ensure()
	var coaches := ["Balanced", "Air Raid", "Ground and Pound", "Adaptive", "Option Run", "By the Numbers"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	print("CSV,res,pts,opp,td,explosive,big_run,sacks,takeaways,parts_off,first_downs,yards,long_td")
	for i in 40:
		var a: String = coaches[rng.randi() % coaches.size()]
		var b: String = coaches[rng.randi() % coaches.size()]
		var g := Batch.play_game(Team.build(0, a), Team.build(1, b), 300.0, rng.randi())
		for t in 2:
			var st: Dictionary = g.stats[t]
			var os: Dictionary = g.stats[1 - t]
			var parts := 0
			for br in g.broken:
				if int(br["team"]) != t:
					parts += 1
			var big_run := 0
			var long_td := 0
			for e in g.log:
				if String(e.get("kind", "")) == "play" and int(e.get("team", -1)) == t:
					var gn := float(e.get("gain", 0))
					if gn >= 15.0 and not String(e.get("off", "")).is_empty() and String(e.get("why", "")) != "" and float(e.get("gain", 0)) >= 15.0 and e.has("off"):
						pass
			var w := g.winner()
			var res := "tie" if w < 0 else ("win" if w == t else "loss")
			print("CSV,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [res, g.score[t], g.score[1 - t], int(st["td"]), int(st["explosive"]), big_run, int(os["sacks"]), int(os["turnovers"]), parts, int(st["first_downs"]), int(st["yards"]), long_td])
	quit()
