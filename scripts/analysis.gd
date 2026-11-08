class_name Analysis
extends RefCounted
## Scouting before a game and a report after it: what to watch for, what went well or badly,
## and what to fix - told apart as play-calling (what was called and how it worked) and the
## players (how good each unit is, who stood out, who is damaged).
##
## Each line is [text, tone]: tone "good", "bad" or "note".

const UNITS := {
	"QB": ["QB"], "running back": ["RB"], "receivers": ["WR1", "WR2", "WR3", "TE"],
	"O-line": ["LT", "LG", "C", "RG", "RT"], "D-line": ["DE1", "DT1", "DT2", "DE2"],
	"linebackers": ["OLB1", "MLB", "OLB2"], "secondary": ["CB1", "CB2", "FS", "SS"],
}

## What the opposing defensive scheme tends to do, and what beats it.
const DEF_TIPS := {
	"Blitz Happy": "blitzes all game: throw quick, screens",
	"Bend Don't Break": "soft zone: short passes and runs work",
	"Man Press": "man, one deep safety: crossers beat it",
	"Stop the Run": "eight in the box: throw early",
	"Spy the QB": "spies the QB: don't scramble",
	"Adaptive D": "adapts to you: mix it up",
	"By the Numbers D": "plays the odds: be unpredictable",
}
const OFF_TIPS := {
	"Air Raid": "throws all day: rush and cover",
	"Ground and Pound": "runs it: load the front",
	"Balanced": "by the book",
	"Adaptive": "repeats what works: stop it early",
	"Option Run": "sweeps and scrambles: keep contain",
	"By the Numbers": "plays the odds",
}


static func unit(tm: Dictionary, slots: Array) -> float:
	var s := 0.0
	var n := 0
	for sl in slots:
		var r: Dictionary = tm.get("starters", {}).get(sl, {})
		if not r.is_empty():
			s += float(Robot.overall_if(r, "now"))
			n += 1
	return s / maxf(n, 1)


static func _weakest(tm: Dictionary, slots: Array) -> Array:
	var best := []
	var lo := 999.0
	for sl in slots:
		var r: Dictionary = tm.get("starters", {}).get(sl, {})
		if r.is_empty():
			continue
		var o := float(Robot.overall_if(r, "now"))
		if o < lo:
			lo = o
			best = [sl, r, o]
	return best


static func _short(r: Dictionary) -> String:
	var bits := String(r.get("name", "")).split(" ")
	return ("%s. %s" % [bits[0].substr(0, 1), " ".join(bits.slice(1))]) if bits.size() > 1 else String(r.get("name", ""))


## One matchup line: our unit `a` against their unit `b`.
static func _vs(out: Array, mine: float, theirs: float, what_good: String, what_bad: String, label: String) -> void:
	var d := mine - theirs
	if d >= 3.0:
		out.append(["%s (%d vs %d): %s" % [label, int(mine), int(theirs), what_good], "good"])
	elif d <= -3.0:
		out.append(["%s (%d vs %d): %s" % [label, int(mine), int(theirs), what_bad], "bad"])
	else:
		out.append(["%s (%d vs %d): even" % [label, int(mine), int(theirs)], "note"])


