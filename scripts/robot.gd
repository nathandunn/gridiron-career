class_name Robot
extends RefCounted
## A robot player: a name, a number, a position and ratings from 1 to 100. A rating of 60 plays
## exactly like the equal bodies of Gridiron Bots; every 10 points either way moves the engine
## numbers that rating stands for (see RATING_HELP and apply()).
##
## Stored as a plain Dictionary so a roster saves straight to JSON:
##   {id, name, number, slot, group, ratings: {speed, strength, toughness, iq, <skills>}}

const BASE := 60.0
const CORE := ["speed", "strength", "toughness", "iq"]
## The skills that matter for each position group.
const SKILLS := {
	"QB": ["arm", "accuracy"], "RB": ["hands", "elusiveness"], "WR": ["hands", "routes"],
	"TE": ["hands", "blocking"], "OL": ["blocking"], "DL": ["rush", "tackling"],
	"LB": ["tackling", "coverage"], "CB": ["coverage", "ball_skills"], "S": ["coverage", "tackling"],
}
const LABEL := {"speed": "Speed", "strength": "Strength", "toughness": "Toughness", "iq": "IQ",
	"arm": "Arm", "accuracy": "Accuracy", "hands": "Hands", "elusiveness": "Elusiveness", "routes": "Routes",
	"blocking": "Blocking", "rush": "Pass rush", "tackling": "Tackling", "coverage": "Coverage",
	"ball_skills": "Ball skills"}
## What each rating does in the engine, for the details screen.
const RATING_HELP := {
	"speed": "Top speed and acceleration",
	"strength": "Blocking and shedding, making and breaking tackles, the pile",
	"toughness": "Gets up faster after a knock-down; holds on to the ball",
	"iq": "Caps the brain's vision, patience and discipline; quicker reactions",
	"arm": "How hard and far he throws",
	"accuracy": "How close the ball lands to where he aimed",
	"hands": "Catching, and holding on when hit",
	"elusiveness": "Jukes, cuts and making tacklers miss",
	"routes": "Sharp cuts and getting open",
	"blocking": "Winning blocks and holding them",
	"rush": "Beating blocks to get to the passer",
	"tackling": "Wrapping up and bringing him down",
	"coverage": "Staying with receivers and breaking on the ball",
	"ball_skills": "Interceptions and getting a hand on it",
}

const FIRST := ["Rivet", "Torque", "Sprocket", "Gizmo", "Piston", "Bolt", "Widget", "Ratchet", "Cog",
	"Servo", "Diode", "Flux", "Gasket", "Axle", "Chrome", "Turbo", "Volt", "Clank", "Socket", "Drive",
	"Cam", "Crank", "Spark", "Ohm", "Pixel", "Byte", "Rotor", "Tesla", "Ampere", "Hex"]
const LAST := ["McGrease", "Steelhead", "Ironside", "Boltman", "Wrenchley", "O'Rust", "Copperfield",
	"Gearhart", "Sparkplug", "Von Chassis", "Tinbottom", "Ampsworth", "Cranky", "Nutsby", "Oilcan",
	"Framewell", "Weldmore", "Hydro", "Magnetti", "Circuitson"]


static func make(rng: RandomNumberGenerator, slot: String, number: int, id: String, mixed_parts := false) -> Dictionary:
	var g: String = Play.SLOT_GROUP.get(slot, slot)
	var r := {}
	for k in CORE + (SKILLS[g] as Array):
		# most robots are about average; a few stand out either way
		r[k] = int(clampf(roundf(rng.randfn(BASE, 12.0)), 25.0, 97.0))
	# toughness varies the most: some robots are tanks, some are glass
	r["toughness"] = int(clampf(roundf(rng.randfn(BASE, 18.0)), 20.0, 99.0))
	var robot := {"id": id, "name": "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]],
		"number": number, "slot": slot, "group": g, "ratings": r}
	ensure_parts(robot)
	if mixed_parts:
		# a drafted robot comes as he is: mostly Stock, some Junk, now and then something better
		for k in PARTS:
			var roll := rng.randf()
			var tier := "Junk" if roll < 0.15 else ("Stock" if roll < 0.85 else ("Mk II" if roll < 0.97 else "Mk III"))
			robot["parts"][k] = {"tier": tier, "hp": TIER_HP[tier]}
	return robot


