# fairy_engine.gd
# Talks to a Fairy-Stockfish process over UCI, playing the "sevencrowns"
# variant defined in res://fsf/sevencrowns.ini.
#
# The engine binaries and the .ini ship inside the game (res://fsf/). Files in
# res:// can't be executed directly (in an exported game they live inside the
# .pck), so on start-up they're copied to user://fsf/ and run from there.
#
# Results use the same dictionary shape as DuelEngine.find_best_move():
#   from_row, from_col, to_row, to_col, score (centipawns, side to move),
#   mate ("M3" / "-M2" White-relative, "" if none), depth, nodes, time_ms
# so the rest of the game doesn't care which engine produced them.
class_name FairyEngine
extends RefCounted

const FSF_RES_DIR := "res://fsf/"
const FSF_USER_DIR := "user://fsf/"
const INI_NAME := "sevencrowns.ini"
const VARIANT := "sevencrowns"
const START_FEN := "cnekwnm/ddddddd/7/7/7/DDDDDDD/CNEKWNM w - - 0 1"
const FILES := "abcdefg"
const MATE_SCORE := 1000000
const MAX_LINES := 200000  # safety valve against a runaway read loop

var ok := false
var last_error := ""

var _stdio: FileAccess = null
var _pid := -1
var _skill := 20  # current "Skill Level" option (0 = weakest, 20 = full strength)
var _start_fen := START_FEN  # starting position of the current game (scenarios)
var _mutex := Mutex.new()


static func binary_name() -> String:
	match OS.get_name():
		"Windows":
			return "fairy-stockfish-windows.exe"
		"macOS":
			return "fairy-stockfish-macos"
		_:
			return "fairy-stockfish-linux"


# UCI move string for a move given in board coordinates
# (row r = rank r+1, col c = file a+c; promotions get the Lancer suffix).
static func move_to_uci(fr: int, fc: int, tr: int, tc: int, promotion: bool) -> String:
	return "%s%d%s%d%s" % [FILES[fc], fr + 1, FILES[tc], tr + 1, "l" if promotion else ""]


# ------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------
func start(threads: int, hash_mb: int = 64) -> bool:
	var exe := _install(binary_name())
	var ini := _install(INI_NAME)
	if exe == "" or ini == "":
		last_error = "Fairy-Stockfish files missing (expected %s%s and %s%s)" % [FSF_RES_DIR, binary_name(), FSF_RES_DIR, INI_NAME]
		return false
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", exe])

	var info := OS.execute_with_pipe(exe, [])
	if info.is_empty():
		last_error = "Could not start " + exe
		return false
	_stdio = info["stdio"]
	_pid = info["pid"]

	_send("uci")
	if not _wait_for("uciok"):
		return _fail("no 'uciok' from engine")
	_send("setoption name VariantPath value " + ini)
	_send("setoption name UCI_Variant value " + VARIANT)
	_send("setoption name Threads value %d" % max(1, threads))
	_send("setoption name Hash value %d" % hash_mb)
	_send("isready")
	if not _wait_for("readyok"):
		return _fail("no 'readyok' after loading the variant")

	# Make sure the variant really loaded (an unknown variant silently falls
	# back to regular chess).
	_send("position startpos")
	_send("d")
	var fen_line: String = _wait_for("Fen:")
	if fen_line.strip_edges() != "Fen: " + START_FEN:
		return _fail("variant did not load (engine reports '%s')" % fen_line.strip_edges())

	ok = true
	return true


func new_game() -> void:
	if not ok:
		return
	_mutex.lock()
	_send("ucinewgame")
	_send("isready")
	_wait_for("readyok")
	_mutex.unlock()


# Asks a running search to finish now (UCI "stop"). Called from the main
# thread while a worker thread is blocked reading the reply, so it skips the
# mutex on purpose; the engine answers with its bestmove right away.
func stop_search() -> void:
	if ok:
		_send("stop")


func shutdown() -> void:
	if _pid > 0:
		if _stdio != null:
			_send("quit")
		OS.kill(_pid)
	_pid = -1
	_stdio = null
	ok = false


