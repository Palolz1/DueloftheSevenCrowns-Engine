#PlayerSetup.gd
# New-game screen: who plays each side (a human or a computer level /
# personality) and the time control.
extends Control

signal players_selected(white_type: String, black_type: String, game_type: String, standard_seconds: float, armageddon_white_seconds: float, armageddon_black_seconds: float, scenario_id: String)

# Choices survive "New game" (the screen is rebuilt each time).
static var _saved := {
	"white": "human", "black": "medium",
	"white_bot": "medium", "black_bot": "medium",
	"game_type": "untimed", "standard": 15.0, "arma_white": 10.0, "arma_black": 8.0,
	"scenario": "classic",
}

var white_type: String = "human"
var black_type: String = "medium"
var game_type: String = "untimed"
var standard_minutes: float = 15.0
var armageddon_white_minutes: float = 10.0
var armageddon_black_minutes: float = 8.0

# The difficulty ladder, weakest first. Position in the list = crowns lit.
# Titles come from UITheme.LEVEL_TITLES; each description leads with the
# plain difficulty word so new players can still read the ladder.
const LEVELS: Array[Dictionary] = [
	{ "id": "beginner",   "label": "Count",        "desc": "Beginner · nearly random moves" },
	{ "id": "novice",     "label": "Marquess",     "desc": "Novice · misses a lot" },
	{ "id": "easy",       "label": "Duke",         "desc": "Easy · casual, slips a lot" },
	{ "id": "medium",     "label": "Archduke",     "desc": "Medium · solid, still errs" },
	{ "id": "hard",       "label": "Grand Prince", "desc": "Hard · strong, rarely careless" },
	{ "id": "expert",     "label": "King",         "desc": "Expert · full engine, quick" },
	{ "id": "impossible", "label": "Emperor",      "desc": "Impossible · full engine, no mercy" },
]

const PERSONALITIES: Array[Dictionary] = [
	{ "id": "roulette", "label": "Roulette", "desc": "Every move is either the best or the worst, 50/50", "accent": Color("#a77bf2") },
	{ "id": "cautious", "label": "Cautious", "desc": "Never blunders on purpose, plays it safe", "accent": Color("#3fc1d9") },
	{ "id": "shepherd", "label": "Shepherd", "desc": "Flawless with its donkeys, human with everything else", "accent": Color("#ec6aa6") },
	{ "id": "random", "label": "Random", "desc": "Picks any legal move completely at random", "accent": Color("#94a3b8") },
	{ "id": "berserker", "label": "Berserker", "desc": "Captures whenever it can, no matter the cost", "accent": Color("#ef5a4f") },
	{ "id": "pacifist", "label": "Pacifist", "desc": "Refuses to capture unless it has no other move", "accent": Color("#7fd6a8") },
	{ "id": "mirror", "label": "Mirror", "desc": "Copies your last move (rotated) whenever it legally can", "accent": Color("#7cb7ff") },
	{ "id": "stampede", "label": "Stampede", "desc": "Always pushes a donkey if one can move", "accent": Color("#d9a35b") },
	{ "id": "wanderer", "label": "Wanderer", "desc": "Takes its king for a walk whenever it can afford to", "accent": Color("#f2d16b") },
]

const GAME_TYPES: Array[Dictionary] = [
	{ "id": "untimed",    "label": "Untimed",    "desc": "No clock" },
	{ "id": "standard",   "label": "Standard",   "desc": "Same time for both sides" },
	{ "id": "armageddon", "label": "Armageddon", "desc": "White gets more time, but a draw counts as a win for Black" },
]


# Seven little crowns, `level` of them lit.
class CrownMeter:
	extends Control
	var level := 1
	var color := Color.WHITE

	func _draw():
		var w := 11.0
		var gap := 3.0
		for i in 7:
			var x := i * (w + gap)
			var col := color if i < level else Color(1, 1, 1, 0.13)
			var base_y := size.y / 2.0 + 4.0
			var pts := PackedVector2Array([
				Vector2(x, base_y), Vector2(x, base_y - 7), Vector2(x + w * 0.25, base_y - 3.5),
				Vector2(x + w * 0.5, base_y - 9), Vector2(x + w * 0.75, base_y - 3.5),
				Vector2(x + w, base_y - 7), Vector2(x + w, base_y)])
			draw_colored_polygon(pts, col)