static func keys(robot: Dictionary) -> Array:
	return CORE + (SKILLS[String(robot["group"])] as Array)


static func rating(robot: Dictionary, k: String) -> float:
	return float((robot["ratings"] as Dictionary).get(k, BASE))


## One number for the robot: the mean of his ratings.
static func overall(robot: Dictionary) -> int:
	var ks := keys(robot)
	var s := 0.0
	for k in ks:
		s += eff(robot, k)
	return int(roundf(s / ks.size()))


static func _f(robot: Dictionary, k: String) -> float:
	return (eff(robot, k) - BASE) / 40.0      # -0.9 at 25, 0 at 60, +0.9 at 96


## ---- upgraded parts add to the ratings they carry ------------------------------------------------
const TIERS := ["Junk", "Stock", "Mk II", "Mk III", "Prototype"]
const TIER_BONUS := {"Junk": 0, "Stock": 0, "Mk II": 6, "Mk III": 12, "Prototype": 20}
## Which ratings each part carries. An arm or a leg gives half its bonus (he has two).
const PART_RATINGS := {
	"head": ["iq"], "core": ["strength", "toughness"],
	"larm": ["hands", "tackling", "arm", "accuracy", "ball_skills", "blocking"],
	"rarm": ["hands", "tackling", "arm", "accuracy", "ball_skills", "blocking"],
	"lleg": ["speed", "elusiveness", "routes", "coverage", "rush"],
	"rleg": ["speed", "elusiveness", "routes", "coverage", "rush"],
}


## How much his parts add to a rating.
static func bonus(robot: Dictionary, k: String) -> float:
	if not robot.has("parts"):
		return 0.0
	var b := 0.0
	for pk in PART_RATINGS:
		if k in PART_RATINGS[pk] and not part_lost(robot, pk):
			var tb := float(TIER_BONUS.get(String(robot["parts"][pk]["tier"]), 0))
			b += tb * (0.5 if pk.ends_with("arm") or pk.ends_with("leg") else 1.0)
	return b


## The rating he plays at: his own, plus what his parts add.
static func eff(robot: Dictionary, k: String) -> float:
	return minf(rating(robot, k) + bonus(robot, k), 120.0)


## Turn the ratings into the engine's body numbers (a copy of the position's body) and the
## IQ factor that scales the brain's thinking dials.
static func apply(robot: Dictionary, body: Dictionary) -> Dictionary:
	var b := body.duplicate()
	var sp := _f(robot, "speed")
	b["speed"] = float(b["speed"]) * (1.0 + 0.10 * sp)
	b["accel"] = float(b["accel"]) * (1.0 + 0.12 * sp)
	b["power"] = clampf(float(b["power"]) + 0.15 * _f(robot, "strength"), 0.05, 1.3)
	b["tough"] = _f(robot, "toughness")
	b["iq"] = clampf(1.0 + 0.35 * _f(robot, "iq"), 0.4, 1.35)
	var sk: Array = SKILLS[String(robot["group"])]
	if "hands" in sk:
		b["hands"] = clampf(float(b["hands"]) + 0.12 * _f(robot, "hands"), 0.05, 0.99)
	if "ball_skills" in sk:
		b["hands"] = clampf(float(b["hands"]) + 0.12 * _f(robot, "ball_skills"), 0.05, 0.99)
	if "elusiveness" in sk:
		b["agility"] = clampf(float(b["agility"]) + 0.12 * _f(robot, "elusiveness"), 0.05, 1.1)
	if "routes" in sk:
		b["agility"] = clampf(float(b["agility"]) + 0.10 * _f(robot, "routes"), 0.05, 1.1)
	if "coverage" in sk:
		b["agility"] = clampf(float(b["agility"]) + 0.10 * _f(robot, "coverage"), 0.05, 1.1)
	if "blocking" in sk:
		b["power"] = clampf(float(b["power"]) + 0.10 * _f(robot, "blocking"), 0.05, 1.3)
	if "rush" in sk:
		b["power"] = clampf(float(b["power"]) + 0.07 * _f(robot, "rush"), 0.05, 1.3)
		b["agility"] = clampf(float(b["agility"]) + 0.07 * _f(robot, "rush"), 0.05, 1.1)
	if "tackling" in sk:
		b["tackle"] = clampf(float(b["tackle"]) + 0.12 * _f(robot, "tackling"), 0.05, 1.1)
	if "arm" in sk:
		b["arm"] = clampf(PlaySim.QB_ARM + 0.15 * _f(robot, "arm"), 0.4, 1.2)
	if "accuracy" in sk:
		b["acc"] = clampf(PlaySim.QB_ACC + 0.12 * _f(robot, "accuracy"), 0.3, 1.1)
	return apply_parts(robot, b)


