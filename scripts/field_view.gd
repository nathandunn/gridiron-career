class_name FieldView
extends Node3D
## The arena and the robots, drawn from a PlaySim. World units are yards: x across the field,
## z along it with Red's goal line at z = -50 and Blue's at z = +50 (Red attacks +z).
##
## The look is a neon robot-football arena: a dark steel field with glowing lines, lit rails and
## walls, light towers, and armoured robots with visor lights in team colours.

const HALF_W := 26.667
## Team colours (the HUD uses these too): a hot red-orange and an electric blue.
const COLORS := [Color(1.0, 0.24, 0.18), Color(0.15, 0.62, 1.0)]
const NEON := [Color(1.0, 0.35, 0.25), Color(0.3, 0.75, 1.0)]
const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const YELLOW := Color(1.0, 0.85, 0.2)
const STEEL := Color(0.16, 0.18, 0.22)

var _players := {}           # idx -> {root, legs, label, ...}
var _ball: MeshInstance3D
var _ball_light: OmniLight3D
var _los: MeshInstance3D
var _sticks: MeshInstance3D
var _mats := {}
var sim: PlaySim = null
var poss := 0                # who has the ball (0 Red, 1 Blue)
var yl := 25.0               # the offense's yard line
var _prev := {}              # idx -> Vector2 (last step), for smoothing
var _cur := {}
var alpha := 1.0             # how far between the last two steps
var _t := 0.0
var _pulse: Array = []       # emissive materials that breathe
var _seen := 0               # sim.actions already acted out
var _celeb := {}             # a score being celebrated: {team, spot, t0, pos: {idx: Vector2}}
var _ball_fx := {}           # a loose or dead ball bouncing: {p0, p1, t0, hop}
var _fx_nodes: Array = []    # popups, sparks, speech: {node, t0, life, kind, ...}
var _spark_mat: Dictionary = {}
var talk := true             # robots talk trash

signal moment(a: Dictionary)                              # each action as it is acted out
signal trash_talk(team: int, slot: String, line: String, who: String)  # a robot says something


func _ready() -> void:
	_build_field()
	_ball = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.18
	bm.height = 0.36
	_ball.mesh = bm
	_ball.scale = Vector3(1, 1, 1.7)
	_ball.material_override = _glow(Color(1.0, 0.6, 0.15), 3.0)
	add_child(_ball)
	_ball_light = OmniLight3D.new()
	_ball_light.light_color = Color(1.0, 0.6, 0.2)
	_ball_light.light_energy = 0.9
	_ball_light.omni_range = 3.0
	_ball.add_child(_ball_light)
	_los = _line(CYAN, 2.5)
	_sticks = _line(YELLOW, 2.5)


## ---- materials -------------------------------------------------------------------------------

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var key := "m%s%s" % [c.to_html(), unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## Brushed metal: dark, a little shine.
func _metal(c: Color) -> StandardMaterial3D:
	var key := "x%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.75
	m.roughness = 0.35
	_mats[key] = m
	return m


## Light that glows.
func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "g%s%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	return mi


func _line(c: Color, energy: float) -> MeshInstance3D:
	return _box(Vector3(HALF_W * 2.0, 0.03, 0.22), Vector3(0, 0.04, 0), _glow(c, energy))


## ---- the arena -------------------------------------------------------------------------------

func _build_field() -> void:
	# the arena floor beyond the field
	_box(Vector3(140, 0.1, 190), Vector3(0, -0.1, 0), _metal(Color(0.07, 0.08, 0.1)))
	# the field: light grey steel plates in five-yard bands - neutral, so red and blue robots
	# both stand out against it
	for i in 20:
		var shade := Color(0.42, 0.43, 0.44) if i % 2 == 0 else Color(0.37, 0.38, 0.39)
		_box(Vector3(HALF_W * 2.0, 0.04, 5.0), Vector3(0, -0.02, -47.5 + i * 5.0), _mat(shade))   # matte: no glare
	# end zones: team light, with chevrons
	for t in 2:
		var z := -55.0 if t == 0 else 55.0
		_box(Vector3(HALF_W * 2.0, 0.04, 10.0), Vector3(0, -0.015, z), _mat(COLORS[t].darkened(0.6)))
		var dir := -1.0 if t == 0 else 1.0
		for k in 5:
			var cz := z - dir * 3.5 + dir * k * 1.6
			for side: float in [-1.0, 1.0]:
				var ch := _box(Vector3(6.0, 0.02, 0.35), Vector3(side * (HALF_W - 5.0), 0.03, cz), _glow(NEON[t], 1.4))
				ch.rotation.y = side * dir * 0.5
		var lab := Label3D.new()
		lab.text = ["RED", "BLUE"][t]
		lab.font_size = 600
		lab.pixel_size = 0.012
		lab.outline_size = 0
		lab.modulate = NEON[t].lightened(0.3)
		lab.rotation = Vector3(-PI / 2, PI if t == 1 else 0.0, 0)
		lab.position = Vector3(0, 0.04, z)
		add_child(lab)
	# glowing yard lines every five yards, numbers every ten
	for i in 21:
		var z := -50.0 + i * 5.0
		var goal := i == 0 or i == 20
		_box(Vector3(HALF_W * 2.0, 0.03, 0.22 if goal else (0.14 if i % 2 == 0 else 0.08)), Vector3(0, 0.0, z),
			_glow(YELLOW if goal else CYAN, 2.2 if goal else (0.9 if i % 2 == 0 else 0.5)))
		if i % 2 == 0 and i > 0 and i < 20:
			var n := 50 - absi(50 - i * 5)
			for side: float in [-1.0, 1.0]:
				var lab := Label3D.new()
				lab.text = str(n)
				lab.font_size = 180
				lab.pixel_size = 0.012
				lab.modulate = Color(0.55, 0.95, 1.0, 0.75)
				lab.rotation = Vector3(-PI / 2, PI / 2 * side, 0)
				lab.position = Vector3(side * (HALF_W - 6.0), 0.03, z)
				add_child(lab)
	# hash marks: small lights
	var hash_mat := _glow(Color(0.45, 0.85, 1.0, 0.7), 0.6)
	for i in range(1, 100):
		var z := -50.0 + i
		for hx: float in [-3.08, 3.08]:
			_box(Vector3(0.45, 0.02, 0.06), Vector3(hx, 0.0, z), hash_mat)
	# lit rails along the sidelines and end lines
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.25, 0.25, 120.6), Vector3(sx * (HALF_W + 0.4), 0.13, 0), _glow(MAGENTA, 2.4))
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(HALF_W * 2.0 + 1.0, 0.25, 0.25), Vector3(0, 0.13, sz * 60.4), _glow(MAGENTA, 2.4))
	# the arena wall: steel, a light strip along the top, lit panels
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.6, 3.2, 128), Vector3(sx * (HALF_W + 4.0), 1.6, 0), _metal(STEEL))
		_box(Vector3(0.65, 0.18, 128), Vector3(sx * (HALF_W + 4.0), 3.25, 0), _glow(CYAN, 2.0))
		for k in 12:
			var pz := -55.0 + k * 10.0
			var panel := _box(Vector3(0.1, 1.2, 6.5), Vector3(sx * (HALF_W + 3.68), 1.5, pz), _glow(NEON[k % 2].darkened(0.25), 1.2))
			_pulse.append(panel.material_override)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(HALF_W * 2.0 + 8.6, 3.2, 0.6), Vector3(0, 1.6, sz * 64.0), _metal(STEEL))
		_box(Vector3(HALF_W * 2.0 + 8.6, 0.18, 0.65), Vector3(0, 3.25, sz * 64.0), _glow(CYAN, 2.0))
	# goal posts in neon
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * 60.0
		var gm := _glow(YELLOW, 2.0)
		_box(Vector3(0.25, 3.3, 0.25), Vector3(0, 1.65, z), gm)
		_box(Vector3(6.2, 0.2, 0.2), Vector3(0, 3.3, z), gm)
		for px: float in [-3.0, 3.0]:
			_box(Vector3(0.2, 7.0, 0.2), Vector3(px, 6.8, z), gm)
	# stands: dark tiers with rows of crowd lights
	for sx: float in [-1.0, 1.0]:
		for r in 7:
			var x := sx * (HALF_W + 7.0 + r * 2.2)
			var h := 3.6 + r * 1.3
			_box(Vector3(2.2, h, 126), Vector3(x, h * 0.5, 0), _metal(Color(0.09, 0.1, 0.13).lightened(r * 0.015)))
			_box(Vector3(2.0, 0.08, 120), Vector3(x, h + 0.05, 0), _glow([CYAN, MAGENTA, NEON[0], NEON[1]][r % 4].darkened(0.55), 1.0))
	# light towers at the corners
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base := Vector3(sx * (HALF_W + 24.0), 0, sz * 58.0)
			_box(Vector3(0.8, 26.0, 0.8), base + Vector3(0, 13.0, 0), _metal(STEEL))
			var head := _box(Vector3(5.0, 2.2, 0.6), base + Vector3(0, 26.5, 0), _glow(Color(0.95, 0.97, 1.0), 3.0))
			head.look_at_from_position(head.position, Vector3(0, 0, 0), Vector3.UP)


