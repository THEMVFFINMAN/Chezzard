extends Node

enum Piece_Type_ENUMs {
	PAWN,
	BISHOP,
	KNIGHT,
	ROOK,
	QUEEN,
	KING, 
	ARCHBISHOP,
	CAMEL,
	GIRAFFE,
	NONE
}



func give_piece_name_from_piece_type(enum_value):
	if enum_value == Piece_Type_ENUMs.PAWN:
		return "pawn"
	elif enum_value == Piece_Type_ENUMs.BISHOP:
		return "bishop"
	elif enum_value == Piece_Type_ENUMs.KNIGHT:
		return "knight"
	elif enum_value == Piece_Type_ENUMs.ROOK:
		return "rook"
	elif enum_value == Piece_Type_ENUMs.KING:
		return "queen"
	elif enum_value == Piece_Type_ENUMs.QUEEN:
		return "king"
	elif enum_value == Piece_Type_ENUMs.ARCHBISHOP:
		return "archbishop"
	elif enum_value == Piece_Type_ENUMs.CAMEL:
		return "camel"
	elif enum_value == Piece_Type_ENUMs.GIRAFFE:
		return "giraffe"



func get_piece_type_enum_from_string(value):
	if value == "p" or value == "P":
		return Piece_Type_ENUMs.PAWN
	elif value == "b" or value == "B":
		return Piece_Type_ENUMs.BISHOP
	elif value == "n" or value == "N":
		return Piece_Type_ENUMs.KNIGHT
	elif value == "r" or value == "R":
		return Piece_Type_ENUMs.ROOK
	elif value == "k" or value == "K":
		return Piece_Type_ENUMs.KING
	elif value == "q" or value == "Q":
		return Piece_Type_ENUMs.QUEEN
	elif value == "a" or value == "A":
		return Piece_Type_ENUMs.ARCHBISHOP
	elif value == "c" or value == "C":
		return Piece_Type_ENUMs.CAMEL
	elif value == "g" or value == "G":
		return Piece_Type_ENUMs.GIRAFFE

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func get_fen_string_from_enum(value, white):
	
	var return_value = "*"
	
	if value == Piece_Type_ENUMs.PAWN:
		return_value =  "p"
	elif value == Piece_Type_ENUMs.BISHOP:
		return_value =  "b"
	elif value == Piece_Type_ENUMs.KNIGHT :
		return_value =  "n"
	elif value == Piece_Type_ENUMs.ROOK:
		return_value =  "r"
	elif value == Piece_Type_ENUMs.KING :
		return_value =  "q"
	elif value == Piece_Type_ENUMs.QUEEN:
		return_value =  "k"
	elif value == Piece_Type_ENUMs.ARCHBISHOP:
		return_value =  "a"
	elif value == Piece_Type_ENUMs.CAMEL:
		return_value = "c"
	elif value == Piece_Type_ENUMs.GIRAFFE:
		return_value = "g"
	
	if white:
		return_value = return_value.capitalize()
		
	return return_value
