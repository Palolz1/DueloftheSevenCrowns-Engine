# ui_theme.gd
# Shared look for every screen: palette, fonts and small widget helpers.
# "Royal" theme -- deep ink-navy surfaces, gold accents, ivory / slate sides.
class_name UITheme
extends RefCounted

# ---- Palette ------------------------------------------------------------
const INK := Color("#0a0e19")          # app background
const INK_2 := Color("#10162a")        # raised background
const SURFACE := Color("#151c31")      # cards
const SURFACE_HI := Color("#1d2640")   # hovered / inset
const SURFACE_LO := Color("#0d1323")   # wells (graph, move list)
const BORDER := Color("#2a3556")
const BORDER_SOFT := Color("#212a45")

const GOLD := Color("#e2b65a")
const GOLD_LIGHT := Color("#f6dc9a")
const GOLD_DARK := Color("#a87a2a")

const TEXT := Color("#eef1f8")
const TEXT_DIM := Color("#a3adc4")
const TEXT_FAINT := Color("#65718f")

const IVORY := Color("#f4efe3")        # White's colour
const SLATE := Color("#2a3148")        # Black's colour
const RUBY := Color("#e0485e")
const EMERALD := Color("#3cc08d")
const SAPPHIRE := Color("#5b8df0")
const AMETHYST := Color("#a77bf2")
const AMBER := Color("#f0a640")

# The seven computer levels, weakest -> strongest. Players see noble titles;
# the ids are what the code uses internally (bot_diff, startgameplay).
# Count..Grand Prince are the "human-like" bots that make deliberate
# mistakes; King and Emperor -- the two sovereign titles -- are the full
# engine with no deliberate mistakes.
const LEVEL_IDS := ["beginner", "novice", "easy", "medium", "hard", "expert", "impossible"]
const LEVEL_TITLES := ["Count", "Marquess", "Duke", "Archduke", "Grand Prince", "King", "Emperor"]
const LEVEL_DIFFICULTY := ["Beginner", "Novice", "Easy", "Medium", "Hard", "Expert", "Impossible"]

# Difficulty ladder colours, weakest -> strongest
const LEVEL_COLORS := [
	Color("#7ddc9e"), Color("#4fc6a6"), Color("#58b4e8"), Color("#e2b65a"),
	Color("#f08a4b"), Color("#e8586e"), Color("#b36cf2"),
]

# ---- Fonts --------------------------------------------------------------
static var _fonts := {}

static func _font(path: String, weight: int) -> Font:
	var key := "%s@%d" % [path, weight]
	if _fonts.has(key):
		return _fonts[key]
	var base = load(path)
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_fonts[key] = f
	return f

static func display(weight: int = 700) -> Font:
	return _font("res://fonts/Cinzel.ttf", weight)

static func ui(weight: int = 400) -> Font:
	return _font("res://fonts/Inter.ttf", weight)

