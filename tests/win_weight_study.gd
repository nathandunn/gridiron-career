extends SceneTree
## How much does each position group swing a game? Side 0 has one group 10 points better at
## every rating; side 1 is all normal. Prints the average point margin and win rate.
##   godot --headless -s tests/win_weight_study.gd -- --group=QB --games=40
const LS = preload("res://tests/_ls_side.gd")
func _init() -> void:
	Library.ensure()
	var g := "QB"
	var ng := 40
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv[0] == "group": g = kv[1]
		if kv[0] == "games": ng = int(kv[1])
		if kv[0] == "boost": PlaySim.K["boost"] = float(kv[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var margin := 0.0
	var wins := 0.0
	var n := 0
	for i in ng:
		var a := LS.side(0, "average", "average", rng)
		var b := LS.side(1, "average", "average", rng)
		for s in a["roster"]:
			var r: Dictionary = a["roster"][s]
			if String(r["group"]) == g:
				for k in r["ratings"]:
					r["ratings"][k] = clampi(int(r["ratings"][k]) + int(PlaySim.K.get("boost", 20.0)), 20, 99)
		var res := Batch.play_game(a, b, 300.0, 500 + i)
		var m: int = res.score[0] - res.score[1]
		margin += m
		wins += 1.0 if m > 0 else (0.5 if m == 0 else 0.0)
		n += 1
	print("RESULT %s margin %.2f win %.3f games %d" % [g, margin / n, wins / n, n])
	quit()