# ------------------------------------------------------------------
# Searching
# ------------------------------------------------------------------
# Best move for the position reached by `moves` (UCI strings from the start
# position). max_depth <= 0 means "no depth limit"; movetime_ms <= 0 means
# "no time limit" (then a depth must be given). skill: Fairy-Stockfish's
# "Skill Level" (0-20); below 20 it deliberately picks weaker moves.
func go(moves: Array, movetime_ms: int, max_depth: int, white_to_move: bool, skill: int = 20) -> Dictionary:
	if not ok:
		return {}
	_mutex.lock()
	var t0 := Time.get_ticks_msec()
	_set_skill(skill)
	_send(_position_cmd(moves))
	_send(_go_cmd(movetime_ms, max_depth))

	var best_info := {}
	var result := {}
	var n := 0
	while n < MAX_LINES:
		n += 1
		var line = _read_line()
		if line == null:
			ok = false
			break
		if line.begins_with("info ") and line.contains(" score ") and not line.contains("bound"):
			var mpv := _field_int(line, "multipv", 1)
			if mpv == 1:
				best_info = _parse_info(line)
		elif line.begins_with("bestmove"):
			var bm_parts: PackedStringArray = line.split(" ", false)
			var mv: String = bm_parts[1] if bm_parts.size() > 1 else "(none)"
			if mv != "(none)" and mv.length() >= 4:
				result = _uci_to_coords(mv)
				result["score"] = best_info.get("score", 0)
				result["depth"] = best_info.get("depth", 0)
				result["nodes"] = best_info.get("nodes", 0)
				result["mate"] = _mate_string(best_info.get("mate_moves", 0), white_to_move)
				result["time_ms"] = float(Time.get_ticks_msec() - t0)
			break
	_mutex.unlock()
	return result


# Scores every legal move (MultiPV search). Returns an Array of dictionaries
# {from_row, from_col, to_row, to_col, score} with side-to-move centipawns,
# like DuelEngine.score_moves().
func score_all(moves: Array, depth: int, movetime_ms: int) -> Array:
	if not ok:
		return []
	_mutex.lock()
	_set_skill(20)  # rankings must be honest, whatever level is playing
	_send("setoption name MultiPV value 256")
	_send(_position_cmd(moves))
	_send(_go_cmd(movetime_ms, depth))

	var by_move := {}  # uci move -> {depth, score}
	var n := 0
	while n < MAX_LINES:
		n += 1
		var line = _read_line()
		if line == null:
			ok = false
			break
		if line.begins_with("info ") and line.contains(" score ") and line.contains(" pv ") and not line.contains("bound"):
			var info := _parse_info(line)
			var pv_parts: PackedStringArray = line.split(" pv ", false)
			var first: String = pv_parts[1].split(" ", false)[0] if pv_parts.size() > 1 else ""
			if first != "":
				var prev = by_move.get(first)
				if prev == null or info.depth >= prev.depth:
					by_move[first] = info
		elif line.begins_with("bestmove"):
			break
	_send("setoption name MultiPV value 1")
	_mutex.unlock()

	var out: Array = []
	for mv in by_move.keys():
		var d := _uci_to_coords(mv)
		d["score"] = by_move[mv].score
		out.append(d)
	return out


# Top `multipv` lines for a position given as a FEN plus moves (doesn't use
# or change the game's start position, so other threads can share the
# engine). Returns [{move, mate, cp, depth}] best first; mate is from the
# side to move's point of view (+3 = it mates in 3, -2 = it gets mated in 2).
func analyse_fen(fen: String, moves: Array, multipv: int, depth: int, movetime_ms: int = 0) -> Array:
	if not ok:
		return []
	_mutex.lock()
	_set_skill(20)
	_send("setoption name MultiPV value %d" % multipv)
	var cmd := "position fen " + fen
	if not moves.is_empty():
		cmd += " moves " + " ".join(PackedStringArray(moves))
	_send(cmd)
	_send(_go_cmd(movetime_ms, depth))
	var lines := {}
	var n := 0
	while n < MAX_LINES:
		n += 1
		var line = _read_line()
		if line == null:
			ok = false
			break
		if line.begins_with("info ") and line.contains(" score ") and line.contains(" pv ") and not line.contains("bound"):
			var info := _parse_info(line)
			var k := _field_int(line, "multipv", 1)
			var pv: PackedStringArray = line.split(" pv ", false)[1].split(" ", false)
			lines[k] = {"move": pv[0], "mate": info.mate_moves, "cp": info.score if info.mate_moves == 0 else 0, "depth": info.depth}
		elif line.begins_with("bestmove"):
			break
	_send("setoption name MultiPV value 1")
	_mutex.unlock()
	var out := []
	var keys := lines.keys()
	keys.sort()
	for k in keys:
		out.append(lines[k])
	return out


