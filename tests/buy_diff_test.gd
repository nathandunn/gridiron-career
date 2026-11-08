extends SceneTree
## Efficient buy vs best buy: how often do they pick different parts?
func _init() -> void:
	Library.ensure()
	var same := 0
	var n := 0
	var ov := 0.0
	for i in 20:
		Career.data = {}
		Career.loaded = false
		Career.ensure()
		Career.new_season()
		Career.add_money(0, 2600)
		var a := Career.coach_plan(0, true, 400, "", 7)
		var b := Career.coach_plan(0, true, 400, "win", 7)
		var ka: Array = a["rows"].map(func(r): return "%s:%s" % [r["slot"], ",".join(r["parts"])])
		var kb: Array = b["rows"].map(func(r): return "%s:%s" % [r["slot"], ",".join(r["parts"])])
		ka.sort(); kb.sort()
		n += 1
		var common := 0
		for x in ka:
			if x in kb:
				common += 1
		ov += float(common) / maxf(maxf(ka.size(), kb.size()), 1)
		if ka == kb:
			same += 1
		if i < 3:
			print("efficient: ", ", ".join(a["rows"].map(func(r): return "%s %d->%d" % [r["slot"], r["before"], r["after"]])))
			print("best:      ", ", ".join(b["rows"].map(func(r): return "%s %d->%d" % [r["slot"], r["before"], r["after"]])))
	print("identical plans: %d of %d, same robot+parts on average %.0f%% of rows" % [same, n, 100.0 * ov / n])
	quit()
