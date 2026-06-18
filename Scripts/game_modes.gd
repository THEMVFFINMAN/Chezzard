class_name GameModes
extends RefCounted

# A game mode / level = an engine variant + optional overrides for the roster,
# starting position, board size, and rules.
#
#   variant     : static variant name in Engine/variants.ini (used when not generated)
#   generated   : true -> build the variant from "roster" via VariantBuilder
#   roster      : [enums] the pieces that exist this game (default: full registry)
#   layout      : { "white": {rank: [enums]/enum, ...}, "black": {...} } compact,
#                 code-friendly placement (a list per rank, or a single enum to
#                 fill the rank). Expanded by VariantBuilder.layout_to_placements().
#   placements  : [{ sq, piece (enum), white, material? }] explicit placement
#                 (use this or "layout"; omit both to keep the board's default FEN)
#   rules       : [String] extra variant option lines, e.g. "blastOnCapture = true"
#   three_check : convenience rule flag the game also reads directly
#
# modes() is built at runtime (not a const) so level data can reference
# Globals.Piece_Type_ENUMs values.

static var _modes = null


static func modes():
	if _modes == null:
		_modes = _build_modes()
	return _modes


static func _build_modes():
	var E = Globals.Piece_Type_ENUMs
	return {
		"standard": {
			"name": "Standard",
			"generated": true,
		},
		"three_check": {
			"name": "Three Check",
			"variant": "custom3check",
			"three_check": true,
		},
		"atomic": {
			"name": "Atomic",
			"variant": "customatomic",
		},
		"koth": {
			"name": "King of the Hill",
			"variant": "customkoth",
		},
		# No royalty (a MAN stands in for the king); win by capturing every enemy
		# piece. Extinction rules also tell the engine the goal.
		"unroyal": {
			"name": "Unroyal (capture all)",
			"generated": true,
			"unroyal": true,
			"rules": ["extinctionValue = loss", "extinctionPieceTypes = *", "extinctionPieceCount = 0"],
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.MAN, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.MAN, E.BISHOP, E.KNIGHT, E.ROOK],
					7: E.PAWN,
				},
			},
		},
		# Normal royal rules, but on checkmate royalty passes to the next piece
		# (back rank forward) instead of ending the game.
		"head_of_snake": {
			"name": "Head of Snake",
			"generated": true,
			"head_of_snake": true,
		},
		# Double King: a side with its flag set gets TWO royal princes (the 2nd on c,
		# replacing the queenside bishop); a side without it keeps a single king.
		# royal_count = 2 means a double-king side loses if EITHER king dies. Edit
		# the two booleans to set white / black independently.
		"double_king": {
			"name": "Double King",
			"generated": true,
			"royal_count": 2,
			"layout": _double_king_layout(true, false),  # (white_double, black_double)
		},
	}


# Double King layout: two princes (c + e) for a side whose flag is set, otherwise
# a single king on e with a normal queenside bishop.
static func _double_king_layout(white_double, black_double):
	var E = Globals.Piece_Type_ENUMs
	var double_back = [E.SHORTROOK, E.MULE, E.PRINCE, E.PRINCESS, E.PRINCE, E.SHORTBISHOP, E.MULE, E.SHORTROOK]
	var single_back = [E.SHORTROOK, E.MULE, E.SHORTBISHOP, E.PRINCESS, E.KING, E.SHORTBISHOP, E.MULE, E.SHORTROOK]
	return {
		"white": {1: double_back if white_double else single_back, 2: E.SHORTPAWN},
		"black": {8: double_back if black_double else single_back, 7: E.SHORTPAWN},
	}


# Configure board size / rule flags for a mode and return the variant name to
# select. (The roster/layout/variant-file are handled in board_container, where
# the build result is available.)
static func apply(board, mode_id):
	var m = modes().get(mode_id, modes()["standard"])
	if m.has("fen") and m["fen"] != "":
		board.generated_fen_string = m["fen"]
	board.width = m.get("width", board.width)
	board.length = m.get("length", board.length)
	board.three_check = m.get("three_check", false)
	board.unroyal = m.get("unroyal", false)
	board.head_of_snake = m.get("head_of_snake", false)
	if m.has("disable_white_castling"): board.disable_white_castling = m["disable_white_castling"]
	if m.has("disable_black_castling"): board.disable_black_castling = m["disable_black_castling"]
	if m.has("flip_white_king_queen"): board.flip_white_king_queen = m["flip_white_king_queen"]
	if m.has("flip_black_king_queen"): board.flip_black_king_queen = m["flip_black_king_queen"]
	return m.get("variant", "generated")


