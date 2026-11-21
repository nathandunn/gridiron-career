extends SceneTree
## Dealt cards in the play review: each maps to a playbook play, so your table groups like the coach's.
func _init() -> void:
	Library.ensure()
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Air Raid")
	var g := Batch.play_game(red, blue, 60.0, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for i in 40:
		for side in ["offense", "defense"]:
			for c in PlayGen.hand(rng, side, 4, 10.0):
				var nn := g.nearest_name(c["play"], side == "offense")
				assert(nn != "" and Library.play(nn) != null, "a dealt card maps to a playbook play")
				seen[nn] = true
	print("dealt cards map onto %d playbook plays" % seen.size())
	print("like_test OK")
	quit()
