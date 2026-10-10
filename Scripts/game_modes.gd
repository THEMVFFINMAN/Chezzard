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
		# Hamlet King: a minor lord from the neighboring hamlet -- his whole
		# army is the diminished "short" roster, the exact same piece family
		# RunState._default_army() uses for the run's own starting half-army:
		# SHORTROOK, MULE (that army's knight-slot filler -- one-step
		# diagonal, not actually a shortened knight, just the established
		# piece for that position), SHORTBISHOP, PRINCESS (short queen:
		# shortrook+shortbishop), and PRINCE instead of a real king (PRINCE is
		# itself the diminished "short king" -- orthogonal-only, no diagonal,
		# never castles). Player's side (white) is untouched, full standard
		# chess -- this is HIS army being weak, not a rule change. Black
		# castling disabled: PRINCE isn't literal KING, and board.gd's
		# castling tracking only recognizes literal KING (same known
		# trade-off already accepted for Lopsided Kings' 2-3-king sides).
		# White keeps normal castling.
		"hamlet_king": {
			"name": "Hamlet King",
			"generated": true,
			"disable_black_castling": true,
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					8: [E.SHORTROOK, E.MULE, E.SHORTBISHOP, E.PRINCESS, E.PRINCE, E.SHORTBISHOP, E.MULE, E.SHORTROOK],
					7: E.SHORTPAWN,
				},
			},
		},
		"three_check": {
			"name": "Three Check",
			"variant": "custom3check",
			"three_check": true,
		},
		"koth": {
			"name": "King of the Hill",
			"variant": "customkoth",
			"koth": true,  # client-side hill-reached check -- see board._check_koth_win()
		},
		# No royalty (a MAN stands in for the king); win by capturing every enemy
		# piece. The win itself is entirely client-side (board._check_unroyal_win,
		# called every move before any engine sync) -- no engine extinction rule
		# needed, and one is actively harmful: extinctionPieceTypes="*" does NOT
		# mean "lose when you have zero pieces total" the way it reads -- Fairy-
		# Stockfish's is_immediate_game_end checks EVERY individual piece type in
		# the set independently, so it would end the game the moment either side
		# ran out of even ONE piece type (e.g. its last knight), nowhere near
		# actual extinction. Previously set here -- removed.
		"unroyal": {
			"name": "Unroyal (capture all)",
			"generated": true,
			"unroyal": true,
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
		# (back rank forward) instead of ending the game. head_of_snake_white/
		# black are independent -- set either to false for a "lopsided" game
		# where only one side's royalty passes on and the other just loses
		# normally on checkmate.
		"head_of_snake": {
			"name": "Head of Snake",
			"generated": true,
			"head_of_snake_white": true,
			"head_of_snake_black": true,
		},
		# Lopsided Kings: each side independently gets 1-3 royal pieces (loses
		# only once ALL of its own royals are gone). Counts are chosen via the
		# White/Black Kings spinboxes on the mode-select screen (mode_select.gd
		# writes GameModes.lopsided_white_count/black_count live) -- get_mode()
		# below injects a fresh layout/royal_count from those each time this
		# mode is actually started, since this base dict is memoized. The
		# values here are just the pre-popup defaults.
		# "royal_count" is a single shared ceiling in the generated variant (the
		# engine has no per-side version of this attribute) but that's fine: per
		# position.cpp (count <= extinctionPieceCount + 1), it just has to be >=
		# the LARGER side's count for both sides' royals to be individually
		# protected -- it does not force both sides to have the same count.
		# Every count uses literal KING copies (regular kings, not the
		# diminished PRINCE) -- only the one actually on the e-file keeps
		# castling rights (position.cpp locks castlingKingSquare to the
		# e-file regardless of how many other KING-type pieces exist); the
		# extras are still fully protected by the pseudo-royal machinery.
		"lopsided_kings": {
			"name": "Rat King",
			"generated": true,
			"royal_count": 1,
			"layout": _kings_layout(1, 1),
		},
		# Chess960/Fischer Random: a constrained-random back rank (bishops on
		# opposite colours, king between the two rooks), same arrangement mirrored
		# for both sides. "chess960" tells the generated variant to use the
		# king-captures-rook UCI castling notation, and tells board.gd to accept
		# that notation as a castle instead of a capture. The layout itself is
		# re-rolled per game by get_mode() below, NOT baked into this cached dict.
		"chess960": {
			"name": "Chess960",
			"generated": true,
			"chess960": true,
			"rules": ["chess960 = true"],
		},
		# Horde: Black is a kingless wall of 24 pawns on its own back rank + the
		# 2 ranks in front of it (6-8); White has a full normal army (a real,
		# royal KING -- castles normally) and wins by capturing every last
		# pawn. The win is entirely client-side (board._check_unroyal_win, see
		# the note on Unroyal above) -- no engine extinction rule.
		"horde": {
			"name": "Horde",
			"generated": true,
			"unroyal": true,
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {6: E.PAWN, 7: E.PAWN, 8: E.PAWN},
			},
		},
		# Torpedo: pawns can double-step from ANY rank, not just their start.
		# Plain pieces both sides (not the short-rook/mule/princess/prince
		# roguelike-run roster -- a mode shouldn't be substituting its own
		# pieces; that's something a run's shop should hand you, not a rule
		# mode). Plain PAWN (not SHORTPAWN, whose betza has no double-step at
		# all) so the rule actually has something to act on.
		"torpedo": {
			"name": "Torpedo",
			"generated": true,
			"rules": [
				"doubleStepRegionWhite = *1 *2 *3 *4 *5 *6 *7 *8",
				"doubleStepRegionBlack = *1 *2 *3 *4 *5 *6 *7 *8",
			],
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					7: E.PAWN,
				},
			},
		},
		# King Race (bonus): the real Racing Kings layout -- both armies share
		# ranks 1-2 (files a-d black, e-h white, mirroring the actual startFen
		# "8/8/8/8/8/8/krbnNBRK/qrbnNBRQ"), racing to a SHARED rank 8. No
		# checks allowed at all, no castling. "king_race": true drives the
		# client-side win check (board._check_king_race_win) since reaching
		# the flag doesn't reduce legal moves to zero, so the normal perft-
		# based game-over detection never fires for this kind of win. A
		# "bonus" mode: mode-select only, never a roguelike floor, so losing
		# it has no run consequence.
		"racing_kings": {
			"name": "King Race (bonus)",
			"generated": true,
			"king_race": true,
			"rules": [
				"whiteFlag = *8", "blackFlag = *8", "flagPiece = k", "flagMove = true",
				"checking = false", "castling = false",
			],
			"layout": {
				"white": {
					2: [null, null, null, null, E.KNIGHT, E.BISHOP, E.ROOK, E.KING],
					1: [null, null, null, null, E.KNIGHT, E.BISHOP, E.ROOK, E.QUEEN],
				},
				"black": {
					2: [E.KING, E.ROOK, E.BISHOP, E.KNIGHT, null, null, null, null],
					1: [E.QUEEN, E.ROOK, E.BISHOP, E.KNIGHT, null, null, null, null],
				},
			},
		},
		# Petrified (v1): queen/rook/bishop/knight turn into an immobile,
		# uncapturable wall on the square they just captured on -- king and
		# pawns are unaffected, so pawns stay the only piece that can keep
		# capturing all game. 100% client-side (board.gd's move()); no engine
		# rule needed at all, unlike every other mode here.
		"petrified": {
			"name": "Petrified",
			"generated": true,
			"petrified_mode": true,
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					7: E.PAWN,
				},
			},
		},
		# Custom: a scratch sandbox for trying things ad hoc -- edit this
		# layout directly instead of adding a one-off mode elsewhere. White's
		# queenside (left) knight is flagged with the "petrify" modifier (a
		# placeholder "P" badge for now, see piece.gd) so it turns into a wall
		# the instant it captures anything, regardless of mode -- same per-
		# piece-tag pattern as racist/time1/double, independent of Petrified
		# mode's blanket queen/rook/bishop/knight rule. White's kingside
		# (right) knight is flagged "atomic" (placeholder "A" badge): capturing
		# with it blows up itself plus every adjacent non-pawn piece, same
		# per-piece-tag pattern, independent of a whole-game atomic rule.
		"custom": {
			"name": "Custom",
			"generated": true,
			"layout": {
				"white": {
					1: [E.ROOK, {"piece": E.KNIGHT, "modifiers": ["petrify"]}, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, {"piece": E.KNIGHT, "modifiers": ["atomic"]}, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					7: E.PAWN,
				},
			},
		},
		# The Bomber: REAL native Atomic Chess (engine blastOnCapture = true),
		# not the client-side "atomic" piece modifier -- the point is the AI's
		# own search/eval genuinely understands blast risk (confirmed in
		# evaluate.cpp's dedicated "Explosion threats" scoring term and
		# position.h's king-safety-near-enemy-king carve-out), which the
		# client-side modifier can never give it since the engine has no idea
		# that tag exists. Both sides' captures explode -- symmetric, because
		# that's what makes the engine-level awareness activate at all; see
		# the parser.cpp warning below for why it can't be one-sided here.
		# No literal KING on either side: the real engine's own atomic variant
		# (variant.cpp's nocheckatomic_variant) removes KING entirely and uses
		# a non-royal "commoner" registered via extinctionPseudoRoyal instead,
		# because parser.cpp:611 flags "Can not use kings with blastOnCapture"
		# the moment the literal KING piece type exists anywhere in the
		# variant. We use PSEUDOKING -- a dedicated piece (betza "WF",
		# "royal": true, same extinctionPseudoRoyal machinery as PRINCE/
		# Lopsided Kings, but visually and mechanically its own thing, not
		# borrowed from Prince) that moves and gets checkmated exactly like a
		# real king and LOOKS like one (its registry "name" is "king", so it
		# plays the existing king sprite). VariantBuilder also now emits
		# "king = -" whenever literal KING isn't in the roster -- just not
		# placing one isn't enough, since "[generated:chess]" inherits the
		# full parent piece set including KING unless explicitly stripped;
		# that inherited-but-unused king combined with blastOnCapture is
		# almost certainly why the original Atomic mode drew instantly on
		# start, before it got removed.
		# Castling disabled on both sides: board.gd's castling tracking is
		# hard-wired to piece_type == KING specifically (not generalized to
		# PRINCE/PSEUDOKING the way _find_royal()/_crown_next_royal() already
		# are), so it wouldn't get detected correctly here. Real atomic chess
		# does have castling; this is a scoped-down trade-off, not a rules
		# accuracy claim -- revisit if full authenticity matters later.
		"bomber": {
			"name": "The Bomber",
			"generated": true,
			"royal_count": 1,
			"disable_white_castling": true,
			"disable_black_castling": true,
			"blast_on_capture": true,
			"rules": ["blastOnCapture = true"],
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.PSEUDOKING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.PSEUDOKING, E.BISHOP, E.KNIGHT, E.ROOK],
					7: E.PAWN,
				},
			},
		},
		# Board-size test modes: still 8 files wide, just a taller/shorter
		# board. White's back rank always stays at 1; black's back rank/pawn
		# rank are repositioned to match the new length (board.length, not a
		# hardcoded 8). Exercises three things that only just got fixed:
		# VariantBuilder now emits maxRank/maxFile (it never did before),
		# board.gd's initiate_board() had width/length crossed on every axis
		# (only ever looked right because both were always 8), and black's
		# (non-960) castling rook squares were hardcoded to rank 8.
		# doubleStepRegionBlack defaults to rank 7 in the engine (standard chess
		# assumption) -- black's pawns here are NOT on rank 7, so without this
		# explicit override they silently couldn't double-step at all. White
		# doesn't need it: its pawns are always on rank 2.
		"long_board": {
			"name": "Long Board (10)",
			"generated": true,
			"length": 10,
			"rules": ["doubleStepRegionBlack = *9"],
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					10: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					9: E.PAWN,
				},
			},
		},
		"short_board": {
			"name": "Short Board (6)",
			"generated": true,
			"length": 6,
			"rules": ["doubleStepRegionBlack = *5"],
			"layout": {
				"white": {
					1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					2: E.PAWN,
				},
				"black": {
					6: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
					5: E.PAWN,
				},
			},
		},
	}


