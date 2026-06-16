extends Node2D
@onready var square_promo_scene = preload("res://Scenes/square_promotion.tscn")
@onready var piece_promo_scene = preload("res://Scenes/piece_promotion.tscn")
@onready var Board = get_parent()

var i = 0

# piece_types: Array of Globals.Piece_Type_ENUMs the pawn may promote to.
func display(piece_types, is_white):
	clear()
	for piece_type in piece_types:
		var square = add_promo_square()
		add_promo_piece(piece_type, is_white, square)
	i = 0

func clear():
	for child in get_node("MarginContainer/GridContainer").get_children():
		child.queue_free()
	i = 0

func add_promo_piece(piece_type, is_white, square):
	var new_piece = piece_promo_scene.instantiate()
	new_piece.name = "piece"
	new_piece.piece_type = piece_type
	var prefix = "white_" if is_white else "black_"
	new_piece.get_node("Sprite2D").play(prefix + Globals.give_piece_name_from_piece_type(piece_type))
	new_piece.global_position = square.global_position + square.get_node("CollisionShape2D").shape.extents
	square.add_child(new_piece)
	new_piece.z_index = 21

func add_promo_square():
	var square = square_promo_scene.instantiate()

	square.get_node("CollisionShape2D").shape.extents = Vector2(int(Board.letters_size / 2), int(Board.numbers_size / 2))
	square.get_node("ColorRect").color = Color(0.4706, 0.5804, 0.3294, 1)
	square.get_node("ColorRect").custom_minimum_size = Vector2(Board.letters_size, Board.numbers_size)

	square.get_node("CollisionShape2D").position = square.get_node("ColorRect").position + square.get_node("CollisionShape2D").shape.size / 2

	square.position.x += (i * Board.letters_size)

	if i % 2 != 0:
		square.get_node("ColorRect").color = Color(1, 1, 1, 1)
	i += 1

	get_node("MarginContainer/GridContainer").add_child(square)
	return square
