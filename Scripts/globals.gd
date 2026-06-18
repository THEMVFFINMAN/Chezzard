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

# Master piece registry: the single source of truth for every piece type. Used
# both by the live game (name + default FEN letter) and by VariantBuilder, which
# generates a fresh variants.ini for a chosen roster from "kind"/"betza".
#
#   kind:  standard = inherited from the chess parent (fixed letter, not emitted)
#          builtin  = a Fairy-Stockfish built-in, emitted as "<builtin> = <letter>"
#          custom   = emitted as "customPieceN = <letter>:<betza>"
#          immobile = the wall blocker, emitted as "immobile = <letter>"
#          wall     = game-side-only piece (sent to the engine as a "*" wall), so
#                     it is NEVER emitted into the variant
#   flags: pawn (promotion/en-passant pawn type), promote (promotion target),
#          royal (the pseudo-royal piece whose extinction loses the game)
const PIECE_REGISTRY = {
	Piece_Type_ENUMs.PAWN:        {"name": "pawn",        "fen": "p", "kind": "standard", "pawn": true},
	Piece_Type_ENUMs.BISHOP:      {"name": "bishop",      "fen": "b", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.KNIGHT:      {"name": "knight",      "fen": "n", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.ROOK:        {"name": "rook",        "fen": "r", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.QUEEN:       {"name": "queen",       "fen": "q", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.KING:        {"name": "king",        "fen": "k", "kind": "standard"},
	Piece_Type_ENUMs.ARCHBISHOP:  {"name": "archbishop",  "fen": "a", "kind": "builtin", "builtin": "archbishop"},
	Piece_Type_ENUMs.GIRAFFE:     {"name": "giraffe",     "fen": "g", "kind": "custom", "betza": "G"},
	Piece_Type_ENUMs.SHORTROOK:   {"name": "shortrook",   "fen": "s", "kind": "custom", "betza": "R4"},
	Piece_Type_ENUMs.SHORTBISHOP: {"name": "shortbishop", "fen": "t", "kind": "custom", "betza": "B3"},
	Piece_Type_ENUMs.SHORTPAWN:   {"name": "shortpawn",   "fen": "z", "kind": "custom", "betza": "fmWfceF", "pawn": true},
	Piece_Type_ENUMs.MULE:        {"name": "mule",        "fen": "m", "kind": "custom", "betza": "F"},
	Piece_Type_ENUMs.CHANCELLOR:  {"name": "chancellor",  "fen": "e", "kind": "builtin", "builtin": "chancellor"},
	Piece_Type_ENUMs.ROYALKNIGHT: {"name": "royalknight", "fen": "c", "kind": "builtin", "builtin": "centaur", "promote": true},
	Piece_Type_ENUMs.ROYALBISHOP: {"name": "royalbishop", "fen": "h", "kind": "custom", "betza": "WFB"},
	Piece_Type_ENUMs.ROYALROOK:   {"name": "royalrook",   "fen": "i", "kind": "custom", "betza": "WFR"},
	Piece_Type_ENUMs.MAN:         {"name": "man",         "fen": "f", "kind": "custom", "betza": "WF"},
	Piece_Type_ENUMs.KNIGHTRIDER: {"name": "knightrider", "fen": "d", "kind": "custom", "betza": "NN"},
	Piece_Type_ENUMs.AMAZON:      {"name": "amazon",      "fen": "x", "kind": "builtin", "builtin": "amazon"},
	Piece_Type_ENUMs.PRINCESS:    {"name": "princess",    "fen": "u", "kind": "custom", "betza": "R4B3"},
	Piece_Type_ENUMs.WALL:        {"name": "wall",        "fen": "w", "kind": "immobile"},
	Piece_Type_ENUMs.EMPRESS:     {"name": "empress",     "fen": "j", "kind": "custom", "betza": "Q"},
	Piece_Type_ENUMs.PRINCE:      {"name": "prince",      "fen": "l", "kind": "custom", "betza": "W", "royal": true},
	Piece_Type_ENUMs.STONE:       {"name": "stone",       "fen": "o", "kind": "wall", "betza": "WF"},  # uncapturable king-mover (game-side, "*")
	Piece_Type_ENUMs.IRONQUEEN:   {"name": "queen",       "fen": "v", "kind": "wall", "betza": "Q"},   # uncapturable queen (game-side, "*")
}

var _char_to_enum := {}

func _ready() -> void:
	for piece_type in PIECE_REGISTRY:
		_char_to_enum[PIECE_REGISTRY[piece_type]["fen"]] = piece_type


func give_piece_name_from_piece_type(enum_value):
	if PIECE_REGISTRY.has(enum_value):
		return PIECE_REGISTRY[enum_value]["name"]
	return ""


func get_piece_type_enum_from_string(value):
	return _char_to_enum.get(value.to_lower(), Piece_Type_ENUMs.NONE)


# Iron pieces reuse their base sprite + the iron recolor shader (no custom art).
func is_iron(type):
	return type == Piece_Type_ENUMs.IRONQUEEN


# --- Material system ---
# A material is a per-piece visual+gameplay flag, independent of the piece's
# movement. Each maps to a recolor ShaderMaterial. "iron"/"stone" are the
# uncapturable family (movement handled by the wall mechanism in board.gd);
# silver/gold/glass/blood are normal capturable pieces with economy effects.
const MATERIALS = {
	"iron":   preload("res://Assets/iron_material.tres"),
	"silver": preload("res://Assets/silver_material.tres"),
	"gold":   preload("res://Assets/gold_material.tres"),
	"glass":  preload("res://Assets/glass_material.tres"),
	"blood":  preload("res://Assets/blood_material.tres"),
	"stone":  preload("res://Assets/stone_material.tres"),
}

# Gameplay effects per material (wired to the economy later). money_mult scales
# gold earned; break_chance is the per-trigger shatter probability (glass);
# lose_on_loss ends the run if the piece dies (blood).
const MATERIAL_EFFECTS = {
	"silver": {"money_mult": 1.5, "break_chance": 0.0,  "lose_on_loss": false},
	"gold":   {"money_mult": 2.0, "break_chance": 0.0,  "lose_on_loss": false},
	"glass":  {"money_mult": 1.0, "break_chance": 0.25, "lose_on_loss": false},
	"blood":  {"money_mult": 3.0, "break_chance": 0.0,  "lose_on_loss": true},
}

func get_material_shader(name):
	return MATERIALS.get(name, null)


func get_fen_string_from_enum(value, white):
	if not PIECE_REGISTRY.has(value):
		print("get fen string from enum error, returned *")
		return "*"
	var fen_char = PIECE_REGISTRY[value]["fen"]
	if white:
		return fen_char.to_upper()
	return fen_char