# Back rank for a side with `count` (1-3) royal pieces. Plain pieces
# throughout (no short-rook/mule/princess roguelike-run roster). All counts
# use literal KING copies -- regular kings, not the diminished PRINCE. 1 = the
# e-file king only. 2 = a 2nd KING replaces the queenside knight. 3 = a 3rd
# KING also replaces the kingside knight.
static func _royal_back_rank(count):
	var E = Globals.Piece_Type_ENUMs
	match clampi(count, 1, 3):
		1:
			return [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK]
		2:
			return [E.ROOK, E.KING, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK]
		_:
			return [E.ROOK, E.KING, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KING, E.ROOK]

# Lopsided Kings layout: white_count / black_count royal pieces (1-3 each,
# independent) via _royal_back_rank above.
static func _kings_layout(white_count, black_count):
	var E = Globals.Piece_Type_ENUMs
	return {
		"white": {1: _royal_back_rank(white_count), 2: E.PAWN},
		"black": {8: _royal_back_rank(black_count), 7: E.PAWN},
	}

# Chosen on the mode-select screen's White/Black Kings spinboxes (only shown
# when "Lopsided Kings" is the selected mode) -- written live by
# mode_select.gd, read by get_mode() below when the game actually starts.
static var lopsided_white_count = 1
static var lopsided_black_count = 1

