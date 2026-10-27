class_name Game
extends RefCounted
## A game: four quarters, downs and distance, the coaches' calls, the score and the box
## score. Plays themselves are PlaySims; the game asks for the next one with next_snap() and is
## told how it went with finish(result).
##
## A touchdown is 7 points, a safety 7 to the defense. Kickoffs (start of each half and after a
## score) and punts are rolled, not played out; no field goals. A turnover - on downs, an
## interception, a fumble - changes hands where the ball is.

const HASH := 3.08

var teams: Array = []          # {index, name, coach: Coach, brains: {slot: Brain}}
var rng := RandomNumberGenerator.new()
var score := [0, 0]
var quarter := 1
var qlen := 360.0
var clock := 360.0
var poss := 0
var yl := 25.0                 # the offense's yard line, 0 = own goal
var down := 1
var to_go := 10.0
var ball_x := 0.0
var over := false
var opened := 0                # who received the opening kick
var log: Array = []            # one entry a snap or kick
var stats := [{}, {}]
var calls := [{}, {}]          # per team: play name -> [times, yards]
var kinds := [{"run": 0, "pass": 0}, {"run": 0, "pass": 0}]   # what each team has called on offense
var last_call := ["", ""]
var last_gain := [0.0, 0.0]
var last_kind := ["", ""]
var coach_tally := [{}, {}]    # rule line -> count
var drive := {}                # the current drive: team, start, plays, yards
var drives: Array = []
var pending := {}              # the call for the snap in play
var plays_run := 0
var down_event := ""           # what the last snap did to the downs: "first_down", "downs" (turned over), ""
var line := [[0, 0, 0, 0], [0, 0, 0, 0]]   # points a quarter
var pstats := [{}, {}]         # per team: slot -> player box score
var quarter_ends: Array = []   # a snapshot at the end of each quarter: {q, score, line, stats, pstats}

## How each side picks its plays: "coach" (the coach's rules), "random" (any play in the book),
## "generated" (a new play made up every down). Kicks on fourth down stay the coach's call.
const CALLING := ["pick", "coach", "random", "generated"]
const CALLING_LABEL := {"pick": "You pick (from new plays)", "coach": "Coach calls", "random": "Random from playbook", "generated": "Random new plays"}


func setup(red: Dictionary, blue: Dictionary, quarter_secs: float, seed_v: int) -> void:
	teams = [red, blue]
	red["index"] = 0
	blue["index"] = 1
	qlen = quarter_secs
	clock = qlen
	rng.seed = seed_v
	for t in 2:
		stats[t] = {"plays": 0, "pass_att": 0, "comp": 0, "pass_yds": 0.0, "rush_att": 0, "rush_yds": 0.0,
			"sacks": 0, "sack_yds": 0.0, "ints": 0, "fumbles": 0, "td": 0, "fg": 0, "fg_att": 0, "punts": 0,
			"first_downs": 0, "third_att": 0, "third_conv": 0, "fourth_att": 0, "fourth_conv": 0, "yards": 0.0,
			"top": 0.0, "explosive": 0, "turnovers": 0}
	opened = rng.randi() % 2
	_kickoff(1 - opened)


func _say(s: String) -> void:
	log.append({"text": s, "q": quarter, "clock": clock, "score": score.duplicate(), "kind": "note"})


func offense() -> Dictionary:
	return teams[poss]


func defense() -> Dictionary:
	return teams[1 - poss]


## A kickoff (to start a half, and after every score): mostly a touchback at the 25, otherwise a
## return to somewhere around the 15-40, now and then a long one. Not played out: rolled.
## Returns a line for the log.
## Special teams. With career robots the kicker's and punter's Leg (with his leg parts) sets
## how far it goes, and the return comes from the receiving side's best returner against the
## kicking side's coverage; without them, everyone is a 60.
func _specialist(t: int, s: String) -> Dictionary:
	return (teams[t].get("special", {}) as Dictionary).get(s, {})


func _leg(t: int, s: String) -> float:
	var r := _specialist(t, s)
	return Robot.eff(r, "leg") if not r.is_empty() else 60.0


func _returner(t: int) -> Dictionary:
	var best := {}
	var bs := -1.0
	var roster: Dictionary = teams[t].get("roster", {})
	for s in roster:
		var r: Dictionary = roster[s]
		if String(r.get("group", "")) in ["RB", "WR", "CB"] and Robot.can_play(r):
			var v := Robot.eff(r, "speed") + 0.6 * Robot.eff(r, "elusiveness" if Robot.keys(r).has("elusiveness") else "speed")
			if v > bs:
				bs = v
				best = r
	return best


## How much better the returner is than the coverage (about -1..1).
func _return_edge(receiver: int) -> float:
	var ret := _returner(receiver)
	var rv := (Robot.eff(ret, "speed") - 60.0) / 40.0 if not ret.is_empty() else 0.0
	var cov := 0.0
	var n := 0
	var roster: Dictionary = teams[1 - receiver].get("roster", {})
	for s in roster:
		if String(roster[s].get("group", "")) in ["LB", "S", "CB"]:
			cov += (Robot.eff(roster[s], "speed") - 60.0) / 40.0
			n += 1
	return clampf(rv - (cov / n if n > 0 else 0.0), -1.0, 1.0)


