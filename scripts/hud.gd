class_name Hud
extends CanvasLayer
## Everything on screen that isn't the field, built in code and sized for a phone: the
## scoreboard, the controls, and the panels - teams and brains, the rule editor, the play log,
## a game's box score and a batch of simulated games.

var main: Node
var _root: Control
var _score := [null, null]
var _clock: Label
var _sit: Label
var _call: Label
var _result: Label
var _pause_btn: Button
var _speed_btns := {}
var _view_btn: Button
var _overlay: Control = null
var _toast: Label
var _board: Control
var _board_tw: Tween
var _toast_t := 0.0
var _progress: Label
var _cap_box: PanelContainer
var _cap: RichTextLabel
var _cap_lines: Array = []    # [text, color], newest last
var _cap_t := 0.0
var _board_on := true
var _sound_btn: Button
var fs := 15                 # base font size

# editor state
var _ed_kind := "ai"
var _ed_name := ""
var _ed_text: CodeEdit
var _ed_status: RichTextLabel
var _ed_words_mode := "conditions"
var _ed_names_box: HFlowContainer
var _ed_words_box: HFlowContainer
var _ed_example: Label

## The interface palette: a stadium broadcast look - dark slate panels, stadium-light amber for
## what matters (titles, the selected choice), sky blue for headings, gold for highlights. (The
## names are kept from the first neon palette so nothing else has to change.)
const CYAN := Color(0.62, 0.74, 0.95)       # headings, information
const MAGENTA := Color(0.96, 0.72, 0.18)    # the accent (gold): money, the selected choice, the coach's pick
const YELLOW := Color(1.0, 0.83, 0.42)      # highlights
const INK := Color(0.1, 0.07, 0.0)          # text on the accent
## The broadcast look (v1.207): night-navy surfaces, team red and blue, gold for money and the
## main action, green / amber / red only for condition.
const NIGHT := Color(0.04, 0.055, 0.086)
const SURF1 := Color(0.07, 0.094, 0.137)
const SURF2 := Color(0.102, 0.133, 0.196)
const SURF3 := Color(0.133, 0.173, 0.251)
const LINE := Color(0.165, 0.208, 0.314)
const DIM := Color(0.553, 0.6, 0.678)
const GOOD := Color(0.3, 0.83, 0.48)
const WARN := Color(1.0, 0.69, 0.18)
const BAD := Color(1.0, 0.35, 0.31)
const TEAM_COL := [Color(0.91, 0.28, 0.23), Color(0.25, 0.55, 1.0)]
## The fonts (Barlow and Barlow Condensed, SIL Open Font License - fonts/OFL.txt).
static var BODY: Font = null
static var BODY_B: Font = null
static var DISP: Font = null       # condensed bold italic: titles, scores, banners
static var NUM: Font = null        # condensed bold: big numbers


static func load_fonts() -> void:
	if DISP != null:
		return
	BODY = load("res://fonts/Barlow-Regular.ttf")
	BODY_B = load("res://fonts/Barlow-SemiBold.ttf")
	DISP = load("res://fonts/BarlowCondensed-BoldItalic.ttf")
	NUM = load("res://fonts/BarlowCondensed-Bold.ttf")


## A label in the display face: "TOUCHDOWN", a panel title, a score.
func _disp(text: String, size: int, color := Color(0.94, 0.95, 0.97), italic := true) -> Label:
	var l := _label(text, size, color)
	l.add_theme_font_override("font", DISP if italic else NUM)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## Small spaced capitals over a section ("PLAYERS OF THE GAME").