# Head of Snake per-side toggle (White/Black Snakes checkboxes, mode-select
# screen) -- a side with its flag off just loses normally on checkmate
# instead of passing royalty on. Written live by mode_select.gd, read by
# get_mode() below each time the mode is actually started.
static var snake_white_enabled = true
static var snake_black_enabled = true


# Mode dict for mode_id, with a Chess960 layout freshly randomized per call,
# Lopsided Kings' layout/royal_count rebuilt from the current spinbox
# selection, or Head of Snake's per-side flags rebuilt from the current
# checkbox selection (the base modes() dict is memoized, so a static value
# baked in there would never change/update).
static func get_mode(mode_id):
	var m = modes().get(mode_id, modes()["standard"])
	if m.get("chess960", false):
		m = m.duplicate(true)
		m["layout"] = random_960_layout()
	elif mode_id == "lopsided_kings":
		m = m.duplicate(true)
		m["layout"] = _kings_layout(lopsided_white_count, lopsided_black_count)
		m["royal_count"] = max(lopsided_white_count, lopsided_black_count)
	elif mode_id == "head_of_snake":
		m = m.duplicate(true)
		m["head_of_snake_white"] = snake_white_enabled
		m["head_of_snake_black"] = snake_black_enabled
	return m


# One random Chess960 starting arrangement, mirrored for both sides (standard
# Fischer Random rule: both armies use the same back rank).
static func random_960_layout():
	var E = Globals.Piece_Type_ENUMs
	var rank = _random_960_back_rank()
	return {
		"white": {1: rank, 2: E.PAWN},
		"black": {8: rank, 7: E.PAWN},
	}