var _cards := {}   # color -> {human, bot, human_box, bot_box, choices}
var _standard_row: Control
var _arma_row: Control
var scenario_id := "classic"
var _scenario_btn: Button
var _scenario_page: Control = null


func _ready():
	visible = true
	z_index = 100
	set_anchors_preset(Control.PRESET_FULL_RECT)
	white_type = _saved.white
	black_type = _saved.black
	game_type = _saved.game_type
	standard_minutes = _saved.standard
	armageddon_white_minutes = _saved.arma_white
	armageddon_black_minutes = _saved.arma_black
	scenario_id = _saved.scenario
	_build_ui()


func _build_ui():
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# soft gold glow behind the title
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(UITheme.GOLD, 0.10))
	grad.set_color(1, Color(UITheme.GOLD, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 512
	gt.height = 256
	glow.texture = gt
	glow.position = Vector2(240, -120)
	glow.size = Vector2(800, 400)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var main := UITheme.vbox(18)
	margin.add_child(main)

	# ---- Title ----
	var title_row := UITheme.hbox(16)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(title_row)
	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.custom_minimum_size = Vector2(70, 70)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(icon)
	var tcol := UITheme.vbox(2)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(tcol)
	tcol.add_child(UITheme.label("Duel of the Seven Crowns", 38, UITheme.GOLD_LIGHT, UITheme.display(700)))
	tcol.add_child(UITheme.label("Choose who plays each side, then pick a clock.", 15, UITheme.TEXT_DIM, UITheme.ui(500)))

	# ---- Player cards ----
	var cards := UITheme.hbox(14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(cards)
	_add_player_card(cards, "white")
	var swap_col := UITheme.vbox(0)
	swap_col.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_child(swap_col)
	var swap := UITheme.button("↔", "ghost", 22, 52)
	swap.custom_minimum_size = Vector2(52, 52)
	swap.tooltip_text = "Swap sides"
	swap.pressed.connect(_on_swap)
	swap_col.add_child(swap)
	_add_player_card(cards, "black")

	# ---- Time control + start ----
	var bottom := UITheme.panel(UITheme.card(16))
	main.add_child(bottom)
	var brow := UITheme.hbox(18)
	bottom.add_child(brow)
	var tc := UITheme.vbox(8)
	brow.add_child(tc)
	tc.add_child(UITheme.heading("Time control"))
	var trow := UITheme.hbox(8)
	tc.add_child(trow)
	var group := ButtonGroup.new()
	for g in GAME_TYPES:
		var b := UITheme.pill(g.label, UITheme.GOLD, 14, 36)
		b.custom_minimum_size.x = 112
		b.tooltip_text = g.desc
		b.button_group = group
		b.button_pressed = g.id == game_type
		b.toggled.connect(func(on): if on: _set_game_type(g.id))
		trow.add_child(b)

	var settings := UITheme.hbox(14)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.size_flags_vertical = Control.SIZE_SHRINK_END
	brow.add_child(settings)
	_standard_row = UITheme.hbox(8)
	_standard_row.add_child(_time_label("Minutes each"))
	_standard_row.add_child(_minutes_spin(standard_minutes, func(v): standard_minutes = v))
	settings.add_child(_standard_row)
	_arma_row = UITheme.hbox(8)
	_arma_row.add_child(_time_label("White"))
	_arma_row.add_child(_minutes_spin(armageddon_white_minutes, func(v): armageddon_white_minutes = v))
	_arma_row.add_child(_time_label("  Black"))
	_arma_row.add_child(_minutes_spin(armageddon_black_minutes, func(v): armageddon_black_minutes = v))
	settings.add_child(_arma_row)
	_set_game_type(game_type)

	# Starting position (opens the Starting Positions page)
	var pos_col := UITheme.vbox(8)
	brow.add_child(pos_col)
	pos_col.add_child(UITheme.heading("Starting position"))
	_scenario_btn = UITheme.button("", "secondary", 14, 36)
	_scenario_btn.custom_minimum_size.x = 210
	_scenario_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scenario_btn.tooltip_text = "Alternative armies, drills and handicaps"
	_scenario_btn.pressed.connect(_open_scenarios)
	pos_col.add_child(_scenario_btn)
	_update_scenario_button()

	var start := UITheme.button("Start game", "primary", 19, 56)
	start.custom_minimum_size = Vector2(230, 56)
	start.add_theme_font_override("font", UITheme.ui(700))
	start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_start)
	brow.add_child(start)


func _update_scenario_button():
	_scenario_btn.text = Scenarios.get_info(scenario_id).name + "   ›"

func _open_scenarios():
	if _scenario_page != null:
		return
	_scenario_page = preload("res://scenario_page.gd").new()
	_scenario_page.selected_id = scenario_id
	_scenario_page.chosen.connect(func(id):
		scenario_id = id
		_update_scenario_button()
		_close_scenarios())
	_scenario_page.closed.connect(_close_scenarios)
	add_child(_scenario_page)

func _close_scenarios():
	if _scenario_page != null:
		_scenario_page.queue_free()
		_scenario_page = null

func _time_label(t: String) -> Label:
	var l := UITheme.label(t, 14, UITheme.TEXT_DIM, UITheme.ui(500))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _minutes_spin(initial: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 180
	spin.step = 1
	spin.value = initial
	spin.suffix = "min"
	spin.custom_minimum_size = Vector2(96, 36)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var le := spin.get_line_edit()
	le.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE_LO, 8, UITheme.BORDER, 1, 6))
	le.add_theme_stylebox_override("focus", UITheme.box(UITheme.SURFACE_LO, 8, UITheme.GOLD, 1, 6))
	le.add_theme_color_override("font_color", UITheme.TEXT)
	le.add_theme_font_override("font", UITheme.ui(600))
	spin.value_changed.connect(on_change)
	return spin

func _set_game_type(id: String):
	game_type = id
	_standard_row.visible = id == "standard"
	_arma_row.visible = id == "armageddon"


# ---------------------------------------------------------------------------
# Player cards
# ---------------------------------------------------------------------------
func _add_player_card(parent: Node, color: String):
	var card := UITheme.panel(UITheme.card(18))
	card.custom_minimum_size = Vector2(500, 0)
	parent.add_child(card)
	var v := UITheme.vbox(12)
	card.add_child(v)

	# Header: token + side name + Human/Computer switch
	var head := UITheme.hbox(12)
	v.add_child(head)
	head.add_child(UITheme.piece_token(("w" if color == "white" else "b") + "K", 44))
	var names := UITheme.vbox(0)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	names.add_child(UITheme.label(color.capitalize(), 24, UITheme.IVORY if color == "white" else Color("#b9c3dc"), UITheme.display(700)))
	names.add_child(UITheme.label("Moves first" if color == "white" else "Moves second", 13, UITheme.TEXT_FAINT, UITheme.ui(500)))
	head.add_child(UITheme.spacer())
	var mode_group := ButtonGroup.new()
	var mh := UITheme.pill("Human", UITheme.EMERALD, 14, 36)
	mh.custom_minimum_size.x = 100
	mh.button_group = mode_group
	var mb := UITheme.pill("Computer", UITheme.GOLD, 14, 36)
	mb.custom_minimum_size.x = 100
	mb.button_group = mode_group
	var mode_row := UITheme.hbox(6)
	mode_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(mh)
	mode_row.add_child(mb)
	head.add_child(mode_row)

	# Human panel
	var human_box := UITheme.vbox(10)
	human_box.alignment = BoxContainer.ALIGNMENT_CENTER
	human_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(human_box)
	var big := UITheme.piece_token(("w" if color == "white" else "b") + "K", 96)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	human_box.add_child(big)
	var ht := UITheme.label("A person plays %s on this computer." % color.capitalize(), 16, UITheme.TEXT, UITheme.ui(500))
	ht.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	human_box.add_child(ht)
	var hs := UITheme.label("Playing a computer? Your side starts at the bottom of the board.", 13, UITheme.TEXT_FAINT, UITheme.ui(500))
	hs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	human_box.add_child(hs)

	# Computer panel
	var bot_box := UITheme.vbox(6)
	bot_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bot_box)
	bot_box.add_child(UITheme.heading("Difficulty"))
	var choice_group := ButtonGroup.new()
	var choices := {}
	for i in LEVELS.size():
		var lv: Dictionary = LEVELS[i]
		var b := _level_row(lv, i + 1, UITheme.LEVEL_COLORS[i])
		b.button_group = choice_group
		b.toggled.connect(func(on): if on: _choose_bot(color, lv.id))
		bot_box.add_child(b)
		choices[lv.id] = b
	bot_box.add_child(UITheme.heading("Personalities"))
	var prow := GridContainer.new()
	prow.columns = 3
	prow.add_theme_constant_override("h_separation", 8)
	prow.add_theme_constant_override("v_separation", 8)
	bot_box.add_child(prow)
	for p in PERSONALITIES:
		var b := UITheme.pill(p.label, p.accent, 13, 32)
		b.tooltip_text = p.desc
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_group = choice_group
		b.toggled.connect(func(on): if on: _choose_bot(color, p.id))
		prow.add_child(b)
		choices[p.id] = b

	_cards[color] = {"human": mh, "bot": mb, "human_box": human_box, "bot_box": bot_box, "choices": choices}
	mh.toggled.connect(func(on): if on: _set_mode(color, true))
	mb.toggled.connect(func(on): if on: _set_mode(color, false))

	var current: String = white_type if color == "white" else black_type
	var bot_choice: String = current if current != "human" else _saved[color + "_bot"]
	if choices.has(bot_choice):
		choices[bot_choice].button_pressed = true
	if current == "human":
		mh.button_pressed = true
	else:
		mb.button_pressed = true
	_set_mode(color, current == "human")


