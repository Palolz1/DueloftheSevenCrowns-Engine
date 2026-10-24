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
	{"id": "variant",  "title": "Variants",        "desc": "Same army on both sides, arranged differently."},
	{"id": "asym",     "title": "Different armies", "desc": "Each side has its own army, yet the engine rates the fight as even."},
	{"id": "practice", "title": "Practice",        "desc": "Drills to sharpen one skill. Play White against a computer."},
	{"id": "uneven",   "title": "Uneven armies",   "desc": "Handicap games, from a small edge to a hopeless fight. The weaker side always plays White."},
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
	{"id": "cavalry", "category": "variant", "name": "Cavalry Charge",
	 "desc": "Every piece is a Knight. Fast, tricky and full of forks.",
	 "verdict": "Even", "tone": "even",
	 "rows": ["wN wN wN wK wN wN wN", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bN bN bN bK bN bN bN"]},
	{"id": "cathedral", "category": "variant", "name": "Cathedral",
	 "desc": "Six Cardinals a side. Long diagonals cut across the whole board.",
	 "verdict": "Even", "tone": "even",
	 "rows": ["wC wC wC wK wC wC wC", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bC bC bK bC bC bC"]},
	{"id": "paladin_order", "category": "variant", "name": "Paladin Order",
	 "desc": "Six Paladins a side, leaping over the donkey walls from move one.",
	 "verdict": "Even", "tone": "even",
	 "rows": ["wP wP wP wK wP wP wP", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bP bP bP bK bP bP bP"]},
	{"id": "wardens_keep", "category": "variant", "name": "Warden's Keep",
	 "desc": "Six Wardens a side. A slow, solid fight between two fortresses.",
	 "verdict": "Even", "tone": "even",
	 "rows": ["wW wW wW wK wW wW wW", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bW bW bW bK bW bW bW"]},
	{"id": "skirmish", "category": "variant", "name": "Skirmish",
	 "desc": "A quick game with half-size armies: four pieces and five donkeys each.",
	 "verdict": "Even", "tone": "even",
	 "rows": [". wN wP wK wW wN .", ". wD wD wD wD wD .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". bD bD bD bD bD .", ". bN bP bK bW bN ."]},
	{"id": "champions", "category": "variant", "name": "Champions",
	 "desc": "Just a Marshal, a Cardinal and three donkeys guarding each King. Every move counts.",
	 "verdict": "Even", "tone": "even",
	 "rows": [". . wM wK wC . .", ". . wD wD wD . .", ". . . . . . .", ". . . . . . .", ". . . . . . .", ". . bD bD bD . .", ". . bM bK bC . ."]},
	{"id": "high_command", "category": "variant", "name": "High Command",
	 "desc": "The minor pieces join the front line, leaving the King with only its Marshal and Cardinal at home.",
	 "verdict": "Even", "tone": "even",
	 "rows": [". . wC wK wM . .", "wN wP wD wD wD wW wN", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bN bP bD bD bD bW bN", ". . bC bK bM . ."]},
	{"id": "warden_wall", "category": "asym", "name": "Warden Wall",
	 "desc": "White's King hides behind seven Wardens; Black has the classic army.",
	 "verdict": "Even · edge to Black", "tone": "even",
	 "rows": [". . . wK . . .", "wW wW wW wW wW wW wW", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "reflected", "category": "asym", "name": "Reflected Court",
	 "desc": "Black's back rank is reversed left to right, so every piece faces a different opponent.",
	 "verdict": "Even", "tone": "even",
	 "rows": ["wC wN wP wK wW wN wM", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bM bN bW bK bP bN bC"]},
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
	{"id": "donkey_odds", "category": "uneven", "name": "Donkey Odds",
	 "desc": "White starts without its d-file donkey. A tiny handicap for two close players.",
	 "verdict": "Black +0.4", "tone": "black",
	 "rows": ["wC wN wP wK wW wN wM", "wD wD wD . wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "cardinal_legion", "category": "uneven", "name": "Cardinal Legion",
	 "desc": "Black swaps its whole back rank for six Cardinals. Diagonals everywhere.",
	 "verdict": "Black +1.7", "tone": "black",
	 "rows": ["wC wN wP wK wW wN wM", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bC bC bK bC bC bC"]},
	{"id": "knight_odds", "category": "uneven", "name": "Knight Odds",
	 "desc": "White plays without its f-file Knight.",
	 "verdict": "Black +3.0", "tone": "black",
	 "rows": ["wC wN wP wK wW . wM", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "marshal_odds", "category": "uneven", "name": "Marshal Odds",
	 "desc": "White plays without its Marshal. The stronger player takes White to give a friend a fair game.",
	 "verdict": "Black +7.6", "tone": "black",
	 "rows": ["wC wN wP wK wW wN .", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "knightmare", "category": "uneven", "name": "Knightmare",
	 "desc": "Black gets four Paladins and a wall of Knights. White's b and f donkeys start as Lancers to fight back.",
	 "verdict": "Black +8", "tone": "black",
	 "rows": ["wC wN wP wK wW wN wM", "wD wL wD wD wD wL wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bN bN bN bN bN bN bN", "bP bN bP bK bP bN bP"]},
	{"id": "lancer_brigade", "category": "uneven", "name": "Lancer Brigade",
	 "desc": "Black's back rank is six Lancers. White has exactly one first move that saves the game. Can you find it?",
	 "verdict": "Black +9.5", "tone": "black",
	 "rows": ["wC wN wP wK wW wN wM", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bL bL bL bK bL bL bL"]},
	{"id": "twin_marshals", "category": "uneven", "name": "Twin Marshals",
	 "desc": "White keeps only two Marshals and its donkeys to face a full army.",
	 "verdict": "Black +13", "tone": "black",
	 "rows": [". wM . wK . wM .", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "last_stand", "category": "uneven", "name": "Last Stand",
	 "desc": "White has just a Marshal and a Warden beside the King. Hold out as long as you can.",
	 "verdict": "Black +15", "tone": "black",
	 "rows": [". . wM wK wW . .", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "onslaught", "category": "uneven", "name": "Onslaught",
	 "desc": "Twenty donkeys and a King against a full army. Can the herd break through?",
	 "verdict": "Black +22", "tone": "black",
	 "rows": ["wD wD wD wK wD wD wD", "wD wD wD wD wD wD wD", "wD wD wD wD wD wD wD", ". . . . . . .", ". . . . . . .", "bD bD bD bD bD bD bD", "bC bN bP bK bW bN bM"]},
	{"id": "god_army", "category": "uneven", "name": "God Army",
	 "desc": "Black fills three ranks with heavy pieces. Survive as White, if you can.",
	 "verdict": "Black mates in 9", "tone": "black",
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
