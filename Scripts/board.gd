extends Node

@onready var square_scene = preload("res://Scenes/square.tscn")
@onready var piece_scene = preload("res://Scenes/piece.tscn")
@onready var top_level = get_parent()

# Emitted when the Back/Forward buttons should be enabled/disabled. The
# BoardAuxiliaryContainer listens and toggles its own buttons, so this script
# never reaches across scenes into them.
signal nav_buttons_enabled(enabled)

var started = false

var possible_letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z']
var holding_piece = false
var held_piece = null
var last_held_piece = null

var pending_promotion = {}

var letters_size = 0
var numbers_size = 0

#var generated_fen_string = "rnbqkbnr/pppppppp/8/8/4w3/8/ZZZZZZZZ/SMTULTMS"

var generated_fen_string = ""  # set per-game from the mode's layout (GameModes.default_layout)

var board_array : Array

var length = 8
var width = 8

var white_to_move = true
var black_move_counter = 1
var blank_space_counter = 0

var regex

var skip_for_loop = 0

var black_move_timer

var en_passant_square = ""
var en_passant_attacker_square = ""
var en_passant_pawn_location = ""

var white_castled = false
var black_castled = false

var white_king_moved = false
var black_king_moved = false
var white_rook_queenside_moved = false
var white_rook_kingside_moved = false
var black_rook_queenside_moved = false
var black_rook_kingside_moved = false

# Actual starting files of each rook, used instead of literal "a"/"h" so castling
# rights tracking works when the back rank isn't the standard layout (chess960).
# Defaulted to the standard corners so every non-960 mode is unaffected.
var white_rook_queenside_start_file = "a"
var white_rook_kingside_start_file = "h"
var black_rook_queenside_start_file = "a"
var black_rook_kingside_start_file = "h"

var moves = []
var redo_moves = []
var double_pending_piece = null  # a "double" piece between its two moves (null = normal)
var pending_legal_snapshot = {}
var undo_steps_remaining = 0
var redo_steps_remaining = 0


var captured_pieces = []
var captured_piece = false

var squares_dict = {}

var castle_info = {}
# Set right before conduct_castling_checks() runs for a chess960 castle: the
# rook's current square (the engine reports castling as "king moves onto its
# own rook"). Cleared once consumed.
var _castle_rook_hint_square = ""

var computer_opponent
var player_white

# --- Per-game rule toggles (Inspector-settable on the Board node) ---
@export var disable_white_castling := false
@export var disable_black_castling := false
# Flip swaps the king-file (e) and queen-file (d) starting pieces for that side.
# A flipped side also loses castling (its royal leaves the e-file).
@export var flip_white_king_queen := false
@export var flip_black_king_queen := false
@export var three_check := false  # win by delivering 3 checks
@export var chess960 := false  # random back rank; castling via king-captures-rook notation
@export var draws_favor_black := false  # a result that would be a draw is instead an automatic Black win
@export var draws_favor_white := false  # same, for White -- the run's "Checkmate Insurance" relic (you're always White in battles)
# Real Atomic Chess (engine blastOnCapture = true, see GameModes "bomber"):
# EVERY capture, either colour, explodes -- not just modifier-tagged pieces
# (that's the separate per-piece "atomic" check below). Mirrors the engine's
# own blast on the client board so our board_array/FEN stay in sync with
# what the engine thinks happened; see the _exploding consumption in move().
@export var blast_on_capture := false
# Petrified: queen/rook/bishop/knight (not king, not pawn) turn into an
# immobile wall right after capturing. See the _petrifying consumption in
# move() for the actual conversion.
@export var petrified_mode := false
const PETRIFY_TYPES = [
	Globals.Piece_Type_ENUMs.QUEEN, Globals.Piece_Type_ENUMs.ROOK,
	Globals.Piece_Type_ENUMs.BISHOP, Globals.Piece_Type_ENUMs.KNIGHT,
]
var _petrifying = null

# Atomic (per-piece modifier, Custom mode): a piece flagged "atomic" that
# captures blows up -- itself plus every adjacent non-pawn piece (either
# colour) -- same real-Atomic-chess blast radius, just scoped to one piece
# instead of a whole-game rule. Consumed alongside _petrifying/_glass_breaking
# further down in move(). No undo support yet -- undoing an atomic capture
# will not bring the exploded pieces back (placeholder, like the petrify badge).
var _exploding = null
# Testing hook: assign materials to squares at startup, e.g. {"d1": "gold"}.
@export var test_materials := {}
# Per-game { square -> [modifier names] }, set from the mode's placements.
var test_modifiers := {}

# 3-check tracking (used only when three_check is on)
signal three_check_won(white_won)
var white_checks := 0
var black_checks := 0

# Emitted once when the side to move has no legal moves (checkmate/stalemate).
# board_container listens and shows the game-over popup.
signal game_over(result_text)
var game_over_emitted := false
var win_awarded := false  # economy: win reward paid once per battle
var player_won := false  # set at game over: did the player (white) win?
var _glass_breaking = null  # a glass piece that rolled to shatter after capturing

# Mode flags (set by GameModes.apply). unroyal: no royalty, win by capturing all
# enemy pieces. head_of_snake_white/black: on THAT colour's checkmate, royalty
# passes to the next piece instead of ending the game -- independent, so a
# "lopsided" game can give it to only one side.
var unroyal := false
var head_of_snake_white := false
var head_of_snake_black := false
# King of the Hill / King Race: both end the game via the engine's own
# "flag reached" rule, not checkmate, which doesn't reduce legal moves to
# zero -- so the normal perft-based game-over detection never fires for
# either. Checked client-side every turn instead (_check_koth_win /
# _check_king_race_win).
var koth := false
var king_race := false

# Brittle curse: an enemy debuff, not a shop modifier. While on, a rotating
# 3-turn cycle (ticked once per player turn, in _finish_move) targets one
# random non-royal player piece: turn 1 of the cycle marks it (mild warning),
# turn 2 upgrades the warning (severe), and turn 3 shatters it if it's still
# the same un-moved piece. Moving the targeted piece at any point clears the
# threat, but the cycle still runs its full 3 turns before targeting a new
# piece -- dodging early doesn't speed up the next pick.
@export var brittle_curse := false
var _brittle_target = null
var _brittle_tick := 0

func _enter_tree():
	# Registered early (before children are ready) so nested nodes can find the
	# board via the "board" group instead of brittle get_parent() chains.
	add_to_group("board")

func _ready():
	black_move_timer = $black_move_timer
	regex = RegEx.new()
	regex.compile(r"([a-zA-Z]\d+)")
	# The board itself is built by board_container once the game mode is chosen
	# (build_board), so mode settings (board size, FEN, rules) apply first.

# Builds the board for the current mode config. Called by board_container after
# the mode and opponent are picked.
func build_board():
	computer_opponent = get_parent().computer_opponent
	player_white = get_parent().player_white
	initiate_board(length, width)
	generated_fen_string = _apply_starting_flips(generated_fen_string)
	generate_board_from_fen_string(generated_fen_string)
	_apply_test_materials()
	if chess960:
		_record_960_start_files()
	freeze_black_pieces()

# Chess960: the rooks aren't on a/h, so record which file each side's rooks
# actually started on (lower file = queenside, higher file = kingside) — the
# castling-rights tracking below keys off these instead of literal "a"/"h".
func _record_960_start_files():
	for white in [true, false]:
		var grp = "white_pieces" if white else "black_pieces"
		var rook_files = []
		for p in get_tree().get_nodes_in_group(grp):
			if not p.dead and p.piece_type == Globals.Piece_Type_ENUMs.ROOK:
				rook_files.append(possible_letters.find(p.chess_position[0]))
		if rook_files.size() < 2:
			continue
		rook_files.sort()
		if white:
			white_rook_queenside_start_file = possible_letters[rook_files[0]]
			white_rook_kingside_start_file = possible_letters[rook_files[1]]
		else:
			black_rook_queenside_start_file = possible_letters[rook_files[0]]
			black_rook_kingside_start_file = possible_letters[rook_files[1]]
	
func check_wall(move):
	if get_square(move).piece_type == Globals.Piece_Type_ENUMs.WALL:
		return true
		
	return false
	
	
func add_legal_moves_to_pieces(legal_moves):
	Globals.dprint("[movegen] engine returned %d raw legal moves: %s" % [legal_moves.size(), legal_moves])
	while legal_moves.size() > 0:
		var legal_move = legal_moves.pop_back()
		legal_move = legal_move.split(":")[0]

		var legal_move_array = get_array_of_individual_moves_from_fen_string(legal_move)

		var piece = get_piece(legal_move_array[0])

		if piece != null:
			Globals.dprint("[movegen] %s -> %s assigned to %s (%s) at %s" % [legal_move_array[0], legal_move_array[1], Globals.give_piece_name_from_piece_type(piece.piece_type), "white" if piece.white else "black", piece.chess_position])
			piece.add_legal_move(legal_move_array[1])
			if legal_move_array.size() == 3:
				piece.add_promotion_piece(legal_move_array[2])
		else:
			Globals.dprint("[movegen] WARNING: move %s -> %s has no piece at the from-square (engine/client desync?)" % [legal_move_array[0], legal_move_array[1]])
			


		
# Wall pieces (stone, iron*) go to the engine as "*" wall squares, so the engine
# never generates their moves. We add them game-side for the side to move (right
# after the engine's legal moves). They only step onto empty squares — never
# capturing.
# A piece is an uncapturable "wall" if it has the iron/stone material (works on
# ANY base piece), is a legacy STONE/IRONQUEEN type, or is the literal WALL
# piece type (a placed obstacle, or a piece that just petrified). Walls go to
# the engine as "*" and the game generates their moves (below) -- WALL gets
# none at all, since it's meant to be genuinely dead, not just uncapturable.
func _is_wall_piece(piece):
	if piece == null:
		return false
	if piece.piece_material == "iron" or piece.piece_material == "stone":
		return true
	return piece.piece_type == Globals.Piece_Type_ENUMs.STONE \
		or piece.piece_type == Globals.Piece_Type_ENUMs.IRONQUEEN \
		or piece.piece_type == Globals.Piece_Type_ENUMs.WALL

