#u_icontroller.gd
extends CanvasLayer

# Small radial "pie" indicator that unfills clockwise to show the
# per-turn grace period (couch-versus buffer) draining. fraction 1.0
# means the full buffer is still available; 0.0 means it's gone and
# the clock is now actively counting down.
class GraceRing:
	extends Control
	var fraction: float = 1.0
	var ring_color: Color = Color("#38bdf8")

	func _draw():
		var r = min(size.x, size.y) / 2.0 - 2.0
		if r <= 0.0:
			return
		var center = size / 2.0
		# Dim background track so the ring is visible even at fraction 0.
		draw_arc(center, r, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 3.0, true)
		if fraction > 0.001:
			var start_angle = -PI / 2.0
			var end_angle = start_angle + TAU * fraction
			draw_arc(center, r, start_angle, end_angle, 32, ring_color, 3.0, true)

	func set_fraction(f: float):
		fraction = clampf(f, 0.0, 1.0)
		queue_redraw()

var turn_label: Label
var turn_counter_label: Label
var eval_label: Label
var status_label: Label
var players_label: Label
var new_game_btn: Button
var info_btn: Button
var clear_drawings_btn: Button
var hint_toggle: CheckButton
var white_clock_label: Label
var black_clock_label: Label
var white_grace_ring: Control
var black_grace_ring: Control

var turn_number: int = 1

# Clock display state — persists across UI rebuilds (resize) since
# _create_ui() rebuilds the label nodes from scratch each time.
var _clocks_visible: bool = false
var _last_white_time: float = 0.0
var _last_black_time: float = 0.0

# Low-time warning thresholds, in seconds.
const CLOCK_WARN_SECONDS := 60.0
const CLOCK_DANGER_SECONDS := 30.0


# Modern dark theme colors
var bg_color = Color("#0f172a")
var panel_color = Color("#1e293b")
var border_color = Color("#334155")
var text_primary = Color("#f1f5f9")
var text_secondary = Color("#94a3b8")
var text_accent = Color("#38bdf8")
var accent_color = Color("#3b82f6")
var white_color = Color("#e2e8f0")
var black_color = Color("#94a3b8")
var clock_warn_color = Color("#f59e0b")
var clock_danger_color = Color("#ef4444")
var board_drawer: Control = null
# Layout cache (recalculated on resize)
var _layout: Dictionary = {}

func _ready():
	layer = 1
	_recalc_layout()
	_create_ui()
	_create_board_drawer()
	get_viewport().size_changed.connect(_on_viewport_resized)
	var game_state = get_parent().get_node("GameState")
	game_state.turn_changed.connect(_on_turn_changed)
	game_state.game_ended.connect(_on_game_ended)
	game_state.thinking_started.connect(_on_thinking)
	game_state.thinking_finished.connect(_on_thinking_done)

func _on_viewport_resized():
	_recalc_layout()
	_rebuild_ui()
	_update_board_drawer()

func _recalc_layout():
	var vp = get_viewport().get_visible_rect().size
	var h = vp.y
	var w = vp.x
	
	# Board takes up available height minus padding, or 65% of width
	var board_size = min(h - 40, w * 0.62)
	board_size = max(board_size, 360)
	
	var panel_x = board_size + max(50, int(board_size * 0.035))
	var panel_w = w - panel_x - 12
	panel_w = max(panel_w, 220)
	
	var sc = board_size / 700.0
	
	_layout = {
		"vp": vp,
		"board_size": board_size,
		"panel_x": panel_x,
		"panel_w": panel_w,
		"panel_h": h,
		"scale": sc,
		"pad": int(20 * sc),
		"line_h": int(24 * sc),
		"title_y": int(16 * sc),
		"turn_card_y": int(100 * sc),
		"clock_y": int(150 * sc),
		"eval_y": int(210 * sc),
		"players_y": int(250 * sc),
		"hint_y": int(330 * sc),
		"new_game_y": int(390 * sc),
		"info_btn_y": int(444 * sc),
		"clear_drawings_y": int(484 * sc),
		"status_y": int(530 * sc),
		"graph_y": int(h - 160 * sc),
		"graph_w": int(panel_w - 32),
		"graph_h": int(100 * sc),
		"graph_margin": int(10 * sc),
	}

func _create_board_drawer():
	var drawer = preload("res://brddrwr.gd").new()
	drawer.name = "brddrwr"
	add_child(drawer)
	board_drawer = drawer