## Where a play-frame point is in the world.
func world(p: Vector2, h := 0.0) -> Vector3:
	var a := yl + p.y                 # yards from the offense's own goal line
	# the camera stands behind the offense, so the play's right (+x) must be the screen's right:
	# looking down +z, screen right is world -x
	if poss == 0:
		return Vector3(-p.x, h, a - 50.0)
	return Vector3(p.x, h, 50.0 - a)


## The direction the offense attacks, in the world.
func attack_dir() -> float:
	return 1.0 if poss == 0 else -1.0


func set_play(s: PlaySim, possession: int, yard_line: float, to_go: float) -> void:
	sim = s
	poss = possession
	yl = yard_line
	_prev.clear()
	_cur.clear()
	_seen = 0
	_ball_fx = {}
	_celeb = {}
	# parts that came off stay where they fell (the newest 40); everything else goes
	var keep: Array = []
	for n in _fx_nodes:
		if n["kind"] == "debris":
			keep.append(n)
		else:
			(n["node"] as Node3D).queue_free()
	while keep.size() > 40:
		(keep.pop_front()["node"] as Node3D).queue_free()
	_fx_nodes = keep
	for k in _players:
		_players[k]["root"].visible = false
		_players[k]["anim"] = ""
		_players[k]["fall_yaw"] = INF
		_players[k]["tilt"] = 0.0
	if s == null:
		_ball.visible = false
		_los.visible = true
		_sticks.visible = true
		_place_line(_los, yard_line)
		_place_line(_sticks, minf(yard_line + to_go, 100.0))
		return
	_ball.visible = true
	# a kick or punt return has no line of scrimmage or first-down marker of its own: the
	# return play's "line" is only where the returner's wall sets up, so the lines are hidden
	var kick: bool = s.air.get("kick", false)
	_los.visible = not kick
	_sticks.visible = not kick
	for p in s.players:
		_ensure_player(p)
		_players[p.idx]["root"].visible = true
		(_players[p.idx]["label"] as Label3D).text = "RET" if kick and p == s.air_target else p.slot
		_prev[p.idx] = p.pos
		_cur[p.idx] = p.pos
	_place_line(_los, yard_line)
	_place_line(_sticks, minf(yard_line + to_go, 100.0))
	_sticks.visible = yard_line + to_go < 100.0 and not kick


func _place_line(mi: MeshInstance3D, offense_yl: float) -> void:
	var a := offense_yl if poss == 0 else 100.0 - offense_yl
	mi.position = Vector3(0, 0.04, a - 50.0)


## ---- the robots ------------------------------------------------------------------------------

## One robot: armoured legs, a torso in team colour with big shoulder plates, a head with a
## glowing visor and a chest light. Linemen are heavier; backs and receivers leaner.
func _ensure_player(p: PlaySim.P) -> void:
	var team := p.team
	var key := p.idx
	var rid := String(p.robot.get("id", "")) + _parts_sig(p.robot)
	if _players.has(key):
		var e: Dictionary = _players[key]
		if e["team"] == team and e["slot"] == p.slot and e["rid"] == rid:
			return
		(e["root"] as Node3D).queue_free()
	var r := build_robot(String(p.robot.get("group", p.group)), team, int(p.robot.get("number", -1)), p.robot.get("parts", {}))
	var root: Node3D = r["root"]
	add_child(root)
	var lab := Label3D.new()
	lab.text = p.slot
	lab.visible = not p.group in ["OL", "DL"]
	lab.font_size = 52
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 2.85, 0)
	lab.outline_size = 10
	lab.no_depth_test = true
	lab.modulate = NEON[team].lightened(0.4)
	root.add_child(lab)
	_players[key] = {"root": root, "body": r["body"], "legs": r["legs"], "arms": r["arms"], "head": r["head"], "nodes": r["nodes"],
		"wheels": r["wheels"], "flames": r["flames"], "label": lab,
		"team": team, "slot": p.slot, "rid": rid,
		"tilt": 0.0, "stride": 0.0, "roll": 0.0, "hop": 0.0, "lunge": 0.0, "arm": [0.0, 0.0], "anim": "", "anim_t": 0.0, "anim_yaw": 0.0, "fall_yaw": INF}


## One robot, not yet placed anywhere: armoured legs on hip pivots, a torso in team colour with
## big shoulder plates and a chest light, arms on shoulder pivots, and a head with a glowing
## visor. Linemen are heavier; backs and receivers leaner. {root, body, legs, arms, head}
## How each position is built. w: width, leg: leg length, chest: chest depth, sh: shoulder width,
## head: block (linemen), dome (backs, corners) or visor; extras pick the trimmings.
const STYLE := {
	"QB": {"w": 1.0, "leg": 1.0, "chest": 1.0, "sh": 0.95, "head": "visor", "extras": ["antenna", "monocle"]},
	"K": {"w": 0.86, "leg": 1.22, "chest": 0.88, "sh": 0.85, "head": "dome", "extras": ["antenna"]},
	"P": {"w": 0.9, "leg": 1.25, "chest": 0.9, "sh": 0.88, "head": "visor", "extras": ["antenna"]},
	"RB": {"w": 1.08, "leg": 0.86, "chest": 1.05, "sh": 1.0, "head": "dome", "extras": ["thigh_pads", "ram_bar"]},
	"WR": {"w": 0.84, "leg": 1.16, "chest": 0.9, "sh": 0.85, "head": "visor", "extras": ["antennas", "gloves"]},
	"TE": {"w": 1.12, "leg": 1.06, "chest": 1.1, "sh": 1.1, "head": "visor", "extras": ["gloves", "neck_roll"]},
	"OL": {"w": 1.38, "leg": 0.84, "chest": 1.25, "sh": 1.3, "head": "block", "extras": ["grille", "big_fists", "plates"]},
	"DL": {"w": 1.32, "leg": 0.86, "chest": 1.2, "sh": 1.3, "head": "block", "extras": ["horns", "spikes", "big_fists"]},
	"LB": {"w": 1.14, "leg": 0.96, "chest": 1.1, "sh": 1.15, "head": "visor", "extras": ["spikes", "neck_roll"]},
	"CB": {"w": 0.86, "leg": 1.1, "chest": 0.9, "sh": 0.88, "head": "dome", "extras": ["fins", "gloves"]},
	"S": {"w": 0.94, "leg": 1.06, "chest": 0.95, "sh": 0.95, "head": "visor", "extras": ["big_crest", "fins"]},
}


