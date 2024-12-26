extends Node2D

var white = true
var center = Vector2.ZERO
var chess_position = ""
var has_piece = false
var has_mouse = false
var piece_type = Globals.Piece_Type_ENUMs.NONE
var board

func _ready():
	get_node("premove").global_position = Vector2(position + (get_node("ColorRect").custom_minimum_size / 2))
	get_node("premove").modulate = Color(0, 0, 0, 1)
	
	board = get_parent()

func remove_piece():
	piece_type = Globals.Piece_Type_ENUMs.NONE
	has_piece = false
	
func delete_self():
	queue_free()

func get_center():
	return Vector2(global_position.x + get_node("CollisionShape2D").shape.extents.x/2, global_position.y + get_node("CollisionShape2D").shape.extents.y/2)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:	
	if has_piece and get_node("premove").visible and !white:
		get_node("premove").modulate = Color(1, 0, 0)
		get_node("premove").play("red")
	else:
		get_node("premove").modulate = Color(0, 0, 0, 1)
		get_node("premove").play("dot")
		
	if has_mouse and board.holding_piece and !Input.is_action_pressed("left_click"):
		if board.get_square(chess_position).has_piece:
			var chess_piece = board.get_piece(chess_position)
			chess_piece.delete_self()
			#get_parent().get_piece(chess_position).delete_self()
			
		board.held_piece.global_position = global_position + get_node("CollisionShape2D").shape.extents
		has_piece = true
		piece_type = board.held_piece.piece_type
		board.holding_piece = null
		white = board.held_piece.white
		
		board.held_piece.set_new_chess_position(chess_position, false)
		board.held_piece.activated = false
		
		board.freeze_white_pieces()
		
	get_node("Label").text = str(chess_position)
	get_node("Label2").text = str(has_piece)


func _on_mouse_entered() -> void:
	has_mouse = true


func _on_mouse_exited() -> void:
	has_mouse = false