func _eyebrow(text: String, color := DIM) -> Label:
	var l := _label(text.to_upper(), fs - 2, color)
	l.add_theme_font_override("font", BODY_B)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func flat(bg: Color, radius := 10, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb
const KIND_LABEL := {"coach": "Coaches", "defense": "Defenses", "play": "Plays", "ai": "Position brains"}
const PLAY_HELP := """Assignments, one line per position (OL, WR, DL, LB, CB, S set the whole group):
QB: pass drop 3|5|7 read WR1 WR2 ... · play action drop 7 read ... · handoff · run sneak
RB: run inside left|inside right|middle|outside left|outside right|sweep left|sweep right|draw
    route NAME [depth] · block · block lead
WR/TE: route NAME [depth] · block then route NAME · block
   routes: go fade slant out in dig post corner hitch curl comeback flat seam drag cross wheel screen swing angle stop
OL: block · pull left|right
DL/LB/CB/S: rush · rush contain · blitz · man WR1|WR2|WR3|TE|RB · spy
   zone deep third left|middle|right · deep half left|right · deep middle · flat left|right
        hook left|middle|right · curl left|right · robber
Header: play "Name" · about "..." · side offense|defense · kind pass|run|man|zone|blitz
        formation shotgun|under center|pistol|empty · front even|press|off|goal line"""


## Version and build time, always on top in the top-right corner.
func _build_watermark() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var wm := Label.new()
	wm.text = "%s  ·  %s" % [BuildInfo.VERSION, BuildInfo.BUILT]
	wm.anchor_left = 0.0
	wm.anchor_right = 1.0
	wm.offset_left = 6
	wm.offset_right = -6
	wm.offset_top = 1
	wm.offset_bottom = 16
	wm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wm.add_theme_font_size_override("font_size", 11)
	wm.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	wm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	wm.add_theme_constant_override("outline_size", 3)
	layer.add_child(wm)


func setup(m: Node) -> void:
	main = m
	load_fonts()
	var vp := get_viewport().get_visible_rect().size
	fs = 15 if vp.x > 700 else 14
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_scoreboard()
	_build_controls()
	_build_watermark()
	Ux.start(self)
	CloudSave.start(self)
	_build_banner()
	_build_caption()


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = BODY
	th.default_font_size = fs
	# buttons: rounded tiles with a darker lip underneath, so they look pressable
	var mk := func(bg: Color, lip: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(9)
		sb.border_color = lip
		sb.border_width_bottom = 3
		if border.a > 0.0:
			sb.border_color = border
			sb.set_border_width_all(2)
			sb.border_width_bottom = 3
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		return sb
	th.set_stylebox("normal", "Button", mk.call(SURF3, Color(0.06, 0.08, 0.12)))
	th.set_stylebox("hover", "Button", mk.call(SURF3.lightened(0.08), Color(0.06, 0.08, 0.12)))
	var down: StyleBoxFlat = mk.call(MAGENTA, Color(0.66, 0.48, 0.08))
	th.set_stylebox("pressed", "Button", down)
	th.set_stylebox("hover_pressed", "Button", mk.call(MAGENTA.lightened(0.08), Color(0.66, 0.48, 0.08)))
	th.set_stylebox("disabled", "Button", mk.call(Color(SURF2, 0.9), Color(0.05, 0.06, 0.09)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_font("font", "Button", BODY_B)
	th.set_color("font_color", "Button", Color(0.94, 0.95, 0.97))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_hover_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.49, 0.56))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(SURF1, 0.98)
	panel.border_color = LINE
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(14)
	panel.shadow_color = Color(0, 0, 0, 0.6)
	panel.shadow_size = 16
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "OptionButton", mk.call(SURF3, Color(0.06, 0.08, 0.12)))
	th.set_stylebox("hover", "OptionButton", mk.call(SURF3.lightened(0.08), Color(0.06, 0.08, 0.12)))
	th.set_stylebox("pressed", "OptionButton", mk.call(SURF3, Color(0.06, 0.08, 0.12), MAGENTA))
	th.set_font("font", "OptionButton", BODY_B)
	th.set_color("default_color", "RichTextLabel", Color(0.9, 0.92, 0.95))
	th.set_font("bold_font", "RichTextLabel", BODY_B)
	th.set_font("normal_font", "RichTextLabel", BODY)
	var le := mk.call(NIGHT, LINE, LINE) as StyleBoxFlat
	th.set_stylebox("normal", "LineEdit", le)
	return th


func _label(text: String, size := 0, color := Color(0.93, 0.93, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size if size > 0 else fs)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# pressed: it greys at once (so a tap shows), and comes back if the page didn't change
	b.pressed.connect(func():
		var was_disabled := b.disabled
		if not b.toggle_mode:
			b.disabled = true
		cb.call()
		if is_instance_valid(b) and not b.toggle_mode and not was_disabled:
			b.set_deferred("disabled", false))
	return b


## ---- scoreboard ----------------------------------------------------------------------------

var _abbr := [null, null]
var _poss_dot := [null, null]


## The broadcast scorebug: [RIV][14][Q2 3:12 / 2ND & 6 OWN 31][17][HOG], with the call, the
## result and any progress in a strip under it.
func _build_scoreboard() -> void:
	var top := VBoxContainer.new()
	_board = top
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 18
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	var bug := PanelContainer.new()
	var bsb := flat(Color(0.03, 0.045, 0.07, 0.96), 9)
	bsb.shadow_color = Color(0, 0, 0, 0.55)
	bsb.shadow_size = 10
	bug.add_theme_stylebox_override("panel", bsb)
	bug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bug)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bug.add_child(row)
	var narrow := get_viewport().get_visible_rect().size.x < 520.0
	var h := 46.0 if narrow else 54.0
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", -2)
	_clock = _disp("", fs + 2, Color(0.95, 0.96, 0.98), false)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_clock)
	_sit = _label("", fs - 3, MAGENTA)
	_sit.add_theme_font_override("font", BODY_B)
	_sit.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sit.clip_text = true
	_sit.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_sit)
	for t in 2:
		var tag := PanelContainer.new()
		var tsb := flat(TEAM_COL[t], 0)
		if t == 0:
			tsb.corner_radius_top_left = 9
			tsb.corner_radius_bottom_left = 9
		else:
			tsb.corner_radius_top_right = 9
			tsb.corner_radius_bottom_right = 9
		tsb.content_margin_left = 10
		tsb.content_margin_right = 10
		tag.add_theme_stylebox_override("panel", tsb)
		tag.custom_minimum_size = Vector2(0, h)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var th := HBoxContainer.new()
		th.alignment = BoxContainer.ALIGNMENT_CENTER
		th.add_theme_constant_override("separation", 5)
		tag.add_child(th)
		var dot := _disp("•", fs + 2, Color(1.0, 0.85, 0.3), false)
		dot.modulate.a = 0.0
		_poss_dot[t] = dot
		_abbr[t] = _disp("", fs + 1, Color.WHITE)
		if t == 0:
			th.add_child(dot)
			th.add_child(_abbr[t])
		else:
			th.add_child(_abbr[t])
			th.add_child(dot)
		var sc := _disp("0", fs + (11 if narrow else 15), Color.WHITE, false)
		sc.custom_minimum_size = Vector2(40 if narrow else 52, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_score[t] = sc
		if t == 0:
			row.add_child(tag)
			row.add_child(sc)
			row.add_child(mid)
		else:
			row.add_child(sc)
			row.add_child(tag)
	var strip := HFlowContainer.new()
	strip.alignment = FlowContainer.ALIGNMENT_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(strip)
	_call = _label("", fs - 2, Color(0.88, 0.9, 0.94))
	_result = _label("", fs - 1, Color(1, 1, 1))
	_progress = _label("", fs - 1, GOOD)
	_progress.visible = false
	for l in [_call, _result, _progress]:
		var chip := PanelContainer.new()
		var csb := flat(Color(0.03, 0.045, 0.07, 0.82), 12, LINE, 1)
		csb.content_margin_left = 10
		csb.content_margin_right = 10
		csb.content_margin_top = 2
		csb.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", csb)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		(l as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		(l as Label).clip_text = true
		(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chip.add_child(l)
		chip.visible = false
		strip.add_child(chip)


## "Sprocket City Sparks" -> "SPA": three letters of the club's last word.
static func abbr(name: String) -> String:
	var w := name.strip_edges().split(" ")
	return String(w[-1]).substr(0, 3).to_upper() if w.size() > 0 else "???"


func show_state(g: Game) -> void:
	for t in 2:
		var has := g.poss == t and not g.over
		var cn: String = String(g.teams[t].get("club", Career.team(t)["name"])) if Career.loaded else (g.teams[t]["coach"] as Coach).name
		_abbr[t].text = abbr(cn)
		_score[t].text = str(g.score[t])
		_poss_dot[t].modulate.a = 1.0 if has else 0.0
	_clock.text = ("FINAL (OT)" if g.in_ot() else "FINAL") if g.over else g.clock_text().to_upper()
	var badge := (Career.mode_badge().to_upper() + " · ") if Career.loaded and get_viewport().get_visible_rect().size.x >= 520.0 else ""
	_sit.text = badge + ("" if g.over else g.situation().to_upper().replace(",", " ·"))


## Fade the scoreboard out for the play and back in after the whistle.
func show_board(on: bool) -> void:
	if _board == null:
		return
	_board_on = on
	if _board_tw != null and _board_tw.is_valid():
		_board_tw.kill()
	_board_tw = create_tween()
	_board_tw.tween_property(_board, "modulate:a", 1.0 if on else 0.0, 0.25)


func show_call(text: String) -> void:
	_chip_text(_call, text)


func show_result(text: String) -> void:
	_chip_text(_result, text)


## A strip chip's text, as wide as it needs up to the screen (then it trims with "...").
func _chip_text(l: Label, text: String) -> void:
	l.text = text
	l.get_parent().visible = text != ""
	var f := l.get_theme_font("font")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x + 2.0
	l.custom_minimum_size.x = minf(w, get_viewport().get_visible_rect().size.x - 44.0)


## ---- banners: the TV lower-third ------------------------------------------------------------

var _ban: Control
var _ban_tag: PanelContainer
var _ban_tag_l: Label
var _ban_msg: PanelContainer
var _ban_msg_l: Label
var _ban_tw: Tween


func _build_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110          # over any panel, so "SIGNED" shows on the roster too
	add_child(layer)
	var hold := Control.new()
	hold.set_anchors_preset(Control.PRESET_FULL_RECT)
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold.theme = _root.theme
	layer.add_child(hold)
	_ban = HBoxContainer.new()
	_ban.add_theme_constant_override("separation", 0)
	_ban.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold.add_child(_ban)
	_ban_tag = PanelContainer.new()
	_ban_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ban_tag_l = _disp("", fs + 6, Color.WHITE)
	_ban_tag.add_child(_ban_tag_l)
	_ban.add_child(_ban_tag)
	_ban_msg = PanelContainer.new()
	_ban_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ban_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var msb := flat(Color(0.03, 0.045, 0.07, 0.94), 0)
	msb.content_margin_left = 12
	msb.content_margin_right = 12
	msb.content_margin_top = 6
	msb.content_margin_bottom = 6
	_ban_msg.add_theme_stylebox_override("panel", msb)
	_ban_msg_l = _label("", fs, Color(0.94, 0.95, 0.97))
	_ban_msg_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ban_msg_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_ban_msg_l.clip_text = true
	_ban_msg_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ban_msg_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ban_msg.add_child(_ban_msg_l)
	_ban.add_child(_ban_msg)
	_ban.visible = false
	_toast = _ban_tag_l


## The colour of a banner's tag, from what it says.
static func banner_color(head: String) -> Color:
	var h := head.to_upper()
	if h.contains("NO GOOD") or h.contains("NOT ") or h.contains("COULDN") or h.contains("NOTHING"):
		return Color(0.85, 0.2, 0.17)
	for k in ["TOUCHDOWN", "GOOD", "FIELD GOAL", "SIGNED", "SOLD", "TRADED", "SAVED", "COACH"]:
		if h.contains(k):
			return Color(0.85, 0.6, 0.06)
	for k in ["INTERCEPT", "FUMBLE", "PICK SIX", "SCOOP", "BLOCKED", "NO GOOD", "FAILS", "TURNOVER", "SAFETY", "SACK", "NOT ENOUGH", "COULDN", "NOT SAVED", "BROKE", "LOST", "OFF", "DOWN!"]:
			if h.contains(k) and not h.contains("FIRST DOWN"):
				return Color(0.85, 0.2, 0.17)
	return Color(0.16, 0.42, 0.85)


## A TV lower-third: the first line is the tag ("TOUCHDOWN!"), the rest the message beside it.
## It slides in over the bottom of the field, holds, and slides away.
func toast(text: String, secs := 1.6) -> void:
	var lines := text.split("\n")
	var head := String(lines[0])
	var rest := " · ".join(lines.slice(1)) if lines.size() > 1 else ""
	var vp := get_viewport().get_visible_rect().size
	_ban_tag_l.text = head.to_upper() if head.length() <= 28 else head
	var big := head.length() <= 28
	_ban_tag_l.add_theme_font_override("font", DISP if big else BODY_B)
	_ban_tag_l.add_theme_font_size_override("font_size", fs + 6 if big else fs)
	_ban_tag_l.autowrap_mode = TextServer.AUTOWRAP_OFF if big else TextServer.AUTOWRAP_WORD_SMART
	var tsb := flat(banner_color(head), 0)
	tsb.content_margin_left = 14
	tsb.content_margin_right = 14
	tsb.content_margin_top = 6
	tsb.content_margin_bottom = 6
	_ban_tag.add_theme_stylebox_override("panel", tsb)
	_ban_msg_l.text = rest
	_ban_msg.visible = rest != ""
	_ban_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL if rest == "" else Control.SIZE_FILL
	_ban_tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if rest == "" else HORIZONTAL_ALIGNMENT_LEFT
	# a phone: the whole width; a wide screen: a broadcast strip in the lower left
	var w := vp.x if vp.x < 700.0 else minf(vp.x * 0.62, 760.0)
	_ban_tag_l.custom_minimum_size = Vector2(0, 0)
	if not big:
		_ban_tag_l.custom_minimum_size = Vector2(w - 28.0, 0)
	_ban.custom_minimum_size = Vector2(w, 0)
	_ban.size = Vector2(w, 0)
	_ban.reset_size()
	_ban.size.x = w
	var y := vp.y - _ban.get_combined_minimum_size().y - (_bar_h() + 22.0)
	_ban.visible = true
	_ban.modulate.a = 1.0
	if _ban_tw != null and _ban_tw.is_valid():
		_ban_tw.kill()
	_ban.position = Vector2(-w, y)
	var x0 := 0.0 if vp.x < 700.0 else 16.0
	_ban_tw = create_tween()
	_ban_tw.tween_property(_ban, "position:x", x0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ban_tw.tween_interval(maxf(secs, 0.8))
	_ban_tw.tween_property(_ban, "modulate:a", 0.0, 0.3)
	_ban_tw.tween_callback(func(): _ban.visible = false)
	_banner_sound(head)


func _banner_sound(head: String) -> void:
	if main == null or not ("sfx" in main) or main.sfx == null:
		return
	var h := head.to_upper()
	if h.contains("TOUCHDOWN") or h.contains("PICK SIX") or h.contains("SCOOP"):
		main.sfx.play("roar", -4.0)
		main.sfx.play("whistle", -12.0, 1.1)
	elif h.contains("INTERCEPT") or h.contains("FUMBLE") or h.contains("TURNOVER") or h.contains("BLOCKED"):
		main.sfx.play("whistle", -10.0)
		main.sfx.play("clank", -10.0, 0.7)
	elif h.contains("GOOD") or h.contains("SAFETY"):
		main.sfx.play("roar", -9.0)
	elif h.contains("SIGNED") or h.contains("SOLD") or h.contains("TRADED"):
		main.sfx.play("clink", -8.0, 1.3)


func _bar_h() -> float:
	return _bar.size.y if _bar != null and _bar.visible else 0.0


## ---- play-by-play captions ----------------------------------------------------------------

func _build_caption() -> void:
	_cap_box = PanelContainer.new()
	_cap_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cap_box.offset_left = 8
	_cap_box.offset_right = -8
	_cap_box.offset_top = 46
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.02, 0.05, 0.7)
	sb.border_color = Color(MAGENTA, 0.7)
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	_cap_box.add_theme_stylebox_override("panel", sb)
	_cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap = RichTextLabel.new()
	_cap.bbcode_enabled = true
	_cap.fit_content = true
	_cap.scroll_active = false
	_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap.add_theme_font_size_override("normal_font_size", fs)
	_cap.add_theme_font_size_override("bold_font_size", fs + 1)
	_cap_box.add_child(_cap)
	_cap_box.visible = false
	_root.add_child(_cap_box)


## A line from the announcer (or a robot). The last two show; they fade when the play goes quiet.
func caption(text: String, big := false, color := Color(0.9, 0.97, 1.0)) -> void:
	_cap_lines.append([text, YELLOW if big else color, big])
	while _cap_lines.size() > 2:
		_cap_lines.pop_front()
	var out := ""
	for i in _cap_lines.size():
		var ln: Array = _cap_lines[i]
		var c: Color = ln[1]
		if i < _cap_lines.size() - 1:
			c = c.darkened(0.35)
		var t := String(ln[0]).replace("[", "(").replace("]", ")")
		out += ("\n" if out != "" else "") + ("[b][color=#%s]%s[/color][/b]" % [c.to_html(false), t] if ln[2] else "[color=#%s]%s[/color]" % [c.to_html(false), t])
	_cap.text = out
	_cap_box.visible = true
	_cap_box.modulate.a = 1.0
	_cap_t = 3.5


func clear_caption() -> void:
	_cap_lines.clear()
	_cap_box.visible = false


## A big button over the field when the game is waiting on you and its panel is closed.
var _resume: Button


var _aud_btn: Button = null
var _aud_toggle: Button = null


## The pre-snap "Audible?" button (only while there is time to check out of the call).
func show_audible_button(on: bool) -> void:
	if _aud_btn == null:
		_aud_btn = _button("Audible?", func(): main.audible_pressed())
		_aud_btn.add_theme_font_size_override("font_size", fs + 6)
		_aud_btn.add_theme_color_override("font_color", YELLOW)
		_root.add_child(_aud_btn)
	_aud_btn.visible = on
	if on:
		_aud_btn.reset_size()
		var vp := get_viewport().get_visible_rect().size
		_aud_btn.position = Vector2((vp.x - _aud_btn.size.x) * 0.5, vp.y * 0.62)


func show_resume(on: bool, text: String) -> void:
	if _resume == null:
		_resume = _button("", func(): main.resume_panel())
		_resume.add_theme_font_size_override("font_size", fs + 6)
		_resume.set_anchors_preset(Control.PRESET_CENTER)
		_root.add_child(_resume)
	var was := _resume.visible
	_resume.visible = on
	if on and (not was or _resume.text != text):
		_resume.text = text
		_resume.reset_size()
		var vp := get_viewport().get_visible_rect().size
		_resume.position = Vector2((vp.x - _resume.size.x) * 0.5, vp.y * 0.55)


func set_progress(text: String) -> void:
	_chip_text(_progress, text)
	_progress.visible = text != ""


func _process(delta: float) -> void:
	if _cap_box != null and _cap_box.visible:
		# under the scoreboard when it is up, in its place while the ball is live
		var want := 18.0 + ((_board.size.y + 6.0) if _board_on else 0.0)
		_cap_box.offset_top = lerpf(_cap_box.offset_top, want, minf(delta * 10.0, 1.0))
		_cap_box.offset_bottom = _cap_box.offset_top
		_cap_t -= delta
		if _cap_t < 0.6:
			_cap_box.modulate.a = maxf(_cap_t / 0.6, 0.0)
		if _cap_t <= 0.0:
			_cap_box.visible = false
			_cap_lines.clear()


## ---- controls ------------------------------------------------------------------------------

var _bar: Control = null
var _speed_btn: Button = null
var _more: PanelContainer = null
const SPEEDS := [1.0, 2.0, 4.0, 8.0]


## One of the five keys along the bottom: a glyph on a tile with its name under it.
func _key(glyph: String, name: String, cb: Callable) -> Button:
	var b := _button(glyph, cb)
	b.add_theme_font_override("font", NUM)
	b.add_theme_font_size_override("font_size", fs + 3)
	b.custom_minimum_size = Vector2(54, 34)
	b.tooltip_text = name
	return b


## The slim bar over the field: Pause, Speed, Skip, Audible and More (the rest, in a drawer).
func _build_controls() -> void:
	var bar := PanelContainer.new()
	_bar = bar
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var bsb := flat(Color(0.03, 0.045, 0.07, 0.93), 14, LINE, 1)
	bsb.set_content_margin_all(6)
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bar.add_theme_stylebox_override("panel", bsb)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -10
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	var col := func(btn: Button, name: String) -> void:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.add_child(btn)
		var l := _label(name, fs - 4, DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(l)
		row.add_child(v)
	_pause_btn = _key("II", "Pause", func(): main.toggle_pause())
	col.call(_pause_btn, "Pause")
	_speed_btn = _key("1x", "Speed", func():
		var i := 0
		for k in SPEEDS.size():
			if is_equal_approx(SPEEDS[k], main.speed):
				i = k
		main.set_speed(SPEEDS[(i + 1) % SPEEDS.size()]))
	col.call(_speed_btn, "Speed")
	col.call(_key(">>", "Skip drive", func(): main.skip_drive()), "Skip drive")
	_aud_toggle = _key("A", "Audibles", func():
		main.toggle_audibles()
		_mark_aud())
	col.call(_aud_toggle, "Audibles")
	col.call(_key("...", "More", func(): _toggle_more()), "More")
	_build_more()
	_mark_aud()
	mark_speed(1.0)


func _mark_aud() -> void:
	if _aud_toggle == null:
		return
	var on: bool = main.audibles_on()
	_aud_toggle.add_theme_color_override("font_color", MAGENTA if on else DIM)
	_aud_toggle.tooltip_text = "Audibles: on" if on else "Audibles: off"


## The drawer above the bar: everything that used to crowd it.
func _build_more() -> void:
	_more = PanelContainer.new()
	_more.visible = false
	_root.add_child(_more)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_more.add_child(g)
	var add := func(t: String, cb: Callable) -> Button:
		var b := _button(t, func():
			_more.visible = false
			cb.call())
		b.custom_minimum_size = Vector2(112, 40)
		g.add_child(b)
		return b
	add.call("Sim to end", func(): main.sim_to_end())
	_view_btn = add.call("Cam: Behind", func(): _view_btn.text = "Cam: " + main.next_view())
	_sound_btn = add.call("Sound: voice", func(): _sound_btn.text = main.next_sound())
	add.call("Roster", func(): open_roster())
	add.call("Teams", func(): open_teams())
	add.call("Box score", func(): if main.game != null: show_stats(main.game, "live", {}, main.reopen_panel()))
	add.call("Play log", func(): open_log())
	add.call("Edit AI", func(): open_editor())
	add.call("Menu", func(): main.show_menu())


func _toggle_more() -> void:
	_more.visible = not _more.visible
	if _more.visible:
		_more.reset_size()
		var vp := get_viewport().get_visible_rect().size
		_more.position = Vector2((vp.x - _more.size.x) * 0.5, vp.y - _bar_h() - 20.0 - _more.size.y)


func mark_speed(s: float) -> void:
	if _speed_btn != null:
		_speed_btn.text = "%dx" % int(s)
		_speed_btn.add_theme_color_override("font_color", MAGENTA if s > 1.0 else Color(0.94, 0.95, 0.97))


func mark_paused(p: bool) -> void:
	_pause_btn.text = ">" if p else "II"


func mark_view(v: String) -> void:
	_view_btn.text = "Cam: " + v


## ---- overlays ------------------------------------------------------------------------------

func any_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


var _back := Callable()      # where Close goes back to (a box score opened from another panel)
## The trail of panels to this one (titles, shortened): shown under the title from the second
## level down, and what "Back to ..." names.
var _crumbs: Array = []
var _prev_crumbs: Array = []
var _close_btn: Button = null
var _crumb_lbl: Label = null
var _cur_title := ""


## A panel title as a short crumb: "Roster · Red Rivets · purse $190" -> "Roster".
static func _crumb(title: String) -> String:
	if title.begins_with("Teams") or title.begins_with("New game: set up") or title.begins_with("Sim lab: schemes"):
		return "Teams" if title.begins_with("Teams") else "Game setup"
	if title.begins_with("Week ") or title.begins_with("Championship") or title.begins_with("Season over") or title.begins_with("Exhibition:"):
		return "Game setup"
	var c := title.get_slice(" · ", 0).get_slice(": ", 0)
	return c if c.length() <= 26 else c.substr(0, 24) + "..."


## After a panel is built (and its caller has set _back): name where Close goes, and the trail.
func _refresh_nav() -> void:
	if _close_btn == null or not is_instance_valid(_close_btn):
		return
	var me := _crumb(_cur_title)
	if _back.is_valid():
		var at := -1
		for i in _prev_crumbs.size():
			if _prev_crumbs[i] == me:
				at = i
				break
		_crumbs = _prev_crumbs.slice(0, at + 1) if at >= 0 else _prev_crumbs + [me]
		if _crumbs.is_empty() or _crumbs[-1] != me:
			_crumbs.append(me)
	else:
		_crumbs = [me]
	if _back.is_valid() and _crumbs.size() >= 2:
		# on a phone the trail underneath says where; the button stays short so it never widens the page
		_close_btn.text = ("« Back" if get_viewport().get_visible_rect().size.x < 520.0 else "« Back to %s" % _crumbs[-2])
	elif _back.is_valid():
		_close_btn.text = "« Back"
	elif main != null and main._phase in ["picking", "special", "qbreak", "injury", "pregame", "audible"]:
		_close_btn.text = "Hide"     # the game waits on this panel: Resume brings it back
	else:
		_close_btn.text = "× Close"
	if _crumb_lbl != null and is_instance_valid(_crumb_lbl):
		_crumb_lbl.text = "  »  ".join(_crumbs)
		_crumb_lbl.visible = _crumbs.size() >= 2
	for b in _back_buttons:
		if is_instance_valid(b):
			b.text = _close_btn.text if _back.is_valid() else b.text


var _back_buttons: Array = []   # extra "Back" buttons on a panel that should read like Close
var slips: Array = []        # the last game's pay slips, for the final box score
var season_lines: Array = [] # the week's other results, next opponent, champion
var game_stars: Dictionary = {}
var _tbl_narrow := false     # player tables on a phone: smaller type, rating under the name   # players of the game just finished (worked out at the final whistle)


func close_overlay(follow_back := true) -> void:
	if any_overlay():
		_overlay.queue_free()
	_overlay = null
	Ux.panel("field")
	main.overlay_changed(false)
	if not (follow_back and _back.is_valid()):
		_crumbs = []           # back to the field: the trail starts again
	if follow_back and _back.is_valid():
		var b := _back
		_back = Callable()
		b.call()


## A panel over the field: returns its content box.
var _sc: DragScroll = null


## " · purse $1,240" (and any upgrade credit), for the title of every panel where you can buy.
func _purse() -> String:
	if not Career.loaded:
		return ""
	var t := " · purse $%d" % Career.money(0)
	if Career.credit(0) > 0:
		t += " + $%d credit" % Career.credit(0)
	return t


func _open(title: String) -> VBoxContainer:
	_prev_crumbs = _crumbs.duplicate() if any_overlay() or not _crumbs.is_empty() else []
	# the same page again (after a purchase, a repair, a tab): stay where you had scrolled to
	var keep_scroll := -1
	if any_overlay() and _sc != null and is_instance_valid(_sc) and _crumb(title) == _crumb(_cur_title):
		keep_scroll = _sc.scroll_vertical
	close_overlay(false)
	Ux.panel(title)
	_back = Callable()
	_cur_title = title
	_back_buttons = []
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_overlay = dim
	var vp := get_viewport().get_visible_rect().size
	var w := minf(vp.x - 16.0, 900.0)
	var pc := PanelContainer.new()
	# in a game the scorebug stays up over the panel: the clock and the down are never hidden
	var top := 40.0
	var in_game: bool = main != null and main.game != null and not main.game.over and _board != null \
			and main._phase in ["picking", "special", "qbreak", "injury", "audible"]
	if in_game:
		_board.modulate.a = 1.0
		_root.move_child(_board, -1)
		top = _board.position.y + _board.get_child(0).size.y + 8.0
	pc.position = Vector2((vp.x - w) * 0.5, top)
	pc.custom_minimum_size = Vector2(w, 0)
	pc.size = Vector2(w, vp.y - top - 20.0)
	dim.add_child(pc)
	var outer := VBoxContainer.new()
	pc.add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	outer.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	var main_t := title.get_slice(" · ", 0)
	var tl := _disp(main_t.to_upper(), fs + 9)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(tl)
	if title.length() > main_t.length():
		var rest := title.substr(main_t.length() + 3)
		var sub := _label(rest, fs - 2, MAGENTA if rest.contains("purse") else DIM)
		sub.add_theme_font_override("font", BODY_B)
		tv.add_child(sub)
	_close_btn = _button("× Close", func(): close_overlay())
	head.add_child(_close_btn)
	_crumb_lbl = _label("", fs - 3, Color(0.65, 0.72, 0.82))
	_crumb_lbl.visible = false
	outer.add_child(_crumb_lbl)
	_refresh_nav.call_deferred()
	var sc := DragScroll.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(sc)
	_sc = sc
	if keep_scroll > 0:
		_restore_scroll(sc, keep_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	# the panel is as tall as what is in it, up to the screen; past that it scrolls
	var refit := func() -> void: _fit_panel(pc, sc, box, vp.y - top - 20.0)
	box.minimum_size_changed.connect(refit)
	refit.call_deferred()
	main.overlay_changed(true)
	return box


func _restore_scroll(sc: DragScroll, v: int) -> void:
	for i in 3:
		await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = v
		sc._pos = float(v)


func _fit_panel(pc: PanelContainer, sc: Control, box: Control, max_h: float) -> void:
	if not is_instance_valid(pc) or not is_instance_valid(box):
		return
	var chrome := pc.get_combined_minimum_size().y - sc.get_combined_minimum_size().y
	var want := minf(max_h, chrome + box.get_combined_minimum_size().y + 6.0)
	pc.size = Vector2(pc.size.x, want)


func _section(box: Control, text: String) -> void:
	var l := _eyebrow(text, CYAN)
	l.add_theme_font_size_override("font_size", fs - 1)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 6)
	m.add_child(l)
	box.add_child(m)


func _chips(box: Control, names: Array, current: String, cb: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	for n in names:
		var b := _button(String(n), func(): cb.call(n), true)
		b.button_pressed = n == current
		f.add_child(b)
	box.add_child(f)
	return f


## ---- teams and brains ----------------------------------------------------------------------

var _teams_side := 0


var _confirm_new_season := false


## Season or exhibition, at the top of the set-up panel.
func _mode_section(box: VBoxContainer) -> void:
	_section(box, Career.mode_badge())
	var dim := Color(0.8, 0.82, 0.85)
	box.add_child(_button("Menu: season, exhibition or sim lab", func(): main.show_menu()))
	if Career.sim_mode():
		box.add_child(_label("Choose your coach (the play-calling scheme) and brains, tune the lab team's roster - swaps, upgrades, new robots - then simulate a game against each of these ten opponents. You only watch the results. The robots are copies: nothing breaks, nobody is paid, your season is untouched. Lab purse $%d." % Career.money(0), fs - 1, dim))
		for o in Career.sim_opponents():
			var ovr := 0.0
			for s0 in o["starters"]:
				ovr += Robot.overall(o["starters"][s0])
			box.add_child(_label("   %s · %s · %s" % [o["name"], Career.schemes_text(o), Career.ratings_text(o)], fs - 2, Color(0.85, 0.9, 0.95)))
		var lr := HFlowContainer.new()
		lr.add_theme_constant_override("h_separation", 6)
		box.add_child(lr)
		lr.add_child(_button("New opponents", func(): Career.new_sim_opponents(); open_teams(true)))
		lr.add_child(_button("New lab team ($2,000)", func(): Career.new_sim_lab(); main.new_game(false)))
		return
	if Career.exhibition():
		box.add_child(_label("One game. Both sides are drafted fresh with a single $2,000 budget: spend yours below (or let the coach); the rival's coach has spent his. Nobody is paid and nothing carries over to your season.", fs - 1, dim))
		box.add_child(_button("New exhibition teams", func(): Career.new_exhibition(); main.new_game(false)))
		return
	var sn := Career.season()
	if String(Career.data.get("last_champion", "")) != "" and int(sn.get("week", 1)) == 1:
		box.add_child(_label("Last season's champions: %s. A new season: $2,000 in your purse to spend before kickoff." % Career.data["last_champion"], fs, YELLOW))
	if Career.season_over():
		box.add_child(_label("SEASON OVER - champions: %s. Kick off starts a new season." % sn.get("champion", "?"), fs + 1, YELLOW))
	else:
		var opp := Career.team(1)
		box.add_child(_label("%s. This week: %s (%s, %s) - %s." % [Career.week_label(), opp["name"], Career.schemes_text(opp), Career._rec_text(opp["rec"]), Career.ratings_text(opp)], fs, Color(0.9, 0.93, 1.0)))
		box.add_child(_label("Your team, its purse and its damage carry from week to week. After each game you are paid for the result (win $1,300, tie $700) and for what you did: $250 a touchdown, $100 a big play (20+ yards), $100 a sack, $200 a takeaway, $50 a big hit (a part knocked off), $25 a first down - about $3,000 for a typical win, $1,000 for a loss. Repairs, upgrades and new robots come out of it. Each rival plays twice; best record is champion.", fs - 1, dim))
	for r in Career.standings():
		box.add_child(_label(("> " if r["you"] else "   ") + String(r["text"]), fs - 1, MAGENTA if r["you"] else Color(0.85, 0.9, 0.95)))
	var ns := _button("Really start over? Tap again" if _confirm_new_season else "Start a new season", func():
		if _confirm_new_season:
			_confirm_new_season = false
			Career.new_season()
			main.new_game(false)
		else:
			_confirm_new_season = true
			toast("TAP AGAIN TO START OVER\n(new draft, $2,000)", 2.0)
			open_teams(true))
	box.add_child(ns)


func open_teams(pregame := false) -> void:
	var title := "New game: set up the teams" if pregame else "Teams, coaches and brains"
	if pregame and Career.loaded:
		match Career.mode():
			"sim":
				title = "Sim lab: schemes and roster"
			"exhibition":
				title = "Exhibition: %s vs %s" % [Career.team(0)["name"], Career.team(1)["name"]]
			_:
				title = ("Season over" if Career.season_over() else "%s: %s vs %s" % [Career.week_label(), Career.team(0)["name"], Career.team(1)["name"]])
	if Career.loaded and Career.sim_mode():
		_teams_side = 0
	var box := _open(title + _purse())
	var lab := Career.loaded and Career.sim_mode()
	box.add_child(_label("Set up your coach (the AI that calls the plays), the brains at every position (the AI that plays them) and your robots, then Simulate." if lab else "Each side has a coach (the AI that calls the plays) and a brain at every position (the AI that plays them), and its robots. Set up both sides, then Kick off.", fs - 1, Color(0.8, 0.82, 0.85)))
	if pregame and lab:
		var sim_b := _button("Simulate %d games" % Career.SIM_OPPONENTS, func(): main.run_sim())
		sim_b.add_theme_font_size_override("font_size", fs + 4)
		box.add_child(sim_b)
	elif pregame:
		var ko := _button("Kick off", func():
			if Career.loaded and not Career.exhibition() and Career.season_over():
				Career.next_season()
			close_overlay(false); main.new_game(true))
		ko.add_theme_font_size_override("font_size", fs + 4)
		box.add_child(ko)
	if pregame and Career.loaded:
		_mode_section(box)
	var sides := HBoxContainer.new()
	box.add_child(sides)
	for t in (1 if lab else 2):
		var b := _button("%s side%s" % [Career.team(t)["name"] if Career.loaded else Team.NAMES[t], " (you)" if t == 0 else ""], func(): _teams_side = t; open_teams(pregame), true)
		b.button_pressed = _teams_side == t
		b.add_theme_color_override("font_color", FieldView.COLORS[t].lightened(0.4))
		sides.add_child(b)
	var t: int = _teams_side
	_section(box, "Offense (coach)")
	var cur: String = main.coaches[t]
	_chips(box, Library.names("coach"), cur, func(n):
		main.coaches[t] = n
		if t == 1 and Career.loaded:
			Career.team(1)["coach"] = n
			Career.save()
		elif t == 0 and Career.loaded:
			Career.set_my_schemes(n, main.defenses[0])
		main.library_changed()
		open_teams(pregame))
	var c: Coach = Library.coach(cur)
	if c != null:
		box.add_child(_label(c.about, fs - 1, Color(0.8, 0.82, 0.85)))
	# the defensive scheme: calls the defenses and picks the defensive brains
	_section(box, "Defense")
	var dcur: String = main.defenses[t]
	var dnames: Array = ["(the coach's own)"] + Library.names("defense")
	_chips(box, dnames, dcur if dcur != "" else dnames[0], func(n):
		var dn: String = "" if n == dnames[0] else n
		main.defenses[t] = dn
		if t == 1 and Career.loaded:
			Career.team(1)["defense"] = dn
			Career.save()
		elif t == 0 and Career.loaded:
			Career.set_my_schemes(main.coaches[0], dn)
		main.library_changed()
		open_teams(pregame))
	var dco: Coach = Library.defense(dcur)
	box.add_child(_label(dco.about if dco != null else "Uses the defense rules and defensive lineup in %s's coach file." % cur, fs - 1, Color(0.8, 0.82, 0.85)))
	var cf := HFlowContainer.new()
	if lab:
		cf.visible = false
	else:
		_section(box, "Play calling (offense and defense)")
	cf.add_theme_constant_override("h_separation", 6)
	cf.add_theme_constant_override("v_separation", 6)
	box.add_child(cf)
	for mode in Game.CALLING:
		var b := _button(Game.CALLING_LABEL[mode], func(): main.calling[t] = mode; main.library_changed(); open_teams(pregame), true)
		b.button_pressed = main.calling[t] == mode
		cf.add_child(b)
	var why := {"pick": "You call every play for this side: each down you get a hand of 8 brand-new plays (with diagrams) to choose from. The coach's choice is marked, with the rule he used. On 4th down the first card is the punt.",
		"coach": "The coach's rules pick every play.",
		"random": "Any play in the playbook, picked at random every down.",
		"generated": "A brand-new play made up every down: random formation, routes, gaps, coverages and blitzes. Save the good ones from the Log."}
	if not lab:
		box.add_child(_label(why[main.calling[t]], fs - 1, Color(0.8, 0.82, 0.85)))
	if Career.loaded:
		_section(box, "Robots")
		var tm := Career.team(t)
		var ovr := 0.0
		var hurt := 0
		for s0 in tm["starters"]:
			ovr += Robot.overall(tm["starters"][s0])
			if not Robot.lost_parts(tm["starters"][s0]).is_empty():
				hurt += 1
		box.add_child(_label("%s: %s, %d on the bench%s. Purse $%d." % [tm["name"], Career.ratings_text(tm), (tm["bench"] as Array).size(),
			(", %d missing parts" % hurt) if hurt > 0 else "", Career.money(t)], fs - 1, Color(0.85, 0.9, 0.95)))
		var rrow := HFlowContainer.new()
		rrow.add_theme_constant_override("h_separation", 6)
		box.add_child(rrow)
		rrow.add_child(_button("Roster, swaps and upgrades", func(): open_roster(t); _back = func(): open_teams(pregame)))
		_spend_row(box, t, func(): open_teams(pregame))
	_section(box, "Brains by position")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for g in Brain.GROUPS:
		var gl := _label(g, fs, Color(0.85, 0.9, 1))
		gl.autowrap_mode = TextServer.AUTOWRAP_OFF
		gl.custom_minimum_size.x = 34
		grid.add_child(gl)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var coach_pick: String = c.lineup.get(g, "") if c != null else ""
		if coach_pick == "":
			var opts0 := Library.brains_for(g)
			coach_pick = opts0[0] if not opts0.is_empty() else "-"
		ob.add_item("Coach's pick (%s)" % coach_pick)
		var opts := Library.brains_for(g)
		var sel := 0
		for i in opts.size():
			ob.add_item(String(opts[i]))
			if main.picks[t].get(g, "") == opts[i]:
				sel = i + 1
		ob.select(sel)
		ob.item_selected.connect(func(idx):
			if idx == 0:
				main.picks[t].erase(g)
			else:
				main.picks[t][g] = opts[idx - 1]
			_brain_about(g, t))
		grid.add_child(ob)
	_section(box, "Game length")
	var q := [["3 min quarters", 180.0], ["5 min", 300.0], ["8 min", 480.0], ["15 min (full)", 900.0]]
	var qf := HFlowContainer.new()
	qf.add_theme_constant_override("h_separation", 6)
	box.add_child(qf)
	for e in q:
		var b := _button(e[0], func(): main.qlen = e[1]; open_teams(pregame), true)
		b.button_pressed = is_equal_approx(main.qlen, e[1])
		qf.add_child(b)
	var go := _button("Kick off" if pregame else "Start a new game with these teams", func(): close_overlay(false); main.new_game(true))
	go.add_theme_font_size_override("font_size", fs + 2)
	box.add_child(go)


func _brain_about(g: String, t: int) -> void:
	var n: String = main.picks[t].get(g, "")
	if n != "":
		var b: Brain = Library.brain(n)
		if b != null:
			toast("%s: %s" % [b.name, b.about], 3.0)


## ---- the rule editor -----------------------------------------------------------------------

func open_editor(kind := "", name := "") -> void:
	if kind != "":
		_ed_kind = kind
	if name != "":
		_ed_name = name
	var box := _open("Edit the AI")
	box.add_child(_label("Every coach, play and position brain is a short rule file. Rules are read top to bottom; the first that holds decides. Tap a word below to insert it; type a space for suggestions.", fs - 1, Color(0.8, 0.82, 0.85)))
	var kinds := HFlowContainer.new()
	kinds.add_theme_constant_override("h_separation", 6)
	box.add_child(kinds)
	for k in ["ai", "coach", "defense", "play"]:
		var b := _button(KIND_LABEL[k], func(): _ed_kind = k; _ed_name = ""; open_editor(), true)
		b.button_pressed = _ed_kind == k
		kinds.add_child(b)
	var names := Library.names(_ed_kind)
	if _ed_name == "" or not names.has(_ed_name):
		_ed_name = names[0] if not names.is_empty() else ""
	_ed_names_box = HFlowContainer.new()
	_ed_names_box.add_theme_constant_override("h_separation", 5)
	_ed_names_box.add_theme_constant_override("v_separation", 5)
	box.add_child(_ed_names_box)
	for n in names:
		var label := String(n)
		if _ed_kind == "ai":
			label = "%s · %s" % [(Library.brain(n) as Brain).group, n]
		if Library.is_edited(_ed_kind, n):
			label += " (edited)"
		var b := _button(label, func(): _ed_name = n; open_editor(), true)
		b.button_pressed = n == _ed_name
		b.add_theme_font_size_override("font_size", fs - 2)
		_ed_names_box.add_child(b)
	_ed_text = CodeEdit.new()
	_ed_text.text = Library.source(_ed_kind, _ed_name)
	_ed_text.custom_minimum_size = Vector2(0, maxf(get_viewport().get_visible_rect().size.y * 0.42, 240))
	_ed_text.add_theme_font_size_override("font_size", fs - 1)
	_ed_text.gutters_draw_line_numbers = true
	_ed_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ed_text.code_completion_enabled = true
	_ed_text.code_completion_prefixes = [" "]
	_ed_text.code_completion_requested.connect(_on_completion)
	_ed_text.syntax_highlighter = _highlighter()
	_ed_text.text_changed.connect(func(): _lint_live())
	box.add_child(_ed_text)
	_ed_status = RichTextLabel.new()
	_ed_status.bbcode_enabled = true
	_ed_status.fit_content = true
	_ed_status.add_theme_font_size_override("normal_font_size", fs - 1)
	box.add_child(_ed_status)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	row.add_child(_button("Check", func(): _lint_live(true)))
	row.add_child(_button("Save", func(): _save()))
	row.add_child(_button("Reset to shipped", func(): Library.reset(_ed_kind, _ed_name); open_editor()))
	row.add_child(_button("Copy as new", func(): _copy_as_new()))
	row.add_child(_button("Save & play", func(): if _save(): close_overlay(); main.new_game()))
	# the words
	if _ed_kind == "play":
		_section(box, "Play syntax")
		var ph := _label(PLAY_HELP, fs - 2, Color(0.85, 0.88, 0.9))
		box.add_child(ph)
	else:
		_section(box, "Words (tap to insert)")
		var wm := HBoxContainer.new()
		box.add_child(wm)
		for m in ["conditions", "actions", "dials" if _ed_kind == "ai" else "lineup"]:
			var b := _button(m.capitalize(), func(): _ed_words_mode = m; _fill_words(), true)
			b.button_pressed = _ed_words_mode == m
			wm.add_child(b)
		_ed_example = _label("", fs - 1, Color(0.7, 1, 0.75))
		box.add_child(_ed_example)
		_ed_words_box = HFlowContainer.new()
		_ed_words_box.add_theme_constant_override("h_separation", 5)
		_ed_words_box.add_theme_constant_override("v_separation", 5)
		box.add_child(_ed_words_box)
		_fill_words()
	_lint_live()


func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color(0.7, 0.9, 1.0)
	h.symbol_color = Color(0.8, 0.8, 0.8)
	h.function_color = Color(0.9, 0.9, 0.9)
	h.member_variable_color = Color(0.9, 0.9, 0.9)
	for w in ["when", "otherwise", "and", "or", "not", "for"]:
		h.add_keyword_color(w, Color(1.0, 0.6, 0.35))
	for w in ["ai", "about", "position", "dials", "rules", "coach", "offense", "defense", "lineup", "play", "side", "kind", "formation", "front"]:
		h.add_keyword_color(w, Color(0.6, 0.8, 1.0))
	h.add_color_region("#", "", Color(0.5, 0.6, 0.5), true)
	h.add_color_region("\"", "\"", Color(0.95, 0.85, 0.5))
	return h


func _fill_words() -> void:
	for c in _ed_words_box.get_children():
		c.queue_free()
	var tables := Library.tables(_ed_kind)
	var items: Array = []
	match _ed_words_mode:
		"conditions":
			items = RuleHelp.phrases(tables["conditions"])
		"actions":
			items = RuleHelp.phrases(tables["actions"])
		"dials":
			for d in Brain.DIALS:
				items.append({"phrase": "%s 0.5" % d, "help": Brain.DIAL_HELP[d]})
		"lineup":
			for g in Brain.GROUPS:
				var opts := Library.brains_for(g)
				for o in opts:
					items.append({"phrase": "%s \"%s\"" % [g, o]})
	for it in items:
		var phrase: String = it["phrase"]
		var b := _button(phrase, func(): _insert(phrase, it))
		b.add_theme_font_size_override("font_size", fs - 2)
		_ed_words_box.add_child(b)
	var ex := ""
	if _ed_kind == "ai":
		ex = "e.g.  when with the ball and one man to beat -> juke\n      when before the throw and pressure and checkdown open -> check down"
	elif _ed_kind == "defense":
		ex = "e.g.  when third down and to go over 7 -> call \"Cover 2\" or \"Cover 3\"\n      when they run over 60% -> call \"Run Blitz\""
	elif _ed_kind == "coach":
		ex = "e.g.  when third down and to go over 7 -> call \"Smash\" or \"Four Verticals\"\n      when \"Power\" averaging over 5 and chance 50% -> call \"Power\""
	_ed_example.text = ex


func _insert(phrase: String, it: Dictionary) -> void:
	var text := phrase.replace("N%", "40%").replace("Ns", "2s").replace(" N", " 5").replace("WORD", "wr1").replace("\"NAME\"", "\"Smash\"")
	_ed_text.insert_text_at_caret(text + " ")
	_ed_text.grab_focus()
	if it.has("help"):
		_ed_example.text = String(it["help"])
	else:
		var verb := "when %s -> ..." % text if _ed_words_mode == "conditions" else "when ... -> %s" % text
		_ed_example.text = "e.g.  " + verb


## Completion: after a space, offer the phrases that continue what is being typed.
func _on_completion() -> void:
	var tables := Library.tables(_ed_kind)
	if tables.is_empty():
		return
	var line := _ed_text.get_line(_ed_text.get_caret_line()).substr(0, _ed_text.get_caret_column()).to_lower()
	var after_arrow := line.find("->") >= 0
	var cut := 0
	for sep in ["when ", " and ", " or ", "not ", "->", ";", "("]:
		var k := line.rfind(sep)
		if k >= 0:
			cut = maxi(cut, k + sep.length())
	var frag := line.substr(cut).strip_edges(true, false)
	var table: Array = tables["actions"] if after_arrow else tables["conditions"]
	var word_start := frag.rfind(" ") + 1
	for ph in RuleHelp.complete(frag, table, 12):
		var rest := ph.substr(word_start) if ph.begins_with(frag) else ph
		_ed_text.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, ph, rest)
	_ed_text.update_code_completion_options(true)


func _lint_live(loud := false) -> void:
	var errs := Library.lint(_ed_kind, _ed_text.text)
	if errs.is_empty():
		_ed_status.text = "[color=#8f8]Reads cleanly.[/color]" + ("" if not loud else " Save to use it.")
	else:
		var s := "[color=#f99]"
		for e in errs.slice(0, 6):
			s += "- " + e.replace("[", "(").replace("]", ")") + "\n"
		_ed_status.text = s + "[/color]"


func _save() -> bool:
	var r := Library.save(_ed_kind, _ed_text.text)
	if not (r[0] as Array).is_empty():
		_lint_live(true)
		toast("Not saved - fix the problems first", 2.0)
		return false
	_ed_name = r[1]
	toast("Saved \"%s\" - used from the next snap" % _ed_name, 2.0)
	main.library_changed()
	open_editor()
	return true


func _copy_as_new() -> void:
	var text := _ed_text.text
	var head: String = {"ai": "ai ", "coach": "coach ", "defense": "coach ", "play": "play "}[_ed_kind]
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].strip_edges().to_lower().begins_with(head):
			var n := Dsl.quoted(lines[i].strip_edges().substr(head.length()))
			lines[i] = "%s\"%s (mine)\"" % [head, n]
			break
	_ed_text.text = "\n".join(lines)
	_lint_live()
	toast("Renamed - Save to keep it as a new one", 2.0)


## ---- the log and results ------------------------------------------------------------------

func open_log() -> void:
	var box := _open("Play by play")
	var g: Game = main.game
	if g == null:
		return
	var entries: Array = g.log.slice(maxi(0, g.log.size() - 120))
	entries.reverse()
	for e in entries:
		var s := maxi(int(e["clock"]), 0)
		var who := ""
		if e.has("team"):
			who = Team.NAMES[int(e["team"])] + " · " + ["", "1st", "2nd", "3rd", "4th"][clampi(int(e["down"]), 1, 4)] + " & " + str(maxi(int(round(float(e["to_go"]))), 1)) + " · "
		var l := _label("Q%d %d:%02d  %d-%d   %s%s" % [e["q"], s / 60, s % 60, e["score"][0], e["score"][1], who, e["text"]], fs - 2)
		box.add_child(l)
		if e.has("off_text") or e.has("def_text"):
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			box.add_child(row)
			for k in ["off_text", "def_text"]:
				if e.has(k):
					var txt: String = e[k]
					var b := _button("+ Save %s play" % ("offense" if k == "off_text" else "defense"), func(): _save_generated(txt))
					b.add_theme_font_size_override("font_size", fs - 3)
					row.add_child(b)


## Keep a play made up during the game: it goes into the playbook under its own name.
func _save_generated(text: String) -> void:
	var p := Play.parse(text)
	var base := p.name.replace("Gen ", "My ")
	var n := base
	var k := 2
	while Library.play(n) != null:
		n = "%s #%d" % [base, k]
		k += 1
	var r := Library.save("play", text.replace("\"%s\"" % p.name, "\"%s\"" % n).replace("Made up for this down.", "Saved from a game."))
	if (r[0] as Array).is_empty():
		toast("Saved \"%s\" to the playbook" % n, 2.5)
		main.library_changed()
	else:
		toast("Couldn't save: %s" % r[0][0], 3.0)


## ---- calling your own plays ---------------------------------------------------------------

## A play card's look: a dark tile, gold-edged when it's the coach's pick.
func _card_style(card: Button, gold: bool) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := flat(SURF1 if st == "normal" else SURF2, 12, MAGENTA if gold else LINE, 2 if gold else 1)
		sb.set_content_margin_all(0)
		if st == "pressed":
			sb.border_color = MAGENTA
			sb.set_border_width_all(2)
		card.add_theme_stylebox_override(st, sb)


func open_picker(g: Game, team: int, side: String, hand: Array, coach: Dictionary = {}) -> void:
	# the clock and the down are on the scorebug, which stays up over this panel
	var title: String = ("Call a play" if side == "offense" else "Call a defense") + " · " + String(Team.NAMES[team]) + " " + side
	var box := _open(title)
	var vp := get_viewport().get_visible_rect().size
	var inner := minf(vp.x - 16.0, 900.0) - 44.0
	var cols := 2 if inner < 560.0 else 4
	var cw := floorf((inner - 8.0 * (cols - 1)) / cols)
	var coach_i := int(coach.get("index", -1))
	var coach_name: String = ((g.teams[team]["coach"]) as Coach).name
	# the coach's pick in one line; the reasons behind a tap
	var why := ""
	var line := ""
	if String(coach.get("call", "")) == "punt":
		line = "Coach's pick: punt it away"
		why = "His rule: %s." % String(coach.get("why", ""))
	elif String(coach.get("call", "")) == "field_goal":
		line = "Coach's pick: kick the field goal"
		why = "His rule: %s." % String(coach.get("why", ""))
	elif coach_i >= 0:
		var gd: Dictionary = coach.get("grade", {})
		line = "Coach's pick: %s" % String(coach.get("call", ""))
		if not gd.is_empty():
			line += "  ·  %d%%  ·  grade %s" % [int(round(float(gd["p"]) * 100)), gd["grade"]]
			var need := float(coach.get("need", 10.0))
			why = "%s's rule: %s. The gold card is the closest to it in this hand.\n%s %d%% (±%d) to %s %d yards, #%d of %d in the playbook (best: %s %d%%, average %d%%)." % [
				coach_name, String(coach.get("why", "-")), String(coach.get("call", "")), int(round(float(gd["p"]) * 100)), int(round(float(gd["margin"]) * 100)),
				"hold them under" if side == "defense" else "gain", int(ceil(need)), int(gd["rank"]), int(gd["of"]),
				gd["best"], int(round(float(gd["best_p"]) * 100)), int(round(float(gd["avg_p"]) * 100))]
		else:
			why = "%s's rule: %s. The gold card is the closest to it in this hand." % [coach_name, String(coach.get("why", "-"))]
	if line != "":
		var lr := HBoxContainer.new()
		box.add_child(lr)
		var ll := _label(line, fs - 1, MAGENTA)
		ll.add_theme_font_override("font", BODY_B)
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(ll)
		var wl := _label(why, fs - 2, DIM)
		wl.visible = false
		var wb := _button("Why?", func(): wl.visible = not wl.visible)
		wb.add_theme_font_size_override("font_size", fs - 2)
		lr.add_child(wb)
		box.add_child(wl)
	var make := func(ci: int, w: float, hero: bool) -> Button:
		var g2: Dictionary = hand[ci]
		var p: Play = g2["play"]
		var card := Button.new()
		var gold := ci == coach_i
		_card_style(card, gold)
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var dh := w * (0.36 if hero else 0.62)
		card.custom_minimum_size = Vector2(w, dh + fs * 2.9 + 14.0)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 3
		v.offset_right = -3
		v.offset_top = 3
		v.offset_bottom = -6
		v.add_theme_constant_override("separation", 1)
		card.add_child(v)
		var d := PlayDiagram.new()
		d.custom_minimum_size = Vector2(w - 6.0, dh)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		d.setup(p)
		if gold:
			var badge := _label("COACH'S PICK", fs - 3, INK)
			badge.add_theme_font_override("font", BODY_B)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bsb := flat(MAGENTA, 5)
			bsb.content_margin_left = 7
			bsb.content_margin_right = 7
			bsb.content_margin_top = 1
			bsb.content_margin_bottom = 1
			badge.add_theme_stylebox_override("normal", bsb)
			badge.autowrap_mode = TextServer.AUTOWRAP_OFF
			badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
			badge.size = Vector2.ZERO
			badge.position = Vector2(9, 9)
			badge.z_index = 1
			card.add_child.call_deferred(badge)
		var nm := (("%s · %s" % [p.name, "run" if p.kind == "run" else "pass"]) if side == "offense" else p.name).to_upper()
		var nl := _disp(nm, fs + (4 if hero else 1))
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var nmc := MarginContainer.new()
		nmc.add_theme_constant_override("margin_left", 8)
		nmc.add_theme_constant_override("margin_right", 8)
		nmc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nmc.add_child(nl)
		v.add_child(nmc)
		var sl := _label(_play_subline(p), fs - 3, DIM)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.clip_text = true
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var slc := MarginContainer.new()
		slc.add_theme_constant_override("margin_left", 8)
		slc.add_theme_constant_override("margin_right", 8)
		slc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slc.add_child(sl)
		v.add_child(slc)
		card.pressed.connect(func(): main.pick_made("off" if side == "offense" else "def", g2))
		return card
	# the coach's pick big on top (on a phone), the rest two by two
	var hero := coach_i >= 0 and coach_i < hand.size() and cols == 2
	if hero:
		box.add_child(make.call(coach_i, inner, true))
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	if side == "offense" and g.down == 4:
		for pc in _punt_cards(g, team, cw, String(coach.get("call", "")) == "punt"):
			grid.add_child(pc)
		# in reach of the posts: a field goal, with its length and the kicker's chance
		if g.fg_distance() <= g.fg_range(team) + 8.0:
			var kr: Dictionary = (g.teams[team].get("special", {}) as Dictionary).get("K", {})
			var fsub := "%s · %d yards · about %d%% to make it" % [_who_txt(kr, "Your kicker"), int(round(g.fg_distance())), int(round(g.fg_chance(team, g.fg_distance()) * 97.5))]
			grid.add_child(_text_card(cw, "Field goal", fsub, String(coach.get("call", "")) == "field_goal", func(): main.pick_made("kick", "field_goal")))
	for ci in hand.size():
		if hero and ci == coach_i:
			continue
		grid.add_child(make.call(ci, cw, false))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	row.add_child(_button("Deal new plays", func(): main.redeal(side)))
	row.add_child(_button("Box score", func(): show_stats(g, "live", {}, func(): open_picker(g, team, side, hand, coach))))
	box.add_child(_label("Yellow is the run, blue the line of scrimmage. Defense: shaded zones, dashed lines for man, pink arrows for blitzers.", fs - 3, Color(0.5, 0.55, 0.62)))


## 4th down: the punt, as the first card in the hand.
## A big text card for a special-teams call (no diagram): title, a line or two, the coach's mark.
func _text_card(cw: float, title: String, sub: String, coach_pick: bool, on_pick: Callable) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = Vector2(cw, cw * 0.62 + fs * 2.9 + 14.0)
	_card_style(card, coach_pick)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var big := _disp(title.to_upper(), fs + 10, YELLOW)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(big)
	for t2 in [sub, "COACH'S PICK" if coach_pick else ""]:
		if t2 == "":
			continue
		var l := _label(t2, fs - 2, MAGENTA if t2 == "COACH'S PICK" else Color(0.85, 0.88, 0.92))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	card.pressed.connect(on_pick)
	return card


func _who_txt(r: Dictionary, fallback: String) -> String:
	return ("#%d %s" % [int(r["number"]), r["name"]]) if not r.is_empty() else fallback


## 4th down: the three punts, first in the hand.
func _punt_cards(g: Game, team: int, cw: float, coach_pick: bool) -> Array:
	var pr: Dictionary = (g.teams[team].get("special", {}) as Dictionary).get("P", {})
	var leg := Robot.eff(pr, "leg") if not pr.is_empty() else 60.0
	var gross := 43.0 + (leg - 60.0) * 0.22
	var who := _who_txt(pr, "Your punter")
	var sub := "%s · about %d yards, then a return" % [who, int(round(gross))]
	if g.yl + gross >= 100.0:
		sub += " (touchback likely)"
	return [
		_text_card(cw, "Punt", sub, coach_pick, func(): main.pick_made("kick", "punt")),
		_text_card(cw, "Coffin corner", "Aimed out of bounds deep: a little shorter, but no return", false, func(): main.pick_made("kick", "coffin")),
		_text_card(cw, "Pooch punt", "High and short to pin them deep: they fair-catch it", false, func(): main.pick_made("kick", "pooch")),
	]


## Kickoffs and returns: the kicking side picks the kick, the receiving side the return.
## Pre-snap: both calls, any check the other side made, and the person's one audible - keep the
## call or check into one of three fresh plays.
func open_audible(g: Game, team: int, side: String, snap: Dictionary, hand: Array, coach: Dictionary) -> void:
	var mine_key := "off_name" if side == "offense" else "def_name"
	var theirs_key := "def_name" if side == "offense" else "off_name"
	var box := _open("%s · %s · Audible? %s" % [g.clock_text(), g.situation(), "offense" if side == "offense" else "defense"])
	box.add_child(_label("Time on the play clock: you may check out of your call once, after seeing how they line up.", fs - 1, Color(0.8, 0.83, 0.88)))
	box.add_child(_label("Your call:  %s" % String(snap[mine_key]), fs + 2, YELLOW))
	var theirs := String(snap[theirs_key])
	box.add_child(_label("Their look:  %s" % theirs, fs + 2, CYAN))
	for a in snap.get("audibles", []):
		if int(a["team"]) != team:
			box.add_child(_label("They audibled: out of %s into %s (%s)" % [a["from"], a["to"], a["why"]], fs, MAGENTA))
	var vp := get_viewport().get_visible_rect().size
	var inner := minf(vp.x - 16.0, 900.0) - 40.0
	var cols := 2
	var cw := floorf((inner - 8.0 * (cols - 1)) / cols)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	grid.add_child(_text_card(cw, "Keep it: %s" % String(snap[mine_key]), "Run the play you called.", false, func(): main.audible_made({})))
	for i in hand.size():
		var card: Dictionary = hand[i]
		var p: Play = card["play"]
		grid.add_child(_text_card(cw, "Check to: %s" % p.name, _play_subline(p), int(coach.get("index", -1)) == i, func(): main.audible_made(card)))
	if int(coach.get("index", -1)) >= 0:
		box.add_child(_label("The marked card is the one the coach would pick.", fs - 2, MAGENTA))


## A check the computer made, shown clearly before the snap: who, what they had, what they went to.
func show_audibles(g: Game, list: Array) -> void:
	var lines: Array = []
	for a in list:
		var nm: String = g.teams[int(a["team"])].get("club", Team.NAMES[int(a["team"])])
		lines.append("%s: %s  ->  %s" % [nm, a["from"], a["to"]])
	toast("AUDIBLE!\n" + "\n".join(lines), 2.6)
	for a in list:
		var nm2: String = g.teams[int(a["team"])].get("club", Team.NAMES[int(a["team"])])
		caption("%s audible (%s): out of %s into %s - %s" % [nm2, a["side"], a["from"], a["to"], a["why"]], false, Color(1.0, 0.85, 0.3))


func open_special(g: Game, team: int, kind: String, coach_pick: String) -> void:
	var tname := String(g.teams[team].get("club", g.teams[team]["name"]))
	var box := _open("%s · %s" % [g.clock_text(), ("%s kick off" if kind == "kickoff" else ("%s: the try" if kind == "try" else "%s return")) % tname])
	var vp := get_viewport().get_visible_rect().size
	var inner := minf(vp.x - 16.0, 900.0) - 40.0
	var cols := 2
	var cw := floorf((inner - 8.0 * (cols - 1)) / cols)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	if kind == "try":
		var kk: Dictionary = (g.teams[team].get("special", {}) as Dictionary).get("K", {})
		box.add_child(_label("Touchdown! %s %d - %d %s. Now the try:" % [g.teams[0]["name"], g.score[0], g.score[1], g.teams[1]["name"]], fs - 1, Color(0.85, 0.88, 0.92)))
		box.move_child(box.get_child(box.get_child_count() - 1), grid.get_index())
		grid.add_child(_text_card(cw, "Kick the extra point", "%s from 32 yards: 1 point, about %d%% (it can be blocked)" % [_who_txt(kk, "Your kicker"), int(round(g.fg_chance(team, 32.0) * 97.5))], coach_pick == "kick", func(): main.pick_made("try", "kick")))
		grid.add_child(_text_card(cw, "Go for two", "One play from the 2: get it in for 2 points, or nothing", coach_pick == "two", func(): main.pick_made("try", "two")))
		return
	if kind == "kickoff":
		var k: Dictionary = (g.teams[team].get("special", {}) as Dictionary).get("K", {})
		var leg := Robot.eff(k, "leg") if not k.is_empty() else 60.0
		var subs := {"deep": "%s, leg %d: as deep as he can - a touchback or a long return" % [_who_txt(k, "Your kicker"), int(leg)],
			"squib": "Driven into the turf, bouncing to their 25-40: no long return, and now and then it squirts away from them",
			"onside": "Short and hopping, both sides diving for it: you get it about 1 in 8, otherwise they start near midfield"}
		for c in Game.KICKS:
			grid.add_child(_text_card(cw, Game.KICKS[c], subs[c], c == coach_pick, func(): main.pick_made("kickoff", c)))
	else:
		var rd: Dictionary = g.return_due
		var ret := g._returner(team)
		var who := _who_txt(ret, "Your returner")
		var deep := String(rd.get("kind", "")) == "kickoff" and float(rd.get("catch", 0.0)) <= 0.0
		var subs := {"middle": "%s takes it straight up behind the wedge" % who,
			"left": "The wall sets up to the left; he bends it that way",
			"right": "The wall sets up to the right; he bends it that way",
			"fair": "Take a knee in the end zone: ball at the 25" if deep else "Fair catch: your ball where he catches it, no return"}
		box.add_child(_label("%s is coming: the ball comes down around the %s." % ["The kickoff" if String(rd.get("kind", "")) == "kickoff" else "The punt",
			"end zone" if deep else g._spot_text(maxf(float(rd.get("catch", 20.0)), 1.0), team)], fs - 1, Color(0.85, 0.88, 0.92)))
		box.move_child(box.get_child(box.get_child_count() - 1), grid.get_index())
		if rd.has("ground"):
			box.get_child(grid.get_index() - 1).text = "%s is coming along the ground - field it on the bounce, then run it back." % ("An onside kick" if String(rd["ground"]) == "onside" else "A squib kick")
		for c in Game.RETURNS:
			# no fair catch on a ball along the ground, and nobody takes a knee in the end zone
			if c == "fair" and (rd.has("ground") or deep):
				continue
			var title := "Take a knee" if c == "fair" and deep else ("Fair catch" if c == "fair" else String(Game.RETURNS[c]))
			grid.add_child(_text_card(cw, title, subs[c], c == coach_pick, func(): main.pick_made("return", c)))


func _play_subline(p: Play) -> String:
	if p.about != "" and not p.about.begins_with("Made up"):
		return p.about
	if p.side == "offense":
		var qb: Dictionary = p.assigns.get("QB", {})
		if p.kind == "run":
			return "%s · run" % p.formation.capitalize()
		return "%s · %s%d-step drop" % [p.formation.capitalize(), "play action, " if qb.get("fake", false) else "", int(qb.get("drop", 5))]
	var blitz := 0
	for s in p.assigns:
		if String(p.assigns[s].get("kind", "")) == "blitz":
			blitz += 1
	return "%s · %s%s" % [p.front.capitalize(), p.kind, (" · %d blitz" % blitz) if blitz > 0 else ""]


## ---- box scores: at each quarter break, at the end and any time from Stats ---------------

var _stats_tab := "report"


## mode: "quarter" (a break - Continue goes on), "final", or "live" (just a look).
## On the final screen: players of the game, of the week (every game this week), and at the end
## of a season the season's awards - near the top, so nobody has to scroll for them.
func _award_sections(box: Container, g: Game) -> void:
	if not Career.loaded:
		return
	var mine := String(Career.team(0)["name"])
	var row_label := func(head: String, b: Dictionary, side: String) -> void:
		# an award card: what it is in gold, who in bold (his club's colour bar on the left), his line
		var ours := String(b["team"]) == mine
		var card := PanelContainer.new()
		var sb := flat(SURF2, 12)
		sb.border_color = TEAM_COL[0 if ours else 1]
		sb.border_width_left = 5
		sb.content_margin_left = 12
		sb.content_margin_right = 10
		sb.content_margin_top = 7
		sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		card.add_child(v)
		v.add_child(_eyebrow(head, MAGENTA))
		var nl := _label("%s %s" % [b["slot"], b["name"]], fs + 1, Color.WHITE)
		nl.add_theme_font_override("font", BODY_B)
		v.add_child(nl)
		v.add_child(_label("%s · %s" % [b["team"], Career.stat_line(b["stats"], side)], fs - 2, DIM))
		box.add_child(card)
	var gs: Dictionary = game_stars if not game_stars.is_empty() else Career.game_stars(g)
	if not (gs["off"] as Dictionary).is_empty() or not (gs["def"] as Dictionary).is_empty():
		_section(box, "Players of the game")
		for side in ["off", "def"]:
			if not (gs[side] as Dictionary).is_empty():
				row_label.call("Offense" if side == "off" else "Defense", gs[side], side)
	if Career.exhibition():
		return
	var sn := Career.season()
	var potw: Dictionary = sn.get("potw", {})
	if not potw.is_empty():
		_section(box, "Players of the week" if not String(sn.get("potw_label", "")).begins_with("Championship") else "Players of the championship game")
		for side in ["off", "def"]:
			if potw.has(side):
				row_label.call("Offense" if side == "off" else "Defense", potw[side], side)
	if Career.season_over():
		_section(box, "Season awards")
		for aw in Career.season_awards():
			row_label.call(String(aw[0]), aw[1], String(aw[1]["side"]))


## The final score, big, on the two clubs' colours; the loser dimmed; WIN / LOSS / TIE under it.
func _final_hero(box: Control, g: Game, names: Array, score: Array) -> void:
	var w := g.winner()
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 0)
	box.add_child(hero)
	for t in 2:
		var half := PanelContainer.new()
		var sb := flat(TEAM_COL[t].darkened(0.6), 0)
		if t == 0:
			sb.corner_radius_top_left = 14
			sb.corner_radius_bottom_left = 14
		else:
			sb.corner_radius_top_right = 14
			sb.corner_radius_bottom_right = 14
		sb.set_content_margin_all(10)
		half.add_theme_stylebox_override("panel", sb)
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hero.add_child(half)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -6)
		half.add_child(v)
		var nm := _disp(String(names[t]).to_upper(), fs, Color.WHITE)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		var sc := _disp(str(score[t]), fs + 40, Color.WHITE, false)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sc)
		if w >= 0 and w != t:
			half.modulate = Color(1, 1, 1, 0.55)
	var res := "TIE" if w < 0 else ("WIN" if w == 0 else "LOSS")
	if Career.loaded and not Career.exhibition():
		res += "  ·  " + Career._rec_text(Career.season().get("you", {"w": 0, "l": 0, "t": 0}))
	var bl := _disp(res, fs + 2, Color(0.03, 0.12, 0.05) if w == 0 else Color.WHITE)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bp := PanelContainer.new()
	var bsb := flat(GOOD if w == 0 else (BAD if w == 1 else SURF3), 6)
	bsb.content_margin_left = 14
	bsb.content_margin_right = 14
	bp.add_theme_stylebox_override("panel", bsb)
	bp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bp.add_child(bl)
	box.add_child(bp)


