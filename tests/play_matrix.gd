extends SceneTree
## Every playbook offense play against every playbook defense play, N times each, equal bodies,
## from 1st and 10 at the offense's 35. Writes data/play_stats.json: for each pair the list of
## gains (a turnover is -99), which is all the coaches and the play picker need to work out the
## chance a play makes any distance, its average and how sure we are of it.
##   godot --headless --path . -s tests/play_matrix.gd -- --n=120 [--shard=0/4]
func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var n := 120
	var shard := 0
	var shards := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		if a.begins_with("--shard="):
			shard = int(a.substr(8).get_slice("/", 0))
			shards = int(a.substr(8).get_slice("/", 1))
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Balanced")
	var offs: Array = Library.plays_for("offense")
	var defs: Array = Library.plays_for("defense")
	var out := {"n": n, "yl": 35, "pairs": {}}
	var rng := RandomNumberGenerator.new()
	var k := 0
	for on in offs:
		for dn in defs:
			k += 1
			if (k - 1) % shards != shard:
				continue
			rng.seed = hash(on + "|" + dn)
			var gains: Array = []
			for i in n:
				var s := PlaySim.new()
				var r := RandomNumberGenerator.new()
				r.seed = rng.randi()
				s.setup(red, blue, Library.play(on), Library.play(dn), {"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
				var res := s.run_to_end()
				var g := 0.0 if res["incomplete"] else float(res["y"])
				if res["turnover"] != "":
					g = -99.0
				gains.append(snappedf(g, 0.1))
			out["pairs"][on + "|" + dn] = gains
	var f := FileAccess.open("res://data/play_stats_%d.json" % shard if shards > 1 else "res://data/play_stats.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print("MATRIX done: %d pairs x %d" % [out["pairs"].size(), n])
	quit()
