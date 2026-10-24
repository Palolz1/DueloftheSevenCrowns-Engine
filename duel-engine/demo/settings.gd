# settings.gd
# Player preferences, saved in user://settings.cfg. Everything reads them
# through the static helpers here, so there is no autoload to register.
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"

const BOARD_THEMES := [
	{"id": "walnut",  "name": "Walnut",  "light": Color("#e8dcc2"), "dark": Color("#a27d58")},
	{"id": "slate",   "name": "Slate",   "light": Color("#dde2ea"), "dark": Color("#7d8aa3")},
	{"id": "meadow",  "name": "Meadow",  "light": Color("#eeeed2"), "dark": Color("#769656")},
	{"id": "royal",   "name": "Royal",   "light": Color("#e4e7f3"), "dark": Color("#5f6fae")},
	{"id": "rosewood", "name": "Rosewood", "light": Color("#f0d9c8"), "dark": Color("#a5605a")},
]

const ANIM_SPEEDS := [
	{"id": "normal", "name": "Normal", "factor": 1.0},
	{"id": "fast",   "name": "Fast",   "factor": 0.45},
	{"id": "off",    "name": "Off",    "factor": 0.0},
]

const DEFAULTS := {
	"sound_volume": 80,      # 0..100, 0 = muted
	"anim_speed": "normal",
	"board_theme": "walnut",
	"show_coords": true,
	"show_legal": true,      # dots for the selected piece's moves
	"hover_preview": true,   # hovering a piece shows what it attacks
	"show_eval": true,       # evaluation bar + graph in game
	"fullscreen": false,
}

static var _values := {}
static var _loaded := false


static func _ensure_loaded():
	if _loaded:
		return
	_loaded = true
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cfg.has_section_key("settings", k):
			_values[k] = cfg.get_value("settings", k)
	# older builds stored the eval switch on its own
	if cfg.has_section_key("display", "show_eval") and not cfg.has_section_key("settings", "show_eval"):
		_values.show_eval = bool(cfg.get_value("display", "show_eval"))


static func get_value(key: String):
	_ensure_loaded()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value) -> void:
	_ensure_loaded()
	_values[key] = value
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # keep anything else in the file
	for k in _values:
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)
	if key == "fullscreen":
		apply_window()


static func reset_to_defaults() -> void:
	for k in DEFAULTS:
		set_value(k, DEFAULTS[k])


# ---- Convenience readers ---------------------------------------------------
static func board_colors() -> Array:
	var id: String = get_value("board_theme")
	for t in BOARD_THEMES:
		if t.id == id:
			return [t.light, t.dark]
	return [BOARD_THEMES[0].light, BOARD_THEMES[0].dark]


static func anim_factor() -> float:
	var id: String = get_value("anim_speed")
	for a in ANIM_SPEEDS:
		if a.id == id:
			return a.factor
	return 1.0


static func volume_db() -> float:
	var v := float(get_value("sound_volume"))
	return -80.0 if v <= 0.0 else linear_to_db(v / 100.0)


static func apply_window() -> void:
	var fs: bool = get_value("fullscreen")
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fs and not is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fs and is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