func show_stats(g: Game, mode: String, snap: Dictionary = {}, back := Callable()) -> void:
	_stats_mode = mode
	_stats_snap = snap
	var names := [(g.teams[0]["coach"] as Coach).name, (g.teams[1]["coach"] as Coach).name]
	if Career.loaded:
		names = [String(g.teams[0].get("club", Career.team(0)["name"])), String(g.teams[1].get("club", Career.team(1)["name"]))]
	var score: Array = snap.get("score", g.score)
	var line: Array = snap.get("line", g.line)
	var stats: Array = snap.get("stats", g.stats)
	var pstats: Array = snap.get("pstats", g.pstats)
	var title := "Box score"
	match mode:
		"quarter":
			var q := int(snap.get("q", 1))
			title = ["", "End of the 1st quarter", "Halftime", "End of the 3rd quarter", "End of regulation"][clampi(q, 1, 4)]
		"final":
			title = "Final"
		"live":
			title = "Box score · %s" % ("OT" if g.in_ot() else "Q%d" % mini(g.quarter, 4))
	var box := _open(title)
	_back = back
	if back.is_valid():
		var bk := _button("« Back", func(): close_overlay())
		box.add_child(bk)
		_back_buttons.append(bk)
	if mode == "final" and _final_for != g:
		_final_for = g
		_stats_tab = "summary"
	if mode == "final":
		_final_hero(box, g, names, score)
	_line_score(box, names, line, score)
	# what to do next stays up top, whatever tab is open
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var wide := func(b: Button) -> Button:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		return b
	if mode == "quarter":
		_primary(wide.call(_button("CONTINUE", func(): close_overlay(); main.resume_after_break())), fs + 2)
		var stop := _button("Stop at quarter breaks", func(): main.stop_at_quarters = not main.stop_at_quarters, true)
		stop.button_pressed = main.stop_at_quarters
		wide.call(stop)
	if mode == "final":
		if not Career.loaded:
			_primary(wide.call(_button("PLAY AGAIN", func(): close_overlay(); main.new_game())), fs + 2)
		elif Career.exhibition():
			_primary(wide.call(_button("ANOTHER EXHIBITION", func(): close_overlay(); Career.new_exhibition(); main.new_game(false))), fs + 2)
		elif Career.season_over():
			_primary(wide.call(_button("START NEXT SEASON", func(): close_overlay(); main.new_game(false))), fs + 2)
		else:
			_primary(wide.call(_button("NEXT: %s" % Career.week_label().to_upper(), func(): main.next_game())), fs + 2)
		var mb := _button("Menu", func(): main.show_menu())
		mb.custom_minimum_size.x = 90
		row.add_child(mb)
	if row.get_child_count() == 0:
		row.queue_free()
	# the tabs
	var tab_list: Array = []
	if mode == "final":
		tab_list.append(["summary", "Summary"])
	tab_list += [["report", "Report"], ["team", "Team"], ["p0", "%s players" % Team.NAMES[0]], ["p1", "%s players" % Team.NAMES[1]], ["plays", "Plays"], ["drives", "Drives"], ["rules", "Rules"]]
	if mode == "final" and Career.loaded and not season_lines.is_empty():
		tab_list.insert(1, ["season", "Season" if not Career.exhibition() else "Exhibition"])
	var keys := tab_list.map(func(x): return x[0])
	if not _stats_tab in keys:
		_stats_tab = keys[0]
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 5)
	tabs.add_theme_constant_override("v_separation", 5)
	box.add_child(tabs)
	for tab in tab_list:
		var b := _button(tab[1], func(): _stats_tab = tab[0]; _back = Callable(); show_stats(g, mode, snap, back), true)
		b.button_pressed = _stats_tab == tab[0]
		b.add_theme_font_size_override("font_size", fs - 2)
		tabs.add_child(b)
	match _stats_tab:
		"summary":
			_award_sections(box, g)
			_pay_cards(box, names)
		"season":
			var sc := _card(box, "Season" if not Career.exhibition() else "Exhibition")
			for ln in season_lines:
				sc.add_child(_label(String(ln), fs - 1, MAGENTA if String(ln).begins_with("SEASON") else Color(0.85, 0.9, 0.95)))
			if not Career.exhibition():
				_standings_card(box)
		"report":
			box.add_child(_label("How it went for %s. Green went well, red needs fixing." % names[0], fs - 2, DIM))
			_report_lines(box, Analysis.postgame(g, 0))
		"team":
			_box_score(box, stats, [1, 1], names)
		"p0", "p1":
			var t := int(_stats_tab.substr(1))
			g._track_ovr(false)
			_player_tables(box, pstats[t], 1, g.teams[t], g.ovr_track)
			_condition_table(box, g.teams[t], g.ovr_track)
		"plays":
			for t in 2:
				_calls_table(box, g.calls[t], names[t], t)
		"drives":
			_drives_table(box, g)
		"rules":
			var bt: Array = g.get_meta("brain_tally", [{}, {}])
			_rules_section(box, bt, g.coach_tally, [g.teams[0]["coach"], g.teams[1]["coach"]], [g.teams[0].get("dcoach", g.teams[0]["coach"]), g.teams[1].get("dcoach", g.teams[1]["coach"])])


