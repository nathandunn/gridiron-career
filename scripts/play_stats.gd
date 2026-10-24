class_name PlayStats
extends RefCounted
## What every playbook play has done against every playbook defense, measured
## (tests/play_matrix.gd: 200 snaps a pair, equal bodies, 1st and 10 from the 35) and shipped
## in data/play_stats.json. From the list of gains for a pair we get the chance a play makes
## any distance, its average, and how sure we can be of either (a 95% margin from the sample).
##
## Coaches use it with `call the best play` (or `best pass` / `best run`): among the plays they
## can call, the ones whose chance of making the line to gain is not clearly worse than the best
## (inside each other's margins) - one of those, at random. The play picker uses it to grade the
## coach's call.

const PATH := "res://data/play_stats.json"
static var _pairs := {}
static var _n := 0
static var _loaded := false


static func ensure() -> bool:
	if _loaded:
		return not _pairs.is_empty()
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_pairs = parsed.get("pairs", {})
		_n = int(parsed.get("n", 0))
	return not _pairs.is_empty()


static func has(off: String, def: String) -> bool:
	return ensure() and _pairs.has(off + "|" + def)


## Chance the offense play gains at least `need` yards (a turnover is a failure) against a
## defense, or against all the measured defenses evenly when def is "". [p, margin, n]
static func success(off: String, need: float, def := "") -> Array:
	if not ensure():
		return [0.0, 1.0, 0]
	var hit := 0
	var n := 0
	for key in _pairs:
		var o := String(key).get_slice("|", 0)
		var d := String(key).get_slice("|", 1)
		if o != off or (def != "" and d != def):
			continue
		for g in _pairs[key]:
			n += 1
			if float(g) >= need:
				hit += 1
	if n == 0:
		return [0.0, 1.0, 0]
	var p := float(hit) / n
	return [p, 1.96 * sqrt(maxf(p * (1.0 - p), 0.0025) / n), n]


## Average gain (turnovers counted as -20, about what one costs in field position). [mean, margin]
static func average(off: String, def := "") -> Array:
	if not ensure():
		return [0.0, 99.0]
	var xs: Array = []
	for key in _pairs:
		if String(key).get_slice("|", 0) != off or (def != "" and String(key).get_slice("|", 1) != def):
			continue
		for g in _pairs[key]:
			xs.append(-20.0 if float(g) <= -90.0 else float(g))
	if xs.is_empty():
		return [0.0, 99.0]
	var m := 0.0
	for x in xs:
		m += x
	m /= xs.size()
	var v := 0.0
	for x in xs:
		v += (x - m) * (x - m)
	v /= maxf(xs.size() - 1, 1)
	return [m, 1.96 * sqrt(v / xs.size())]


## Chance a defense play stops the offense short of `need` (against all measured offenses).
static func stop(def: String, need: float) -> Array:
	if not ensure():
		return [0.0, 1.0, 0]
	var hit := 0
	var n := 0
	for key in _pairs:
		if String(key).get_slice("|", 1) != def:
			continue
		for g in _pairs[key]:
			n += 1
			if float(g) < need:
				hit += 1
	if n == 0:
		return [0.0, 1.0, 0]
	var p := float(hit) / n
	return [p, 1.96 * sqrt(maxf(p * (1.0 - p), 0.0025) / n), n]


## Like success/stop, but against the other side's plays weighted by how often they have
## called them (`weights`: play name -> times; every measured play also counts once, so a few
## calls only lean the answer, they don't swing it). For offense `name` is ours and the weights
## are their defenses; for defense the other way round.
static func weighted(name: String, need: float, defense: bool, weights: Dictionary) -> Array:
	if not ensure():
		return [0.0, 1.0, 0]
	var num := 0.0
	var den := 0.0
	var n := 0
	for key in _pairs:
		var o := String(key).get_slice("|", 0)
		var d := String(key).get_slice("|", 1)
		if (d if defense else o) != name:
			continue
		var w := 1.0 + float(weights.get(o if defense else d, 0))
		var gains: Array = _pairs[key]
		var hit := 0
		for g in gains:
			if (float(g) < need) if defense else (float(g) >= need):
				hit += 1
		num += w * float(hit) / gains.size()
		den += w
		n += gains.size()
	if den == 0.0:
		return [0.0, 1.0, 0]
	var p := num / den
	return [p, 1.96 * sqrt(maxf(p * (1.0 - p), 0.0025) / n), n]


## The plays from `names` that are not clearly worse than the best at making `need` (offense)
## or stopping it (defense): each one's chance plus its margin reaches the best one's chance
## less its margin. Sorted best first: [[name, p, margin], ...]
static func best_of(names: Array, need: float, defense: bool, weights: Dictionary = {}) -> Array:
	var scored: Array = []
	for nm in names:
		var s := weighted(nm, need, defense, weights)
		if int(s[2]) > 0:
			scored.append([nm, float(s[0]), float(s[1])])
	scored.sort_custom(func(a, b): return a[1] > b[1])
	if scored.is_empty():
		return []
	var top: Array = scored[0]
	var out: Array = []
	for s in scored:
		if float(s[1]) + float(s[2]) >= float(top[1]) - float(top[2]):
			out.append(s)
	return out


## A grade for a call: where it ranks among all the playbook's plays of that side for this
## distance. {p, margin, rank, of, best, best_p, avg_p, grade}
static func grade(name: String, need: float, defense: bool) -> Dictionary:
	var names := Library.plays_for("defense" if defense else "offense")
	var rows: Array = []
	var mean := 0.0
	for nm in names:
		var s := stop(nm, need) if defense else success(nm, need)
		if int(s[2]) == 0:
			continue
		rows.append([nm, float(s[0]), float(s[1])])
		mean += float(s[0])
	if rows.is_empty():
		return {}
	mean /= rows.size()
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var rank := -1
	var me: Array = []
	for i in rows.size():
		if rows[i][0] == name:
			rank = i + 1
			me = rows[i]
	if rank < 0:
		return {}
	# a letter by where it stands: A when it is not clearly worse than the best, F when it is
	# clearly worse than the playbook's average
	var top: Array = rows[0]
	var letter := "C"
	if float(me[1]) + float(me[2]) >= float(top[1]) - float(top[2]):
		letter = "A"
	elif float(me[1]) - float(me[2]) > mean:
		letter = "B"
	elif float(me[1]) + float(me[2]) < mean:
		letter = "D" if float(me[1]) + float(me[2]) >= mean - 0.1 else "F"
	return {"p": me[1], "margin": me[2], "rank": rank, "of": rows.size(), "best": top[0], "best_p": top[1],
		"avg_p": mean, "grade": letter}
