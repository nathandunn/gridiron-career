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


## Every robot in the save, wherever he is (teams, rival clubs, the exhibition and sim-lab
## teams, the market, special teams, benches).
static func _all_robots() -> Array:
	var out: Array = []
	var visit: Array = [data]
	while not visit.is_empty():
		var v: Variant = visit.pop_back()
		if v is Dictionary:
			var d: Dictionary = v
			if d.has("ratings") and d.has("group") and d.has("name"):
				out.append(d)
				continue
			for k in d:
				visit.append(d[k])
		elif v is Array:
			visit.append_array(v)
	return out


static func _register_names() -> void:
	Robot.used_names = {}
	for r in _all_robots():
		Robot.used_names[String(r["name"])] = true


## Saves from before ratings had position averages: shift each robot's core ratings by his
## position's average, so he plays exactly as before (a 60-speed lineman becomes a 40).
static func _position_ratings() -> void:
	if bool(data.get("pos_ratings", false)):
		return
	for r in _all_robots():
		var g := String(r["group"])
		for k in Robot.CORE:
			if (r["ratings"] as Dictionary).has(k):
				r["ratings"][k] = int(clampf(float(r["ratings"][k]) + Robot.mean_for(g, k) - Robot.BASE, 5.0, 99.0))
	data["pos_ratings"] = true
	save()


## Saves from before robots were the sum of their parts: every robot's ratings go back to his
## position's base (plating bought before this cannot be told from his old ratings, so it goes), so
## the same parts make the same robot on any team.
static func _parts_only() -> void:
	if bool(data.get("parts_only", false)):
		return
	for r in _all_robots():
		if not r.has("armor"):
			r["armor"] = 0
		Robot.reset_ratings(r)
	data["parts_only"] = true
	save()


static func ensure() -> void:
	if loaded:
		return
	loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).has("teams"):
			data = parsed
			# there is one purse: any upgrade credit left from before goes into it
			if data.has("credit"):
				for t in 2:
					data["money"] = data.get("money", [START_MONEY, START_MONEY])
					data["money"][t] = int(data["money"][t]) + int(data["credit"][t])
				data.erase("credit")
				save()
			# saves from before every team started with its upgrades get them now
			if not bool(data.get("starter_upgrades", false)):
				# the rival's coach fits his; you get yours as credit to spend (or hand to the coach)
				starter_upgrades(data["teams"][1])
				add_money(1, int(data["teams"][1].get("leftover", 0)))
				money(0)
				add_money(0, STARTER_BUDGET)          # yours goes in the purse, to spend as you like
				data["starter_upgrades"] = true
				save()
			_position_ratings()
			_parts_only()
			_register_names()
			if not data.has("season"):
				_season_around_current()      # saves from before seasons: this becomes week 1 of one
				data["money"][0] = maxi(int(data["money"][0]), STARTER_BUDGET)   # and a season starts with $2,000
				save()
			_give_defenses()
			return
	Robot.used_names = {}
	data = {"version": 1, "fair": false, "teams": [new_team(0, -1, false), new_team(1, -1, false)], "starter_upgrades": true, "mode": "season", "pos_ratings": true, "parts_only": true}
	_fresh_season()
	save()


static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()
		CloudSave.queue()     # and up to the cloud shortly (see cloud.gd)