## One robot, not yet placed anywhere, built for his position (STYLE): armoured legs on hip
## pivots (rollers and a jet pack for skill players), a torso in team colour with shoulder plates
## and a chest light, arms on shoulder pivots, and a head - a block with a grille for linemen, a
## dome for backs and corners, a visor for the rest - with the trimmings of his job. Missing
## parts are hidden, junk is rusty, upgraded parts carry a glowing band. {root, body, legs, arms,
## head, nodes, wheels, flames}
func build_robot(group: String, team: int, number := -1, parts: Dictionary = {}) -> Dictionary:
	var st: Dictionary = STYLE.get(group, STYLE["LB"])
	var w: float = st["w"]
	var lg: float = st["leg"]
	var ch: float = st["chest"]
	var shw: float = st["sh"]
	var ex: Array = st["extras"]
	var root := Node3D.new()
	var body := Node3D.new()        # hops and lunges move this; root keeps the spot and facing
	root.add_child(body)
	var armour := _metal(COLORS[team].darkened(0.15))
	var dark := _metal(COLORS[team].darkened(0.55))
	var frame := _metal(Color(0.22, 0.24, 0.28))
	var light := _glow(NEON[team], 2.6)
	var skill := group in ["QB", "RB", "WR", "TE", "CB", "S"]
	var hip_y := 0.95 * lg
	var up := hip_y - 0.95          # how much higher (or lower) everything above the hips sits
	var wheels: Array = []
	var flames: Array = []
	var legs: Array = []
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.2 * w, hip_y, 0)
		body.add_child(hip)
		_box(Vector3(0.24 * w, 0.95 * lg, 0.28), Vector3(0, -0.48 * lg, 0), frame, hip)
		if "thigh_pads" in ex or "plates" in ex:
			_box(Vector3(0.3 * w, 0.32 * lg, 0.34), Vector3(0, -0.2 * lg, 0.02), armour, hip)   # thigh armour
		if skill:
			# a roller skate: a glowing wheel on an axle where the foot would be
			var axle := Node3D.new()
			axle.position = Vector3(0, -0.8 * lg, 0.05)
			hip.add_child(axle)
			var wm := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.15
			cyl.bottom_radius = 0.15
			cyl.height = 0.14 * w
			wm.mesh = cyl
			wm.rotation.z = PI * 0.5
			wm.material_override = frame
			axle.add_child(wm)
			_box(Vector3(0.16 * w, 0.05, 0.32), Vector3(0, 0.0, 0), light, axle)      # hub stripe that shows the spin
			wheels.append(axle)
		else:
			# linemen stand on big flat feet - built to plant and push
			_box(Vector3(0.36 * w, 0.18, 0.5), Vector3(0, -0.9 * lg, 0.08), armour, hip)
		_box(Vector3(0.26 * w, 0.18, 0.08), Vector3(0, -0.45 * lg, 0.15), light, hip)    # knee light
		legs.append(hip)
	# torso and plates
	_box(Vector3(0.62 * w, 0.75, 0.42 * ch), Vector3(0, 1.32 + up, 0), armour, body)
	_box(Vector3(0.95 * w * shw, 0.24, 0.55 * ch), Vector3(0, 1.72 + up, 0), armour, body)          # shoulders
	_box(Vector3(0.22, 0.14, 0.04), Vector3(0, 1.38 + up, 0.21 * ch + 0.01), light, body)            # chest light
	if "plates" in ex:
		_box(Vector3(0.7 * w, 0.2, 0.46 * ch), Vector3(0, 1.0 + up, 0), dark, body)                  # belly plate
	if "spikes" in ex:
		for sx: float in [-1.0, 1.0]:
			for k in 2:
				var sp := _box(Vector3(0.08, 0.28, 0.08), Vector3(sx * (0.3 + 0.14 * k) * w * shw, 1.92 + up, 0.05 - 0.1 * k), light, body)
				sp.rotation.z = -sx * 0.5
	if "neck_roll" in ex:
		_box(Vector3(0.5 * w, 0.12, 0.42 * ch), Vector3(0, 1.86 + up, -0.04), dark, body)
	if "ram_bar" in ex:
		_box(Vector3(0.5 * w, 0.1, 0.12), Vector3(0, 1.55 + up, 0.24 * ch), light, body)            # a lowered-shoulder bumper
	if skill:
		# a jet pack: two tanks on the back, each with a flame that grows with his speed
		for jx: float in [-0.14, 0.14]:
			var tank := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.09
			tc.bottom_radius = 0.11
			tc.height = 0.5
			tank.mesh = tc
			tank.material_override = frame
			tank.position = Vector3(jx * w, 1.42 + up, -0.21 * ch - 0.09)
			body.add_child(tank)
			_box(Vector3(0.16, 0.05, 0.16), Vector3(jx * w, 1.15 + up, -0.21 * ch - 0.09), light, body)     # nozzle ring
			var fl := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.08
			cone.bottom_radius = 0.0
			cone.height = 0.6
			fl.mesh = cone
			fl.material_override = _glow(Color(1.0, 0.6, 0.2) if team == 0 else Color(0.4, 0.8, 1.0), 4.0)
			var fp := Node3D.new()
			fp.position = Vector3(jx * w, 1.12 + up, -0.21 * ch - 0.09)
			body.add_child(fp)
			fp.add_child(fl)
			fl.position = Vector3(0, -0.3, 0)
			flames.append(fp)
	if "fins" in ex:
		for fx: float in [-1.0, 1.0]:
			var fin := _box(Vector3(0.04, 0.34, 0.26), Vector3(fx * 0.26 * w, 1.55 + up, -0.3 * ch), light, body)
			fin.rotation.z = fx * 0.35
	if number >= 0:
		for z: float in [0.21 * ch + 0.005, -0.21 * ch - 0.005]:
			var num := Label3D.new()
			num.text = str(number)
			num.font_size = 64
			num.pixel_size = 0.006 * (1.15 if w > 1.2 else 1.0)
			num.outline_size = 6
			num.modulate = Color(1, 1, 1)
			num.position = Vector3(0, 1.18 + up, z)
			num.rotation.y = 0.0 if z > 0.0 else PI
			body.add_child(num)
	# arms swing from the shoulder: rotation.x below 0 raises them forward, about -3 is overhead
	var arms: Array = []
	var fist := 1.45 if "big_fists" in ex else 1.0
	var arm_len := 1.12 if group == "WR" else 1.0
	for side: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.52 * w * shw, 1.64 + up, 0)
		body.add_child(sh)
		_box(Vector3(0.2 * (1.2 if w > 1.2 else 1.0), 0.7 * arm_len, 0.22), Vector3(0, -0.34 * arm_len, 0), frame, sh)
		_box(Vector3(0.24 * fist, 0.16 * fist, 0.26 * fist), Vector3(0, -0.72 * arm_len, 0.02), _glow(NEON[team], 1.6) if "gloves" in ex else armour, sh)   # fist (receivers' gloves glow)
		arms.append(sh)
	var head := Node3D.new()
	head.position = Vector3(0, 1.85 + up, 0)
	body.add_child(head)
	var helm := _metal(Color(0.12, 0.13, 0.16))
	match String(st["head"]):
		"block":
			# a wide square head sunk into the shoulders, with a grille for a face
			head.position.y -= 0.06
			_box(Vector3(0.5, 0.3, 0.44), Vector3(0, 0.15, 0), helm, head)
			for gx in 4:
				_box(Vector3(0.05, 0.2, 0.04), Vector3(-0.15 + gx * 0.1, 0.13, 0.23), light, head)
		"dome":
			var dm := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.22
			sph.height = 0.4
			dm.mesh = sph
			dm.material_override = helm
			dm.position = Vector3(0, 0.18, 0)
			head.add_child(dm)
			_box(Vector3(0.36, 0.07, 0.06), Vector3(0, 0.18, 0.2), light, head)                       # eye slit
		_:
			_box(Vector3(0.36, 0.34, 0.4), Vector3(0, 0.17, 0), helm, head)
			_box(Vector3(0.38, 0.08, 0.06), Vector3(0, 0.2, 0.2), light, head)                         # visor
	if "big_crest" in ex:
		_box(Vector3(0.08, 0.26, 0.44), Vector3(0, 0.44, -0.02), light, head)
	elif String(st["head"]) != "block":
		_box(Vector3(0.06, 0.16, 0.36), Vector3(0, 0.39, -0.02), light, head)                      # crest
	if "horns" in ex:
		for hx: float in [-1.0, 1.0]:
			var hn := _box(Vector3(0.08, 0.3, 0.08), Vector3(hx * 0.27, 0.35, 0.02), light, head)
			hn.rotation.z = -hx * 0.6
	if "antenna" in ex or "antennas" in ex:
		for ax: float in ([0.12] if "antenna" in ex else [-0.12, 0.12]):
			_box(Vector3(0.025, 0.36, 0.025), Vector3(ax, 0.52, -0.08), frame, head)
			_box(Vector3(0.07, 0.07, 0.07), Vector3(ax, 0.72, -0.08), _glow(YELLOW, 3.0), head)       # sensor tip
	if "monocle" in ex:
		_box(Vector3(0.12, 0.12, 0.05), Vector3(0.1, 0.22, 0.23), _glow(YELLOW, 3.0), head)            # the passer's targeting eye
	# legs[0] and arms[0] are on his right (-x when he faces +z)
	var nodes := {"head": head, "rarm": arms[0], "larm": arms[1], "rleg": legs[0], "lleg": legs[1]}
	var band_col := {"Mk II": Color(0.75, 0.82, 0.9), "Mk III": Color(1.0, 0.8, 0.25), "Prototype": Color(0.75, 0.4, 1.0)}
	for k in parts:
		var pt: Dictionary = parts[k]
		var n: Node3D = nodes.get(k, null)
		var tier := String(pt.get("tier", "Stock"))
		if float(pt.get("hp", 100)) <= 0.0:
			if n != null:
				n.visible = false          # gone: the pivot stays so the poses still work
		elif tier == "Junk" and n != null:
			for c in n.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = _metal(Color(0.42, 0.27, 0.16))   # rusty spare
		elif band_col.has(tier):
			# an upgraded part wears a glowing band: silver Mk II, gold Mk III, violet Prototype
			var bm := _glow(band_col[tier], 2.2)
			match k:
				"head":
					_box(Vector3(0.42, 0.05, 0.46), Vector3(0, 0.04, 0), bm, head)
				"core":
					_box(Vector3(0.66 * w, 0.06, 0.44 * ch + 0.02), Vector3(0, 1.12 + up, 0), bm, body)
				"larm", "rarm":
					_box(Vector3(0.24, 0.06, 0.26), Vector3(0, -0.3 * arm_len, 0), bm, n)
				"lleg", "rleg":
					_box(Vector3(0.28 * w, 0.06, 0.32), Vector3(0, -0.6 * lg, 0), bm, n)
	return {"root": root, "body": body, "legs": legs, "arms": arms, "head": head, "nodes": nodes, "wheels": wheels, "flames": flames}