# =====================================================================
# PIECE REFERENCE — use as E.<NAME> in a roster / layout / placement.
# (Movement in Betza; "leaper (a,b)" = jumps that offset, ignoring blockers.)
#
# Standard chess:
#   PAWN          pawn
#   KNIGHT        (1,2) leaper                              N
#   BISHOP        diagonal slider                           B
#   ROOK          orthogonal slider                         R
#   QUEEN         rook + bishop                             Q
#   KING          1 step any direction (royal)             K
#
# Royal / commoner family:
#   PRINCE        1 step orthogonal — THE royal piece       W   (extinction = loss)
#   MAN           commoner: moves like a king, not royal    WF
#   ROYALKNIGHT   centaur: king + knight                    (builtin)
#   ROYALBISHOP   king-step + bishop                        WFB
#   ROYALROOK     king-step + rook                          WFR
#
# Shortened pieces:
#   SHORTROOK     rook, up to 4 squares                     R4
#   SHORTBISHOP   bishop, up to 3 squares                   B3
#   PRINCESS      shortrook + shortbishop                   R4B3
#   SHORTPAWN     pawn with no initial double-step          fmWfceF
#   MULE          1 step diagonal                           F
#
# Compounds / long:
#   ARCHBISHOP    bishop + knight                           (builtin)
#   CHANCELLOR    rook + knight                             (builtin)
#   AMAZON        queen + knight                            (builtin)
#   EMPRESS       queen                                     Q
#   GIRAFFE       (1,4) leaper                              G
#   KNIGHTRIDER   repeating knight leaps                     NN
#
# Specials (engine-affecting):
#   WALL          immobile blocker                          (immobile)
#   STONE         uncapturable king-mover (game-side "*")    WF
#   IRONQUEEN     uncapturable queen      (game-side "*")    Q
#
# Extra fairy pieces (need white_<name>/black_<name> sprites before use):
#   FERZ          1 step diagonal, colorbound               F
#   ALFIL         2-square diagonal jump                    A
#   DABBABA       2-square orthogonal jump                  D
#   GOLDGENERAL   shogi gold (orthogonal + fwd diagonal)    WfF
#   SILVERGENERAL shogi silver (diagonal + fwd orthogonal)  FfW
#   CAMEL         (1,3) leaper, colorbound                  C
#   ZEBRA         (2,3) leaper                              Z
#   WILDEBEEST    knight + camel                            NC
#   DABBABARIDER  "one-colour rook" (2-square rook hops)    DD
#   BUFFALO       knight + camel + zebra                    NCZ
#
# A layout/placement cell can be a bare piece enum OR a dict carrying extras:
#   {"piece": E.MULE, "material": "silver", "modifiers": ["racist", "time1"]}
#
# MATERIALS (a per-piece flag; "material" key, or piece.apply_material):
#   iron, stone                  uncapturable wall — keeps its own movement
#   silver, gold, glass, blood   normal piece; visual + (future) economy effect
#
# MODIFIERS (per-piece rule tags; "modifiers" list, or piece.apply_modifiers).
# Scaffolded — mechanics WIP:
#   racist         colourbound: only the square colour it starts on (queen/rook
#                  family — short queens/rooks, queen variants)
#   time1 / time2  cooldown: after moving, locked for 1 / 2 full turns
#   double         may move twice in a row (limit to short-range pieces)
#   slippery       (a SQUARE effect, planned) piece slips; spend a turn clicking
#                  it to upright it
#
# BOARD / MODE options (keys on a GameModes entry):
#   width / length        board size (default 8x8; rendering still assumes 8 wide)
#   layout / placements   starting position (see below)
#   roster                pieces available (else derived from the placements)
#   rules                 extra raw variants.ini option lines
#
# RULE TOGGLES (mode keys, or @export on the Board node):
#   three_check                                       win by giving 3 checks
#   disable_white_castling / disable_black_castling
#   flip_white_king_queen / flip_black_king_queen     swap the d/e start pieces
# =====================================================================

# Default starting layout (used when a mode doesn't define its own) — the classic
# Chezzard army. Edit this instead of a FEN string.
static func default_layout():
	var E = Globals.Piece_Type_ENUMs
	return {
		"white": {
			1: [
				{"piece": E.SHORTROOK, "material": "gold", "modifiers": ["racist", "time1"]},
				{"piece": E.MULE, "material": "iron", "modifiers": ["double"]},
				{"piece": E.SHORTBISHOP, "material": "blood"},
				E.PRINCESS, E.PRINCE,
				{"piece": E.SHORTBISHOP, "material": "gold"},
				{"piece": E.MULE, "material": "silver"},
				E.ROOK,
			],
			2: [{"piece": E.SHORTPAWN, "material": "iron"}, {"piece": E.SHORTPAWN, "material": "glass"}, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN],
		},
		"black": {
			8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
			7: E.PAWN,
		},
	}