func align_drawer_to_board(board_global_pos: Vector2):
	if board_drawer == null:
		return
	board_drawer.align_to_board(board_global_pos)

func _update_board_drawer():
	var board_renderer = get_parent().get_node("BoardRenderer")
	align_drawer_to_board(board_renderer.global_position)

func _get_layout() -> Dictionary:
	return _layout

func _clear_ui():
	for child in get_children():
		remove_child(child)
		child.free()

func _rebuild_ui():
	_clear_ui()
	_create_ui()
	_create_board_drawer()
	# Re-align after rebuild — board_renderer.global_position is stable
	var board_renderer = get_parent().get_node("BoardRenderer")
	align_drawer_to_board(board_renderer.global_position)
	if eval_history.size() > 0:
		_update_eval_graph(last_logged_eval)
	if _clocks_visible:
		update_clocks(_last_white_time, _last_black_time)

func _create_ui():
	var L = _get_layout()
	var px = L.panel_x
	var pw = L.panel_w
	var ph = L.panel_h
	var sc = L.scale
	var pad = L.pad

	# --- Background Panel ---
	var panel = Panel.new()
	panel.position = Vector2(px, 0)
	panel.size = Vector2(pw, ph)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = panel_color
	panel_style.border_width_left = max(1, int(2 * sc))
	panel_style.border_width_right = 0
	panel_style.border_width_top = 0
	panel_style.border_width_bottom = 0
	panel_style.border_color = border_color
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	# --- Title ---
	var title = Label.new()
	title.text = "Duel of the Seven Crowns"
	title.position = Vector2(px + pad, L.title_y)
	title.add_theme_font_size_override("font_size", int(24 * sc))
	title.add_theme_color_override("font_color", text_primary)
	add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Modern Variant"
	subtitle.position = Vector2(px + pad, L.title_y + int(26 * sc))
	subtitle.add_theme_font_size_override("font_size", int(12 * sc))
	subtitle.add_theme_color_override("font_color", text_secondary)
	add_child(subtitle)

	# --- Turn Counter ---
	turn_counter_label = Label.new()
	turn_counter_label.text = "Turn 1"
	turn_counter_label.position = Vector2(px + pad, L.turn_card_y - int(24 * sc))
	turn_counter_label.add_theme_font_size_override("font_size", int(14 * sc))
	turn_counter_label.add_theme_color_override("font_color", text_secondary)
	add_child(turn_counter_label)

	# --- Turn Indicator Card ---
	var card_h = int(44 * sc)
	var turn_bg = Panel.new()
	turn_bg.position = Vector2(px + pad, L.turn_card_y)
	turn_bg.size = Vector2(L.graph_w, card_h)
	var turn_bg_style = StyleBoxFlat.new()
	turn_bg_style.bg_color = Color("#0f172a")
	var r = int(8 * sc)
	turn_bg_style.corner_radius_top_left = r
	turn_bg_style.corner_radius_top_right = r
	turn_bg_style.corner_radius_bottom_left = r
	turn_bg_style.corner_radius_bottom_right = r
	turn_bg_style.border_width_left = max(1, int(1 * sc))
	turn_bg_style.border_width_right = max(1, int(1 * sc))
	turn_bg_style.border_width_top = max(1, int(1 * sc))
	turn_bg_style.border_width_bottom = max(1, int(1 * sc))
	turn_bg_style.border_color = border_color
	turn_bg.add_theme_stylebox_override("panel", turn_bg_style)
	add_child(turn_bg)

	turn_label = Label.new()
	turn_label.text = "White's Turn"
	turn_label.position = Vector2(px + pad + int(16 * sc), L.turn_card_y + int(10 * sc))
	turn_label.add_theme_font_size_override("font_size", int(18 * sc))
	turn_label.add_theme_color_override("font_color", white_color)
	add_child(turn_label)

	# Turn indicator dot
	var dot_s = max(6, int(12 * sc))
	var turn_dot = ColorRect.new()
	turn_dot.position = Vector2(px + pad + L.graph_w - dot_s - int(8 * sc), L.turn_card_y + (card_h - dot_s) / 2)
	turn_dot.size = Vector2(dot_s, dot_s)
	turn_dot.color = white_color
	add_child(turn_dot)

	# --- Clocks (hidden unless the current game is timed) ---
	white_clock_label = Label.new()
	white_clock_label.text = "White: --:--"
	white_clock_label.position = Vector2(px + pad, L.clock_y)
	white_clock_label.add_theme_font_size_override("font_size", int(16 * sc))
	white_clock_label.add_theme_color_override("font_color", white_color)
	white_clock_label.visible = _clocks_visible
	add_child(white_clock_label)

	black_clock_label = Label.new()
	black_clock_label.text = "Black: --:--"
	black_clock_label.position = Vector2(px + pad + L.graph_w / 2, L.clock_y)
	black_clock_label.add_theme_font_size_override("font_size", int(16 * sc))
	black_clock_label.add_theme_color_override("font_color", black_color)
	black_clock_label.visible = _clocks_visible
	add_child(black_clock_label)

	# --- Grace-period rings (unfill clockwise, one per side) ---
	var ring_d = max(14, int(16 * sc))
	white_grace_ring = GraceRing.new()
	white_grace_ring.size = Vector2(ring_d, ring_d)
	white_grace_ring.custom_minimum_size = Vector2(ring_d, ring_d)
	white_grace_ring.position = Vector2(px + pad + int(92 * sc), L.clock_y + int(2 * sc))
	white_grace_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white_grace_ring.visible = false
	add_child(white_grace_ring)

	black_grace_ring = GraceRing.new()
	black_grace_ring.size = Vector2(ring_d, ring_d)
	black_grace_ring.custom_minimum_size = Vector2(ring_d, ring_d)
	black_grace_ring.position = Vector2(px + pad + L.graph_w / 2 + int(92 * sc), L.clock_y + int(2 * sc))
	black_grace_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_grace_ring.visible = false
	add_child(black_grace_ring)

	# --- Eval Label ---
	eval_label = Label.new()
	eval_label.text = "Eval: 0.0"
	eval_label.position = Vector2(px + pad, L.eval_y)
	eval_label.add_theme_font_size_override("font_size", int(14 * sc))
	eval_label.add_theme_color_override("font_color", text_secondary)
	add_child(eval_label)

	# --- Players Info ---
	players_label = Label.new()
	players_label.text = ""
	players_label.position = Vector2(px + pad, L.players_y)
	players_label.add_theme_font_size_override("font_size", int(13 * sc))
	players_label.add_theme_color_override("font_color", text_secondary)
	add_child(players_label)

	# --- Hint Toggle ---
	hint_toggle = CheckButton.new()
	hint_toggle.text = "Show Engine Move"
	hint_toggle.position = Vector2(px + pad, L.hint_y)
	hint_toggle.size = Vector2(L.graph_w, int(32 * sc))
	hint_toggle.add_theme_font_size_override("font_size", int(13 * sc))
	hint_toggle.add_theme_color_override("font_color", text_primary)
	hint_toggle.toggled.connect(_on_hint_toggled)
	add_child(hint_toggle)

	# --- New Game Button ---
	new_game_btn = Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.position = Vector2(px + pad, L.new_game_y)
	new_game_btn.size = Vector2(L.graph_w, int(44 * sc))
	new_game_btn.add_theme_font_size_override("font_size", int(14 * sc))
	new_game_btn.pressed.connect(_on_new_game)
	_style_button(new_game_btn, accent_color, sc)
	add_child(new_game_btn)

	# --- Info Button ---
	info_btn = Button.new()
	info_btn.text = "Info"
	info_btn.position = Vector2(px + pad, L.info_btn_y)
	info_btn.size = Vector2(L.graph_w, int(36 * sc))
	info_btn.add_theme_font_size_override("font_size", int(13 * sc))
	info_btn.pressed.connect(_on_info_pressed)
	_style_button(info_btn, Color("#475569"), sc)
	add_child(info_btn)

	# --- Clear Drawings Button ---
	clear_drawings_btn = Button.new()
	clear_drawings_btn.text = "Clear Drawings"
	clear_drawings_btn.position = Vector2(px + pad, L.clear_drawings_y)
	clear_drawings_btn.size = Vector2(L.graph_w, int(36 * sc))
	clear_drawings_btn.add_theme_font_size_override("font_size", int(13 * sc))
	clear_drawings_btn.pressed.connect(_on_clear_drawings_pressed)
	_style_button(clear_drawings_btn, Color("#475569"), sc)
	add_child(clear_drawings_btn)

	# --- Status Label ---
	status_label = Label.new()
	status_label.text = ""
	status_label.position = Vector2(px + pad, L.status_y)
	status_label.add_theme_font_size_override("font_size", int(14 * sc))
	status_label.add_theme_color_override("font_color", text_accent)
	add_child(status_label)

	# --- Eval Graph ---
	_create_eval_graph_container()

	# --- Bottom accent ---
	var bar_h = max(1, int(2 * sc))
	var bottom_bar = ColorRect.new()
	bottom_bar.position = Vector2(px, ph - bar_h)
	bottom_bar.size = Vector2(pw, bar_h)
	bottom_bar.color = accent_color
	add_child(bottom_bar)

