extends StaticBody2D

var white = true
var piece_type
var has_mouse = false
var chess_position = ""
var picked_up = false

var default_location = Vector2.ZERO

var previous_chess_position = ""

var SPEED = 50

var activated = false

var board

func delete_self():
	queue_free()
	
var legal_moves = []

func add_legal_move(legal_move):
	legal_moves.append(legal_move)
	

func initialize(is_white, piece_sprite, chess_location, _piece_type, _global_position):
	white = is_white
	piece_type = _piece_type
	chess_position = chess_location
	get_node("Sprite2D").play(piece_sprite)
	global_position = _global_position
	if is_white:
		add_to_group("white_pieces")
	else:
		add_to_group("black_pieces")

func _ready():
	board = get_parent()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	get_node("Label").text = str(chess_position)
	get_node("Label2").text = str(legal_moves)
	

	
	if has_mouse and Input.is_action_pressed("left_click") and !picked_up:
		
		for move in legal_moves:
			board.get_square(move).get_node("CollisionShape2D").disabled = false
			board.get_square(move).get_node("premove").visible = true
			
		picked_up = true
		activated = true
		
		default_location = global_position
		
		z_index = 15
		
		board.held_piece = self
		board.freeze_pieces()
		board.holding_piece = true
		
	if picked_up:
		if board.holding_piece:
			global_position = get_global_mouse_position()
		if !Input.is_action_pressed("left_click"):
			picked_up = false
			z_index = 5
			#board.unfreeze_white_pieces()
			board.holding_piece = false
			board.held_piece = null
			get_node("CollisionShape2D").disabled = true
			
	if !picked_up and activated and !Input.is_action_pressed("left_click"):
		activated = false
		board.holding_piece = false
		board.held_piece = null
		board.unfreeze_white_pieces()
		global_position = default_location 
		
		for move in legal_moves:
			board.get_square(move).get_node("CollisionShape2D").disabled = true
			board.get_square(move).get_node("premove").visible = false
		
		

func _on_mouse_entered():
	has_mouse = true
	
func set_new_chess_position(_chess_position, rook_castle):

	previous_chess_position = chess_position
	chess_position = _chess_position
	
	if piece_type == Globals.Piece_Type_ENUMs.KING:
		if white:
			board.white_king_moved = true
			
			if previous_chess_position[0] == "e":
				if _chess_position[0] == "g" and !board.white_rook_kingside_moved:
					board.white_castled = true
					
					var rook_to_move = board.get_piece("h1")
					rook_to_move.set_new_chess_position("f1", true)
					
					var rook_to_move_square = board.get_square("f1")
					
					var tween = get_tree().create_tween()
					tween.tween_property(rook_to_move, "global_position", rook_to_move_square.global_position + rook_to_move_square.get_node("CollisionShape2D").shape.extents, .05)
					print("ROOK TO MOVE CHESS POSITION  ", rook_to_move.chess_position)
					
					rook_to_move_square.has_piece = true
					rook_to_move_square.piece_type = rook_to_move.piece_type
					rook_to_move_square.white = rook_to_move.white
					
				if _chess_position[0] == "c" and !board.white_rook_queenside_moved:
					board.white_castled = true
					
					var rook_to_move = board.get_piece("a1")
					rook_to_move.set_new_chess_position("d1", true)
					
					var rook_to_move_square = board.get_square("d1")
					
					var tween = get_tree().create_tween()
					tween.tween_property(rook_to_move, "global_position", rook_to_move_square.global_position + rook_to_move_square.get_node("CollisionShape2D").shape.extents, .05)
					print("ROOK TO MOVE CHESS POSITION  ", rook_to_move.chess_position)
					
					rook_to_move_square.has_piece = true
					rook_to_move_square.piece_type = rook_to_move.piece_type
					rook_to_move_square.white = rook_to_move.white
		else:
			board.black_king_moved = true

	if piece_type == Globals.Piece_Type_ENUMs.ROOK:
		if _chess_position[0] == "a":
			if white:
				board.white_rook_queenside_moved = true
			else:
				board.black_rook_queenside_moved = true
				
		if _chess_position[0] == "h":
			if white:
				board.white_rook_kingside_moved = true
			else:
				board.black_rook_kingside_moved = true
	
	if piece_type == Globals.Piece_Type_ENUMs.PAWN:
		var pawn_pos_1 = int(previous_chess_position.substr(1, previous_chess_position.length() - 1))
		var pawn_pos_2 = int(_chess_position.substr(1, _chess_position.length() - 1))
		
		# This checks if the pawn went forward twice to set the en passant square

			
		# This checks if the pawn moved en passant and to delete the old piece
		if previous_chess_position[0] != _chess_position[0] and _chess_position == board.en_passant_square:
			var captured_piece = board.get_piece(board.en_passant_pawn_location)
			var captured_square = board.get_square(board.en_passant_pawn_location)
			
			captured_piece.delete_self()
			captured_square.has_piece = false
			
		if abs(pawn_pos_2 - pawn_pos_1) == 2:
			var en_passant_square = previous_chess_position[0]
			if white:
				en_passant_square += str(pawn_pos_2 - 1)
			else:
				en_passant_square += str(pawn_pos_2 + 1)
				
			board.en_passant_square = en_passant_square
			board.en_passant_pawn_location = _chess_position
			print("SET EN PASSANT SQUARE")
			print(en_passant_square)
		else:
			board.en_passant_square = ""
			board.en_passant_pawn_location = ""
	else:
		board.en_passant_square = ""
		board.en_passant_pawn_location = ""
		
	
	print(previous_chess_position)
	print(_chess_position)
	
	
	board.set_previous_square(previous_chess_position)
	
	for move in legal_moves:
		board.get_square(move).get_node("CollisionShape2D").disabled = true
		board.get_square(move).get_node("premove").visible = false
		
	if !rook_castle:
		board.send_move(previous_chess_position, chess_position, white, piece_type)

func _on_mouse_exited():
	has_mouse = false
