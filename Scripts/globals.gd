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
	STONE,
	IRONQUEEN,
	NONE
}

# Single source of truth for every piece: its display name and its (lower-case)
# FEN character. The reverse lookup (char -> enum) is derived from this in
# _ready(), so the mappings can never drift out of sync.
const PIECE_INFO = {
	Piece_Type_ENUMs.PAWN:        {"name": "pawn",        "fen": "p"},
	Piece_Type_ENUMs.BISHOP:      {"name": "bishop",      "fen": "b"},
	Piece_Type_ENUMs.KNIGHT:      {"name": "knight",      "fen": "n"},
	Piece_Type_ENUMs.ROOK:        {"name": "rook",        "fen": "r"},
	Piece_Type_ENUMs.QUEEN:       {"name": "queen",       "fen": "q"},
	Piece_Type_ENUMs.KING:        {"name": "king",        "fen": "k"},
	Piece_Type_ENUMs.ARCHBISHOP:  {"name": "archbishop",  "fen": "a"},
	Piece_Type_ENUMs.GIRAFFE:     {"name": "giraffe",     "fen": "g"},
	Piece_Type_ENUMs.SHORTROOK:   {"name": "shortrook",   "fen": "s"},
	Piece_Type_ENUMs.SHORTBISHOP: {"name": "shortbishop", "fen": "t"},
	Piece_Type_ENUMs.SHORTPAWN:   {"name": "shortpawn",   "fen": "z"},
	Piece_Type_ENUMs.MULE:        {"name": "mule",        "fen": "m"},
	Piece_Type_ENUMs.CHANCELLOR:  {"name": "chancellor",  "fen": "e"},
	Piece_Type_ENUMs.ROYALKNIGHT: {"name": "royalknight", "fen": "c"},
	Piece_Type_ENUMs.ROYALBISHOP: {"name": "royalbishop", "fen": "h"},
	Piece_Type_ENUMs.ROYALROOK:   {"name": "royalrook",   "fen": "i"},
	Piece_Type_ENUMs.MAN:         {"name": "man",         "fen": "f"},
	Piece_Type_ENUMs.KNIGHTRIDER: {"name": "knightrider", "fen": "d"},
	Piece_Type_ENUMs.AMAZON:      {"name": "amazon",      "fen": "x"},
	Piece_Type_ENUMs.PRINCESS:    {"name": "princess",    "fen": "u"},
	Piece_Type_ENUMs.WALL:        {"name": "wall",        "fen": "w"},
	Piece_Type_ENUMs.EMPRESS:     {"name": "empress",     "fen": "j"},
	Piece_Type_ENUMs.PRINCE:      {"name": "prince",      "fen": "l"},
	Piece_Type_ENUMs.STONE:       {"name": "stone",       "fen": "o"},  # king-mover, uncapturable
	Piece_Type_ENUMs.IRONQUEEN:   {"name": "queen",       "fen": "v"},  # moves as queen, uncapturable (queen sprite for now)
}

var _char_to_enum := {}

func _ready() -> void:
	for piece_type in PIECE_INFO:
		_char_to_enum[PIECE_INFO[piece_type]["fen"]] = piece_type


func give_piece_name_from_piece_type(enum_value):
	if PIECE_INFO.has(enum_value):
		return PIECE_INFO[enum_value]["name"]
	return ""


func get_piece_type_enum_from_string(value):
	return _char_to_enum.get(value.to_lower(), Piece_Type_ENUMs.NONE)


# Iron pieces reuse their base sprite + the iron recolor shader (no custom art).
func is_iron(type):
	return type == Piece_Type_ENUMs.IRONQUEEN


func get_fen_string_from_enum(value, white):
	if not PIECE_INFO.has(value):
		print("get fen string from enum error, returned *")
		return "*"
	var fen_char = PIECE_INFO[value]["fen"]
	if white:
		return fen_char.to_upper()
	return fen_char
