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
			if not data.has("season"):
				_season_around_current()      # saves from before seasons: this becomes week 1 of one
				data["money"][0] = maxi(int(data["money"][0]), STARTER_BUDGET)   # and a season starts with $2,000
				save()
			return
	data = {"version": 1, "fair": false, "teams": [new_team(0, -1, false), new_team(1)], "starter_upgrades": true, "mode": "season"}
	data["money"] = [STARTER_BUDGET, START_MONEY + int(data["teams"][1].get("leftover", 0))]   # you start with $2,000 to spend
	_season_around_current()
	save()


static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


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
	if fit:
		starter_upgrades(tm, rng)
	return tm


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
	elif t == 1 and data.has("season"):
		var club := team(1)
		for k in ["starters", "bench"]:
			club[k] = nt[k]
	else:
		data["teams"][t] = nt
	add_money(t, int(nt.get("leftover", 0)))
	save()


## Find a robot by id on either team: {team, robot, where ("starter"/"bench"), slot}.
static func find(id: String) -> Dictionary:
	ensure()
	for t in 2:
		var tm: Dictionary = team(t)
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
	var bought: Array = []
	for k in lost:
		var t := team_of(r)
		if t >= 0 and money(t) >= repair_cost(r, k) * 3 and buy_repair(t, r, k):
			bought.append(k)
		else:
			buy_junk(t, r, k)
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
	if t == 1 and data.has("season"):
		return int(team(1).get("money", 0))
	if not data.has("money"):
		data["money"] = [START_MONEY, START_MONEY]
	return int(data["money"][t])


static func add_money(t: int, amount: int) -> void:
	money(t)
	if exhibition():
		data["exhibition"]["money"][t] = int(data["exhibition"]["money"][t]) + amount
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
static func repair_cost(robot: Dictionary, k: String) -> int:
	var pt: Dictionary = Robot.ensure_parts(robot)[k]
	var price := int(PART_PRICE[k])
	if float(pt["hp"]) <= 0.0 or String(pt["tier"]) == "Junk":
		return price
	var mx := float(Robot.TIER_HP.get(String(pt["tier"]), 100))
	return int(ceilf(price * 0.6 * (1.0 - float(pt["hp"]) / mx)))


## What putting right the damage costs (a lost part, a junk spare bolted on in a game, a worn
## part); junk he started with is not damage - replace it on his page if you like.
static func fix_cost(robot: Dictionary, k: String) -> int:
	var pt: Dictionary = Robot.ensure_parts(robot)[k]
	if String(pt["tier"]) == "Junk" and float(pt["hp"]) > 0.0 and not bool(pt.get("spare", false)):
		return 0
	return repair_cost(robot, k)


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


## A junk spare costs $25 - or whatever is left in the purse, so a side can always field a robot.
const JUNK_PRICE := 25


static func buy_junk(t: int, robot: Dictionary, k: String) -> void:
	if t >= 0:
		add_money(t, -mini(JUNK_PRICE, maxi(money(t), 0)))
		save()
	Robot.bolt_on_junk(robot, k)


## Buy a new Stock part (or a repair) if the purse allows. true if done.
static func buy_repair(t: int, robot: Dictionary, k: String) -> bool:
	var c := repair_cost(robot, k)
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
const RESULT_SHARE := {"win": 0.20, "tie": 0.15, "loss": 0.10}


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
	data["bill_before"] = [damage_bill(0), damage_bill(1)]
	save()


static func pay_game(g: Game) -> Array:
	var slips: Array = []
	var w := g.winner()
	for t in 2:
		var lines: Array = []
		var res := "tie" if w < 0 else ("win" if w == t else "loss")
		var share := int(STARTER_BUDGET * float(RESULT_SHARE[res]))
		lines.append(["%s (%d%% of $%d)" % [{"win": "Win", "tie": "Tie", "loss": "Loss"}[res], int(RESULT_SHARE[res] * 100), STARTER_BUDGET], share])
		# only this game's damage: what was already broken before kickoff was yours to fix
		var bill := maxi(damage_bill(t) - int(data.get("bill_before", [0, 0])[t]), 0)
		if bill > 0:
			lines.append(["Damage covered", bill])
		var total := share + bill
		add_money(t, total)
		slips.append({"lines": lines, "total": total, "name": String(team(t)["name"]), "purse": money(t)})
	save()
	slips[1]["news"] = rival_shopping(1)     # the rival's owner goes shopping
	slips[1]["news"] = coach_repairs(1) + slips[1]["news"]
	slips[1]["purse"] = money(1)
	return slips