func _who(r: Dictionary, fallback: String) -> String:
	return ("#%d %s" % [int(r["number"]), r["name"]]) if not r.is_empty() else fallback


## A kickoff is owed: the kicking side calls it (deep, squib or onside) as the next snap, and
## the kick and the return are then played out on the field.
var kick_due := {}


func _kickoff(receiver: int) -> String:
	poss = receiver
	return_due = {}
	kick_due = {"receiver": receiver}
	yl = 25.0
	down = 1
	to_go = 10.0
	ball_x = 0.0
	var text := "%s kick off to %s." % [teams[1 - receiver]["name"], teams[receiver]["name"]]
	_say(text)
	return text


const KICKS := {"deep": "Deep kick", "squib": "Squib kick", "onside": "Onside kick"}
const RETURNS := {"middle": "Return up the middle", "left": "Return left", "right": "Return right", "fair": "Fair catch / take a knee"}
const PUNTS := {"punt": "Punt", "coffin": "Coffin corner", "pooch": "Pooch punt"}


## What the kicking side's coach calls: onside only when it is late and he must have the ball.
func coach_kick() -> String:
	var kicker := 1 - int(kick_due.get("receiver", poss))
	var diff: int = score[kicker] - score[1 - kicker]
	if quarter == 4 and clock < 180.0 and diff < 0 and diff >= -14:
		return "onside"
	return "deep"


## What the returning side's coach calls.
func coach_return() -> String:
	var rd := return_due
	if String(rd.get("kind", "")) == "kickoff" and float(rd.get("catch", 0.0)) < -3.0:
		return "fair"          # deep in the end zone: take a knee
	if String(rd.get("kind", "")) == "punt" and float(rd.get("catch", 50.0)) < 10.0:
		return "fair"
	if bool(rd.get("pooch", false)):
		return "fair"
	return ["middle", "middle", "left", "right"][rng.randi() % 4]


func _do_kickoff(kind: String) -> Dictionary:
	var receiver := int(kick_due["receiver"])
	var kicker := 1 - receiver
	kick_due = {}
	var leg := _leg(kicker, "K")
	var k := _who(_specialist(kicker, "K"), teams[kicker]["name"])
	var who: String = teams[receiver]["name"]
	var text := ""
	poss = receiver
	down = 1
	to_go = 10.0
	ball_x = 0.0
	match kind:
		"onside":
			var got := rng.randf() < 0.22
			if got:
				poss = kicker
				yl = 47.0
				text = "%s ONSIDE KICK - and %s RECOVER at the %s!" % [k, teams[kicker]["name"], _spot_text(47.0, kicker)]
			else:
				yl = 53.0
				text = "%s onside kick - %s fall on it at the %s." % [k, who, _spot_text(53.0, receiver)]
			_new_drive()
		"squib":
			var c := clampf(roundf(rng.randfn(22.0, 5.0)), 10.0, 34.0)
			yl = c
			return_due = {"kind": "kickoff", "kicker": kicker, "catch": c, "depth": 10.0, "gap": 22.0, "hang": 1.7, "low": true, "kick_dist": 45.0}
			text = "%s squibs it along the ground." % k
			_new_drive()
		_:
			# deep: further with a big leg; caught deep in the end zone, a knee is a touchback
			var c := clampf(roundf(rng.randfn(3.0 - (leg - 60.0) * 0.2, 5.0)), -8.0, 15.0)
			yl = maxf(c, 1.0)
			return_due = {"kind": "kickoff", "kicker": kicker, "catch": c, "depth": 12.0, "gap": 66.0, "hang": 3.4, "kick_dist": 62.0}
			text = "%s kicks it deep." % k
			_new_drive()
	var e := {"kind": "kickoff", "text": text, "call": KICKS.get(kind, kind)}
	_say(text)
	_log_play(e)
	return e


## "own 32" / "50" / "Blue 40", from the side with the ball.
func _spot_text(y: float, side: int) -> String:
	if absf(y - 50.0) < 0.5:
		return "50"
	if y < 50.0:
		return "%s %d" % [teams[side]["name"], int(round(y))]
	return "%s %d" % [teams[1 - side]["name"], int(round(100.0 - y))]


## The other side takes over where the ball is (the offense's yard line `spot`).
func _take_over(spot: float) -> void:
	poss = 1 - poss
	yl = clampf(100.0 - spot, 1.0, 99.0)
	down = 1
	to_go = minf(10.0, 100.0 - yl)
	_new_drive()


func _new_drive() -> void:
	if not drive.is_empty():
		drives.append(drive)
	drive = {"team": poss, "start": yl, "plays": 0, "yards": 0.0, "result": ""}


## What the side on offense / defense picks with, right now.
func calling_for(on_offense: bool) -> String:
	return String((offense() if on_offense else defense()).get("calling", "coach"))


