# puzzle_gen.gd
# Endless random puzzles: plays quick, deliberately sloppy engine games in a
# background thread and stops at the first position where the side to move
# has a forced mate in 2-4 that starts with exactly one move. The rest of
# the puzzle is played live: the engine checks each of your moves (any move
# that still mates in time is accepted) and plays the best defence.
#
# One instance lives under the scene tree root (PuzzleGen.get_instance());
# it runs its own Fairy-Stockfish process so it never disturbs a game.
class_name PuzzleGen
extends Node

signal generated(puzzle: Dictionary)

const SETUPS := ["classic", "shuffle", "shuffle", "vanguard", "royal_guard", "cavalry", "skirmish"]

static var _instance: PuzzleGen = null

var engine: FairyEngine = null
var ok := false
var current: Dictionary = {}     # the puzzle being played
var _ready_puzzles := {}         # target -> prefetched puzzle
var _gen_thread: Thread = null
var _gen_target := -1
var _stop := false
var _mutex := Mutex.new()
var _waiting_for := -1           # target someone is waiting on (-1 = none)
var _rng := RandomNumberGenerator.new()
var _job_thread: Thread = null   # live move checks


static func get_instance(tree: SceneTree) -> PuzzleGen:
	if _instance == null or not is_instance_valid(_instance):
		_instance = PuzzleGen.new()
		_instance.name = "PuzzleGen"
		tree.root.add_child(_instance)
	return _instance


func _ready():
	_rng.randomize()
	engine = FairyEngine.new()
	ok = engine.start(2, 32)
	if not ok:
		push_warning("Random puzzles unavailable: " + engine.last_error)


func _exit_tree():
	_stop = true
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	if _job_thread != null and _job_thread.is_started():
		_job_thread.wait_to_finish()
	if engine != null:
		engine.shutdown()


# ---- Generation ------------------------------------------------------------
# target: 2, 3 or 4 = mate in that many moves; 0 = any of them.
# Emits `generated` (deferred) when a puzzle is ready.
func request(target: int):
	if not ok:
		return
	if _ready_puzzles.has(target):
		var p: Dictionary = _ready_puzzles[target]
		_ready_puzzles.erase(target)
		_deliver.call_deferred(p)
		return
	_waiting_for = target
	_start_generation(target)


# Generate one in the background so the next request is instant.
func prefetch(target: int):
	if not ok or _ready_puzzles.has(target):
		return
	_start_generation(target)


func _start_generation(target: int):
	if _gen_thread != null:
		if _gen_thread.is_alive() and _gen_target == target:
			return   # already working on it
		_stop = true
		_gen_thread.wait_to_finish()
		_gen_thread = null
	_stop = false
	_gen_target = target
	_gen_thread = Thread.new()
	_gen_thread.start(_generate.bind(target, _rng.randi()))


func _on_generated(p: Dictionary):
	if _gen_thread != null and not _gen_thread.is_alive():
		_gen_thread.wait_to_finish()
		_gen_thread = null
	if p.is_empty():
		return
	if _waiting_for == p.target:
		_waiting_for = -1
		_deliver(p)
	else:
		_ready_puzzles[p.target] = p


func _deliver(p: Dictionary):
	current = p
	generated.emit(p)


func _generate(target: int, seed: int):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var scan_depth := 5
	while not _stop:
		var setup: String = SETUPS[rng.randi() % SETUPS.size()]
		var board: Array = Scenarios.make_board(setup)
		var start_fen := Scenarios.board_to_fen(board, "white")
		var moves := []
		var turn := "white"
		for ply in 120:
			if _stop:
				return
			var res := engine.analyse_fen(start_fen, moves, 4, scan_depth)
			if res.is_empty():
				break   # game over
			var m0: int = res[0].mate
			# A quick depth-5 scan only sees mates up to about 3 moves, so for
			# mate in 4 any big advantage is worth a deeper look.
			var candidate := m0 >= 2 and m0 <= 4 and (target == 0 or m0 == target)
			if target == 4 and m0 == 0 and res[0].cp >= 600:
				candidate = true
			if ply >= 8 and candidate and _piece_count(board) >= 9:
				var chk := engine.analyse_fen(start_fen, moves, 2, 13)
				var n: int = chk[0].mate if not chk.is_empty() else 0
				var unique: bool = chk.size() < 2 or chk[1].mate <= 0
				if n >= 2 and n <= 4 and (target == 0 or n == target) and unique:
					var p := {
						"id": "random", "random": true, "target": target, "n": n,
						"theme": "mate%d" % n,
						"fen": Scenarios.board_to_fen(board, turn).split(" ")[0] + (" w" if turn == "white" else " b"),
						"line": [chk[0].move],
						"setup": setup,
					}
					_on_generated.call_deferred(p)
					return
			# sloppy play: usually the best move, sometimes a worse one
			var pick: String = res[0].move
			if rng.randf() > 0.6 and res.size() > 1:
				pick = res[1 + rng.randi() % (res.size() - 1)].move
			moves.append(pick)
			apply_uci(board, pick)
			turn = "black" if turn == "white" else "white"


static func _piece_count(board: Array) -> int:
	var n := 0
	for r in board:
		for p in r:
			if p != "":
				n += 1
	return n


# Plays a UCI move on a board array (rank 1 = row 0), incl. promotion.
static func apply_uci(board: Array, mv: String):
	var m := Puzzles.uci_to_move(mv)
	var piece: String = board[m.from_row][m.from_col]
	board[m.from_row][m.from_col] = ""
	if piece.ends_with("D") and m.to_row == (6 if piece.begins_with("w") else 0):
		piece = piece[0] + "L"
	board[m.to_row][m.to_col] = piece


# ---- Live checking -----------------------------------------------------------
# Runs an analysis of the current puzzle (its FEN plus `moves`) off the main
# thread and calls `callback(result_array)` on the main thread.
func analyse_async(moves: Array, multipv: int, depth: int, callback: Callable):
	if _job_thread != null:
		_job_thread.wait_to_finish()
	_job_thread = Thread.new()
	var fen: String = current.fen + " - - 0 1"
	_job_thread.start(func():
		var r := engine.analyse_fen(fen, moves, multipv, depth)
		callback.call_deferred(r))