# in_check: the side to move is in check (from the engine eval). A wall/iron piece
# can't capture and can't move the king, so the ONLY way it can resolve a check is
# by interposing on the checking line (_check_block_squares). We keep only wall
# moves that land on one — so an iron piece can still block a sliding check, but
# can't ignore a knight/double check (no block squares) or shuffle to escape.
func add_wall_piece_moves(in_check = false):
	var block_squares = _check_block_squares() if in_check else {}
	var group = "white_pieces" if white_to_move else "black_pieces"
	for piece in get_tree().get_nodes_in_group(group):
		if piece.dead or not _is_wall_piece(piece):
			continue
		# Legacy dedicated types keep their own movement; otherwise an iron/stone
		# piece keeps its BASE type's movement.
		match piece.piece_type:
			Globals.Piece_Type_ENUMs.STONE:
				_add_king_step_moves(piece)
			Globals.Piece_Type_ENUMs.IRONQUEEN:
				_add_slider_moves(piece, true, true)  # orthogonal + diagonal = queen
			Globals.Piece_Type_ENUMs.WALL:
				pass  # fully immobile -- no moves at all, not even to block a check
			_:
				_add_base_type_moves(piece)
		if in_check:
			var keep = []
			for m in piece.legal_moves:
				if block_squares.has(m):
					keep.append(m)  # only interpositions resolve the check
			piece.legal_moves = keep

# Squares where the side to move can interpose against a check. Computed
# geometrically (NOT from the engine's legal moves) because the engine sees iron as
# a wall and wouldn't report an iron-only block — the very case we want to allow.
# Single sliding check -> the empty squares between king and checker; knight check,
# adjacent check, or double check -> empty (nothing can block).
func _check_block_squares():
	var king = _find_royal(white_to_move)
	if king == null:
		return {}
	var enemy_group = "black_pieces" if white_to_move else "white_pieces"
	var checkers = []
	for p in get_tree().get_nodes_in_group(enemy_group):
		if not p.dead and _attacks(p, king.chess_position):
			checkers.append(p)
	if checkers.size() != 1:
		return {}  # double check (or unclassified) -> can't block
	return _between_squares(king.chess_position, checkers[0].chess_position)

# Does `piece` attack `target` (movement + blocking, ignoring check legality)? Used
# to find the checker. Enemy walls are "*" to the engine and never give check.
func _attacks(piece, target):
	if _is_wall_piece(piece):
		return false
	var pf = possible_letters.find(piece.chess_position[0])
	var pr = int(piece.chess_position.substr(1, piece.chess_position.length() - 1))
	var tf = possible_letters.find(target[0])
	var tr = int(target.substr(1, target.length() - 1))
	var df = tf - pf
	var dr = tr - pr
	if df == 0 and dr == 0:
		return false
	var adf = abs(df)
	var adr = abs(dr)
	var ranges = _slide_ranges(piece.piece_type)
	if (df == 0 or dr == 0) and ranges[0] >= max(adf, adr) and _ray_clear(piece.chess_position, target):
		return true
	if adf == adr and ranges[1] >= adf and _ray_clear(piece.chess_position, target):
		return true
	for o in _leap_offsets(piece.piece_type):
		if df == o[0] and dr == o[1]:
			return true
	if Globals.is_pawn_type(piece.piece_type):
		if dr == (1 if piece.white else -1) and adf == 1:
			return true
	return false

# [orthogonal range, diagonal range] for sliders/steppers (0 = doesn't slide that
# way, 99 = unlimited). King-type steps are range 1. Leapers use _leap_offsets.
func _slide_ranges(t):
	var E = Globals.Piece_Type_ENUMs
	match t:
		E.ROOK, E.CHANCELLOR: return [99, 0]
		E.BISHOP, E.ARCHBISHOP: return [0, 99]
		E.QUEEN, E.EMPRESS, E.AMAZON: return [99, 99]
		E.ROYALROOK: return [99, 1]
		E.ROYALBISHOP: return [1, 99]
		E.SHORTROOK: return [4, 0]
		E.SHORTBISHOP: return [0, 3]
		E.PRINCESS: return [4, 3]
		E.KING, E.MAN, E.STONE, E.ROYALKNIGHT: return [1, 1]
		E.PRINCE: return [1, 0]
		E.MULE, E.FERZ: return [0, 1]
		_: return [0, 0]

# Leap offsets [df, dr] for jumpers (and the jumping component of compounds).
func _leap_offsets(t):
	var E = Globals.Piece_Type_ENUMs
	match t:
		E.KNIGHT, E.ARCHBISHOP, E.CHANCELLOR, E.AMAZON, E.ROYALKNIGHT, E.KNIGHTRIDER:
			return _OFF_KNIGHT
		E.CAMEL: return _OFF_CAMEL
		E.ZEBRA: return _OFF_ZEBRA
		E.ALFIL: return _OFF_ALFIL
		E.DABBABA, E.DABBABARIDER: return _OFF_DABBABA
		E.GIRAFFE: return _OFF_GIRAFFE
		E.WILDEBEEST: return _OFF_KNIGHT + _OFF_CAMEL
		E.BUFFALO: return _OFF_KNIGHT + _OFF_CAMEL + _OFF_ZEBRA
		_: return []

# True if every square strictly between `from_sq` and `to_sq` (along a line) is empty.
func _ray_clear(from_sq, to_sq):
	var ff = possible_letters.find(from_sq[0])
	var fr = int(from_sq.substr(1, from_sq.length() - 1))
	var tf = possible_letters.find(to_sq[0])
	var tr = int(to_sq.substr(1, to_sq.length() - 1))
	var sf = sign(tf - ff)
	var sr = sign(tr - fr)
	var nf = ff + sf
	var nr = fr + sr
	while nf != tf or nr != tr:
		if get_square(str(possible_letters[nf]) + str(nr)).has_piece:
			return false
		nf += sf
		nr += sr
	return true

# Empty squares strictly between two squares on a rook/bishop line (else {} — a
# knight/adjacent checker can't be interposed).
func _between_squares(a, b):
	var af = possible_letters.find(a[0])
	var ar = int(a.substr(1, a.length() - 1))
	var bf = possible_letters.find(b[0])
	var br = int(b.substr(1, b.length() - 1))
	var df = bf - af
	var dr = br - ar
	if not (df == 0 or dr == 0 or abs(df) == abs(dr)):
		return {}
	var sf = sign(df)
	var sr = sign(dr)
	var result = {}
	var nf = af + sf
	var nr = ar + sr
	while nf != bf or nr != br:
		result[str(possible_letters[nf]) + str(nr)] = true
		nf += sf
		nr += sr
	return result

# Sliding move generation to empty squares only (stops before any piece, since
# wall pieces can't capture). orthogonal = rook lines, diagonal = bishop lines.
func _add_slider_moves(piece, orthogonal, diagonal, max_range = 0):
	var dirs = []
	if orthogonal:
		dirs += [[1, 0], [-1, 0], [0, 1], [0, -1]]
	if diagonal:
		dirs += [[1, 1], [1, -1], [-1, 1], [-1, -1]]
	var file_index = possible_letters.find(piece.chess_position[0])
	var rank = int(piece.chess_position.substr(1, piece.chess_position.length() - 1))
	for d in dirs:
		var nf = file_index
		var nr = rank
		var steps = 0
		while true:
			nf += d[0]
			nr += d[1]
			steps += 1
			if nf < 0 or nf >= width or nr < 1 or nr > length:
				break
			if max_range > 0 and steps > max_range:
				break  # range-limited slider (shortrook = 4, shortbishop = 3, ...)
			var target = str(possible_letters[nf]) + str(nr)
			if get_square(target).has_piece:
				break  # blocked — can't capture, so stop before the piece
			piece.add_legal_move(target)

func _add_king_step_moves(piece):
	var file_index = possible_letters.find(piece.chess_position[0])
	var rank = int(piece.chess_position.substr(1, piece.chess_position.length() - 1))
	for df in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			if df == 0 and dr == 0:
				continue
			var nf = file_index + df
			var nr = rank + dr
			if nf < 0 or nf >= width or nr < 1 or nr > length:
				continue
			var target = str(possible_letters[nf]) + str(nr)
			if not get_square(target).has_piece:
				piece.add_legal_move(target)

# Offset tables for game-side move generation of iron/stone wall pieces.
const _DIRS_ORTHO := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const _DIRS_DIAG := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const _DIRS_KING := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]
const _OFF_KNIGHT := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const _OFF_CAMEL := [[1, 3], [3, 1], [3, -1], [1, -3], [-1, -3], [-3, -1], [-3, 1], [-1, 3]]
const _OFF_ZEBRA := [[2, 3], [3, 2], [3, -2], [2, -3], [-2, -3], [-3, -2], [-3, 2], [-2, 3]]
const _OFF_ALFIL := [[2, 2], [2, -2], [-2, 2], [-2, -2]]
const _OFF_DABBABA := [[2, 0], [-2, 0], [0, 2], [0, -2]]
const _OFF_GIRAFFE := [[1, 4], [4, 1], [4, -1], [1, -4], [-1, -4], [-4, -1], [-4, 1], [-1, 4]]

# Add a leap to each given offset, onto empty squares only (walls never capture).
func _add_offset_moves(piece, offsets):
	var file_index = possible_letters.find(piece.chess_position[0])
	var rank = int(piece.chess_position.substr(1, piece.chess_position.length() - 1))
	for o in offsets:
		var nf = file_index + o[0]
		var nr = rank + o[1]
		if nf < 0 or nf >= width or nr < 1 or nr > length:
			continue
		var target = str(possible_letters[nf]) + str(nr)
		if not get_square(target).has_piece:
			piece.add_legal_move(target)

# One-step-forward generation for iron pawns (no capture, no double-step).
func _add_pawn_moves(piece):
	var file_index = possible_letters.find(piece.chess_position[0])
	var rank = int(piece.chess_position.substr(1, piece.chess_position.length() - 1))
	var nr = rank + (1 if piece.white else -1)
	if nr >= 1 and nr <= length:
		var target = str(possible_letters[file_index]) + str(nr)
		if not get_square(target).has_piece:
			piece.add_legal_move(target)