## `choice` carries a person's picks: {off: {text, play}} / {def: {text, play}}.
## A side set to "pick" with no choice given plays a made-up play (as in a batch).
func next_snap(choice: Dictionary = {}) -> Dictionary:
	if over:
		return {"kind": "over"}
	if not kick_due.is_empty():
		return _do_kickoff(String(choice.get("kickoff", coach_kick())))
	if not return_due.is_empty():
		return _return_snap(String(choice.get("return", coach_return())))
	var oc: Coach = offense()["coach"]
	var dc: Coach = defense()["coach"]
	var od := _coach_call(oc, true, poss)
	var dd := _coach_call(dc, false, 1 - poss)
	if calling_for(true) == "pick" and (choice.has("off") or choice.has("kick")):
		od = {"kind": "punt" if choice.has("kick") else "play", "play": od.get("play", ""), "punt": String(choice.get("kick", "punt"))}
		if od["play"] == "":
			od["play"] = Library.plays_for("offense")[0]
	if String(od["kind"]) == "kneel":
		return _kneel()
	if String(od["kind"]) == "punt":
		return _punt(String(od.get("punt", "punt")) if PUNTS.has(String(od.get("punt", "punt"))) else "punt")
	var op: Play = Library.play(od["play"])
	var dp: Play = Library.play(dd.get("play", ""))
	if dp == null:
		dp = Library.play(Library.plays_for("defense")[0])
	pending = {"kind": "play", "off_text": "", "def_text": ""}
	var off_mode := calling_for(true)
	var def_mode := calling_for(false)
	if off_mode == "pick":
		off_mode = ""      # nobody to ask (a batch) or "let the coach call it": the coach's play
		if choice.has("off"):
			op = choice["off"]["play"]
			pending["off_text"] = choice["off"]["text"]
	if def_mode == "pick":
		def_mode = ""
		if choice.has("def"):
			dp = choice["def"]["play"]
			pending["def_text"] = choice["def"]["text"]
	match off_mode:
		"random":
			var o: Array = Library.plays_for("offense")
			op = Library.play(o[rng.randi() % o.size()])
		"generated":
			var g := PlayGen.offense(rng)
			op = g["play"]
			pending["off_text"] = g["text"]
	match def_mode:
		"random":
			var d: Array = Library.plays_for("defense")
			dp = Library.play(d[rng.randi() % d.size()])
		"generated":
			var g := PlayGen.defense(rng)
			dp = g["play"]
			pending["def_text"] = g["text"]
	pending["off"] = op
	pending["def"] = dp
	pending["off_name"] = op.name
	pending["def_name"] = dp.name
	return pending


## A PlaySim for the pending call.
func make_sim() -> PlaySim:
	var sim := PlaySim.new()
	var ctx := {"yl": yl, "down": down, "to_go": to_go, "ball_x": ball_x, "quarter": quarter, "clock": clock,
		"score_diff": score[poss] - score[1 - poss]}
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	var off := offense()
	if pending.has("return"):
		# the returner carries it, from the quarterback's spot in the return play
		var ret := _returner(poss)
		if off.has("roster") and not ret.is_empty():
			off = off.duplicate()
			var ro: Dictionary = (off["roster"] as Dictionary).duplicate()
			ro["QB"] = ret
			off["roster"] = ro
	sim.setup(off, defense(), pending["off"], pending["def"], ctx, r)
	if pending.has("return"):
		var rd: Dictionary = pending["return"]
		sim.start_kick(Vector2(0.0, float(rd["from_y"])), float(rd.get("hang", 3.5)), bool(rd.get("fair", false)), bool(rd.get("low", false)))
	return sim


## ---- kick and punt returns, played out ----------------------------------------------------------
var return_due := {}       # set by a kickoff or punt that is fielded: the next snap is the return


func _return_snap(call := "middle") -> Dictionary:
	var rd := return_due
	return_due = {}
	rd["call"] = call
	rd["fair"] = call == "fair"
	var catch_y := float(rd["catch"])
	var depth := float(rd["depth"])
	var los := catch_y + depth
	var gap := minf(float(rd["gap"]), 97.0 - los)
	rd["from_y"] = minf(-depth + float(rd.get("kick_dist", 55.0)), 99.0 - los)
	var kr := PlayGen.kick_return(rng, depth, gap, call)
	yl = los
	down = 1
	to_go = 10.0
	ball_x = 0.0
	var nm := ("Kickoff" if String(rd["kind"]) == "kickoff" else "Punt") + " · " + String(RETURNS.get(call, call)).to_lower()
	pending = {"kind": "play", "return": rd, "off": kr["off"], "def": kr["def"], "off_name": nm, "def_name": "Coverage",
		"off_text": "", "def_text": ""}
	return pending