var _final_for: Game = null


## Pay for the game: each club's total big, its lines as a two-column list, the purse after,
## and what its coach did with it.
func _pay_cards(box: Control, names: Array) -> void:
	if slips.is_empty():
		return
	_section(box, "Pay")
	for t in 2:
		var sl: Dictionary = slips[t]
		var pc := PanelContainer.new()
		var sb := flat(SURF2, 12)
		sb.border_color = TEAM_COL[t]
		sb.border_width_left = 5
		sb.set_content_margin_all(12)
		pc.add_theme_stylebox_override("panel", sb)
		box.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		pc.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		var nl := _label(String(names[t]), fs, Color.WHITE)
		nl.add_theme_font_override("font", BODY_B)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nl)
		head.add_child(_disp("+$" + _commas(int(sl["total"])), fs + 8, MAGENTA, false))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		v.add_child(grid)
		for l in sl["lines"]:
			var a := _label(String(l[0]), fs - 2, DIM)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(a)
			var b := _label("$" + _commas(int(l[1])), fs - 2, Color(0.9, 0.92, 0.95))
			b.autowrap_mode = TextServer.AUTOWRAP_OFF
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(b)
		var pl := _label("Purse now $" + _commas(int(sl.get("purse", Career.money(t)))), fs - 1, MAGENTA if t == 0 else Color(0.85, 0.88, 0.92))
		pl.add_theme_font_override("font", BODY_B)
		v.add_child(pl)
		for nline in sl.get("news", []):
			v.add_child(_label(String(nline), fs - 3, DIM))


func _standings_card(box: Control) -> void:
	var st := _card(box, "Standings")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	st.add_child(grid)
	var sn := Career.season()
	for h in ["Club", "W-L-T", "PF-PA", "OVR"]:
		var hl := _label(h, fs - 3, DIM)
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		if h == "Club":
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(hl)
	for r in Career.standings():
		var c := MAGENTA if r["you"] else Color(0.9, 0.92, 0.95)
		var n := _label(String(r["name"]), fs - 1, c)
		n.add_theme_font_override("font", BODY_B if r["you"] else BODY)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(n)
		for tx in [[Career._rec_text(r["rec"]), c], ["%d-%d" % [int(r["rec"]["pf"]), int(r["rec"]["pa"])], DIM]]:
			var gl := _label(tx[0], fs - 1, tx[1])
			gl.autowrap_mode = TextServer.AUTOWRAP_OFF
			grid.add_child(gl)
		var tmr: Dictionary = Career.team(0) if r["you"] else {}
		if not r["you"]:
			for cl in sn.get("clubs", []):
				if String(cl["name"]) == String(r["name"]):
					tmr = cl
		grid.add_child(_disp(str(int(Career.team_ratings(tmr)["ovr"])) if not tmr.is_empty() else "-", fs, c, false))


