extends SceneTree
## Saves keep across updates while the schema holds; a different schema, or a file that can't be
## read, starts a new career - with the old file kept, and the last good save tried first.
func _fresh() -> void:
	Career.loaded = false
	Career.data = {}
	Career.wiped = ""
	Career.ensure()

func _init() -> void:
	Library.ensure()
	var ok := true
	for p in [Career.PATH, Career.PREV_PATH, Career.OLD_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_fresh()
	Career.add_money(0, 1234)
	var m := Career.money(0)
	Career.save()
	_fresh()                                   # same schema: kept
	ok = ok and Career.money(0) == m and Career.wiped == ""
	# an old save without the field is taken as this schema
	var d: Dictionary = Career.data.duplicate(true)
	d.erase("schema")
	var f := FileAccess.open(Career.PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	_fresh()
	ok = ok and Career.money(0) == m and int(Career.data["schema"]) == Career.SCHEMA
	# a cut-off write: the previous save is used
	Career.save()
	f = FileAccess.open(Career.PATH, FileAccess.WRITE); f.store_string("{\"teams\": [ broken"); f.close()
	_fresh()
	ok = ok and Career.money(0) == m and Career.wiped == ""
	# another schema: put aside, a new career
	d = Career.data.duplicate(true)
	d["schema"] = Career.SCHEMA + 1
	f = FileAccess.open(Career.PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	_fresh()
	ok = ok and Career.wiped != "" and FileAccess.file_exists(Career.OLD_PATH) and Career.money(0) != m
	print("schema_test ", "OK" if ok else "FAIL")
	quit()