func _finish_return(sim: PlaySim) -> Dictionary:
	var r: Dictionary = sim.result
	var rd: Dictionary = pending["return"]
	var team := poss
	var st: Dictionary = stats[team]
	var catch_y := float(rd["catch"])
	var spot := yl + float(r["y"])
	var ret_yds := spot - catch_y
	if String(r["why"]) == "fair" or (spot <= 0.0 and r["turnover"] == ""):
		# a fair catch, a knee in the end zone, or downed in it: no return
		var kick := String(rd["kind"]) == "kickoff"
		var at := (25.0 if kick else 20.0) if catch_y <= 0.0 or spot <= 0.0 else catch_y
		var what := ("Touchback" if catch_y <= 0.0 or spot <= 0.0 else "Fair catch")
		yl = at
		down = 1
		to_go = 10.0
		ball_x = 0.0
		var e0 := {"kind": "play", "team": team, "off": "Return", "def": "Coverage", "gain": 0.0, "why": "fair", "return": true,
			"text": "%s: %s, %s ball at the %s." % [what, _who(_returner(team), teams[team]["name"]), teams[team]["name"], _spot_text(yl, team)], "down": 1, "to_go": 10.0, "yl": at}
		_tick(float(r["t"]), true)
		e0["down_event"] = ""
		_log_play(e0)
		pending = {}
		return e0
	var who := _who(_returner(team), teams[team]["name"])
	var nm := "Kick return" if String(rd["kind"]) == "kickoff" else "Punt return"
	if String(rd.get("call", "middle")) in ["left", "right"]:
		nm += " (%s)" % rd["call"]
	st["ret_yds"] = float(st.get("ret_yds", 0.0)) + ret_yds
	st["returns"] = int(st.get("returns", 0)) + 1
	var e := {"kind": "play", "team": team, "off": nm, "def": "Coverage", "gain": ret_yds, "why": r["why"], "text": "",
		"down": 1, "to_go": 10.0, "yl": catch_y, "return": true}
	down_event = ""
	var elapsed := float(r["t"])
	if r["turnover"] != "":
		st["turnovers"] = int(st["turnovers"]) + 1
		st["fumbles"] = int(st["fumbles"]) + 1
		e["text"] = "%s: %s FUMBLES on the return - the kicking team has it!" % [nm, who]
		drive["result"] = "fumble"
		_tick(elapsed, true)
		ball_x = clampf(float(r["x"]), -HASH, HASH)
		_take_over(clampf(spot, 1.0, 99.0))
	elif r["td"] or spot >= 100.0:
		st["td"] = int(st["td"]) + 1
		_pts(team, 7)
		drive["result"] = "return TD"
		e["text"] = "%s: %s takes it ALL THE WAY - TOUCHDOWN! (%d yards)" % [nm, who, int(round(100.0 - catch_y))]
		r["td"] = true
		_tick(elapsed, true)
		e["text"] += " " + _kickoff(1 - team)
	else:
		yl = clampf(spot, 1.0, 99.0)
		down = 1
		to_go = minf(10.0, 100.0 - yl)
		ball_x = clampf(float(r["x"]), -HASH, HASH)
		e["text"] = "%s: %s brings it back %d yards to the %s." % [nm, who, int(round(ret_yds)), _spot_text(yl, team)]
		if ret_yds >= 20.0:
			st["explosive"] = int(st["explosive"]) + 1
		_tick(elapsed, true)
	e["down_event"] = down_event
	_log_play(e)
	pending = {}
	return e


func _coach_call(c: Coach, on_offense: bool, team: int, count := true) -> Dictionary:
	var out := {"kind": "", "play": ""}
	var rules: Array = c.offense_rules if on_offense else c.defense_rules
	var act := func(id: String, a: Array) -> bool:
		match id:
			"call":
				var opts: Array = []
				for n in a[0]:
					var p: Play = Library.play(n)
					if p != null and p.side == ("offense" if on_offense else "defense"):
						opts.append(n)
				if opts.is_empty():
					return false
				out["kind"] = "play"
				out["play"] = opts[rng.randi() % opts.size()]
				return true
			"call_best", "call_best_pass", "call_best_run":
				# by the numbers: a play not clearly worse than the best at this distance
				var names: Array = []
				for n in Library.plays_for("offense" if on_offense else "defense"):
					var p: Play = Library.play(n)
					if p == null:
						continue
					if id == "call_best_run" and p.kind != "run":
						continue
					if id == "call_best_pass" and p.kind == "run":
						continue
					names.append(n)
				# lean towards what the other side has actually been calling this game
				var seen := {}
				for nm in calls[1 - team]:
					seen[nm] = int(calls[1 - team][nm][0])
				var best := PlayStats.best_of(names, need_yards(), not on_offense, seen)
				if best.is_empty():
					return false
				out["kind"] = "play"
				out["play"] = best[rng.randi() % best.size()][0]
				return true
			"punt":
				if not on_offense:
					return false
				out["kind"] = "punt"
				return true
			"field_goal":
				return false   # no field goals in this game: the next rule decides
			"kneel":
				if not on_offense:
					return false
				out["kind"] = id
				return true
			"go_for_it":
				return true
		return false
	var sense := func(id: String, a: Array) -> bool:
		return _coach_sense(id, a, team, on_offense)
	out["line"] = Dsl.run(rules, sense, act, {}, 0.0, Coach.MODIFIERS, coach_tally[team] if count else {})
	if out["kind"] == "":
		var opts := Library.plays_for("offense" if on_offense else "defense")
		out["kind"] = "play"
		out["play"] = opts[rng.randi() % opts.size()]
	return out


