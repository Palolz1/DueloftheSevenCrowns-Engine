# puzzle_page.gd
# Puzzle list (puzzles.gd), grouped by theme. Each tile is a mini board;
# picking one emits `chosen(id)`.
extends Control

signal chosen(id: String)
signal closed


func _ready():
	z_index = 200
	var shell := UITheme.page_shell(self, "Puzzles",
		"%d of %d solved. Every puzzle comes from a real computer game and was checked by the engine." % [Puzzles.solved_count(), Puzzles.LIST.size()])
	shell.back.pressed.connect(func(): closed.emit())
	var cont := UITheme.button("Continue  ›", "primary", 15, 40)
	cont.custom_minimum_size.x = 150
	cont.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var next_id := Puzzles.next_unsolved()
	cont.disabled = next_id == ""
	cont.tooltip_text = "Next puzzle you haven't solved"
	cont.pressed.connect(func(): chosen.emit(next_id))
	shell.head.add_child(cont)
	shell.head.move_child(cont, 1)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.body.add_child(scroll)
	var list := UITheme.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for th in Puzzles.THEMES:
		var items := Puzzles.in_theme(th.id)
		if items.is_empty():
			continue
		var hrow := UITheme.hbox(12)
		list.add_child(hrow)
		hrow.add_child(UITheme.label(th.name, 20, UITheme.TEXT, UITheme.display(700)))
		var d := UITheme.label("%s   %d / %d solved" % [th.desc, Puzzles.solved_count(th.id), items.size()], 13, UITheme.TEXT_FAINT, UITheme.ui(500))
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hrow.add_child(d)
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for i in items.size():
			grid.add_child(_tile(items[i], i + 1))
		list.add_child(UITheme.spacer(false))


func _tile(p: Dictionary, n: int) -> Button:
	var st := Puzzles.status(p.id)
	var done := st in ["solved", "clean"]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(128, 150)
	var border := UITheme.EMERALD if done else (UITheme.GOLD_DARK if st == "revealed" else UITheme.BORDER_SOFT)
	b.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE, 12, border, 2 if done else 1))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_HI, 12, UITheme.GOLD, 2))
	b.add_theme_stylebox_override("pressed", UITheme.box(UITheme.SURFACE_HI, 12, UITheme.GOLD, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var start := Puzzles.fen_to_start(p.fen)
	b.tooltip_text = "%s to move" % start.turn.capitalize()
	b.pressed.connect(func(): chosen.emit(p.id))

	var v := UITheme.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var mb = preload("res://scenario_page.gd").MiniBoard.new()
	mb.board = start.board
	mb.cell = 15.0
	mb.white_bottom = start.turn == "white"
	mb.custom_minimum_size = Vector2(105, 105)
	mb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mb)
	var row := UITheme.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var dot := UITheme.label("●", 11, UITheme.IVORY if start.turn == "white" else Color("#7d89a8"), UITheme.ui(700))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.tooltip_text = ""
	row.add_child(dot)
	var nm := UITheme.label("#%d" % n, 13, UITheme.TEXT, UITheme.ui(650))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var sp := UITheme.spacer()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var tag := ""
	var tcol := UITheme.TEXT_FAINT
	match st:
		"clean": tag = "Solved"; tcol = UITheme.EMERALD
		"solved": tag = "Solved"; tcol = UITheme.EMERALD
		"revealed": tag = "Seen"; tcol = UITheme.GOLD
	var tl := UITheme.label(tag, 12, tcol, UITheme.ui(650))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tl)
	return b
