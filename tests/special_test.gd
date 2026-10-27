extends SceneTree
## Kickers and punters: they exist, they show up in the log, and a big leg kicks further.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	var sp := Career.special(0)
	print("K ", sp["K"]["name"], " leg ", Robot.eff(sp["K"], "leg"), "  P ", sp["P"]["name"], " leg ", Robot.eff(sp["P"], "leg"), " ovr ", Robot.overall(sp["P"]))
	assert(Career.find(String(sp["P"]["id"]))["where"] == "special")
	for side_leg in [35, 95]:
		Career.special(0)["P"]["ratings"]["leg"] = side_leg
		var tot := 0.0
		var n := 0
		for i in 300:
			var g := Game.new()
			g.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, i)
			g.poss = 0
			g.yl = 30.0
			var e := g._punt()
			if i < 2:
				print("  ", e["text"])
			tot += g.yl if g.poss == 1 else 0.0
			n += 1
		print("punter leg %d: receiving team starts on average at their own %.1f" % [side_leg, 100.0 - (tot / n) - 0.0 if false else tot / n])
	var g2 := Game.new()
	g2.setup(Team.build(0, "Balanced"), Team.build(1, "Balanced"), 300.0, 5)
	print("  ", g2.log[0].get("text", "") if not g2.log.is_empty() else "(no log)")
	print("OK")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	quit()