static func _parts_sig(robot: Dictionary) -> String:
	var out := ""
	var parts: Dictionary = robot.get("parts", {})
	for k in parts:
		var pt: Dictionary = parts[k]
		out += "|" + k + ("x" if float(pt["hp"]) <= 0.0 else String(pt["tier"]).substr(0, 1))
	return out


## Called after each sim step.
func stepped() -> void:
	if sim == null:
		return
	for p in sim.players:
		_prev[p.idx] = _cur.get(p.idx, p.pos)
		_cur[p.idx] = p.pos
	while _seen < sim.actions.size():
		_act_out(sim.actions[_seen])
		_seen += 1


func _process(delta: float) -> void:
	_t += delta
	var breathe := 1.0 + 0.35 * sin(_t * 2.2)
	for m in _pulse:
		(m as StandardMaterial3D).emission_energy_multiplier = breathe
	_tick_fx(delta)
	if sim == null:
		return
	for p in sim.players:
		var e: Dictionary = _players.get(p.idx, {})
		if e.is_empty():
			continue
		var a: Vector2 = _prev.get(p.idx, p.pos)
		var b: Vector2 = _cur.get(p.idx, p.pos)
		var pos := a.lerp(b, clampf(alpha, 0.0, 1.0))
		var root: Node3D = e["root"]
		if not _celeb.is_empty():
			_celebrate_one(p, e, delta)
			continue
		root.position = world(pos)
		var f: Vector2 = p.face
		if p.vel.length() > 0.4:
			f = p.vel.normalized()
		var fw := world(pos + f) - world(pos)
		if fw.length() > 0.01:
			root.rotation.y = atan2(fw.x, fw.z)
		var sp: float = p.vel.length()
		e["stride"] = float(e["stride"]) + delta * sp * 1.6
		var swing := sin(float(e["stride"])) * clampf(sp / 6.0, 0.0, 1.0) * 0.7
		_pose(p, e, swing, delta)
		_gear(p, e, sp, delta)
		var lab: Label3D = e["label"]
		lab.modulate = YELLOW if p == sim.carrier else NEON[p.team].lightened(0.4)
	# the ball
	var bp := sim.ball_pos
	var h := sim.ball_h
	if sim.ball_state == "held" and sim.carrier != null:
		var a2: Vector2 = _prev.get(sim.carrier.idx, sim.carrier.pos)
		var b2: Vector2 = _cur.get(sim.carrier.idx, sim.carrier.pos)
		bp = a2.lerp(b2, clampf(alpha, 0.0, 1.0)) + sim.carrier.face * 0.4
		h = 1.25 if not sim.carrier.down else 0.25
	_ball.position = world(bp, h)
	if not _ball_fx.is_empty() and sim.ball_state != "held" and sim.ball_state != "air" and sim.ball_state != "bounce" and sim.ball_state != "tip":
		_ball.position = _ball_fx_pos()
		_ball.rotation.x += delta * 9.0
	if sim.ball_state == "air":
		_ball.rotation.y += delta * 12.0
	elif sim.ball_state == "tip":
		_ball.rotation.x += delta * 14.0
		_ball.rotation.z += delta * 9.0
	elif sim.ball_state == "bounce":
		# end over end and wobbling, faster the faster it goes
		var spin := sim.ball_vel.length()
		_ball.rotation.x += delta * spin * 1.4
		_ball.rotation.z += delta * spin * 0.5 * sin(_t * 7.0)


## A spot for the camera to watch: the ball, mostly.
func focus() -> Vector3:
	if sim == null:
		return world(Vector2(0, 0))
	return _ball.position * Vector3(1, 0, 1)


## ---- the action ------------------------------------------------------------------------------

const POPUP := {
	"miss": ["BROKEN TACKLE!", Color(1.0, 0.85, 0.2)], "dive_miss": ["SLIPS IT!", Color(1.0, 0.85, 0.2)],
	"big_hit": ["BIG HIT!", Color(1.0, 0.35, 0.3)], "sack": ["SACK!", Color(1.0, 0.35, 0.3)],
	"dive_tackle": ["DIVING STOP!", Color(0.4, 0.95, 1.0)], "juke": ["JUKE!", Color(1.0, 0.85, 0.2)],
	"stiff_arm": ["STIFF ARM!", Color(1.0, 0.85, 0.2)], "catch": ["CATCH!", Color(0.4, 0.95, 1.0)],
	"drop": ["DROPPED!", Color(1.0, 0.4, 0.8)], "pbu": ["BROKEN UP!", Color(1.0, 0.4, 0.8)],
	"int": ["PICKED OFF!", Color(1.0, 0.35, 0.3)], "fumble": ["FUMBLE!", Color(1.0, 0.35, 0.3)],
	"recover": ["RECOVERED!", Color(0.4, 0.95, 1.0)], "pancake": ["PANCAKE!", Color(1.0, 0.85, 0.2)],
	"head": ["HEAD OFF!", Color(1.0, 0.3, 0.3)], "core": ["POWERED DOWN!", Color(1.0, 0.3, 0.3)],
	"larm": ["ARM OFF!", Color(1.0, 0.3, 0.3)], "rarm": ["ARM OFF!", Color(1.0, 0.3, 0.3)],
	"lleg": ["LEG OFF!", Color(1.0, 0.3, 0.3)], "rleg": ["LEG OFF!", Color(1.0, 0.3, 0.3)],
}

