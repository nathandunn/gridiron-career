extends SceneTree
## Blitzers near the quarterback: how long does a free one spend within reach without a sack?
const Side := preload("res://tests/_ls_side.gd")

func _init() -> void:
	Library.ensure()
	PlaySim.K["wear"] = 0.0
	var offs: Array = Library.plays_for("offense").filter(func(x): return (Library.play(x) as Play).kind != "run" and (Library.play(x) as Play).name.begins_with("PA"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var off := Side.side(0, "average", "average", rng)
	var dfn := Side.side(1, "average", "average", rng)
	var hover := 0
	var plays := 0
	var why := {}
	var bitten := 0
	var blitzers := 0
	for i in 400:
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		var gd := PlayGen.defense(rng)
		s.setup(off, dfn, Library.play(offs[rng.randi() % offs.size()]), gd["play"],
			{"yl": 35.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		plays += 1
		for e0: PlaySim.P in s.dfn:
			if String(e0.assign.get("kind", "")) == "blitz":
				blitzers += 1
		var near_t := {}
		var bit := {}
		var guard := 0
		while not s.over and guard < 2000:
			s.step()
			if s.thrown or s.t > 4.0:
				break
			guard += 1
			if s.thrown:
				break
			var qb: PlaySim.P = s.by_slot.get("o:QB")
			for e: PlaySim.P in s.dfn:
				if String(e.assign.get("kind", "")) == "blitz" and s.t < e.bitten_until and not bit.has(e):
					bit[e] = true
				if e.down:
					continue
				var d := e.pos.distance_to(qb.pos)
				if d < 2.2:
					near_t[e.slot] = float(near_t.get(e.slot, 0.0)) + PlaySim.DT
					if float(near_t[e.slot]) > 0.6 and float(near_t[e.slot]) < 0.6 + PlaySim.DT * 1.5:
						hover += 1
						var k := "engaged" if e.engaged != null else ("bitten" if s.t < e.bitten_until else "")
						if k == "":
							k = "free d=%.1f intent=%s kind=%s" % [d, e.intent, String(e.assign.get("kind", ""))]
						var kk := k if e.engaged != null else "free " + k.get_slice("intent=", 1)
						why[kk] = int(why.get(kk, 0)) + 1
						if hover <= 8:
							print("  ", e.slot, " ", k, " t=", snappedf(s.t, 0.01))
		bitten += bit.size()

	print("plays %d, blitzers hanging within 2.2 yds of the QB for 0.6 s+: %d" % [plays, hover])
	print(why)
	print("blitzers %d, of them stopped by the play fake %d" % [blitzers, bitten])
	quit()
