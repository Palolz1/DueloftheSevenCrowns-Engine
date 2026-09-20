#PlayerSetup.gd
extends Control

signal players_selected(white_type: String, black_type: String, game_type: String)

var white_type: String = "human"
var black_type: String = "human"
var game_type: String = "untimed"

# ------------------------------------------------------------------
# CONFIGURATION — add new bots here and the UI adapts automatically
# ------------------------------------------------------------------
const OPTIONS: Array[Dictionary] = [
	{ "id": "human",      "label": "Human",          "desc": "You control",        "accent": Color("#22c55e") },
	{ "id": "beginner",   "label": "Beginner Bot",   "desc": "Very passive AI",    "accent": Color("#86efac") },
	{ "id": "easy",       "label": "Easy Bot",       "desc": "Casual AI",          "accent": Color("#4ade80") },
	{ "id": "medium",     "label": "Medium Bot",     "desc": "Balanced AI",        "accent": Color("#facc15") },
	{ "id": "hard",       "label": "Hard Bot",       "desc": "Aggressive AI",      "accent": Color("#fb923c") },
	{ "id": "impossible", "label": "Impossible Bot", "desc": "Full power AI",          "accent": Color("#ef4444") },
	{ "id": "roulette",   "label": "Roulette Bot",   "desc": "Random moves",       "accent": Color("#a855f7") },
	{ "id": "cautious",   "label": "Cautious Bot",   "desc": "Never blunders",     "accent": Color("#06b6d4") },
	{ "id": "shepherd",   "label": "Shepherd Bot",   "desc": "Perfects the herd",  "accent": Color("#ec4899") },
]

# ------------------------------------------------------------------
# GAME TYPES — untimed / standard / armageddon
# ------------------------------------------------------------------
const GAME_TYPES: Array[Dictionary] = [
	{ "id": "untimed",    "label": "Untimed",    "desc": "No clock",                              "accent": Color("#22c55e") },
	{ "id": "standard",   "label": "Standard",   "desc": "15 min vs 15 min",                       "accent": Color("#facc15") },
	{ "id": "armageddon", "label": "Armageddon", "desc": "10 min White vs 8 min Black, draw = Black wins", "accent": Color("#ef4444") },
]

const BG_COLOR    := Color(0.039, 0.047, 0.086, 0.95)  # near-black overlay
const PANEL_BG    := Color(0.071, 0.086, 0.133, 1.0)   # card background
const TITLE_COLOR := Color("#e94560")
const SUB_COLOR   := Color("#94a3b8")

func _ready():
	visible = true
	z_index = 100
	set_anchors_preset(Control.PRESET_FULL_RECT)  # Make PlayerSetup fill the screen
	_build_ui()

func _build_ui():
	# Dark fullscreen overlay
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Root centering container
	var root := CenterContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var main := VBoxContainer.new()
	main.name = "MainVBox"
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_theme_constant_override("separation", 20)
	root.add_child(main)

	# ---- Title ----
	var title := Label.new()
	title.text = "Duel of the Seven Crowns"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	main.add_child(title)

	var sub := Label.new()
	sub.text = "Select Your Opponents"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", SUB_COLOR)
	main.add_child(sub)

	# ---- Time control card + player cards, side by side ----
	var hbox := HBoxContainer.new()
	hbox.name = "PlayersHBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 28)
	main.add_child(hbox)

	_add_game_type_card(hbox)
	_add_player_card(hbox, "white", "White Player", Color("#fef3c7"), Color("#f59e0b"))
	_add_player_card(hbox, "black", "Black Player", Color("#a78bfa"), Color("#8b5cf6"))

	# ---- Start button ----
	var start := Button.new()
	start.text = "Start Game"
	start.custom_minimum_size = Vector2(220, 52)
	start.add_theme_font_size_override("font_size", 20)

	var st_normal := StyleBoxFlat.new()
	st_normal.bg_color = TITLE_COLOR
	start.add_theme_stylebox_override("normal", st_normal)

	var st_hover := StyleBoxFlat.new()
	st_hover.bg_color = Color("#f43f5e")
	start.add_theme_stylebox_override("hover", st_hover)

	start.add_theme_color_override("font_color", Color("#ffffff"))
	start.pressed.connect(_on_start)
	main.add_child(start)