## What the robots say to each other, by what just happened.
const TRASH := {
	"tackler": ["Sit down, toaster.", "Error 404: yards not found.", "Reboot and try again.", "You run like dial-up.",
		"Welcome to the scrap yard.", "Nice try, tin can.", "Stay down, bolt bucket.", "I eat microwaves for breakfast.",
		"Your servos are trash.", "Return to sender."],
	"hitter": ["DING DING! Lights out!", "That's a factory reset!", "Scrap metal. SCRAP. METAL.", "Uninstall yourself.",
		"Call the repair shop!", "Hope you got a warranty.", "Who ordered the crunch?", "Your firmware just cried."],
	"sacker": ["Pocket's closed, pal.", "Get used to the turf.", "I live in your backfield.", "Say hi to the grass, QB."],
	"runner": ["Too slow, Roomba!", "Catch me? Catch a virus.", "Ankle software crashed?", "Bye-bye, buffering boy.",
		"You tackle like a printer.", "Was that a tackle? Cute.", "Leg day, every day."],
	"catcher": ["Mine. All mine.", "Hands like magnets.", "Catch THAT on your hard drive.", "Too easy, scrap heap."],
	"swatter": ["Not in my house!", "Get that weak junk outta here!", "Denied. Access DENIED.", "Swat-ware update installed."],
	"mocker": ["Butterfingers!", "Hands made of rust?", "Grease your grabbers, genius.", "Who coded your hands?"],
	"picker": ["Thanks for the gift!", "Your QB works for us now.", "Interception subroutine: ONLINE.", "Throw it again. Please."],
	"scorer": ["TOUCHDOWN, TIN CANS!", "Put it on the scoreboard!", "Too easy. Too, too easy.", "Six points. Zero effort."],
}

const DUR := {"dive": 1.7, "wrap": 1.3, "fall_back": 99.0, "fall_fwd": 99.0, "stumble": 0.6, "shrug": 0.5,
	"juke": 0.4, "stiff": 0.55, "throw": 0.5, "give": 0.45, "take": 0.5, "reach": 0.55, "swat": 0.55, "spike": 1.4}


func _who(i: int) -> PlaySim.P:
	if sim == null or i < 0 or i >= sim.players.size():
		return null
	return sim.players[i]


func _yaw_to(a: PlaySim.P, b: PlaySim.P) -> float:
	var d := world(_cur.get(b.idx, b.pos)) - world(_cur.get(a.idx, a.pos))
	if Vector2(d.x, d.z).length() < 0.01:
		return (_players[a.idx]["root"] as Node3D).rotation.y
	return atan2(d.x, d.z)


func _anim(p: PlaySim.P, kind: String, yaw := INF) -> void:
	if p == null or not _players.has(p.idx):
		return
	var e: Dictionary = _players[p.idx]
	e["anim"] = kind
	e["anim_t"] = _t
	e["anim_yaw"] = yaw


## One moment from the sim, acted out on the field.
func _act_out(a: Dictionary) -> void:
	var k := String(a["kind"])
	var pa := _who(int(a["a"]))
	var pb := _who(int(a["b"]))
	match k:
		"tackle", "big_hit", "sack", "dive_tackle":
			if pa != null and pb != null:
				var y := _yaw_to(pa, pb)
				_anim(pa, "dive" if k == "dive_tackle" or k == "sack" else "wrap", y)
				# a big hit knocks him back the way the tackler was going; otherwise he falls forward
				_anim(pb, "fall_back" if k == "big_hit" else "fall_fwd", y + PI if k == "big_hit" else INF)
				_sparks(world(pb.pos, 1.3), 7 if k == "tackle" else 16, Color(1.0, 0.75, 0.3))
				if k != "tackle":
					_popup(k, pb)
				_trash("sacker" if k == "sack" else ("hitter" if k == "big_hit" else "tackler"), pa, 0.45 if k == "tackle" or k == "dive_tackle" else 1.0)
		"miss", "dive_miss":
			if pa != null:
				_anim(pa, "dive" if k == "dive_miss" else "stumble", _yaw_to(pa, pb) if pb != null else INF)
			if pb != null:
				_anim(pb, "shrug")
				_sparks(world(pb.pos, 1.2), 5, Color(0.8, 0.9, 1.0))
				_popup(k, pb)
				_trash("runner", pb, 0.4)
		"juke":
			_anim(pa, "juke")
			_popup(k, pa)
		"stiff_arm":
			_anim(pa, "stiff", _yaw_to(pa, pb) if pb != null else INF)
			if pb != null:
				_anim(pb, "stumble")
				_sparks(world(pb.pos, 1.6), 4, Color(0.8, 0.9, 1.0))
			_popup(k, pa)
		"throw":
			_anim(pa, "throw")
		"handoff":
			_anim(pa, "give")
			_anim(pb, "take")
		"catch":
			_anim(pa, "reach")
			_popup(k, pa)
			_trash("catcher", pa, 0.25)
		"int":
			_anim(pa, "reach")
			_popup(k, pa)
			_trash("picker", pa, 1.0)
		"pbu":
			_anim(pa, "swat")
			_popup(k, pa)
			_trash("swatter", pa, 0.7)
			_bounce(_ball.position, 1.4)
		"drop":
			_anim(pa, "reach")
			_popup(k, pa)
			_bounce(_ball.position, 1.0)
			# the nearest defender lets him hear about it
			var best: PlaySim.P = null
			if pa != null:
				for q in sim.players:
					if q.side != pa.side and (best == null or q.pos.distance_to(pa.pos) < best.pos.distance_to(pa.pos)):
						best = q
			_trash("mocker", best, 0.8)
		"incomplete":
			if _ball_fx.is_empty():
				_bounce(world(a["pos"], 0.6), 0.9)
		"fumble":
			if pa != null:
				_anim(pa, "fall_back", _yaw_to(pa, pb) if pb != null else INF)
				_popup(k, pa)
				_sparks(world(pa.pos, 1.2), 12, Color(1.0, 0.75, 0.3))
				_ball_fx = {"p0": world(pa.pos, 1.2), "p1": world(sim.ball_pos, 0.15), "t0": _t, "hop": 2.2}
		"recover":
			_anim(pa, "dive")
			_popup(k, pa)
			_ball_fx = {}
		"part_off":
			if pa != null:
				_part_off(pa, String(a.get("part", "")), pb)
		"pancake":
			if pb != null:
				_anim(pb, "fall_back", _yaw_to(pb, pa) if pa != null else INF)
				_popup(k, pb)
				_sparks(world(pb.pos, 1.0), 6, Color(1.0, 0.75, 0.3))
	moment.emit(a)


## The scorer celebrates (called when a play ends in a touchdown).
func touchdown(p: PlaySim.P) -> void:
	_anim(p, "spike")
	_trash("scorer", p, 1.0)
	_sparks(world(p.pos, 2.5), 24, Color(1.0, 0.85, 0.2))


func _bounce(from: Vector3, hop: float) -> void:
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.5, 3.5)
	_ball_fx = {"p0": from, "p1": Vector3(from.x, 0.15, from.z) + dir, "t0": _t, "hop": hop}


## A ball that flies to p1 and bounces twice more, lower each time.
func _ball_fx_pos() -> Vector3:
	var p0: Vector3 = _ball_fx["p0"]
	var p1: Vector3 = _ball_fx["p1"]
	var hop: float = _ball_fx["hop"]
	var u := (_t - float(_ball_fx["t0"])) / 0.55
	var flat := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	var segs := [[0.0, 1.0, 1.0], [1.0, 1.55, 0.35], [1.55, 1.85, 0.12]]
	for sg: Array in segs:
		if u < float(sg[1]):
			var f := (u - float(sg[0])) / (float(sg[1]) - float(sg[0]))
			var along := p0 + flat * minf(u, 1.0) + flat * 0.4 * maxf(u - 1.0, 0.0)
			var base_h := lerpf(p0.y, p1.y, f) if float(sg[0]) == 0.0 else p1.y
			return Vector3(along.x, base_h + hop * float(sg[2]) * 4.0 * f * (1.0 - f), along.z)
	var end := p0 + flat * 1.34
	return Vector3(end.x, p1.y, end.z)


func _popup(kind: String, p: PlaySim.P) -> void:
	if p == null or not POPUP.has(kind):
		return
	var lab := Label3D.new()
	lab.text = POPUP[kind][0]
	lab.font_size = 96
	lab.pixel_size = 0.017
	lab.outline_size = 22
	lab.modulate = POPUP[kind][1]
	lab.outline_modulate = Color(0.1, 0.0, 0.15)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.render_priority = 5
	# stack over any popup still rising
	var h := 3.6
	for n in _fx_nodes:
		if n["kind"] == "popup" and _t - float(n["t0"]) < 0.8:
			h = maxf(h, float(n["y0"]) + 1.9)
	lab.position = world(_cur.get(p.idx, p.pos), h)
	add_child(lab)
	_fx_nodes.append({"node": lab, "t0": _t, "life": 1.4, "kind": "popup", "y0": h})


