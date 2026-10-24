extends SceneTree
## Ratings matter, and a roster of 60s plays exactly like the equal bodies.
func _avg_rec(red: Dictionary, blue: Dictionary, n: int) -> Array:
	var rec := 0.0
	var yds := 0.0
	var pts := 0.0
	for s in n:
		var g := Batch.play_game(red, blue, 300.0, 1000 + s)
		for slot in g.pstats[0]:
			var ps: Dictionary = g.pstats[0][slot]
			if String(slot).begins_with("WR"):
				rec += float(ps.get("rec", 0))
				yds += float(ps.get("recyd", 0))
		pts += g.score[0] - g.score[1]
	return [yds / maxf(rec, 1.0), pts / n]


func _roster(t: int, val: int) -> Dictionary:
	var r := {}
	var rng := RandomNumberGenerator.new()
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		var rb := Robot.make(rng, s, 1, "x")
		for k in rb["ratings"]:
			rb["ratings"][k] = val
		r[s] = rb
	return r


func _init() -> void:
	Library.ensure()
	# 1. sixties are the equal bodies (with wear and tear off: hits don't break anything)
	PlaySim.K["wear"] = 0.0
	var same := true
	for s in 5:
		var a := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, s)
		var r0 := Team.build(0, "Balanced"); r0["roster"] = _roster(0, 60)
		var r1 := Team.build(1, "Air Raid"); r1["roster"] = _roster(1, 60)
		var b := Batch.play_game(r0, r1, 300.0, s)
		if a.score != b.score:
			same = false
	print("SIXTIES = EQUAL BODIES: ", same)
	PlaySim.K["wear"] = 1.0
	# 2. fast receivers gain more a catch, and better robots win
	var base := _avg_rec(Team.build(0, "Air Raid"), Team.build(1, "Balanced"), 30)
	var fast := Team.build(0, "Air Raid")
	fast["roster"] = _roster(0, 60)
	for s in ["WR1", "WR2", "WR3"]:
		fast["roster"][s]["ratings"]["speed"] = 95
	var f := _avg_rec(fast, Team.build(1, "Balanced"), 30)
	print("WR yards a catch: speed 60 %.1f, speed 95 %.1f" % [base[0], f[0]])
	var good := Team.build(0, "Air Raid"); good["roster"] = _roster(0, 80)
	var bad := Team.build(1, "Balanced"); bad["roster"] = _roster(1, 40)
	var gb := _avg_rec(good, bad, 30)
	print("Margin a game: equal %.1f, 80s vs 40s %.1f" % [base[1], gb[1]])
	quit()
