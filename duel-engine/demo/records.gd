# records.gd
# Your win / loss / draw record against each of the seven nobles, saved in
# user://records.cfg. A game counts when exactly one side is a person and the
# other is one of the seven levels, in a fair starting position (Variants or
# Different armies; drills and handicap games don't count).
class_name Records
extends RefCounted

const PATH := "user://records.cfg"

static var _data := {}      # level id -> {w, l, d, w_white, w_black, streak, best_streak, last}
static var _loaded := false


static func _blank() -> Dictionary:
	return {"w": 0, "l": 0, "d": 0, "w_white": 0, "w_black": 0, "streak": 0, "best_streak": 0, "first_win": ""}


static func _ensure_loaded():
	if _loaded:
		return
	_loaded = true
	_data = {}
	for id in UITheme.LEVEL_IDS:
		_data[id] = _blank()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for id in UITheme.LEVEL_IDS:
		if cfg.has_section(id):
			for k in _blank():
				_data[id][k] = cfg.get_value(id, k, _data[id][k])


static func _save():
	var cfg := ConfigFile.new()
	for id in _data:
		for k in _data[id]:
			cfg.set_value(id, k, _data[id][k])
	cfg.save(PATH)


static func get_record(level_id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get(level_id, _blank()).duplicate()


static func counts_for_record(white: String, black: String, scenario_id: String) -> bool:
	var cat: String = Scenarios.get_info(scenario_id).category
	if cat != "variant" and cat != "asym":
		return false
	var wh := white == "human"
	var bh := black == "human"
	if wh == bh:
		return false
	var bot := black if wh else white
	return bot in UITheme.LEVEL_IDS


# result: "win" | "loss" | "draw", from the person's point of view.
static func add_result(level_id: String, result: String, human_color: String) -> void:
	_ensure_loaded()
	if not _data.has(level_id):
		return
	var r: Dictionary = _data[level_id]
	match result:
		"win":
			r.w += 1
			if human_color == "white":
				r.w_white += 1
			else:
				r.w_black += 1
			r.streak += 1
			r.best_streak = max(r.best_streak, r.streak)
			if r.first_win == "":
				r.first_win = Time.get_date_string_from_system()
		"loss":
			r.l += 1
			r.streak = 0
		_:
			r.d += 1
			r.streak = 0
	_save()


static func reset() -> void:
	_ensure_loaded()
	for id in _data:
		_data[id] = _blank()
	_save()


# "3-1-0" style summary (wins-losses-draws), "" if never played.
static func short_text(level_id: String) -> String:
	var r := get_record(level_id)
	if r.w + r.l + r.d == 0:
		return ""
	return "%d–%d–%d" % [r.w, r.l, r.d]


# Highest level beaten at least once (index into LEVEL_IDS), or -1.
static func highest_beaten() -> int:
	_ensure_loaded()
	var best := -1
	for i in UITheme.LEVEL_IDS.size():
		if _data[UITheme.LEVEL_IDS[i]].w > 0:
			best = i
	return best