func _trash(who: String, p: PlaySim.P, chance: float) -> void:
	if not talk or p == null or randf() > chance:
		return
	for n in _fx_nodes:
		if n["kind"] == "talk":
			return   # one talker at a time is plenty
	var lines: Array = TRASH[who]
	var line: String = lines[randi() % lines.size()]
	if randf() < 0.4:
		line = babble()   # sometimes the circuits just say whatever comes out
	_say_line(p, line)


func _say_line(p: PlaySim.P, line: String) -> void:
	var lab := Label3D.new()
	lab.text = "\"%s\"" % line
	lab.font_size = 60
	lab.pixel_size = 0.015
	lab.outline_size = 16
	lab.modulate = Color(1, 1, 1)
	lab.outline_modulate = (NEON[p.team] as Color).darkened(0.6)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.render_priority = 4
	lab.width = 900
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.position = world(_cur.get(p.idx, p.pos), 4.6)
	lab.visible = false
	add_child(lab)
	_fx_nodes.append({"node": lab, "t0": _t + 0.4, "life": 2.6, "kind": "talk", "y0": 4.6, "who": p.idx})
	trash_talk.emit(p.team, p.slot, line, String(p.robot.get("name", "")))


func _sparks(at: Vector3, n: int, c: Color) -> void:
	if not _spark_mat.has(c):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 4.0
		_spark_mat[c] = m
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.1)
		mi.mesh = bm
		mi.material_override = _spark_mat[c]
		mi.position = at
		add_child(mi)
		var v := Vector3(randf_range(-1, 1), randf_range(0.4, 1.6), randf_range(-1, 1)).normalized() * randf_range(3.0, 7.5)
		_fx_nodes.append({"node": mi, "t0": _t, "life": randf_range(0.35, 0.65), "kind": "spark", "vel": v})
	var fl := OmniLight3D.new()
	fl.light_color = c
	fl.light_energy = 3.0
	fl.omni_range = 5.0
	fl.position = at
	add_child(fl)
	_fx_nodes.append({"node": fl, "t0": _t, "life": 0.25, "kind": "flash"})


var _tears_now := 0


func _tick_fx(delta: float) -> void:
	var keep: Array = []
	_tears_now = 0
	for n0 in _fx_nodes:
		if n0["kind"] == "tear":
			_tears_now += 1
	for n: Dictionary in _fx_nodes:
		var node: Node3D = n["node"]
		var age := _t - float(n["t0"])
		var life: float = n["life"]
		if age > life:
			node.queue_free()
			continue
		keep.append(n)
		if age < 0.0:
			continue
		var u := age / life
		match String(n["kind"]):
			"popup":
				var lab := node as Label3D
				lab.position.y = float(n["y0"]) + 1.6 * u
				lab.scale = Vector3.ONE * (1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.15))
				lab.modulate.a = 1.0 if u < 0.6 else 1.0 - (u - 0.6) / 0.4
				lab.outline_modulate.a = lab.modulate.a
			"talk":
				var lab := node as Label3D
				lab.visible = true
				var p := _who(int(n["who"]))
				if p != null:
					var at := world(_cur.get(p.idx, p.pos))
					lab.position = Vector3(at.x, float(n["y0"]) + 0.3 * u, at.z)
				lab.modulate.a = 1.0 if u < 0.8 else 1.0 - (u - 0.8) / 0.2
				lab.outline_modulate.a = lab.modulate.a
			"tear":
				var v: Vector3 = n["vel"]
				v.y -= 14.0 * delta
				n["vel"] = v
				node.position += v * delta
				if node.position.y < 0.05:
					node.position.y = 0.05
					node.scale = Vector3(1.8, 0.2, 1.8)   # a little puddle
			"spark":
				var v: Vector3 = n["vel"]
				v.y -= 18.0 * delta
				n["vel"] = v
				node.position += v * delta
				node.scale = Vector3.ONE * maxf(1.0 - u, 0.01)
			"flash":
				(node as OmniLight3D).light_energy = 3.0 * (1.0 - u)
			"ring":
				node.scale = Vector3.ONE * (1.0 + 5.0 * u)
				node.visible = u < 0.95
			"debris":
				var v: Vector3 = n["vel"]
				if node.position.y > 0.12 or v.y > 0.0:
					v.y -= 20.0 * delta
					node.position += v * delta
					node.rotation += (n["spin"] as Vector3) * delta
					if node.position.y < 0.12 and v.y < 0.0:
						node.position.y = 0.12
						v = Vector3(v.x * 0.5, -v.y * 0.35, v.z * 0.5)   # bounce
						n["spin"] = (n["spin"] as Vector3) * 0.5
						if v.y < 1.0:
							v = Vector3.ZERO
					n["vel"] = v
	_fx_nodes = keep


## Pose a robot for this frame: the running stride, the arms, and whatever he is acting out.
func _pose(p: PlaySim.P, e: Dictionary, swing: float, delta: float) -> void:
	var root: Node3D = e["root"]
	var pitch := 1.45 if p.down else 0.0
	var roll := 0.0
	var hop := 0.0
	var lunge := 0.0
	var arm := [-swing * 0.8, swing * 0.8]
	if sim != null and p == sim.carrier and not p.down:
		arm[0] = -0.9   # ball tucked
	var leg_kick := 0.0
	var kind := String(e["anim"])
	var age := _t - float(e["anim_t"])
	var yaw: float = e["anim_yaw"]
	if kind != "" and (age > float(DUR.get(kind, 0.0)) or (kind.begins_with("fall") and age > 0.6 and not p.down)):
		kind = ""
		e["anim"] = ""
		e["fall_yaw"] = INF
	var rate := 14.0
	match kind:
		"dive":
			var u := clampf(age / 0.22, 0.0, 1.0)
			pitch = 1.4 * u
			lunge = 0.8 * u
			hop = sin(clampf(age / 0.3, 0.0, 1.0) * PI) * 0.35
			arm = [-1.9, -1.9]
			leg_kick = 0.5
			rate = 30.0
		"wrap":
			pitch = 0.75 if age < 0.4 else 1.1
			lunge = 0.4
			arm = [-1.5, -1.5]
			rate = 22.0
		"fall_back":
			pitch = -1.45
			arm = [-2.4, -2.2]
			rate = 16.0 if age < 0.4 else 8.0
		"fall_fwd":
			pitch = 1.45
			arm = [-1.6, -1.2]
			rate = 10.0
		"stumble":
			var f := 1.0 - age / 0.6
			roll = sin(age * 26.0) * 0.4 * f
			pitch = 0.35 * f
			arm = [-1.2 + sin(age * 20.0), -1.2 - sin(age * 20.0)]
			rate = 30.0
		"shrug":
			var f := 1.0 - age / 0.5
			roll = sin(age * 22.0) * 0.3 * f
			hop = 0.15 * f
			rate = 30.0
		"juke":
			var u := age / 0.4
			hop = sin(u * PI) * 0.45
			roll = sin(u * TAU) * 0.55
			rate = 30.0
		"stiff":
			arm[1] = -1.65
			pitch = -0.12
			rate = 30.0
		"throw":
			var u := clampf(age / 0.32, 0.0, 1.0)
			arm[1] = lerpf(-3.6, -1.1, u * u)
			arm[0] = -1.0
			pitch = 0.25 * u
			rate = 40.0
		"give":
			arm = [-1.3, -1.3]
		"take":
			arm = [-1.0, -0.9]
		"reach":
			arm = [-2.95, -2.95]
			hop = sin(clampf(age / 0.45, 0.0, 1.0) * PI) * 0.4
			rate = 24.0
		"swat":
			arm = [-1.0, -3.1]
			hop = sin(clampf(age / 0.45, 0.0, 1.0) * PI) * 0.5
			rate = 30.0
		"spike":
			# arms up, a little jump for joy
			var j := fmod(age, 0.45) / 0.45
			arm = [-3.0, -3.0]
			hop = sin(j * PI) * 0.5
			pitch = 0.0
			rate = 24.0
	if kind.begins_with("fall") and float(e["fall_yaw"]) == INF:
		e["fall_yaw"] = yaw if yaw != INF else root.rotation.y
	if kind.begins_with("fall"):
		yaw = float(e["fall_yaw"])
	if kind != "" and yaw != INF:
		root.rotation.y = yaw
	elif p.down and float(e["fall_yaw"]) != INF:
		root.rotation.y = float(e["fall_yaw"])
	var k := minf(delta * rate, 1.0)
	e["tilt"] = lerpf(float(e["tilt"]), pitch, k)
	e["roll"] = lerpf(float(e["roll"]), roll, k)
	e["hop"] = lerpf(float(e["hop"]), hop, k)
	e["lunge"] = lerpf(float(e["lunge"]), lunge, k)
	var cur_arm: Array = e["arm"]
	cur_arm[0] = lerpf(float(cur_arm[0]), float(arm[0]), k)
	cur_arm[1] = lerpf(float(cur_arm[1]), float(arm[1]), k)
	root.rotation.x = float(e["tilt"])
	root.rotation.z = float(e["roll"])
	(e["body"] as Node3D).position = Vector3(0, float(e["hop"]), float(e["lunge"]))
	var arms: Array = e["arms"]
	(arms[0] as Node3D).rotation.x = float(cur_arm[0])
	(arms[1] as Node3D).rotation.x = float(cur_arm[1])
	var legs: Array = e["legs"]
	(legs[0] as Node3D).rotation.x = swing + leg_kick
	(legs[1] as Node3D).rotation.x = -swing + leg_kick



