extends Node

@onready var square_scene = preload("res://Scenes/square.tscn")
@onready var piece_scene = preload("res://Scenes/piece.tscn")
@onready var top_level = get_parent()

# Emitted when the Back/Forward buttons should be enabled/disabled. The
# BoardAuxiliaryContainer listens and toggles its own buttons, so this script
# never reaches across scenes into them.
signal nav_buttons_enabled(enabled)

var started = false

var place_holder_numbers = 0
var possible_letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
var holding_piece = false
var held_piece = null
var last_held_piece = null

var pending_promotion = {}

var letters_size = 0
var numbers_size = 0

#var generated_fen_string = "rnbqkbnr/pppppppp/8/8/4w3/8/ZZZZZZZZ/SMTULTMS"

var generated_fen_string = "rnbqkbnr/pppppppp/8/8/3w4/8/ZZZOZVZZ/SMTULTMS"

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

var moves = []
var redo_moves = []
var pending_legal_snapshot = {}
var undo_steps_remaining = 0
var redo_steps_remaining = 0


var captured_pieces = []
var captured_piece = false

var squares_dict = {}

var castle_info = {}

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
# Testing hook: assign materials to squares at startup, e.g. {"d1": "gold"}.
@export var test_materials := {}

# 3-check tracking (used only when three_check is on)
signal three_check_won(white_won)
var white_checks := 0
var black_checks := 0

# Emitted once when the side to move has no legal moves (checkmate/stalemate).
# board_container listens and shows the game-over popup.
signal game_over(result_text)
var game_over_emitted := false

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
	freeze_black_pieces()
	
func check_wall(move):
	if get_square(move).piece_type == Globals.Piece_Type_ENUMs.WALL:
		return true
		
	return false
	
	
func add_legal_moves_to_pieces(legal_moves):
	while legal_moves.size() > 0:
		var legal_move = legal_moves.pop_back()
		legal_move = legal_move.split(":")[0]
		
		var legal_move_array = get_array_of_individual_moves_from_fen_string(legal_move)
		
		var piece = get_piece(legal_move_array[0])
		
		if piece != null:
			piece.add_legal_move(legal_move_array[1])
			if legal_move_array.size() == 3:
				piece.add_promotion_piece(legal_move_array[2])
			


		
# Wall pieces (stone, iron*) go to the engine as "*" wall squares, so the engine
# never generates their moves. We add them game-side for the side to move (right
# after the engine's legal moves). They only step onto empty squares — never
# capturing.
func is_wall_piece(type):
	return type == Globals.Piece_Type_ENUMs.STONE or type == Globals.Piece_Type_ENUMs.IRONQUEEN

func add_wall_piece_moves():
	var group = "white_pieces" if white_to_move else "black_pieces"
	for piece in get_tree().get_nodes_in_group(group):
		if piece.dead:
			continue
		match piece.piece_type:
			Globals.Piece_Type_ENUMs.STONE:
				_add_king_step_moves(piece)
			Globals.Piece_Type_ENUMs.IRONQUEEN:
				_add_slider_moves(piece, true, true)  # orthogonal + diagonal = queen

# Sliding move generation to empty squares only (stops before any piece, since
# wall pieces can't capture). orthogonal = rook lines, diagonal = bishop lines.
func _add_slider_moves(piece, orthogonal, diagonal):
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
		while true:
			nf += d[0]
			nr += d[1]
			if nf < 0 or nf >= width or nr < 1 or nr > length:
				break
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

## Apply test materials (Inspector dict of square -> material name) after setup.
func _apply_test_materials():
	for sq in test_materials:
		var p = get_piece(sq)
		if p:
			p.apply_material(test_materials[sq])

# Called (deferred) when the engine's perft for the side to move was 0. Wall
# pieces (stone/iron) are added game-side, so re-check real legal moves before
# declaring the game over, then emit game_over with the popup text.
func check_game_over(in_check):
	if game_over_emitted:
		return
	if _side_to_move_has_move():
		return  # a stone/iron piece can still move -> not over
	var text
	if not in_check:
		text = "Draw"  # stalemate
	elif computer_opponent:
		text = "You Lose" if white_to_move else "You Win"
	else:
		text = "Black Wins" if white_to_move else "White Wins"
	game_over_emitted = true
	emit_signal("game_over", text)

func _side_to_move_has_move():
	var group = "white_pieces" if white_to_move else "black_pieces"
	for piece in get_tree().get_nodes_in_group(group):
		if not piece.dead and piece.legal_moves.size() > 0:
			return true
	return false


