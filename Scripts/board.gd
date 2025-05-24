extends Node

@onready var square_scene = preload("res://Scenes/square.tscn")
@onready var piece_scene = preload("res://Scenes/piece.tscn")
@onready var top_level = get_parent()

var started = false

var place_holder_numbers = 0
var possible_letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm']
var holding_piece = false
var held_piece = null
var last_held_piece = null

var promotion_pieces = "qnbr"

var letters_size = 0
var numbers_size = 0

#var generated_fen_string = "rnbqkbnr/pppppppp/8/8/4w3/8/ZZZZZZZZ/SMTULTMS"

var generated_fen_string = "rnbqkbnr/pppppppp/7P/8/8/8/PPPPPPPP/SMTULTMS"

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


var captured_pieces = []
var captured_piece = false

var squares_dict = {}

var castle_move_string = ""

var computer_opponent
var player_white

func _ready():
	computer_opponent = get_parent().computer_opponent
	player_white = get_parent().player_white
	black_move_timer = $black_move_timer
	initiate_board(length, width)
	#initialize_weird_pieces()
	generate_board_from_fen_string(generated_fen_string)

	#top_level.send_
	
	freeze_black_pieces()
	
	regex = RegEx.new()
	regex.compile(r"([a-zA-Z]\d+)")
	
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
			


		
func conduct_castling_checks(piece_to_move, previous_chess_position, chess_position):
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
					castle_move_string = "wK"
					
					
				if chess_position[0] == "c" and !white_rook_queenside_moved:
					white_castled = true
					castle_rook("a1", "d1")
					castle_move_string = "wQ"
					
		else:
			black_king_moved = true
			
			if previous_chess_position[0] == "e":
				if chess_position[0] == "g" and !black_rook_kingside_moved:
					black_castled = true
					castle_rook("h8", "f8")
					castle_move_string = "bK"

				if chess_position[0] == "c" and !black_rook_queenside_moved:
					black_castled = true
					castle_rook("a8", "d8")
					castle_move_string = "bQ"
					

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
		
func move(previous_chess_position, chess_position):
	redo_moves.clear()
	
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
	
	moves.append([piece_to_move, previous_chess_square, get_square(chess_position), previous_chess_square.global_position + previous_chess_square.get_node("CollisionShape2D").shape.extents, \
	piece_to_move.legal_moves, previous_chess_position, chess_position, captured_piece, castle_move_string, rook_king_movement, \
	en_passant_undo_check])

	castle_move_string = ""
	captured_piece = false
	set_previous_square(previous_chess_position)
	
	for move in piece_to_move.legal_moves:
		get_square(move).get_node("CollisionShape2D").disabled = true
		get_square(move).get_node("premove").visible = false
		
	send_move(previous_chess_position, chess_position)
	
		
	for piece in get_tree().get_nodes_in_group("pieces"):
		piece.legal_moves = []
		
	
	print("DEBUGGING 2")
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.perft()
	
	if piece_to_move.select_promotion_piece:
		freeze_buttons()
		freeze_pieces()
		get_node("Promotion_display").global_position = piece_to_move.global_position
		
		get_node("Promotion_display").display(promotion_pieces)
		#var subtraction_amount = get_node("Promotion_display/MarginContainer/GridContainer").get_rect().size.x * promotion_pieces.length() + get_node("Promotion_display/MarginContainer/GridContainer").get_rect().size.x
		#print(subtraction_amount)
		#get_node("Promotion_display").global_position.x -= subtraction_amount
		get_node("Promotion_display").show()
		print(piece_to_move.promotion_piece)
	

			
			
			
func castle_rook(rook_position, new_rook_position):	
	var rook_to_move = get_piece(rook_position)
	var rook_to_move_square = get_square(new_rook_position)
	var old_rook_square = get_square(rook_position)
	
	rook_to_move.chess_position = new_rook_position
	old_rook_square.has_piece = false
	old_rook_square.piece_type = Globals.Piece_Type_ENUMs.NONE
					
	var tween = get_tree().create_tween()
	tween.tween_property(rook_to_move, "global_position", rook_to_move_square.global_position + rook_to_move_square.get_node("CollisionShape2D").shape.extents, .05)
	print("ROOK TO MOVE CHESS POSITION  ", rook_to_move.chess_position)
	
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
		redo_individual_move()
		

		