## ---- parts ------------------------------------------------------------------------------------
## Six parts, each with a tier and a condition (hp). A part at 0 hp is gone: it came off on the
## field. A Junk part is a cheap spare bolted on in its place - it works, badly, and breaks sooner.

const PARTS := ["head", "core", "larm", "rarm", "lleg", "rleg"]
const PART_LABEL := {"head": "Head", "core": "Core", "larm": "Left arm", "rarm": "Right arm", "lleg": "Left leg", "rleg": "Right leg"}
const TIER_HP := {"Junk": 50, "Stock": 100, "Mk II": 140, "Mk III": 180, "Prototype": 240}
const PART_HELP := {
	"head": "Sensors and CPU. Without it: IQ near zero - he only follows his assignment.",
	"core": "The power plant. Without it he shuts down and can't play.",
	"larm": "Catching, tackling, stiff arms, throwing. Lose one: about half as good. Lose both: hopeless.",
	"rarm": "Catching, tackling, stiff arms, throwing. Lose one: about half as good. Lose both: hopeless.",
	"lleg": "Speed and cuts. Lose one: he hops, at under half speed.",
	"rleg": "Speed and cuts. Lose one: he hops, at under half speed.",
}


static func ensure_parts(robot: Dictionary) -> Dictionary:
	if not robot.has("parts"):
		var p := {}
		for k in PARTS:
			p[k] = {"tier": "Stock", "hp": 100}
		robot["parts"] = p
	return robot["parts"]


static func part_lost(robot: Dictionary, k: String) -> bool:
	return float(ensure_parts(robot)[k]["hp"]) <= 0.0


static func part_junk(robot: Dictionary, k: String) -> bool:
	return String(ensure_parts(robot)[k]["tier"]) == "Junk" and not part_lost(robot, k)


static func lost_parts(robot: Dictionary) -> Array:
	var out: Array = []
	for k in PARTS:
		if part_lost(robot, k):
			out.append(k)
	return out


## Can he take the field at all? (no core, or no legs, and he can't)
static func can_play(robot: Dictionary) -> bool:
	return not part_lost(robot, "core") and not (part_lost(robot, "lleg") and part_lost(robot, "rleg"))


static func bolt_on_junk(robot: Dictionary, k: String) -> void:
	ensure_parts(robot)[k] = {"tier": "Junk", "hp": TIER_HP["Junk"]}


static func repair(robot: Dictionary, k: String) -> void:
	var p: Dictionary = ensure_parts(robot)[k]
	if float(p["hp"]) <= 0.0 or String(p["tier"]) == "Junk":
		p["tier"] = "Stock"           # a lost or junk part is replaced with a proper one
	p["hp"] = TIER_HP.get(String(p["tier"]), 100)