# Eval graph state
var eval_history = []
var last_logged_eval = 999999.0

func _create_eval_graph_container():
	var L = _get_layout()
	var gx = L.panel_x + L.pad
	var gy = L.graph_y
	var gw = L.graph_w
	var gh = L.graph_h
	var sc = L.scale

	var title = Label.new()
	title.text = "Evaluation History"
	title.position = Vector2(gx, gy - int(22 * sc))
	title.add_theme_font_size_override("font_size", int(12 * sc))
	title.add_theme_color_override("font_color", Color("#94a3b8"))
	title.name = "EvalGraphTitle"
	add_child(title)

	var bg = ColorRect.new()
	bg.position = Vector2(gx, gy)
	bg.size = Vector2(gw, gh)
	bg.color = Color("#0f172a")
	bg.name = "EvalGraphBg"
	add_child(bg)

	var bw = max(1, int(1 * sc))
	var borders = [
		[Vector2(gx, gy), Vector2(gw, bw)],
		[Vector2(gx, gy + gh - bw), Vector2(gw, bw)],
		[Vector2(gx, gy), Vector2(bw, gh)],
		[Vector2(gx + gw - bw, gy), Vector2(bw, gh)]
	]
	for i in range(borders.size()):
		var b = borders[i]
		var line = ColorRect.new()
		line.position = b[0]
		line.size = b[1]
		line.color = Color("#334155")
		line.name = "EvalBorder" + str(i)
		add_child(line)

	var center = ColorRect.new()
	center.position = Vector2(gx, gy + gh / 2)
	center.size = Vector2(gw, bw)
	center.color = Color("#334155")
	center.name = "EvalCenterLine"
	add_child(center)