## Which card in a dealt hand the coach would call: his own call from the playbook, matched to
## the closest play in the hand. {index, call} - call is the playbook play he had in mind.
func coach_suggest(on_offense: bool, hand: Array) -> Dictionary:
	var team := poss if on_offense else 1 - poss
	var c: Coach = (offense() if on_offense else defense())["coach"]
	var d := _coach_call(c, on_offense, team, false)
	if String(d.get("kind", "")) == "punt":
		return {"index": -1, "call": "punt", "why": _rule_text(c, on_offense, int(d.get("line", -1)))}
	var want: Play = Library.play(String(d.get("play", "")))
	if want == null:
		return {"index": -1, "call": String(d.get("kind", ""))}
	# which of his rules decided it, in his own words
	var why := "nothing special: his usual mix"
	for rr in (c.offense_rules if on_offense else c.defense_rules):
		if int(rr["line"]) == int(d.get("line", -1)):
			why = String(rr["text"])
	var fw := Play.features(want)
	var best := -1
	var best_d := INF
	for i in hand.size():
		var dist := Play.feature_distance(fw, Play.features(hand[i]["play"]))
		if dist < best_d:
			best_d = dist
			best = i
	return {"index": best, "call": want.name, "why": why, "grade": PlayStats.grade(want.name, need_yards(), not on_offense), "need": need_yards()}


func _rule_text(c: Coach, on_offense: bool, line: int) -> String:
	for rr in (c.offense_rules if on_offense else c.defense_rules):
		if int(rr["line"]) == line:
			return String(rr["text"])
	return ""


## The yards that make this a successful play - the usual football measure: 40% of the
## distance on first down, 60% on second, all of it on third and fourth (never past the goal line).
func need_yards() -> float:
	var share: float = [1.0, 0.4, 0.6, 1.0, 1.0][clampi(down, 0, 4)]
	return maxf(1.0, minf(ceilf(to_go * share), 100.0 - yl))


func _coach_sense(id: String, a: Array, team: int, on_offense: bool) -> bool:
	var diff: int = score[team] - score[1 - team]
	var to_goal := 100.0 - yl
	match id:
		"always": return true
		"chance": return rng.randf() < float(a[0])
		"down_is": return down == int(a[0])
		"first_down": return down == 1
		"second_down": return down == 2
		"third_down": return down == 3
		"fourth_down": return down == 4
		"to_go_over": return to_go > float(a[0])
		"to_go_under": return to_go < float(a[0])
		"goal_to_go": return yl + to_go >= 100.0
		"goal_within": return to_goal < float(a[0])
		"fg_range": return to_goal + 17.0 <= 52.0
		"own_goal_within": return yl < float(a[0])
		"backed_up": return yl < 10.0
		"red_zone": return to_goal <= 20.0
		"past_midfield": return yl > 50.0
		"leading_by": return diff > int(a[0])
		"trailing_by": return -diff > int(a[0])
		"winning": return diff > 0
		"losing": return diff < 0
		"tied": return diff == 0
		"quarter_is": return quarter == int(a[0])
		"clock_under": return clock < float(a[0])
		"half_ending": return (quarter == 2 or quarter == 4) and clock < 120.0
		"game_ending": return quarter == 4 and clock < 150.0
		"last_call_was": return last_call[team] == String(a[0])
		"last_gained_over": return last_gain[team] > float(a[0])
		"last_failed": return last_gain[team] < 3.0
		"avg_over", "avg_under":
			var c: Array = calls[team].get(String(a[0]), [0, 0.0])
			if int(c[0]) < 2:
				return false
			var avg := float(c[1]) / float(c[0])
			return avg > float(a[1]) if id == "avg_over" else avg < float(a[1])
		"called_over": return int(calls[team].get(String(a[0]), [0, 0.0])[0]) > int(a[1])
		"pass_avg_over", "pass_avg_under", "run_avg_over", "run_avg_under":
			var st: Dictionary = stats[team]
			var n := int(st["pass_att"]) if id.begins_with("pass") else int(st["rush_att"])
			if n < 3:
				return false
			var avg2 := (float(st["pass_yds"]) if id.begins_with("pass") else float(st["rush_yds"])) / n
			return avg2 > float(a[0]) if id.ends_with("over") else avg2 < float(a[0])
		"they_ran_last": return last_kind[1 - team] == "run"
		"they_passed_last": return last_kind[1 - team] == "pass"
		"they_run_over", "they_pass_over":
			var k: Dictionary = kinds[1 - team]
			var tot := int(k["run"]) + int(k["pass"])
			if tot < 4:
				return false
			var share := float(k["run"] if id == "they_run_over" else k["pass"]) / tot
			return share > float(a[0])
	return false