## Overall, less what missing and junk parts cost him - what a coach looks at when choosing a sub.
static func effective_overall(robot: Dictionary) -> float:
	var o := float(overall(robot))
	var cost := {"head": 30.0, "core": 60.0, "larm": 14.0, "rarm": 14.0, "lleg": 25.0, "rleg": 25.0}
	for k in PARTS:
		if part_lost(robot, k):
			o -= float(cost[k])
		elif part_junk(robot, k):
			o -= 4.0
	return o


## What missing and junk parts do to his body (after his ratings are applied).
static func apply_parts(robot: Dictionary, b: Dictionary) -> Dictionary:
	if not robot.has("parts"):
		return b
	var legs_lost := int(part_lost(robot, "lleg")) + int(part_lost(robot, "rleg"))
	var legs_junk := int(part_junk(robot, "lleg")) + int(part_junk(robot, "rleg"))
	var arms_lost := int(part_lost(robot, "larm")) + int(part_lost(robot, "rarm"))
	var arms_junk := int(part_junk(robot, "larm")) + int(part_junk(robot, "rarm"))
	var leg_f: float = [1.0, 0.45, 0.2][legs_lost] * pow(0.94, legs_junk)
	b["speed"] = float(b["speed"]) * leg_f
	b["accel"] = float(b["accel"]) * leg_f
	b["agility"] = maxf(float(b["agility"]) - 0.25 * legs_lost - 0.05 * legs_junk, 0.05)
	b["hands"] = clampf(float(b["hands"]) * float([1.0, 0.55, 0.05][arms_lost]) - 0.05 * arms_junk, 0.02, 0.99)
	b["tackle"] = clampf(float(b["tackle"]) * float([1.0, 0.6, 0.1][arms_lost]) - 0.04 * arms_junk, 0.02, 1.1)
	b["arm"] = float(b.get("arm", PlaySim.QB_ARM)) * float([1.0, 0.65, 0.1][arms_lost])
	b["acc"] = float(b.get("acc", PlaySim.QB_ACC)) * float([1.0, 0.6, 0.1][arms_lost])
	b["one_arm"] = arms_lost > 0
	if part_lost(robot, "head"):
		b["iq"] = 0.25
	elif part_junk(robot, "head"):
		b["iq"] = float(b.get("iq", 1.0)) * 0.8
	if part_lost(robot, "core"):
		b["power"] = float(b["power"]) * 0.3
		b["speed"] = float(b["speed"]) * 0.5
	elif part_junk(robot, "core"):
		b["power"] = maxf(float(b["power"]) - 0.08, 0.05)
		b["tough"] = float(b.get("tough", 0.0)) - 0.3
	return b



## His armour: how well he stands up to hits - his toughness, with what his core adds.
static func armour(robot: Dictionary) -> int:
	return int(roundf(eff(robot, "toughness")))


## Condition of all his parts together: [now, most].
static func condition(robot: Dictionary) -> Array:
	var now := 0.0
	var most := 0.0
	for k in PARTS:
		var pt: Dictionary = ensure_parts(robot)[k]
		now += maxf(float(pt["hp"]), 0.0)
		most += float(TIER_HP.get(String(pt["tier"]), 100))
	return [int(now), int(most)]


## His parts by tier, short: "1 Junk, 4 Stock, 1 Mk II".
static func tiers_text(robot: Dictionary, short := false) -> String:
	var counts := {}
	for k in PARTS:
		var tier := "lost" if part_lost(robot, k) else String(ensure_parts(robot)[k]["tier"])
		counts[tier] = int(counts.get(tier, 0)) + 1
	var out: Array = []
	for tier in ["lost"] + TIERS:
		if counts.has(tier):
			var nm: String = {"lost": "GONE", "Junk": "J", "Stock": "S", "Mk II": "M2", "Mk III": "M3", "Prototype": "P"}[tier] if short else tier
			out.append(("%s%d" % [nm, counts[tier]]) if short else ("%d %s" % [counts[tier], nm]))
	return (" " if short else ", ").join(out)