# Standard algorithm: bishops on opposite-colour squares, queen + 2 knights on
# any 3 of the remaining squares, then rook/king/rook fill the last 3 squares
# in file order (so the king always lands between the two rooks).
static func _random_960_back_rank():
	var E = Globals.Piece_Type_ENUMs
	var squares = [null, null, null, null, null, null, null, null]
	var evens = [0, 2, 4, 6]
	var odds = [1, 3, 5, 7]
	var b1 = evens[randi() % evens.size()]
	var b2 = odds[randi() % odds.size()]
	squares[b1] = E.BISHOP
	squares[b2] = E.BISHOP
	var empty = []
	for i in 8:
		if i != b1 and i != b2:
			empty.append(i)
	empty.shuffle()
	squares[empty.pop_back()] = E.QUEEN
	squares[empty.pop_back()] = E.KNIGHT
	squares[empty.pop_back()] = E.KNIGHT
	empty.sort()
	squares[empty[0]] = E.ROOK
	squares[empty[1]] = E.KING
	squares[empty[2]] = E.ROOK
	return squares


# Configure board size / rule flags for a mode and return the variant name to
# select. (The roster/layout/variant-file are handled in board_container, where
# the build result is available.)
static func apply(board, mode_id):
	return apply_config(board, get_mode(mode_id))


# Apply a mode/battle config dict's flags to the board; returns the variant name.
static func apply_config(board, m):
	if m.has("fen") and m["fen"] != "":
		board.generated_fen_string = m["fen"]
	board.width = m.get("width", board.width)
	board.length = m.get("length", board.length)
	board.three_check = m.get("three_check", false)
	board.unroyal = m.get("unroyal", false)
	board.head_of_snake_white = m.get("head_of_snake_white", false)
	board.head_of_snake_black = m.get("head_of_snake_black", false)
	board.koth = m.get("koth", false)
	board.king_race = m.get("king_race", false)
	board.chess960 = m.get("chess960", false)
	board.draws_favor_black = m.get("draws_favor_black", false)
	board.draws_favor_white = m.get("draws_favor_white", false)
	board.blast_on_capture = m.get("blast_on_capture", false)
	board.brittle_curse = m.get("brittle_curse", false)
	board.petrified_mode = m.get("petrified_mode", false)
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

# Default starting layout (used when a mode doesn't define its own: Standard,
# Three Check, Atomic, King of the Hill, Head of Snake). Plain standard chess
# for both sides -- the short-rook/mule/princess/prince roster with gold/iron/
# blood/silver/glass materials and racist/time1/double modifiers was testing
# scaffolding for the roguelike run and never belonged on these "normal chess
# + one rule" modes. The actual roguelike run's starting army is unaffected --
# it comes entirely from RunState._default_army() / RunState.army, not here.
static func default_layout():
	var E = Globals.Piece_Type_ENUMs
	return {
		"white": {
			1: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
			2: E.PAWN,
		},
		"black": {
			8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
			7: E.PAWN,
		},
	}