# Generate an iron piece's moves from its BASE type's movement (empty squares
# only). Riders / shogi generals fall back to a king step for now.
func _add_base_type_moves(piece):
	var E = Globals.Piece_Type_ENUMs
	match piece.piece_type:
		E.QUEEN, E.EMPRESS:
			_add_slider_moves(piece, true, true, 0)
		E.ROOK:
			_add_slider_moves(piece, true, false, 0)
		E.BISHOP:
			_add_slider_moves(piece, false, true, 0)
		E.SHORTROOK:
			_add_slider_moves(piece, true, false, 4)
		E.SHORTBISHOP:
			_add_slider_moves(piece, false, true, 3)
		E.PRINCESS:
			_add_slider_moves(piece, true, false, 4)
			_add_slider_moves(piece, false, true, 3)
		E.KING, E.MAN:
			_add_offset_moves(piece, _DIRS_KING)
		E.PRINCE:
			_add_offset_moves(piece, _DIRS_ORTHO)   # wazir
		E.MULE, E.FERZ:
			_add_offset_moves(piece, _DIRS_DIAG)    # ferz
		E.KNIGHT:
			_add_offset_moves(piece, _OFF_KNIGHT)
		E.CAMEL:
			_add_offset_moves(piece, _OFF_CAMEL)
		E.ZEBRA:
			_add_offset_moves(piece, _OFF_ZEBRA)
		E.ALFIL:
			_add_offset_moves(piece, _OFF_ALFIL)
		E.DABBABA:
			_add_offset_moves(piece, _OFF_DABBABA)
		E.GIRAFFE:
			_add_offset_moves(piece, _OFF_GIRAFFE)
		E.WILDEBEEST:
			_add_offset_moves(piece, _OFF_KNIGHT)
			_add_offset_moves(piece, _OFF_CAMEL)
		E.BUFFALO:
			_add_offset_moves(piece, _OFF_KNIGHT)
			_add_offset_moves(piece, _OFF_CAMEL)
			_add_offset_moves(piece, _OFF_ZEBRA)
		E.ARCHBISHOP:
			_add_slider_moves(piece, false, true, 0)
			_add_offset_moves(piece, _OFF_KNIGHT)
		E.CHANCELLOR:
			_add_slider_moves(piece, true, false, 0)
			_add_offset_moves(piece, _OFF_KNIGHT)
		E.AMAZON:
			_add_slider_moves(piece, true, true, 0)
			_add_offset_moves(piece, _OFF_KNIGHT)
		E.ROYALKNIGHT:
			_add_offset_moves(piece, _DIRS_KING)
			_add_offset_moves(piece, _OFF_KNIGHT)
		E.ROYALBISHOP:
			_add_offset_moves(piece, _DIRS_KING)
			_add_slider_moves(piece, false, true, 0)
		E.ROYALROOK:
			_add_offset_moves(piece, _DIRS_KING)
			_add_slider_moves(piece, true, false, 0)
		E.PAWN, E.SHORTPAWN, E.BACKPAWN:
			_add_pawn_moves(piece)  # NOTE: forward-only -- an iron/stone BACKPAWN loses its backward step
		_:
			_add_offset_moves(piece, _DIRS_KING)    # fallback (riders / shogi generals)

## Apply test materials (Inspector dict of square -> material name) after setup.
func _apply_test_materials():
	for sq in test_materials:
		var p = get_piece(sq)
		if p:
			p.apply_material(test_materials[sq])
	for sq in test_modifiers:
		var p = get_piece(sq)
		if p:
			p.apply_modifiers(test_modifiers[sq])

# Game-side modifier move filters, run after legal moves are populated. "racist"
# (colourbound) keeps a piece to squares of the colour it currently stands on
# (which is the colour it started on, since it only ever moves same-colour). The
# engine still sees a normal piece — fine, since the player picks from the
# filtered set and same-colour moves are a subset of the engine's legal moves.
func apply_modifier_filters():
	for group in ["white_pieces", "black_pieces"]:
		for piece in get_tree().get_nodes_in_group(group):
			if piece.dead:
				continue
			piece.queue_redraw()  # refresh the cooldown/racist overlay
			if piece.cooldown_until > moves.size():
				piece.legal_moves = []  # timed piece still on cooldown this turn
				continue
			if piece.has_modifier("racist"):
				_filter_colorbound(piece)
	# Double: during the second half, only the double piece may move.
	if double_pending_piece != null:
		for piece in get_tree().get_nodes_in_group("pieces"):
			if piece != double_pending_piece:
				piece.legal_moves = []
		if double_pending_piece.legal_moves.is_empty():
			_end_double_turn()  # can't move again -> just end the turn
		else:
			# Re-enable the piece for its second pickup. We skipped _flip_turn (to keep
			# the turn), which is normally what re-enables the side-to-move's pieces, so
			# without this the double piece's collision stays disabled and it can't be
			# grabbed again.
			double_pending_piece.get_node("CollisionShape2D").disabled = false

func _filter_colorbound(piece):
	if piece.legal_moves.is_empty():
		return
	var start_color = _square_color(piece.chess_position)
	var keep = []
	for m in piece.legal_moves:
		if _square_color(m) == start_color:
			keep.append(m)
	piece.legal_moves = keep

# Square colour by file+rank parity (independent of any piece on it). Same parity
# = same colour; that's all the racist modifier needs.
func _square_color(pos):
	var file_index = possible_letters.find(pos[0])
	var rank = int(pos.substr(1, pos.length() - 1))
	return (file_index + rank) % 2

# Called (deferred) when the engine's perft for the side to move was 0. Wall
# pieces (stone/iron) are added game-side, so re-check real legal moves before
# declaring the game over, then emit game_over with the popup text.
func check_game_over(in_check):
	if game_over_emitted:
		return
	if _side_to_move_has_move():
		Globals.dprint("[game_over] check_game_over called but side to move still has a move -- not over")
		return  # a stone/iron piece can still move -> not over
	# Head of Snake applies per-colour: whenever the MATED colour (white_to_move,
	# the side with no legal moves) has its flag on, royalty passes to the next
	# piece instead of ending the game.
	var mated_white = white_to_move
	var this_side_has_head_of_snake = head_of_snake_white if mated_white else head_of_snake_black
	if this_side_has_head_of_snake and _crown_next_royal():
		Globals.dprint("[game_over] head of snake: royalty passed to a new piece, game continues")
		return
	# Stalemate is a draw — except in head-of-snake, where reaching here means a
	# side is truly finished (mated and out of heads, or the player mated).
	var draw = (not in_check) and not this_side_has_head_of_snake
	if draw and draws_favor_black:
		Globals.dprint("[game_over] draw converted to automatic Black win (draws_favor_black)")
		game_over_emitted = true
		_award_win_once(false)
		emit_signal("game_over", _game_over_text(true) + " (Draw)")
		return
	if draw and draws_favor_white:
		Globals.dprint("[game_over] draw converted to automatic White win (draws_favor_white)")
		game_over_emitted = true
		_award_win_once(true)
		emit_signal("game_over", _game_over_text(false) + " (Draw)")
		return
	var text = "Draw" if draw else _game_over_text(white_to_move)
	Globals.dprint("[game_over] mated_white=%s in_check=%s head_of_snake=%s -> %s" % [mated_white, in_check, this_side_has_head_of_snake, text])
	game_over_emitted = true
	if not draw:
		_award_win_once(not white_to_move)  # the side to move lost
	emit_signal("game_over", text)

func _side_to_move_has_move():
	var group = "white_pieces" if white_to_move else "black_pieces"
	for piece in get_tree().get_nodes_in_group(group):
		if not piece.dead and piece.legal_moves.size() > 0:
			return true
	return false

# Game-over text from the loser's colour (player perspective vs the AI, or hot-seat).
func _game_over_text(white_loses):
	if computer_opponent:
		return "You Lose" if white_loses else "You Win"
	return "Black Wins" if white_loses else "White Wins"

# --- Economy ---
# Capture bonus: the captured piece's value scaled by the CAPTURER's material
# multiplier (gold/silver/blood/glass). Only the player's own captures pay out.
# A glass capturer may then shatter (rolled here, applied in move()).
func _award_capture(capturer, captured):
	if capturer == null or captured == null or capturer.white != player_white:
		return
	var eff = Globals.MATERIAL_EFFECTS.get(capturer.piece_material, {})
	var amount = int(round(Globals.piece_value(captured.piece_type) * eff.get("money_mult", 1.0)))
	if RunState.has_relic("bloodstone"):
		amount += 2  # Bloodstone relic: flat bonus per capture
	RunState.add_gold(amount, "capture")
	var break_chance = eff.get("break_chance", 0.0)
	if RunState.has_relic("glassblower"):
		break_chance = 0.0  # Glassblower's Gloves relic: glass never shatters
	if break_chance > 0.0 and randf() < break_chance:
		_glass_breaking = capturer

# Blood: when one of YOUR blood pieces is captured it's lost PERMANENTLY from the
# run army (recorded for the next battle's rebuild). It is not royal — losing it
# does not end the battle; it just dies normally and never comes back this run.
func _on_blood_death(captured):
	if captured == null or captured.white != player_white:
		return
	if Globals.MATERIAL_EFFECTS.get(captured.piece_material, {}).get("lose_on_loss", false):
		RunState.lose_piece(captured.origin)

# Debug / convenience: end the current battle as a player win (Auto-Win button).
func force_win_player():
	if game_over_emitted:
		return
	game_over_emitted = true
	_award_win_once(player_white)
	emit_signal("game_over", _game_over_text(not player_white))

# Win reward: the primary, mode-agnostic income — paid once when YOU win.
func _award_win_once(winner_white):
	if win_awarded:
		return
	win_awarded = true
	player_won = (winner_white == player_white)
	if player_won:
		var amount = 50 + 10 * RunState.floor
		if RunState.has_relic("merchants_scale"):
			amount = int(round(amount * 1.5))  # Merchant's Scale relic
		RunState.add_gold(amount, "win")

# Unroyal: a side with no pieces left has lost (you win by capturing everything).
func _check_unroyal_win():
	if game_over_emitted:
		return false
	for white in [true, false]:
		var grp = "white_pieces" if white else "black_pieces"
		var alive = false
		var alive_count = 0
		for p in get_tree().get_nodes_in_group(grp):
			if not p.dead:
				alive = true
				alive_count += 1
		if not alive:
			Globals.dprint("[unroyal] %s has zero pieces left -> game over" % ("white" if white else "black"))
			game_over_emitted = true
			_award_win_once(not white)  # this side has no pieces -> the other won
			emit_signal("game_over", _game_over_text(white))
			return true
	return false

# Atomic (blast_on_capture): a side's PSEUDOKING can be destroyed directly by
# a nearby explosion with no "check" ever involved -- check_game_over()'s
# perft/in_check-based win-vs-draw split has no way to tell that apart from a
# genuine stalemate (confirmed: blowing up the enemy king gave a Draw).
# Same category as Unroyal/KOTH/King Race -- needs its own direct check.
func _check_atomic_win():
	if game_over_emitted:
		return false
	for white in [true, false]:
		var grp = "white_pieces" if white else "black_pieces"
		var has_king = false
		for p in get_tree().get_nodes_in_group(grp):
			if not p.dead and p.piece_type == Globals.Piece_Type_ENUMs.PSEUDOKING:
				has_king = true
				break
		if not has_king:
			Globals.dprint("[atomic] %s has no king left -> game over" % ("white" if white else "black"))
			game_over_emitted = true
			_award_win_once(not white)  # this side's king was blown up -> the other won
			emit_signal("game_over", _game_over_text(white) + " (Explosion)")
			return true
	return false

