extends SceneTree
## Which positions wear out: parts lost and condition left after a game, by slot.
func _init() -> void:
	Library.ensure()
	var n := 16
	var off := {}
	var cond := {}
	for s in n:
		var red := Team.build(0, "Balanced")
		var blue := Team.build(1, "Air Raid")
		for pair in [[red, 0], [blue, 1]]:
			var tm := Career.new_team(pair[1], 700 + s * 2 + pair[1])
			pair[0]["roster"] = tm["starters"]
			pair[0]["bench"] = tm["bench"]
		var g := Batch.play_game(red, blue, 300.0, 1900 + s)
		for b in g.broken:
			off[b["slot"]] = int(off.get(b["slot"], 0)) + 1
		for tm2 in [red, blue]:
			for sl in tm2["roster"]:
				var c := Robot.condition(tm2["roster"][sl])
				if not cond.has(sl): cond[sl] = [0.0, 0]
				cond[sl][0] += float(c[0]) / float(c[1]); cond[sl][1] += 1
	var keys := cond.keys()
	keys.sort_custom(func(a, b): return cond[a][0] / cond[a][1] < cond[b][0] / cond[b][1])
	for k in keys.slice(0, 10):
		print("%-4s cond %3d%%  parts off/game %.2f" % [k, int(100.0 * cond[k][0] / cond[k][1]), float(off.get(k, 0)) / (2.0 * n)])
	quit()