## A punt: rolled, not played out. About 43 yards, a short return; into the end zone is a
## touchback at the 20.
func _punt(kind := "punt") -> Dictionary:
	var kicker := poss
	var pr := _specialist(kicker, "P")
	var leg := _leg(kicker, "P")
	var acc := Robot.eff(pr, "accuracy") if not pr.is_empty() else 60.0
	var gross := 43.0 + (leg - 60.0) * 0.22 + rng.randfn(0.0, 5.5 * clampf(1.3 - (acc - 60.0) / 80.0, 0.6, 1.6))
	if kind == "pooch":
		gross = minf(gross, 100.0 - yl - rng.randf_range(6.0, 14.0))     # high and short, to pin them
	elif kind == "coffin":
		gross = minf(gross - 4.0, 100.0 - yl - rng.randf_range(3.0, 12.0) + rng.randfn(0.0, 3.0 * clampf(1.3 - (acc - 60.0) / 80.0, 0.6, 1.6)))
	var land := yl + gross
	var st: Dictionary = stats[poss]
	st["punts"] = int(st.get("punts", 0)) + 1
	var who: String = offense()["name"]
	var text := ""
	drive["result"] = "punt"
	if land >= 100.0:
		poss = 1 - poss
		yl = 20.0
		down = 1
		to_go = 10.0
		_new_drive()
		text = "%s punt into the end zone. Touchback." % who
	else:
		_take_over(land)
		if kind == "coffin":
			text = "%s angles it out of bounds: a %d-yard coffin corner, out at the %s." % [_who(pr, who), int(round(gross)), _spot_text(yl, poss)]
		elif land < 95.0:
			# he fields it: the punt and the return are played out as the next snap
			return_due = {"kind": "punt", "kicker": kicker, "catch": yl, "depth": 10.0, "gap": 40.0,
				"hang": 4.6 if kind == "pooch" else 3.9, "kick_dist": gross + 12.0, "pooch": kind == "pooch"}
			text = "%s punts it away." % _who(pr, who)
		else:
			text = "%s punts %d yards, downed at the %s." % [_who(pr, who), int(round(gross)), _spot_text(yl, poss)]
	ball_x = 0.0
	_tick(9.0, true)
	var e := {"kind": "punt", "text": text}
	_log_play(e)
	return e


func _kneel() -> Dictionary:
	yl = maxf(yl - 1.0, 1.0)
	var e := {"kind": "kneel", "text": "%s take a knee." % offense()["name"]}
	_advance_down(-1.0)
	_tick(40.0, false)
	_log_play(e)
	return e


func _log_play(e: Dictionary) -> void:
	e["q"] = quarter
	e["clock"] = clock
	e["score"] = score.duplicate()
	log.append(e)


## The play is over: move the ball, the downs, the clock and the score.
## Parts that came off this game: [{team, slot, name, part, q}]
var broken: Array = []
var hurt := {}                 # robot id -> true: took some damage this game


## A team's coach deals with any robot missing a part: a better sub, or junk bolted on.
func coach_fixes(t: int) -> Array:
	var tm: Dictionary = teams[t]
	var out: Array = []
	if not tm.has("roster"):
		return out
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		var line := Career.coach_fix(tm["roster"], tm.get("bench", []), s)
		if line != "":
			out.append(line)
			_say(line)
	return out


func finish(sim: PlaySim) -> Dictionary:
	var r: Dictionary = sim.result
	for id in sim.hurt_ids:
		hurt[id] = true
	for pl: Dictionary in sim.parts_lost:
		var p: PlaySim.P = sim.players[int(pl["idx"])]
		broken.append({"team": p.team, "slot": p.slot, "name": String(p.robot.get("name", p.slot)), "part": pl["part"], "q": quarter, "id": String(p.robot.get("id", ""))})
	if pending.has("return"):
		return _finish_return(sim)
	var op: Play = pending["off"]
	var dp: Play = pending["def"]
	var team := poss
	var st: Dictionary = stats[team]
	var dst: Dictionary = stats[1 - team]
	plays_run += 1
	st["plays"] = int(st["plays"]) + 1
	drive["plays"] = int(drive["plays"]) + 1
	var gain := 0.0 if r["incomplete"] else float(r["y"])
	var was_down := down
	var was_to_go := to_go
	# the box score
	if r["pass"]:
		st["pass_att"] = int(st["pass_att"]) + 1
		if r.has("pass_yds"):
			st["comp"] = int(st["comp"]) + 1
			st["pass_yds"] = float(st["pass_yds"]) + gain
	elif r["sack"]:
		st["sacks"] = int(st["sacks"]) + 1
		st["sack_yds"] = float(st["sack_yds"]) + gain
	elif r.has("rush_yds"):
		st["rush_att"] = int(st["rush_att"]) + 1
		st["rush_yds"] = float(st["rush_yds"]) + gain
	var kind := "pass" if op.kind != "run" else "run"
	kinds[team][kind] = int(kinds[team][kind]) + 1
	last_kind[team] = kind
	last_call[team] = op.name
	last_call[1 - team] = dp.name
	var c: Array = calls[team].get(op.name, [0, 0.0])
	calls[team][op.name] = [int(c[0]) + 1, float(c[1]) + (gain if r["turnover"] == "" else -20.0)]
	var dc: Array = calls[1 - team].get(dp.name, [0, 0.0])
	calls[1 - team][dp.name] = [int(dc[0]) + 1, float(dc[1]) + (gain if r["turnover"] == "" else -20.0)]
	if was_down == 3:
		st["third_att"] = int(st["third_att"]) + 1
	if was_down == 4:
		st["fourth_att"] = int(st["fourth_att"]) + 1
	if gain >= 20.0:
		st["explosive"] = int(st["explosive"]) + 1
	var desc := _describe(sim, op, dp, gain)
	var e := {"kind": "play", "team": team, "off": op.name, "def": dp.name, "gain": gain, "why": r["why"], "text": desc,
		"down": was_down, "to_go": was_to_go, "yl": yl}
	down_event = ""
	_player_stats(sim, team, gain)
	if pending.get("off_text", "") != "":
		e["off_text"] = pending["off_text"]
	if pending.get("def_text", "") != "":
		e["def_text"] = pending["def_text"]
	var elapsed := float(r["t"])
	# the ball carried to (or over) the goal line is a touchdown, whatever the sim called it
	if not r["td"] and not r["incomplete"] and r["turnover"] == "" and not r.get("safety", false) and yl + gain >= 100.0:
		r["td"] = true
		e["text"] += " Over the line!"
	# the outcome
	if r.get("def_td", false):
		st["turnovers"] = int(st["turnovers"]) + 1
		st["ints"] = int(st["ints"]) + (1 if r["turnover"] == "int" else 0)
		dst["td"] = int(dst["td"]) + 1
		_pts(1 - team, 7)
		e["text"] += " Returned for a TOUCHDOWN!"
		drive["result"] = "pick six"
		_tick(elapsed, true)
		e["text"] += " " + _kickoff(team)
	elif r["turnover"] != "":
		st["turnovers"] = int(st["turnovers"]) + 1
		if r["turnover"] == "int":
			st["ints"] = int(st["ints"]) + 1
		else:
			st["fumbles"] = int(st["fumbles"]) + 1
		drive["result"] = "INT" if r["turnover"] == "int" else "fumble"
		# they take over where the return ended (a touchback if it ended in their own end zone)
		var spot_y := yl + float(r["y"])
		_tick(elapsed, true)
		ball_x = clampf(float(r["x"]), -HASH, HASH)
		if spot_y >= 100.0:
			_take_over(80.0)
			e["text"] += " Touchback."
		else:
			_take_over(spot_y)
	elif r.get("safety", false):
		_pts(1 - team, 7)
		e["text"] += " SAFETY - 7 points!"
		drive["result"] = "safety"
		_tick(elapsed, true)
		e["text"] += " " + _kickoff(1 - team)
	elif r["td"]:
		st["td"] = int(st["td"]) + 1
		st["yards"] = float(st["yards"]) + gain
		drive["yards"] = float(drive["yards"]) + gain
		_pts(team, 7)
		drive["result"] = "TD"
		_tick(elapsed, true)
		e["text"] += " " + _kickoff(1 - team)
	else:
		st["yards"] = float(st["yards"]) + gain
		drive["yards"] = float(drive["yards"]) + gain
		if not r["incomplete"]:
			ball_x = clampf(float(r["x"]), -HASH, HASH)
		var goal_to_go := yl + to_go >= 99.9
		yl = clampf(yl + gain, 0.5, 99.5)
		_advance_down(gain, goal_to_go)
		var stops: bool = r["clock_stops"]
		_tick(elapsed + (0.0 if stops else _runoff(team)), stops)
	last_gain[team] = gain
	e["down_event"] = down_event
	_log_play(e)
	return e