# King of the Hill: a KING sitting on d4/e4/d5/e5 wins immediately. This is
# an engine "flag reached" rule, not checkmate, so it does NOT reduce legal
# moves to zero -- the normal perft-based check_game_over() never fires for
# it, hence this separate, direct, client-side check every turn.
const _KOTH_HILL = ["d4", "e4", "d5", "e5"]
func _check_koth_win():
	if game_over_emitted:
		return false
	for white in [true, false]:
		var grp = "white_pieces" if white else "black_pieces"
		for p in get_tree().get_nodes_in_group(grp):
			if not p.dead and p.piece_type == Globals.Piece_Type_ENUMs.KING and p.chess_position in _KOTH_HILL:
				Globals.dprint("[koth] %s king reached the hill (%s) -> game over" % ["white" if white else "black", p.chess_position])
				game_over_emitted = true
				_award_win_once(white)
				emit_signal("game_over", _game_over_text(not white) + " (King of the Hill)")
				return true
	return false

# King Race: same "flag reached, doesn't zero out legal moves" problem as
# King of the Hill -- a KING reaching the far rank (board.length) wins
# immediately, checked directly instead of relying on perft-based detection.
func _check_king_race_win():
	if game_over_emitted:
		return false
	for white in [true, false]:
		var grp = "white_pieces" if white else "black_pieces"
		for p in get_tree().get_nodes_in_group(grp):
			if not p.dead and p.piece_type == Globals.Piece_Type_ENUMs.KING and int(p.chess_position.substr(1)) == length:
				Globals.dprint("[king_race] %s king reached rank %d (%s) -> game over" % ["white" if white else "black", length, p.chess_position])
				game_over_emitted = true
				_award_win_once(white)
				emit_signal("game_over", _game_over_text(not white) + " (King Race)")
				return true
	return false

# Brittle curse tick: called once at the start of each of the player's own
# turns (from _finish_move, before the position is sent to the engine, so a
# shatter is reflected in the next legal-move query). See the brittle_curse
# var comment for the 3-turn cycle shape.
func _brittle_tick_curse():
	if _brittle_target != null and _brittle_target.dead:
		_brittle_target = null  # died some other way (e.g. a normal capture)
	match _brittle_tick:
		0:
			_brittle_target = _pick_brittle_target()
			if _brittle_target != null:
				_brittle_target.brittle_stage = 1
				_brittle_target.queue_redraw()
		1:
			if _brittle_target != null:
				_brittle_target.brittle_stage = 2
				_brittle_target.queue_redraw()
		2:
			if _brittle_target != null:
				_shatter_brittle_target()
	_brittle_tick = (_brittle_tick + 1) % 3

func _pick_brittle_target():
	var grp = "white_pieces" if player_white else "black_pieces"
	var candidates = []
	for p in get_tree().get_nodes_in_group(grp):
		if p.dead:
			continue
		if p.piece_type == Globals.Piece_Type_ENUMs.KING or p.piece_type == Globals.Piece_Type_ENUMs.PRINCE:
			continue
		candidates.append(p)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

func _shatter_brittle_target():
	var p = _brittle_target
	_brittle_target = null
	if p == null or p.dead:
		return
	get_square(p.chess_position).has_piece = false
	if p.white == player_white:
		RunState.lose_piece(p.origin)  # permanently gone for the rest of the run, same as a blood death
	p.delete_self()

# Head of Snake: the mated royal disappears and royalty passes to the next piece,
# scanning the mated side's back rank forward. False if no piece is left to crown.
func _crown_next_royal():
	var white = white_to_move  # the checkmated side (to move, no legal moves)
	var old_royal = _find_royal(white)
	if old_royal != null:
		get_square(old_royal.chess_position).has_piece = false
		old_royal.delete_self()
	var next = _next_crownable(white)
	if next == null:
		return false
	next.piece_type = Globals.Piece_Type_ENUMs.KING
	next.get_node("Sprite2D").play(("white_" if white else "black_") + "king")
	get_square(next.chess_position).piece_type = Globals.Piece_Type_ENUMs.KING
	for p in get_tree().get_nodes_in_group("pieces"):
		p.legal_moves = []
	# Re-sync and hand the turn back to the enemy so its new head actually plays.
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.send_to_stockfish("go depth 10")
	top_level.send_to_stockfish("eval")
	top_level.perft()
	return true

func _find_royal(white):
	var grp = "white_pieces" if white else "black_pieces"
	for p in get_tree().get_nodes_in_group(grp):
		if not p.dead and (p.piece_type == Globals.Piece_Type_ENUMs.PRINCE or p.piece_type == Globals.Piece_Type_ENUMs.KING):
			return p
	return null

func _next_crownable(white):
	var ranks = range(1, length + 1) if white else range(length, 0, -1)
	for r in ranks:
		for f in range(width):
			var p = get_piece(str(possible_letters[f]) + str(r))
			if p != null and not p.dead and p.white == white \
					and p.piece_type != Globals.Piece_Type_ENUMs.PRINCE \
					and p.piece_type != Globals.Piece_Type_ENUMs.KING:
				return p
	return null

# Atomic blast: destroys every non-pawn piece (either colour) on the 8 squares
# around center_sq. Pawns are immune to the blast (same as real Atomic chess),
# though they still die normally if directly captured. Returns the list of
# squares that were cleared, for logging only.
func _explode_adjacent(center_sq):
	var cf = possible_letters.find(center_sq[0])
	var cr = int(center_sq.substr(1))
	var cleared = []
	for df in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			if df == 0 and dr == 0:
				continue
			var nf = cf + df
			var nr = cr + dr
			if nf < 0 or nf >= width or nr < 1 or nr > length:
				continue
			var sq = possible_letters[nf] + str(nr)
			var p = get_piece(sq)
			if p != null and not p.dead and not Globals.is_pawn_type(p.piece_type):
				get_square(sq).has_piece = false
				p.delete_self()
				cleared.append(sq)
	return cleared

# Zombie respawn: `captured` comes back one rung down Globals'
# demotion ladder (Globals.zombie_target) at its original battle-start
# square (captured.origin), or if that's unavailable, the nearest empty
# square that neither attacks nor is attacked by the enemy. Keeps the same
# `origin` as before (still the same run-army slot, just a weaker piece
# occupying it now) and keeps the "zombie" modifier tag -- the ladder
# target is never pawn-type except at the very bottom (Short Pawn), so the
# charge naturally re-arms rung by rung until it bottoms out there.
# No undo support -- same placeholder status as the petrify/atomic captures.
func _zombie_respawn(captured):
	var is_white = captured.white
	var home = captured.origin if captured.origin != "" else captured.chess_position
	var target_type = Globals.zombie_target(captured.piece_type)
	var target_sq = home if _zombie_square_ok(home, is_white, target_type) else _zombie_nearest_safe_square(home, is_white, target_type)
	if target_sq == "":
		Globals.dprint("[zombie] no safe square found for %s's respawn near %s -- staying dead" % ["white" if is_white else "black", home])
		return
	var prefix = "white_" if is_white else "black_"
	var new_piece = piece_scene.instantiate()
	new_piece.white = is_white
	new_piece.add_to_group("white_pieces" if is_white else "black_pieces")
	new_piece.piece_type = target_type
	new_piece.get_node("Sprite2D").play(prefix + Globals.give_piece_name_from_piece_type(target_type))
	new_piece.chess_position = target_sq
	new_piece.origin = captured.origin
	new_piece.apply_modifiers(["zombie"])
	var sq = get_square(target_sq)
	new_piece.global_position = sq.global_position + sq.get_node("CollisionShape2D").shape.extents
	add_child(new_piece)
	sq.has_piece = true
	sq.piece_type = target_type
	sq.white = is_white
	Globals.dprint("[zombie] %s demotes to %s at %s (home was %s)" % [Globals.give_piece_name_from_piece_type(captured.piece_type), Globals.give_piece_name_from_piece_type(target_type), target_sq, home])

# Nearest-first search (Chebyshev distance, ties broken by file then rank)
# for a square that passes _zombie_square_ok, starting from `center`.
func _zombie_nearest_safe_square(center, is_white, piece_type):
	var cf = possible_letters.find(center[0])
	var cr = int(center.substr(1, center.length() - 1))
	var candidates = []
	for f in width:
		for r in range(1, length + 1):
			if f == cf and r == cr:
				continue
			candidates.append({"sq": possible_letters[f] + str(r), "d": max(abs(f - cf), abs(r - cr))})
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])
	for c in candidates:
		if _zombie_square_ok(c["sq"], is_white, piece_type):
			return c["sq"]
	return ""

# Empty, and a `piece_type` of `is_white` placed there would neither attack
# nor be attacked by the enemy. Reuses _attacks()'s real movement logic (via
# a lightweight stand-in Dictionary instead of a real piece node) so this
# works correctly for whatever the demotion ladder actually produces -- a
# Rook's reach is nothing like a Pawn's.
func _zombie_square_ok(sq, is_white, piece_type):
	var s = get_square(sq)
	if s == null or s.has_piece:
		return false
	var enemy_group = "black_pieces" if is_white else "white_pieces"
	var fake = {"chess_position": sq, "piece_type": piece_type, "white": is_white, "piece_material": ""}
	for p in get_tree().get_nodes_in_group(enemy_group):
		if p.dead:
			continue
		if _attacks(p, sq) or _attacks(fake, p.chess_position):
			return false
	return true


