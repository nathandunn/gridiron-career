extends RefCounted
## A side for the line studies: everyone a normal player for his position (each rating at his
## position's average, stock parts) except the O-line / D-line, set great / average / poor
## against what is normal for a lineman.
const LEVELS := {"great": [22, "Mk III"], "average": [0, "Stock"], "poor": [-20, "Junk"]}
static func side(index: int, ol: String, dl: String, rng: RandomNumberGenerator) -> Dictionary:
	var tm := Team.build(index, "Balanced")
	var roster := {}
	var n := 0
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		var r := Robot.make(rng, s, 10 + n, "x%d-%d" % [index, n], false)
		n += 1
		var g := String(r["group"])
		var lvl: Array = [0, "Stock"]
		if g == "OL":
			lvl = LEVELS[ol]
		elif g == "DL":
			lvl = LEVELS[dl]
		for k in r["ratings"]:
			r["ratings"][k] = clampi(int(Robot.mean_for(g, k)) + int(lvl[0]), 20, 99)
		for k in Robot.PARTS:
			r["parts"][k] = {"tier": String(lvl[1]), "hp": Robot.TIER_HP[String(lvl[1])]}
		roster[s] = r
	tm["roster"] = roster
	tm["bench"] = []
	tm["fair"] = false
	return tm