static func new_team(t: int, seed_v := -1, fit := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_v >= 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	var starters := {}
	var used := {}
	var n := 0
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		starters[s] = Robot.make(rng, s, _number(rng, s, used), "t%d-%d" % [t, n], true)
		n += 1
	var bench: Array = []
	for g in BENCH:
		var slot: String = (Play.GROUP_SLOTS.get(g, [g]) as Array)[0]
		var r := Robot.make(rng, slot, _number(rng, slot, used), "t%d-%d" % [t, n], true)
		r["slot"] = ""          # on the bench: no slot until he goes in
		r["group"] = g
		bench.append(r)
		n += 1
	var tm := {"name": TEAM_NAMES[t], "starters": starters, "bench": bench}
	tm["special"] = _make_special(rng, t, used)
	if fit:
		starter_upgrades(tm, rng)
	best_lineup(tm)
	return tm


## ---- lineups: the best start, the worst sit -------------------------------------------------------
const LINEUP_GROUPS := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S"]


static func _slots_of(g: String) -> Array:
	return Play.GROUP_SLOTS.get(g, [g])


static func _lineup_score(r: Dictionary, g: String) -> float:
	if not Robot.can_play(r):
		return -1000.0
	return float(Robot.overall_at(r, g)) + (0.5 if String(r.get("group", "")) == g else 0.0)


## At every position the healthiest, highest-rated robots start (anyone already playing there,
## and the bench men of that position); the rest go to the bench.
static func best_lineup(tm: Dictionary) -> void:
	var starters: Dictionary = tm["starters"]
	var everyone: Array = (starters.values() + (tm["bench"] as Array)).filter(func(r): return not (r as Dictionary).is_empty())
	for g in LINEUP_GROUPS:
		var slots := _slots_of(g)
		var pool: Array = []
		for s in slots:
			if starters.has(s) and not (starters[s] as Dictionary).is_empty():
				pool.append(starters[s])
		for b in tm["bench"]:
			if String(b.get("group", "")) == g and not pool.any(func(x): return is_same(x, b)):
				pool.append(b)
		pool.sort_custom(func(a, b): return _lineup_score(a, g) > _lineup_score(b, g))
		for i in mini(slots.size(), pool.size()):
			starters[slots[i]] = pool[i]
			pool[i]["slot"] = slots[i]
	var bench: Array = []
	for r in everyone:
		if not starters.values().any(func(x): return is_same(x, r)):
			r["slot"] = ""
			bench.append(r)
	tm["bench"] = bench


## Before a kickoff: both sides put their best robots out (yours too, unless you set your own).
static func auto_lineups() -> void:
	for t in 2:
		if t == 0 and not bool(data.get("auto_lineup", true)):
			continue
		best_lineup(team(t))
	save()


## ---- selling, scrapping and trading robots ----------------------------------------------------
## Why `robot` can't leave your team, or "" if he can (someone on the bench must be able to take
## his place if he starts; kickers and punters stay for now).
static func cant_part_with(t: int, robot: Dictionary) -> String:
	var g := String(robot.get("group", ""))
	if g in ["K", "P"]:
		return "Kickers and punters can't be sold or traded yet."
	var tm := team(t)
	for s in tm["starters"]:
		if is_same(tm["starters"][s], robot):
			for b in tm["bench"]:
				if fits(b, s) and Robot.can_play(b):
					return ""
			return "Nobody on the bench can play %s: buy or trade for one first." % s
	return ""


## Take `robot` off team `t`, his place (if he started) going to the best bench man who fits.
static func _take_off(t: int, robot: Dictionary) -> void:
	var tm := team(t)
	for s in tm["starters"]:
		if is_same(tm["starters"][s], robot):
			var best := {}
			for b in tm["bench"]:
				if fits(b, s) and Robot.can_play(b) and (best.is_empty() or Robot.overall_at(b, String(Play.SLOT_GROUP[s])) > Robot.overall_at(best, String(Play.SLOT_GROUP[s]))):
					best = b
			tm["starters"][s] = best
			best["slot"] = s
			tm["bench"].erase(best)
			best_lineup(tm)
			return
	for i in (tm["bench"] as Array).size():
		if is_same(tm["bench"][i], robot):
			tm["bench"].remove_at(i)
			return


## What his parts fetch as scrap: a share of their price, by tier and condition.
static func scrap_value(r: Dictionary) -> int:
	var v := 0.0
	for k in Robot.PARTS:
		var pt: Dictionary = Robot.ensure_parts(r)[k]
		var tier := String(pt["tier"])
		var mx := float(Robot.TIER_HP.get(tier, 100))
		v += float(PART_PRICE[k]) * {"Junk": 0.1, "Stock": 1.0, "Mk II": 2.0, "Mk III": 3.5, "Prototype": 6.0}.get(tier, 1.0) * clampf(float(pt["hp"]) / mx, 0.0, 1.0)
	return int(roundf(v * 0.25 / 10.0)) * 10


static func scrap(t: int, robot: Dictionary) -> int:
	if cant_part_with(t, robot) != "":
		return 0
	var v := scrap_value(robot)
	_take_off(t, robot)
	add_money(t, v)
	save()
	return v


## The other sides you can deal with: in a season the three rival clubs, in an exhibition the
## other team; none in the sim lab.
static func dealers() -> Array:
	if exhibition():
		return [team(1)]
	if sim_mode() or not data.has("season"):
		return []
	return data["season"]["clubs"]


static func _club_money(c: Dictionary) -> int:
	return money(1) if exhibition() else int(c.get("money", 0))


static func _club_pay(c: Dictionary, amount: int) -> void:
	if exhibition():
		add_money(1, amount)
	else:
		c["money"] = int(c.get("money", 0)) + amount


## Would he start for club `c`? (Better than their worst starter at his position.)
static func would_start(r: Dictionary, c: Dictionary) -> bool:
	var g := String(r.get("group", ""))
	var worst := 999.0
	for s in _slots_of(g):
		var x: Dictionary = c["starters"].get(s, {})
		if not x.is_empty():
			worst = minf(worst, float(Robot.overall_at(x, g)))
	return float(Robot.overall_at(r, g)) > worst


## What club `c` would pay for him: most of his price if he'd start for them, a little if not.
static func sell_offer(r: Dictionary, c: Dictionary) -> int:
	var f := 0.75 if would_start(r, c) else 0.35
	return int(roundf(robot_price(r) * f / 10.0)) * 10


static func sell_to(t: int, robot: Dictionary, c: Dictionary) -> bool:
	var offer := sell_offer(robot, c)
	if cant_part_with(t, robot) != "" or _club_money(c) < offer:
		return false
	_take_off(t, robot)
	robot["slot"] = ""
	(c["bench"] as Array).append(robot)
	best_lineup(c)
	_club_pay(c, -offer)
	add_money(t, offer)
	save()
	return true


## A trade: your `mine` for their `theirs` (same position), plus `cash` from you. They take it
## if what they get is worth at least what they give.
static func trade_gap(mine: Dictionary, theirs: Dictionary) -> int:
	return maxi(int(roundf((robot_price(theirs) * 0.95 - robot_price(mine)) / 10.0)) * 10, 0)


static func trade(t: int, mine: Dictionary, c: Dictionary, theirs: Dictionary) -> bool:
	var cash := trade_gap(mine, theirs)
	if money(t) < cash:
		return false
	var tm := team(t)
	# theirs takes mine's place on your side, and mine his on theirs
	var swapped := false
	for s in tm["starters"]:
		if is_same(tm["starters"][s], mine):
			tm["starters"][s] = theirs
			swapped = true
	if not swapped:
		tm["bench"].erase(mine)
		tm["bench"].append(theirs)
	var their_swapped := false
	for s in c["starters"]:
		if is_same(c["starters"][s], theirs):
			c["starters"][s] = mine
			their_swapped = true
	if not their_swapped:
		c["bench"].erase(theirs)
		c["bench"].append(mine)
	best_lineup(tm)
	best_lineup(c)
	if cash > 0:
		add_money(t, -cash)
		_club_pay(c, cash)
	save()
	return true


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
	if exhibition():
		return data["exhibition"]["teams"][t]
	if sim_mode():
		return data["sim"]["team"] if t == 0 else data["sim"]["opps"][int(data["sim"].get("idx", 0))]
	if t == 1 and data.has("season"):
		return data["season"]["clubs"][int(data["season"].get("opp", 0))]
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
	# a redrafted team comes with $2,000 of upgrades already fitted (no money changes hands)
	var nt := new_team(t)
	if exhibition():
		data["exhibition"]["teams"][t] = nt
	elif sim_mode():
		var tm := team(t)
		for k in ["starters", "bench", "special"]:
			tm[k] = nt[k]
	elif t == 1 and data.has("season"):
		var club := team(1)
		for k in ["starters", "bench"]:
			club[k] = nt[k]
	else:
		data["teams"][t] = nt
	add_money(t, int(nt.get("leftover", 0)))
	save()


## Find a robot by id on either team: {team, robot, where ("starter"/"bench"), slot}.
## Special teams: a kicker (kickoffs) and a punter. Teams from before get theirs when first asked.
static func _make_special(rng: RandomNumberGenerator, t: int, used := {}) -> Dictionary:
	var out := {}
	for s in ["K", "P"]:
		var n := rng.randi_range(1, 19)
		var tries := 0
		while used.has(n) and tries < 40:
			n = rng.randi_range(1, 19)
			tries += 1
		used[n] = true
		var r := Robot.make(rng, s, n, "t%d-%s%d" % [t, s, rng.randi() % 100000], true)
		out[s] = r
	return out


static func special(t: int) -> Dictionary:
	var tm := team(t)
	if not tm.has("special"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		tm["special"] = _make_special(rng, t)
		save()
	return tm["special"]


static func find(id: String) -> Dictionary:
	ensure()
	for t in 2:
		var tm: Dictionary = team(t)
		for s in special(t):
			if String(tm["special"][s]["id"]) == id:
				return {"team": t, "robot": tm["special"][s], "where": "special", "slot": s}
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
## Who can stand in where: his own position, or one built much the same (no receiver on the
## defensive line, no lineman at quarterback).
const CAN_PLAY := {
	"QB": ["QB"], "RB": ["RB", "WR", "TE"], "WR": ["WR", "RB", "TE", "CB"], "TE": ["TE", "RB", "WR", "OL"],
	"OL": ["OL", "TE", "DL"], "DL": ["DL", "OL", "LB"], "LB": ["LB", "DL", "S"], "CB": ["CB", "S", "WR"],
	"S": ["S", "CB", "LB"], "K": ["K", "P"], "P": ["P", "K"],
}


static func fits(robot: Dictionary, slot: String) -> bool:
	var g: String = Play.SLOT_GROUP.get(slot, slot)
	return String(robot.get("group", "")) in (CAN_PLAY.get(g, [g]) as Array)


static func swap_any(starters: Dictionary, bench: Array, slot: String, bench_id: String) -> bool:
	for i in bench.size():
		var b: Dictionary = bench[i]
		if String(b["id"]) == bench_id:
			if not fits(b, slot):
				return false
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
	var bought: Array = []
	var t := team_of(r)
	# an empty purse buys nothing: he plays on without it if he can, or the best robot on the
	# bench from any position comes in; only if neither is possible is a junk spare found for him
	var junk_all := 0
	for k0 in lost:
		junk_all += junk_price(k0)
	if t >= 0 and money(t) < junk_all:
		if Robot.can_play(r):
			return "%s plays on without his %s (no money)." % [r["name"], " or ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))]
		var any := {}
		for b in bench:
			if Robot.can_play(b) and fits(b, slot) and (any.is_empty() or Robot.effective_overall(b) > Robot.effective_overall(any)):
				any = b
		if not any.is_empty():
			swap_any(starters, bench, slot, String(any["id"]))
			return "%s comes in for %s at %s (no money for parts)." % [any["name"], r["name"], slot]
		for k in lost:
			buy_junk(t, r, k, true)
		return "%s gets an emergency junk %s (purse empty)." % [r["name"], " and junk ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))]
	for k in lost:
		if t >= 0 and money(t) >= repair_cost(r, k) * 3 and buy_repair(t, r, k):
			bought.append(k)
		elif not buy_junk(t, r, k):
			continue
	if bought.size() == lost.size():
		return "%s gets a new %s." % [r["name"], " and new ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))]
	return "%s gets a junk %s bolted on." % [r["name"], " and junk ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))]


## ---- money -------------------------------------------------------------------------------------
## Each side has a purse. A junk spare is always free; a real (Stock) part costs money, and so
## does repairing a worn one. Games pay out at the final whistle.

const START_MONEY := 400
const PART_PRICE := {"head": 200, "core": 250, "larm": 120, "rarm": 120, "lleg": 140, "rleg": 140}
const PAY := {"win": 600, "tie": 350, "loss": 200, "td": 60, "sack": 25, "takeaway": 50}


static func money(t: int) -> int:
	ensure()
	if exhibition():
		return int(data["exhibition"]["money"][t])
	if sim_mode():
		return int(data["sim"]["money"]) if t == 0 else 0
	if t == 1 and data.has("season"):
		return int(team(1).get("money", 0))
	if not data.has("money"):
		data["money"] = [START_MONEY, START_MONEY]
	return int(data["money"][t])


static func add_money(t: int, amount: int) -> void:
	money(t)
	if exhibition():
		data["exhibition"]["money"][t] = int(data["exhibition"]["money"][t]) + amount
	elif sim_mode():
		if t == 0:
			data["sim"]["money"] = int(data["sim"]["money"]) + amount
	elif t == 1 and data.has("season"):
		team(1)["money"] = int(team(1).get("money", 0)) + amount
	else:
		data["money"][t] = int(data["money"][t]) + amount


static func spend(t: int, amount: int) -> bool:
	if money(t) < amount:
		return false
	add_money(t, -amount)
	save()
	return true


## What it costs to put a part right: a lost (or junk) part is a new Stock one at full price;
## a worn one costs a share of the price by how worn it is.
## What a repair costs: the same as a fix (where it's at). Junk he has is not damage.
static func repair_cost(robot: Dictionary, k: String) -> int:
	return fix_cost(robot, k)


## The price of a new part of a tier.
static func tier_price(k: String, tier: String) -> int:
	match tier:
		"Junk":
			return int(JUNK_PRICES[k])
		"Stock":
			return int(PART_PRICE[k])
	return upgrade_price(k, tier)


## Fix where it's at: a worn part back to full at its tier (junk patched up, still junk), a
## lost part replaced with stock. 60% of a stock part's price (a junk one's, for junk) for the
## share that's worn.
static func fix_cost(robot: Dictionary, k: String) -> int:
	var pt: Dictionary = Robot.ensure_parts(robot)[k]
	if float(pt["hp"]) <= 0.0:
		return int(JUNK_PRICES[k]) if Robot.original_tier(robot, k) == "Junk" else int(PART_PRICE[k])
	var tier := String(pt["tier"])
	var mx := float(Robot.TIER_HP.get(tier, 100))
	var base := float(JUNK_PRICES[k]) if tier == "Junk" else float(PART_PRICE[k])
	return int(ceilf(base * 0.6 * (1.0 - float(pt["hp"]) / mx)))


## Fix to original: a lost part, or a junk spare bolted on in a game, back as what he had
## (a new part of that tier); anything else as fix_cost.
static func restore_cost(robot: Dictionary, k: String) -> int:
	var pt: Dictionary = Robot.ensure_parts(robot)[k]
	var orig := Robot.original_tier(robot, k)
	if float(pt["hp"]) <= 0.0 or (bool(pt.get("spare", false)) and orig != "Junk"):
		return tier_price(k, orig)
	return fix_cost(robot, k)


static func restore_all_cost(robot: Dictionary) -> int:
	var c := 0
	for k in Robot.PARTS:
		c += restore_cost(robot, k)
	return c


static func buy_fix(t: int, robot: Dictionary, k: String) -> bool:
	var c := fix_cost(robot, k)
	if c <= 0:
		return true
	if not spend(t, c):
		return false
	Robot.patch(robot, k)
	save()
	return true


static func buy_restore(t: int, robot: Dictionary, k: String) -> bool:
	var c := restore_cost(robot, k)
	if c <= 0:
		return true
	if not spend(t, c):
		return false
	var pt: Dictionary = Robot.ensure_parts(robot)[k]
	if float(pt["hp"]) <= 0.0 or bool(pt.get("spare", false)):
		Robot.restore(robot, k)
	else:
		Robot.patch(robot, k)
	save()
	return true


static func fix_all_cost(robot: Dictionary) -> int:
	var c := 0
	for k in Robot.PARTS:
		c += fix_cost(robot, k)
	return c


static func repair_all_cost(robot: Dictionary) -> int:
	var c := 0
	for k in Robot.PARTS:
		c += repair_cost(robot, k)
	return c


## Junk spares are priced by part (JUNK_PRICES).
const JUNK_PRICE := 25        # the cheapest junk spare (an arm); the rest are priced by part
## A junk spare costs about a tenth of a new Stock part of the same kind.
const JUNK_PRICES := {"head": 20, "core": 25, "larm": 12, "rarm": 12, "lleg": 15, "rleg": 15}


static func junk_price(k: String) -> int:
	return int(JUNK_PRICES.get(k, JUNK_PRICE))


## A junk spare costs $25: with less in the purse there is none (unless `emergency`, when the
## side could not otherwise field a robot there). A simulated copy (t < 0) always gets one.
static func buy_junk(t: int, robot: Dictionary, k: String, emergency := false) -> bool:
	if t >= 0:
		if money(t) >= junk_price(k):
			add_money(t, -junk_price(k))
		elif not emergency:
			return false
		save()
	Robot.bolt_on_junk(robot, k)
	return true


## Buy a new Stock part (or a repair) if the purse allows. true if done.
static func buy_repair(t: int, robot: Dictionary, k: String) -> bool:
	var c := fix_cost(robot, k)
	if c <= 0:
		return true
	if not spend(t, c):
		return false
	Robot.repair(robot, k)
	save()
	return true


## The final whistle: pay each side for the result and what it did. Returns the two pay slips.
## Pay between games: whatever the damage costs to put right (every lost or worn part back to
## new), plus a share of the $2,000 budget for the result - 20% for a win, 15% a tie, 10% a loss -
## to spend on upgrades or new robots. So winning buys you a 20% better team for next week.
## Earned in the game: about $3,000 for an average win and $1,000 for an average loss (measured
## over 40 games), more for a big day. Repairs, upgrades and new robots come out of it.
const RESULT_PAY := {"win": 1300, "tie": 700, "loss": 0}
const EARN := [["td", "Touchdowns", 250], ["big", "Big plays (20+ yds)", 100], ["sacks", "Sacks", 100],
	["takeaways", "Takeaways", 200], ["hits", "Big hits (parts knocked off)", 50], ["first_downs", "First downs", 25]]


static func _earned(g: Game, t: int) -> Dictionary:
	var hits := 0
	for br in g.broken:
		if int(br["team"]) != t:
			hits += 1
	return {"td": int(g.stats[t]["td"]), "big": int(g.stats[t]["explosive"]), "sacks": int(g.stats[1 - t]["sacks"]),
		"takeaways": int(g.stats[1 - t]["turnovers"]), "hits": hits, "first_downs": int(g.stats[t]["first_downs"])}


static func damage_bill(t: int) -> int:
	var c := 0
	var tm := team(t)
	for s in tm["starters"]:
		c += fix_all_cost(tm["starters"][s])
	for r in tm["bench"]:
		c += fix_all_cost(r)
	return c


## Called at kickoff, so the pay covers only the damage done in this game.
static func note_kickoff() -> void:
	ensure()
	auto_lineups()
	data["bill_before"] = [damage_bill(0), damage_bill(1)]
	save()


## What side `t` is paid for game `g`: the result and what they did, as [label, $] lines.
## The same table for every club, in your games and the others.
static func pay_lines(g: Game, t: int) -> Array:
	var w := g.winner()
	var lines: Array = []
	var res := "tie" if w < 0 else ("win" if w == t else "loss")
	if int(RESULT_PAY[res]) > 0:
		lines.append([{"win": "Win", "tie": "Tie", "loss": "Loss"}[res], int(RESULT_PAY[res])])
	var got := _earned(g, t)
	for e in EARN:
		var n := int(got[e[0]])
		if n > 0:
			lines.append(["%s x%d" % [e[1], n], n * int(e[2])])
	return lines


## Pay as it happens (a setting): after each play, whatever a club has earned since the last
## look - a touchdown, a takeaway, a big play, a sack, a big hit, a first down - goes in its purse
## at once. Returns [[what, amount], ...] earned by club t just now. The final whistle then pays
## only the result and anything not paid yet.
static func pay_live(g: Game, t: int) -> Array:
	if exhibition():
		return []
	var paid: Array = g.get_meta("live_counts", [{}, {}])
	var got := _earned(g, t)
	var out: Array = []
	for e in EARN:
		var n := int(got[e[0]]) - int((paid[t] as Dictionary).get(e[0], 0))
		if n > 0:
			out.append([String(e[1]).get_slice(" (", 0).trim_suffix("s") if n == 1 else String(e[1]).get_slice(" (", 0), n * int(e[2])])
			add_money(t, n * int(e[2]))
		paid[t][e[0]] = int(got[e[0]])
	var sums: Array = g.get_meta("live_paid", [0, 0])
	for x in out:
		sums[t] = int(sums[t]) + int(x[1])
	g.set_meta("live_counts", paid)
	g.set_meta("live_paid", sums)
	return out


static func pay_game(g: Game) -> Array:
	var slips: Array = []
	var live: Array = g.get_meta("live_paid", [0, 0])
	for t in 2:
		var lines := pay_lines(g, t)
		var total := 0
		for ln in lines:
			total += int(ln[1])
		add_money(t, total - int(live[t]))      # what was paid during the game is already in
		slips.append({"lines": lines, "total": total, "name": String(team(t)["name"]), "purse": money(t)})
	save()
	slips[1]["news"] = club_ready(1)     # the rival repairs, then spends with Best buy
	slips[1]["purse"] = money(1)
	return slips


## A rival club gets ready for its next game: repairs all its damage, then spends what it has
## (above a $400 reserve for repairs) with Best buy, as you could.
static func club_ready(t: int) -> Array:
	var news := coach_repairs(t)
	var spent := club_spend(t)
	if spent > 0:
		news.append("%s spends $%d on upgrades (Best buy); purse now $%d." % [team(t)["name"], spent, money(t)])
	return news


## A rival club's Best buy with its own purse (above $400). Returns what it cost.
static func club_spend(t: int) -> int:
	var budget := maxi(money(t) - 400, 0)
	if budget <= 0:
		return 0
	var spent := _spend(team(t)["starters"], special(t), "win", budget, _opp_of(t))
	add_money(t, -spent)
	return spent


## The rival coach puts all his damage right before he shops.
static func coach_repairs(t: int) -> Array:
	var tm := team(t)
	var n := 0
	for r in (tm["starters"].values() + tm["bench"]):
		for k in Robot.PARTS:
			# what he had if he can afford it, else patched where it's at
			if restore_cost(r, k) > 0 and money(t) - restore_cost(r, k) >= 400 and buy_restore(t, r, k):
				n += 1
			elif fix_cost(r, k) > 0 and buy_fix(t, r, k):
				n += 1
	return ["%s repairs %d parts." % [tm["name"], n]] if n > 0 else []


## ---- the robot market ---------------------------------------------------------------------------
## Three robots for sale each week (new ones after every game). Bought, they join your bench.
static func _new_id() -> String:
	data["next_id"] = int(data.get("next_id", 1000)) + 1
	return "m%d" % int(data["next_id"])


static func robot_price(r: Dictionary) -> int:
	var parts := 0
	for k in Robot.PARTS:
		var tier := String(r["parts"][k]["tier"])
		parts += int(PART_PRICE[k] * {"Junk": 0.2, "Stock": 1.0, "Mk II": 1.6, "Mk III": 2.4, "Prototype": 3.5}.get(tier, 1.0))
	return int(roundf((Robot.overall(r) * 6 + parts * 0.5) / 10.0)) * 10


static func market() -> Array:
	ensure()
	if not data.has("market") or (data["market"] as Array).is_empty():
		restock()
	return data["market"]


static func restock() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var groups := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K", "P"]
	groups.shuffle()
	var out: Array = []
	for g in groups.slice(0, 3):
		var slot: String = (Play.GROUP_SLOTS.get(g, [g]) as Array)[0]
		var r := Robot.make(rng, slot, rng.randi_range(1, 99), _new_id(), true)
		r["slot"] = ""
		r["group"] = g
		r["price"] = robot_price(r)
		out.append(r)
	data["market"] = out
	save()


static func buy_robot(t: int, id: String) -> bool:
	for r in market():
		if String(r["id"]) == id:
			if not spend(t, int(r["price"])):
				return false
			market().erase(r)
			r.erase("price")
			if String(r["group"]) in ["K", "P"]:
				r["slot"] = String(r["group"])
				special(t)[String(r["group"])] = r     # a new kicker or punter takes the job
			else:
				team(t)["bench"].append(r)
			save()
			return true
	return false




## Which career team a robot is on (-1 if none: a simulated copy).
static func team_of(robot: Dictionary) -> int:
	if not loaded:
		return -1
	for t in 2:
		var tm: Dictionary = team(t)
		for s in tm["starters"]:
			if is_same(tm["starters"][s], robot):
				return t
		for b in tm["bench"]:
			if is_same(b, robot):
				return t
		for s in tm.get("special", {}):
			if is_same(tm["special"][s], robot):
				return t
	return -1



## ---- the shop: better parts and armour, any time --------------------------------------------------

const TIER_PRICE := {"Mk II": 2.5, "Mk III": 5.0, "Prototype": 10.0}


static func next_tier(robot: Dictionary, k: String) -> String:
	var cur := String(Robot.ensure_parts(robot)[k]["tier"])
	var i := Robot.TIERS.find(cur)
	if Robot.part_lost(robot, k) or i < 0 or i >= Robot.TIERS.size() - 1:
		return ""
	return Robot.TIERS[i + 1]     # one step at a time: junk -> stock -> Mk II -> Mk III -> Prototype


## Upgrade credit: money that comes with a new team and buys upgrades only.
static func credit(t: int) -> int:
	ensure()
	if not data.has("credit"):
		data["credit"] = [0, 0]
	return int(data["credit"][t])


## What can be spent on an upgrade right now: credit plus purse.
static func upgrade_funds(t: int) -> int:
	return credit(t) + money(t)


## The coach spends for you: all your credit, and if `purse` the purse above a $400 reserve.
## Returns what he bought, as lines.
## What the coach can be told to spend on. Each names the robots and the parts that carry what
## those robots do (legs for speed and routes, arms for hands and throwing, core for strength).
const FOCUS := {
	"": {"label": "Efficient (most OVR per $)", "slots": [], "parts": []},
	"win": {"label": "Best buy (beat this opponent)", "slots": [], "parts": []},
	"off": {"label": "Offense", "slots": [], "parts": []},
	"def": {"label": "Defense", "slots": [], "parts": []},
	"run": {"label": "Run game", "slots": [], "parts": []},
	"pass": {"label": "Passing", "slots": [], "parts": []},
	"rund": {"label": "Run defense", "slots": [], "parts": []},
	"passd": {"label": "Pass defense", "slots": [], "parts": []},
	"qb": {"label": "Quarterback", "slots": ["QB"], "parts": ["rarm", "larm", "head", "core", "lleg", "rleg"]},
	"wr": {"label": "Receivers", "slots": ["WR1", "WR2", "WR3", "TE"], "parts": ["lleg", "rleg", "larm", "rarm", "head"]},
	"rb": {"label": "Running back", "slots": ["RB"], "parts": ["lleg", "rleg", "core", "larm", "rarm", "head"]},
	"ol": {"label": "O-line", "slots": ["LT", "LG", "C", "RG", "RT"], "parts": ["core", "larm", "rarm", "lleg", "rleg"]},
	"dl": {"label": "Pass rush", "slots": ["DE1", "DT1", "DT2", "DE2"], "parts": ["core", "lleg", "rleg", "larm", "rarm"]},
	"lb": {"label": "Linebackers", "slots": ["OLB1", "MLB", "OLB2"], "parts": ["lleg", "rleg", "core", "larm", "rarm", "head"]},
	"db": {"label": "Secondary (CB, S)", "slots": ["CB1", "CB2", "FS", "SS"], "parts": ["lleg", "rleg", "larm", "rarm", "head"]},
	"st": {"label": "Kicker and punter", "slots": ["K", "P"], "parts": ["lleg", "rleg", "larm", "rarm"]},
}


## Spend `budget` on one group: round after round, the cheapest next tier among its robots'
## parts, so the whole group gets better together, up to Prototype. Returns what it cost.
static func focus_upgrades(t: int, focus: String, budget: int) -> int:
	return _focus_on(team(t)["starters"], special(t), focus, budget)


static func _focus_on(starters: Dictionary, specials: Dictionary, focus: String, budget: int) -> int:
	var f: Dictionary = FOCUS[focus]
	var robots: Array = []
	for s in f["slots"]:
		var r: Dictionary = starters.get(s, {})
		if r.is_empty():
			r = specials.get(s, {})
		if not r.is_empty():
			robots.append(r)
	var left := budget
	for guard in 200:
		# the weakest part first; among equals, the part that matters most (listed first)
		var best := {}
		var best_k := ""
		var best_p := 0
		var best_score := 1 << 30
		for r in robots:
			for i in (f["parts"] as Array).size():
				var k: String = f["parts"][i]
				var nt := next_tier(r, k)
				if nt == "":
					continue
				var pr := upgrade_price(k, nt)
				var score := Robot.TIERS.find(nt) * 100 + i
				if pr <= left and score < best_score:
					best_score = score
					best_p = pr
					best = r
					best_k = k
		if best.is_empty():
			break
		var tier := next_tier(best, best_k)
		Robot.ensure_parts(best)[best_k] = {"tier": tier, "hp": Robot.TIER_HP[tier]}
		left -= best_p
	return budget - left


## What the coach WOULD buy with coach_spend(t, purse, reserve, focus, seed), worked out on
## copies so nothing changes: {budget, cost, rows: [{slot, name, before, after, cost, parts}]},
## one row per robot he would upgrade (parts: ["left leg Stock -> Mk II", ...]).
static func coach_plan(t: int, purse: bool, reserve := 400, focus := "", seed := 1) -> Dictionary:
	var budget := credit(t) + (maxi(money(t) - reserve, 0) if purse else 0)
	var out := {"budget": budget, "cost": 0, "rows": []}
	if budget <= 0:
		return out
	var real: Dictionary = (team(t)["starters"] as Dictionary).duplicate()
	var sp: Dictionary = special(t)
	var copy := {"starters": (team(t)["starters"] as Dictionary).duplicate(true)}
	var sp_copy := sp.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	out["cost"] = _spend(copy["starters"], sp_copy, focus, budget, _opp_of(t))
	for s in real:
		_plan_row(out["rows"], s, real[s], copy["starters"][s])
	for s in sp:
		_plan_row(out["rows"], s, sp[s], sp_copy[s])
	return out




## His overall, unrounded (so a small gain still shows).
static func _ovr_f(r: Dictionary) -> float:
	var ks := Robot.keys(r)
	var g := String(r.get("group", ""))
	var s := 0.0
	for k in ks:
		s += Robot.eff(r, k) - Robot.mean_for(g, k) + Robot.BASE
	# what junk and missing parts take off, as the shown overall counts it
	return s / maxf(ks.size(), 1) + Robot.effective_overall(r) - float(Robot.overall(r))


## "Efficient buy": the most team overall per dollar. Again and again it takes the step - one
## part, up one or more tiers - that adds the most to the starters' average overall (the team
## OVR the tables show) per dollar, until nothing affordable is left. Looking more than one tier
## ahead keeps it from passing up a part whose first step is dear but whose next ones pay.
## Kicker and punter are left alone: they do not count in the team OVR. Fits the parts;
## returns what it cost.
## How much a point of each position's overall is worth in winning games, per robot: a best
## guess (football sense, loosely checked with tests/win_weight_study.gd). "Best buy" spends by
## these.
const WIN_WEIGHT := {"QB": 2.0, "LB": 1.2, "RB": 1.1, "WR": 1.0, "DL": 1.0, "CB": 1.0, "OL": 0.9, "S": 0.8, "TE": 0.7}


## The weighted buys: which positions count, and how much. A position left out is not bought for.
static var BUY_WEIGHTS := {
	"win": WIN_WEIGHT,
	"off": {"QB": 2.0, "RB": 1.1, "WR": 1.0, "TE": 0.7, "OL": 0.9},
	"def": {"DL": 1.0, "LB": 1.2, "CB": 1.0, "S": 0.8},
	# the run game: the back and the men blocking for him (a QB's legs on keepers, a little)
	"run": {"RB": 1.6, "OL": 1.2, "TE": 0.9, "WR": 0.3, "QB": 0.3},
	# passing: the thrower, his targets and his protection
	"pass": {"QB": 2.0, "WR": 1.2, "TE": 0.8, "OL": 0.9, "RB": 0.3},
	# stopping the run: the front that takes on blockers and the men who fill behind it
	"rund": {"DL": 1.4, "LB": 1.3, "S": 0.6, "CB": 0.3},
	# stopping the pass: the cover men and the pass rush
	"passd": {"CB": 1.4, "S": 1.1, "DL": 1.0, "LB": 0.6},
}


## Win weights against a particular opponent: WIN_WEIGHT (to the 1.5, so the positions that
## win games stand out more), scaled by how far each position's unit trails the unit it lines
## up against (behind by 5 counts double; ahead by 3, about half).
static func _win_weights(me: Dictionary, opp: Dictionary) -> Dictionary:
	var U := Analysis.UNITS
	var u := func(tm: Dictionary, k: String) -> float: return Analysis.unit(tm, U[k])
	var gap := {
		"OL": u.call(opp, "D-line") - u.call(me, "O-line"),
		"DL": u.call(opp, "O-line") - u.call(me, "D-line"),
		"WR": u.call(opp, "secondary") - u.call(me, "receivers"),
		"TE": u.call(opp, "secondary") - u.call(me, "receivers"),
		"CB": u.call(opp, "receivers") - u.call(me, "secondary"),
		"S": u.call(opp, "receivers") - u.call(me, "secondary"),
		"RB": (u.call(opp, "linebackers") + u.call(opp, "D-line")) * 0.5 - u.call(me, "running back"),
		"LB": (u.call(opp, "running back") + u.call(opp, "O-line")) * 0.5 - u.call(me, "linebackers"),
		"QB": u.call(opp, "secondary") - u.call(me, "QB"),
	}
	var w := {}
	for g in WIN_WEIGHT:
		w[g] = pow(float(WIN_WEIGHT[g]), 1.5) * clampf(1.0 + 0.2 * float(gap.get(g, 0.0)), 0.25, 3.0)
	return w


## This week's opponent for club t (the other side of the current game), or {} outside a season.
static func _opp_of(t: int) -> Dictionary:
	if not loaded or t > 1:
		return {}
	return team(1 - t)


## Spend for a coach's plan: "" the efficient buy, "win" the best buy, else one group.
static func _spend(starters: Dictionary, specials: Dictionary, focus: String, budget: int, opp: Dictionary = {}) -> int:
	if focus == "":
		return value_upgrades(starters, specials, budget)
	if focus == "win" and not opp.is_empty():
		return value_upgrades(starters, specials, budget, WIN_WEIGHT, opp)
	if BUY_WEIGHTS.has(focus):
		return value_upgrades(starters, specials, budget, BUY_WEIGHTS[focus])
	return _focus_on(starters, specials, focus, budget)


## "Best buy" is the same search with each robot's gain weighted by WIN_WEIGHT.
static func value_upgrades(starters: Dictionary, specials: Dictionary, budget: int, weights: Dictionary = {}, opp: Dictionary = {}) -> int:
	var robots: Array = []
	for s in starters:
		if not (starters[s] as Dictionary).is_empty():
			robots.append(starters[s])
	var left := budget
	for guard in 300:
		# the best buy looks at this week's opponent: a unit losing its matchup counts for more,
		# one already winning it for less (worked out again after every part, as gaps close)
		if not opp.is_empty():
			weights = _win_weights({"starters": starters}, opp)
		var best := {}
		var best_k := ""
		var best_tier := ""
		var best_p := 0
		var best_r := 0.0
		for r in robots:
			var parts := Robot.ensure_parts(r)
			var before := _ovr_f(r)
			var w := float(weights.get(String(r.get("group", "")), 0.0)) if not weights.is_empty() else 1.0
			if w <= 0.0:
				continue
			for k in Robot.PARTS:
				var keep: Dictionary = parts[k]
				var cost := 0
				for step in 4:
					var nt := next_tier(r, k)
					if nt == "":
						break
					cost += upgrade_price(k, nt)
					if cost > left:
						break
					parts[k] = {"tier": nt, "hp": Robot.TIER_HP[nt]}
					var ratio := (_ovr_f(r) - before) * w / float(cost)
					if ratio > best_r:
						best_r = ratio
						best = r
						best_k = k
						best_tier = nt
						best_p = cost
				parts[k] = keep
		if best.is_empty():
			break
		Robot.ensure_parts(best)[best_k] = {"tier": best_tier, "hp": Robot.TIER_HP[best_tier]}
		left -= best_p
	return budget - left


static func _plan_row(rows: Array, slot: String, was: Dictionary, now: Dictionary) -> void:
	var parts: Array = []
	var cost := 0
	for k in Robot.PARTS:
		var a := String(Robot.ensure_parts(was)[k]["tier"])
		var b := String(Robot.ensure_parts(now)[k]["tier"])
		if a == b:
			continue
		parts.append("%s %s -> %s" % [String(Robot.PART_LABEL[k]).to_lower(), a, b])
		var probe := {"parts": {k: {"tier": a, "hp": 1}}}
		for guard in 5:
			var nt := next_tier(probe, k)
			if nt == "" or Robot.TIERS.find(nt) > Robot.TIERS.find(b):
				break
			cost += upgrade_price(k, nt)
			probe["parts"][k]["tier"] = nt
	if parts.is_empty():
		return
	var gains: Array = []
	for rk in Robot.keys(was):
		var d := int(roundf(Robot.eff(now, rk) - Robot.eff(was, rk)))
		if d != 0:
			gains.append("%s %+d" % [String(Robot.LABEL.get(rk, rk)).to_lower(), d])
	rows.append({"slot": slot, "name": String(was.get("name", slot)), "before": Robot.overall_if(was, "now"),
		"after": Robot.overall_if(now, "now"), "cost": cost, "parts": parts, "gains": gains})


static func coach_spend(t: int, purse: bool, reserve := 400, focus := "", seed := 0) -> Array:
	var news: Array = []
	var budget := credit(t) + (maxi(money(t) - reserve, 0) if purse else 0)
	if budget <= 0:
		return news
	var before := {}
	var st: Dictionary = (team(t)["starters"] as Dictionary).duplicate()
	for s in special(t):
		st[s] = special(t)[s]
	for s in st:
		for k in Robot.PARTS:
			before[s + k] = String(Robot.ensure_parts(st[s])[k]["tier"])
	var rng: RandomNumberGenerator = null
	if seed != 0:
		rng = RandomNumberGenerator.new()
		rng.seed = seed            # the same draw coach_plan showed
	var spent := _spend(team(t)["starters"], special(t), focus, budget, _opp_of(t))
	var from_credit := mini(credit(t), spent)
	data["credit"][t] = credit(t) - from_credit
	add_money(t, -(spent - from_credit))
	# credit too small to buy any upgrade is no use as credit: it goes in the purse
	if credit(t) < 300:
		add_money(t, credit(t))
		data["credit"][t] = 0
	news.push_front("spent $%d; purse now $%d" % [spent, money(t)])
	for s in st:
		for k in Robot.PARTS:
			var now := String(st[s]["parts"][k]["tier"])
			if now != before[s + k]:
				news.append("%s %s: %s %s" % [s, st[s]["name"], now, String(Robot.PART_LABEL[k]).to_lower()])
	save()
	return news


static func upgrade_price(k: String, tier: String) -> int:
	return int(roundf(float(PART_PRICE[k]) * float(TIER_PRICE.get(tier, 1.0)) / 10.0) * 10.0)


## Buy the next tier for a part (a fresh one, full condition). true if done.
static func buy_upgrade(t: int, robot: Dictionary, k: String) -> bool:
	var tier := next_tier(robot, k)
	if tier == "":
		return false
	var price := upgrade_price(k, tier)
	if credit(t) + money(t) < price:
		return false
	var from_credit := mini(credit(t), price)
	data["credit"][t] = credit(t) - from_credit
	if price - from_credit > 0 and not spend(t, price - from_credit):
		data["credit"][t] = credit(t) + from_credit
		return false
	Robot.ensure_parts(robot)[k] = {"tier": tier, "hp": Robot.TIER_HP[tier]}
	save()
	return true


## Armour plating: +5 toughness. Dearer the tougher he already is.
static func armor_price(robot: Dictionary) -> int:
	return int(100 + maxf(Robot.rating(robot, "toughness") - 50.0, 0.0) * 6.0)


static func buy_armor(t: int, robot: Dictionary) -> bool:
	if Robot.rating(robot, "toughness") >= 99.0 or not spend(t, armor_price(robot)):
		return false
	robot["armor"] = int(robot.get("armor", 0)) + 1
	Robot.reset_ratings(robot)
	save()
	return true


## The rival's owner spends after a game: upgrades for his weakest starters, keeping a reserve.
## ---- every team starts with $2,000 of upgrades ------------------------------------------------------

const STARTER_BUDGET := 2000
## Where a coach puts upgrade money first: the parts that carry each position's key ratings.
const UPGRADE_SPOTS := [["QB", "rarm"], ["QB", "larm"], ["QB", "head"], ["RB", "lleg"], ["RB", "rleg"],
	["WR1", "lleg"], ["WR1", "rleg"], ["WR2", "lleg"], ["WR2", "rleg"], ["LT", "core"], ["RT", "core"],
	["DE1", "core"], ["DE2", "core"], ["MLB", "core"], ["CB1", "lleg"], ["CB1", "rleg"], ["FS", "head"]]


## Fit Mk II parts worth up to $2,000 to a new team's key starters (no money changes hands: it
## comes with the team). A different spread each draft.
static func starter_upgrades(tm: Dictionary, rng: RandomNumberGenerator = null) -> int:
	var spent := upgrades_with(tm, STARTER_BUDGET, rng)
	tm["leftover"] = STARTER_BUDGET - spent      # what $2,000 couldn't buy goes in the purse
	return spent


## A coach's shopping with `budget`: key starters' parts first (the quarterback's arms leading),
## then any starter's arms and legs. Fits the parts; returns what it cost.
static func upgrades_with(tm: Dictionary, budget: int, rng: RandomNumberGenerator = null) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var spots: Array = UPGRADE_SPOTS.duplicate()
	# shuffle, but keep the quarterback's arms near the front
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	spots.sort_custom(func(a, b): return int(a[0] == "QB" and a[1].ends_with("arm")) > int(b[0] == "QB" and b[1].ends_with("arm")))
	var left := budget
	for sp in spots:
		var r: Dictionary = tm["starters"].get(sp[0], {})
		if r.is_empty():
			continue
		var k: String = sp[1]
		var nt := next_tier(r, k)
		if nt == "":
			continue
		var price := upgrade_price(k, nt)
		if price > left:
			continue
		Robot.ensure_parts(r)[k] = {"tier": nt, "hp": Robot.TIER_HP[nt]}
		left -= price
	# whatever is left goes on any starter's arms or legs that it still covers
	var slots: Array = (Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS).duplicate()
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	for s2 in slots:
		for k2 in ["larm", "rarm", "lleg", "rleg"]:
			var r2: Dictionary = tm["starters"][s2]
			var nt2 := next_tier(r2, k2)
			if nt2 == "" or Robot.TIERS.find(nt2) > 2 or upgrade_price(k2, nt2) > left:
				continue
			Robot.ensure_parts(r2)[k2] = {"tier": nt2, "hp": Robot.TIER_HP[nt2]}
			left -= upgrade_price(k2, nt2)
	return budget - left



## ---- exhibition and season -----------------------------------------------------------------------
## Two ways to play. EXHIBITION: a one-off game; both sides are drafted fresh with a single $2,000
## budget to spend before kickoff (you spend yours or let the coach; the rival's coach spends his);
## nothing carries over and nobody is paid. SEASON: your team, its money and its damage carry
## from game to game through a schedule against three rival clubs (each twice, six weeks); a win
## pays more than a loss; the other games are played too; the best record is champion.

const RIVAL_NAMES := ["Iron Hogs", "Chrome Chargers", "Sprocket City Sparks", "Voltage Vikings",
	"Rust Belt Rollers", "Neon Ninjas", "Gearbox Grizzlies", "Turbo Titans", "Static Stingers"]
const WEEKS := 6
## Four clubs (0 is you), each meets each twice.
const SCHEDULE := [[[0, 1], [2, 3]], [[0, 2], [1, 3]], [[0, 3], [1, 2]], [[1, 0], [3, 2]], [[2, 0], [3, 1]], [[3, 0], [2, 1]]]
const EXHIBITION_BUDGET := 2000


static func exhibition() -> bool:
	return String(data.get("mode", "season")) == "exhibition" and data.has("exhibition")


## The sim lab: your own lab team ($2,000 to fit it out) against ten drafted opponents; games are
## only simulated, on copies of the robots - nothing breaks, nobody is paid, the season is untouched.
static func sim_mode() -> bool:
	return String(data.get("mode", "season")) == "sim" and data.has("sim")


static func mode() -> String:
	ensure()
	if exhibition():
		return "exhibition"
	if sim_mode():
		return "sim"
	return "season"


## "Season · week 3 of 6" / "Exhibition · no pay" / "Sim lab"
static func mode_badge() -> String:
	match mode():
		"exhibition":
			return "Exhibition · no pay"
		"sim":
			return "Sim lab"
	return "Season · " + week_label().to_lower()


static func set_mode(m: String) -> void:
	ensure()
	data["mode"] = m
	if m == "exhibition" and not data.has("exhibition"):
		new_exhibition()
	if m == "sim" and not data.has("sim"):
		new_sim_lab()
	save()


const SIM_OPPONENTS := 10


static func new_sim_lab() -> void:
	data["sim"] = {"team": new_team(0, -1, false), "money": EXHIBITION_BUDGET, "opps": [], "idx": 0}
	data["sim"]["team"]["name"] = "Lab Rats"
	new_sim_opponents()


## Ten opponents, each drafted with $2,000 of upgrades fitted and its own coach.
static func new_sim_opponents() -> void:
	var opps: Array = []
	var names := RIVAL_NAMES.duplicate()
	names.shuffle()
	for i in SIM_OPPONENTS:
		var tm := new_team(1)
		tm["name"] = String(names[i % names.size()]) + ("" if i < names.size() else " II")
		tm["coach"] = _random_coach()
		tm["defense"] = _random_defense()
		opps.append(tm)
	data["sim"]["opps"] = opps
	data["sim"]["idx"] = 0
	save()


static func sim_opponents() -> Array:
	return data["sim"]["opps"] if sim_mode() else []


static func set_sim_opponent(i: int) -> void:
	data["sim"]["idx"] = i


## Fresh teams for a one-off game, $2,000 each; the rival's coach spends his at once.
static func new_exhibition() -> void:
	data["exhibition"] = {"teams": [new_team(0, -1, false), new_team(1, -1, false)], "money": [EXHIBITION_BUDGET, EXHIBITION_BUDGET]}
	data["exhibition"]["teams"][1]["name"] = RIVAL_NAMES[randi() % RIVAL_NAMES.size()]
	data["exhibition"]["teams"][1]["coach"] = _random_coach()
	data["exhibition"]["teams"][1]["defense"] = _random_defense()
	var was := String(data.get("mode", "season"))
	data["mode"] = "exhibition"
	coach_spend(1, true, 0, "win")
	data["mode"] = was
	save()


## A random defensive scheme for a rival.
static func _random_defense() -> String:
	var names := Library.names("defense")
	return names[randi() % names.size()] if not names.is_empty() else ""


## Every rival without a defensive scheme gets one (old saves, and new teams).
static func _give_defenses() -> void:
	var sides: Array = []
	if data.has("teams"):
		sides.append(data["teams"][1])
	for c in data.get("season", {}).get("clubs", []):
		sides.append(c)
	for c in data.get("sim", {}).get("opps", []):
		sides.append(c)
	var ex: Dictionary = data.get("exhibition", {})
	if ex.has("teams"):
		sides.append(ex["teams"][1])
	for tm in sides:
		if tm is Dictionary and String(tm.get("defense", "")) == "":
			tm["defense"] = _random_defense()


## Your own schemes, kept with the career: [offense coach, defensive scheme].
static func my_schemes() -> Array:
	return [String(data.get("coach0", "Balanced")), String(data.get("defense0", ""))]


static func set_my_schemes(coach_name: String, defense_name: String) -> void:
	data["coach0"] = coach_name
	data["defense0"] = defense_name
	save()


static func _random_coach() -> String:
	var names := Library.names("coach")
	return names[randi() % names.size()] if not names.is_empty() else "Balanced"


static func _new_club(name: String, fit := true) -> Dictionary:
	var tm := new_team(1, -1, fit)
	tm["name"] = name
	tm["coach"] = _random_coach()
	tm["defense"] = _random_defense()
	tm["money"] = START_MONEY + int(tm.get("leftover", 0))
	tm["rec"] = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}
	return tm


## A season with your current team (and purse) against the current rival and two new clubs.
static func _season_around_current() -> void:
	var names := RIVAL_NAMES.duplicate()
	names.shuffle()
	var first: Dictionary = data["teams"][1]
	first["name"] = names[0]
	first["coach"] = _random_coach()
	first["defense"] = _random_defense()
	first["money"] = int(data.get("money", [START_MONEY, START_MONEY])[1])
	first["rec"] = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}
	var fresh := bool(data.get("_fresh", false))
	data["season"] = {"week": 1, "clubs": [first, _new_club(names[1], not fresh), _new_club(names[2], not fresh)],
		"you": {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}, "results": [], "champion": ""}
	_set_opponent()


## A new season: you are drafted fresh with $2,000 to spend; three new rival clubs.
static func new_season() -> void:
	ensure()
	if season_over():
		data["last_champion"] = String(season().get("champion", ""))
	data["teams"][0] = new_team(0, -1, false)
	data["teams"][1] = new_team(1, -1, false)
	data["bill_before"] = [0, 0]
	_fresh_season()
	data["mode"] = "season"
	save()


## A career starts level: four new teams drafted the same way (no upgrades fitted), evened out
## with parts so each has the same average starter rating, and $5,000 apiece to spend. Later
## seasons keep every club as it is - its robots, parts, damage and purse - and add $5,000.
const SEASON_MONEY := 5000


## The next season: the same four clubs with the same robots (unless traded or scrapped), records
## cleared, $5,000 more each; the rivals spend theirs before week 1. No levelling.
static func next_season() -> void:
	ensure()
	var sn := season()
	if sn.is_empty():
		new_season()
		return
	data["last_champion"] = String(sn.get("champion", ""))
	var clubs: Array = sn["clubs"]
	data["mode"] = "season"
	add_money(0, SEASON_MONEY)
	for c in clubs:
		c["rec"] = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}
		c["money"] = int(c.get("money", 0)) + SEASON_MONEY
	data["season"] = {"week": 1, "clubs": clubs, "you": {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}, "results": [], "champion": ""}
	data["mode"] = "season"
	for ci in clubs.size():
		data["season"]["opp"] = ci
		club_ready(1)
	_set_opponent()
	restock()
	save()


static func _fresh_season() -> void:
	data["money"] = [SEASON_MONEY, SEASON_MONEY]
	data["_fresh"] = true
	_season_around_current()
	data.erase("_fresh")
	var clubs: Array = data["season"]["clubs"]
	for c in clubs:
		c["money"] = SEASON_MONEY
	var all: Array = [data["teams"][0]] + clubs
	equalize_teams(all)
	# every rival spends its season money before week 1, as you can
	var keep := int(data["season"].get("opp", 0))
	for ci in clubs.size():
		data["season"]["opp"] = ci
		club_spend(1)
	data["season"]["opp"] = keep


## A side's average starter rating, unrounded.
static func _team_avg(tm: Dictionary) -> float:
	var s := 0.0
	var n := 0
	for sl in tm["starters"]:
		var r: Dictionary = tm["starters"][sl]
		if not r.is_empty():
			s += float(Robot.overall_if(r, "now"))    # the rating the tables show
			n += 1
	return s / maxf(n, 1)


## Even out the teams: robots are the sum of their parts, so the weaker sides are given parts
## (free, the best value first) until every side's average starter rating is within half a
## point of the best one's.
static func equalize_teams(teams: Array) -> void:
	if teams.is_empty():
		return
	for tm in teams:
		best_lineup(tm)           # who starts first: then the starters are what gets evened out
	var target := 0.0
	for tm in teams:
		target = maxf(target, _team_avg(tm))
	for tm in teams:
		for guard in 200:
			if _team_avg(tm) >= target - 0.25:
				break
			if value_upgrades(tm["starters"], {}, 400) == 0:
				break


static func season() -> Dictionary:
	ensure()
	return data.get("season", {})


static func season_over() -> bool:
	return int(season().get("week", 1)) > WEEKS + 1


## After the six weeks the top two in the table meet in the championship game.
static func is_final() -> bool:
	return int(season().get("week", 1)) == WEEKS + 1


## "Week 3 of 6" / "Championship game" / "Season over"
static func week_label() -> String:
	if season_over():
		return "Season over"
	if is_final():
		return "Championship game"
	return "Week %d of %d" % [int(season().get("week", 1)), WEEKS]


## Who you play this week: points team(1) at that club.
static func _set_opponent() -> void:
	var sn := season()
	if is_final() and sn.has("final"):
		sn["opp"] = int(sn["final"]["opp"])
		return
	var wk := clampi(int(sn.get("week", 1)), 1, WEEKS)
	for pair in SCHEDULE[wk - 1]:
		if 0 in pair:
			sn["opp"] = int(pair[0] if pair[1] == 0 else pair[1]) - 1
			return


static func opponent_name() -> String:
	return String(team(1).get("name", "Rival"))


static func opponent_coach() -> String:
	return String(team(1).get("coach", "Balanced"))


static func opponent_defense() -> String:
	return String(team(1).get("defense", ""))


## "Balanced / Blitz Happy": a side's offense and defense schemes.
static func schemes_text(tm: Dictionary) -> String:
	var dn := String(tm.get("defense", ""))
	return String(tm.get("coach", "?")) + (" / " + dn if dn != "" else "")


static func _record(rec: Dictionary, us: int, them: int) -> void:
	rec["pf"] = int(rec["pf"]) + us
	rec["pa"] = int(rec["pa"]) + them
	var k := "w" if us > them else ("l" if us < them else "t")
	rec[k] = int(rec[k]) + 1


## After your game: record it, play the week's other game, pay the other clubs, let them shop,
## and move on a week. Returns lines for the final box score.
static func finish_week(g: Game) -> Array:
	var sn := season()
	if sn.is_empty() or season_over():
		return []
	var lines: Array = []
	var opp: Dictionary = team(1)
	var wk := int(sn["week"])
	var games: Array = [[g, data["teams"][0], opp]]
	if wk > WEEKS:
		# the championship game: no draws - a tie goes to overtime
		var mine: int = g.score[0]
		var theirs: int = g.score[1]
		var ot := ""
		if mine == theirs:
			var w := _overtime(-1, int(sn["opp"]))
			ot = " (won in overtime)"
			mine += 1 if w == 0 else 0
			theirs += 1 if w == 1 else 0
		sn["champion"] = String(data["teams"][0]["name"]) if mine > theirs else String(opp["name"])
		sn["results"].append("Championship: %s %d - %d %s%s" % [data["teams"][0]["name"], g.score[0], g.score[1], opp["name"], ot])
		lines.append("CHAMPIONS: %s%s!" % [sn["champion"], ot])
		_awards(games, "Championship game")
		sn["week"] = wk + 1
		restock()
		save()
		return lines
	_record(sn["you"], g.score[0], g.score[1])
	_record(opp["rec"], g.score[1], g.score[0])
	sn["results"].append("Week %d: %s %d - %d %s" % [wk, data["teams"][0]["name"], g.score[0], g.score[1], opp["name"]])
	# the other game this week
	for pair in SCHEDULE[wk - 1]:
		if 0 in pair:
			continue
		var a: Dictionary = sn["clubs"][int(pair[0]) - 1]
		var b: Dictionary = sn["clubs"][int(pair[1]) - 1]
		best_lineup(a)
		best_lineup(b)
		var ta := Team.build(0, String(a["coach"]), {}, "coach", String(a.get("defense", "")))
		ta["roster"] = a["starters"]
		ta["bench"] = a["bench"]
		var tb := Team.build(1, String(b["coach"]), {}, "coach", String(b.get("defense", "")))
		tb["roster"] = b["starters"]
		tb["bench"] = b["bench"]
		var og := Batch.play_game(ta, tb, g.qlen, randi())
		games.append([og, a, b])
		_record(a["rec"], og.score[0], og.score[1])
		_record(b["rec"], og.score[1], og.score[0])
		for side in 2:
			var club: Dictionary = [a, b][side]
			for ln in pay_lines(og, side):
				club["money"] = int(club.get("money", 0)) + int(ln[1])
		var keep := int(sn["opp"])
		for ci in [int(pair[0]) - 1, int(pair[1]) - 1]:
			sn["opp"] = ci
			var club2: Dictionary = team(1)
			for slot in club2["starters"]:
				coach_fix(club2["starters"], club2["bench"], slot)
			club_ready(1)
		sn["opp"] = keep
		var line := "Week %d: %s %d - %d %s" % [wk, a["name"], og.score[0], og.score[1], b["name"]]
		sn["results"].append(line)
		lines.append("Elsewhere: %s %d - %d %s" % [a["name"], og.score[0], og.score[1], b["name"]])
	_awards(games, "Week %d" % wk)
	sn["week"] = wk + 1
	restock()
	if wk == WEEKS:
		# the regular season is done: the top two play for the championship
		var table := standings()
		var a: Dictionary = table[0]
		var b: Dictionary = table[1]
		if a["you"] or b["you"]:
			var other: Dictionary = b if a["you"] else a
			for ci in sn["clubs"].size():
				if String(sn["clubs"][ci]["name"]) == String(other["name"]):
					sn["final"] = {"opp": ci}
			_set_opponent()
			lines.append("YOU'RE IN THE CHAMPIONSHIP GAME: %s vs %s" % [data["teams"][0]["name"], opponent_name()])
		else:
			# you missed out: the two clubs play it out
			var ia := _club_index(String(a["name"]))
			var ib := _club_index(String(b["name"]))
			var ca: Dictionary = sn["clubs"][ia]
			var cb: Dictionary = sn["clubs"][ib]
			var og := Batch.play_game(_club_side(0, ca), _club_side(1, cb), g.qlen, randi())
			var sa: int = og.score[0]
			var sb: int = og.score[1]
			var ot := ""
			if sa == sb:
				ot = " (overtime)"
				if _overtime(ia, ib) == 0:
					sa += 1
				else:
					sb += 1
			sn["champion"] = String(ca["name"]) if sa > sb else String(cb["name"])
			sn["results"].append("Championship: %s %d - %d %s%s" % [ca["name"], og.score[0], og.score[1], cb["name"], ot])
			lines.append("You missed the championship game. %s %d - %d %s%s: CHAMPIONS %s" % [ca["name"], og.score[0], og.score[1], cb["name"], ot, sn["champion"]])
			_awards([[og, ca, cb]], "Championship game")
			sn["week"] = WEEKS + 2
	else:
		_set_opponent()
		lines.append("Next week: %s (%s)" % [opponent_name(), _rec_text(team(1)["rec"])])
	save()
	return lines


## ---- players of the week and of the season -------------------------------------------------------
## Points for a player's game: yards, touchdowns and takeaways, less what he gave away.
static func _off_pts(d: Dictionary) -> float:
	# a passer's yards and touchdowns count a little less than the catcher's, but he has all of them
	return float(d["pyd"]) * 0.05 + float(d["ptd"]) * 5.0 - float(d["int"]) * 2.5 - float(d["sk"]) * 0.5 \
		+ float(d["ryd"]) * 0.1 + float(d["rtd"]) * 6.0 + float(d["rec"]) * 0.3 + float(d["recyd"]) * 0.07 \
		+ float(d["rectd"]) * 5.0 - float(d["fum"]) * 2.0


static func _def_pts(d: Dictionary) -> float:
	return float(d["tkl"]) + float(d["sack"]) * 4.0 + float(d["dint"]) * 5.0 + float(d["pbu"]) * 1.5 \
		+ float(d["ff"]) * 3.0 + float(d["fr"]) * 2.0 + float(d["dtd"]) * 6.0 - float(d["mt"]) * 0.5


## "21/30, 280 pass yds, 3 TD" - the numbers that earned it.
static func stat_line(d: Dictionary, side: String) -> String:
	var bits: Array = []
	if side == "off":
		if float(d["att"]) > 0:
			bits.append("%d/%d, %d pass yds" % [int(d["cmp"]), int(d["att"]), int(d["pyd"])])
			if int(d["ptd"]) > 0: bits.append("%d TD pass%s" % [int(d["ptd"]), "" if int(d["ptd"]) == 1 else "es"])
			if int(d["int"]) > 0: bits.append("%d INT" % int(d["int"]))
		if float(d["car"]) > 0:
			bits.append("%d run%s, %d yds" % [int(d["car"]), "" if int(d["car"]) == 1 else "s", int(d["ryd"])])
			if int(d["rtd"]) > 0: bits.append("%d rushing TD" % int(d["rtd"]))
		if float(d["rec"]) > 0:
			bits.append("%d catch%s, %d yds" % [int(d["rec"]), "" if int(d["rec"]) == 1 else "es", int(d["recyd"])])
			if int(d["rectd"]) > 0: bits.append("%d TD catch%s" % [int(d["rectd"]), "" if int(d["rectd"]) == 1 else "es"])
	else:
		for kv in [["tkl", "tackle"], ["sack", "sack"], ["dint", "interception"], ["pbu", "pass broken up"], ["ff", "forced fumble"], ["fr", "fumble recovery"], ["dtd", "TD"]]:
			var n := int(d[kv[0]])
			if n > 0:
				bits.append("%d %s%s" % [n, kv[1], "" if n == 1 or kv[0] == "pbu" else "s"])
	return ", ".join(bits)


## The week's best on offense and on defense across every game played, added to the season
## tally. Returns the lines to show.
static func _awards(games: Array, label: String) -> Array:
	var sn := season()
	var tally: Dictionary = sn.get("tally", {})
	var best := _best_in(games, tally)
	sn["tally"] = tally
	var out: Array = []
	var potw := {}
	for side in ["off", "def"]:
		var b: Dictionary = best[side]
		if b.is_empty():
			continue
		potw[side] = b
		out.append("%s %s player of the week: %s %s (%s) - %s" % [label, "offensive" if side == "off" else "defensive", b["slot"], b["name"], b["team"], stat_line(b["stats"], side)])
	sn["potw"] = potw
	sn["potw_label"] = label
	return out


## The best on offense and on defense in these games ([Game, side 0 team, side 1 team] each);
## with a tally, every player's numbers are added to it too.
static func _best_in(games: Array, tally = null) -> Dictionary:
	var best := {"off": {}, "def": {}}
	for gm in games:
		var gg: Game = gm[0]
		for t in 2:
			var tm: Dictionary = gm[1 + t]
			for slot in gg.pstats[t]:
				var r: Dictionary = (tm["starters"] as Dictionary).get(slot, {})
				if r.is_empty():
					continue
				var d: Dictionary = gg.pstats[t][slot]
				var side := "off" if slot in Play.OFFENSE_SLOTS else "def"
				var pts := _off_pts(d) if side == "off" else _def_pts(d)
				var who := {"id": String(r.get("id", "")), "name": String(r["name"]), "slot": String(slot), "team": String(tm["name"]), "side": side, "pts": pts, "stats": d.duplicate()}
				if (best[side] as Dictionary).is_empty() or pts > float(best[side]["pts"]):
					best[side] = who
				if tally == null:
					continue
				# the season tally: points and stats added up, per robot
				var key := String(r.get("id", r["name"]))
				var tl: Dictionary = tally.get(key, {"name": who["name"], "slot": who["slot"], "team": who["team"], "side": side, "pts": 0.0, "games": 0, "stats": {}})
				tl["pts"] = float(tl["pts"]) + pts
				tl["games"] = int(tl["games"]) + 1
				tl["team"] = who["team"]
				for k in d:
					tl["stats"][k] = float(tl["stats"].get(k, 0.0)) + float(d[k])
				tally[key] = tl
	return best


## Players of the game: the best on each side in one of your games (both teams).
static func game_stars(g: Game) -> Dictionary:
	return _best_in([[g, team(0), team(1)]])


## The season's awards by kind: [title, row, what it counts], from the season tally.
const AWARD_KINDS := [
	["Best offensive player", "off", ""], ["Best defensive player", "def", ""],
	["Best passer", "off", "pass"], ["Best runner", "off", "run"], ["Best receiver", "off", "catch"],
	["Top tackler", "def", "tkl"], ["Sack leader", "def", "sack"], ["Ball hawk", "def", "hawk"]]
static func _kind_pts(st: Dictionary, kind: String) -> float:
	match kind:
		"pass": return float(st.get("pyd", 0)) * 0.05 + float(st.get("ptd", 0)) * 5.0 - float(st.get("int", 0)) * 2.5
		"run": return float(st.get("ryd", 0)) * 0.1 + float(st.get("rtd", 0)) * 6.0 - float(st.get("fum", 0)) * 2.0
		"catch": return float(st.get("recyd", 0)) * 0.1 + float(st.get("rectd", 0)) * 6.0 + float(st.get("rec", 0)) * 0.5
		"tkl": return float(st.get("tkl", 0)) - float(st.get("mt", 0)) * 0.3
		"sack": return float(st.get("sack", 0)) + float(st.get("ff", 0)) * 0.3
		"hawk": return float(st.get("dint", 0)) * 2.0 + float(st.get("pbu", 0)) + float(st.get("fr", 0))
	return 0.0


## [title, row] for each award; row = {name, slot, team, side, pts, stats}.
static func season_awards() -> Array:
	var out: Array = []
	var tally: Dictionary = season().get("tally", {})
	for aw in AWARD_KINDS:
		var best := {}
		var bp := 0.0
		for k in tally:
			var row: Dictionary = tally[k]
			if String(row["side"]) != String(aw[1]):
				continue
			var p := float(row["pts"]) if String(aw[2]) == "" else _kind_pts(row["stats"], String(aw[2]))
			if p > bp:
				bp = p
				best = row
		if not best.is_empty():
			out.append([aw[0], best])
	return out


## The season's best: top three on offense and on defense by points over the season.
static func season_leaders(side: String, n := 3) -> Array:
	var rows: Array = []
	var tally: Dictionary = season().get("tally", {})
	for k in tally:
		if String(tally[k]["side"]) == side:
			rows.append(tally[k])
	rows.sort_custom(func(a, b): return float(a["pts"]) > float(b["pts"]))
	return rows.slice(0, n)


static func season_award_lines() -> Array:
	var out: Array = ["SEASON AWARDS"]
	for aw in season_awards():
		var row: Dictionary = aw[1]
		out.append("%s: %s %s (%s) - %s" % [aw[0], row["slot"], row["name"], row["team"], stat_line(row["stats"], String(row["side"]))])
	return out


static func _club_index(name: String) -> int:
	var sn := season()
	for ci in sn["clubs"].size():
		if String(sn["clubs"][ci]["name"]) == name:
			return ci
	return 0


static func _club_side(side: int, club: Dictionary) -> Dictionary:
	var tm := Team.build(side, String(club["coach"]), {}, "coach", String(club.get("defense", "")))
	tm["roster"] = club["starters"]
	tm["bench"] = club["bench"]
	tm["club"] = String(club["name"])
	return tm


## A tied championship game goes to overtime: short periods until someone is ahead (a coin toss
## after three). `a` / `b` are club indices, -1 for your team. Returns 0 if `a` wins, 1 if `b`.
static func _overtime(a: int, b: int) -> int:
	var sn := season()
	for i in 3:
		var ta: Dictionary = Team.build(0, String(data.get("coach0", "Balanced")), {}, "coach", String(data.get("defense0", ""))) if a < 0 else _club_side(0, sn["clubs"][a])
		var tb: Dictionary = _club_side(1, sn["clubs"][b])
		var og := Batch.play_game(ta, tb, 120.0, randi())
		if og.score[0] != og.score[1]:
			return 0 if og.score[0] > og.score[1] else 1
	return randi() % 2


static func _rec_text(r: Dictionary) -> String:
	return "%d-%d%s" % [int(r["w"]), int(r["l"]), ("-%d" % int(r["t"])) if int(r["t"]) > 0 else ""]


## The table, best first: [{name, rec, text, you}]
## A side's ratings: the average overall of its starters (as they are now, damage and all),
## all of them, the offence and the defence. {ovr, off, def}
static func team_ratings(tm: Dictionary) -> Dictionary:
	var sums := {"ovr": 0.0, "off": 0.0, "def": 0.0}
	var ns := {"ovr": 0, "off": 0, "def": 0}
	for s in tm.get("starters", {}):
		var r: Dictionary = tm["starters"][s]
		if r.is_empty():
			continue
		var o := float(Robot.overall_if(r, "now"))
		var side := "off" if s in Play.OFFENSE_SLOTS else "def"
		sums["ovr"] += o
		sums[side] += o
		ns["ovr"] += 1
		ns[side] += 1
	var out := {}
	for k in sums:
		out[k] = int(roundf(sums[k] / maxf(ns[k], 1)))
	return out


## "OVR 61 (off 63, def 59)"
static func ratings_text(tm: Dictionary) -> String:
	var rt := team_ratings(tm)
	return "OVR %d (off %d, def %d)" % [rt["ovr"], rt["off"], rt["def"]]


## The clubs other than yours and this week's opponent, to look at (season: the other clubs;
## sim lab: the ten opponents).
static func other_clubs() -> Array:
	if sim_mode():
		return sim_opponents()
	if exhibition() or not data.has("season"):
		return []
	var out: Array = []
	for c in data["season"]["clubs"]:
		if not is_same(c, team(1)):
			out.append(c)
	return out


static func standings() -> Array:
	var sn := season()
	if sn.is_empty():
		return []
	var rows: Array = [{"name": String(data["teams"][0]["name"]), "rec": sn["you"], "you": true, "rt": ratings_text(data["teams"][0])}]
	for c in sn["clubs"]:
		rows.append({"name": String(c["name"]), "rec": c["rec"], "you": false, "rt": ratings_text(c)})
	rows.sort_custom(func(a, b):
		var pa := int(a["rec"]["w"]) * 2 + int(a["rec"]["t"])
		var pb := int(b["rec"]["w"]) * 2 + int(b["rec"]["t"])
		if pa != pb:
			return pa > pb
		return int(a["rec"]["pf"]) - int(a["rec"]["pa"]) > int(b["rec"]["pf"]) - int(b["rec"]["pa"]))
	for r in rows:
		r["text"] = "%s  %s  (%d-%d)  ·  %s" % [r["name"], _rec_text(r["rec"]), int(r["rec"]["pf"]), int(r["rec"]["pa"]), r["rt"]]
	return rows