## The rival coach puts all his damage right before he shops.
static func coach_repairs(t: int) -> Array:
	var tm := team(t)
	var n := 0
	for r in (tm["starters"].values() + tm["bench"]):
		for k in Robot.PARTS:
			if fix_cost(r, k) > 0 and buy_repair(t, r, k):
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
	var groups := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S"]
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
	return -1



## ---- the shop: better parts and armour, any time --------------------------------------------------

const TIER_PRICE := {"Mk II": 2.5, "Mk III": 5.0, "Prototype": 10.0}


static func next_tier(robot: Dictionary, k: String) -> String:
	var cur := String(Robot.ensure_parts(robot)[k]["tier"])
	var i := Robot.TIERS.find(cur)
	if Robot.part_lost(robot, k) or i < 0 or i >= Robot.TIERS.size() - 1:
		return ""
	return Robot.TIERS[maxi(i + 1, 2)]   # junk or stock both go to Mk II


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
static func coach_spend(t: int, purse: bool, reserve := 400) -> Array:
	var news: Array = []
	var budget := credit(t) + (maxi(money(t) - reserve, 0) if purse else 0)
	if budget <= 0:
		return news
	var before := {}
	var st: Dictionary = team(t)["starters"]
	for s in st:
		for k in Robot.PARTS:
			before[s + k] = String(Robot.ensure_parts(st[s])[k]["tier"])
	var spent := upgrades_with(team(t), budget)
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
	robot["ratings"]["toughness"] = mini(int(Robot.rating(robot, "toughness")) + 5, 99)
	save()
	return true


## The rival's owner spends after a game: upgrades for his weakest starters, keeping a reserve.
static func rival_shopping(t: int) -> Array:
	var news: Array = []
	var starters: Dictionary = team(t)["starters"]
	for i in 4:
		var best := {}
		var best_k := ""
		var best_tier := 99
		for s in starters:
			var r: Dictionary = starters[s]
			for k in Robot.PARTS:
				var nt := next_tier(r, k)
				if nt == "":
					continue
				var ti := Robot.TIERS.find(String(r["parts"][k]["tier"]))
				if ti < best_tier or (ti == best_tier and randf() < 0.15):
					best_tier = ti
					best = r
					best_k = k
		if best.is_empty() or money(t) - upgrade_price(best_k, next_tier(best, best_k)) < 400:
			break
		var tier := next_tier(best, best_k)
		if buy_upgrade(t, best, best_k):
			news.append("%s buys %s a %s %s." % [team(t)["name"], best["name"], tier, String(Robot.PART_LABEL[best_k]).to_lower()])
	return news



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


static func set_mode(mode: String) -> void:
	ensure()
	data["mode"] = mode
	if mode == "exhibition" and not data.has("exhibition"):
		new_exhibition()
	save()


## Fresh teams for a one-off game, $2,000 each; the rival's coach spends his at once.
static func new_exhibition() -> void:
	data["exhibition"] = {"teams": [new_team(0, -1, false), new_team(1, -1, false)], "money": [EXHIBITION_BUDGET, EXHIBITION_BUDGET]}
	data["exhibition"]["teams"][1]["name"] = RIVAL_NAMES[randi() % RIVAL_NAMES.size()]
	data["exhibition"]["teams"][1]["coach"] = _random_coach()
	var was := String(data.get("mode", "season"))
	data["mode"] = "exhibition"
	coach_spend(1, true, 0)
	data["mode"] = was
	save()


static func _random_coach() -> String:
	var names := Library.names("coach")
	return names[randi() % names.size()] if not names.is_empty() else "Balanced"


static func _new_club(name: String) -> Dictionary:
	var tm := new_team(1)
	tm["name"] = name
	tm["coach"] = _random_coach()
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
	first["money"] = int(data.get("money", [START_MONEY, START_MONEY])[1])
	first["rec"] = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}
	data["season"] = {"week": 1, "clubs": [first, _new_club(names[1]), _new_club(names[2])],
		"you": {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0}, "results": [], "champion": ""}
	_set_opponent()


## A new season: you are drafted fresh with $2,000 to spend; three new rival clubs.
static func new_season() -> void:
	ensure()
	if season_over():
		data["last_champion"] = String(season().get("champion", ""))
	data["teams"][0] = new_team(0, -1, false)
	data["money"] = [STARTER_BUDGET, START_MONEY]
	data["teams"][1] = new_team(1)
	data["bill_before"] = [0, 0]
	_season_around_current()
	data["mode"] = "season"
	save()


