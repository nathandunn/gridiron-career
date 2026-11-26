extends SceneTree
## Kick and punt returns are counted for the team and the returner, and they add up.
func _init() -> void:
	Library.ensure()
	var ok := true
	var shown := 0
	for s in 4:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 300 + s)
		for t in 2:
			var st: Dictionary = g.stats[t]
			var n := int(st.get("kr", 0)) + int(st.get("pr", 0))
			var yds := float(st.get("kr_yds", 0.0)) + float(st.get("pr_yds", 0.0))
			var pn := 0.0
			var py := 0.0
			for sl in g.pstats[t]:
				pn += float(g.pstats[t][sl].get("kr", 0)) + float(g.pstats[t][sl].get("pr", 0))
				py += float(g.pstats[t][sl].get("kryd", 0)) + float(g.pstats[t][sl].get("pryd", 0))
			if n != int(st.get("returns", 0)) or absf(yds - float(st.get("ret_yds", 0.0))) > 0.01 or pn > n or py > yds + 0.01:
				ok = false
				print("MISMATCH ", st.get("returns"), " ", n, " ", pn)
			if shown < 2:
				shown += 1
				print("team %d: KR %d-%d (lng %d)  PR %d-%d  FC %d  TB %d" % [t, st.get("kr", 0), st.get("kr_yds", 0), st.get("kr_long", 0), st.get("pr", 0), st.get("pr_yds", 0), st.get("fc", 0), st.get("tb", 0)])
	print("return_stats_test ", "OK" if ok else "FAIL")
	quit()