func _add_game_type_card(parent: Node):
	var panel := PanelContainer.new()
	panel.name = "GameTypePanel"
	panel.custom_minimum_size = Vector2(180, 0)

	var panel_style := StyleBoxFlat.new()
	panel_style.set_bg_color(PANEL_BG)
	panel_style.set_border_width_all(2)
	panel_style.set_border_color(Color("#22c55e"))
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_meta("border_style", panel_style)

	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "Time Control"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color("#e2e8f0"))
	vbox.add_child(lbl)

	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color("#334155")
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	vbox.add_child(sep)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_col)

	var group := ButtonGroup.new()

	for gt in GAME_TYPES:
		var btn := Button.new()
		btn.text = gt["label"]
		btn.tooltip_text = gt["desc"]
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(150, 44)
		btn.add_theme_font_size_override("font_size", 13)

		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.12, 0.14, 0.20)
		n.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", n)

		var h := StyleBoxFlat.new()
		h.bg_color = Color(0.18, 0.20, 0.28)
		h.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("hover", h)

		var p := StyleBoxFlat.new()
		p.bg_color = gt["accent"]
		p.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("pressed", p)

		btn.add_theme_color_override("font_color", Color("#cbd5e1"))
		btn.add_theme_color_override("font_pressed_color", Color("#0f172a"))
		btn.add_theme_color_override("font_hover_color", Color("#f8fafc"))

		btn.toggled.connect(func(pressed: bool):
			if pressed:
				game_type = gt["id"]
				var style: StyleBoxFlat = panel.get_meta("border_style")
				style.set_border_color(gt["accent"])
		)

		if gt["id"] == "untimed":
			btn.button_pressed = true
			var style: StyleBoxFlat = panel.get_meta("border_style")
			style.set_border_color(gt["accent"])

		btn_col.add_child(btn)

func _add_player_card(parent: Node, player_id: String, header: String, border_base: Color, header_color: Color):
	var panel := PanelContainer.new()
	panel.name = player_id.capitalize() + "Panel"
	panel.custom_minimum_size = Vector2(260, 0)

	# Card background & border
	var panel_style := StyleBoxFlat.new()
	panel_style.set_bg_color(PANEL_BG)
	panel_style.set_border_width_all(2)
	panel_style.set_border_color(border_base)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_meta("border_style", panel_style)  # keep ref for live updates

	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header
	var lbl := Label.new()
	lbl.text = header
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", header_color)
	vbox.add_child(lbl)

	# Divider
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = border_base
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	vbox.add_child(sep)

	# Options grid: 2 columns × 5 rows = 10 slots (was 8, now 9 options)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	var group := ButtonGroup.new()

	for opt in OPTIONS:
		var btn := Button.new()
		btn.text = opt["label"]
		btn.tooltip_text = opt["desc"]
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(110, 44)
		btn.add_theme_font_size_override("font_size", 13)

		# Normal
		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.12, 0.14, 0.20)
		n.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", n)

		# Hover
		var h := StyleBoxFlat.new()
		h.bg_color = Color(0.18, 0.20, 0.28)
		h.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("hover", h)

		# Pressed / Selected
		var p := StyleBoxFlat.new()
		p.bg_color = opt["accent"]
		p.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("pressed", p)

		btn.add_theme_color_override("font_color", Color("#cbd5e1"))
		btn.add_theme_color_override("font_pressed_color", Color("#0f172a"))
		btn.add_theme_color_override("font_hover_color", Color("#f8fafc"))

		btn.toggled.connect(func(pressed: bool):
			if pressed:
				if player_id == "white":
					white_type = opt["id"]
				else:
					black_type = opt["id"]
				# Flash the card border to match the selected bot's accent
				var style: StyleBoxFlat = panel.get_meta("border_style")
				style.set_border_color(opt["accent"])
		)

		# Default selection
		if opt["id"] == "human":
			btn.button_pressed = true
			var style: StyleBoxFlat = panel.get_meta("border_style")
			style.set_border_color(opt["accent"])

		grid.add_child(btn)

func _on_start():
	visible = false
	players_selected.emit(white_type, black_type, game_type)
