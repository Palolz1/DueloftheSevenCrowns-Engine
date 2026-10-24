# scenarios.gd
# Alternative starting positions ("Starting Positions" page).
#
# Boards are listed row 0 (White's back rank) .. row 6 (Black's back rank),
# one string per row, "." = empty square. Every position here was checked
# with both engines (identical perft counts) and given an engine verdict
# with Fairy-Stockfish; the verdict is shown on the page.
class_name Scenarios
extends RefCounted

const CATEGORIES := [
	{"id": "variant",  "title": "Variants",       "desc": "Balanced alternatives to the classic setup."},
	{"id": "practice", "title": "Practice",       "desc": "Drills to sharpen one skill. Play White against a computer."},
	{"id": "uneven",   "title": "Uneven armies",  "desc": "Lopsided fights: give a friend odds, or try to survive as the weaker side."},
]

# tone: "even" | "white" | "black" (who the engine says is better)
const LIST := [
	{"id": "classic", "category": "variant", "name": "Classic",
	 "desc": "The standard battle of the Seven Crowns.",
	 "verdict": "Even · tiny edge to White", "tone": "even",
	 "rows": ["wC wN wP wK wW wN wM", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "shuffle", "category": "variant", "name": "Shuffled Court",
	 "desc": "Back ranks are shuffled every game, mirrored for both sides; the King stays central. All 354 possible shuffles were engine-checked for fairness.",
	 "verdict": "Even · new every game", "tone": "even",
	 "rows": ["wW wC wN wK wM wP wN", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bW bC bN bK bM bP bN"]},
	{"id": "vanguard", "category": "variant", "name": "Vanguard",
	 "desc": "Both donkey walls start one rank further forward. Contact from the very first move.",
	 "verdict": "Even", "tone": "even",
	 "rows": ["wC wN wP wK wW wN wM", ". . . . . . .", "wD wD wD wD wD wD wD", ". . . . . . .", "bD bD bD bD bD bD bD", ". . . . . . .", "bC bN bP bK bW bN bM"]},
	{"id": "royal_guard", "category": "variant", "name": "Royal Guard",
	 "desc": "Each King stands alone on its back rank behind a wall of pieces, with the donkeys out in front.",
	 "verdict": "Even", "tone": "even",
	 "rows": [". . . wK . . .", "wC wN wP wW wP wN wC", "wD wD wD wD wD wD wD", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bW bP bN bC", ". . . bK . . ."]},

	{"id": "lancer_hunt", "category": "practice", "name": "Lancer's Hunt",
	 "desc": "King and Lancer against a lone King. Learn to trap the King with a piece that only leaps.",
	 "verdict": "White mates in 10", "tone": "white",
	 "rows": [". . . wK wL . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . . bK . . ."]},
	{"id": "marshal_mate", "category": "practice", "name": "Marshal's Mate",
	 "desc": "King and Marshal against a lone King: the easiest checkmate to learn.",
	 "verdict": "White mates in 6", "tone": "white",
	 "rows": [". . . wK wM . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . . bK . . ."]},
	{"id": "donkey_race", "category": "practice", "name": "Donkey Race",
	 "desc": "Kings and donkeys only. Learn to break through the wall and promote to a Lancer first.",
	 "verdict": "Even · drawish", "tone": "even",
	 "rows": [". . . wK . . .", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", ". . . bK . . ."]},

	{"id": "marshal_odds", "category": "uneven", "name": "Marshal Odds",
	 "desc": "White plays without its Marshal. The stronger player takes White to give a friend a fair game.",
	 "verdict": "Black +7.6", "tone": "black",
	 "rows": ["wC wN wP wK wW wN .", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "cardinal_legion", "category": "uneven", "name": "Cardinal Legion",
	 "desc": "White swaps its whole back rank for six Cardinals. Diagonals everywhere.",
	 "verdict": "White +3.3", "tone": "white",
	 "rows": ["wC wC wC wK wC wC wC", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "knightmare", "category": "uneven", "name": "Knightmare",
	 "desc": "Four Paladins and a wall of Knights for White. (Knights must guard b1 and f1, or it is mate in one!)",
	 "verdict": "White +28", "tone": "white",
	 "rows": ["wP wN wP wK wP wN wP", "wN wN wN wN wN wN wN", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "onslaught", "category": "uneven", "name": "Onslaught",
	 "desc": "Twenty donkeys and a King against a full army. Can the herd break through?",
	 "verdict": "Black +22", "tone": "black",
	 "rows": ["wD wD wD wK wD wD wD", "wD wD wD wD wD wD wD", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "god_army", "category": "uneven", "name": "God Army",
	 "desc": "Black fills three ranks with heavy pieces. Survive as White, if you can.",
	 "verdict": "Black has a forced win", "tone": "black",
	 "rows": ["wC wN wP wK wW wN wM", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", "bC bD bC bD bC bD bC", "bP bM bW bN bW bM bP", "bM bP bC bK bC bP bM"]},
]

# Back ranks (files a..g) for Shuffled Court that were checked as fair:
# no early forced mates and an engine eval within 0.6 of even.
const SAFE_SHUFFLES := [
	"CMNKNPW", "CMNKNWP", "CMNKPNW", "CMNKPWN", "CMNKWNP", "CMNKWPN", "CMPKNNW", "CMPKNWN", "CMPKWNN", "CMWKNNP",
	"CMWKNPN", "CMWKPNN", "CNMKNPW", "CNMKNWP", "CNMKPNW", "CNMKPWN", "CNMKWNP", "CNMKWPN", "CNNKMPW", "CNNKMWP",
	"CNNKPMW", "CNNKPWM", "CNNKWMP", "CNNKWPM", "CNPKMNW", "CNPKMWN", "CNPKNMW", "CNPKNWM", "CNPKWMN", "CNPKWNM",
	"CNWKMNP", "CNWKMPN", "CNWKNMP", "CNWKNPM", "CNWKPMN", "CNWKPNM", "CPMKNNW", "CPMKNWN", "CPMKWNN", "CPNKMNW",
	"CPNKMWN", "CPNKNMW", "CPNKNWM", "CPNKWMN", "CPNKWNM", "CPWKMNN", "CPWKNMN", "CPWKNNM", "CWMKNNP", "CWMKPNN",
	"CWNKMNP", "CWNKMPN", "CWNKNMP", "CWNKNPM", "CWNKPMN", "CWNKPNM", "CWPKMNN", "CWPKNMN", "CWPKNNM", "MCNKNPW",
	"MCNKNWP", "MCNKPNW", "MCNKPWN", "MCNKWNP", "MCNKWPN", "MCPKNNW", "MCPKNWN", "MCPKWNN", "MCWKNNP", "MCWKNPN",
	"MCWKPNN", "MNCKNPW", "MNCKNWP", "MNCKPNW", "MNCKPWN", "MNCKWNP", "MNCKWPN", "MNNKCPW", "MNNKCWP", "MNNKPCW",
	"MNNKPWC", "MNNKWCP", "MNNKWPC", "MNPKCNW", "MNPKCWN", "MNPKNCW", "MNPKNWC", "MNPKWCN", "MNPKWNC", "MNWKCNP",
	"MNWKCPN", "MNWKNCP", "MNWKNPC", "MNWKPCN", "MNWKPNC", "MPCKNNW", "MPCKNWN", "MPCKWNN", "MPNKCNW", "MPNKCWN",
	"MPNKNCW", "MPNKNWC", "MPNKWCN", "MPNKWNC", "MPWKCNN", "MPWKNCN", "MPWKNNC", "MWCKNNP", "MWCKNPN", "MWCKPNN",
	"MWNKCNP", "MWNKCPN", "MWNKNCP", "MWNKNPC", "MWNKPCN", "MWNKPNC", "MWPKCNN", "MWPKNCN", "MWPKNNC", "NCMKNPW",
	"NCMKNWP", "NCMKPNW", "NCMKPWN", "NCMKWNP", "NCMKWPN", "NCNKMPW", "NCNKMWP", "NCNKPMW", "NCNKPWM", "NCNKWMP",
	"NCNKWPM", "NCPKMNW", "NCPKMWN", "NCPKNMW", "NCPKNWM", "NCPKWMN", "NCPKWNM", "NCWKMNP", "NCWKMPN", "NCWKNMP",
	"NCWKNPM", "NCWKPMN", "NCWKPNM", "NMCKNPW", "NMCKNWP", "NMCKPNW", "NMCKPWN", "NMCKWNP", "NMCKWPN", "NMNKCPW",
	"NMNKCWP", "NMNKPCW", "NMNKPWC", "NMNKWCP", "NMNKWPC", "NMPKCNW", "NMPKCWN", "NMPKNCW", "NMPKWCN", "NMPKWNC",
	"NMWKCNP", "NMWKCPN", "NMWKNCP", "NMWKNPC", "NMWKPCN", "NMWKPNC", "NNCKMPW", "NNCKMWP", "NNCKPMW", "NNCKPWM",
	"NNCKWMP", "NNCKWPM", "NNMKCPW", "NNMKCWP", "NNMKPCW", "NNMKPWC", "NNMKWCP", "NNMKWPC", "NNPKCMW", "NNPKCWM",
	"NNPKMCW", "NNPKMWC", "NNPKWCM", "NNPKWMC", "NNWKCMP", "NNWKCPM", "NNWKMCP", "NNWKMPC", "NNWKPCM", "NNWKPMC",
	"NPCKMNW", "NPCKMWN", "NPCKNMW", "NPCKNWM", "NPCKWMN", "NPCKWNM", "NPMKCWN", "NPMKNCW", "NPMKNWC", "NPMKWCN",
	"NPMKWNC", "NPNKCMW", "NPNKCWM", "NPNKMCW", "NPNKMWC", "NPNKWCM", "NPNKWMC", "NPWKCMN", "NPWKCNM", "NPWKMCN",
	"NPWKMNC", "NPWKNCM", "NPWKNMC", "NWCKMNP", "NWCKMPN", "NWCKNMP", "NWCKNPM", "NWCKPMN", "NWCKPNM", "NWMKCNP",
	"NWMKCPN", "NWMKNCP", "NWMKNPC", "NWMKPCN", "NWMKPNC", "NWNKCMP", "NWNKCPM", "NWNKMPC", "NWNKPCM", "NWNKPMC",
	"NWPKCMN", "NWPKCNM", "NWPKMCN", "NWPKMNC", "NWPKNCM", "NWPKNMC", "PCMKNNW", "PCMKNWN", "PCMKWNN", "PCNKMNW",
	"PCNKMWN", "PCNKNMW", "PCNKNWM", "PCNKWMN", "PCNKWNM", "PCWKMNN", "PCWKNMN", "PCWKNNM", "PMCKNNW", "PMCKNWN",
	"PMCKWNN", "PMNKCNW", "PMNKCWN", "PMNKNCW", "PMNKNWC", "PMNKWCN", "PMNKWNC", "PMWKCNN", "PMWKNCN", "PMWKNNC",
	"PNCKMNW", "PNCKMWN", "PNCKNMW", "PNCKNWM", "PNCKWMN", "PNCKWNM", "PNMKCNW", "PNMKCWN", "PNMKNCW", "PNMKNWC",
	"PNMKWCN", "PNMKWNC", "PNNKCMW", "PNNKCWM", "PNNKMCW", "PNNKMWC", "PNNKWCM", "PNNKWMC", "PNWKCMN", "PNWKCNM",
	"PNWKMCN", "PNWKMNC", "PNWKNCM", "PNWKNMC", "PWCKMNN", "PWCKNMN", "PWCKNNM", "PWMKCNN", "PWMKNCN", "PWMKNNC",
	"PWNKCMN", "PWNKCNM", "PWNKMCN", "PWNKMNC", "PWNKNCM", "PWNKNMC", "WCMKNNP", "WCMKNPN", "WCMKPNN", "WCNKMNP",
	"WCNKMPN", "WCNKNMP", "WCNKNPM", "WCNKPMN", "WCNKPNM", "WCPKMNN", "WCPKNMN", "WCPKNNM", "WMCKNNP", "WMCKNPN",
	"WMCKPNN", "WMNKCNP", "WMNKCPN", "WMNKNCP", "WMNKNPC", "WMNKPCN", "WMNKPNC", "WMPKCNN", "WMPKNNC", "WNCKMNP",
	"WNCKNMP", "WNCKNPM", "WNCKPMN", "WNCKPNM", "WNMKCNP", "WNMKCPN", "WNMKNCP", "WNMKNPC", "WNMKPCN", "WNMKPNC",
	"WNNKCMP", "WNNKCPM", "WNNKMCP", "WNNKMPC", "WNNKPCM", "WNNKPMC", "WNPKCMN", "WNPKCNM", "WNPKMCN", "WNPKMNC",
	"WNPKNCM", "WNPKNMC", "WPCKMNN", "WPCKNMN", "WPCKNNM", "WPMKCNN", "WPMKNCN", "WPMKNNC", "WPNKCMN", "WPNKCNM",
	"WPNKMCN", "WPNKMNC", "WPNKNCM", "WPNKNMC",
]

const _FSF_LETTER := {"K": "k", "N": "n", "C": "c", "P": "e", "M": "m", "D": "d", "L": "l", "W": "w"}


static func get_info(id: String) -> Dictionary:
	for s in LIST:
		if s.id == id:
			return s
	return LIST[0]


static func rows_to_board(rows: Array) -> Array:
	var b := []
	for r in 7:
		var row := []
		for t in rows[r].split(" ", false):
			row.append("" if t == "." else t)
		b.append(row)
	return b


# A fresh starting board for scenario uid=0(root) gid=0(root) groups=0(root) (Shuffled Court picks a new
# random pre-checked back rank each time).
static func make_board(id: String) -> Array:
	if id == "shuffle":
		var back: String = SAFE_SHUFFLES[randi() % SAFE_SHUFFLES.size()]
		var w := []
		var bl := []
		for ch in back:
			w.append("w" + ch)
			bl.append("b" + ch)
		var rows := [" ".join(w), "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", " ".join(bl)]
		return rows_to_board(rows)
	return rows_to_board(get_info(id).rows)


# Fairy-Stockfish FEN (White to move) for a board in the game's format.
static func board_to_fen(board: Array) -> String:
	var ranks := []
	for r in range(6, -1, -1):
		var s := ""
		var empty := 0
		for c in 7:
			var p: String = board[r][c]
			if p == "":
				empty += 1
				continue
			if empty > 0:
				s += str(empty)
				empty = 0
			var ch: String = _FSF_LETTER[p.substr(1, 1)]
			s += ch.to_upper() if p.begins_with("w") else ch
		if empty > 0:
			s += str(empty)
		ranks.append(s)
	return "/".join(ranks) + " w - - 0 1"