func conduct_castling_checks(piece_to_move, previous_chess_position, chess_position):
	# Reset for this move; only set below when a castle actually happens. (Resetting
	# here, not after the move() append, keeps redo from leaving a stale value.)
	castle_info = {}
	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.ROOK:
		if piece_to_move.white:
			if previous_chess_position[0] == white_rook_queenside_start_file:
				white_rook_queenside_moved = true
			elif previous_chess_position[0] == white_rook_kingside_start_file:
				white_rook_kingside_moved = true
		else:
			if previous_chess_position[0] == black_rook_queenside_start_file:
				black_rook_queenside_moved = true
			elif previous_chess_position[0] == black_rook_kingside_start_file:
				black_rook_kingside_moved = true

	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.KING:
		# Chess960: the engine reports castling as the king landing on its own
		# rook's square. move() detects that and leaves the rook's square here
		# via _castle_rook_hint_square (and remaps chess_position to the king's
		# real landing square, g/c, before calling this). Handle it generically
		# instead of the file-letter heuristic below, which assumes a standard
		# e1/a1/h1 start.
		if chess960 and _castle_rook_hint_square != "":
			var rook_sq = _castle_rook_hint_square
			_castle_rook_hint_square = ""
			var kingside = possible_letters.find(rook_sq[0]) > possible_letters.find(previous_chess_position[0])
			var rank = previous_chess_position.substr(1, previous_chess_position.length() - 1)
			var rook_dest = ("f" if kingside else "d") + rank
			Globals.dprint("[chess960] castle: king %s->%s, rook %s->%s, kingside=%s" % [previous_chess_position, chess_position, rook_sq, rook_dest, kingside])
			if piece_to_move.white:
				white_king_moved = true
				white_castled = true
			else:
				black_king_moved = true
				black_castled = true
			castle_rook(rook_sq, rook_dest)
			castle_info = {"white": piece_to_move.white, "kingside": kingside, "rook_origin": rook_sq, "rook_dest": rook_dest}
			return

		if piece_to_move.white:
			white_king_moved = true

			if previous_chess_position[0] == "e":
				if chess_position[0] == "g" and !white_rook_kingside_moved:
					white_castled = true
					castle_rook("h1", "f1")
					castle_info = {"white": true, "kingside": true}


				if chess_position[0] == "c" and !white_rook_queenside_moved:
					white_castled = true
					castle_rook("a1", "d1")
					castle_info = {"white": true, "kingside": false}

		else:
			black_king_moved = true

			if previous_chess_position[0] == "e":
				# Black's back rank is board.length, not always 8 (e.g. a
				# long/short-board mode) -- white's is always rank 1.
				if chess_position[0] == "g" and !black_rook_kingside_moved:
					black_castled = true
					castle_rook("h" + str(length), "f" + str(length))
					castle_info = {"white": false, "kingside": true}

				if chess_position[0] == "c" and !black_rook_queenside_moved:
					black_castled = true
					castle_rook("a" + str(length), "d" + str(length))
					castle_info = {"white": false, "kingside": false}


	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.ROOK:
		if piece_to_move.white:
			if chess_position[0] == white_rook_queenside_start_file:
				white_rook_queenside_moved = true
			elif chess_position[0] == white_rook_kingside_start_file:
				white_rook_kingside_moved = true
		else:
			if chess_position[0] == black_rook_queenside_start_file:
				black_rook_queenside_moved = true
			elif chess_position[0] == black_rook_kingside_start_file:
				black_rook_kingside_moved = true
				
func conduct_en_passant_check(piece_to_move, previous_chess_position, chess_position):
	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.PAWN:
		var pawn_pos_1 = int(previous_chess_position.substr(1, previous_chess_position.length() - 1))
		var pawn_pos_2 = int(chess_position.substr(1, chess_position.length() - 1))
		
		if previous_chess_position[0] != chess_position[0] and chess_position == en_passant_square:
			var captured_pawn = get_en_passant_piece()
			var captured_square = get_square(get_en_passant_piece().chess_position)
			
			if captured_pawn != null:
				captured_pawn.delete_self()
				
			captured_square.has_piece = false
			captured_piece = true
			
		if abs(pawn_pos_2 - pawn_pos_1) == 2:
			en_passant_square = previous_chess_position[0]
			if piece_to_move.white:
				en_passant_square += str(pawn_pos_2 - 1)
			else:
				en_passant_square += str(pawn_pos_2 + 1)
				
			en_passant_pawn_location = chess_position
			#print(en_passant_square)
		else:
			en_passant_square = ""
			en_passant_pawn_location = ""
	else:
		en_passant_square = ""
		en_passant_pawn_location = ""
		
func is_computer_turn():
	return (white_to_move == !player_white)

# Called by board_container when the engine reports the side to move is in check.
# by_white = the side that just moved (i.e. who delivered the check).
func register_check(by_white):
	if not three_check:
		return
	if by_white:
		white_checks += 1
	else:
		black_checks += 1
	Globals.dprint("[three_check] %s delivered a check -> white=%d black=%d" % ["white" if by_white else "black", white_checks, black_checks])
	# Record the new tally on the move that delivered the check, so undo/redo can
	# restore it exactly.
	if moves.size() > 0:
		moves[moves.size() - 1]["checks_after"] = [white_checks, black_checks]
	if white_checks >= 3:
		Globals.dprint("[three_check] white wins on 3 checks")
		_award_win_once(true)
		three_check_won.emit(true)
	elif black_checks >= 3:
		Globals.dprint("[three_check] black wins on 3 checks")
		_award_win_once(false)
		three_check_won.emit(false)
		
func move(previous_chess_position, chess_position):
	redo_moves.clear()

	# Snapshot every piece's legal moves for THIS position before anything
	# changes. On undo we reload this exact set instead of re-asking the engine
	# (the recompute could desync the position and show impossible moves).
	var legal_snapshot = {}
	for snap_piece in get_tree().get_nodes_in_group("pieces"):
		legal_snapshot[snap_piece.chess_position] = snap_piece.legal_moves.duplicate()
	
	var piece_to_move
	if held_piece != null:
		piece_to_move = held_piece
	else:
		piece_to_move = get_piece(previous_chess_position)

	# Chess960: the engine reports castling as the king landing on its own rook
	# (UCI_Chess960 notation), not g1/c1. Detect that here, before the generic
	# capture logic below runs (which would otherwise delete the rook as a
	# "captured" piece), and remap the destination to the king's real landing
	# square. conduct_castling_checks() reads _castle_rook_hint_square and
	# relocates the rook separately via castle_rook().
	_castle_rook_hint_square = ""
	if chess960 and piece_to_move.piece_type == Globals.Piece_Type_ENUMs.KING:
		var maybe_rook = get_piece(chess_position)
		if maybe_rook != null and maybe_rook.piece_type == Globals.Piece_Type_ENUMs.ROOK and maybe_rook.white == piece_to_move.white:
			_castle_rook_hint_square = chess_position
			var kingside = possible_letters.find(chess_position[0]) > possible_letters.find(previous_chess_position[0])
			var rank = previous_chess_position.substr(1, previous_chess_position.length() - 1)
			Globals.dprint("[chess960] move() detected castle gesture: king %s landed on own rook at %s, remapping destination to %s" % [previous_chess_position, chess_position, ("g" if kingside else "c") + rank])
			chess_position = ("g" if kingside else "c") + rank

	var previous_chess_square = get_square(previous_chess_position)
	var rook_king_movement = []
	var second_square = get_square(chess_position)
	var en_passant_undo_check = check_en_passant()

	if _castle_rook_hint_square != "":
		# The player (or a redo cascade) may have snapped the king's sprite to the
		# square they dropped it on (the rook's square) — correct it to the real
		# landing square now that chess_position has been remapped above.
		piece_to_move.global_position = second_square.global_position + second_square.get_node("CollisionShape2D").shape.extents

	if second_square.has_piece:
		var captured = get_piece(chess_position)
		if captured != null:
			_award_capture(piece_to_move, captured)
			_on_blood_death(captured)
			captured.delete_self()
			# Zombie: captured while NOT currently a pawn (so a piece
			# that promoted back into something else since its last
			# resurrection still counts) respawns as a plain pawn. Checking
			# is_pawn_type() here instead of consuming the modifier tag is
			# what makes the charge re-arm on promotion and get spent for
			# good on a pawn death -- see the comment on the modifier itself.
			if captured.has_modifier("zombie") and not Globals.is_pawn_type(captured.piece_type):
				_zombie_respawn(captured)
			# Petrify-on-capture: either the whole-game Petrified mode rule
			# (queen/rook/bishop/knight only), or an individual piece flagged
			# with the "petrify" modifier (any piece type, any mode -- the
			# same per-piece-tag pattern as racist/time1/double).
			var mode_petrifies = petrified_mode and piece_to_move.piece_type in PETRIFY_TYPES
			var piece_petrifies = piece_to_move.has_modifier("petrify")
			if mode_petrifies or piece_petrifies:
				Globals.dprint("[petrified] capture by %s at %s petrifies it (mode_rule=%s, piece_flag=%s)" % [Globals.give_piece_name_from_piece_type(piece_to_move.piece_type), chess_position, mode_petrifies, piece_petrifies])
				_petrifying = piece_to_move
			if piece_to_move.has_modifier("atomic") or blast_on_capture:
				_exploding = piece_to_move
		captured_piece = true
	second_square.has_piece = true
	second_square.piece_type = piece_to_move.piece_type
	second_square.white = piece_to_move.white
	
	
	
	
	if !piece_to_move.white:
		rook_king_movement = [black_rook_kingside_moved, black_rook_queenside_moved, black_king_moved]
	else:
		rook_king_movement = [white_rook_kingside_moved, white_rook_queenside_moved, white_king_moved]
			
	conduct_castling_checks(piece_to_move, previous_chess_position, chess_position)
	
	conduct_en_passant_check(piece_to_move, previous_chess_position, chess_position)
	
		
	piece_to_move.chess_position = chess_position

	# Brittle curse: moving the targeted piece lifts the threat immediately
	# (the cycle still runs its full 3 turns before a new piece is picked).
	if piece_to_move == _brittle_target:
		piece_to_move.brittle_stage = 0
		piece_to_move.queue_redraw()
		_brittle_target = null

	if computer_opponent and (white_to_move == !player_white):
		var tween = get_tree().create_tween()
		tween.tween_property(piece_to_move, "global_position", second_square.global_position + second_square.get_node("CollisionShape2D").shape.extents, .1)
		tween.tween_callback(black_moved_piece)
		
	# "double" pieces move twice in a row: on the first move keep the turn (and
	# remember the piece); on the second, flip normally.
	var is_player_piece = not computer_opponent or piece_to_move.white
	var double_first = is_player_piece and piece_to_move.has_modifier("double") and double_pending_piece == null
	var double_second = double_pending_piece == piece_to_move
	if double_first:
		double_pending_piece = piece_to_move
	else:
		if double_second:
			double_pending_piece = null
		_flip_turn(piece_to_move.white)

	var record = {
		"piece": piece_to_move,
		"from_square": previous_chess_square,
		"to_square": get_square(chess_position),
		"from_global_position": previous_chess_square.global_position + previous_chess_square.get_node("CollisionShape2D").shape.extents,
		"piece_legal_moves": piece_to_move.legal_moves,
		"from_position": previous_chess_position,
		"to_position": chess_position,
		"captured": captured_piece,
		"castle": castle_info,
		"rook_king_flags": rook_king_movement,
		"en_passant": en_passant_undo_check,
		"legal_snapshot": legal_snapshot,
		"promoted_to": null,  # set by complete_promotion() if this move is a promotion
		"petrified_from": null,  # set below if this capture petrifies the capturer
		"checks_before": [white_checks, black_checks],
		"checks_after": [white_checks, black_checks],  # updated by register_check() if this move checks
		"cooldown_before": piece_to_move.cooldown_until,
		"cooldown_after": piece_to_move.cooldown_until,  # set below if this piece is timed
	}
	moves.append(record)

	# Timed pieces (time1/time2) lock themselves for N of the mover's own turns.
	for mod in piece_to_move.piece_modifiers:
		var cd = Globals.MODIFIERS.get(mod, {}).get("cooldown", 0)
		if cd > 0:
			piece_to_move.cooldown_until = moves.size() + 2 * cd
			record["cooldown_after"] = piece_to_move.cooldown_until

	# Tag both halves of a completed double move so undo/redo step over the pair.
	if double_second:
		record["double_role"] = "second"
		if moves.size() >= 2:
			moves[moves.size() - 2]["double_role"] = "first"

	captured_piece = false
	set_previous_square(previous_chess_position)
	
	for move in piece_to_move.legal_moves:
		get_square(move).get_node("CollisionShape2D").disabled = true
		get_square(move).get_node("premove").visible = false
		
	# Glass: a piece that just captured may shatter (break_chance, default 25%).
	var broke = false
	if _glass_breaking == piece_to_move:
		_glass_breaking = null
		record["glass_broke"] = true
		get_square(chess_position).has_piece = false
		piece_to_move.delete_self()
		broke = true

	# Petrified: a piece that just captured (queen/rook/bishop/knight) turns
	# into an immobile, uncapturable wall on the square it landed on -- the
	# same WALL piece type already used for placed obstacles (now also
	# recognized by _is_wall_piece()/add_wall_piece_moves() so it's a genuine
	# dead square, not just a piece with no moves of its own). Recorded (like
	# a promotion) so undo/redo can restore the original piece type/sprite.
	if _petrifying == piece_to_move:
		_petrifying = null
		Globals.dprint("[petrified] converting piece at %s to WALL" % chess_position)
		record["petrified_from"] = piece_to_move.piece_type
		piece_to_move.piece_type = Globals.Piece_Type_ENUMs.WALL
		second_square.piece_type = Globals.Piece_Type_ENUMs.WALL
		piece_to_move.get_node("Sprite2D").play(("white_" if piece_to_move.white else "black_") + "wall")

	# Atomic: the capturer + every adjacent non-pawn piece (either colour) are
	# destroyed. No undo support -- undoing an atomic capture does not bring
	# the exploded pieces back (placeholder, same spirit as the petrify badge).
	if not broke and _exploding == piece_to_move:
		_exploding = null
		var blown_up = _explode_adjacent(chess_position)
		Globals.dprint("[atomic] %s at %s explodes, also destroying %s" % [Globals.give_piece_name_from_piece_type(piece_to_move.piece_type), chess_position, blown_up])
		record["atomic_exploded"] = blown_up
		get_square(chess_position).has_piece = false
		piece_to_move.delete_self()
		broke = true

	# A pawn reaching the last rank must promote. Defer the engine handoff until a
	# piece is chosen — a pawn sitting on the last rank is an illegal position the
	# engine would reject.
	if not broke and Globals.is_pawn_type(piece_to_move.piece_type) and _is_promotion_rank(chess_position, piece_to_move.white):
		pending_promotion = {"pawn": piece_to_move, "prev": previous_chess_position, "cur": chess_position, "record": record}
		# Clear legal moves so no other piece can be picked up while choosing.
		for p in get_tree().get_nodes_in_group("pieces"):
			p.legal_moves = []
		if not computer_opponent or piece_to_move.white == player_white:
			_show_promotion_popup(piece_to_move)
		else:
			# Opponent (engine) promotion: auto-pick so we don't block on a popup.
			complete_promotion(_default_promotion_choice(piece_to_move.white))
		return

	_finish_move(previous_chess_position, chess_position)
	

			
			
			
