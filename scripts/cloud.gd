class_name CloudSave
extends Node
## Cloud saves by code. Every time the career is saved it is also sent (a few seconds later, the
## newest only) to the hub, filed under a private save code - three groups of four letters and
## digits, made up on this device the first time. Nothing about the person goes with it.
##
## The code is what moves a career: type it into another phone or computer ("Load a save code"),
## or open the game with ?save=CODE on the end of the address. If a phone forgets its storage,
## the code brings the career back - so the menu shows it, and the link to keep.
##
## The hub side is saves/server.py behind nginx at /api/save/<code>.

const SITE := "https://gridiron-career.apps.precogsoftwareservices.com"
const CFG := "user://cloud.cfg"
const DELAY := 3.0                    # seconds after a save before it goes up
const ALPHA := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I to misread

static var me: CloudSave = null
var code := ""
var last_sync := 0            # unix time the cloud last took (or gave) a save
var status := ""              # "saved", "saving", "offline", "loaded", ...
var _due := -1.0
var _busy := false
var _http: HTTPRequest


static func start(host: Node) -> void:
	if me != null:
		return
	me = CloudSave.new()
	me.name = "CloudSave"
	host.add_child(me)


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		code = String(cf.get_value("cloud", "code", ""))
		last_sync = int(cf.get_value("cloud", "last_sync", 0))
	# a save code in the address (?save=CODE): that career is the one to play
	var from_url := _url_code()
	if from_url != "" and from_url != code:
		load_code(from_url)
	elif code != "" and not FileAccess.file_exists(Career.PATH):
		# this device lost its save (or never had it) but knows its code: fetch it back
		load_code(code)


func _process(delta: float) -> void:
	if _due >= 0.0:
		_due -= delta
		if _due < 0.0:
			_push()


## Career.save() calls this: send the save up shortly (several saves close together go as one).
static func queue() -> void:
	if me != null:
		me._due = DELAY


## The save code, made up the first time it is needed.
func ensure_code() -> String:
	if code == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var parts: Array = []
		for g in 3:
			var s := ""
			for i in 4:
				s += ALPHA[rng.randi() % ALPHA.length()]
			parts.append(s)
		code = "-".join(parts)
		_store()
	return code


## The link that opens this career anywhere.
func link() -> String:
	return "%s/?save=%s" % [SITE, ensure_code()]


static func clean(c: String) -> String:
	var s := c.strip_edges().to_upper().replace(" ", "")
	var out := ""
	for ch in s:
		if ALPHA.contains(ch) or ch == "-":
			out += ch
	return out


func _url() -> String:
	return _site() + "/api/save/" + code


func _site() -> String:
	var env := OS.get_environment("GRIDIRON_SAVE_SITE")     # tests point it at a local server
	if env != "":
		return env
	if OS.has_feature("web"):
		var o: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if o is String and String(o).begins_with("http"):
			return String(o)
	return SITE


func _url_code() -> String:
	if not OS.has_feature("web"):
		return ""
	var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('save') || ''", true)
	return clean(String(q)) if q is String else ""


func _store() -> void:
	var cf := ConfigFile.new()
	cf.set_value("cloud", "code", code)
	cf.set_value("cloud", "last_sync", last_sync)
	cf.save(CFG)


func _push() -> void:
	if _busy:
		_due = 1.0
		return
	if not FileAccess.file_exists(Career.PATH):
		return
	ensure_code()
	var body := FileAccess.get_file_as_string(Career.PATH)
	_busy = true
	status = "saving"
	_http.request_completed.connect(_pushed, CONNECT_ONE_SHOT)
	var err := _http.request(_url(), ["Content-Type: application/json"], HTTPClient.METHOD_PUT, body)
	if err != OK:
		_http.request_completed.disconnect(_pushed)
		_busy = false
		status = "offline"


func _pushed(result: int, rc: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and rc >= 200 and rc < 300:
		last_sync = int(Time.get_unix_time_from_system())
		status = "saved"
		_store()
	else:
		status = "offline"
		_due = 30.0           # try again later


## Fetch the career filed under `c` and play it (the page reloads into it). `done` gets
## (ok, message).
func load_code(c: String, done := Callable()) -> void:
	var cc := clean(c)
	if cc.length() < 8:
		if done.is_valid():
			done.call(false, "That doesn't look like a save code.")
		return
	if _busy:
		await _http.request_completed
	_busy = true
	status = "loading"
	var url := _site() + "/api/save/" + cc
	_http.request_completed.connect(_loaded.bind(cc, done), CONNECT_ONE_SHOT)
	var err := _http.request(url)
	if err != OK:
		_http.request_completed.disconnect(_loaded)
		_busy = false
		if done.is_valid():
			done.call(false, "Couldn't reach the save server.")


func _loaded(result: int, rc: int, _h: PackedStringArray, b: PackedByteArray, cc: String, done: Callable) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		status = "offline"
		if done.is_valid():
			done.call(false, "Couldn't reach the save server - try again when online.")
		return
	if rc == 404:
		status = ""
		if done.is_valid():
			done.call(false, "No career is saved under that code.")
		return
	var txt := b.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(txt)
	if rc != 200 or not (parsed is Dictionary and (parsed as Dictionary).has("teams")):
		status = ""
		if done.is_valid():
			done.call(false, "That save couldn't be read.")
		return
	var f := FileAccess.open(Career.PATH, FileAccess.WRITE)
	if f == null:
		if done.is_valid():
			done.call(false, "Couldn't write the save on this device.")
		return
	f.store_string(txt)
	f.close()
	code = cc
	last_sync = int(Time.get_unix_time_from_system())
	status = "loaded"
	_store()
	if done.is_valid():
		done.call(true, "Loaded.")
	# start over on the loaded career
	Career.loaded = false
	Career.data = {}
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()


## "Saved to the cloud 3 min ago" and the like, for the menu.
func status_text() -> String:
	if code == "":
		return "Not saved to the cloud yet - it will be after the next save."
	match status:
		"saving": return "Saving to the cloud..."
		"loading": return "Loading from the cloud..."
		"offline": return "Couldn't reach the cloud - it will try again."
	if last_sync <= 0:
		return "Waiting for the next save."
	var ago := int(Time.get_unix_time_from_system()) - last_sync
	var t := "just now" if ago < 60 else ("%d min ago" % (ago / 60) if ago < 3600 else ("%d h ago" % (ago / 3600) if ago < 86400 else "%d days ago" % (ago / 86400)))
	return "Saved to the cloud %s." % t
