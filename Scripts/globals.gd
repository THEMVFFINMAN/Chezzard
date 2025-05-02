extends Node

var crashed = false

enum Piece_Type_ENUMs {
	PAWN,
	BISHOP,
	KNIGHT, 
	ROOK,
	QUEEN,
	KING, 
	ARCHBISHOP,
	GIRAFFE,
	SHORTROOK,
	SHORTBISHOP,
	SHORTPAWN,
	MULE,
	CHANCELLOR,
	ROYALKNIGHT,
	ROYALBISHOP,
	ROYALROOK,
	MAN,
	KNIGHTRIDER,
	AMAZON,
	PRINCESS,
	WALL,
	EMPRESS,
	PRINCE,
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
		return "king"
	elif enum_value == Piece_Type_ENUMs.QUEEN:
		return "queen"
	elif enum_value == Piece_Type_ENUMs.ARCHBISHOP:
		return "archbishop"
	elif enum_value == Piece_Type_ENUMs.GIRAFFE:
		return "giraffe"
	elif enum_value == Piece_Type_ENUMs.SHORTROOK:
		return "shortrook"
	elif enum_value == Piece_Type_ENUMs.SHORTBISHOP:
		return "shortbishop"
	elif enum_value == Piece_Type_ENUMs.SHORTPAWN:
		return "shortpawn"
	elif enum_value == Piece_Type_ENUMs.MULE:
		return "mule"
	elif enum_value == Piece_Type_ENUMs.AMAZON:
		return "amazon" 
	elif enum_value == Piece_Type_ENUMs.CHANCELLOR:
		return "chancellor" 
	elif enum_value == Piece_Type_ENUMs.ROYALKNIGHT:
		return "royalknight" 
	elif enum_value == Piece_Type_ENUMs.PRINCESS:
		return "princess" 
	elif enum_value == Piece_Type_ENUMs.WALL:
		return "wall" 
	elif enum_value == Piece_Type_ENUMs.KNIGHTRIDER:
		return "knightrider" 
	elif enum_value == Piece_Type_ENUMs.MAN:
		return "man" 
	elif enum_value == Piece_Type_ENUMs.ROYALBISHOP:
		return "royalbishop" 
	elif enum_value == Piece_Type_ENUMs.ROYALROOK:
		return "royalrook" 
	elif enum_value == Piece_Type_ENUMs.EMPRESS:
		return "empress" 
	elif enum_value == Piece_Type_ENUMs.PRINCE:
		return "prince" 



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
	elif value == "g" or value == "G":
		return Piece_Type_ENUMs.GIRAFFE
	elif value == "s" or value == "S":
		return Piece_Type_ENUMs.SHORTROOK
	elif value == "t" or value == "T":
		return Piece_Type_ENUMs.SHORTBISHOP
	elif value == "m" or value == "M":
		return Piece_Type_ENUMs.MULE
	elif value == "z" or value == "Z":
		return Piece_Type_ENUMs.SHORTPAWN
	elif value == "e" or value == "E":
		return Piece_Type_ENUMs.CHANCELLOR 
	elif value == "x" or value == "X":
		return Piece_Type_ENUMs.AMAZON
	elif value == "c" or value == "C":
		return Piece_Type_ENUMs.ROYALKNIGHT
	elif value == "u" or value == "U":
		return Piece_Type_ENUMs.PRINCESS
	elif value == "w" or value == "W":
		return Piece_Type_ENUMs.WALL
	elif value == "d" or value == "D":
		return Piece_Type_ENUMs.KNIGHTRIDER
	elif value == "f" or value == "F":
		return Piece_Type_ENUMs.MAN
	elif value == "h" or value == "H":
		return Piece_Type_ENUMs.ROYALBISHOP
	elif value == "i" or value == "I":
		return Piece_Type_ENUMs.ROYALROOK
	elif value == "j" or value == "J":
		return Piece_Type_ENUMs.EMPRESS
	elif value == "l" or value == "L":
		return Piece_Type_ENUMs.PRINCE

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
		return_value =  "k"
	elif value == Piece_Type_ENUMs.QUEEN:
		return_value =  "q"
	elif value == Piece_Type_ENUMs.ARCHBISHOP:
		return_value =  "a"
	elif value == Piece_Type_ENUMs.GIRAFFE:
		return_value = "g"
	elif value == Piece_Type_ENUMs.SHORTROOK:
		return_value = "s"
	elif value == Piece_Type_ENUMs.SHORTBISHOP:
		return_value = "t"
	elif value == Piece_Type_ENUMs.MULE:
		return_value = "m"
	elif value == Piece_Type_ENUMs.SHORTPAWN:
		return_value = "z"
	elif value == Piece_Type_ENUMs.AMAZON:
		return_value = "x"
	elif value == Piece_Type_ENUMs.CHANCELLOR:
		return_value = "e"
	elif value == Piece_Type_ENUMs.ROYALKNIGHT:
		return_value = "c"
	elif value == Piece_Type_ENUMs.PRINCESS:
		return_value = "u"
	elif value == Piece_Type_ENUMs.WALL:
		return_value = "w"
	elif value == Piece_Type_ENUMs.KNIGHTRIDER:
		return_value = "d"
	elif value == Piece_Type_ENUMs.MAN:
		return_value = "f"
	elif value == Piece_Type_ENUMs.ROYALBISHOP:
		return_value = "h"
	elif value == Piece_Type_ENUMs.ROYALROOK:
		return_value = "i"
	elif value == Piece_Type_ENUMs.EMPRESS:
		return_value = "j"
	elif value == Piece_Type_ENUMs.PRINCE:
		return_value = "l"
	
	if white:
		return_value = return_value.capitalize()
		
	if return_value == "*":
		print("get fen string from eval error, returned *")
		
	return return_value