## A club's play calls as a table: play, times called, yards a call (green for good, red for bad).
func _calls_table(box: Control, calls: Dictionary, name: String, t: int) -> void:
	var cd := _card(box, name, TEAM_COL[t])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	cd.add_child(grid)
	for h in ["Play", "Calls", "Yds a call"]:
		var hl := _label(h, fs - 3, DIM)
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		if h == "Play":
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(hl)
	var ks := calls.keys()
	ks.sort_custom(func(a, b): return calls[a][0] > calls[b][0] or (calls[a][0] == calls[b][0] and float(calls[a][1]) > float(calls[b][1])))
	for k in ks:
		var n := int(calls[k][0])
		var y := float(calls[k][1]) / maxf(float(n), 1.0)
		var pl := _label(String(k), fs - 2, Color(0.9, 0.92, 0.95))
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		pl.clip_text = true
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(pl)
		var nl := _label(str(n), fs - 2, DIM)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(nl)
		var yl := _label("%.1f" % y, fs - 2, GOOD if y >= 6.0 else (BAD if y < 3.0 else Color(0.9, 0.92, 0.95)))
		yl.autowrap_mode = TextServer.AUTOWRAP_OFF
		yl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(yl)


## The drives as a table: whose, plays, yards and how it ended (scores in gold, giveaways red).
func _drives_table(box: Control, g: Game) -> void:
	var cd := _card(box, "Drives")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	cd.add_child(grid)
	for h in ["Team", "Plays", "Yds", "Result"]:
		var hl := _label(h, fs - 3, DIM)
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		if h == "Result":
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(hl)
	for d in g.drives:
		var t := int(d["team"])
		var res := String(d["result"])
		var tl := _disp(String(Team.NAMES[t]).to_upper(), fs - 1, TEAM_COL[t].lightened(0.25))
		grid.add_child(tl)
		for v in [str(int(d["plays"])), str(int(round(float(d["yards"]))))]:
			var l := _label(v, fs - 1, Color(0.9, 0.92, 0.95))
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
		var rc := MAGENTA if (res.contains("TD") or res == "FG") else (BAD if res in ["INT", "fumble", "downs", "safety", "blocked"] else DIM)
		var rl := _label(res if res != "" else "-", fs - 1, rc)
		rl.add_theme_font_override("font", BODY_B)
		rl.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(rl)


func _line_score(box: Control, names: Array, line: Array, score: Array) -> void:
	var grid := GridContainer.new()
	var nq: int = mini((line[0] as Array).size(), 5)
	grid.columns = 2 + nq
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for h in (["", "1", "2", "3", "4", "OT", "T"] if nq == 5 else ["", "1", "2", "3", "4", "T"]):
		var l := _label(h, fs - 1, CYAN)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for t in 2:
		var nl := _label(names[t], fs, FieldView.COLORS[t].lightened(0.4))
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(nl)
		for q in nq:
			var l := _label(str(line[t][q]), fs)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
		var tl := _label(str(score[t]), fs + 1, Color.WHITE)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(tl)


## Passing, rushing, receiving and defense for one side. `per` divides (games in a batch).
func _player_tables(box: Control, ps: Dictionary, per: int, team: Dictionary, track: Dictionary = {}) -> void:
	var v := func(slot: String, k: String) -> float: return float(ps[slot][k]) / float(per)
	var fmt := func(x: float) -> String: return str(int(round(x))) if per == 1 else "%.1f" % x
	_tbl_narrow = get_viewport().get_visible_rect().size.x < 520.0
	var who := func(slot: String) -> String:
		# the robot himself: number and name (and his position)
		var rb: Dictionary = (team.get("roster", {}) as Dictionary).get(slot, {})
		if not rb.is_empty():
			var nm := String(rb.get("name", slot))
			var parts := nm.split(" ")
			var short := ("%s. %s" % [parts[0].substr(0, 1), " ".join(parts.slice(1))]) if parts.size() > 1 else nm
			if per == 1:
				# on a phone his rating goes under his name, so the numbers keep their room
				return "%s (%s)  %s" % [short, slot, final_rating(rb, track)]
			return "%s (%s)" % [short, slot]
		var b: Brain = (team.get("brains", {}) as Dictionary).get(slot, null)
		return slot if b == null else "%s %s" % [slot, b.name.split(" ")[0]]
	if per > 1:
		box.add_child(_label("Per game, over %d games. LNG is the longest." % per, fs - 2, Color(0.8, 0.82, 0.85)))
	var tables := [
		["Passing", ["C/ATT", "YDS", "TD", "INT", "SK", "RTG"], func(s): return v.call(s, "att") > 0 or v.call(s, "sk") > 0,
			func(s): return ["%s/%s" % [fmt.call(v.call(s, "cmp")), fmt.call(v.call(s, "att"))], fmt.call(v.call(s, "pyd")), fmt.call(v.call(s, "ptd")), fmt.call(v.call(s, "int")), fmt.call(v.call(s, "sk")),
				"%.1f" % passer_rating(v.call(s, "cmp"), v.call(s, "att"), v.call(s, "pyd"), v.call(s, "ptd"), v.call(s, "int"))], "pyd"],
		["Rushing", ["CAR", "YDS", "AVG", "TD", "LNG"], func(s): return v.call(s, "car") > 0,
			func(s): return [fmt.call(v.call(s, "car")), fmt.call(v.call(s, "ryd")), "%.1f" % (float(ps[s]["ryd"]) / maxf(float(ps[s]["car"]), 1.0)), fmt.call(v.call(s, "rtd")), str(int(round(float(ps[s]["rlong"]))))], "ryd"],
		["Receiving", ["REC/TGT", "YDS", "AVG", "TD", "LNG"], func(s): return v.call(s, "tgt") > 0,
			func(s): return ["%s/%s" % [fmt.call(v.call(s, "rec")), fmt.call(v.call(s, "tgt"))], fmt.call(v.call(s, "recyd")), "%.1f" % (float(ps[s]["recyd"]) / maxf(float(ps[s]["rec"]), 1.0)), fmt.call(v.call(s, "rectd")), str(int(round(float(ps[s]["reclong"]))))], "recyd"],
		["Defense", ["TKL", "SK", "INT", "PBU", "BAT", "FF"], func(s): return Play.DEFENSE_SLOTS.has(s) and (v.call(s, "tkl") + v.call(s, "sack") + v.call(s, "dint") + v.call(s, "pbu") + v.call(s, "ff")) > 0,
			func(s): return [fmt.call(v.call(s, "tkl")), fmt.call(v.call(s, "sack")), fmt.call(v.call(s, "dint")), fmt.call(v.call(s, "pbu")), fmt.call(v.call(s, "bat")), fmt.call(v.call(s, "ff"))], "tkl"],
	]
	for tb in tables:
		var slots: Array = ps.keys().filter(tb[2])
		if slots.is_empty():
			continue
		var key: String = tb[4]
		slots.sort_custom(func(a, b): return float(ps[a][key]) > float(ps[b][key]))
		_section(box, tb[0])
		var grid := GridContainer.new()
		grid.columns = 1 + (tb[1] as Array).size()      # the name, then one column per stat
		grid.add_theme_constant_override("h_separation", 7 if _tbl_narrow else 12)
		grid.add_theme_constant_override("v_separation", 2)
		box.add_child(grid)
		var tf := fs - (3 if _tbl_narrow else 2)
		var hl := _label("", tf)
		grid.add_child(hl)
		for h in tb[1]:
			var l := _label(h, tf, CYAN)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
		for sl in slots:
			var nl := _label(who.call(sl), tf, Color(0.85, 0.9, 1))
			nl.autowrap_mode = TextServer.AUTOWRAP_OFF
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(nl)
			for cell in tb[3].call(sl):
				var l := _label(String(cell), tf)
				l.autowrap_mode = TextServer.AUTOWRAP_OFF
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				grid.add_child(l)


## "80 -3 +2 = 79": his overall at kickoff, what the hits took, what repairs gave back, and
## where that leaves him; just "80" when nothing changed. Second value: did he take damage.
## The NFL passer rating (0 to 158.3) from completions, attempts, yards, touchdowns, interceptions.
static func passer_rating(cmp: float, att: float, yds: float, td: float, ints: float) -> float:
	if att <= 0.0:
		return 0.0
	var a := clampf((cmp / att - 0.3) * 5.0, 0.0, 2.375)
	var b := clampf((yds / att - 3.0) * 0.25, 0.0, 2.375)
	var c := clampf(td / att * 20.0, 0.0, 2.375)
	var d := clampf(2.375 - ints / att * 25.0, 0.0, 2.375)
	return (a + b + c + d) / 6.0 * 100.0


## "60(-3)": his rating at the final whistle and how it moved over the game; just "60" when it
## ended where it started.
static func final_rating(r: Dictionary, track: Dictionary) -> String:
	var now := Robot.overall_if(r, "now")
	var tr: Dictionary = track.get(String(r.get("id", "")), {})
	if tr.is_empty():
		return str(now)
	var d := now - int(roundf(float(tr["start"])))
	return str(now) if d == 0 else "%d(%+d)" % [now, d]


static func ovr_change_text(r: Dictionary, track: Dictionary) -> Array:
	var tr: Dictionary = track.get(String(r.get("id", "")), {})
	if tr.is_empty():
		return [str(Robot.overall_if(r, "now")), false]
	var st := int(roundf(float(tr["start"])))
	var dm := int(roundf(float(tr["dmg"])))
	var up := int(roundf(float(tr["upg"])))
	var txt := "%d" % st
	if dm > 0:
		txt += " -%d" % dm
	if up > 0:
		txt += " +%d" % up
	if dm > 0 or up > 0:
		txt += " = %d" % int(roundf(float(tr["last"])))
	return [txt, dm > 0]


## Every robot on the side: his overall at kickoff, minus what the hits took, plus what
## repairs gave back, equals where he is now; then how worn each of his parts is.
var _cond_all := false
var _stats_mode := "live"
var _stats_snap := {}


func _condition_table(box: Control, team: Dictionary, track: Dictionary) -> void:
	var roster: Dictionary = team.get("roster", {})
	if roster.is_empty():
		return
	_section(box, "Condition")
	box.add_child(_label("Each robot's rating at the final whistle, with how it moved this game (red if he was hurt), then his parts' wear: at 100% a part comes off.", fs - 3, Color(0.75, 0.8, 0.85)))
	# one robot to a line - his name and overall - with his parts' wear wrapped underneath, so a
	# long list of wear never pushes the panel off a phone screen
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	box.add_child(grid)
	var rows: Array = []
	for slot in roster:
		rows.append([String(slot), roster[slot]])
	for r: Dictionary in team.get("bench", []):
		rows.append(["bench", r])
	# the damaged first (most hurt at the top); the unmarked only if asked for
	var hurt_of := func(r: Dictionary) -> float:
		var h := 0.0
		for k in Robot.PARTS:
			var pt: Dictionary = Robot.ensure_parts(r)[k]
			h += 1.0 - clampf(float(pt["hp"]) / float(Robot.TIER_HP.get(String(pt["tier"]), 100)), 0.0, 1.0)
		return h
	rows = rows.filter(func(x): return not (x[1] as Dictionary).is_empty())
	rows.sort_custom(func(a, b): return hurt_of.call(a[1]) > hurt_of.call(b[1]))
	var unmarked := rows.filter(func(x): return hurt_of.call(x[1]) < 0.001).size()
	if not _cond_all:
		rows = rows.filter(func(x): return hurt_of.call(x[1]) >= 0.001)
	var ft := _button(("Unmarked robots: shown (%d)" if _cond_all else "Unmarked robots: hidden (%d) - show them") % unmarked, func():
		_cond_all = not _cond_all
		if main.game != null:
			show_stats(main.game, _stats_mode, _stats_snap, _back), true)
	ft.button_pressed = _cond_all
	box.add_child(_wrap_button(ft))
	for row in rows:
		var r: Dictionary = row[1]
		if r.is_empty():
			continue
		var nm := String(r.get("name", ""))
		var bits := nm.split(" ")
		var short := ("%s. %s" % [bits[0].substr(0, 1), " ".join(bits.slice(1))]) if bits.size() > 1 else nm
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		grid.add_child(line)
		var nl := _label("%s (%s)" % [short, row[0]], fs - 2, Color(0.85, 0.9, 1))
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(nl)
		var oc := ovr_change_text(r, track)
		var o_txt := final_rating(r, track)
		var hit: bool = oc[1]
		var ol := _label(o_txt, fs - 2, Color(1.0, 0.55, 0.5) if hit else Color(0.85, 0.88, 0.92))
		ol.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(ol)
		var worn: Array = []
		var parts := Robot.ensure_parts(r)
		for k in Robot.PARTS:
			var pt: Dictionary = parts[k]
			var mx := float(Robot.TIER_HP.get(String(pt["tier"]), 100))
			var hp := float(pt["hp"])
			if hp <= 0.0:
				worn.append("%s OFF" % String(Robot.PART_LABEL[k]).to_lower())
			elif hp < mx - 0.5:
				worn.append("%s %d%%" % [String(Robot.PART_LABEL[k]).to_lower(), int(roundf(100.0 * (1.0 - hp / mx)))])
		var dl := _label("   " + (", ".join(worn) if not worn.is_empty() else "unmarked"), fs - 3, YELLOW if not worn.is_empty() else Color(0.6, 0.65, 0.7))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(dl)


func show_game_over(g: Game) -> void:
	show_stats(g, "final")


## After the game: who is damaged and what it costs, the coach's buttons, and the robot market.
## Between games: last week, the table, who is next, and getting the team ready - repairs,
## upgrades, the market - then Kick off.
## A card that holds a section: a dark tile with a small heading.
func _card(box: Control, head := "", accent := Color(0, 0, 0, 0)) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := flat(SURF2, 12, LINE, 1)
	sb.set_content_margin_all(12)
	if accent.a > 0.0:
		sb.border_color = accent
		sb.set_border_width_all(0)
		sb.border_width_left = 4
	pc.add_theme_stylebox_override("panel", sb)
	box.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	if head != "":
		v.add_child(_eyebrow(head))
	return v


## An award as a card: what it is in gold, who in bold, his club's colour down the side.
func _award_card(box: Control, head: String, b: Dictionary, side: String) -> void:
	var ours := String(b["team"]) == String(Career.team(0)["name"])
	var card := PanelContainer.new()
	var sb := flat(SURF2, 12)
	sb.border_color = TEAM_COL[0 if ours else 1]
	sb.border_width_left = 5
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	card.add_child(v)
	v.add_child(_eyebrow(head, MAGENTA))
	var nl := _label("%s %s" % [b["slot"], b["name"]], fs + 1, Color.WHITE)
	nl.add_theme_font_override("font", BODY_B)
	v.add_child(nl)
	v.add_child(_label("%s · %s" % [b["team"], Career.stat_line(b["stats"], side)], fs - 2, DIM))
	box.add_child(card)


## The matchup across the top: the two clubs on their colours, record and OVR, VS between.
func _matchup(box: Control, me: Dictionary, my_rec: Dictionary, opp: Dictionary) -> void:
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 0)
	box.add_child(hero)
	var teams := [[me, my_rec], [opp, opp.get("rec", {"w": 0, "l": 0, "t": 0})]]
	for t in 2:
		var tm: Dictionary = teams[t][0]
		var half := PanelContainer.new()
		var sb := flat(TEAM_COL[t].darkened(0.6), 0)
		if t == 0:
			sb.corner_radius_top_left = 14
			sb.corner_radius_bottom_left = 14
		else:
			sb.corner_radius_top_right = 14
			sb.corner_radius_bottom_right = 14
		sb.set_content_margin_all(12)
		half.add_theme_stylebox_override("panel", sb)
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hero.add_child(half)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		half.add_child(v)
		var al := HORIZONTAL_ALIGNMENT_LEFT if t == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		var nm := _disp(String(tm["name"]).to_upper(), fs + 4, Color.WHITE)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.horizontal_alignment = al
		v.add_child(nm)
		var rt := Career.team_ratings(tm)
		var big := _disp(str(int(rt["ovr"])), fs + 22, Color.WHITE, false)
		big.horizontal_alignment = al
		v.add_child(big)
		var sub := _label("OVR  ·  %s  ·  off %d  def %d" % [Career._rec_text(teams[t][1]), int(rt["off"]), int(rt["def"])], fs - 3, Color(1, 1, 1, 0.7))
		sub.horizontal_alignment = al
		v.add_child(sub)
		if t == 1:
			var sch := _label(Career.schemes_text(tm), fs - 3, Color(1, 1, 1, 0.6))
			sch.horizontal_alignment = al
			v.add_child(sch)


