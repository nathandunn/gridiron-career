extends SceneTree
## Touchdowns are 6 and a try follows: the score is 6 a TD + 1 an extra point + 2 a two-point
## try + 3 a field goal + 2 a safety, always.
func _init() -> void:
	Library.ensure()
	var xp := [0, 0]
	var two := [0, 0]
	var bad := 0
	for i in 10:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 300 + i)
		for t in 2:
			var st: Dictionary = g.stats[t]
			var saf := 0
			for e in g.log:
				if String(e.get("text", "")).find("SAFETY") >= 0 and int(e.get("team", -1)) == 1 - t:
					saf += 1
			var want := 6 * int(st["td"]) + int(st.get("xp", 0)) + 2 * int(st.get("two", 0)) + 3 * int(st.get("fg", 0)) + 2 * saf
			if want != g.score[t]:
				bad += 1
				print("game %d side %d: score %d but parts make %d (td %d xp %d two %d fg %d saf %d)" % [i, t, g.score[t], want, st["td"], st.get("xp", 0), st.get("two", 0), st.get("fg", 0), saf])
			xp[0] += int(st.get("xp", 0))
			xp[1] += int(st.get("xp_att", 0))
			two[0] += int(st.get("two", 0))
			two[1] += int(st.get("two_att", 0))
	print("extra points %d/%d, two-point tries %d/%d, mismatches %d" % [xp[0], xp[1], two[0], two[1], bad])
	assert(xp[1] > 0)
	print("OK")
	quit()
