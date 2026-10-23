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


static func make(rng: RandomNumberGenerator, slot: String, number: int, id: String) -> Dictionary:
	var g: String = Play.SLOT_GROUP.get(slot, slot)
	var r := {}
	for k in CORE + (SKILLS[g] as Array):
		# most robots are about average; a few stand out either way
		r[k] = int(clampf(roundf(rng.randfn(BASE, 12.0)), 25.0, 97.0))
	return {"id": id, "name": "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]],
		"number": number, "slot": slot, "group": g, "ratings": r}


static func keys(robot: Dictionary) -> Array:
	return CORE + (SKILLS[String(robot["group"])] as Array)


static func rating(robot: Dictionary, k: String) -> float:
	return float((robot["ratings"] as Dictionary).get(k, BASE))


## One number for the robot: the mean of his ratings.
static func overall(robot: Dictionary) -> int:
	var ks := keys(robot)
	var s := 0.0
	for k in ks:
		s += rating(robot, k)
	return int(roundf(s / ks.size()))


static func _f(robot: Dictionary, k: String) -> float:
	return (rating(robot, k) - BASE) / 40.0      # -0.9 at 25, 0 at 60, +0.9 at 96


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
	return b