func redo_individual_move():
	if redo_moves.size() == 0:
		return
	var redo_array = redo_moves.pop_back()
	moves.append(redo_array)
	

	var redo_piece = redo_array[0]
	var previous_square = redo_array[1]
	var current_square = redo_array[2]
	var previous_global_position = redo_array[3]
	
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

			
			
	if redo_piece.white:
		white_rook_kingside_moved = redo_array[9][0]
		white_rook_queenside_moved = redo_array[9][1]
		white_king_moved = redo_array[9][2]
	else:
		black_rook_kingside_moved = redo_array[9][0]
		black_rook_queenside_moved = redo_array[9][1]
		black_king_moved = redo_array[9][2]
	
	
	
	redo_piece.legal_moves = redo_array[4]
	
	if !redo_piece.white:
		var tween = get_tree().create_tween()
		tween.tween_property(redo_piece, "global_position", current_square.global_position + current_square.get_node("CollisionShape2D").shape.extents, .1)
		tween.tween_callback(undo_done)
	else:
		var tween2 = get_tree().create_tween()
		tween2.tween_property(redo_piece, "global_position", current_square.global_position + current_square.get_node("CollisionShape2D").shape.extents, .1)
		tween2.tween_callback(redo_individual_move)

	
func undo():
	if moves.size() > 0:
		freeze_buttons()
		freeze_pieces()
		black_move_counter -= 1
		undo_individual_move()
	
func undo_individual_move():

	var undo_array = moves.pop_back()
	redo_moves.append(undo_array)
	

	var undo_piece = undo_array[0]
	var previous_square = undo_array[1]
	var current_square = undo_array[2]
	var previous_global_position = undo_array[3]
	
	current_square.has_piece = false
	
	if undo_array[7]:
		if captured_pieces.size() > 0:
			var captured_piece = captured_pieces.pop_back()
			
			captured_piece.global_position = captured_piece.dead_position
			captured_piece.dead = false
			var captured_square = get_square(captured_piece.chess_position)
			captured_square.has_piece = true
			captured_square.piece_type = captured_piece.piece_type
			captured_square.white = captured_piece.white
	
	previous_square.piece_type = undo_piece.piece_type
	
	if "w" in undo_array[8]:
		if "Q" in undo_array[8]:
			undo_castle("a1", "d1")
		else:
			undo_castle("h1", "f1")
			
	if "b" in undo_array[8]:
		if "Q" in undo_array[8]:
			undo_castle("a8", "d8")
		else:
			undo_castle("h8", "f8")
			
			
	if undo_piece.white:
		white_rook_kingside_moved = undo_array[9][0]
		white_rook_queenside_moved = undo_array[9][1]
		white_king_moved = undo_array[9][2]
	else:
		black_rook_kingside_moved = undo_array[9][0]
		black_rook_queenside_moved = undo_array[9][1]
		black_king_moved = undo_array[9][2]
	
	
	previous_square.has_piece = true
	previous_square.white = undo_piece.white
	undo_piece.legal_moves = undo_array[4]
	undo_piece.chess_position = undo_array[5]
	
	if "-" not in undo_array[10]:
		en_passant_square = undo_array[10]
	
	if undo_piece.white:
		var tween = get_tree().create_tween()
		tween.tween_property(undo_piece, "global_position", previous_global_position, .1)
		tween.tween_callback(undo_done)
	else:
		var tween2 = get_tree().create_tween()
		tween2.tween_property(undo_piece, "global_position", previous_global_position, .1)
		tween2.tween_callback(undo_individual_move)
		

	
func undo_done():
	
	for piece in get_tree().get_nodes_in_group("pieces"):
		piece.legal_moves =  []
		
	print("finished_undo")
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.perft()
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
	fen_string += " " + check_half_moves()
	fen_string += " " + check_full_moves()
	
	#print("GENERATED FEN STRING")
	#print(fen_string)

	return fen_string
	
func check_castle():
	var castle_string = ""
	if !white_castled:
		if !white_king_moved:
			if !white_rook_kingside_moved:
				castle_string += "K"
			if !white_rook_queenside_moved:
				castle_string += "Q"
	if !black_castled:
		if !black_king_moved:
			if !black_rook_kingside_moved:
				castle_string += "k"
			if !black_rook_queenside_moved:
				castle_string += "q"

	if castle_string.length() == 0:
		return "-"
	else:
		return castle_string
	
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
	
func freeze_buttons():
	get_parent().get_parent().get_node("BoardAuxiliaryContainer/HBoxContainer/Redo").disabled = true
	get_parent().get_parent().get_node("BoardAuxiliaryContainer/HBoxContainer/Undo").disabled = true
	
func unfreeze_buttons():
	get_parent().get_parent().get_node("BoardAuxiliaryContainer/HBoxContainer/Redo").disabled = false
	get_parent().get_parent().get_node("BoardAuxiliaryContainer/HBoxContainer/Undo").disabled = false
	
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
	
	get_parent().board_size = Vector2(letters_size * letters, numbers_size * numbers)
	get_parent().get_parent().initiate_board_auxiliary()
	
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
			square.get_node("Label").text = square.chess_position
			
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
