# settings_page.gd
# Settings screen (from the setup screen or the in-game sidebar). Every
# change is saved straight away (settings.gd) and announced with `changed`
# so an open game can redraw.
extends Control

signal changed
signal closed

var _confirm := {}   # button -> original text, for two-click resets


func _ready():
	z_index = 200
	var shell := UITheme.page_shell(self, "Settings", "Saved automatically. Changes apply straight away.")
	shell.back.pressed.connect(func(): closed.emit())
	var body: VBoxContainer = shell.body

	var cols := UITheme.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UITheme.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := UITheme.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	# ---- Board ----
	var board := _card(left, "Board")
	board.add_child(_sub("Colours"))
	var themes := UITheme.hbox(10)
	board.add_child(themes)
	var tgroup := ButtonGroup.new()
	for t in Settings.BOARD_THEMES:
		themes.add_child(_theme_button(t, tgroup))
	board.add_child(_switch("Show coordinates (a–g, 1–7)", "show_coords"))
	board.add_child(_switch("Show legal moves for the selected piece", "show_legal"))
	board.add_child(_switch("Hover a piece to see what it attacks", "hover_preview"))

	# ---- Game ----
	var game := _card(left, "Game")
	game.add_child(_sub("Move animation"))
	var arow := UITheme.hbox(8)
	game.add_child(arow)
	var agroup := ButtonGroup.new()
	for a in Settings.ANIM_SPEEDS:
		var b := UITheme.pill(a.name, UITheme.GOLD, 14, 36)
		b.custom_minimum_size.x = 96
		b.button_group = agroup
		b.button_pressed = Settings.get_value("anim_speed") == a.id
		b.toggled.connect(func(on): if on: _store("anim_speed", a.id))
		arow.add_child(b)
	game.add_child(_switch("Show the evaluation bar and graph (E)", "show_eval"))

	# ---- Sound & window ----
	var sound := _card(right, "Sound and window")
	sound.add_child(_sub("Sound effects volume"))
	var vrow := UITheme.hbox(12)
	sound.add_child(vrow)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = int(Settings.get_value("sound_volume"))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 24
	vrow.add_child(slider)
	var vlabel := UITheme.label("", 14, UITheme.TEXT, UITheme.ui(650))
	vlabel.custom_minimum_size.x = 52
	vrow.add_child(vlabel)
	var show_vol := func(v): vlabel.text = "Off" if v <= 0 else "%d%%" % int(v)
	show_vol.call(slider.value)
	slider.value_changed.connect(func(v):
		show_vol.call(v)
		_store("sound_volume", int(v)))
	slider.drag_ended.connect(func(_c): SFXhandler.play("check"))
	sound.add_child(_switch("Fullscreen", "fullscreen"))

	# ---- Progress ----
	var prog := _card(right, "Progress")
	var note := UITheme.label("Your records against the seven nobles and your solved puzzles.", 13, UITheme.TEXT_FAINT, UITheme.ui(500))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prog.add_child(note)
	var prow := UITheme.hbox(10)
	prog.add_child(prow)
	prow.add_child(_reset_button("Reset records", func(): Records.reset()))
	prow.add_child(_reset_button("Reset puzzles", func(): Puzzles.reset_progress()))

	# ---- Keys ----
	var keys := _card(right, "Keyboard")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	keys.add_child(grid)
	for k in [["F", "Flip the board"], ["E", "Show / hide the evaluation"], ["I", "How the pieces move"],
			["Ctrl+Z", "Undo your last move"], ["← → Home End", "Step through a finished game"],
			["Right-click", "Mark a square (drag to draw an arrow)"],
			["+ Shift / Ctrl / Alt", "Red / blue / yellow instead of green"],
			["C or left-click", "Clear arrows and marks"]]:
		grid.add_child(UITheme.label(k[0], 13, UITheme.GOLD_LIGHT, UITheme.ui(700)))
		grid.add_child(UITheme.label(k[1], 13, UITheme.TEXT_DIM, UITheme.ui(500)))

	var foot := UITheme.hbox(10)
	body.add_child(foot)
	foot.add_child(UITheme.spacer())
	var defaults := UITheme.button("Restore default settings", "ghost", 13, 34)
	defaults.pressed.connect(func():
		Settings.reset_to_defaults()
		changed.emit()
		# rebuild so every control shows the defaults
		for ch in get_children():
			ch.queue_free()
		_ready())
	foot.add_child(defaults)


func _card(parent: Control, title: String) -> VBoxContainer:
	var card := UITheme.panel(UITheme.card(18))
	parent.add_child(card)
	var v := UITheme.vbox(10)
	card.add_child(v)
	v.add_child(UITheme.label(title, 20, UITheme.GOLD_LIGHT, UITheme.display(700)))
	return v


func _sub(t: String) -> Label:
	return UITheme.heading(t, 12)


func _switch(text: String, key: String) -> CheckButton:
	var sw := UITheme.switch(text, bool(Settings.get_value(key)))
	sw.toggled.connect(func(on): _store(key, on))
	return sw


func _store(key: String, value) -> void:
	Settings.set_value(key, value)
	changed.emit()


# Two squares of the board colours plus the theme name.
func _theme_button(t: Dictionary, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(82, 86)
	b.tooltip_text = t.name
	b.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE_LO, 10, UITheme.BORDER_SOFT, 1))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_HI, 10, UITheme.BORDER, 1))
	var sel := UITheme.box(Color(UITheme.GOLD, 0.12), 10, UITheme.GOLD, 2)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.button_pressed = Settings.get_value("board_theme") == t.id
	var v := UITheme.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 10
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var sw := ColorGrid.new()
	sw.light = t.light
	sw.dark = t.dark
	sw.custom_minimum_size = Vector2(44, 44)
	sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sw)
	var l := UITheme.label(t.name, 12, UITheme.TEXT_DIM, UITheme.ui(600))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.toggled.connect(func(on): if on: _store("board_theme", t.id))
	return b


# A reset button that needs a second click to confirm.
func _reset_button(text: String, action: Callable) -> Button:
	var b := UITheme.button(text, "ghost", 13, 36)
	b.custom_minimum_size.x = 150
	b.pressed.connect(func():
		if _confirm.get(b, "") == "":
			_confirm[b] = text
			b.text = "Click again to reset"
			UITheme.style_button(b, "danger")
		else:
			action.call()
			_confirm[b] = ""
			b.text = "Done"
			UITheme.style_button(b, "ghost")
			changed.emit())
	return b


class ColorGrid:
	extends Control
	var light := Color.WHITE
	var dark := Color.BLACK

	func _draw():
		var h := size.x / 3.0
		for r in 3:
			for c in 3:
				draw_rect(Rect2(c * h, r * h, h, h), light if (r + c) % 2 == 0 else dark)