static func season() -> Dictionary:
	ensure()
	return data.get("season", {})


static func season_over() -> bool:
	return int(season().get("week", 1)) > WEEKS


## Who you play this week: points team(1) at that club.
static func _set_opponent() -> void:
	var sn := season()
	var wk := clampi(int(sn.get("week", 1)), 1, WEEKS)
	for pair in SCHEDULE[wk - 1]:
		if 0 in pair:
			sn["opp"] = int(pair[0] if pair[1] == 0 else pair[1]) - 1
			return


static func opponent_name() -> String:
	return String(team(1).get("name", "Rival"))


static func opponent_coach() -> String:
	return String(team(1).get("coach", "Balanced"))


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
	_record(sn["you"], g.score[0], g.score[1])
	_record(opp["rec"], g.score[1], g.score[0])
	var wk := int(sn["week"])
	sn["results"].append("Week %d: %s %d - %d %s" % [wk, data["teams"][0]["name"], g.score[0], g.score[1], opp["name"]])
	# the other game this week
	for pair in SCHEDULE[wk - 1]:
		if 0 in pair:
			continue
		var a: Dictionary = sn["clubs"][int(pair[0]) - 1]
		var b: Dictionary = sn["clubs"][int(pair[1]) - 1]
		var ta := Team.build(0, String(a["coach"]))
		ta["roster"] = a["starters"]
		ta["bench"] = a["bench"]
		var tb := Team.build(1, String(b["coach"]))
		tb["roster"] = b["starters"]
		tb["bench"] = b["bench"]
		var og := Batch.play_game(ta, tb, g.qlen, randi())
		_record(a["rec"], og.score[0], og.score[1])
		_record(b["rec"], og.score[1], og.score[0])
		for pr in [[a, og.score[0], og.score[1]], [b, og.score[1], og.score[0]]]:
			var club: Dictionary = pr[0]
			var res := "win" if pr[1] > pr[2] else ("loss" if pr[1] < pr[2] else "tie")
			club["money"] = int(club.get("money", 0)) + int(PAY[res])
		var keep := int(sn["opp"])
		for ci in [int(pair[0]) - 1, int(pair[1]) - 1]:
			sn["opp"] = ci
			var club2: Dictionary = team(1)
			for slot in club2["starters"]:
				coach_fix(club2["starters"], club2["bench"], slot)
			rival_shopping(1)
		sn["opp"] = keep
		var line := "Week %d: %s %d - %d %s" % [wk, a["name"], og.score[0], og.score[1], b["name"]]
		sn["results"].append(line)
		lines.append("Elsewhere: %s %d - %d %s" % [a["name"], og.score[0], og.score[1], b["name"]])
	sn["week"] = wk + 1
	restock()
	if season_over():
		var table := standings()
		sn["champion"] = String(table[0]["name"])
		lines.append("SEASON OVER - champions: %s" % sn["champion"])
	else:
		_set_opponent()
		lines.append("Next week: %s (%s)" % [opponent_name(), _rec_text(team(1)["rec"])])
	save()
	return lines


static func _rec_text(r: Dictionary) -> String:
	return "%d-%d%s" % [int(r["w"]), int(r["l"]), ("-%d" % int(r["t"])) if int(r["t"]) > 0 else ""]


## The table, best first: [{name, rec, text, you}]
static func standings() -> Array:
	var sn := season()
	if sn.is_empty():
		return []
	var rows: Array = [{"name": String(data["teams"][0]["name"]), "rec": sn["you"], "you": true}]
	for c in sn["clubs"]:
		rows.append({"name": String(c["name"]), "rec": c["rec"], "you": false})
	rows.sort_custom(func(a, b):
		var pa := int(a["rec"]["w"]) * 2 + int(a["rec"]["t"])
		var pb := int(b["rec"]["w"]) * 2 + int(b["rec"]["t"])
		if pa != pb:
			return pa > pb
		return int(a["rec"]["pf"]) - int(a["rec"]["pa"]) > int(b["rec"]["pf"]) - int(b["rec"]["pa"]))
	for r in rows:
		r["text"] = "%s  %s  (%d-%d)" % [r["name"], _rec_text(r["rec"]), int(r["rec"]["pf"]), int(r["rec"]["pa"])]
	return rows
