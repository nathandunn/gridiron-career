extends SceneTree
## Field goals: tried on fourth down in range, made more often close in, worth 3.
func _init() -> void:
	Library.ensure()
	var att := 0
	var made := 0
	var by_d := {}
	var safeties := 0
	for i in 16:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 900 + i)
		for e in g.log:
			if String(e.get("kind", "")) == "fg":
				att += 1
				var pre := String(e["text"]).get_slice("-yard", 0).split(" ")
				var d := int(pre[pre.size() - 1])
				var b := "%d-%d" % [d / 10 * 10, d / 10 * 10 + 9]
				var a: Array = by_d.get(b, [0, 0])
				a[0] += 1
				if bool(e.get("good", false)):
					made += 1
					a[1] += 1
				by_d[b] = a
			if String(e.get("text", "")).find("SAFETY") >= 0:
				safeties += 1
	print("field goals %d/%d  by distance %s  safeties %d" % [made, att, by_d, safeties])
	assert(att > 0)
	print("OK")
	quit()