func _runoff(team: int) -> float:
	# hurry up when behind late; milk it when ahead
	var diff: int = score[team] - score[1 - team]
	if (quarter == 4 or quarter == 2) and clock < 150.0 and diff <= 0:
		return 12.0
	if quarter == 4 and diff > 0:
		return 36.0
	return 27.0


func _advance_down(gain: float, goal_to_go := false) -> void:
	var st: Dictionary = stats[poss]
	if goal_to_go:
		# first and goal: there is no first down to be had, only the end zone. Stopped short
		# (however close), it is the next down with the goal still to go.
		to_go = maxf(100.0 - yl, 0.5)
		down += 1
		if down > 4:
			down_event = "downs"
			drive["result"] = "downs"
			_take_over(yl)
		return
	if gain >= to_go:
		if down == 3:
			st["third_conv"] = int(st["third_conv"]) + 1
		if down == 4:
			st["fourth_conv"] = int(st["fourth_conv"]) + 1
		st["first_downs"] = int(st["first_downs"]) + 1
		down_event = "first_down"
		down = 1
		to_go = minf(10.0, 100.0 - yl)
		return
	to_go -= gain
	down += 1
	if down > 4:
		down_event = "downs"
		drive["result"] = "downs"
		_take_over(yl)          # they take over right where he was stopped


## The player box score.
const PSTAT_KEYS := ["cmp", "att", "pyd", "ptd", "int", "sk", "skyd", "car", "ryd", "rtd", "rlong",
	"tgt", "rec", "recyd", "rectd", "reclong", "tkl", "sack", "dint", "pbu", "ff", "fr", "mt", "dtd", "fum"]


func _ps(t: int, slot: String) -> Dictionary:
	if slot == "":
		return {}
	if not pstats[t].has(slot):
		var d := {}
		for k in PSTAT_KEYS:
			d[k] = 0.0
		pstats[t][slot] = d
	return pstats[t][slot]


func _add(t: int, slot: String, k: String, v := 1.0) -> void:
	if slot == "":
		return
	var d := _ps(t, slot)
	d[k] = float(d[k]) + v


func _long(t: int, slot: String, k: String, v: float) -> void:
	if slot == "":
		return
	var d := _ps(t, slot)
	d[k] = maxf(float(d[k]), v)


