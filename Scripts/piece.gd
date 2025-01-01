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

var dead_position = null

var dead = false

func delete_self():
	dead_position = global_position
	dead = true
	global_position= Vector2(-200, -200)
	if self not in get_parent().captured_pieces:
		get_parent().captured_pieces.append(self)
	
var legal_moves = []

func add_legal_move(legal_move):
	if legal_move not in legal_moves:
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
		
		if board.white_to_move:
			board.unfreeze_white_pieces()
		else:
			board.unfreeze_black_pieces()
			
		global_position = default_location 
		
		for move in legal_moves:
			board.get_square(move).get_node("CollisionShape2D").disabled = true
			board.get_square(move).get_node("premove").visible = false
		
		

func _on_mouse_entered():
	has_mouse = true


func _on_mouse_exited():
	has_mouse = false