## Between games: the matchup and Kick off on top, then repairs, the scouting report as
## unit-against-unit bars, the table, last week and the market.
func open_next() -> void:
	Career.ensure()
	var sn := Career.season()
	var opp := Career.team(1)
	var me := Career.team(0)
	var box := _open("%s%s" % [Career.week_label(), _purse()])
	_matchup(box, me, sn.get("you", {"w": 0, "l": 0, "t": 0}), opp)
	var ko := _primary(_button("KICK OFF", func(): close_overlay(false); main.new_game(true)))
	box.add_child(ko)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for bd in [["Coach & plays", func(): open_teams(true)], ["Roster", func(): open_roster(0); _back = func(): open_next()], ["Menu", func(): main.show_menu()]]:
		var b := _button(bd[0], bd[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_garage(box, func(): open_next())
	# scouting: each unit against theirs as a bar, then their schemes
	var sc := _card(box, "Scouting report")
	var re := RegEx.new()
	re.compile("^(.*?) \\((\\d+) vs (\\d+)\\): (.*)$")
	for ln in Analysis.pregame(me, opp):
		var txt := String(ln[0])
		var col := GOOD if ln[1] == "good" else (BAD if ln[1] == "bad" else DIM)
		var m := re.search(txt)
		if m == null:
			var nl := _label(txt, fs - 2, col if ln[1] != "note" else Color(0.8, 0.83, 0.88))
			sc.add_child(nl)
			continue
		var head := m.get_string(1).replace("Your ", "").replace(" vs their ", "  vs  ")
		head = head[0].to_upper() + head.substr(1)
		var a := int(m.get_string(2))
		var b2 := int(m.get_string(3))
		var hr := HBoxContainer.new()
		sc.add_child(hr)
		var hl := _label(head, fs - 1, Color(0.94, 0.95, 0.97))
		hl.add_theme_font_override("font", BODY_B)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(hl)
		hr.add_child(_disp("%d" % a, fs + 2, TEAM_COL[0].lightened(0.25), false))
		var vsl := _label(" vs ", fs - 3, DIM)
		vsl.autowrap_mode = TextServer.AUTOWRAP_OFF
		hr.add_child(vsl)
		hr.add_child(_disp("%d" % b2, fs + 2, TEAM_COL[1].lightened(0.25), false))
		# a tug-of-war bar: your share against theirs, centred on even
		var bar := ProgressBar.new()
		bar.min_value = -10
		bar.max_value = 10
		bar.value = clampf(float(a - b2), -10.0, 10.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		bar.add_theme_stylebox_override("fill", flat(col if ln[1] != "note" else SURF3.lightened(0.2), 3))
		bar.add_theme_stylebox_override("background", flat(SURF3, 3))
		bar.value = 10.0 + clampf(float(a - b2), -10.0, 10.0)
		bar.min_value = 0
		bar.max_value = 20
		sc.add_child(bar)
		var adv := m.get_string(4)
		if adv != "even":
			sc.add_child(_label(adv[0].to_upper() + adv.substr(1), fs - 3, col))
	# the table
	var st := _card(box, "Standings")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	st.add_child(grid)
	for h in ["Club", "W-L-T", "PF-PA", "OVR"]:
		var hl2 := _label(h, fs - 3, DIM)
		hl2.autowrap_mode = TextServer.AUTOWRAP_OFF
		if h == "Club":
			hl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(hl2)
	for r in Career.standings():
		var c := MAGENTA if r["you"] else Color(0.9, 0.92, 0.95)
		var n := _label(String(r["name"]), fs - 1, c)
		n.add_theme_font_override("font", BODY_B if r["you"] else BODY)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(n)
		for tx in [[Career._rec_text(r["rec"]), c], ["%d-%d" % [int(r["rec"]["pf"]), int(r["rec"]["pa"])], DIM]]:
			var gl := _label(tx[0], fs - 1, tx[1])
			gl.autowrap_mode = TextServer.AUTOWRAP_OFF
			grid.add_child(gl)
		var tmr: Dictionary = me if r["you"] else {}
		if not r["you"]:
			for cl in sn.get("clubs", []):
				if String(cl["name"]) == String(r["name"]):
					tmr = cl
		grid.add_child(_disp(str(int(Career.team_ratings(tmr)["ovr"])) if not tmr.is_empty() else "-", fs, c, false))
	var results: Array = sn.get("results", [])
	if not results.is_empty():
		var lw := _card(box, "Last week")
		for ln in results.slice(maxi(results.size() - 2, 0)):
			lw.add_child(_label(String(ln), fs - 1, Color(0.85, 0.9, 0.95)))
	var potw: Dictionary = sn.get("potw", {})
	if not potw.is_empty():
		_section(box, "Players of the week")
		for side in ["off", "def"]:
			if potw.has(side):
				_award_card(box, "Offense" if side == "off" else "Defense", potw[side], side)
	if Career.season_over() and not (sn.get("tally", {}) as Dictionary).is_empty():
		_section(box, "Season awards")
		for aw in Career.season_awards():
			_award_card(box, String(aw[0]), aw[1], String(aw[1]["side"]))
	elif not (sn.get("tally", {}) as Dictionary).is_empty():
		var sl := _card(box, "Season leaders")
		for side in ["off", "def"]:
			var i := 0
			for r2 in Career.season_leaders(side):
				i += 1
				var ours := String(r2["team"]) == String(me["name"])
				sl.add_child(_label("%d. %s %s (%s) - %s" % [i, r2["slot"], r2["name"], r2["team"], Career.stat_line(r2["stats"], side)], fs - 2, MAGENTA if ours else Color(0.82, 0.86, 0.9)))
	_market(box, func(): open_next())


## Repairs: Fix everybody first (grey when the purse won't cover it), then each damaged robot.
func _garage(box: Control, refresh: Callable) -> void:
	var tm := Career.team(0)
	var all_cost := 0
	var who: Array = []
	for s in tm["starters"]:
		who.append([tm["starters"][s], s])
	for r0 in tm["bench"]:
		who.append([r0, String(r0["group"])])
	var hurt: Array = []
	for w in who:
		var c := Career.fix_all_cost(w[0])
		if c > 0:
			hurt.append([w[0], w[1], c])
			all_cost += c
	var gc := _card(box, "Repairs" if not hurt.is_empty() else "", WARN if not hurt.is_empty() else Color(0, 0, 0, 0))
	if hurt.is_empty():
		var ok := _label("Nobody is damaged. Ready to play.", fs - 1, GOOD)
		ok.add_theme_font_override("font", BODY_B)
		gc.add_child(ok)
	else:
		var fa := _button("Fix everybody  $%s" % _commas(all_cost), func():
			for w in who:
				for k in Robot.PARTS:
					if Career.fix_cost(w[0], k) > 0:
						Career.buy_repair(0, w[0], k)
			refresh.call())
		if Career.money(0) >= all_cost:
			_primary(fa, fs + 2)
		else:
			fa.disabled = true
			fa.text = "Fix everybody  $%s  (purse $%s)" % [_commas(all_cost), _commas(Career.money(0))]
		gc.add_child(fa)
		for h in hurt:
			var r: Dictionary = h[0]
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			gc.add_child(line)
			var badge := _disp(String(h[1]), fs - 1, Color(0.45, 0.68, 1.0), false)
			badge.custom_minimum_size.x = 36
			line.add_child(badge)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(v)
			var nl := _label(String(r["name"]), fs - 1, Color(0.94, 0.95, 0.97))
			nl.add_theme_font_override("font", BODY_B)
			v.add_child(nl)
			var lost := Robot.lost_parts(r)
			var cnd := Robot.condition(r)
			var dt := ("No " + ", ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))) if not lost.is_empty() \
				else "Condition %d%%" % int(roundf(100.0 * float(cnd[0]) / maxf(float(cnd[1]), 1.0)))
			var dl := _label(dt, fs - 3, BAD if not lost.is_empty() else WARN)
			dl.tooltip_text = _damage_text(r)
			v.add_child(dl)
			var rid := String(r["id"])
			var c2 := int(h[2])
			var fix := _button("Fix $%d" % c2, func():
				var rr: Dictionary = Career.find(rid).get("robot", {})
				if rr.is_empty():
					return
				for k in Robot.PARTS:
					if Career.fix_cost(rr, k) > 0:
						Career.buy_repair(0, rr, k)
				refresh.call())
			fix.disabled = Career.money(0) < c2
			fix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(fix)


## Upgrades and the robot market.
func _market(box: Control, refresh: Callable) -> void:
	var up := _card(box, "Upgrades")
	var ur := HBoxContainer.new()
	ur.add_theme_constant_override("separation", 6)
	up.add_child(ur)
	var rb := _button("Roster & upgrades", func(): open_roster(0); _back = refresh)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ur.add_child(rb)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.visible = _buys_open
	if Career.money(0) > 400 or Career.credit(0) > 0:
		var cb := _button("Coach buys  " + ("-" if _buys_open else "+"), func():
			_buys_open = not _buys_open
			refresh.call())
		cb.add_theme_color_override("font_color", MAGENTA)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ur.add_child(cb)
	up.add_child(inner)
	_spend_row(inner, 0, refresh)
	var mk := _card(box, "Robot market  ·  joins your bench")
	for r in Career.market():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		mk.add_child(row)
		var badge := _disp(String(r["group"]), fs - 1, Color(0.45, 0.68, 1.0), false)
		badge.custom_minimum_size.x = 36
		row.add_child(badge)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var nl := _label(String(r["name"]), fs - 1, Color(0.94, 0.95, 0.97))
		nl.add_theme_font_override("font", BODY_B)
		v.add_child(nl)
		v.add_child(_label("Armour %d  ·  %s" % [Robot.armour(r), Robot.tiers_text(r)], fs - 3, DIM))
		row.add_child(_disp(str(Robot.overall(r)), fs + 6, Color.WHITE, false))
		var rid := String(r["id"])
		var price := int(r["price"])
		var buy := _button("Buy $%d" % price, func():
			if Career.buy_robot(0, rid):
				toast("SIGNED", 1.4)
			refresh.call())
		buy.disabled = Career.money(0) < price
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(buy)


func _damage_text(r: Dictionary) -> String:
	var bits: Array = []
	for k in Robot.PARTS:
		var pt: Dictionary = r["parts"][k]
		if Robot.part_lost(r, k):
			bits.append("NO " + String(Robot.PART_LABEL[k]).to_upper())
		elif String(pt["tier"]) == "Junk":
			if bool(pt.get("spare", false)):
				bits.append("junk spare " + String(Robot.PART_LABEL[k]).to_lower())
		else:
			var mx := float(Robot.TIER_HP.get(String(pt["tier"]), 100))
			if float(pt["hp"]) < mx * 0.99:
				bits.append("%s %d%%" % [String(Robot.PART_LABEL[k]).to_lower(), int(100.0 * float(pt["hp"]) / mx)])
	return ", ".join(bits)


func _final_extras(box: Control, g: Game) -> void:
	_section(box, "Play calls (calls · yards a call)")
	for t in 2:
		box.add_child(_label(_calls_line(g.calls[t], Team.NAMES[t]), fs - 2))
	_section(box, "Drives")
	var ds := []
	for d in g.drives:
		ds.append("%s: %d plays, %d yds, %s" % [Team.NAMES[int(d["team"])], int(d["plays"]), int(round(float(d["yards"]))), d["result"]])
	box.add_child(_label("\n".join(ds), fs - 2))
	var bt: Array = g.get_meta("brain_tally", [{}, {}])
	_rules_section(box, bt, g.coach_tally, [g.teams[0]["coach"], g.teams[1]["coach"]], [g.teams[0].get("dcoach", g.teams[0]["coach"]), g.teams[1].get("dcoach", g.teams[1]["coach"])])


func _calls_line(calls: Dictionary, who: String) -> String:
	var parts := []
	var names := calls.keys()
	names.sort_custom(func(a, b): return calls[a][0] > calls[b][0])
	for n in names:
		parts.append("%s %d · %.1f" % [n, calls[n][0], float(calls[n][1]) / maxf(float(calls[n][0]), 1.0)])
	return "%s: %s" % [who, ",  ".join(parts)]


func _box_score(box: Control, stats: Array, per: Array, names: Array) -> void:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	box.add_child(g)
	var rows := [["", names[0], names[1]]]
	var f := func(t: int, k: String) -> float: return float(stats[t].get(k, 0.0)) / float(per[t])
	rows.append(["Points" if per[0] == 1 else "Points a game", "", ""])
	rows.append(["Plays", "%.1f" % f.call(0, "plays"), "%.1f" % f.call(1, "plays")])
	rows.append(["Yards", "%.0f" % f.call(0, "yards"), "%.0f" % f.call(1, "yards")])
	rows.append(["Pass C/A, yds (avg)", _pass_line(stats[0], per[0]), _pass_line(stats[1], per[1])])
	rows.append(["Rush car-yds (avg)", _rush_line(stats[0], per[0]), _rush_line(stats[1], per[1])])
	rows.append(["Sacks taken", "%.1f" % f.call(0, "sacks"), "%.1f" % f.call(1, "sacks")])
	rows.append(["Turnovers", "%.1f" % f.call(0, "turnovers"), "%.1f" % f.call(1, "turnovers")])
	rows.append(["  interceptions thrown", "%.1f" % f.call(0, "ints"), "%.1f" % f.call(1, "ints")])
	rows.append(["  fumbles lost", "%.1f" % f.call(0, "fumbles"), "%.1f" % f.call(1, "fumbles")])
	rows.append(["Returns (yds)", "%.1f (%.0f)" % [f.call(0, "returns"), f.call(0, "ret_yds")], "%.1f (%.0f)" % [f.call(1, "returns"), f.call(1, "ret_yds")]])
	rows.append(["3rd down", _rate(stats[0], "third_conv", "third_att"), _rate(stats[1], "third_conv", "third_att")])
	rows.append(["Big plays (20+)", "%.1f" % f.call(0, "explosive"), "%.1f" % f.call(1, "explosive")])
	rows.append(["Passes broken up (batted)", "%.1f (%.1f)" % [f.call(0, "pbu"), f.call(0, "bats")], "%.1f (%.1f)" % [f.call(1, "pbu"), f.call(1, "bats")]])
	rows.append(["Field goals", "%.1f/%.1f" % [f.call(0, "fg"), f.call(0, "fg_att")], "%.1f/%.1f" % [f.call(1, "fg"), f.call(1, "fg_att")]])
	rows.append(["Punts", "%.1f" % f.call(0, "punts"), "%.1f" % f.call(1, "punts")])
	rows.remove_at(1)
	for r in rows:
		for i in 3:
			var l := _label(String(r[i]), fs - 1, CYAN if i == 0 or r == rows[0] else Color(0.93, 0.93, 0.9))
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			g.add_child(l)


func _pass_line(s: Dictionary, n: int) -> String:
	var att := float(s.get("pass_att", 0))
	return "%.0f/%.0f, %.0f (%.1f)" % [float(s.get("comp", 0)) / n, att / n, float(s.get("pass_yds", 0)) / n, float(s.get("pass_yds", 0)) / maxf(att, 1.0)]


func _rush_line(s: Dictionary, n: int) -> String:
	var att := float(s.get("rush_att", 0))
	return "%.0f-%.0f (%.1f)" % [att / n, float(s.get("rush_yds", 0)) / n, float(s.get("rush_yds", 0)) / maxf(att, 1.0)]


func _rate(s: Dictionary, a: String, b: String) -> String:
	var d := float(s.get(b, 0))
	return "-" if d == 0 else "%.0f%%" % (100.0 * float(s.get(a, 0)) / d)


## The rules that did the work, per side: the coach's and the busiest brain rules.
func _rules_section(box: Control, brain_tally: Array, coach_tally: Array, coaches: Array, dcoaches: Array = []) -> void:
	_section(box, "Rules that decided (most used)")
	for t in 2:
		var c: Coach = coaches[t]
		var lines := []
		var ct: Dictionary = coach_tally[t]
		var cl := ct.keys()
		cl.sort_custom(func(a, b): return ct[a] > ct[b])
		for ln in cl.slice(0, 4):
			var dln := String(str(ln)).begins_with("d")
			var rc: Coach = (dcoaches[t] if dcoaches.size() > t else c) if dln else c
			lines.append("  %d× %s" % [ct[ln], _coach_rule(rc, int(String(str(ln)).trim_prefix("d")))])
		var bt: Dictionary = brain_tally[t]
		var flat := []
		for bn in bt:
			for ln in bt[bn]:
				flat.append([int(bt[bn][ln]), bn, int(ln)])
		flat.sort_custom(func(a, b): return a[0] > b[0])
		for f in flat.slice(0, 8):
			var b: Brain = Library.brain(f[1])
			lines.append("  %d× %s: %s" % [f[0], f[1], b.rule_text(f[2]) if b != null else str(f[2])])
		var dname := (dcoaches[t] as Coach).name if dcoaches.size() > t and dcoaches[t] != null and dcoaches[t] != c else ""
		var l := _label("%s (%s%s)\n%s" % [Team.NAMES[t], c.name, (" / " + dname) if dname != "" else "", "\n".join(lines)], fs - 2)
		box.add_child(l)


func _coach_rule(c: Coach, ln: int) -> String:
	for r in c.offense_rules + c.defense_rules:
		if int(r["line"]) == ln:
			return String(r["text"])
	return "line %d" % ln


func show_batch(agg: Dictionary, names: Array) -> void:
	var box := _open("Sim ×%d" % int(agg["n"]))
	var n := int(agg["n"])
	box.add_child(_label("%s won %d, %s won %d, %d tied.   Points a game %.1f - %.1f" % [names[0], agg["wins"][0], names[1], agg["wins"][1], agg["ties"], float(agg["points"][0]) / n, float(agg["points"][1]) / n], fs + 2))
	var sc := []
	for s in agg["scores"]:
		sc.append("%d-%d" % [s[0], s[1]])
	box.add_child(_label("Scores: " + ", ".join(sc), fs - 2, Color(0.8, 0.82, 0.85)))
	var avg_line := [[], []]
	for t in 2:
		for q in 4:
			avg_line[t].append(snappedf(float(agg["line"][t][q]) / n, 0.1))
	box.add_child(_label("Points a quarter", fs - 1, CYAN))
	_line_score(box, names, avg_line, [snappedf(float(agg["points"][0]) / n, 0.1), snappedf(float(agg["points"][1]) / n, 0.1)])
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	box.add_child(tabs)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	var teams_now := [Team.build(0, main.coaches[0], main.picks[0], "coach", main.defenses[0]), Team.build(1, main.coaches[1], main.picks[1], "coach", main.defenses[1])]
	var fill := func(tab: String) -> void:
		for ch in holder.get_children():
			ch.queue_free()
		if tab == "team":
			_box_score(holder, agg["stats"], [n, n], names)
		else:
			var t := int(tab.substr(1))
			_player_tables(holder, agg["pstats"][t], n, teams_now[t])
		for b in tabs.get_children():
			b.button_pressed = b.get_meta("tab") == tab
	for tab in [["team", "Team"], ["p0", "%s players" % Team.NAMES[0]], ["p1", "%s players" % Team.NAMES[1]]]:
		var b := _button(tab[1], func(): fill.call(tab[0]), true)
		b.set_meta("tab", tab[0])
		tabs.add_child(b)
	box.add_child(holder)
	fill.call("team")
	_section(box, "Play calls (calls · yards a call)")
	for t in 2:
		box.add_child(_label(_calls_line(agg["calls"][t], Team.NAMES[t]), fs - 2))
	var dcs: Array = [Library.defense(main.defenses[0]), Library.defense(main.defenses[1])]
	var ocs: Array = [main.game.teams[0]["coach"], main.game.teams[1]["coach"]] if main.game != null else [Library.coach(main.coaches[0]), Library.coach(main.coaches[1])]
	_rules_section(box, agg["brain_tally"], agg["coach_tally"], ocs, [dcs[0] if dcs[0] != null else ocs[0], dcs[1] if dcs[1] != null else ocs[1]])
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(_button("Teams", func(): open_teams()))


## ---- the start menu -------------------------------------------------------------------------

## A big gold button: the one thing to do next on a screen.
func _primary(b: Button, size := 0) -> Button:
	var sb := flat(MAGENTA, 11)
	sb.border_color = Color(0.66, 0.48, 0.08)
	sb.border_width_bottom = 4
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb if st != "hover" else _lit(sb))
	b.add_theme_font_override("font", DISP)
	b.add_theme_font_size_override("font_size", size if size > 0 else fs + 6)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.custom_minimum_size.y = 50
	return b


static func _lit(sb: StyleBoxFlat) -> StyleBoxFlat:
	var l := sb.duplicate() as StyleBoxFlat
	l.bg_color = sb.bg_color.lightened(0.1)
	return l


## A full-screen page of our own (the title screen), in place of a floating panel.
func _open_page() -> Control:
	_prev_crumbs = []
	close_overlay(false)
	Ux.panel("menu")
	_back = Callable()
	_cur_title = "Gridiron Career"
	_back_buttons = []
	var page := Panel.new()
	page.add_theme_stylebox_override("panel", flat(NIGHT, 0))
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(page)
	_overlay = page
	_close_btn = null
	main.overlay_changed(true)
	return page


## The title screen: the name, the next game as a matchup card with one gold button, and
## Exhibition / Sim lab under it. Cloud save and the rest are behind "Save code & settings".
func open_menu() -> void:
	Career.ensure()
	var page := _open_page()
	var vp := get_viewport().get_visible_rect().size
	# the field glow behind, faded to night
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.16, 0.05, 0.05, 1.0))
	gr.set_color(1, Color(NIGHT, 1.0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.25)
	gt.fill_to = Vector2(1.1, 0.9)
	glow.texture = gt
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(glow)
	var w := minf(vp.x - 32.0, 520.0)
	var col := VBoxContainer.new()
	col.position = Vector2((vp.x - w) * 0.5, 0)
	col.size = Vector2(w, vp.y)
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var gap := Control.new()
	gap.custom_minimum_size.y = maxf(vp.y * 0.08, 30.0)
	col.add_child(gap)
	var big := clampi(int(w / 6.0), 44, 84)
	var t1 := _disp("GRIDIRON", big)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_color_override("font_shadow_color", TEAM_COL[0])
	t1.add_theme_constant_override("shadow_offset_x", 0)
	t1.add_theme_constant_override("shadow_offset_y", 4)
	col.add_child(t1)
	var t2 := _disp("C A R E E R", int(big * 0.55), MAGENTA)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t2)
	var t3 := _eyebrow("Robot football  ·  eleven a side")
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t3)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	# the season card
	var card := PanelContainer.new()
	col.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var top := HBoxContainer.new()
	cv.add_child(top)
	var sn := Career.season()
	var you: Dictionary = Career.data["teams"][0]
	var rec := Career._rec_text(sn.get("you", {"w": 0, "l": 0, "t": 0}))
	var wk := _eyebrow("Season over" if Career.season_over() else "Season · " + Career.week_label())
	wk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(wk)
	top.add_child(_money_chip(int(Career.data["money"][0])))
	var mu := HBoxContainer.new()
	mu.add_theme_constant_override("separation", 10)
	cv.add_child(mu)
	var side := func(nm: String, sub: String, t: int) -> void:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := _disp(nm.to_upper(), fs + 5, TEAM_COL[t].lightened(0.15))
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if t == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(n)
		var s := _label(sub, fs - 2, DIM)
		s.horizontal_alignment = n.horizontal_alignment
		v.add_child(s)
		mu.add_child(v)
	side.call(String(you["name"]), "%s · OVR %d" % [rec, int(Career.team_ratings(you)["ovr"])], 0)
	if Career.season_over():
		var ch := _label("Champions: %s" % sn.get("champion", "?"), fs - 1, MAGENTA)
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mu.add_child(ch)
	else:
		var vs := _disp("VS", fs, Color(0.4, 0.45, 0.55))
		vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mu.add_child(vs)
		var opp: Dictionary = sn["clubs"][int(sn.get("opp", 0))]
		side.call(String(opp["name"]), "OVR %d" % int(Career.team_ratings(opp)["ovr"]) if opp.has("starters") else "", 1)
	var cont := _primary(_button("CONTINUE SEASON" if not Career.season_over() else "START NEXT SEASON", func(): main.choose_mode("season")))
	cv.add_child(cont)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var ex := _button("Exhibition", func(): Career.ensure(); Career.data["mode"] = "exhibition"; Career.new_exhibition(); main.choose_mode("exhibition"))
	var lab := _button("Sim lab", func(): main.choose_mode("sim"))
	# a new season, right here: tap twice (it wipes this one)
	var ns := _button("Sure? Tap again" if _confirm_new_season else "New season", func():
		if _confirm_new_season:
			_confirm_new_season = false
			Career.new_season()
			main.choose_mode("season")
		else:
			_confirm_new_season = true
			open_menu())
	if _confirm_new_season:
		ns.add_theme_color_override("font_color", BAD)
	for b in [ex, lab, ns]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 46
		b.add_theme_font_override("font", DISP)
		b.add_theme_font_size_override("font_size", fs + 3)
		row.add_child(b)
	if Career.data.has("exhibition"):
		var last := _button("Back to the last exhibition", func(): main.choose_mode("exhibition"))
		col.add_child(last)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	var cs := CloudSave.me
	var code_l := _label(("Cloud save  " + cs.ensure_code()) if cs != null else "", fs - 3, Color(0.45, 0.5, 0.6))
	code_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	foot.add_child(code_l)
	var more := _button("Save code & settings", func(): open_settings())
	more.flat = true
	more.add_theme_font_size_override("font_size", fs - 2)
	more.add_theme_color_override("font_color", DIM)
	foot.add_child(more)
	var pad := Control.new()
	pad.custom_minimum_size.y = 14
	col.add_child(pad)