# ------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------
func _fail(msg: String) -> bool:
	last_error = msg
	shutdown()
	return false


# Copies res://fsf/<file> to user://fsf/<file> if it's missing or different,
# and returns the absolute path of the copy ("" if the source doesn't exist).
static func _install(file: String) -> String:
	var src := FSF_RES_DIR + file
	if not FileAccess.file_exists(src):
		return ""
	DirAccess.make_dir_recursive_absolute(FSF_USER_DIR)
	var dst := FSF_USER_DIR + file
	if not FileAccess.file_exists(dst) or FileAccess.get_md5(dst) != FileAccess.get_md5(src):
		var data := FileAccess.get_file_as_bytes(src)
		var f := FileAccess.open(dst, FileAccess.WRITE)
		if f != null:
			f.store_buffer(data)
			f.close()
		elif not FileAccess.file_exists(dst):
			return ""
		# (if the copy failed because an old engine process still has the file
		# open, just run the existing copy)
	return ProjectSettings.globalize_path(dst)


func _set_skill(skill: int) -> void:
	skill = clampi(skill, 0, 20)
	if skill != _skill:
		_send("setoption name Skill Level value %d" % skill)
		_skill = skill


func _send(cmd: String) -> void:
	if _stdio == null:
		return
	_stdio.store_string(cmd + "\n")
	_stdio.flush()


# Next line from the engine, or null if the process has gone away.
func _read_line():
	if _stdio == null:
		return null
	var line := _stdio.get_line()
	if line == "" and (_stdio.eof_reached() or _stdio.get_error() != OK):
		return null
	return line.strip_edges(false, true)


# Reads until a line starting with `prefix`; returns that line ("" on failure).
func _wait_for(prefix: String) -> String:
	for i in MAX_LINES:
		var line = _read_line()
		if line == null:
			return ""
		if line.begins_with(prefix):
			return line
	return ""


# Starting position for the following searches (set once per game, before
# any search runs). Moves are always given relative to it.
func set_start_fen(fen: String) -> void:
	_start_fen = fen

func _position_cmd(moves: Array) -> String:
	var base := "position startpos" if _start_fen == START_FEN else "position fen " + _start_fen
	if moves.is_empty():
		return base
	return base + " moves " + " ".join(PackedStringArray(moves))


func _go_cmd(movetime_ms: int, depth: int) -> String:
	var cmd := "go"
	if depth > 0:
		cmd += " depth %d" % depth
	if movetime_ms > 0:
		cmd += " movetime %d" % movetime_ms
	return cmd


func _uci_to_coords(mv: String) -> Dictionary:
	return {
		"from_row": int(mv[1]) - 1,
		"from_col": FILES.find(mv[0]),
		"to_row": int(mv[3]) - 1,
		"to_col": FILES.find(mv[2]),
	}


static func _field_int(line: String, key: String, default_value: int) -> int:
	var parts := line.split(" ", false)
	var i := parts.find(key)
	if i >= 0 and i + 1 < parts.size():
		return int(parts[i + 1])
	return default_value


# depth, nodes, score (side-to-move centipawns, mates mapped like DuelEngine:
# +/-(MATE_SCORE - plies)), mate_moves (side-to-move relative, 0 = no mate).
func _parse_info(line: String) -> Dictionary:
	var parts := line.split(" ", false)
	var d := {"depth": _field_int(line, "depth", 0), "nodes": _field_int(line, "nodes", 0), "score": 0, "mate_moves": 0}
	var i := parts.find("score")
	if i >= 0 and i + 2 < parts.size():
		var v := int(parts[i + 2])
		if parts[i + 1] == "cp":
			d.score = v
		elif parts[i + 1] == "mate":
			d.mate_moves = v
			if v > 0:
				d.score = MATE_SCORE - (2 * v - 1)
			else:
				d.score = -(MATE_SCORE - 2 * (-v))
	return d


static func _mate_string(mate_moves: int, white_to_move: bool) -> String:
	if mate_moves == 0:
		return ""
	var white_mates := (mate_moves > 0) == white_to_move
	return ("M%d" if white_mates else "-M%d") % abs(mate_moves)