## ---- robot babble: nonsense sentences out of random words --------------------------------------

const BAB_ADJ := ["rusty", "turbo", "quantum", "greasy", "binary", "chrome", "soggy", "electric", "wobbly",
	"magnetic", "crunchy", "glitchy", "nuclear", "squeaky", "hydraulic", "moist", "laser", "obsolete", "fuzzy", "titanium"]
const BAB_NOUN := ["toaster", "sprocket", "firmware", "gravy", "capacitor", "hubcap", "waffle iron", "flux valve",
	"cheese grater", "motherboard", "lug nut", "spatula", "dial tone", "carburetor", "teapot", "gearbox",
	"floppy disk", "pancake", "fax machine", "bolt", "sandwich", "transistor", "vacuum", "doorknob"]
const BAB_VERB := ["defragment", "lubricate", "microwave", "reboot", "calibrate", "vaporize", "sprinkle",
	"download", "polish", "compress", "magnetize", "unscrew", "toast", "overclock", "recycle", "buffer"]
const BAB_EXCL := ["BEEP BOOP", "ERROR", "WHIRRR", "BZZT", "AFFIRMATIVE", "CLANK", "DING", "KZZZT", "BLORP", "SYSTEM OK"]
const BAB_FORMS := [
	"{E}! I will {v} your {a} {n}!",
	"My {n} is {a} and your {n2} is {a2}.",
	"{E}. {V} the {n}. {V2} the {n2}.",
	"You smell like a {a} {n}.",
	"Error: {a} {n} not found. {E}.",
	"Mother always said: never {v} a {a} {n}.",
	"I am {pct} percent {n}.",
	"Warning: {pct} {ns} detected in the {a} zone.",
	"{E}. Please insert {pct} {ns}.",
	"Do not {v} me, you {a} {n}!",
	"{E}! {E2}! Who left this {n} in my {n2}?",
	"Today I {v} the {n}. Tomorrow, the {a} {n2}.",
	"Initiating {a} {n} protocol.",
	"Your {n} has been {v}ed. {E}.",
]


static func babble() -> String:
	var f: String = BAB_FORMS[randi() % BAB_FORMS.size()]
	var pick := func(a: Array) -> String: return a[randi() % a.size()]
	var v: String = pick.call(BAB_VERB)
	var v2: String = pick.call(BAB_VERB)
	f = f.replace("{E2}", pick.call(BAB_EXCL)).replace("{E}", pick.call(BAB_EXCL))
	f = f.replace("{V2}", v2.capitalize()).replace("{V}", v.capitalize())
	f = f.replace("{v}ed", (v.trim_suffix("e") + "ed")).replace("{v}", v)
	f = f.replace("{a2}", pick.call(BAB_ADJ)).replace("{a}", pick.call(BAB_ADJ))
	f = f.replace("{n2}", pick.call(BAB_NOUN)).replace("{n}", pick.call(BAB_NOUN))
	f = f.replace("{pct}", str(randi_range(3, 99)))
	var pl: String = pick.call(BAB_NOUN)
	if pl.ends_with("x") or pl.ends_with("s") or pl.ends_with("ch") or pl.ends_with("sh"):
		pl += "es"
	elif pl.ends_with("y") and not pl.ends_with("ey"):
		pl = pl.trim_suffix("y") + "ies"
	else:
		pl += "s"
	f = f.replace("{ns}", pl)
	return f


## A random robot on the field says something that makes no sense (unless someone else is talking).
func babble_now() -> void:
	if sim == null or not talk:
		return
	for n in _fx_nodes:
		if n["kind"] == "talk":
			return
	var p: PlaySim.P = sim.players[randi() % sim.players.size()]
	_say_line(p, babble())



## ---- the touchdown dance (and the other side crying) ---------------------------------------------

const DANCES := ["robot", "spin", "pump", "floss", "jump", "sprinkler"]
const SOBS := ["WAAAH!", "*sad beeping*", "Not again...", "My circuits hurt.", "Boo hoo hoo.", "I want my mom(board).",
	"Leaking coolant from my eyes.", "This is so unfair!", "*sniff* *bzzt*"]


## The team that scored runs to the scorer in the end zone and dances; the other team cries.
func celebrate(team: int, spot: Vector2) -> void:
	if sim == null:
		return
	var pos := {}
	for p in sim.players:
		pos[p.idx] = _cur.get(p.idx, p.pos)
		var e: Dictionary = _players.get(p.idx, {})
		if not e.is_empty():
			e["anim"] = ""
	_celeb = {"team": team, "spot": spot, "t0": _t, "pos": pos, "next_tear": 0.0}
	_sparks(world(spot, 2.5), 28, Color(1.0, 0.85, 0.2))
	moment.emit({"kind": "celebrate", "a": -1, "b": -1, "t": sim.t, "pos": spot})
	# one of the losers says how he feels
	var losers: Array = []
	for p in sim.players:
		if p.team != team:
			losers.append(p)
	if not losers.is_empty() and talk:
		_say_line(losers[randi() % losers.size()], SOBS[randi() % SOBS.size()])


