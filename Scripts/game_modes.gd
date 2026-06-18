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
# Materials (NOT pieces — a flag on any piece): "iron","stone" (uncapturable),
#   "silver","gold","glass","blood" (visual + economy). Apply via a placement's
#   "material" key or piece.apply_material(name).
# =====================================================================

# Default starting layout (used when a mode doesn't define its own) — the classic
# Chezzard army. Edit this instead of a FEN string.
static func default_layout():
	var E = Globals.Piece_Type_ENUMs
	return {
		"white": {
			1: [
				{"piece": E.SHORTROOK, "material": "gold"},
				{"piece": E.MULE, "material": "iron"},
				{"piece": E.SHORTBISHOP, "material": "blood"},
				E.PRINCESS, E.PRINCE,
				{"piece": E.SHORTBISHOP, "material": "gold"},
				{"piece": E.MULE, "material": "silver"},
				E.SHORTROOK,
			],
			2: [{"piece": E.SHORTPAWN, "material": "iron"}, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN],
		},
		"black": {
			8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
			7: E.PAWN,
		},
	}
