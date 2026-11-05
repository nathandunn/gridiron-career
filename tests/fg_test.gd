extends SceneTree
## Field goals: tried on fourth down in range, made more often close in, worth 3.
func _init() -> void:
	Library.ensure()
	var att := 0
	var made := 0
	var by_d := {}
	var safeties := 0
	var blocked := 0
	for i in 16:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 900 + i)
		for e in g.log:
			if String(e.get("fg", "")) != "":
				att += 1
				var pre := String(e["text"]).get_slice("-yard", 0).split(" ")
				var d := int(pre[pre.size() - 1])
				var b := "%d-%d" % [d / 10 * 10, d / 10 * 10 + 9]
				var a: Array = by_d.get(b, [0, 0])
				a[0] += 1
				if String(e["fg"]) == "good":
					made += 1
					a[1] += 1
				by_d[b] = a
				if String(e["fg"]) == "blocked":
					blocked += 1
			if String(e.get("text", "")).find("SAFETY") >= 0:
				safeties += 1
	print("field goals %d/%d  by distance %s  blocked %d  safeties %d" % [made, att, by_d, blocked, safeties])
	assert(att > 0)
	print("OK")
	quit()
