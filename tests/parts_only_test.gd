extends SceneTree
## A robot is the sum of his parts: the same parts make the same ratings on any team, and a new
## season starts every team level.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	var seen := {}
	var teams: Array = [Career.data["teams"][0]] + Career.season()["clubs"]
	for tm in teams:
		for s in tm["starters"]:
			var r: Dictionary = tm["starters"][s]
			var key := String(r["group"])
			for k in Robot.PARTS:
				key += String(r["parts"][k]["tier"])
			var o := Robot.overall_if(r, "now")
			if seen.has(key):
				assert(seen[key] == o, "same parts, different rating: " + key)
			seen[key] = o
	# equal starts (before rivals spend: the clubs have spent their season money already)
	Career.new_season()
	for tm in [Career.data["teams"][0]] + Career.season()["clubs"]:
		print("%s %s purse $%d" % [tm["name"], Career.ratings_text(tm), Career.money(0) if tm == Career.data["teams"][0] else int(tm["money"])])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	print("OK")
	quit()