# One row of the difficulty ladder: crown meter, name, description.
func _level_row(lv: Dictionary, level: int, accent: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 33)
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0, 0, 0, 0), 8))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_HI, 8, UITheme.BORDER_SOFT, 1))
	var sel := UITheme.box(Color(accent, 0.13), 8, accent, 2)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var row := UITheme.hbox(12)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var meter := CrownMeter.new()
	meter.level = level
	meter.color = accent
	meter.custom_minimum_size = Vector2(96, 0)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meter)
	var nm := UITheme.label(lv.label, 15, UITheme.TEXT, UITheme.ui(650))
	nm.custom_minimum_size = Vector2(108, 0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var desc := UITheme.label(lv.desc, 13, UITheme.TEXT_DIM, UITheme.ui(450))
	desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc)
	return b


func _set_mode(color: String, human: bool):
	var c: Dictionary = _cards[color]
	c.human_box.visible = human
	c.bot_box.visible = not human
	if human:
		_set_type(color, "human")
	else:
		var chosen: String = _saved[color + "_bot"]
		for id in c.choices:
			if c.choices[id].button_pressed:
				chosen = id
		_set_type(color, chosen)

func _choose_bot(color: String, id: String):
	_saved[color + "_bot"] = id
	if not _cards[color].human.button_pressed:
		_set_type(color, id)

func _set_type(color: String, t: String):
	if color == "white":
		white_type = t
	else:
		black_type = t

func _on_swap():
	var w := white_type
	var b := black_type
	var wb: String = _saved.white_bot
	_saved.white_bot = _saved.black_bot
	_saved.black_bot = wb
	_apply_choice("white", b)
	_apply_choice("black", w)

func _apply_choice(color: String, t: String):
	var c: Dictionary = _cards[color]
	if t == "human":
		c.human.button_pressed = true
	else:
		if c.choices.has(t):
			c.choices[t].button_pressed = true
		c.bot.button_pressed = true
	_set_mode(color, t == "human")


func _on_start():
	_saved.white = white_type
	_saved.black = black_type
	_saved.game_type = game_type
	_saved.standard = standard_minutes
	_saved.arma_white = armageddon_white_minutes
	_saved.arma_black = armageddon_black_minutes
	_saved.scenario = scenario_id
	visible = false
	players_selected.emit(
		white_type, black_type, game_type,
		standard_minutes * 60.0,
		armageddon_white_minutes * 60.0,
		armageddon_black_minutes * 60.0,
		scenario_id
	)
	queue_free()
