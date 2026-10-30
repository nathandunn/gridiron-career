extends SceneTree
## Whole games: Red's O-line quality x Blue's D-line quality (everyone else a plain 60, stock
## parts; Red's D-line and Blue's O-line average). Red's offense: yards a carry, a pass attempt,
## sacks, points. Both sides coached "Balanced".   -- --ol=great --games=12
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	var ol := "average"
	var games := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ol="):
			ol = a.substr(5)
		if a.begins_with("--games="):
			games = int(a.substr(8))
	for dl in ["great", "average", "poor"]:
		var t := {"ra": 0, "ry": 0.0, "pa": 0, "c": 0, "py": 0.0, "sk": 0, "sy": 0.0, "int": 0, "pts": 0, "stuff": 0, "big": 0, "runs": 0}
		for i in games:
			var rng := RandomNumberGenerator.new()
			rng.seed = 4000 + i
			var red := Side.side(0, ol, "average", rng)
			var blue := Side.side(1, "average", dl, rng)
			var g := Batch.play_game(red, blue, 300.0, 7000 + i)
			var st: Dictionary = g.stats[0]
			t["ra"] += int(st["rush_att"])
			t["ry"] += float(st["rush_yds"])
			t["pa"] += int(st["pass_att"])
			t["c"] += int(st["comp"])
			t["py"] += float(st["pass_yds"])
			t["sk"] += int(st["sacks"])
			t["sy"] += float(st["sack_yds"])
			t["int"] += int(st["ints"])
			t["pts"] += g.score[0]
			for e in g.log:
				if int(e.get("team", -1)) == 0 and String(e.get("kind", "")) == "play" and not e.get("return", false) and String(e.get("off", "")) in Library.plays_for("offense") and (Library.play(String(e["off"])) as Play).kind == "run":
					t["runs"] += 1
					if float(e.get("gain", 0.0)) <= 0.0:
						t["stuff"] += 1
					if float(e.get("gain", 0.0)) >= 10.0:
						t["big"] += 1
		var drop := maxf(t["pa"] + t["sk"], 1)
		print("CSV,%s,%s,%.2f,%.0f,%.0f,%.2f,%.0f,%.2f,%.1f,%.2f,%.1f,%d" % [ol, dl, t["ry"] / maxf(t["ra"], 1), 100.0 * t["stuff"] / maxf(t["runs"], 1), 100.0 * t["big"] / maxf(t["runs"], 1),
			t["py"] / maxf(t["pa"], 1), 100.0 * t["c"] / maxf(t["pa"], 1), float(t["sk"]) / games, 100.0 * t["sk"] / drop, (t["py"] + t["sy"]) / drop, float(t["pts"]) / games, t["ra"] + t["pa"]])
	print("OK")
	quit()