# Hand the turn to the other side (freeze the mover, unfreeze the opponent unless
# the AI controls it). Factored out so the double modifier can skip it.
func _flip_turn(piece_is_white):
	if piece_is_white:
		white_to_move = false
		freeze_white_pieces()
		if !computer_opponent or !is_computer_turn():
			unfreeze_black_pieces()
	else:
		white_to_move = true
		freeze_black_pieces()
		if !computer_opponent or !is_computer_turn():
			unfreeze_white_pieces()
	# A real turn transition (skipped during a double move's first half, which
	# keeps the turn) -- tick the curse exactly once per player turn.
	if brittle_curse and white_to_move == player_white:
		_brittle_tick_curse()

# A double piece that can't make its second move just ends the turn normally.
func _end_double_turn():
	var was_white = double_pending_piece.white
	double_pending_piece = null
	_flip_turn(was_white)
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.send_to_stockfish("go depth 10")
	top_level.send_to_stockfish("eval")
	top_level.perft()

func _finish_move(prev, cur):
	# Engine handoff + legal-move refresh for the next turn. Split out of move()
	# so promotion can run it AFTER a piece is chosen.
	if unroyal and _check_unroyal_win():
		return
	if koth and _check_koth_win():
		return
	if king_race and _check_king_race_win():
		return
	if blast_on_capture and _check_atomic_win():
		return
	if double_pending_piece != null:
		# First half of a double move: keep the turn, re-query the same side's moves
		# (restricted to this piece in apply_modifier_filters), no AI handoff.
		for piece in get_tree().get_nodes_in_group("pieces"):
			piece.legal_moves = []
		top_level.send_to_stockfish("position fen " + generate_fen_string())
		top_level.send_to_stockfish("eval")
		top_level.perft()
		return
	send_move(prev, cur)  # already sends "eval" (alongside "go depth 10") -- don't duplicate it here
	for piece in get_tree().get_nodes_in_group("pieces"):
		piece.legal_moves = []
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.perft()

func _is_promotion_rank(pos, is_white):
	var rank = int(pos.substr(1, pos.length() - 1))
	if is_white:
		return rank == length
	return rank == 1

# A promoting pawn may become any distinct piece type already on its own side of
# the board, except pawns and royal pieces (king / prince).
func get_promotion_choices(is_white):
	var excluded = [Globals.Piece_Type_ENUMs.PAWN, Globals.Piece_Type_ENUMs.SHORTPAWN,
		Globals.Piece_Type_ENUMs.BACKPAWN, Globals.Piece_Type_ENUMs.KING, Globals.Piece_Type_ENUMs.PRINCE,
		Globals.Piece_Type_ENUMs.PSEUDOKING, Globals.Piece_Type_ENUMs.WALL]
	var group = "white_pieces" if is_white else "black_pieces"
	var choices = []
	for p in get_tree().get_nodes_in_group(group):
		if p.dead:
			continue
		if p.piece_type in excluded:
			continue
		if p.piece_type not in choices:
			choices.append(p.piece_type)
	return choices

func _default_promotion_choice(is_white):
	# Used for the engine's own promotions (no popup): prefer a queen, else the
	# first available choice.
	var choices = get_promotion_choices(is_white)
	if Globals.Piece_Type_ENUMs.QUEEN in choices:
		return Globals.Piece_Type_ENUMs.QUEEN
	if choices.is_empty():
		return Globals.Piece_Type_ENUMs.QUEEN
	return choices[0]

func _show_promotion_popup(pawn):
	top_level.promotion = true
	freeze_buttons()
	var display_node = get_node("Promotion_display")
	display_node.global_position = pawn.global_position
	display_node.display(get_promotion_choices(pawn.white), pawn.white)
	display_node.show()

func complete_promotion(chosen_type):
	var pawn = pending_promotion["pawn"]
	pending_promotion["record"]["promoted_from"] = pawn.piece_type
	pawn.piece_type = chosen_type
	pending_promotion["record"]["promoted_to"] = chosen_type
	var prefix = "white_" if pawn.white else "black_"
	pawn.get_node("Sprite2D").play(prefix + Globals.give_piece_name_from_piece_type(chosen_type))
	get_square(pawn.chess_position).piece_type = chosen_type

	var display_node = get_node("Promotion_display")
	display_node.clear()
	display_node.hide()
	top_level.promotion = false
	unfreeze_buttons()

	var prev = pending_promotion["prev"]
	var cur = pending_promotion["cur"]
	pending_promotion = {}
	_finish_move(prev, cur)

func castle_rook(rook_position, new_rook_position):
	var rook_to_move = get_piece(rook_position)
	if rook_to_move == null:
		print("[castle_rook] ERROR: no piece found at %s (expected the castling rook) -- aborting, board state is now inconsistent" % rook_position)
		return
	var rook_to_move_square = get_square(new_rook_position)
	var old_rook_square = get_square(rook_position)

	rook_to_move.chess_position = new_rook_position
	old_rook_square.has_piece = false
	old_rook_square.piece_type = Globals.Piece_Type_ENUMs.NONE
					
	var tween = get_tree().create_tween()
	tween.tween_property(rook_to_move, "global_position", rook_to_move_square.global_position + rook_to_move_square.get_node("CollisionShape2D").shape.extents, .05)
	rook_to_move_square.has_piece = true
	rook_to_move_square.piece_type = rook_to_move.piece_type
	rook_to_move_square.white = rook_to_move.white
	
func get_en_passant_piece():
	if en_passant_square[1] == "6":
		return get_piece(en_passant_square[0] + "5")
	else:
		return get_piece(en_passant_square[0] + "4")
		
func redo():
	if redo_moves.size() > 0:
		freeze_buttons()
		freeze_pieces()
		black_move_counter += 1
		# Mirrors undo()'s step count: always a full round (3 plies if it was
		# a double move, else 2), landing back on the same colour's turn.
		if redo_moves.back().get("double_role", "") == "first":
			redo_steps_remaining = 3
		else:
			redo_steps_remaining = 2
		redo_individual_move()
		

		