func _clear_eval_data():
	var to_remove = []
	for child in get_children():
		var n = child.name
		if n.begins_with("EvalLine") or n.begins_with("EvalDot") or n == "EvalScoreLabel" or n.begins_with("EvalBound") or n == "EvalPlaceholder":
			to_remove.append(child)
	for child in to_remove:
		remove_child(child)
		child.free()

func _update_eval_graph(current_score: float):
	_clear_eval_data()

	var L = _get_layout()
	var gx = L.panel_x + L.pad
	var gy = L.graph_y
	var gw = L.graph_w
	var gh = L.graph_h
	var gm = L.graph_margin
	var sc = L.scale

	var score_label = Label.new()
	score_label.text = "%+.1f" % current_score
	score_label.position = Vector2(gx + gw / 2 - int(25 * sc), gy + gh + int(4 * sc))
	score_label.add_theme_font_size_override("font_size", int(14 * sc))
	score_label.add_theme_color_override("font_color", Color("#e2e8f0"))
	score_label.name = "EvalScoreLabel"
	add_child(score_label)

	var CAP = 5000.0
	var capped = []
	for entry in eval_history:
		var s = entry[1]
		if typeof(s) == TYPE_STRING and s.begins_with("M"):
			var m = int(s.substr(1))
			capped.append(CAP if m > 0 else -CAP)
		else:
			capped.append(clampf(float(s), -CAP, CAP))

	var max_abs = 0.0
	for s in capped:
		max_abs = maxf(max_abs, abs(s))
	var bound = maxf(max_abs, 200.0)

	var top_label = Label.new()
	top_label.text = "+%d" % int(bound)
	top_label.position = Vector2(gx + int(4 * sc), gy + int(4 * sc))
	top_label.add_theme_font_size_override("font_size", int(9 * sc))
	top_label.add_theme_color_override("font_color", Color("#475569"))
	top_label.name = "EvalBoundTop"
	add_child(top_label)

	var bot_label = Label.new()
	bot_label.text = "-%d" % int(bound)
	bot_label.position = Vector2(gx + int(4 * sc), gy + gh - int(14 * sc))
	bot_label.add_theme_font_size_override("font_size", int(9 * sc))
	bot_label.add_theme_color_override("font_color", Color("#475569"))
	bot_label.name = "EvalBoundBot"
	add_child(bot_label)

	var n = capped.size()
	var step_x = float(gw - 2 * gm) / maxf(n - 1, 1)
	var left = gx + gm
	var usable_h = gh - 2 * gm
	var cy = gy + gh / 2

	var points = []
	for i in range(n):
		var x = left + i * step_x
		var ratio = clampf(capped[i] / bound, -1.0, 1.0)
		var y = cy - ratio * (usable_h / 2)
		points.append(Vector2(x, y))

	var lw = max(1, int(2 * sc))
	for i in range(points.size() - 1):
		var line = Line2D.new()
		line.add_point(points[i])
		line.add_point(points[i + 1])
		line.width = lw
		var mid_y = (points[i].y + points[i + 1].y) / 2
		line.default_color = white_color if mid_y < cy else Color("#94a3b8")
		line.name = "EvalLine" + str(i)
		add_child(line)

	var ds = max(2, int(4 * sc))
	for i in range(points.size()):
		var p = points[i]
		var dot = ColorRect.new()
		dot.position = Vector2(p.x - ds / 2, p.y - ds / 2)
		dot.size = Vector2(ds, ds)
		dot.color = Color("#e2e8f0")
		dot.name = "EvalDot" + str(i)
		add_child(dot)