## A gold coin and an amount: the purse.
func _money_chip(amount: int) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := flat(SURF2, 14, LINE, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	chip.add_child(h)
	var coin := Panel.new()
	coin.add_theme_stylebox_override("panel", flat(MAGENTA, 7, Color(1.0, 0.88, 0.5), 1))
	coin.custom_minimum_size = Vector2(14, 14)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin)
	h.add_child(_disp("$" + _commas(amount), fs + 1, Color.WHITE, false))
	return chip


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Cloud save, downloads and starting the season over: what used to crowd the menu.
func open_settings() -> void:
	var box := _open("Save code & settings")
	_cloud_section(box)
	_section(box, "Start over")
	box.add_child(_label("A new season wipes this one: a fresh draft, $5,000.", fs - 2, DIM))
	box.add_child(_button("Really wipe it? Tap again" if _confirm_new_season else "New season (wipes this one)", func():
		if _confirm_new_season:
			_confirm_new_season = false
			Career.new_season()
			main.choose_mode("season")
		else:
			_confirm_new_season = true
			open_settings()))
	_back = func(): main.show_menu()
	_refresh_nav.call_deferred()


## Cloud save: the save code, how it went, the link to keep, and loading another code.
func _cloud_section(box: Container) -> void:
	var cs := CloudSave.me
	if cs == null:
		return
	_section(box, "Cloud save")
	var code := cs.ensure_code()
	box.add_child(_label("Your save code: %s" % code, fs + 2, YELLOW))
	box.add_child(_label(cs.status_text(), fs - 2, Color(0.75, 0.8, 0.85)))
	box.add_child(_label("Every save goes to the cloud under this code. Keep the code (or the link) and your career is never lost: open the link, or type the code on another phone or computer.", fs - 2, Color(0.75, 0.8, 0.85)))
	var link := LineEdit.new()
	link.text = cs.link()
	link.editable = false
	link.add_theme_font_size_override("font_size", fs - 2)
	box.add_child(link)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	row.add_child(_button("Copy the link", func():
		DisplayServer.clipboard_set(cs.link())
		toast("Link copied", 1.2)))
	row.add_child(_button("Save to the cloud now", func():
		Career.save()
		CloudSave.me._due = 0.01
		toast("Saving...", 1.0)))
	var lr := HFlowContainer.new()
	lr.add_theme_constant_override("h_separation", 6)
	box.add_child(lr)
	var inp := LineEdit.new()
	inp.placeholder_text = "XXXX-XXXX-XXXX"
	inp.custom_minimum_size = Vector2(220, 0)
	inp.add_theme_font_size_override("font_size", fs)
	lr.add_child(inp)
	var msg := _label("", fs - 2, Color(1.0, 0.6, 0.5))
	lr.add_child(_button("Load this save code", func():
		msg.text = "Loading..."
		cs.load_code(inp.text, func(ok: bool, m: String): msg.text = "" if ok else m)))
	box.add_child(msg)
	box.add_child(_label("Loading a code replaces the career on this device with that one (yours stays safe in the cloud under your own code).", fs - 3, Color(0.7, 0.72, 0.75)))
	if OS.has_feature("web"):
		_section(box, "Download the game")
		box.add_child(_label("Play it as an app on a computer - the same game and the same cloud saves.", fs - 2, Color(0.75, 0.8, 0.85)))
		var dr := HFlowContainer.new()
		dr.add_theme_constant_override("h_separation", 6)
		box.add_child(dr)
		dr.add_child(_button("Mac", func(): OS.shell_open(CloudSave.SITE + "/downloads/gridiron-career-mac.zip")))
		dr.add_child(_button("Linux", func(): OS.shell_open(CloudSave.SITE + "/downloads/gridiron-career-linux.zip")))


## The sim lab's results: one game against each opponent.
func show_sim(games: Array) -> void:
	var agg := Batch.aggregate(games)
	var n := int(agg["n"])
	var me := String(Career.team(0)["name"])
	var box := _open("Sim lab: %d-%d-%d" % [agg["wins"][0], agg["wins"][1], agg["ties"]])
	box.add_child(_label("%s (coach %s) against %d opponents: won %d, lost %d, tied %d. Points a game %.1f - %.1f." % [me, main.coaches[0], n,
		agg["wins"][0], agg["wins"][1], agg["ties"], float(agg["points"][0]) / n, float(agg["points"][1]) / n], fs + 1))
	for g: Game in games:
		var o: Dictionary = g.get_meta("opp", {})
		var res := "W" if g.score[0] > g.score[1] else ("L" if g.score[0] < g.score[1] else "T")
		box.add_child(_label("   %s %d-%d  vs %s (%s)" % [res, g.score[0], g.score[1], o.get("name", "?"), Career.schemes_text(o)], fs - 1,
			Color(0.5, 0.95, 0.6) if res == "W" else (Color(1.0, 0.5, 0.5) if res == "L" else Color(0.9, 0.9, 0.9))))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	row.add_child(_button("Simulate again", func(): main.run_sim()))
	row.add_child(_button("Back to the lab", func(): main.new_game(false)))
	row.add_child(_button("New opponents", func(): Career.new_sim_opponents(); main.new_game(false)))
	row.add_child(_button("Menu", func(): main.show_menu()))
	var names := [me, "Opponents"]
	_section(box, "Box score (a game)")
	_box_score(box, agg["stats"], [n, n], names)
	_section(box, "Your players (a game)")
	_player_tables(box, agg["pstats"][0], n, Team.build(0, main.coaches[0], main.picks[0]))
	_section(box, "Your play calls (calls · yards a call)")
	box.add_child(_label(_calls_line(agg["calls"][0], me), fs - 2))


## ---- the roster and each robot ----------------------------------------------------------------

var _roster_team := 0
var _draft_armed := false
const SIDE_GROUPS := [["Offense", ["QB", "RB", "WR", "TE", "OL"]], ["Defense", ["DL", "LB", "CB", "S"]]]


var _roster_tab := "Offense"
var _buys_open := false
const TIER_COL := {"Junk": Color(0.5, 0.36, 0.28), "Stock": Color(0.55, 0.59, 0.66), "Mk II": Color(0.25, 0.7, 1.0),
	"Mk III": Color(0.73, 0.55, 1.0), "Prototype": Color(0.96, 0.72, 0.18), "lost": Color(1.0, 0.35, 0.31)}


func open_roster(t := -1) -> void:
	if t >= 0:
		_roster_team = t
	Career.ensure()
	var tm := Career.team(_roster_team)
	var keep_back := _back        # refreshing the roster (a purchase, a tab) keeps where Close goes
	var box := _open("%s · %s" % [tm["name"], Career.ratings_text(tm)])
	_back = keep_back
	var mine := _roster_team == 0
	# purse, coach buys, repairs
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 8)
	top.add_theme_constant_override("v_separation", 6)
	box.add_child(top)
	if Career.loaded:
		top.add_child(_money_chip(Career.money(_roster_team)))
		if Career.credit(_roster_team) > 0:
			var cl := _label("+ $%d credit" % Career.credit(_roster_team), fs - 2, MAGENTA)
			cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(cl)
	var buys := VBoxContainer.new()
	buys.add_theme_constant_override("separation", 6)
	buys.visible = _buys_open
	if mine and (Career.money(0) > 400 or Career.credit(0) > 0):
		var bb := _button("Coach buys  " + ("-" if _buys_open else "+"), func():
			_buys_open = not _buys_open
			open_roster())
		bb.add_theme_color_override("font_color", MAGENTA)
		top.add_child(bb)
		if Career.credit(0) > 0:
			buys.add_child(_button("Coach spends the credit", func(): _open_plan(0, false, "", func(): open_roster())))
		if Career.money(0) > 400:
			buys.add_child(_label("He keeps $400 back. Pick what he shops for:", fs - 2, DIM))
			var fr := GridContainer.new()
			fr.columns = 2
			fr.add_theme_constant_override("h_separation", 6)
			fr.add_theme_constant_override("v_separation", 6)
			buys.add_child(fr)
			for fk in Career.FOCUS:
				var fkey: String = fk
				var fb := _button(String(Career.FOCUS[fkey]["label"]).replace(" (", "\n("), func(): _open_plan(0, true, fkey, func(): open_roster()))
				fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				fb.add_theme_font_size_override("font_size", fs - 2)
				fr.add_child(fb)
	var hurt := 0
	for sl in tm["starters"]:
		var rr: Dictionary = tm["starters"][sl]
		if not rr.is_empty():
			var cnd := Robot.condition(rr)
			if not Robot.lost_parts(rr).is_empty() or float(cnd[0]) < float(cnd[1]) * 0.5:
				hurt += 1
	if hurt > 0:
		var hl := _label("%d need repair" % hurt, fs - 2, WARN)
		hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(hl)
	box.add_child(buys)
	# the tabs
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 4)
	box.add_child(seg)
	for tab in ["Offense", "Defense", "Kickers", "Bench"]:
		var tb := _button(tab, func(): _roster_tab = tab; open_roster(), true)
		tb.button_pressed = tab == _roster_tab
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", fs - 1)
		seg.add_child(tb)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	box.add_child(list)
	var starters: Dictionary = tm["starters"]
	match _roster_tab:
		"Offense", "Defense":
			for g in SIDE_GROUPS[0 if _roster_tab == "Offense" else 1][1]:
				for s2 in Play.GROUP_SLOTS.get(g, [g]):
					list.add_child(_robot_row(starters[s2], s2, true))
		"Kickers":
			var sp := Career.special(_roster_team)
			for s2 in ["K", "P"]:
				list.add_child(_robot_row(sp[s2], s2, true))
		"Bench":
			for r in tm["bench"]:
				list.add_child(_robot_row(r, "", true))
			if (tm["bench"] as Array).is_empty():
				list.add_child(_label("Nobody on the bench.", fs - 1, DIM))
	# the parts key
	var key := HFlowContainer.new()
	key.add_theme_constant_override("h_separation", 6)
	box.add_child(key)
	key.add_child(_label("Parts:", fs - 3, DIM))
	for tier in Robot.TIERS:
		var sw := Panel.new()
		sw.add_theme_stylebox_override("panel", flat(TIER_COL[tier], 2))
		sw.custom_minimum_size = Vector2(14, 5)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.add_child(sw)
		key.add_child(_label(tier, fs - 3, DIM))
	# other clubs and options, out of the way at the bottom
	_section(box, "Clubs")
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	box.add_child(tabs)
	for i2 in 2:
		var b := _button(String(Career.team(i2)["name"]) + (" (you)" if i2 == 0 else ""), func(): _draft_armed = false; open_roster(i2), true)
		b.button_pressed = i2 == _roster_team
		tabs.add_child(b)
	for c in Career.other_clubs():
		var cc: Dictionary = c
		tabs.add_child(_button(String(cc["name"]), func(): open_club(cc)))
	_section(box, "Options")
	var opts := HFlowContainer.new()
	opts.add_theme_constant_override("h_separation", 6)
	opts.add_theme_constant_override("v_separation", 6)
	box.add_child(opts)
	var auto_on := bool(Career.data.get("auto_lineup", true))
	var al := _button("Coach sets the lineup: %s" % ("on" if auto_on else "off"), func():
		Career.data["auto_lineup"] = not bool(Career.data.get("auto_lineup", true))
		if bool(Career.data["auto_lineup"]):
			Career.best_lineup(Career.team(0))
		Career.save(); main.library_changed(); open_roster(), true)
	al.button_pressed = auto_on
	opts.add_child(al)
	var fair := _button("Fair bodies: %s" % ("on" if Career.fair() else "off"), func():
		Career.set_fair(not Career.fair()); main.library_changed(); open_roster(), true)
	fair.button_pressed = Career.fair()
	opts.add_child(fair)
	var draft := _button("Are you sure? Tap again to scrap this team" if _draft_armed else "Draft a whole new team", func():
		if _draft_armed:
			_draft_armed = false
			Career.regenerate(_roster_team)
			main.library_changed()
		else:
			_draft_armed = true
		open_roster())
	opts.add_child(draft)
	box.add_child(_label("Tap a robot for his parts and upgrades. OVR is against his position: 60 is an average one of his kind. Fair bodies: everyone plays as a 60, so only the brains differ.", fs - 3, Color(0.5, 0.55, 0.62)))


## Report lines in colour: green went well, red needs fixing, grey to note.
func _report_lines(box: Control, lines: Array) -> void:
	for ln in lines:
		var col := Color(0.55, 0.95, 0.6) if ln[1] == "good" else (Color(1.0, 0.55, 0.5) if ln[1] == "bad" else Color(0.85, 0.88, 0.92))
		box.add_child(_label(("+ " if ln[1] == "good" else ("! " if ln[1] == "bad" else "- ")) + String(ln[0]), fs - 1, col))


## Any club's players, to look at: their schemes, record, ratings and every robot.
func open_club(c: Dictionary) -> void:
	var box := _open("%s players%s" % [c["name"], _purse()])
	_back = func(): open_roster()
	box.add_child(_label("%s · %s%s" % [Career.schemes_text(c), Career.ratings_text(c), ("  ·  record " + Career._rec_text(c["rec"])) if c.has("rec") else ""], fs, CYAN))
	var starters: Dictionary = c["starters"]
	for sg in SIDE_GROUPS:
		_section(box, sg[0])
		for g in sg[1]:
			for s in Play.GROUP_SLOTS.get(g, [g]):
				var b := _robot_row(starters[s], s, false)
				b.disabled = true
				box.add_child(b)
	_section(box, "Bench")
	for r in c["bench"]:
		var b2 := _robot_row(r, "", false)
		b2.disabled = true
		box.add_child(b2)


## A roster row: position badge, name over his six part pips (coloured by tier), and a big OVR
## with what is wrong under it.
func _robot_row(r: Dictionary, slot: String, from_roster := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := flat(SURF2 if st in ["hover", "pressed", "hover_pressed"] else Color(SURF1, 0.0), 10)
		b.add_theme_stylebox_override(st, sb)
	b.custom_minimum_size.y = 50
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -8
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", flat(SURF3, 7))
	badge.custom_minimum_size = Vector2(44, 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := _disp(slot if slot != "" else String(r["group"]), fs - 1, Color(0.45, 0.68, 1.0), false)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	h.add_child(badge)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 5)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mid)
	var nl := _label("#%d  %s" % [int(r["number"]), r["name"]], fs, Color(0.94, 0.95, 0.97))
	nl.add_theme_font_override("font", BODY_B)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(nl)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(pips)
	for k in Robot.PARTS:
		var pt: Dictionary = Robot.ensure_parts(r)[k]
		var tier := "lost" if Robot.part_lost(r, k) else String(pt["tier"])
		var pip := Panel.new()
		var c: Color = TIER_COL[tier]
		var f := clampf(float(pt["hp"]) / float(Robot.TIER_HP.get(String(pt["tier"]), 100)), 0.0, 1.0)
		if tier != "lost" and f < 0.5:
			c = c.darkened(0.45)          # worn: dimmer
		pip.add_theme_stylebox_override("panel", flat(c, 2))
		pip.custom_minimum_size = Vector2(16, 5)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", -3)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	var now := Robot.overall_if(r, "now")
	var full := Robot.overall(r)
	var oc := MAGENTA if now >= 70 else (Color.WHITE if now >= 65 else Color(0.85, 0.87, 0.9))
	var ol := _disp(str(now), fs + 9, oc, false)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(ol)
	var lost := Robot.lost_parts(r)
	var junk := 0
	for k in Robot.PARTS:
		if Robot.part_junk(r, k):
			junk += 1
	var note := ""
	if not lost.is_empty():
		note = "no " + ", ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))
	elif junk > 0:
		note = "junk x%d" % junk
	elif now < full:
		note = "%d hurt" % (now - full)
	if note != "":
		var nt := _label(note, fs - 4, BAD if not lost.is_empty() else WARN)
		nt.autowrap_mode = TextServer.AUTOWRAP_OFF
		nt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(nt)
	var id := String(r["id"])
	if from_roster:
		# Close on his page comes back to the roster (and Close there goes where it went before)
		b.pressed.connect(func():
			var roster_back := _back
			open_robot(id)
			_back = func(): open_roster(); _back = roster_back)
	else:
		b.pressed.connect(func(): open_robot(id))
	return b