func _player_stats(sim: PlaySim, off_t: int, gain: float) -> void:
	var r: Dictionary = sim.result
	var st: Dictionary = r["stat"]
	var def_t := 1 - off_t
	var offense_carrier := int(r.get("carrier_side", 0)) == 0
	if r["pass"]:
		var tgt := String(st.get("target", ""))
		if tgt != "":
			_add(off_t, "QB", "att")
			_add(off_t, tgt, "tgt")
		if r.has("pass_yds"):
			var rcv := String(st.get("catch_slot", ""))
			_add(off_t, "QB", "cmp")
			_add(off_t, "QB", "pyd", gain)
			_add(off_t, rcv, "rec")
			_add(off_t, rcv, "recyd", gain)
			_long(off_t, rcv, "reclong", gain)
			if r["td"] and offense_carrier:
				_add(off_t, "QB", "ptd")
				_add(off_t, rcv, "rectd")
		if r["turnover"] == "int":
			_add(off_t, "QB", "int")
	elif r["sack"]:
		_add(off_t, "QB", "sk")
		_add(off_t, "QB", "skyd", gain)
	elif r.has("rush_yds") or st.has("fumbler"):
		var ru := String(st.get("rusher", r["carrier"]))
		_add(off_t, ru, "car")
		if r.has("rush_yds"):
			_add(off_t, ru, "ryd", gain)
			_long(off_t, ru, "rlong", gain)
			if r["td"] and offense_carrier:
				_add(off_t, ru, "rtd")
	# defense (and offense, when they tackle after a turnover)
	for k in st:
		var ks := String(k)
		if ks.begins_with("sack:"):
			_add(def_t, ks.substr(5), "sack")
		elif ks.begins_with("int_by:"):
			_add(def_t, ks.substr(7), "dint")
		elif ks.begins_with("missed:"):
			_add(def_t if offense_carrier else off_t, ks.substr(7), "mt", float(st[k]))
		elif ks.begins_with("fumble:"):
			_add(off_t, ks.substr(7), "fum")
	if st.has("tackler") and r["why"] in ["tackle", "sack"] or (st.has("tackler") and st.has("ff_by")):
		_add(def_t if offense_carrier else off_t, String(st["tackler"]), "tkl")
	if st.has("pbu_by"):
		_add(def_t, String(st["pbu_by"]), "pbu")
	if st.has("ff_by"):
		_add(def_t, String(st["ff_by"]), "ff")
	if st.has("fr_by"):
		_add(def_t, String(st["fr_by"]), "fr")
	if r.get("def_td", false):
		_add(def_t, String(r["carrier"]), "dtd")


func _pts(t: int, n: int) -> void:
	score[t] += n
	line[t][clampi(quarter, 1, 4) - 1] += n


func _tick(secs: float, _stops: bool) -> void:
	var st: Dictionary = stats[poss]
	st["top"] = float(st["top"]) + minf(secs, clock)
	clock -= secs
	if clock <= 0.0:
		quarter_ends.append({"q": quarter, "score": score.duplicate(), "line": line.duplicate(true),
			"stats": stats.duplicate(true), "pstats": pstats.duplicate(true)})
		quarter += 1
		clock = qlen
		if quarter == 3:
			# second half: the other side receives
			_kickoff(1 - opened)
			_say("Second half. %s receive." % teams[poss]["name"])
		elif quarter > 4:
			over = true
			drive["result"] = drive.get("result", "") if drive.get("result", "") != "" else "end of game"
			drives.append(drive)
			_say("Final: %s %d, %s %d" % [teams[0]["name"], score[0], teams[1]["name"], score[1]])
		else:
			_say("End of quarter %d." % (quarter - 1))


func winner() -> int:
	if score[0] == score[1]:
		return -1
	return 0 if score[0] > score[1] else 1


func situation() -> String:
	var side := "own" if yl <= 50.0 else "opp"
	var line := int(round(yl if yl <= 50.0 else 100.0 - yl))
	var dn: String = ["", "1st", "2nd", "3rd", "4th"][clampi(down, 1, 4)]
	var tg := "Goal" if yl + to_go >= 100.0 else str(maxi(int(round(to_go)), 1))
	if line == 50:
		return "%s & %s at midfield" % [dn, tg]
	return "%s & %s, %s %d" % [dn, tg, side, line]


func _describe(sim: PlaySim, op: Play, dp: Play, gain: float) -> String:
	var r: Dictionary = sim.result
	var yd := int(round(gain))
	var s := ""
	var who := String(r["carrier"])
	match String(r["why"]):
		"incomplete", "broken up":
			s = "Pass incomplete" + (" (broken up)" if r["why"] == "broken up" else "")
		"sack":
			s = "SACKED for %d" % yd
		"td":
			s = "TOUCHDOWN %s, %d yards" % [who, yd]
		"out":
			s = "%s out of bounds, %+d" % [who, yd]
		_:
			if r["turnover"] == "int":
				s = "INTERCEPTED"
			elif r["turnover"] == "fumble":
				s = "FUMBLE, lost"
			elif r["pass"]:
				s = "Complete to %s, %+d" % [who, yd]
			else:
				s = "%s runs, %+d" % [who, yd]
	return "%s vs %s: %s" % [op.name, dp.name, s]


## Everything in one dictionary, for the result panel and the batch.
func summary() -> Dictionary:
	return {"line": line.duplicate(true), "pstats": pstats.duplicate(true), "score": score.duplicate(), "winner": winner(), "stats": stats.duplicate(true), "calls": calls.duplicate(true),
		"drives": drives.duplicate(true), "plays": plays_run, "coach_tally": coach_tally.duplicate(true)}
