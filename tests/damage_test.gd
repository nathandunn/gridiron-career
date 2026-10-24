extends SceneTree
## Wear and tear: how many parts come off a game (the plan aims for 1-3), and that the
## coaches' fixes keep a full side on the field.
func _init() -> void:
	Library.ensure()
	var n := 20
	var total := 0
	var by_part := {}
	var by_kind := {}
	var fixes := 0
	var hurt_total := 0
	var plays := 0
	for s in n:
		var red := Team.build(0, "Balanced")
		var blue := Team.build(1, "Air Raid")
		for pair in [[red, 0], [blue, 1]]:
			var tm := Career.new_team(pair[1], 500 + s * 2 + pair[1])
			pair[0]["roster"] = tm["starters"]
			pair[0]["bench"] = tm["bench"]
		var g := Batch.play_game(red, blue, 300.0, 900 + s)
		total += g.broken.size()
		plays += g.plays_run
		hurt_total += g.hurt.size()
		for b in g.broken:
			by_part[b["part"]] = int(by_part.get(b["part"], 0)) + 1
			by_kind["team%d" % int(b["team"])] = int(by_kind.get("team%d" % int(b["team"]), 0)) + 1
		for e in g.log:
			var tx := String(e.get("text", ""))
			if tx.find("comes in for") >= 0 or tx.find("bolted on") >= 0:
				fixes += 1
	print("PARTS OFF a game: %.2f  by part %s  coach fixes %d" % [float(total) / n, by_part, fixes])
	print("PLAYS a part comes off: every %.1f plays (%d plays, %d parts)" % [float(plays) / maxf(total, 1), plays, total])
	print("BY TEAM ", by_kind)
	print("ROBOTS DAMAGED a game: %.1f of 44 (%.0f%%)" % [float(hurt_total) / n, 100.0 * hurt_total / n / 44.0])
	quit()
