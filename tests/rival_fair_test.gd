extends SceneTree
## Rival clubs spend their season money before week 1 (Best buy, keeping $400), are paid on
## the same table as you in their own games, and repair after them.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.ensure()
	var clubs: Array = Career.season()["clubs"]
	for c in clubs:
		print("%s purse $%d  %s" % [c["name"], int(c["money"]), Career.ratings_text(c)])
		assert(int(c["money"]) <= 1000 and int(c["money"]) >= 0)
	print("you: purse $%d  %s" % [Career.money(0), Career.ratings_text(Career.team(0))])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	print("OK")
	quit()
