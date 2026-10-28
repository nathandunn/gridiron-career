extends RefCounted
const LEVELS := {"great": [85, "Mk III"], "average": [60, "Stock"], "poor": [38, "Junk"]}
static func side(index: int, ol: String, dl: String, rng: RandomNumberGenerator) -> Dictionary:
	var tm := Team.build(index, "Balanced")
	var roster := {}
	var n := 0
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		var r := Robot.make(rng, s, 10 + n, "x%d-%d" % [index, n], false)
		n += 1
		var g := String(r["group"])
		var lvl: Array = [60, "Stock"]
		if g == "OL":
			lvl = LEVELS[ol]
		elif g == "DL":
			lvl = LEVELS[dl]
		for k in r["ratings"]:
			r["ratings"][k] = int(lvl[0])
		for k in Robot.PARTS:
			r["parts"][k] = {"tier": String(lvl[1]), "hp": Robot.TIER_HP[String(lvl[1])]}
		roster[s] = r
	tm["roster"] = roster
	tm["bench"] = []
	tm["fair"] = false
	return tm
