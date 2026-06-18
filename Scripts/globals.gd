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
	FERZ,
	ALFIL,
	DABBABA,
	GOLDGENERAL,
	SILVERGENERAL,
	CAMEL,
	ZEBRA,
	WILDEBEEST,
	DABBABARIDER,
	BUFFALO,
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
	# --- Extra fairy pieces. No fixed "fen": letters are assigned dynamically per
	# roster (so they never burn the 26-letter budget). Each needs sprites — add
	# white_<name>/black_<name> animations before putting one on the board.
	Piece_Type_ENUMs.FERZ:          {"name": "ferz",          "kind": "custom", "betza": "F"},        # 1 step diagonal (colorbound)
	Piece_Type_ENUMs.ALFIL:         {"name": "alfil",         "kind": "custom", "betza": "A"},        # 2-square diagonal jump
	Piece_Type_ENUMs.DABBABA:       {"name": "dabbaba",       "kind": "custom", "betza": "D"},        # 2-square orthogonal jump
	Piece_Type_ENUMs.GOLDGENERAL:   {"name": "goldgeneral",   "kind": "custom", "betza": "WfF"},      # shogi gold
	Piece_Type_ENUMs.SILVERGENERAL: {"name": "silvergeneral", "kind": "custom", "betza": "FfW"},      # shogi silver
	Piece_Type_ENUMs.CAMEL:         {"name": "camel",         "kind": "custom", "betza": "C"},        # (1,3) leaper (colorbound)
	Piece_Type_ENUMs.ZEBRA:         {"name": "zebra",         "kind": "custom", "betza": "Z"},        # (2,3) leaper
	Piece_Type_ENUMs.WILDEBEEST:    {"name": "wildebeest",    "kind": "custom", "betza": "NC"},       # knight + camel
	Piece_Type_ENUMs.DABBABARIDER:  {"name": "dabbabarider",  "kind": "custom", "betza": "DD"},       # "one-colour rook"
	Piece_Type_ENUMs.BUFFALO:       {"name": "buffalo",       "kind": "custom", "betza": "NCZ"},      # knight + camel + zebra
}

var _char_to_enum := {}
# When a generated roster is active these override the registry defaults so reused
# letters resolve per-roster. Empty = use registry defaults.
var _active_enum_to_char := {}

func _ready() -> void:
	for piece_type in PIECE_REGISTRY:
		var f = PIECE_REGISTRY[piece_type].get("fen", "")
		if f != "":
			_char_to_enum[f] = piece_type

# Swap in a roster's letter assignment (from VariantBuilder) for the current game.
func set_active_char_map(char_to_enum, enum_to_char):
	_char_to_enum = char_to_enum
	_active_enum_to_char = enum_to_char

# Restore the default registry letter map (for static / non-generated variants).
func reset_char_map():
	_active_enum_to_char = {}
	_char_to_enum = {}
	for piece_type in PIECE_REGISTRY:
		var f = PIECE_REGISTRY[piece_type].get("fen", "")
		if f != "":
			_char_to_enum[f] = piece_type

# The default registry letter for each piece as { enum: letter } — for building
# positions in canonical letters (static variants / non-generated modes).
func default_enum_to_char():
	var m = {}
	for piece_type in PIECE_REGISTRY:
		var f = PIECE_REGISTRY[piece_type].get("fen", "")
		if f != "":
			m[piece_type] = f
	return m


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
	var fen_char
	if _active_enum_to_char.has(value):
		fen_char = _active_enum_to_char[value]
	elif PIECE_REGISTRY.has(value):
		fen_char = PIECE_REGISTRY[value]["fen"]
	else:
		print("get fen string from enum error, returned *")
		return "*"
	if white:
		return fen_char.to_upper()
	return fen_char