func _celebrate_one(p: PlaySim.P, e: Dictionary, delta: float) -> void:
	var root: Node3D = e["root"]
	var age := _t - float(_celeb["t0"])
	var cur: Vector2 = _celeb["pos"][p.idx]
	var spot: Vector2 = _celeb["spot"]
	var arm := [0.0, 0.0]
	var pitch := 0.0
	var roll := 0.0
	var hop := 0.0
	var legs := [0.0, 0.0]
	var yaw := root.rotation.y
	if p.team == int(_celeb["team"]):
		# gather round the scorer, then dance
		var ring: int = p.idx % 11
		var target := spot
		if p != sim.carrier:
			var ang := TAU * float(ring) / 11.0
			target = spot + Vector2(cos(ang), sin(ang)) * (2.2 + 0.6 * float(ring % 3))
		var to := target - cur
		var moving := to.length() > 0.3
		if moving:
			cur += to.normalized() * minf(to.length(), maxf(8.0, to.length() * 2.2) * delta)
			_celeb["pos"][p.idx] = cur
			var fw := world(cur + to.normalized()) - world(cur)
			yaw = atan2(fw.x, fw.z)
			e["stride"] = float(e["stride"]) + delta * 11.0
			var sw := sin(float(e["stride"])) * 0.7
			legs = [sw, -sw]
			arm = [-sw * 0.8, sw * 0.8]
		else:
			var ph := age * TAU * 1.6 + float(p.idx)
			match DANCES[p.idx % DANCES.size()] if p != sim.carrier else "spike":
				"robot":
					var step := floorf(age * 3.2)
					arm = [-1.57 + 0.6 * fmod(step, 2.0), -1.57 - 0.6 * fmod(step + 1.0, 2.0)]
					yaw += (0.6 if fmod(step, 4.0) < 2.0 else -0.6) * delta * 4.0
					hop = 0.08 * fmod(step, 2.0)
				"spin":
					yaw += delta * 9.0
					arm = [-1.6, -1.6]
					hop = absf(sin(ph)) * 0.2
				"pump":
					arm = [-3.0 + 0.5 * sin(ph * 2.0), -3.0 - 0.5 * sin(ph * 2.0)]
					hop = absf(sin(ph)) * 0.35
				"floss":
					roll = sin(ph) * 0.35
					arm = [-0.4 + 0.9 * sin(ph), -0.4 - 0.9 * sin(ph)]
				"jump":
					hop = absf(sin(ph * 0.8)) * 0.8
					arm = [-2.9, -2.9]
					legs = [0.4 * absf(sin(ph * 0.8)), -0.4 * absf(sin(ph * 0.8))]
				"sprinkler":
					arm = [-1.6, -2.6]
					yaw += (sin(ph * 0.5) * 2.2) * delta
					legs = [0.3 * sin(ph), 0.3 * sin(ph)]
				"spike":
					var j := fmod(age, 0.5) / 0.5
					hop = sin(j * PI) * 0.6
					arm = [-3.0, -3.0]
					yaw += delta * 2.0
	else:
		# heads down, hands to the face, shoulders shaking; some go to a knee
		var sob := sin(age * 28.0 + float(p.idx))
		pitch = 0.35 + 0.04 * sob
		roll = 0.05 * sob
		arm = [-2.45 + 0.08 * sob, -2.45 - 0.08 * sob]
		if p.idx % 3 == 0:
			hop = -0.35
			legs = [-1.2, 0.2]
	root.position = world(cur)
	root.rotation.y = yaw
	var k := minf(delta * 16.0, 1.0)
	e["tilt"] = lerpf(float(e["tilt"]), pitch, k)
	e["roll"] = lerpf(float(e["roll"]), roll, k)
	e["hop"] = lerpf(float(e["hop"]), hop, k)
	var ca: Array = e["arm"]
	ca[0] = lerpf(float(ca[0]), float(arm[0]), k)
	ca[1] = lerpf(float(ca[1]), float(arm[1]), k)
	root.rotation.x = float(e["tilt"])
	root.rotation.z = float(e["roll"])
	(e["body"] as Node3D).position = Vector3(0, float(e["hop"]), 0)
	(e["arms"][0] as Node3D).rotation.x = float(ca[0])
	(e["arms"][1] as Node3D).rotation.x = float(ca[1])
	(e["legs"][0] as Node3D).rotation.x = float(legs[0])
	(e["legs"][1] as Node3D).rotation.x = float(legs[1])
	_gear(p, e, 0.0, delta)
	# tears: streams of blue drops from both eyes of every crier
	if p.team != int(_celeb["team"]) and randf() < delta * 9.0:
		var eye_h := (1.95 + float(e["hop"])) - 0.25 * float(e["tilt"])
		_tear(world(cur, eye_h), yaw)


func _tear(at: Vector3, yaw: float) -> void:
	var c := Color(0.35, 0.7, 1.0)
	if not _spark_mat.has(c):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 3.0
		_spark_mat[c] = m
	if _tears_now > 160:
		return                       # enough tears on the field already
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.13, 0.2, 0.13)
	mi.mesh = bm
	mi.material_override = _spark_mat[c]
	var side := 0.1 if randf() < 0.5 else -0.1
	mi.position = at + Vector3(sin(yaw) * 0.25 + cos(yaw) * side, 0, cos(yaw) * 0.25 - sin(yaw) * side)
	add_child(mi)
	var v := Vector3(sin(yaw), 0, cos(yaw)) * 1.4 + Vector3(cos(yaw) * side * 6.0, 1.8, -sin(yaw) * side * 6.0)
	_fx_nodes.append({"node": mi, "t0": _t, "life": 0.9, "kind": "tear", "vel": v})



## ---- parts coming off ----------------------------------------------------------------------------

## The part leaves him: a copy flies off spinning and bounces on the turf (it lies there till
## the next snap), the real one is hidden, sparks and a popup.
func _part_off(p: PlaySim.P, part: String, by: PlaySim.P) -> void:
	var e: Dictionary = _players.get(p.idx, {})
	if e.is_empty():
		return
	var at := world(_cur.get(p.idx, p.pos), 1.6)
	_sparks(at, 22, Color(1.0, 0.6, 0.2))
	_popup(part, p)
	if part == "core":
		_anim(p, "fall_back", INF)
		return
	var n: Node3D = (e["nodes"] as Dictionary).get(part, null)
	if n == null or not n.visible:
		return
	var piece := n.duplicate() as Node3D
	var xf := n.global_transform
	add_child(piece)
	piece.global_transform = xf
	n.visible = false
	# the part keeps its own colours - red for Red, blue for Blue - with a small orange ember where
	# it tore off, so you can see whose it was and where it lies for the rest of the game
	var ember := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.09
	em.height = 0.18
	ember.mesh = em
	ember.material_override = _glow(Color(1.0, 0.45, 0.1), 2.4)
	piece.add_child(ember)
	_ring(world(_cur.get(p.idx, p.pos), 0.06))
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	if by != null:
		var away := world(_cur.get(p.idx, p.pos)) - world(_cur.get(by.idx, by.pos))
		if away.length() > 0.1:
			dir = (away.normalized() + dir * 0.5).normalized()
	var v := dir * randf_range(4.0, 7.0) + Vector3(0, randf_range(5.0, 8.0), 0)
	var spin := Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	_fx_nodes.append({"node": piece, "t0": _t, "life": 999.0, "kind": "debris", "vel": v, "spin": spin})



## Rollers spin and jets flare with speed; a robot missing a part sparks from the stump.
func _gear(p: PlaySim.P, e: Dictionary, sp: float, delta: float) -> void:
	for w: Node3D in e.get("wheels", []):
		w.rotation.x += sp * delta / 0.15
	for f: Node3D in e.get("flames", []):
		var k := clampf(sp / 8.0, 0.0, 1.3)
		f.visible = k > 0.15
		f.scale = Vector3(0.7 + 0.5 * k, (0.4 + 1.1 * k) * randf_range(0.85, 1.15), 0.7 + 0.5 * k)
	if p.robot.is_empty() or randf() > delta * 14.0:
		return
	var lost := Robot.lost_parts(p.robot)
	if lost.is_empty():
		return
	var k2: String = lost[randi() % lost.size()]
	var n: Node3D = (e.get("nodes", {}) as Dictionary).get(k2, null)
	var at := n.global_position if n != null else (e["body"] as Node3D).global_position + Vector3(0, 1.35, 0)
	_stump_spark(at)


func _stump_spark(at: Vector3) -> void:
	var c := Color(1.0, 0.8, 0.3)
	if not _spark_mat.has(c):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 5.0
		_spark_mat[c] = m
	for i in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 0.06)
		mi.mesh = bm
		mi.material_override = _spark_mat[c]
		mi.position = at
		add_child(mi)
		var v := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized() * randf_range(2.0, 4.5)
		_fx_nodes.append({"node": mi, "t0": _t, "life": randf_range(0.2, 0.4), "kind": "spark", "vel": v})


## A new game: sweep the field of the parts left lying on it.
func clear_debris() -> void:
	var keep: Array = []
	for n in _fx_nodes:
		if n["kind"] == "debris":
			(n["node"] as Node3D).queue_free()
		else:
			keep.append(n)
	_fx_nodes = keep



## A red shock ring that spreads across the turf where a part came off.
func _ring(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.8
	t.outer_radius = 1.0
	mi.mesh = t
	mi.material_override = _glow(Color(1.0, 0.2, 0.2), 3.0)
	mi.position = at
	add_child(mi)
	_fx_nodes.append({"node": mi, "t0": _t, "life": 1.2, "kind": "ring"})
