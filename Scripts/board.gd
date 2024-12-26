extends Node

@onready var square_scene = preload("res://Scenes/square.tscn")
@onready var piece_scene = preload("res://Scenes/piece.tscn")
@onready var top_level = get_parent()

var started = false

var place_holder_numbers = 0
var possible_letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm']
var holding_piece = false
var held_piece = null

var generated_fen_string = "rnbqkgnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKGNR"

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

func _ready():
	black_move_timer = $black_move_timer
	initiate_board(length, width)
	#initialize_weird_pieces()
	generate_board_from_fen_string(generated_fen_string)
	#top_level.send_
	freeze_black_pieces()
	
	regex = RegEx.new()
	regex.compile(r"([a-zA-Z]\d+)")
	
func add_legal_moves_to_white_pieces(legal_moves):
	while legal_moves.size() > 0:
		var legal_move = legal_moves.pop_back()
		legal_move = legal_move.split(":")[0]
		
		var legal_move_array = get_array_of_individual_moves_from_fen_string(legal_move)
		
		var piece = get_piece(legal_move_array[0])

		piece.add_legal_move(legal_move_array[1])	
	
func play_black_move(fen_move):	
	var results = get_array_of_individual_moves_from_fen_string(fen_move)
	var first_location = results[0]
	var second_location = results[1]

	var previous_square = get_square(first_location)
	var second_square = get_square(second_location)
	var piece_to_move = get_piece(first_location)
	
	if second_square.has_piece:
		get_piece(second_location).delete_self()
	
	
	var tween = get_tree().create_tween()
	tween.tween_property(piece_to_move, "global_position", second_square.global_position + second_square.get_node("CollisionShape2D").shape.extents, .1)
	tween.tween_callback(black_moved_piece)
	
	if previous_square.has_piece:
		previous_square.remove_piece()
		
	if !black_castled and !black_king_moved:
		if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.KING:
			print("CHECK IT")
			if first_location[0] == "e":
				if second_location[0] == "c" and !black_rook_queenside_moved:
					var queenside_rook = get_piece("a8")
					var queenside_rook_location = get_square("d8")
					var queenside_rook_previous_location = get_square("a8")
					
					tween.tween_property(queenside_rook, "global_position", queenside_rook_location.global_position + queenside_rook_location.get_node("CollisionShape2D").shape.extents, .1)
					queenside_rook_location.white = queenside_rook.white
					queenside_rook_previous_location.has_piece = false
					queenside_rook_location.has_piece = true
					queenside_rook_location.piece_type = queenside_rook.piece_type
					queenside_rook.chess_position = "d8"
					
					black_castled = true
					black_king_moved = true 
					black_rook_queenside_moved = true
					
				if second_location[0] == "g" and !black_rook_kingside_moved:
					var kingside_rook = get_piece("h8")
					var kingside_rook_location = get_square("f8")
					var kingside_rook_previous_location = get_square("h8")
					
					tween.tween_property(kingside_rook, "global_position", kingside_rook_location.global_position + kingside_rook_location.get_node("CollisionShape2D").shape.extents, .1)
					kingside_rook_location.white = kingside_rook.white
					kingside_rook_previous_location.has_piece = false
					kingside_rook_location.has_piece = true
					kingside_rook_location.piece_type = kingside_rook.piece_type
					kingside_rook.chess_position = "f8"
					
					black_castled = true
					black_king_moved = true 
					black_rook_kingside_moved = true
					
					
					
		
	second_square.has_piece = true
	second_square.piece_type = piece_to_move.piece_type
	second_square.white = piece_to_move.white
	
	piece_to_move.chess_position = second_location

	white_to_move = true
	
			
	if piece_to_move.piece_type == Globals.Piece_Type_ENUMs.PAWN:
		var pawn_pos_1 = int(first_location.substr(1, first_location.length() - 1))
		var pawn_pos_2 = int(second_location.substr(1, second_location.length() - 1))
		
		# This checks if the pawn went forward twice to set the en passant square
		if abs(pawn_pos_2 - pawn_pos_1) == 2:
			var _en_passant_square = first_location[0]
			if piece_to_move.white:
				_en_passant_square += str(pawn_pos_2 - 1)
			else:
				_en_passant_square += str(pawn_pos_2 + 1)
				
			en_passant_square = _en_passant_square
			en_passant_pawn_location = second_location
			print("SET BLACK EN PASSANT SQUARE")
			print(_en_passant_square)
		else:
			en_passant_square = ""
			en_passant_pawn_location = ""
			
		# This checks if the pawn moved en passant and to delete the old piece
		if first_location[0] != second_location[0] and second_location == en_passant_square:
			var captured_piece = get_piece(en_passant_pawn_location)
			var captured_square = get_square(en_passant_pawn_location)
			
			captured_piece.delete_self()
			captured_square.has_piece = false
	else:
		en_passant_square = ""
		en_passant_pawn_location = ""
	
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.send_to_stockfish("eval")
	#top_level.send_to_stockfish("fen")
	
	top_level.perft()
	
	black_move_counter += 1
	
	for piece in get_tree().get_nodes_in_group("pieces"):
		piece.legal_moves = []

	
	
func black_moved_piece():
	white_to_move = true
	unfreeze_white_pieces()
	
func get_array_of_individual_moves_from_fen_string(fen_move):
	var result = []
	var matcher = regex.search(fen_move)
	
	while matcher:
		result.append(matcher.get_string(0))
		matcher = regex.search(fen_move, matcher.get_end())
	
	return result

	
func send_move(previous_chess_position, chess_position, white, piece_type):
	if chess_position == previous_chess_position:
		return

	white_to_move = false
		
	top_level.send_to_stockfish("position fen " + generate_fen_string())
	top_level.send_to_stockfish("go depth 10")
	top_level.send_to_stockfish("eval")
	
	freeze_white_pieces()

	
func get_square(chess_location):
	chess_location = chess_location.replace(" ", "")
	for square in get_tree().get_nodes_in_group("squares"):
		if chess_location in square.chess_position:
			return square
			
func get_piece(chess_location):
	chess_location = chess_location.replace(" ", "")
	
	for piece in get_tree().get_nodes_in_group("pieces"):

		if chess_location in piece.chess_position:
			return piece
			
func set_previous_square(chess_position):
	get_square(chess_position).has_piece = false
	get_square(chess_position).piece_type = Globals.Piece_Type_ENUMs.NONE
	
func generate_fen_string():
	print
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
		fen_string += " w "
	else:
		fen_string += " b "
	
	fen_string += " " + check_castle()
	fen_string += " " + check_en_passant() 
	fen_string += " " + check_half_moves()
	fen_string += " " + check_full_moves()
	
	print("GENERATED FEN STRING")
	print(fen_string)

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
		print("EN PASSANT SQUARE: ", en_passant_square)
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
	for black_piece in get_tree().get_nodes_in_group("black_pieces"):
		if !black_piece.picked_up:
			black_piece.get_node("CollisionShape2D").disabled = false
	
func unfreeze_white_pieces():
	for white_piece in get_tree().get_nodes_in_group("white_pieces"):
		if !white_piece.picked_up:
			white_piece.get_node("CollisionShape2D").disabled = false
			
func freeze_pieces():
	freeze_white_pieces()
	freeze_black_pieces()
	
func unfreeze_pieces():
	unfreeze_white_pieces()
	unfreeze_black_pieces()
	
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
	var letters_size = int(get_node("MarginContainer").get_rect().size.x / letters)
	var numbers_size = int(get_node("MarginContainer").get_rect().size.y / numbers)
	
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
			
			add_child(square)
			board_array[i].append(square)
