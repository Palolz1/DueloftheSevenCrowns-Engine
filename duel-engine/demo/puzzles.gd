# puzzles.gd
# Tactics puzzles. Every position comes from a computer game of Duel of the
# Seven Crowns and was checked with Fairy-Stockfish:
#   * mate1..mate3: a forced mate where each of your moves is the only one
#     that mates in time (any mating final move is accepted in game);
#   * win: exactly one move wins a lot of material; every other move is at
#     least 3.5 pawns worse.
# "line" lists the moves in engine notation (file a-g + rank 1-7, rank 1 =
# White's back row; promotions end in "l"), alternating you / the computer.
# Progress is saved in user://puzzles.cfg.
class_name Puzzles
extends RefCounted

const PROGRESS_PATH := "user://puzzles.cfg"

const THEMES := [
	{"id": "mate1", "name": "Mate in 1", "desc": "One move, checkmate. Warm-ups."},
	{"id": "win",   "name": "Winning move", "desc": "One move wins material. Find the tactic."},
	{"id": "mate2", "name": "Mate in 2", "desc": "Your move, their best defence, then mate."},
	{"id": "mate3", "name": "Mate in 3", "desc": "Longer forced mates. Calculate the whole line."},
]

static var _progress := {}   # id -> "solved" | "clean" | "revealed"
static var _loaded := false


static func theme_name(id: String) -> String:
	for t in THEMES:
		if t.id == id:
			return t.name
	return id


static func get_puzzle(id: String) -> Dictionary:
	for p in LIST:
		if p.id == id:
			return p
	return {}


static func in_theme(theme: String) -> Array:
	var out := []
	for p in LIST:
		if p.theme == theme:
			out.append(p)
	return out


# Next puzzle after `id` that isn't solved yet (same theme first, then any).
static func next_unsolved(after_id: String = "") -> String:
	var start := 0
	var theme := ""
	for i in LIST.size():
		if LIST[i].id == after_id:
			start = i + 1
			theme = LIST[i].theme
	for pass_theme in [theme, ""]:
		for k in LIST.size():
			var p: Dictionary = LIST[(start + k) % LIST.size()]
			if (pass_theme == "" or p.theme == pass_theme) and status(p.id) not in ["solved", "clean"]:
				return p.id
	return ""


# ---- Board helpers ------------------------------------------------------------
# FEN piece placement -> board array (row 0 = rank 1) and side to move.
static func fen_to_start(fen: String) -> Dictionary:
	var letters := {"k": "K", "n": "N", "c": "C", "e": "P", "m": "M", "d": "D", "l": "L", "w": "W"}
	var parts := fen.split(" ")
	var ranks := parts[0].split("/")
	var board := []
	for r in 7:
		var row := []
		for c in 7:
			row.append("")
		board.append(row)
	for i in ranks.size():
		var r := 6 - i
		var c := 0
		for ch in ranks[i]:
			if ch.is_valid_int():
				c += int(ch)
			else:
				var white := ch == ch.to_upper()
				board[r][c] = ("w" if white else "b") + letters[ch.to_lower()]
				c += 1
	return {"board": board, "turn": "white" if parts.size() < 2 or parts[1] == "w" else "black"}


# "c2b1" -> {from_row, from_col, to_row, to_col}
static func uci_to_move(mv: String) -> Dictionary:
	var files := "abcdefg"
	return {
		"from_col": files.find(mv[0]), "from_row": int(mv[1]) - 1,
		"to_col": files.find(mv[2]), "to_row": int(mv[3]) - 1,
	}


# ---- Progress -------------------------------------------------------------------
static func _ensure_loaded():
	if _loaded:
		return
	_loaded = true
	_progress = {}
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK and cfg.has_section("progress"):
		for k in cfg.get_section_keys("progress"):
			_progress[k] = cfg.get_value("progress", k)