func redo_individual_move():
	if redo_moves.size() == 0:
		undo_done()
		return
	var record = redo_moves.pop_back()
	moves.append(record)
	

	var redo_piece = record["piece"]
	var previous_square = record["from_square"]
	var current_square = record["to_square"]
	var previous_global_position = record["from_global_position"]

	# Re-applying this move hands the turn to the other colour -- except a
	# double move's first half, which keeps the turn on the same piece (see
	# move()'s own double-move handling). Never tracked here before either
	# (same gap as undo_individual_move's white_to_move fix above).
	if record.get("double_role", "") == "first":
		white_to_move = redo_piece.white
	else:
		white_to_move = not redo_piece.white

	previous_square.has_piece = false
	previous_square.piece_type = Globals.Piece_Type_ENUMs.NONE
	
	if current_square.has_piece:
		get_piece(current_square.chess_position).delete_self()
		
	conduct_en_passant_check(redo_piece, previous_square.chess_position, current_square.chess_position)
	
	if current_square.chess_position == en_passant_square:
		get_en_passant_piece().delete_self()
		en_passant_square = ""
		
	
	
	current_square.piece_type = redo_piece.piece_type
	current_square.has_piece = true
	current_square.white = redo_piece.white
	
	redo_piece.chess_position = current_square.chess_position
	redo_piece.cooldown_until = record.get("cooldown_after", redo_piece.cooldown_until)


	previous_square.piece_type = redo_piece.piece_type

			
			
	# Re-apply castling/king-rook state the way move() does. This re-performs the
	# rook move on a castle — the old code restored the PRE-move flags here, so
	# the rook never re-castled — and sets the correct post-move flags.
	if record["castle"].has("rook_origin"):
		_castle_rook_hint_square = record["castle"]["rook_origin"]
	conduct_castling_checks(redo_piece, previous_square.chess_position, current_square.chess_position)
	
	
	
	redo_piece.legal_moves = record["piece_legal_moves"]
	if record.has("checks_after"):
		white_checks = record["checks_after"][0]
		black_checks = record["checks_after"][1]

	# Redo a promotion: re-apply the chosen piece.
	if record.get("promoted_to", null) != null:
		redo_piece.piece_type = record["promoted_to"]
		var promo_prefix = "white_" if redo_piece.white else "black_"
		redo_piece.get_node("Sprite2D").play(promo_prefix + Globals.give_piece_name_from_piece_type(record["promoted_to"]))
		current_square.piece_type = record["promoted_to"]

	# Redo a petrify: turn the piece back into a wall on this square.
	if record.get("petrified_from", null) != null:
		redo_piece.piece_type = Globals.Piece_Type_ENUMs.WALL
		redo_piece.get_node("Sprite2D").play(("white_" if redo_piece.white else "black_") + "wall")
		current_square.piece_type = Globals.Piece_Type_ENUMs.WALL
	
	redo_steps_remaining -= 1

	var tween = get_tree().create_tween()
	tween.tween_property(redo_piece, "global_position", current_square.global_position + current_square.get_node("CollisionShape2D").shape.extents, .1)
	if redo_steps_remaining > 0 and redo_moves.size() > 0:
		tween.tween_callback(redo_individual_move)
	else:
		tween.tween_callback(undo_done)

	
func undo():
	if moves.size() > 0:
		freeze_buttons()
		freeze_pieces()
		black_move_counter -= 1
		# Always a full round (2 plies): undoing an EVEN number of plies
		# preserves whose turn it is, so this lands back on the SAME colour
		# that was about to move before you pressed undo, just with the
		# position rewound one round. 3 if the round being undone was a
		# double move (its own 2 halves + the reply); 1 if you're mid-double.
		if double_pending_piece != null:
			double_pending_piece = null
			undo_steps_remaining = 1
		elif moves.size() >= 2 and moves[moves.size() - 2].get("double_role", "") == "second":
			undo_steps_remaining = 3
		else:
			undo_steps_remaining = 2
		undo_individual_move()
	
func undo_individual_move():
	if moves.size() == 0:
		undo_finalize()
		return

	var record = moves.pop_back()
	redo_moves.append(record)
	

	var undo_piece = record["piece"]
	# Un-making this move means it's this piece's colour's turn again. This was
	# never tracked at all during undo before -- white_to_move just sat at
	# whatever it was before undo() ran, which happened to not matter when
	# undo always stepped back an even number of plies (always landing back on
	# white). Now that hotseat undo can land on either colour, this has to be
	# right for unfreezing the correct side's pieces afterward.
	white_to_move = undo_piece.white
	if record.get("glass_broke", false):  # un-shatter a glass piece on undo
		undo_piece.dead = false
		captured_pieces.erase(undo_piece)
	var previous_square = record["from_square"]
	var current_square = record["to_square"]
	var previous_global_position = record["from_global_position"]
	
	current_square.has_piece = false

	# Undo a promotion: turn the piece back into a pawn before it returns home.
	if record.get("promoted_to", null) != null:
		var original_type = record.get("promoted_from", Globals.Piece_Type_ENUMs.PAWN)
		undo_piece.piece_type = original_type
		var pawn_prefix = "white_" if undo_piece.white else "black_"
		undo_piece.get_node("Sprite2D").play(pawn_prefix + Globals.give_piece_name_from_piece_type(original_type))

	# Undo a petrify: turn the wall back into the piece it was before capturing.
	if record.get("petrified_from", null) != null:
		var original_type = record["petrified_from"]
		undo_piece.piece_type = original_type
		var prefix = "white_" if undo_piece.white else "black_"
		undo_piece.get_node("Sprite2D").play(prefix + Globals.give_piece_name_from_piece_type(original_type))

	if record["captured"]:
		if captured_pieces.size() > 0:
			var captured_piece = captured_pieces.pop_back()
			
			captured_piece.global_position = captured_piece.dead_position
			captured_piece.dead = false
			var captured_square = get_square(captured_piece.chess_position)
			captured_square.has_piece = true
			captured_square.piece_type = captured_piece.piece_type
			captured_square.white = captured_piece.white
	
	previous_square.piece_type = undo_piece.piece_type
	
	var castle = record["castle"]
	if not castle.is_empty():
		if castle.has("rook_origin"):
			undo_castle(castle["rook_origin"], castle["rook_dest"])
		elif castle["white"]:
			if castle["kingside"]:
				undo_castle("h1", "f1")
			else:
				undo_castle("a1", "d1")
		else:
			if castle["kingside"]:
				undo_castle("h" + str(length), "f" + str(length))
			else:
				undo_castle("a" + str(length), "d" + str(length))
			
			
			
	var flags = record["rook_king_flags"]
	if undo_piece.white:
		white_rook_kingside_moved = flags[0]
		white_rook_queenside_moved = flags[1]
		white_king_moved = flags[2]
	else:
		black_rook_kingside_moved = flags[0]
		black_rook_queenside_moved = flags[1]
		black_king_moved = flags[2]
	
	
	previous_square.has_piece = true
	previous_square.white = undo_piece.white
	undo_piece.legal_moves = record["piece_legal_moves"]
	undo_piece.chess_position = record["from_position"]
	undo_piece.cooldown_until = record.get("cooldown_before", 0)  # un-move resets its timer

	if "-" not in record["en_passant"]:
		en_passant_square = record["en_passant"]
	
	# The last step's snapshot is the one undo_finalize applies. Stop after the
	# requested number of plies (or early if the history runs out) — colour no
	# longer decides when to stop.
	pending_legal_snapshot = record["legal_snapshot"]
	if record.has("checks_before"):
		white_checks = record["checks_before"][0]
		black_checks = record["checks_before"][1]
	undo_steps_remaining -= 1

	var tween = get_tree().create_tween()
	tween.tween_property(undo_piece, "global_position", previous_global_position, .1)
	if undo_steps_remaining > 0 and moves.size() > 0:
		tween.tween_callback(undo_individual_move)
	else:
		tween.tween_callback(undo_finalize)
		

	
func undo_done():

	for piece in get_tree().get_nodes_in_group("pieces"):
		piece.legal_moves =  []

	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.send_to_stockfish("eval")
	top_level.perft()
	unfreeze_buttons()
	# Hotseat undo can now land on EITHER colour's turn (not always white's --
	# see undo()'s comment), so unfreeze whichever colour is actually to move.
	if white_to_move:
		unfreeze_white_pieces()
	else:
		unfreeze_black_pieces()

func undo_finalize():
	# Reload the legal moves this position had when it was actually played,
	# instead of re-running perft (which could desync and surface impossible
	# moves). Keyed by each piece's restored square.
	for piece in get_tree().get_nodes_in_group("pieces"):
		if pending_legal_snapshot.has(piece.chess_position):
			piece.legal_moves = pending_legal_snapshot[piece.chess_position].duplicate()
		else:
			piece.legal_moves = []
	# Keep the engine's position in sync for the next move / evaluation.
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	unfreeze_buttons()
	if white_to_move:
		unfreeze_white_pieces()
	else:
		unfreeze_black_pieces()

func undo_castle(rook_position, old_rook_position):
	var rook = get_piece(old_rook_position)
	if rook == null:
		print("[undo_castle] ERROR: no piece found at %s (expected the castled rook) -- aborting, board state is now inconsistent" % old_rook_position)
		return
	var previous_rook_square = get_square(old_rook_position)
	var new_rook_square = get_square(rook_position)

	previous_rook_square.has_piece = false
	previous_rook_square.piece_type = Globals.Piece_Type_ENUMs.NONE
	rook.chess_position = rook_position
	new_rook_square.has_piece = true
	new_rook_square.piece_type = rook.piece_type
	new_rook_square.white = rook.white
	
	if rook.white:
		white_king_moved = false
		white_castled = false
	else:
		black_king_moved = false
		black_castled = false
	
	var tween = get_tree().create_tween()
	tween.tween_property(rook, "global_position", get_square(rook_position).global_position + get_square(rook_position).get_node("CollisionShape2D").shape.extents, .05)
	
	
func black_moved_piece():
	white_to_move = true
	unfreeze_white_pieces()
	
func get_array_of_individual_moves_from_fen_string(fen_move):
	var result = []
	var matcher = regex.search(fen_move)
	
	while matcher:
		result.append(matcher.get_string(0))
		matcher = regex.search(fen_move, matcher.get_end())
	
	if fen_move[-1] in "abcdefghijklmnopqrstuvwxyz":
		result.append(fen_move[-1])
	
	return result

	
func send_move(previous_chess_position, chess_position):
	if chess_position == previous_chess_position:
		return

	var fen_string = generate_fen_string()
	top_level.send_to_stockfish("position fen " + fen_string)
	# "go depth 10" exists purely to make the engine search and eventually print
	# "bestmove ..." for board_container to execute as the AI's move -- it was
	# being sent unconditionally, even in human-vs-human games with no AI move
	# ever needed, and even right before this file also sends ANOTHER "position
	# fen" + "go perft 1" a few lines later in _finish_move (without waiting for
	# "go depth 10"'s search to finish). That's a real search thread still
	# reading the position while we mutate it again underneath it -- a classic
	# data race, and a strong suspect for "a piece's legal moves intermittently
	# look like some other piece's" corruption, worse the more moves have been
	# played (more chances to hit the race window). Only send it when an AI
	# move is actually about to be needed.
	if computer_opponent and is_computer_turn():
		top_level.send_to_stockfish("go depth 10")
	top_level.send_to_stockfish("eval")

func get_square(chess_location):
	chess_location = chess_location.replace(" ", "")
	return squares_dict[chess_location]
			
func get_piece(chess_location):
	chess_location = chess_location.replace(" ", "")
	
	for piece in get_tree().get_nodes_in_group("pieces"):

		if chess_location in piece.chess_position and !piece.dead:
			return piece
			
func set_previous_square(chess_position):
	get_square(chess_position).has_piece = false
	get_square(chess_position).piece_type = Globals.Piece_Type_ENUMs.NONE