func _style_button(btn: Button, color: Color, sc: float):
	var r = int(8 * sc)
	var normal = StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = r
	normal.corner_radius_top_right = r
	normal.corner_radius_bottom_left = r
	normal.corner_radius_bottom_right = r
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.15)
	hover.corner_radius_top_left = r
	hover.corner_radius_top_right = r
	hover.corner_radius_bottom_left = r
	hover.corner_radius_bottom_right = r
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.15)
	pressed.corner_radius_top_left = r
	pressed.corner_radius_top_right = r
	pressed.corner_radius_bottom_left = r
	pressed.corner_radius_bottom_right = r
	btn.add_theme_stylebox_override("pressed", pressed)

func _bot_label(type: String) -> String:
	match type:
		"human":
			return "Human"
		"easy":
			return "Easy Bot"
		"medium":
			return "Medium Bot"
		"hard":
			return "Hard Bot"
		"impossible":
			return "Impossible Bot"
		"roulette":
			return "Roulette Bot"
	return type.capitalize()

func set_player_labels(white: String, black: String):
	var w_label = _bot_label(white)
	var b_label = _bot_label(black)
	players_label.text = "White: %s\nBlack: %s" % [w_label, b_label]

# ------------------------------------------------------------------
# CLOCK DISPLAY API — called by StartGameplay
# ------------------------------------------------------------------
func set_clocks_visible(vis: bool):
	_clocks_visible = vis
	if white_clock_label != null:
		white_clock_label.visible = vis
	if black_clock_label != null:
		black_clock_label.visible = vis
	if not vis:
		if white_grace_ring != null:
			white_grace_ring.visible = false
		if black_grace_ring != null:
			black_grace_ring.visible = false

func update_clocks(white_seconds: float, black_seconds: float):
	_last_white_time = white_seconds
	_last_black_time = black_seconds
	if white_clock_label != null:
		white_clock_label.text = "White: " + _format_clock(white_seconds)
		white_clock_label.add_theme_color_override("font_color", _clock_color(white_seconds, white_color))
	if black_clock_label != null:
		black_clock_label.text = "Black: " + _format_clock(black_seconds)
		black_clock_label.add_theme_color_override("font_color", _clock_color(black_seconds, black_color))

# Called every frame while a timed game is in progress. active_side is
# whichever color is currently on move; remaining/total describe the
# per-turn grace buffer (GameState.turn_grace_remaining / TURN_GRACE_PERIOD).
# Only the side on move ever shows a ring — the waiting side's buffer
# isn't running.
func update_grace(active_side: String, remaining: float, total: float):
	if not _clocks_visible:
		return
	var frac = 0.0 if total <= 0.0 else remaining / total
	var showing = remaining > 0.0
	if active_side == "white":
		if white_grace_ring != null:
			white_grace_ring.visible = showing
			white_grace_ring.set_fraction(frac)
		if black_grace_ring != null:
			black_grace_ring.visible = false
	else:
		if black_grace_ring != null:
			black_grace_ring.visible = showing
			black_grace_ring.set_fraction(frac)
		if white_grace_ring != null:
			white_grace_ring.visible = false