## A robot's page: a turning model, his ratings and what each does, his brain, this game's stats.
func open_robot(id: String) -> void:
	var f := Career.find(id)
	if f.is_empty():
		return
	var r: Dictionary = f["robot"]
	var t: int = f["team"]
	var slot: String = f["slot"]
	var keep_back := _back        # buying a part reopens the page: keep where Close goes
	var box := _open("%s%s" % [Career.team(t)["name"], _purse()])
	_back = keep_back
	var hero := PanelContainer.new()
	var hsb := flat(Color(TEAM_COL[t].darkened(0.62), 1.0), 14)
	hsb.bg_color = TEAM_COL[t].darkened(0.68)
	hsb.border_color = TEAM_COL[t].darkened(0.3)
	hsb.border_width_bottom = 3
	hsb.content_margin_left = 6
	hsb.content_margin_right = 12
	hsb.content_margin_top = 6
	hsb.content_margin_bottom = 8
	hero.add_theme_stylebox_override("panel", hsb)
	box.add_child(hero)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	hero.add_child(top)
	# the model, turning slowly
	var svc := SubViewportContainer.new()
	var narrow := get_viewport().get_visible_rect().size.x < 520.0
	svc.custom_minimum_size = Vector2(130, 196) if narrow else Vector2(180, 250)
	svc.stretch = true
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	top.add_child(svc)
	var model: Dictionary = main.view.build_robot(String(r["group"]), t, int(r["number"]), Robot.ensure_parts(r))
	var turn := Node3D.new()
	sv.add_child(turn)
	turn.add_child(model["root"])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.35, 5.0)      # far enough back that he fits head to foot
	cam.fov = 38
	sv.add_child(cam)
	cam.look_at(Vector3(0, 1.2, 0))
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, 0.6, 0)
	key.light_energy = 1.6
	sv.add_child(key)
	var front := OmniLight3D.new()
	front.position = Vector3(1.2, 2.4, 3.0)
	front.light_energy = 2.5
	front.omni_range = 10.0
	sv.add_child(front)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.0, -2.5)
	rim.light_color = FieldView.NEON[t]
	rim.light_energy = 2.0
	rim.omni_range = 8.0
	sv.add_child(rim)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 1.8
	e.glow_enabled = true
	env.environment = e
	sv.add_child(env)
	var tw := turn.create_tween().set_loops()
	tw.tween_property(turn, "rotation:y", TAU, 8.0).from(0.0)
	# who he is
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 4)
	top.add_child(who)
	var pos_txt := (slot if slot == String(r["group"]) else "%s (%s)" % [slot, r["group"]]) if slot != "" else ("Bench · %s" % r["group"])
	who.add_child(_eyebrow("#%d  ·  %s" % [int(r["number"]), pos_txt], TEAM_COL[t].lightened(0.45)))
	var nm := _disp(String(r["name"]).to_upper(), fs + 9)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(nm)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 18)
	who.add_child(nums)
	var cond := Robot.condition(r)
	var cpct := int(roundf(100.0 * float(cond[0]) / maxf(float(cond[1]), 1.0)))
	var stat := func(v: String, label: String, c: Color, size: int) -> void:
		var v2 := VBoxContainer.new()
		v2.add_theme_constant_override("separation", -4)
		v2.alignment = BoxContainer.ALIGNMENT_END
		v2.add_child(_disp(v, size, c, false))
		var e2 := _eyebrow(label)
		e2.add_theme_font_size_override("font_size", fs - 5)
		v2.add_child(e2)
		nums.add_child(v2)
	var ovr_now := Robot.overall_if(r, "now")
	stat.call(str(ovr_now), "Overall", MAGENTA if ovr_now >= 70 else Color.WHITE, fs + 26)
	stat.call("%d%%" % cpct, "Condition", GOOD if cpct >= 75 else (WARN if cpct >= 40 else BAD), fs + 8)
	stat.call(str(Robot.armour(r)), "Armour", Color(0.85, 0.88, 0.92), fs + 8)
	if slot != "" and main.game != null:
		var br: Brain = (main.game.teams[t]["brains"] as Dictionary).get(slot, null)
		if br != null:
			var bl := _label("Brain: %s" % br.name, fs - 2, Color(0.9, 0.92, 0.95))
			bl.add_theme_font_override("font", BODY_B)
			bl.tooltip_text = br.about
			who.add_child(bl)
	if Career.fair():
		who.add_child(_label("Fair bodies on: he plays as a 60.", fs - 3, MAGENTA))
	# the ratings
	_section(box, "Ratings")
	for k in Robot.keys(r):
		var v := int(Robot.eff(r, k))
		var plus := int(Robot.bonus(r, k))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)
		var name_l := _label(String(Robot.LABEL[k]), fs - 2, DIM)
		name_l.custom_minimum_size.x = 84 if get_viewport().get_visible_rect().size.x < 520.0 else 110
		name_l.tooltip_text = String(Robot.RATING_HELP[k])
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(name_l)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = v
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := flat(GOOD if v >= 65 else (WARN if v >= 45 else BAD), 4)
		var bg := flat(SURF3, 4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		line.add_child(bar)
		var num := _disp(str(v) + (" +%d" % plus if plus > 0 else ""), fs + 1, CYAN if plus > 0 else Color(1, 1, 1), false)
		num.custom_minimum_size.x = 46
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(num)
		if k == "toughness" and Robot.rating(r, k) < 99.0:
			var tt := maxi(Career.team_of(r), 0)
			var ap := Career.armor_price(r)
			var ab := _button("Armour plating: +5 toughness ($%d)" % ap, func(): Career.buy_armor(tt, r); open_robot(id))
			ab.disabled = Career.money(tt) < ap
			var arow := HFlowContainer.new()
			arow.add_child(ab)
			box.add_child(arow)
	_parts_section(box, r, id)
	# this game
	if slot != "" and main.game != null:
		var ps: Dictionary = (main.game.pstats[t] as Dictionary).get(slot, {})
		_section(box, "This game")
		var bits: Array = []
		for k2 in ps:
			if float(ps[k2]) != 0.0:
				bits.append("%s %s" % [k2, str(int(ps[k2]))])
		box.add_child(_label(" · ".join(bits) if not bits.is_empty() else "Nothing yet.", fs - 2, Color(0.85, 0.88, 0.9)))
	# swap him, any time: a bench robot goes in for any slot, a starter comes out for anyone on the bench
	var grp := String(r["group"])
	if slot == "":
		_section(box, "Put him in")
		box.add_child(_label("At his own position, or one built much the same - his own first. He plays from the next snap.", fs - 3, Color(0.7, 0.74, 0.8)))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		box.add_child(row)
		var slots: Array = (Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS).duplicate()
		slots.sort_custom(func(a1, b1): return int(String(Play.SLOT_GROUP[a1]) == grp) > int(String(Play.SLOT_GROUP[b1]) == grp))
		for s in slots:
			if not Career.fits(r, s):
				continue
			var out: Dictionary = Career.roster(t)[s]
			var b := _button("%s: for #%d %s (%d)" % [s, int(out["number"]), out["name"], Robot.overall(out)], func():
				Career.swap_any(Career.roster(t), Career.team(t)["bench"], s, id); Career.save(); open_robot(id))
			if String(Play.SLOT_GROUP[s]) == grp:
				b.add_theme_color_override("font_color", YELLOW)
			row.add_child(b)
	else:
		_section(box, "Take him out")
		box.add_child(_label("Bring in a bench robot who can play here - his position first. From the next snap.", fs - 3, Color(0.7, 0.74, 0.8)))
		var row2 := HFlowContainer.new()
		row2.add_theme_constant_override("h_separation", 6)
		row2.add_theme_constant_override("v_separation", 6)
		box.add_child(row2)
		var bench: Array = (Career.team(t)["bench"] as Array).duplicate()
		bench.sort_custom(func(x, y): return int(String(x["group"]) == String(Play.SLOT_GROUP[slot])) * 1000 + Robot.effective_overall(x) > int(String(y["group"]) == String(Play.SLOT_GROUP[slot])) * 1000 + Robot.effective_overall(y))
		for bb: Dictionary in bench:
			if not Career.fits(bb, slot):
				continue
			var bid := String(bb["id"])
			var lost := Robot.lost_parts(bb)
			var b2 := _button("#%d %s, %s %d%s" % [int(bb["number"]), bb["name"], bb["group"], Robot.overall(bb), (" (no %s)" % ", ".join(lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower()))) if not lost.is_empty() else ""], func():
				Career.swap_any(Career.roster(t), Career.team(t)["bench"], slot, bid); Career.save(); open_robot(bid))
			if String(bb["group"]) == String(Play.SLOT_GROUP[slot]):
				b2.add_theme_color_override("font_color", YELLOW)
			row2.add_child(b2)
	if t == 0:
		_sell_section(box, r, id)
	var back := HFlowContainer.new()
	box.add_child(back)
	back.add_child(_button("« Back to Roster", func():
		if _back.is_valid():
			close_overlay()
		else:
			open_roster(t)))



## A long button that wraps onto two lines rather than widen the page past a phone's screen.
func _wrap_button(b: Button) -> Button:
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = minf(get_viewport().get_visible_rect().size.x - 80.0, 420.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## Sell him to a rival club, scrap him for parts, or trade him for one of theirs.
func _sell_section(box: Control, r: Dictionary, id: String) -> void:
	_section(box, "Sell or trade")
	var why := Career.cant_part_with(0, r)
	if why != "":
		box.add_child(_label(why, fs - 1, Color(0.85, 0.75, 0.6)))
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	var sv := Career.scrap_value(r)
	row.add_child(_button("Scrap for parts: $%d" % sv, func():
		var got := Career.scrap(0, r)
		main.library_changed()
		toast("SCRAPPED\n+$%d" % got, 1.8)
		open_roster(0)))
	for c in Career.dealers():
		var offer := Career.sell_offer(r, c)
		var can := Career._club_money(c) >= offer
		var b := _button("Sell to %s: $%d%s%s" % [c["name"], offer, " (he'd start for them)" if Career.would_start(r, c) else "", "" if can else " - can't afford it"], func():
			if Career.sell_to(0, r, c):
				main.library_changed()
				toast("SOLD\nto %s, +$%d" % [c["name"], offer], 1.8)
				open_roster(0))
		_wrap_button(b)
		b.disabled = not can
		if not can:
			b.tooltip_text = "%s can't afford him ($%d in their purse)" % [c["name"], Career._club_money(c)]
		row.add_child(b)
	for c in Career.dealers():
		row.add_child(_wrap_button(_button("Trade with %s..." % c["name"], func(): _open_trade(r, id, c))))
	if Career.dealers().is_empty():
		box.add_child(_label("No other clubs to deal with here: scrap is the only sale.", fs - 2, Color(0.75, 0.8, 0.85)))


## Their robots at his position: what each is worth against him, and the deal.
func _open_trade(r: Dictionary, id: String, c: Dictionary) -> void:
	var g := String(r.get("group", ""))
	var box := _open("Trade with %s%s" % [c["name"], _purse()])
	_back = func(): open_robot(id)
	box.add_child(_label("Your %s %s (%s, OVR %d, worth $%d) for one of their %s players. They take the deal if what they get is worth at least what they give; if not, you add the difference in cash." % [g, r["name"], g, Robot.overall_if(r, "now"), Career.robot_price(r), g], fs - 1, Color(0.85, 0.88, 0.92)))
	var theirs: Array = []
	for s in c["starters"]:
		var x: Dictionary = c["starters"][s]
		if not x.is_empty() and String(x.get("group", "")) == g:
			theirs.append([x, s])
	for x in c["bench"]:
		if String(x.get("group", "")) == g:
			theirs.append([x, "bench"])
	if theirs.is_empty():
		box.add_child(_label("They have no %s to trade." % g, fs, YELLOW))
	for pair in theirs:
		var x: Dictionary = pair[0]
		var cash := Career.trade_gap(r, x)
		var line := "%s (%s) OVR %d, worth $%d - %s" % [x["name"], pair[1], Robot.overall_if(x, "now"), Career.robot_price(x), ("straight swap" if cash == 0 else "you add $%d" % cash)]
		var b := _button(line, func():
			if Career.trade(0, r, c, x):
				main.library_changed()
				toast("TRADED\n%s for %s" % [r["name"], x["name"]], 2.0)
				open_roster(0))
		b.disabled = Career.money(0) < cash
		box.add_child(_wrap_button(b))


## ---- broken robots -----------------------------------------------------------------------------

## Your robots that lost parts: for each, put in the best sub, bolt on junk, or play on.
func open_injuries(slots: Array) -> void:
	var box := _open("Broken robots" + _purse())
	box.add_child(_label("Parts came off on the field. Decide for each, then the game goes on. Each choice shows what his overall would be; junk spares run $12 (an arm) to $25 (a core).", fs - 2, Color(0.8, 0.83, 0.88)))
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 6)
	box.add_child(top)
	var pl := _label("Purse $%d" % Career.money(0), fs + 1, YELLOW)
	pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(pl)
	top.add_child(_button("Box score", func(): show_stats(main.game, "live", {}, func(): open_injuries(main._broken_mine()))))
	var tm: Dictionary = main.game.teams[0]
	for s in slots:
		var r: Dictionary = tm["roster"][s]
		var lost := Robot.lost_parts(r)
		var names: Array = lost.map(func(k): return String(Robot.PART_LABEL[k]).to_lower())
		var junk_cost := 0
		for k in lost:
			junk_cost += Career.junk_price(k)
		var o_full := Robot.overall_if(r, "healthy")
		var o_now := Robot.overall_if(r, "now")
		var o_junk := Robot.overall_if(r, "junk")
		_section(box, "%s  #%d %s - no %s" % [s, int(r["number"]), r["name"], " or ".join(names)])
		box.add_child(_label("Overall %d -> %d without %s (-%d)   ·   with junk %d   ·   with new %d" % [o_full, o_now, "them" if lost.size() > 1 else "it", o_full - o_now, o_junk, o_full], fs, YELLOW))
		var help: Array = []
		for k in lost:
			help.append(String(Robot.PART_HELP[k]))
		box.add_child(_label(" ".join(help), fs - 3, Color(0.7, 0.74, 0.8)))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		box.add_child(row)
		var jb := _button("Bolt on junk %s ($%d) - OVR %d" % [" and ".join(names), junk_cost, o_junk], func(): main.injury_choice(s, "junk"))
		jb.disabled = Career.money(0) < junk_cost
		row.add_child(jb)
		if Career.money(0) < junk_cost and not Robot.can_play(r):
			var any_sub := false
			for bb in Career.team(0)["bench"]:
				if Robot.can_play(bb) and Career.fits(bb, s):
					any_sub = true
			if not any_sub:
				row.add_child(_button("Emergency junk (purse empty, no one on the bench)", func(): main.injury_choice(s, "emergency")))
		var cost := 0
		for k in lost:
			cost += Career.repair_cost(r, k)
		var buy := _button("New %s ($%d) - OVR %d" % [" and ".join(names), cost, o_full], func(): main.injury_choice(s, "buy"))
		buy.disabled = Career.money(0) < cost
		row.add_child(buy)
		if Robot.can_play(r):
			row.add_child(_button("Play on without it - OVR %d" % o_now, func(): main.injury_choice(s, "play_on")))
		else:
			row.add_child(_label("He can't play like this.", fs - 2, MAGENTA))
		# or anyone healthy off the bench, from any position - his own kind first
		var subs: Array = []
		for b: Dictionary in tm.get("bench", []):
			if Robot.can_play(b) and Career.fits(b, s):
				subs.append(b)
		var grp := String(Play.SLOT_GROUP[s])
		subs.sort_custom(func(x, y): return Robot.overall_at(x, grp) > Robot.overall_at(y, grp))
		if not subs.is_empty():
			box.add_child(_label("Or put in from the bench - each shown with how he would rate as a %s, best first:" % grp, fs - 2, CYAN))
			var srow := HFlowContainer.new()
			srow.add_theme_constant_override("h_separation", 6)
			srow.add_theme_constant_override("v_separation", 6)
			box.add_child(srow)
			for b: Dictionary in subs:
				var bid := String(b["id"])
				var tag := "" if String(b["group"]) == grp else "  (plays %s)" % b["group"]
				var bo := Robot.overall_at(b, grp)
				var better := "  (better)" if bo > maxi(o_now, o_junk) else ""
				srow.add_child(_button("#%d %s, %s - as %s %d%s" % [int(b["number"]), b["name"], b["group"], grp, bo, better], func(): main.injury_choice(s, "sub:" + bid)))


func _parts_section(box: Control, r: Dictionary, id: String) -> void:
	_section(box, "Parts")
	var parts := Robot.ensure_parts(r)
	var grid := GridContainer.new()
	var narrow := get_viewport().get_visible_rect().size.x < 520.0
	grid.columns = 3 if narrow else 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var tu := maxi(Career.team_of(r), 0)
	var small := func(b: Button, gold := true) -> Button:
		b.add_theme_font_size_override("font_size", fs - 3)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if gold:
			var sb := flat(Color(0, 0, 0, 0), 8, MAGENTA, 1)
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", _lit(sb))
			b.add_theme_color_override("font_color", MAGENTA)
		return b
	for k in Robot.PARTS:
		var pt: Dictionary = parts[k]
		var hp := float(pt["hp"])
		var mx := float(Robot.TIER_HP.get(String(pt["tier"]), 100))
		var tile := PanelContainer.new()
		var tsb := flat(SURF1, 12, LINE, 1)
		tsb.set_content_margin_all(8)
		tile.add_theme_stylebox_override("panel", tsb)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		tile.add_child(v)
		var pl := _eyebrow(String(Robot.PART_LABEL[k]).replace("Left ", "L ").replace("Right ", "R "))
		pl.add_theme_font_size_override("font_size", fs - 4)
		pl.tooltip_text = String(Robot.PART_HELP.get(k, ""))
		pl.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(pl)
		if hp <= 0.0:
			v.add_child(_disp("GONE", fs + 2, BAD))
			var jk: Button = small.call(_button("Junk $%d" % Career.junk_price(k), func(): Career.buy_junk(Career.team_of(r), r, k); open_robot(id)), false)
			jk.disabled = Career.money(tu) < Career.junk_price(k)
			v.add_child(jk)
			var nb: Button = small.call(_button("New $%d" % Career.repair_cost(r, k), func(): Career.buy_repair(Career.team_of(r), r, k); open_robot(id)))
			nb.disabled = Career.money(tu) < Career.repair_cost(r, k)
			v.add_child(nb)
			continue
		var tier := String(pt["tier"])
		var tl := _disp(tier, fs + 2, TIER_COL.get(tier, Color.WHITE).lightened(0.15))
		tl.tooltip_text = "%d / %d condition" % [int(hp), int(mx)]
		tl.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(tl)
		var bar := ProgressBar.new()
		bar.max_value = mx
		bar.value = hp
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(40, 5)
		var f := hp / mx
		bar.add_theme_stylebox_override("fill", flat(GOOD if f > 0.6 else (WARN if f > 0.3 else BAD), 3))
		bar.add_theme_stylebox_override("background", flat(SURF3, 3))
		v.add_child(bar)
		if hp < mx and tier != "Junk":
			var fc := Career.repair_cost(r, k)
			var fb: Button = small.call(_button("Fix $%d" % fc, func(): Career.buy_repair(tu, r, k); open_robot(id)), false)
			fb.add_theme_color_override("font_color", WARN)
			fb.disabled = Career.money(tu) < fc
			v.add_child(fb)
		var nt := Career.next_tier(r, k)
		if nt != "":
			var up := Career.upgrade_price(k, nt)
			var ub: Button = small.call(_button("%s $%d" % [nt.replace("Prototype", "Proto"), up], func(): Career.buy_upgrade(tu, r, k); open_robot(id)))
			ub.disabled = Career.upgrade_funds(tu) < up
			ub.tooltip_text = "Upgrade to %s: +%d to %s, %d condition" % [nt, int(Robot.TIER_BONUS[nt]), ", ".join(Robot.PART_RATINGS[k]), int(Robot.TIER_HP[nt])]
			v.add_child(ub)
		else:
			var mxl := _label("Maxed", fs - 3, DIM)
			v.add_child(mxl)
	box.add_child(_label("Upgrades: Mk II +6, Mk III +12, Prototype +20 to what a part carries (an arm or leg half), and more condition.", fs - 4, Color(0.5, 0.55, 0.62)))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	var t := maxi(Career.team_of(r), 0)
	var all_cost := Career.repair_all_cost(r)
	row.add_child(_money_chip(Career.money(t)))
	if all_cost > 0:
		var rb := _button("Repair everything ($%d)" % all_cost, func():
			if Career.spend(t, all_cost):
				for k in Robot.PARTS:
					Robot.repair(r, k)
				Career.save()
			open_robot(id))
		rb.disabled = Career.money(t) < all_cost
		row.add_child(rb)



## Upgrade money: spend it yourself on the robot pages, or let the coach spend it.
## The coach's plan before he spends: each robot he would upgrade, which parts, what it does
## to his overall and what it costs; then buy it or go back.
func _open_plan(t: int, purse: bool, focus: String, refresh: Callable) -> void:
	var seed := randi() % 1000000 + 1
	var plan := Career.coach_plan(t, purse, 400, focus, seed)
	var what := "the credit" if not purse else String(Career.FOCUS[focus]["label"])
	var box := _open("Coach's plan: %s%s" % [what, _purse()])
	var rows: Array = plan["rows"]
	var cost := int(plan["cost"])
	var from_credit := mini(Career.credit(t), cost)
	box.add_child(_label("He has $%d to spend%s. This would cost $%d%s, leaving $%d in the purse." % [int(plan["budget"]),
		" (keeping $400 back)" if purse else "", cost, (" ($%d of it credit)" % from_credit) if from_credit > 0 else "",
		Career.money(t) - (cost - from_credit)], fs, YELLOW))
	if rows.is_empty():
		box.add_child(_label("Nothing he can buy with that: every part he'd look at is maxed out or costs more than he has.", fs - 1, Color(0.85, 0.88, 0.92)))
	var gain := 0
	for r in rows:
		gain += int(r["after"]) - int(r["before"])
		var nm := String(r["name"])
		var bits := nm.split(" ")
		var short := ("%s. %s" % [bits[0].substr(0, 1), " ".join(bits.slice(1))]) if bits.size() > 1 else nm
		var per := float(int(r["after"]) - int(r["before"])) * 100.0 / maxf(float(r["cost"]), 1.0)
		box.add_child(_label("%s (%s)   OVR %d -> %d (%+d)   $%d   (%.1f OVR per $100)" % [short, r["slot"], int(r["before"]), int(r["after"]), int(r["after"]) - int(r["before"]), int(r["cost"]), per], fs, Color(0.85, 0.95, 1.0)))
		box.add_child(_label("    " + ", ".join(r["parts"]), fs - 2, Color(0.75, 0.8, 0.88)))
		if not (r.get("gains", []) as Array).is_empty():
			box.add_child(_label("    " + ", ".join(r["gains"]), fs - 2, Color(0.55, 0.95, 0.6)))
	if not rows.is_empty():
		box.add_child(_label("In all: %d robots, %+d overall between them, $%d." % [rows.size(), gain, cost], fs - 1, CYAN))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	if not rows.is_empty():
		var buy := _button("Buy it ($%d)" % cost, func():
			var news := Career.coach_spend(t, purse, 400, focus, seed)
			refresh.call()
			toast("COACH %s" % String(news[0]).to_upper() if not news.is_empty() else "NOTHING TO BUY", 2.4))
		buy.add_theme_font_size_override("font_size", fs + 2)
		row.add_child(buy)
	row.add_child(_button("Back", func(): refresh.call()))


func _spend_row(box: Control, t: int, refresh: Callable) -> void:
	var cr := Career.credit(t)
	if cr > 0:
		box.add_child(_label("Upgrade credit $%d - spend it yourself on the robot pages (tap a robot, then a part's upgrade button), or let the coach:" % cr, fs - 1, YELLOW))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	if cr > 0:
		row.add_child(_button("Coach spends the credit", func(): _open_plan(t, false, "", refresh)))
	if Career.money(t) > 400:
		if cr <= 0:
			box.move_child(row, box.get_child_count() - 1)
			var hint := _label("Spend the purse on upgrades yourself on the robot pages (tap a robot, then a part's upgrade button), or let the coach:", fs - 2, Color(0.8, 0.83, 0.88))
			box.add_child(hint)
			box.move_child(hint, row.get_index())
		box.add_child(_label("Coach buys upgrades (keeps $400) - for:", fs - 2, Color(0.8, 0.83, 0.88)))
		var fr := HFlowContainer.new()
		fr.add_theme_constant_override("h_separation", 6)
		fr.add_theme_constant_override("v_separation", 6)
		box.add_child(fr)
		for fk in Career.FOCUS:
			var fkey: String = fk
			fr.add_child(_button(String(Career.FOCUS[fkey]["label"]), func(): _open_plan(t, true, fkey, refresh)))
