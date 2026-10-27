extends SceneTree
## Kickoff and punt returns are played out: how many, how far, and nothing breaks.
func _init() -> void:
	Library.ensure()
	var n := {"Kick return": 0, "Punt return": 0}
	var yds := {"Kick return": 0.0, "Punt return": 0.0}
	var tds := 0
	var fum := 0
	var pts := 0
	for i in 12:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "By the Numbers"), 300.0, 100 + i)
		pts += g.score[0] + g.score[1]
		for e in g.log:
			if e.get("return", false):
				n[e["off"]] += 1
				yds[e["off"]] += float(e["gain"])
				if String(e["text"]).find("TOUCHDOWN") >= 0:
					tds += 1
				if String(e["text"]).find("FUMBLES") >= 0:
					fum += 1
		if i == 0:
			for e in g.log:
				if e.get("return", false) or String(e.get("kind", "")) in ["punt"]:
					print("  ", e["text"])
	for k in n:
		print("%s: %d, %.1f yds avg" % [k, n[k], yds[k] / maxf(n[k], 1)])
	print("return TDs %d, fumbles %d, points per game %.1f" % [tds, fum, pts / 12.0])
	assert(n["Kick return"] > 0)
	print("OK")
	quit()
