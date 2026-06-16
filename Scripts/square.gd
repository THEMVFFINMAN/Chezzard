extends Node2D

var white = true
var center = Vector2.ZERO
var chess_position = ""
var has_piece = false
var has_mouse = false
var piece_type = Globals.Piece_Type_ENUMs.NONE
var board

var en_passant = false

func _ready():
	get_node("premove").global_position = Vector2(position + (get_node("ColorRect").custom_minimum_size / 2))
	get_node("premove").modulate = Color(0, 0, 0, 1)
	
	board = get_parent()
	# Hide leftover debug overlays.
	get_node("Label").visible = false
	get_node("Label2").visible = false

func remove_piece():
	piece_type = Globals.Piece_Type_ENUMs.NONE
	has_piece = false
	
func delete_self():
	queue_free()

func get_center():
	return Vector2(global_position.x + get_node("CollisionShape2D").shape.extents.x/2, global_position.y + get_node("CollisionShape2D").shape.extents.y/2)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:	
	
	
	get_node("NumberLabel").text = chess_position.to_upper()
	
	if (has_piece or (board.held_piece != null and board.held_piece.piece_type == Globals.Piece_Type_ENUMs.PAWN and board.en_passant_square == chess_position and board.en_passant_square[0]!= board.held_piece.chess_position[0])):
		get_node("premove").modulate = Color(1, 0, 0)
		get_node("premove").play("red")
	else:
		get_node("premove").modulate = Color(0, 0, 0, 1)
		get_node("premove").play("dot")
		
	if has_mouse and board.holding_piece and !Input.is_action_pressed("left_click"):
		board.held_piece.global_position = global_position + get_node("CollisionShape2D").shape.extents
		board.holding_piece = null
		
		board.move(board.held_piece.chess_position, chess_position)
		board.held_piece.activated = false
	
		


func _on_mouse_entered() -> void:
	has_mouse = true


func _on_mouse_exited() -> void:
	has_mouse = false
