extends SceneTree
## Cloud saves round trip against a local saves/server.py (GRIDIRON_SAVE_SITE): a save goes up
## under a made-up code, the device loses it, the code brings it back.
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CloudSave.CFG))
	CloudSave.start(root)
	await process_frame
	Career.loaded = false
	Career.ensure()
	var name0 := String(Career.data["teams"][0]["name"])
	var money0 := int(Career.data["money"][0])
	Career.data["money"][0] = money0 + 1234
	Career.save()
	var code := CloudSave.me.ensure_code()
	print("code ", code)
	for i in 150:
		await create_timer(0.1).timeout
		if CloudSave.me.status == "saved":
			break
	assert(CloudSave.me.status == "saved", "it went up")
	# the device forgets everything but the code
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	Career.loaded = false
	Career.data = {}
	var res := []
	CloudSave.me.load_code(code.to_lower(), func(ok, m): res.append([ok, m]))
	for i in 150:
		await create_timer(0.1).timeout
		if not res.is_empty():
			break
	assert(not res.is_empty() and res[0][0], "loaded back")
	Career.ensure()
	assert(int(Career.data["money"][0]) == money0 + 1234 and String(Career.data["teams"][0]["name"]) == name0)
	var bad := []
	CloudSave.me.load_code("ZZZZ-ZZZZ-ZZZZ", func(ok, m): bad.append([ok, m]))
	for i in 150:
		await create_timer(0.1).timeout
		if not bad.is_empty():
			break
	print("unknown code: ", bad)
	assert(not bad[0][0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CloudSave.CFG))
	print("OK")
	quit()
