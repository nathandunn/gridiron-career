extends SceneTree
## Defensive schemes load, and a side's scheme (not its coach) calls its defenses.
func _init() -> void:
	Library.ensure()
	var names := Library.names("defense")
	print("defenses: ", names)
	assert(names.size() >= 7)
	for n in names:
		var c: Coach = Library.defense(n)
		assert(c != null and c.errors.is_empty())
		assert(Library.lint("defense", Library.source("defense", n)).is_empty())
	for dn in ["Blitz Happy", "Bend Don't Break", "Stop the Run"]:
		var calls := {}
		for i in 3:
			var g := Batch.play_game(Team.build(0, "Air Raid"), Team.build(1, "Air Raid", {}, "coach", dn), 300.0, 40 + i)
			for e in g.log:
				if String(e.get("kind", "")) == "play" and int(e.get("team", -1)) == 0 and e.has("def"):
					calls[e["def"]] = int(calls.get(e["def"], 0)) + 1
			assert(g.coach_tally[1].keys().any(func(k): return String(str(k)).begins_with("d")))
		print("%s: %s" % [dn, calls])
	print("OK")
	quit()