# Raw board_array dump (what generate_fen_string actually reads from) --
# labeled by each square's OWN chess_position, so if board_array[i][j] and
# squares_dict ever disagree about what square something is (an aliasing/
# construction bug), or a square's has_piece/piece_type are inconsistent
# with what's actually on the visual board, it shows up directly here
# instead of only in the resulting FEN text.
func _debug_dump_board_array():
	if not Globals.debug_logging:
		return
	var lines = []
	for i in range(length):
		var row = []
		for j in range(width):
			var sq = board_array[i][j]
			if sq.has_piece:
				row.append("%s:%s%s" % [sq.chess_position, Globals.give_piece_name_from_piece_type(sq.piece_type).substr(0, 3), ("w" if sq.white else "b")])
			else:
				row.append("%s:." % sq.chess_position)
		lines.append(" ".join(row))
	Globals.dprint("[board_dump]\n" + "\n".join(lines))

func generate_fen_string():
	_debug_dump_board_array()
	var fen_string = ""
	blank_space_counter = 0
	# Squares holding an uncapturable wall piece (iron/stone material, or a legacy
	# STONE/IRONQUEEN) are sent to the engine as "*".
	var wall_at = {}
	for piece in get_tree().get_nodes_in_group("pieces"):
		if not piece.dead and _is_wall_piece(piece):
			wall_at[piece.chess_position] = true
	for i in range(length):
		if i > 0:
			if blank_space_counter > 0:
				fen_string += str(blank_space_counter)
				blank_space_counter = 0
			fen_string += "/"
		
			
			
		for j in range(width):
			var square = board_array[i][j]
			if square.has_piece:
				if blank_space_counter > 0:
					fen_string += str(blank_space_counter)
					blank_space_counter = 0
				if wall_at.has(square.chess_position):
					fen_string += "*"  # iron/stone -> engine wall square (uncapturable, blocks)
				else:
					fen_string += Globals.get_fen_string_from_enum(square.piece_type, square.white)
			elif j == width - 1 and i == length - 1:
				blank_space_counter += 1
				fen_string += str(blank_space_counter)
				
			else:
				blank_space_counter += 1
		
		
	if white_to_move:
		fen_string += " w"
	else:
		fen_string += " b"
	
	fen_string += " " + check_castle()
	fen_string += " " + check_en_passant()
	if three_check:
		# Fairy-Stockfish check-count field: <whiteRemaining>+<blackRemaining>.
		fen_string += " " + str(3 - white_checks) + "+" + str(3 - black_checks)
	fen_string += " " + check_half_moves()
	fen_string += " " + check_full_moves()
	
	#print("GENERATED FEN STRING")
	#print(fen_string)

	return fen_string
	
func check_castle():
	var castle_string = ""
	if !white_castled and not disable_white_castling and not flip_white_king_queen:
		if !white_king_moved:
			if !white_rook_kingside_moved:
				castle_string += "K"
			if !white_rook_queenside_moved:
				castle_string += "Q"
	if !black_castled and not disable_black_castling and not flip_black_king_queen:
		if !black_king_moved:
			if !black_rook_kingside_moved:
				castle_string += "k"
			if !black_rook_queenside_moved:
				castle_string += "q"

	if castle_string.length() == 0:
		return "-"
	else:
		return castle_string
	
# Swap the king-file (e) and queen-file (d) pieces on the requested side(s) of
# the starting position. Back ranks are fully populated at game start, so the
# d/e files are characters 3 and 4 of the rank string.
func _apply_starting_flips(fen):
	var ranks = fen.split("/")
	if ranks.size() == 8:
		if flip_black_king_queen:
			ranks[0] = _swap_de(ranks[0])  # rank 8 = black back rank
		if flip_white_king_queen:
			ranks[7] = _swap_de(ranks[7])  # rank 1 = white back rank
	return "/".join(ranks)

func _swap_de(rank):
	if rank.length() < 5:
		return rank
	return rank.substr(0, 3) + rank[4] + rank[3] + rank.substr(5)

func check_en_passant():
	if en_passant_square.length() == 0:
		return "-"
	else:
		return en_passant_square
	
func check_half_moves():
	return "0"
	
func check_full_moves():
	return str(black_move_counter)
	
	
func freeze_black_pieces():
	for black_piece in get_tree().get_nodes_in_group("black_pieces"):
		if !black_piece.picked_up:
			black_piece.get_node("CollisionShape2D").disabled = true
	
func freeze_white_pieces():
	for white_piece in get_tree().get_nodes_in_group("white_pieces"):
		if !white_piece.picked_up:
			white_piece.get_node("CollisionShape2D").disabled = true
			
func unfreeze_black_pieces():
	if !computer_opponent and (white_to_move == !player_white):
		unfreeze_buttons()
		
	for black_piece in get_tree().get_nodes_in_group("black_pieces"):
		if !black_piece.picked_up:
			black_piece.get_node("CollisionShape2D").disabled = false
	
func unfreeze_white_pieces():
	if !computer_opponent and (!white_to_move == player_white):
		unfreeze_buttons()
		
	for white_piece in get_tree().get_nodes_in_group("white_pieces"):
		if !white_piece.picked_up:
			white_piece.get_node("CollisionShape2D").disabled = false
			
func freeze_pieces():
	freeze_white_pieces()
	freeze_black_pieces()
	
func unfreeze_pieces():
	unfreeze_white_pieces()
	unfreeze_black_pieces()
	
func cancel_pickup(piece):
	# Called when a held piece is released somewhere that isn't a legal move
	# (including its own square). No move happened, so the position — and the
	# piece's legal_moves — are unchanged; we just restore the interaction state
	# so play can continue: snap the piece home, hide its move highlights, and
	# re-enable the side to move.
	piece.global_position = piece.default_location
	piece.activated = false
	piece.get_node("CollisionShape2D").disabled = false
	for move in piece.legal_moves:
		get_square(move).get_node("CollisionShape2D").disabled = true
		get_square(move).get_node("premove").visible = false
	if white_to_move:
		unfreeze_white_pieces()
	else:
		unfreeze_black_pieces()

func freeze_buttons():
	nav_buttons_enabled.emit(false)

func unfreeze_buttons():
	nav_buttons_enabled.emit(true)
	
func generate_board_from_fen_string(fen_string):
	
	
	var char_string = ""
	for single_array in board_array:
		for square in single_array:
			if len(fen_string) > 0:				
				if skip_for_loop > 1:
					skip_for_loop -= 1
					if skip_for_loop == 1:
						fen_string = fen_string.erase(0, 1)
					continue
				
				if fen_string[0] == "/":
					fen_string = fen_string.erase(0, 1)					
				
				
				if !fen_string[0].is_valid_int():
					char_string = fen_string[0]
					var new_piece = make_piece_from_string(char_string, square.chess_position)
					fen_string = fen_string.erase(0, 1)
					
					square.has_piece = true
					square.piece_type = new_piece.piece_type
					square.white = new_piece.white
				else:
					skip_for_loop = int(fen_string[0])
					# A count of exactly 1 is never caught by the "skip_for_loop > 1"
					# branch above (1 is not > 1), so the digit was never erased and
					# this re-read itself forever on every subsequent square -- the
					# single square it represents needs to resolve immediately, here,
					# not over follow-up iterations like counts >= 2 do.
					if skip_for_loop == 1:
						fen_string = fen_string.erase(0, 1)

	
func make_piece_from_string(piece_char, chess_position):
	var animation_string = ""
	
	var new_piece = piece_scene.instantiate()
	if piece_char == piece_char.to_lower():
		new_piece.white = false
		animation_string += "black_"
		new_piece.add_to_group("black_pieces")
	else:
		new_piece.white = true 
		animation_string += "white_"
		new_piece.add_to_group("white_pieces")
		
	new_piece.piece_type = Globals.get_piece_type_enum_from_string(piece_char)
	animation_string += Globals.give_piece_name_from_piece_type(new_piece.piece_type)
	new_piece.get_node("Sprite2D").play(animation_string)
	new_piece.chess_position = chess_position
	new_piece.origin = chess_position  # its slot in the run army (for permanent loss)
		
	new_piece.global_position = get_square(chess_position).global_position + get_square(chess_position).get_node("CollisionShape2D").shape.extents
	
	add_child(new_piece)
	
	return new_piece

func initiate_board(ranks, files):
	# letters_size/numbers_size are read externally by promotion_display.gd as
	# "the X/horizontal" and "the Y/vertical" pixel size of one square — NOT
	# literally tied to file-letters vs rank-numbers. The previous version
	# divided container.size.x by the RANK count and container.size.y by the
	# FILE count (backwards), which only ever looked right because ranks and
	# files were always both 8. Fixed to divide each axis by its own count.
	# Squares are added as children of this Node2D directly (not of
	# MarginContainer) at LOCAL positions, so centering them has to be done
	# here, not via MarginContainer's own anchors -- a Control's anchors
	# resolve against its nearest Control/CanvasItem ancestor's "parent area
	# size", which is not well-defined for a Control parented directly under
	# a plain Node2D (no Control, no CanvasLayer): anchoring it to 50%+-300
	# did NOT produce a box centered on the viewport, it landed near the
	# viewport's center/corner with the offsets not applied as expected.
	# MarginContainer is now just a fixed, unambiguous 600x600 box (see
	# board.tscn) used ONLY for its size; the real on-screen centering is
	# computed here directly from the viewport, which has no such ambiguity.
	var margin_rect = get_node("MarginContainer").get_rect()
	# get_viewport_rect() is a Control-only convenience method; Board is a
	# Node2D, so go through get_viewport() (available on any Node) instead.
	var board_origin = (get_viewport().get_visible_rect().size - margin_rect.size) / 2.0
	letters_size = int(margin_rect.size.x / files)
	numbers_size = int(margin_rect.size.y / ranks)

	var white_checker = false

	for i in range(ranks):

		if white_checker:
			white_checker = false
		else:
			white_checker = true

		board_array.append([])

		for j in range(files):

			var square = square_scene.instantiate()
			square.get_node("CollisionShape2D").shape.extents = Vector2(int(letters_size/2), int(numbers_size/2))
			square.get_node("CollisionShape2D").position = Vector2(letters_size/2, numbers_size/2)

			if white_checker:
				square.get_node("ColorRect").color = Color(1, 1, 1, 1)
				white_checker = false
				square.white = false
			else:
				square.get_node("ColorRect").color = Color(0.4706, 0.5804, 0.3294, 1)
				white_checker = true
				square.white = true


			square.get_node("ColorRect").custom_minimum_size = Vector2(letters_size, numbers_size)
			square.position = board_origin + Vector2(j * letters_size, i * numbers_size)
			square.chess_position = str(possible_letters[j]) + str(ranks - i)

			squares_dict[square.chess_position] = square
			add_child(square)
			board_array[i].append(square)