# Project-wide default theme so every plain Control uses Inter.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = ui(450)
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(SURFACE_HI, 8, BORDER, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t

# ---- StyleBoxes ---------------------------------------------------------
static func box(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

static func card(pad: int = 16) -> StyleBoxFlat:
	var s := box(SURFACE, 14, BORDER_SOFT, 1, pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	return s

# ---- Widgets ------------------------------------------------------------
static func label(text: String, size: int = 15, color: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	return l

static func heading(text: String, size: int = 13) -> Label:
	# Small all-caps section heading ("EVALUATION", "MOVES", ...)
	var l := label(text.to_upper(), size, TEXT_FAINT, ui(650))
	l.add_theme_constant_override("outline_size", 0)
	return l

# Variants: "primary" (gold), "secondary" (surface), "ghost" (outline), "danger"
static func button(text: String, variant: String = "secondary", font_size: int = 15, min_h: int = 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", ui(600))
	style_button(b, variant)
	return b

static func style_button(b: Button, variant: String) -> void:
	var bg: Color
	var fg: Color
	var border := Color(0, 0, 0, 0)
	var bw := 0
	match variant:
		"primary":
			bg = GOLD
			fg = Color("#1b1406")
		"danger":
			bg = RUBY
			fg = Color.WHITE
		"ghost":
			bg = Color(1, 1, 1, 0.0)
			fg = TEXT_DIM
			border = BORDER
			bw = 1
		_:
			bg = SURFACE_HI
			fg = TEXT
			border = BORDER
			bw = 1
	var n := box(bg, 10, border, bw, 10)
	var h := box(bg.lightened(0.10) if variant != "ghost" else Color(1, 1, 1, 0.05), 10, border.lightened(0.2), bw, 10)
	var p := box(bg.darkened(0.12) if variant != "ghost" else Color(1, 1, 1, 0.08), 10, border, bw, 10)
	var d := box(bg.darkened(0.35), 10, border, bw, 10)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg if variant != "ghost" else TEXT)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_hover_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", fg.darkened(0.4))

# A selectable "pill" for toggle groups; selected state uses `accent`.
static func pill(text: String, accent: Color = GOLD, font_size: int = 14, min_h: int = 36) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", ui(600))
	b.add_theme_stylebox_override("normal", box(SURFACE_LO, 9, BORDER_SOFT, 1, 8))
	b.add_theme_stylebox_override("hover", box(SURFACE_HI, 9, BORDER, 1, 8))
	var sel := box(Color(accent, 0.16), 9, accent, 2, 8)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT_DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", accent.lightened(0.25))
	b.add_theme_color_override("font_hover_pressed_color", accent.lightened(0.25))
	return b

static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func panel(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	return p

static func spacer(h_expand: bool = true) -> Control:
	var c := Control.new()
	if h_expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

# Round token with a piece sprite (same look as on the board).
static func piece_token(code: String, diameter: float = 40.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_white := code.begins_with("w")
	var t := Panel.new()
	t.size = Vector2(diameter, diameter)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := box(IVORY if is_white else SLATE, int(diameter / 2), GOLD_DARK if is_white else Color("#59647f"), 2)
	t.add_theme_stylebox_override("panel", st)
	holder.add_child(t)
	var names := {"K": "king", "N": "knight", "C": "cardinal", "P": "paladin", "M": "marshal", "D": "donkey", "L": "lancer", "W": "warden"}
	var tex = load("res://piecepng/%s.png" % names.get(code.substr(1, 1), "king"))
	var tr := TextureRect.new()
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var inner := diameter * 0.8
	tr.size = Vector2(inner, inner)
	tr.position = Vector2((diameter - inner) / 2.0, (diameter - inner) / 2.0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	return holder

# Full-screen page frame used by the Starting Positions, Puzzles, Records
# and Settings pages: background, title, subtitle and a Back button.
# Returns {"body": VBoxContainer, "back": Button, "head": HBoxContainer}.
static func page_shell(page: Control, title: String, subtitle: String) -> Dictionary:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	page.add_child(margin)
	var main := vbox(14)
	margin.add_child(main)
	var head := hbox(16)
	main.add_child(head)
	var titles := vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(label(title, 34, GOLD_LIGHT, display(700)))
	titles.add_child(label(subtitle, 15, TEXT_DIM, ui(500)))
	var back := button("Back", "secondary", 15, 40)
	back.custom_minimum_size.x = 110
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	return {"body": main, "back": back, "head": head}

# On/off switch styled like the rest of the UI.
static func switch(text: String, on: bool) -> CheckButton:
	var t := CheckButton.new()
	t.text = text
	t.button_pressed = on
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	t.add_theme_font_override("font", ui(550))
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", TEXT_DIM)
	t.add_theme_color_override("font_hover_color", TEXT)
	t.add_theme_color_override("font_pressed_color", TEXT)
	t.add_theme_color_override("font_hover_pressed_color", TEXT)
	return t
