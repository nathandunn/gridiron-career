extends SceneTree
## Audibles happen (not every snap), read sensibly, and don't break games.
func _init() -> void:
	Library.ensure()
	var n_aud := 0
	var plays := 0
	var kinds := {}
	var shown := 0
	var edge := 0
	for i in 6:
		var g := Batch.play_game(Team.build(0, "Ground and Pound"), Team.build(1, "Air Raid", {}, "coach", "Adaptive D"), 300.0, 300 + i)
		for e in g.log:
			if String(e.get("kind", "")) != "play" or e.get("return", false):
				continue
			plays += 1
			if e.has("audible"):
				n_aud += 1
				for note in e["audible"]:
					var k := "offense" if String(note).find(" audible:") >= 0 else ("edge" if String(note).find("set the edge") >= 0 else "defense")
					kinds[k] = int(kinds.get(k, 0)) + 1
					if shown < 8:
						print("  ", note)
						shown += 1
	print("plays %d, with an audible %d (%.0f%%): %s" % [plays, n_aud, 100.0 * n_aud / maxf(plays, 1), kinds])
	assert(n_aud > 0 and n_aud < plays)
	print("OK")
	quit()