func _clock_color(seconds: float, base_color: Color) -> Color:
	if seconds <= CLOCK_DANGER_SECONDS:
		return clock_danger_color
	elif seconds <= CLOCK_WARN_SECONDS:
		return clock_warn_color
	return base_color

func _format_clock(seconds: float) -> String:
	var s = max(0, int(ceil(seconds)))
	var m = s / 60
	var rem = s % 60
	return "%d:%02d" % [m, rem]

func _on_hint_toggled(enabled: bool):
	var root = get_parent()
	var game_state = root.get_node("GameState")
	if enabled:
		var current_player = root.white_player if game_state.turn == "white" else root.black_player
		if current_player == "human" and not game_state.game_over:
			game_state.start_hint_search()
	else:
		game_state.stop_hint_search()

func _normalize_mate_score(raw_score) -> String:
	var f = float(raw_score)
	if f > 100000.0:
		var mate_in = max(1, int(round(999999.0 - f)))
		return "M%d" % mate_in
	elif f < -100000.0:
		var mate_in = max(1, int(round(999999.0 + f)))
		return "-M%d" % mate_in
	return str(raw_score)


func update_turn(turn: String):
	turn_label.text = turn.capitalize() + "'s Turn"
	turn_label.add_theme_color_override("font_color", white_color if turn == "white" else black_color)
	var game_state = get_parent().get_node("GameState")
	update_eval(game_state.current_eval_score, true)

func update_eval(eval_score, is_new_move: bool = false):
	var normalized = _normalize_mate_score(eval_score)
	var numeric_score: float
	
	if normalized.begins_with("-M"):
		var mate_in = int(normalized.substr(2))
		eval_label.text = "Eval: -M%d" % mate_in
		numeric_score = -10000.0
	elif normalized.begins_with("M"):
		var mate_in = int(normalized.substr(1))
		eval_label.text = "Eval: M%d" % mate_in
		numeric_score = 10000.0
	else:
		numeric_score = float(normalized)
		eval_label.text = "Eval: %+.1f" % numeric_score
	
	if is_new_move or eval_history.is_empty():
		eval_history.append([eval_history.size(), numeric_score])
	else:
		eval_history[eval_history.size() - 1][1] = numeric_score
	
	last_logged_eval = numeric_score
	_update_eval_graph(numeric_score)

func show_game_over(reason: String, winner: String):
	match reason:
		"checkmate":
			status_label.text = "Checkmate! " + winner + " wins!"
		"40move":
			if winner != "":
				status_label.text = "Draw (40 moves without capture) — " + winner + " wins on Armageddon rules!"
			else:
				status_label.text = "Draw! (40 moves without capture)"
		"insufficient":
			if winner != "":
				status_label.text = "Draw (insufficient material) — " + winner + " wins on Armageddon rules!"
			else:
				status_label.text = "Draw! (Insufficient material)"
		"no_legal_moves":
			status_label.text = winner + " wins! (No legal moves)"
		"time":
			status_label.text = winner + " wins on time!"

func _on_turn_changed(new_turn: String):
	update_turn(new_turn)
	# turn_changed fires right after a move flips the turn. new_turn == "white"
	# means Black just moved (turn flipped black -> white), which is the
	# correct moment a new turn begins. new_turn == "black" means White just
	# moved and Black hasn't played yet -- must NOT increment there.
	if new_turn == "white":
		turn_number += 1
	turn_counter_label.text = "Turn %d" % turn_number

func _on_game_ended(reason: String, winner: String):
	show_game_over(reason, winner)

func _on_thinking():
	status_label.text = "Thinking..."

func _on_thinking_done():
	status_label.text = ""

func _on_info_pressed():
	var info = get_parent().get_node_or_null("Info")
	if info != null:
		info.toggle()

func _on_clear_drawings_pressed():
	if board_drawer != null:
		board_drawer.clear_arrows()

func _on_new_game():
	turn_number = 1
	turn_counter_label.text = "Turn 1"
	status_label.text = ""
	eval_history.clear()
	last_logged_eval = 999999.0
	set_clocks_visible(false)
	if board_drawer != null:
		board_drawer.clear_arrows()
	get_parent().new_game()