func conduct_castling_checks(piece_to_move, previous_chess_position, chess_position):
	# Reset for this move; only set below when a castle actually happens. (Resetting
	# here, not after the move() append, keeps redo from leaving a stale value.)
	castle_info = {}
	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.ROOK:
		if piece_to_move.white:
			if previous_chess_position[0] == "a":
				white_rook_queenside_moved = true
			elif previous_chess_position[0] == "h":
				white_rook_kingside_moved = true
		else:
			if previous_chess_position[0] == "a":
				black_rook_queenside_moved = true
			elif previous_chess_position[0] == "h":
				black_rook_kingside_moved = true
				
	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.KING:
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
				if chess_position[0] == "g" and !black_rook_kingside_moved:
					black_castled = true
					castle_rook("h8", "f8")
					castle_info = {"white": false, "kingside": true}

				if chess_position[0] == "c" and !black_rook_queenside_moved:
					black_castled = true
					castle_rook("a8", "d8")
					castle_info = {"white": false, "kingside": false}
					

	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.ROOK:
		if chess_position[0] == "a":
			if piece_to_move.white:
				white_rook_queenside_moved = true
			else:
				black_rook_queenside_moved = true
				
		if chess_position[0] == "h":
			if piece_to_move.white:
				white_rook_kingside_moved = true
			else:
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
	# Record the new tally on the move that delivered the check, so undo/redo can
	# restore it exactly.
	if moves.size() > 0:
		moves[moves.size() - 1]["checks_after"] = [white_checks, black_checks]
	if white_checks >= 3:
		three_check_won.emit(true)
	elif black_checks >= 3:
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
		
	var previous_chess_square = get_square(previous_chess_position)
	var rook_king_movement = []
	var second_square = get_square(chess_position)
	var en_passant_undo_check = check_en_passant()
	
	if second_square.has_piece:
		get_piece(chess_position).delete_self()
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
	
	if computer_opponent and (white_to_move == !player_white):
		var tween = get_tree().create_tween()
		tween.tween_property(piece_to_move, "global_position", second_square.global_position + second_square.get_node("CollisionShape2D").shape.extents, .1)
		tween.tween_callback(black_moved_piece)
		
	if piece_to_move.white:
		white_to_move = false
		freeze_white_pieces()
		if !computer_opponent or !is_computer_turn():
			unfreeze_black_pieces()
	else:
		white_to_move = true
		freeze_black_pieces()
		if !computer_opponent or !is_computer_turn():
			unfreeze_white_pieces()
	
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
		"checks_before": [white_checks, black_checks],
		"checks_after": [white_checks, black_checks],  # updated by register_check() if this move checks
	}
	moves.append(record)

	captured_piece = false
	set_previous_square(previous_chess_position)
	
	for move in piece_to_move.legal_moves:
		get_square(move).get_node("CollisionShape2D").disabled = true
		get_square(move).get_node("premove").visible = false
		
	# A pawn reaching the last rank must promote. Defer the engine handoff until a
	# piece is chosen — a pawn sitting on the last rank is an illegal position the
	# engine would reject.
	if (piece_to_move.piece_type == Globals.Piece_Type_ENUMs.PAWN or piece_to_move.piece_type == Globals.Piece_Type_ENUMs.SHORTPAWN) and _is_promotion_rank(chess_position, piece_to_move.white):
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
	

			
			
			
func _finish_move(prev, cur):
	# Engine handoff + legal-move refresh for the next turn. Split out of move()
	# so promotion can run it AFTER a piece is chosen.
	send_move(prev, cur)
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
		Globals.Piece_Type_ENUMs.KING, Globals.Piece_Type_ENUMs.PRINCE]
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
		# Step forward a full move pair (or fewer if there's less to redo).
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
	
	
	previous_square.piece_type = redo_piece.piece_type

			
			
	# Re-apply castling/king-rook state the way move() does. This re-performs the
	# rook move on a castle — the old code restored the PRE-move flags here, so
	# the rook never re-castled — and sets the correct post-move flags.
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
		# Always step back a full move pair (or fewer if the history is shorter),
		# no matter which colour the human plays.
		undo_steps_remaining = 2
		undo_individual_move()
	
func undo_individual_move():
	if moves.size() == 0:
		undo_finalize()
		return

	var record = moves.pop_back()
	redo_moves.append(record)
	

	var undo_piece = record["piece"]
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
		if castle["white"]:
			if castle["kingside"]:
				undo_castle("h1", "f1")
			else:
				undo_castle("a1", "d1")
		else:
			if castle["kingside"]:
				undo_castle("h8", "f8")
			else:
				undo_castle("a8", "d8")
			
			
			
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
	top_level.perft()
	unfreeze_buttons()
	unfreeze_white_pieces()

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
	unfreeze_white_pieces()

func undo_castle(rook_position, old_rook_position):
	var rook = get_piece(old_rook_position)
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
	
func generate_fen_string():
	var fen_string = ""
	blank_space_counter = 0
	for i in range(length):
		if len(fen_string) > 0:
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
				if is_wall_piece(square.piece_type):
					fen_string += "*"  # stone/iron -> engine wall square (uncapturable, blocks)
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
		
	new_piece.global_position = get_square(chess_position).global_position + get_square(chess_position).get_node("CollisionShape2D").shape.extents
	
	add_child(new_piece)
	
	return new_piece

func initiate_board(letters, numbers): 
	letters_size = int(get_node("MarginContainer").get_rect().size.x / letters)
	numbers_size = int(get_node("MarginContainer").get_rect().size.y / numbers)
	
	var white_checker = false
	
	for i in range(letters):
		
		if white_checker:
			white_checker = false
		else:
			white_checker = true
		
		board_array.append([])		
		
		for j in range(numbers):			
			
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
			square.position = Vector2(j * numbers_size, i * letters_size)
			square.chess_position = str(possible_letters[place_holder_numbers % letters]) + str(numbers - i)
			
			place_holder_numbers = place_holder_numbers + 1
			squares_dict[square.chess_position] = square
			add_child(square)
			board_array[i].append(square)

func _on_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		
		get_node("Promotion_display").global_position = Vector2(300, 300)
		get_node("Promotion_display").display("qnbr")
		get_node("Promotion_display").show()

	else:
		get_node("Promotion_display").hide()
		
		for child in get_node("Promotion_display/MarginContainer/GridContainer").get_children():
			child.queue_free()