## Before kickoff: the matchups, their schemes and what to do about them, the damage.
static func pregame(me: Dictionary, opp: Dictionary) -> Array:
	var out: Array = []
	var U := UNITS
	# the players: unit against unit
	_vs(out, unit(me, U["O-line"]), unit(opp, U["D-line"]),
		"lean on the run",
		"quick passes, outside runs", "Your O-line vs their D-line")
	_vs(out, unit(me, U["D-line"]), unit(opp, U["O-line"]),
		"your rush gets home",
		"blitz more", "Your D-line vs their O-line")
	_vs(out, unit(me, U["receivers"]), unit(opp, U["secondary"]),
		"throw it",
		"run and throw short", "Your receivers vs their secondary")
	_vs(out, unit(me, U["secondary"]), unit(opp, U["receivers"]),
		"play man",
		"play zone, keep it in front", "Your secondary vs their receivers")
	_vs(out, unit(me, U["running back"]) * 0.5 + unit(me, U["O-line"]) * 0.5, unit(opp, U["linebackers"]) * 0.5 + unit(opp, U["D-line"]) * 0.5,
		"run it", "running will be hard", "Your run game vs their front")
	# the play-calling side: their schemes and what beats them
	var dn := String(opp.get("defense", ""))
	if DEF_TIPS.has(dn):
		out.append(["Their D, %s: %s." % [dn, DEF_TIPS[dn]], "note"])
	var on := String(opp.get("coach", ""))
	if OFF_TIPS.has(on):
		out.append(["Their O, %s: %s." % [on, OFF_TIPS[on]], "note"])
	# weak spots
	var tw := _weakest(opp, U["secondary"])
	if not tw.is_empty() and float(tw[2]) < 58.0:
		out.append(["Their weak spot: %s %s (%d) - throw at him." % [tw[0], _short(tw[1]), int(tw[2])], "good"])
	var tl := _weakest(opp, U["O-line"])
	if not tl.is_empty() and float(tl[2]) < 56.0:
		out.append(["Their weakest blocker: %s %s (%d) - rush at him." % [tl[0], _short(tl[1]), int(tl[2])], "good"])
	var mw := _weakest(me, U["O-line"] + U["secondary"])
	if not mw.is_empty() and float(mw[2]) < 55.0:
		out.append(["Your weak link: %s %s (%d) - they may pick on him." % [mw[0], _short(mw[1]), int(mw[2])], "bad"])
	# damage
	for s in me.get("starters", {}):
		var r: Dictionary = me["starters"][s]
		var lost := Robot.lost_parts(r)
		if not lost.is_empty():
			out.append(["%s %s is missing his %s (OVR %d) - fix or bench him before kickoff." % [s, _short(r), ", ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower())), Robot.overall_if(r, "now")], "bad"])
	for s in opp.get("starters", {}):
		var r2: Dictionary = opp["starters"][s]
		if not Robot.lost_parts(r2).is_empty():
			out.append(["Their %s %s is playing hurt (OVR %d) - go after him." % [s, _short(r2), Robot.overall_if(r2, "now")], "good"])
	return out


static func _pl(k: String) -> String:
	return k + ("es" if k.ends_with("ss") else "s")


static func _avg(a: Array) -> float:
	return float(a[1]) / maxf(float(a[0]), 1.0)


## After a game (or at a break): how it went, why - the calls and the players - and what to fix.
static func postgame(g: Game, t: int) -> Array:
	var out: Array = []
	var me: Dictionary = g.stats[t]
	var them: Dictionary = g.stats[1 - t]
	var ypc := float(me["rush_yds"]) / maxf(float(me["rush_att"]), 1.0)
	var ypa := float(me["pass_yds"]) / maxf(float(me["pass_att"]), 1.0)
	var o_ypc := float(them["rush_yds"]) / maxf(float(them["rush_att"]), 1.0)
	var o_ypa := float(them["pass_yds"]) / maxf(float(them["pass_att"]), 1.0)
	# --- how it went
	out.append(["Your runs: %.1f a carry on %d carries." % [ypc, int(me["rush_att"])], "good" if ypc >= 5.0 else ("bad" if ypc < 3.5 and int(me["rush_att"]) >= 4 else "note")])
	out.append(["Your passing: %d of %d, %.1f a throw, %d sacked, %d intercepted." % [int(me["comp"]), int(me["pass_att"]), ypa, int(me["sacks"]), int(me["ints"])],
		"good" if ypa >= 7.5 and int(me["ints"]) == 0 else ("bad" if ypa < 5.0 or int(me["ints"]) >= 2 else "note")])
	out.append(["Their runs: %.1f a carry; their passing %.1f a throw; your defense got %d sacks and %d takeaways." % [o_ypc, o_ypa, int(them["sacks"]), int(them["turnovers"])],
		"good" if o_ypc < 3.8 and o_ypa < 6.0 else ("bad" if o_ypc >= 5.0 or o_ypa >= 8.0 else "note")])
	# --- play-calling: which kinds of plays worked, and how often you called them
	var tr: Dictionary = g.trend[t]
	var kinds: Array = []
	var total := 0
	for k in tr:
		total += int(tr[k][0])
	for k in tr:
		if int(tr[k][0]) >= 2:
			kinds.append([k, _avg(tr[k]), int(tr[k][0])])
	kinds.sort_custom(func(a, b): return a[1] > b[1])
	if kinds.size() >= 2:
		var best: Array = kinds[0]
		var worst: Array = kinds[-1]
		out.append(["Play-calling: %s worked best (%.1f yds on %d calls); %s worst (%.1f on %d)." % [_pl(best[0]), best[1], best[2], _pl(worst[0]), worst[1], worst[2]], "note"])
		if float(best[1]) >= float(worst[1]) + 3.0 and float(best[2]) / maxf(total, 1) < 0.35:
			out.append(["Call more %s - you only called them %d of %d times." % [_pl(best[0]), best[2], total], "bad"])
		if float(worst[1]) < 2.0 and float(worst[2]) / maxf(total, 1) > 0.3:
			out.append(["Call fewer %s - %d calls for %.1f a play." % [_pl(worst[0]), worst[2], worst[1]], "bad"])
	var otr: Dictionary = g.trend[1 - t]
	var ob := ""
	var ov := -99.0
	for k in otr:
		if int(otr[k][0]) >= 3 and _avg(otr[k]) > ov:
			ov = _avg(otr[k])
			ob = String(k)
	if ob != "" and ov >= 5.0:
		out.append(["What hurt you: their %s (%.1f a play) - call defenses against them (%s)." % [_pl(ob), ov, "Run Blitz, Cover 1" if ob.ends_with("run") or ob == "sweep" or ob == "QB run" else "Cover 2, Cover 3"], "bad"])
	# --- the players
	var tm: Dictionary = g.teams[t]
	var ps: Dictionary = g.pstats[t]
	var star := ""
	var star_v := 0.0
	for s in ps:
		var v := float(ps[s].get("ryd", 0)) + float(ps[s].get("recyd", 0)) + float(ps[s].get("tkl", 0)) * 8.0 + float(ps[s].get("sack", 0)) * 25.0 + float(ps[s].get("dint", 0)) * 30.0
		if v > star_v:
			star_v = v
			star = s
	if star != "" and tm.get("roster", {}).has(star):
		var r: Dictionary = tm["roster"][star]
		var p: Dictionary = ps[star]
		var what := []
		if float(p.get("ryd", 0)) > 0.0:
			what.append("%d rushing yds" % int(p["ryd"]))
		if float(p.get("recyd", 0)) > 0.0:
			what.append("%d receiving yds" % int(p["recyd"]))
		if float(p.get("tkl", 0)) > 0.0:
			what.append("%d tackles" % int(p["tkl"]))
		if float(p.get("sack", 0)) > 0.0:
			what.append("%d sacks" % int(p["sack"]))
		out.append(["Standout: %s %s (OVR %d) - %s." % [star, _short(r), Robot.overall_if(r, "now"), ", ".join(what)], "good"])
	if tm.has("roster"):
		var U := UNITS
		if int(me["sacks"]) >= 3:
			var w := _weakest(tm, U["O-line"])
			if not w.is_empty():
				out.append(["%d sacks: your O-line (%d) didn't hold - its weakest, %s %s (%d), is the first to upgrade or replace." % [int(me["sacks"]), int(unit(tm, U["O-line"])), w[0], _short(w[1]), int(w[2])], "bad"])
		if o_ypc >= 5.0 and int(them["rush_att"]) >= 5:
			var w2 := _weakest(tm, U["D-line"] + U["linebackers"])
			if not w2.is_empty():
				out.append(["They ran at will: your front (%d) needs help - start with %s %s (%d)." % [int(unit(tm, U["D-line"] + U["linebackers"])), w2[0], _short(w2[1]), int(w2[2])], "bad"])
		if o_ypa >= 8.0 and int(them["pass_att"]) >= 5:
			var w3 := _weakest(tm, U["secondary"])
			if not w3.is_empty():
				out.append(["They threw at will: your secondary (%d) - %s %s (%d) is the weak spot." % [int(unit(tm, U["secondary"])), w3[0], _short(w3[1]), int(w3[2])], "bad"])
		if ypc < 3.5 and int(me["rush_att"]) >= 5:
			out.append(["Your runs went nowhere: O-line %d, running back %d - upgrade or throw more." % [int(unit(tm, U["O-line"])), int(unit(tm, U["running back"]))], "bad"])
		# damage to fix
		var broken: Array = []
		for s in tm["roster"]:
			var r3: Dictionary = tm["roster"][s]
			var lost := Robot.lost_parts(r3)
			if not lost.is_empty():
				broken.append("%s %s (%s)" % [s, _short(r3), ", ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))])
		if not broken.is_empty():
			out.append(["To fix before next game: %s." % "; ".join(broken), "bad"])
	return out
