class_name Career
extends RefCounted
## The career save: each side's robots (22 starters by slot plus a bench), kept in the browser
## at user://career.json. For now the two sides are your team (Red) and one rival (Blue); the
## league of rival teams comes in a later step.
##
## Nothing here is loaded in headless runs unless asked: batches and tests play with the equal
## bodies of Gridiron Bots unless they build rosters themselves.

const PATH := "user://career.json"
const BENCH := ["QB", "RB", "WR", "TE", "OL", "OL", "DL", "LB", "CB", "S"]
const TEAM_NAMES := ["Red Rivets", "Blue Bolts"]

static var data := {}          # {version, fair, teams: [{name, starters: {slot: robot}, bench: [robot]}]}
static var loaded := false


static func ensure() -> void:
	if loaded:
		return
	loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).has("teams"):
			data = parsed
			return
	data = {"version": 1, "fair": false, "teams": [new_team(0), new_team(1)]}
	save()


static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


static func new_team(t: int, seed_v := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_v >= 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	var starters := {}
	var used := {}
	var n := 0
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		starters[s] = Robot.make(rng, s, _number(rng, s, used), "t%d-%d" % [t, n])
		n += 1
	var bench: Array = []
	for g in BENCH:
		var slot: String = (Play.GROUP_SLOTS.get(g, [g]) as Array)[0]
		var r := Robot.make(rng, slot, _number(rng, slot, used), "t%d-%d" % [t, n])
		r["slot"] = ""          # on the bench: no slot until he goes in
		r["group"] = g
		bench.append(r)
		n += 1
	return {"name": TEAM_NAMES[t], "starters": starters, "bench": bench}


## Jersey numbers by position, roughly as the real game hands them out.
static func _number(rng: RandomNumberGenerator, slot: String, used: Dictionary) -> int:
	var g: String = Play.SLOT_GROUP.get(slot, slot)
	var ranges := {"QB": [1, 19], "RB": [20, 49], "WR": [10, 19], "TE": [80, 89], "OL": [50, 79],
		"DL": [90, 99], "LB": [40, 59], "CB": [20, 39], "S": [20, 49]}
	var r: Array = ranges.get(g, [1, 99])
	for i in 200:
		var k := rng.randi_range(int(r[0]), int(r[1]))
		if not used.has(k):
			used[k] = true
			return k
	return rng.randi_range(1, 99)


static func team(t: int) -> Dictionary:
	ensure()
	return data["teams"][t]


static func roster(t: int) -> Dictionary:
	return team(t)["starters"]


static func fair() -> bool:
	ensure()
	return bool(data.get("fair", false))


static func set_fair(on: bool) -> void:
	ensure()
	data["fair"] = on
	save()


static func regenerate(t: int) -> void:
	ensure()
	data["teams"][t] = new_team(t)
	save()


## Find a robot by id on either team: {team, robot, where ("starter"/"bench"), slot}.
static func find(id: String) -> Dictionary:
	ensure()
	for t in 2:
		var tm: Dictionary = data["teams"][t]
		for s in tm["starters"]:
			if String(tm["starters"][s]["id"]) == id:
				return {"team": t, "robot": tm["starters"][s], "where": "starter", "slot": s}
		for r in tm["bench"]:
			if String(r["id"]) == id:
				return {"team": t, "robot": r, "where": "bench", "slot": ""}
	return {}


## Swap a bench robot in for a starter of the same position group.
static func swap(t: int, slot: String, bench_id: String) -> bool:
	var tm := team(t)
	var ok := swap_in(tm["starters"], tm["bench"], slot, bench_id)
	if ok:
		save()
	return ok


## Swap a bench robot in for the starter at `slot` (the same position group); the starter sits.
static func swap_in(starters: Dictionary, bench: Array, slot: String, bench_id: String) -> bool:
	for i in bench.size():
		var b: Dictionary = bench[i]
		if String(b["id"]) == bench_id and String(b["group"]) == String(Play.SLOT_GROUP[slot]):
			var out: Dictionary = starters[slot]
			b["slot"] = slot
			out["slot"] = ""
			starters[slot] = b
			bench[i] = out
			return true
	return false


## The best healthy bench robot for a slot, or {}.
static func best_sub(bench: Array, slot: String) -> Dictionary:
	var best := {}
	for b: Dictionary in bench:
		if String(b["group"]) == String(Play.SLOT_GROUP[slot]) and Robot.can_play(b):
			if best.is_empty() or Robot.effective_overall(b) > Robot.effective_overall(best):
				best = b
	return best


## A quarterback who loses an arm gets a standard (Stock) one put straight back on: nobody
## plays quarterback one-armed. Returns a line for the log, or "".
static func qb_arms(starters: Dictionary) -> String:
	var qb: Dictionary = starters.get("QB", {})
	if qb.is_empty():
		return ""
	var fixed: Array = []
	for k in ["larm", "rarm"]:
		if Robot.part_lost(qb, k):
			Robot.repair(qb, k)
			fixed.append(String(Robot.PART_LABEL[k]).to_lower())
	if fixed.is_empty():
		return ""
	return "%s gets a new standard %s." % [qb["name"], " and ".join(fixed)]


## Put any healthy bench robot (any position) in at `slot`; the starter sits.
static func swap_any(starters: Dictionary, bench: Array, slot: String, bench_id: String) -> bool:
	for i in bench.size():
		var b: Dictionary = bench[i]
		if String(b["id"]) == bench_id:
			var out: Dictionary = starters[slot]
			b["slot"] = slot
			out["slot"] = ""
			starters[slot] = b
			bench[i] = out
			return true
	return false


## What a coach does about a broken robot at `slot`: put in a better sub if there is one,
## else bolt junk on whatever is missing. Returns a line for the log, or "".
static func coach_fix(starters: Dictionary, bench: Array, slot: String) -> String:
	var r: Dictionary = starters[slot]
	var qb_line := qb_arms(starters) if slot == "QB" else ""
	var lost := Robot.lost_parts(r)
	if lost.is_empty():
		return qb_line
	var sub := best_sub(bench, slot)
	var patched := Robot.effective_overall(r)
	for k in lost:
		patched += 4.0 + {"head": 30.0, "core": 60.0, "larm": 14.0, "rarm": 14.0, "lleg": 25.0, "rleg": 25.0}[k] - 8.0
	if not sub.is_empty() and Robot.effective_overall(sub) > patched:
		swap_in(starters, bench, slot, String(sub["id"]))
		return "%s comes in for %s at %s." % [sub["name"], r["name"], slot]
	for k in lost:
		Robot.bolt_on_junk(r, k)
	return "%s gets a junk %s bolted on." % [r["name"], " and junk ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))]