static func status(id: String) -> String:
	_ensure_loaded()
	return _progress.get(id, "")


# "clean" = solved first try without hints; "solved" = solved after a
# mistake or a hint; "revealed" = solution shown. Never downgrades.
static func set_status(id: String, st: String) -> void:
	_ensure_loaded()
	var rank := {"": 0, "revealed": 1, "solved": 2, "clean": 3}
	if rank.get(st, 0) <= rank.get(_progress.get(id, ""), 0):
		return
	_progress[id] = st
	var cfg := ConfigFile.new()
	for k in _progress:
		cfg.set_value("progress", k, _progress[k])
	cfg.save(PROGRESS_PATH)


static func solved_count(theme: String = "") -> int:
	_ensure_loaded()
	var n := 0
	for p in LIST:
		if (theme == "" or p.theme == theme) and status(p.id) in ["solved", "clean"]:
			n += 1
	return n


static func reset_progress() -> void:
	_progress = {}
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.save(PROGRESS_PATH)


const LIST := [
	{"id": "m1-01", "theme": "mate1", "fen": "4k2/d1dd2d/1d2n1d/2N2n1/2D1c2/D6/2e1K2 b", "line": ["e3e2"]},
	{"id": "m1-02", "theme": "mate1", "fen": "cnek2m/ddd1wdd/2dd1D1/7/D1C1n2/D1DDKDD/1NE1W1M b", "line": ["e6e4"]},
	{"id": "m1-03", "theme": "mate1", "fen": "1nn2k1/7/2d1WD1/C1D2d1/4D2/e6/2K2N1 w", "line": ["e5f6"]},
	{"id": "m1-04", "theme": "mate1", "fen": "3kw2/d2dddn/1d1N1d1/2Dd3/4K1D/DDDD2c/1C4m b", "line": ["e7e5"]},
	{"id": "m1-05", "theme": "mate1", "fen": "1kNC3/6d/W4D1/1d5/DnD3D/D2D3/3K2M w", "line": ["a5a6"]},
	{"id": "m1-06", "theme": "mate1", "fen": "7/d5d/D1d2Dk/7/3l3/K6/2c4 b", "line": ["c1b2"]},
	{"id": "m1-07", "theme": "mate1", "fen": "2k4/2dd3/d3d2/7/1DDdw1D/2DD2D/1C1K3 b", "line": ["e3d2"]},
	{"id": "m1-08", "theme": "mate1", "fen": "1k1c1M1/dd3d1/2dDNd1/1D2D2/2D1C2/4D2/2K4 w", "line": ["f7d7"]},
	{"id": "m1-09", "theme": "mate1", "fen": "k6/1E3d1/2d1L1D/d2W3/1D3d1/1DDDD1K/C6 w", "line": ["d4c5"]},
	{"id": "m1-10", "theme": "mate1", "fen": "c3k2/d1dd3/2d1dDM/n2C3/D6/D1DD2D/3K3 w", "line": ["g5g7"]},
	{"id": "m1-11", "theme": "mate1", "fen": "7/d1d4/1k5/7/4D1D/2e1K2/1l1l3 b", "line": ["b1c3"]},
	{"id": "m1-12", "theme": "mate1", "fen": "4k2/1K5/4dCN/dD5/1D3D1/2D1dD1/7 w", "line": ["f5e6"]},
	{"id": "m1-13", "theme": "mate1", "fen": "c2k1nm/d1dd1d1/1Dd1dd1/2e4/D1N1Dn1/D1DDMKD/C1E2N1 b", "line": ["g7g4"]},
	{"id": "m1-14", "theme": "mate1", "fen": "3kL2/cde1E1d/1dd2dw/4M2/1D2W1D/D1K1D2/3n3 w", "line": ["e7d5"]},
	{"id": "m1-15", "theme": "mate1", "fen": "3k3/3d3/d3d2/1Dc4/3n1l1/2K4/2l4 b", "line": ["c1a3"]},
	{"id": "w-01", "theme": "win", "fen": "2k4/d1ndmMd/dD1dd2/1D1c2D/D1N4/3D1D1/3KW2 w", "line": ["f6e6"]},
	{"id": "w-02", "theme": "win", "fen": "N1E1k2/1ddddd1/1dn1nd1/7/1DD2D1/DK1DDD1/1C2m2 w", "line": ["c7d4"]},
	{"id": "w-03", "theme": "win", "fen": "1n4m/dkdd1dd/de2d1n/1c5/2NDND1/CDKDDD1/4W1M w", "line": ["c3b5"]},
	{"id": "w-04", "theme": "win", "fen": "2k4/2c1d1d/dD1D3/dD1Dnd1/7/D4D1/2CKM1m b", "line": ["e4f2"]},
	{"id": "w-05", "theme": "win", "fen": "3e1k1/d1d2d1/d2D1d1/1DN1Dd1/4D2/7/nN1K3 b", "line": ["d7c4"]},
	{"id": "w-06", "theme": "win", "fen": "7/dd5/5d1/4D2/2kDK2/D6/7 w", "line": ["e4d5"]},
	{"id": "w-07", "theme": "win", "fen": "4k2/4D2/1dm3D/1c3M1/D6/2DDDn1/1K5 b", "line": ["c5e6"]},
	{"id": "w-08", "theme": "win", "fen": "ck5/d1d4/1Dd1dm1/1N1dn2/1DD1D2/3d3/C1K3M b", "line": ["f5g3"]},
	{"id": "w-09", "theme": "win", "fen": "1c4m/1dNkn1d/2ddMEd/4e1d/1D1D1D1/1D1DKD1/C6 w", "line": ["e5e4"]},
	{"id": "w-10", "theme": "win", "fen": "3k3/2nddd1/1N2m2/1dDDd1n/3D3/CD1W1D1/K6 b", "line": ["e5b5"]},
	{"id": "w-11", "theme": "win", "fen": "7/k1w1md1/Md1D1d1/2DdC1D/D6/2nDED1/3K3 b", "line": ["a6a5"]},
	{"id": "w-12", "theme": "win", "fen": "1n1kw2/2eddn1/2d1dd1/d1E1W2/2N2Dm/DDMDDD1/C3K2 b", "line": ["c5c4"]},
	{"id": "w-13", "theme": "win", "fen": "1e1kw1m/2d1ddd/4d2/2d1W2/D3N1M/D1DKD2/1N5 b", "line": ["e5e4"]},
	{"id": "w-14", "theme": "win", "fen": "5e1/1d1km1d/2dc2d/4d1d/DDCD1D1/2nD1DE/1M3K1 b", "line": ["c2e3"]},
	{"id": "w-15", "theme": "win", "fen": "2ekw1m/ndddddd/4n2/6M/D3ND1/D1DDDD1/CN1KW2 w", "line": ["g4a4"]},
	{"id": "w-16", "theme": "win", "fen": "2k1w1m/d1dnd1d/2d2Nd/1e5/5D1/DDDDDD1/C1EKW2 w", "line": ["c1b4"]},
	{"id": "w-17", "theme": "win", "fen": "c2kw2/1dddded/1d3md/2DE3/3DDM1/1D1KDn1/CN2WN1 b", "line": ["f5f3"]},
	{"id": "w-18", "theme": "win", "fen": "c1ek3/dddd1dd/3dm2/4D2/2W1D2/DD1DD1w/C1EK2M w", "line": ["g1g2"]},
	{"id": "w-19", "theme": "win", "fen": "c1ekwn1/dddd1dd/2nd3/1E2m1M/D4D1/D1DDDD1/CN1KWN1 w", "line": ["g4e4"]},
	{"id": "w-20", "theme": "win", "fen": "1c1k3/1ddnD2/5d1/d2dD2/1D1WN1D/1DK4/7 b", "line": ["d4d3"]},
	{"id": "m2-01", "theme": "mate2", "fen": "3kw2/d2d1dd/dd5/D1WK3/2D2D1/2D1Dm1/7 b", "line": ["e7e5", "d4e5", "f2g4"]},
	{"id": "m2-02", "theme": "mate2", "fen": "7/2M4/3e1d1/D1d1dkD/D2Dn2/3D1K1/7 w", "line": ["c6e6", "f4g4", "e6e4"]},
	{"id": "m2-03", "theme": "mate2", "fen": "7/d1dk1m1/2d1D2/4M1D/1d1Dd2/D6/4c1K b", "line": ["f6e4", "d3c4", "e4g4"]},
	{"id": "m2-04", "theme": "mate2", "fen": "5k1/d2d2d/dcn2N1/2DKdW1/2D2D1/4DD1/m6 b", "line": ["a1d1", "e2d3", "d1d3"]},
	{"id": "m2-05", "theme": "mate2", "fen": "1n1kwnm/cdd1d1d/1d2d2/1e1W1d1/D4D1/D1DDDD1/CNEK1NM w", "line": ["d4d5", "d7c7", "c1d4"]},
	{"id": "m2-06", "theme": "mate2", "fen": "k1c4/d6/1E2n2/2dD1d1/CD5/1KDmD2/7 w", "line": ["a3c5", "c7b6", "c5b6"]},
	{"id": "m2-07", "theme": "mate2", "fen": "3k3/d1ddddd/dN5/2M4/3m1DN/DnD1DD1/C1E2K1 b", "line": ["d3c1", "f1g2", "c1e1"]},
	{"id": "m2-08", "theme": "mate2", "fen": "1k5/dd3Nd/7/3n2D/D1DcD2/DK5/7 b", "line": ["d3c2", "b2a1", "d4b3"]},
	{"id": "m2-09", "theme": "mate2", "fen": "c2k1n1/1dd3d/Kd1Ed1d/2M4/D4D1/Dn1DDD1/1N1m3 b", "line": ["b2c4", "a5a4", "d1b2"]},
	{"id": "m2-10", "theme": "mate2", "fen": "4Lk1/d3dem/1d1N3/4D2/dn1D1WD/1D2K2/7 w", "line": ["f3f5", "f6f5", "e7f5"]},
	{"id": "m2-11", "theme": "mate2", "fen": "c1ekw1m/ddndddd/2n4/d1NE3/4WD1/DDDDDD1/C2K1NM w", "line": ["c4b6", "a7b6", "d4c4"]},
	{"id": "m2-12", "theme": "mate2", "fen": "3k3/2d2d1/dd1N1d1/2D4/DE1Dd1m/2D4/C3K2 b", "line": ["g3f3", "e1d1", "f3f1"]},
	{"id": "m2-13", "theme": "mate2", "fen": "3M3/d1dd3/dk5/4D2/Dm2d2/D5D/4K2 b", "line": ["b3d3", "e1f1", "d3d1"]},
	{"id": "m2-14", "theme": "mate2", "fen": "2k4/1D5/6d/D1lL1K1/7/7/3l3 b", "line": ["d1d3", "f4g5", "c4e4"]},
	{"id": "m2-15", "theme": "mate2", "fen": "4k2/2d2d1/1d2Kd1/1dD1E2/D1mDN2/2D4/7 w", "line": ["c2c3", "b5a4", "e3d5"]},
	{"id": "m2-16", "theme": "mate2", "fen": "c4nM/d1kd1d1/d2d3/m4D1/1D1D1DN/3DDE1/4K2 b", "line": ["a4a1", "f2c1", "a1c1"]},
	{"id": "m2-17", "theme": "mate2", "fen": "1e5/ddm1k1d/1c1M3/4D1D/DnCn2N/D2D1D1/3K3 w", "line": ["d5f6", "e6e7", "g3f5"]},
	{"id": "m2-18", "theme": "mate2", "fen": "c1Nkw2/2dddd1/1d3d1/2d1n2/3nD2/NDD1MmD/CK2E2 b", "line": ["e4d2", "e2d2", "f2d2"]},
	{"id": "m3-01", "theme": "mate3", "fen": "1e2k2/cd3d1/3d3/4EMD/2D4/DD1D1D1/4K2 w", "line": ["f4d5", "e7e6", "d5d4", "e6e7", "d4c6"]},
	{"id": "m3-02", "theme": "mate3", "fen": "E3e2/1d1ddd1/1dk4/2m1d1D/2ND3/2N1D2/3K1W1 b", "line": ["c4c3", "d1c1", "c3b3", "c1d1", "b3d3"]},
	{"id": "m3-03", "theme": "mate3", "fen": "3k3/4d2/D1cd3/2N2D1/C2d3/1K5/7 w", "line": ["a3c5", "d7c7", "a5b6", "d3c2", "c5d6"]},
	{"id": "m3-04", "theme": "mate3", "fen": "Mn1k3/1d2m2/2d4/2DD1Dd/Nd3d1/D1DK1n1/1E3N1 b", "line": ["e6e4", "d2c1", "f2d3", "c1d1", "e4f2"]},
	{"id": "m3-05", "theme": "mate3", "fen": "1n1k3/d1d2d1/1Nd1d2/1cd2mE/2Dd3/D1D1D1D/4K2 b", "line": ["f4f3", "e1d1", "f3g1", "g4f1", "g1f1"]},
	{"id": "m3-06", "theme": "mate3", "fen": "3m3/1k1K3/d6/1D2M2/1D5/6D/7 w", "line": ["d6d7", "b6b7", "e4d6", "b7a7", "d7e6"]},
	{"id": "m3-07", "theme": "mate3", "fen": "k3L2/7/1d2d2/D1nD3/DN1d2D/1d1c3/K6 b", "line": ["b2c1l", "b3c1", "d2c3", "a1b1", "c3b2"]},
	{"id": "m3-08", "theme": "mate3", "fen": "c6/2k1dd1/4nd1/3e2m/1DD1D2/1CD1DWD/3KM2 b", "line": ["g4f2", "d1d2", "e5f3", "e1f3", "f2d3"]},
	{"id": "m3-09", "theme": "mate3", "fen": "3kc2/1d1d3/1dK1C2/1D1N3/1D3D1/2D1dD1/7 w", "line": ["c5b6", "e2f1l", "e5f5", "e7e6", "f5e6"]},
	{"id": "m3-10", "theme": "mate3", "fen": "7/d2d3/1k5/7/1d1DWc1/D1NDE2/l1e1K2 b", "line": ["a1c2", "e1f1", "c2e3", "e2e3", "f3f2"]},
	{"id": "m3-11", "theme": "mate3", "fen": "c1k4/1d2dm1/2d3n/D1EM3/7/D1DK1DD/C6 w", "line": ["c4b4", "c7b7", "d4d6", "b7a6", "b4b3"]},
	{"id": "m3-12", "theme": "mate3", "fen": "7/d3d2/1d3ek/3DDN1/d4WD/1D5/3K3 w", "line": ["f3g4", "g5f6", "g4g6", "f6e7", "g6e6"]},
	{"id": "m3-13", "theme": "mate3", "fen": "2k4/dE5/5dd/1N1KD2/D1D3D/7/7 w", "line": ["d4c5", "f5g4", "b4d5", "c7d7", "b6e7"]},
	{"id": "m3-14", "theme": "mate3", "fen": "3k1C1/1d1dn2/3Dw1d/2M4/1D3dW/D2K2D/7 w", "line": ["c4e5", "d7c7", "d5c6", "c7b7", "e5a5"]},
]
