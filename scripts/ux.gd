class_name Ux
extends Node
## Usage tracking: what gets tapped, which panels open and how long they stay open, so the
## UI can be improved from how it is really used. Nothing about the person is sent - a random
## id for the browser, one for the visit, and the events.
##
## In the browser, events queue in JavaScript and go to /ux with sendBeacon every 15 seconds
## and when the tab is hidden or closed; nginx writes each batch as one line of
## /var/log/ux/ux.log on the hub. Off the web they are appended to user://ux.log instead.

static var me: Ux = null
var _t0 := 0
var _panel := "field"
var _panel_t := 0.0
var _web := false


static func start(host: Node) -> void:
	if me != null:
		return
	me = Ux.new()
	me.name = "Ux"
	host.add_child(me)


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_web = OS.has_feature("web")
	if _web:
		JavaScriptBridge.eval("""
(function(){
  if (window.__ux) return;
  var cid = '';
  try { cid = localStorage.getItem('ux_cid') || ''; if (!cid) { cid = Math.random().toString(36).slice(2, 12); localStorage.setItem('ux_cid', cid); } } catch (e) { cid = 'anon'; }
  window.__ux = {q: [], cid: cid, sid: Math.random().toString(36).slice(2, 10),
    send: function () {
      if (!this.q.length) return;
      var body = JSON.stringify({cid: this.cid, sid: this.sid, at: new Date().toISOString(), ev: this.q});
      this.q = [];
      try { navigator.sendBeacon('/ux', body); } catch (e) {}
    }};
  setInterval(function () { window.__ux.send(); }, 15000);
  addEventListener('pagehide', function () { window.__ux.send(); });
  document.addEventListener('visibilitychange', function () { if (document.hidden) window.__ux.send(); });
})();
""", true)
	var vp := get_viewport().get_visible_rect().size
	ev("start", {"v": BuildInfo.VERSION, "w": int(vp.x), "h": int(vp.y), "touch": DisplayServer.is_touchscreen_available()})
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(n)


## Record one event: kind, plus whatever goes with it.
static func ev(kind: String, data: Dictionary = {}) -> void:
	if me == null:
		return
	var e := data.duplicate()
	e["k"] = kind
	e["s"] = snappedf(float(Time.get_ticks_msec() - me._t0) / 1000.0, 0.1)
	if not e.has("p"):
		e["p"] = me._panel
	me._send(e)


## The panel on screen changed ("field" when none is open): logs how long the last one stayed.
static func panel(title: String) -> void:
	if me == null or title == me._panel:
		return
	var now := float(Time.get_ticks_msec() - me._t0) / 1000.0
	ev("panel", {"p": title, "from": me._panel, "stayed": snappedf(now - me._panel_t, 0.1)})
	me._panel = title
	me._panel_t = now


func _send(e: Dictionary) -> void:
	var js := JSON.stringify(e)
	if _web:
		JavaScriptBridge.eval("window.__ux && window.__ux.q.push(%s);" % js, true)
	else:
		var f := FileAccess.open("user://ux.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://ux.log") else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(js)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("_ux"):
		n.set_meta("_ux", true)
		var b := n as BaseButton
		b.pressed.connect(func(): Ux.ev("tap", {"b": Ux.label_of(b), "on": b.button_pressed if b.toggle_mode else null}))


## What a button says: its own text, or the first text inside it (the play cards).
static func label_of(b: BaseButton) -> String:
	var t := ""
	if b is Button:
		t = (b as Button).text
	if t == "":
		for c in b.find_children("*", "Label", true, false):
			if (c as Label).text != "":
				t = (c as Label).text
				break
	return t.substr(0, 60)
