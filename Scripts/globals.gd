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
	BACKPAWN,
	PSEUDOKING,
	ROYALQUEEN,
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
#          royal (a pseudo-royal piece — a side loses when its royals go extinct;
#          ALL royal types in the roster are registered, so mixed armies like
#          prince-vs-king work)
const PIECE_REGISTRY = {
	Piece_Type_ENUMs.PAWN:        {"name": "pawn",        "fen": "p", "kind": "standard", "pawn": true},
	Piece_Type_ENUMs.BISHOP:      {"name": "bishop",      "fen": "b", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.KNIGHT:      {"name": "knight",      "fen": "n", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.ROOK:        {"name": "rook",        "fen": "r", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.QUEEN:       {"name": "queen",       "fen": "q", "kind": "standard", "promote": true},
	Piece_Type_ENUMs.KING:        {"name": "king",        "fen": "k", "kind": "standard", "royal": true},
	Piece_Type_ENUMs.ARCHBISHOP:  {"name": "archbishop",  "fen": "a", "kind": "builtin", "builtin": "archbishop"},
	Piece_Type_ENUMs.GIRAFFE:     {"name": "giraffe",     "fen": "g", "kind": "custom", "betza": "G"},
	Piece_Type_ENUMs.SHORTROOK:   {"name": "shortrook",   "fen": "s", "kind": "custom", "betza": "R4"},
	Piece_Type_ENUMs.SHORTBISHOP: {"name": "shortbishop", "fen": "t", "kind": "custom", "betza": "B3"},
	Piece_Type_ENUMs.SHORTPAWN:   {"name": "shortpawn",   "fen": "z", "kind": "custom", "betza": "fmWfceF", "pawn": true},
	Piece_Type_ENUMs.MULE:        {"name": "mule",        "fen": "m", "kind": "custom", "betza": "F"},
	Piece_Type_ENUMs.CHANCELLOR:  {"name": "chancellor",  "fen": "e", "kind": "builtin", "builtin": "chancellor"},
	Piece_Type_ENUMs.ROYALKNIGHT: {"name": "royalknight", "fen": "c", "kind": "builtin", "builtin": "centaur", "promote": true, "royal": true},
	Piece_Type_ENUMs.ROYALBISHOP: {"name": "royalbishop", "fen": "h", "kind": "custom", "betza": "WFB", "royal": true},
	Piece_Type_ENUMs.ROYALROOK:   {"name": "royalrook",   "fen": "i", "kind": "custom", "betza": "WFR", "royal": true},
	Piece_Type_ENUMs.MAN:         {"name": "man",         "fen": "f", "kind": "custom", "betza": "WF"},
	Piece_Type_ENUMs.KNIGHTRIDER: {"name": "knightrider", "fen": "d", "kind": "custom", "betza": "NN"},
	Piece_Type_ENUMs.AMAZON:      {"name": "amazon",      "fen": "x", "kind": "builtin", "builtin": "amazon"},
	Piece_Type_ENUMs.PRINCESS:    {"name": "princess",    "fen": "u", "kind": "custom", "betza": "R4B3"},
	Piece_Type_ENUMs.WALL:        {"name": "wall",        "fen": "w", "kind": "immobile"},
	Piece_Type_ENUMs.EMPRESS:     {"name": "empress",     "fen": "j", "kind": "custom", "betza": "Q"},
	# Orthogonal-only royal (Wazir) -- the diminished "short king." No diagonal
	# movement, and never castles (board.gd's castling tracking only
	# recognizes literal KING) -- Big (-> KING) is the only way to get either.
	Piece_Type_ENUMs.PRINCE:      {"name": "prince",      "fen": "l", "kind": "custom", "betza": "W", "royal": true},
	# Prince + full queen slide -- no existing piece covered this combo (unlike
	# Royal Bishop/Rook/Knight, which all happened to already exist), so this
	# is a genuinely new piece rather than a lookup-table reuse.
	Piece_Type_ENUMs.ROYALQUEEN:  {"name": "royalqueen",  "fen": "j", "kind": "custom", "betza": "QWF", "royal": true},
	# Moves and is checkmated exactly like a real king, but is a distinct enum
	# from literal KING -- needed for variants (e.g. Atomic) where the engine
	# flatly refuses literal KING (parser.cpp: "Can not use kings with
	# blastOnCapture"). "name": "king" is deliberate, not a typo -- it makes
	# give_piece_name_from_piece_type() resolve to the existing white_king/
	# black_king sprite, so it looks exactly like a king with zero new art.
	Piece_Type_ENUMs.PSEUDOKING:  {"name": "king",        "fen": "y", "kind": "custom", "betza": "WF", "royal": true},
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
	# Pawnback-style pawn: moves/captures forward normally, but can also step
	# backward (no capture) one square. Betza copied verbatim from Fairy-
	# Stockfish's own pawnback_variant(). NEEDS A SPRITE (white_backpawn /
	# black_backpawn) before it's usable on a real board -- no art yet.
	Piece_Type_ENUMs.BACKPAWN:      {"name": "backpawn",      "kind": "custom", "betza": "fbmWfceFifmnD", "pawn": true},
}

# True if this piece type is "a pawn" for promotion/en-passant/attack-shape
# purposes (the registry's "pawn" flag), not just the two original hardcoded
# PAWN/SHORTPAWN types. Use this instead of a hardcoded enum check so new pawn
# variants (e.g. BACKPAWN) don't silently fall through promotion handling.
func is_pawn_type(piece_type):
	return PIECE_REGISTRY.get(piece_type, {}).get("pawn", false)

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
	"iron":    preload("res://Assets/iron_material.tres"),
	"silver":  preload("res://Assets/silver_material.tres"),
	"gold":    preload("res://Assets/gold_material.tres"),
	"glass":   preload("res://Assets/glass_material.tres"),
	"blood":   preload("res://Assets/blood_material.tres"),
	"stone":   preload("res://Assets/stone_material.tres"),
	"diamond": preload("res://Assets/diamond_material.tres"),
}

# Gameplay effects per material (wired to the economy later). money_mult scales
# gold earned; break_chance is the per-trigger shatter probability (glass);
# lose_on_loss ends the run if the piece dies (blood).
const MATERIAL_EFFECTS = {
	"silver":  {"money_mult": 1.5, "break_chance": 0.0,  "lose_on_loss": false},
	"gold":    {"money_mult": 2.0, "break_chance": 0.0,  "lose_on_loss": false},
	# Safe tier above Gold -- deliberately below Glass's 4x so Glass still has
	# a reason to exist despite its break chance.
	"diamond": {"money_mult": 2.5, "break_chance": 0.0,  "lose_on_loss": false},
	"glass":   {"money_mult": 4.0, "break_chance": 0.25, "lose_on_loss": false},
	"blood":   {"money_mult": 5.0, "break_chance": 0.0,  "lose_on_loss": true},
}

func get_material_shader(name):
	return MATERIALS.get(name, null)


# Capture value (gold) per piece, for the economy. Uncapturable wall pieces never
# get taken, so they don't need a value here.
const PIECE_VALUES = {
	Piece_Type_ENUMs.PAWN: 1, Piece_Type_ENUMs.SHORTPAWN: 1, Piece_Type_ENUMs.BACKPAWN: 1,
	Piece_Type_ENUMs.KNIGHT: 3, Piece_Type_ENUMs.BISHOP: 3,
	Piece_Type_ENUMs.ROOK: 5, Piece_Type_ENUMs.QUEEN: 9,
	Piece_Type_ENUMs.KING: 4, Piece_Type_ENUMs.PRINCE: 4, Piece_Type_ENUMs.PSEUDOKING: 4,
	Piece_Type_ENUMs.SHORTROOK: 4, Piece_Type_ENUMs.SHORTBISHOP: 3,
	Piece_Type_ENUMs.MULE: 2, Piece_Type_ENUMs.MAN: 3,
	Piece_Type_ENUMs.PRINCESS: 6, Piece_Type_ENUMs.GIRAFFE: 2,
	Piece_Type_ENUMs.KNIGHTRIDER: 5, Piece_Type_ENUMs.EMPRESS: 9,
	Piece_Type_ENUMs.ARCHBISHOP: 7, Piece_Type_ENUMs.CHANCELLOR: 8,
	Piece_Type_ENUMs.AMAZON: 12, Piece_Type_ENUMs.ROYALKNIGHT: 5,
	Piece_Type_ENUMs.ROYALBISHOP: 5, Piece_Type_ENUMs.ROYALROOK: 6,
	Piece_Type_ENUMs.ROYALQUEEN: 10,
	Piece_Type_ENUMs.WALL: 0,
	Piece_Type_ENUMs.FERZ: 2, Piece_Type_ENUMs.ALFIL: 2,
	Piece_Type_ENUMs.DABBABA: 2, Piece_Type_ENUMs.GOLDGENERAL: 3,
	Piece_Type_ENUMs.SILVERGENERAL: 3, Piece_Type_ENUMs.CAMEL: 2,
	Piece_Type_ENUMs.ZEBRA: 2, Piece_Type_ENUMs.WILDEBEEST: 5,
	Piece_Type_ENUMs.DABBABARIDER: 4, Piece_Type_ENUMs.BUFFALO: 6,
}

func piece_value(piece_type):
	return PIECE_VALUES.get(piece_type, 1)


# --- Modifiers ---
# A modifier is a per-piece rule tag, separate from material; several can stack
# on one piece. Applied via a placement/cell "modifiers": [...] key or
# piece.apply_modifiers(). Mechanics are scaffolded here, not all wired yet.
const MODIFIERS = {
	"racist":   {"desc": "colourbound: only the square colour it starts on", "colorbound": true},
	"time1":    {"desc": "after moving, locked for 1 full turn", "cooldown": 1},
	"time2":    {"desc": "after moving, locked for 2 full turns", "cooldown": 2},
	"double":   {"desc": "may move twice in a row (short-range pieces)", "extra_moves": 1},
	"slippery": {"desc": "(square effect, planned) slips; spend a turn to upright", "square_effect": true},
	"petrify":  {"desc": "turns into an immobile wall right after capturing", "petrify": true},
	"atomic":   {"desc": "capturing blows up itself + adjacent non-pawns", "atomic": true},
	# Captured while NOT currently a pawn -> respawns one rung down the
	# demotion ladder (see ZOMBIE_DEMOTE/_COMPOUND_PARENTS below) at (or near)
	# its original battle-start square instead of staying dead. Since
	# board.gd checks is_pawn_type(piece_type) at the moment of capture, not
	# this flag alone, the charge re-arms every time it demotes to something
	# that ISN'T itself pawn-type -- a Rook steps down to Short Rook, and if
	# THAT dies too, down again to Short Pawn, which finally ends the chain
	# (any pawn-type death, including Short Pawn's, is final -- never
	# retriggers). Never a valid target for a royal piece (shop.gd excludes
	# it) -- a respawning king would break checkmate.
	"zombie": {"desc": "if captured while not a pawn, demotes one rung instead of dying", "zombie": true},
}

# --- Zombie demotion ladder ---
# What a captured "zombie" piece respawns as (see board.gd's
# _zombie_respawn). Two shapes:
#  - ZOMBIE_DEMOTE: an atomic single-direction piece (Rook/Bishop/Knight/
#    Pawn), or a rider that's just that atomic's leap repeated (Knightrider,
#    Dabbabarider), demotes to its own pre-existing diminished counterpart --
#    a fixed naming/content fact, not something derivable from anything
#    else, so this is the one part that's genuinely hardcoded.
#  - ZOMBIE_COMPOUND_PARENTS: every OTHER piece lists the fundamental
#    movement identities it's built from (Bishop/Rook/Knight/Pawn/Camel/
#    Zebra only -- King/royalty is deliberately never listed, since it's
#    never a legal landing spot: a Royal Bishop's only listed parent is
#    Bishop, a Man's only listed parent is Pawn). zombie_target() picks the
#    single highest-value listed parent and lands on its FULL-size form (not
#    demoted further) -- e.g. Bishop+Rook (Queen, Empress, or Royal Queen
#    once King is excluded) goes back to a full Rook, since Rook outvalues
#    Bishop. A tie (equal-value parents, e.g. Bishop+Knight -> Archbishop)
#    picks randomly between them. Anything missing from BOTH tables (already
#    diminished, or genuinely unmapped -- Giraffe, Alfil, Dabbaba, the shogi
#    generals, bare Ferz/Camel/Zebra: none of these have an in-game
#    diminished sibling or a tracked parent pair) bottoms out at Short Pawn.
# Everything here is audited against the full Piece_Type_ENUMs list -- not
# just what's currently reachable through the shop -- so a piece that isn't
# player-placeable TODAY (Wildebeest, Buffalo, Dabbabarider, Empress) still
# resolves correctly the day something makes it reachable.
const ZOMBIE_DEMOTE = {
	Piece_Type_ENUMs.ROOK: Piece_Type_ENUMs.SHORTROOK,
	Piece_Type_ENUMs.BISHOP: Piece_Type_ENUMs.SHORTBISHOP,
	Piece_Type_ENUMs.KNIGHT: Piece_Type_ENUMs.MULE,
	Piece_Type_ENUMs.KNIGHTRIDER: Piece_Type_ENUMs.MULE,
	Piece_Type_ENUMs.PAWN: Piece_Type_ENUMs.SHORTPAWN,
	Piece_Type_ENUMs.DABBABARIDER: Piece_Type_ENUMs.DABBABA,
}
const ZOMBIE_COMPOUND_PARENTS = {
	Piece_Type_ENUMs.QUEEN: [Piece_Type_ENUMs.BISHOP, Piece_Type_ENUMs.ROOK],
	Piece_Type_ENUMs.EMPRESS: [Piece_Type_ENUMs.BISHOP, Piece_Type_ENUMs.ROOK],  # betza "Q" -- mechanically a Queen under a different name
	Piece_Type_ENUMs.ARCHBISHOP: [Piece_Type_ENUMs.BISHOP, Piece_Type_ENUMs.KNIGHT],
	Piece_Type_ENUMs.CHANCELLOR: [Piece_Type_ENUMs.ROOK, Piece_Type_ENUMs.KNIGHT],
	Piece_Type_ENUMs.AMAZON: [Piece_Type_ENUMs.BISHOP, Piece_Type_ENUMs.ROOK, Piece_Type_ENUMs.KNIGHT],
	Piece_Type_ENUMs.WILDEBEEST: [Piece_Type_ENUMs.KNIGHT, Piece_Type_ENUMs.CAMEL],
	Piece_Type_ENUMs.BUFFALO: [Piece_Type_ENUMs.KNIGHT, Piece_Type_ENUMs.CAMEL, Piece_Type_ENUMs.ZEBRA],
	# King component dropped from every one of these -- never a legal target.
	Piece_Type_ENUMs.MAN: [Piece_Type_ENUMs.PAWN],
	Piece_Type_ENUMs.ROYALBISHOP: [Piece_Type_ENUMs.BISHOP],
	Piece_Type_ENUMs.ROYALROOK: [Piece_Type_ENUMs.ROOK],
	Piece_Type_ENUMs.ROYALKNIGHT: [Piece_Type_ENUMs.KNIGHT],
	Piece_Type_ENUMs.ROYALQUEEN: [Piece_Type_ENUMs.BISHOP, Piece_Type_ENUMs.ROOK],
}

func zombie_target(piece_type):
	if ZOMBIE_DEMOTE.has(piece_type):
		return ZOMBIE_DEMOTE[piece_type]
	if ZOMBIE_COMPOUND_PARENTS.has(piece_type):
		var parents = ZOMBIE_COMPOUND_PARENTS[piece_type]
		var best_value = -1
		for p in parents:
			best_value = max(best_value, piece_value(p))
		var tied = parents.filter(func(p): return piece_value(p) == best_value)
		return tied[randi() % tied.size()]
	return Piece_Type_ENUMs.SHORTPAWN  # already short, or genuinely unmapped -- bottom rung

# Flip to true for the full [uci]/[movegen]/[board_dump]/[game_over]/etc. trace
# that was used to hunt the FEN-corruption bug -- very noisy, off by default.
var debug_logging = true

func dprint(msg):
	if debug_logging:
		print(msg)


# --- Relics ---
# A relic is a run-wide passive, owned once (RunState.relics). Effects are read at
# the relevant hook (economy in board.gd, war_chest in RunState.advance).
const RELICS = {
	"merchants_scale":     {"name": "Merchant's Scale",     "desc": "+50% gold from wins",              "cost": 60},
	"bloodstone":          {"name": "Bloodstone",           "desc": "+2 gold per capture",              "cost": 50},
	"glassblower":         {"name": "Glassblower's Gloves", "desc": "Glass pieces never break",         "cost": 70},
	"war_chest":           {"name": "War Chest",            "desc": "+15 gold each floor",              "cost": 55},
	# Board/rule-level passives (not piece-specific) -- applied every battle
	# via RunState._apply_relic_battle_effects(), reusing flags board.gd
	# already has rather than inventing new mechanics.
	"siege_breaker":       {"name": "Siege Breaker",        "desc": "Enemy can never castle",           "cost": 50},
	"checkmate_insurance": {"name": "Checkmate Insurance",  "desc": "Draws count as your win",          "cost": 80},
	"confusion_tactics":   {"name": "Confusion Tactics",    "desc": "Enemy starts king/queen swapped",  "cost": 45},
}


# --- Piece transformations ---
# Deckbuilder-style shop cards: you buy a card (a material, a modifier, a
# movement add-on, or "Big") at a flat price, THEN pick which of your own
# pieces to drop it on for free -- placement never costs extra regardless of
# target. See shop.gd for the buy-then-target-pick flow.

# "Big": removes the "short"/diminished restriction -- one fixed full-
# strength target each. Only short pieces belong here; KNIGHT is already
# full-strength, so it's deliberately NOT a Big target (no de-limiting to do).
const BIG_UPGRADES = {
	Piece_Type_ENUMs.SHORTROOK: Piece_Type_ENUMs.ROOK,
	Piece_Type_ENUMs.SHORTBISHOP: Piece_Type_ENUMs.BISHOP,
	Piece_Type_ENUMs.SHORTPAWN: Piece_Type_ENUMs.PAWN,
	Piece_Type_ENUMs.MULE: Piece_Type_ENUMs.KNIGHT,
	Piece_Type_ENUMs.PRINCESS: Piece_Type_ENUMs.QUEEN,
	# PRINCE is orthogonal-only (Wazir) and never castles. KING is the native
	# "kind": "standard" royal type, so this grants diagonal movement AND real
	# castling in one upgrade (board.gd's castling tracking only recognizes
	# literal KING).
	Piece_Type_ENUMs.PRINCE: Piece_Type_ENUMs.KING,
}

# Movement-compound cards: bolt an additional movement type onto a piece that
# doesn't already have it. Keyed by the movement being added, then by the
# piece type it can legally land on -> the resulting (already-registered,
# no new art/betza needed) piece type. Deliberately NOT exhaustive beyond
# this: e.g. adding any of these onto a PAWN (other than "king", below)
# needs a genuinely synthesized custom piece, not a lookup entry, and isn't
# supported by this system yet.
const MOVEMENT_UPGRADES = {
	"knight": {
		Piece_Type_ENUMs.BISHOP: Piece_Type_ENUMs.ARCHBISHOP,
		Piece_Type_ENUMs.ROOK: Piece_Type_ENUMs.CHANCELLOR,
		Piece_Type_ENUMs.QUEEN: Piece_Type_ENUMs.AMAZON,
		Piece_Type_ENUMs.PRINCE: Piece_Type_ENUMs.ROYALKNIGHT,
		# Symmetric with "king" table's KNIGHT entry below -- same destination,
		# starting from the other piece.
		Piece_Type_ENUMs.KING: Piece_Type_ENUMs.ROYALKNIGHT,
		# Second tier: a piece that already has two of the three (bishop+
		# knight, or rook+knight) picks up the third component, completing
		# queen+knight = Amazon either way. Lets a Knight genuinely stack
		# (e.g. Bishop Movement then Rook Movement reaches Amazon via
		# Archbishop, same as going straight there with Queen Movement).
		Piece_Type_ENUMs.CHANCELLOR: Piece_Type_ENUMs.AMAZON,
		# Unlike every other entry in this table, a Pawn has no sliding/leaping
		# identity for a knight's leap to union with -- this is a straight
		# replacement, not a movement-set simplification. Full Pawn only;
		# Short Pawn needs Big first, same as every other short piece.
		Piece_Type_ENUMs.PAWN: Piece_Type_ENUMs.KNIGHT,
	},
	"bishop": {
		Piece_Type_ENUMs.PRINCE: Piece_Type_ENUMs.ROYALBISHOP,
		# Symmetric with "king" table's BISHOP entry below.
		Piece_Type_ENUMs.KING: Piece_Type_ENUMs.ROYALBISHOP,
		Piece_Type_ENUMs.ROOK: Piece_Type_ENUMs.QUEEN,
		# Symmetric with "knight"'s BISHOP entry above -- same destination,
		# starting from the other piece. This is specifically the gap that
		# blocked adding Bishop/Rook to an already-Double Knight.
		Piece_Type_ENUMs.KNIGHT: Piece_Type_ENUMs.ARCHBISHOP,
		Piece_Type_ENUMs.CHANCELLOR: Piece_Type_ENUMs.AMAZON,
		Piece_Type_ENUMs.ROYALROOK: Piece_Type_ENUMs.ROYALQUEEN,
		# Short Bishop's "B3" is a strict subset of full Bishop's "B" -- same
		# family, so this also works as a Big shortcut for this one piece.
		# Mule doesn't get the equivalent treatment under "knight": Mule's
		# actual movement (F, one-step diagonal) has nothing to do with a
		# knight's leap -- it only occupies that slot by layout convention,
		# not by any real movement relationship.
		Piece_Type_ENUMs.SHORTBISHOP: Piece_Type_ENUMs.BISHOP,
		# Straight replacement, not a subset simplification -- see "knight"'s
		# PAWN entry above. Full Pawn only.
		Piece_Type_ENUMs.PAWN: Piece_Type_ENUMs.BISHOP,
	},
	"rook": {
		Piece_Type_ENUMs.PRINCE: Piece_Type_ENUMs.ROYALROOK,
		# Symmetric with "king" table's ROOK entry below.
		Piece_Type_ENUMs.KING: Piece_Type_ENUMs.ROYALROOK,
		Piece_Type_ENUMs.BISHOP: Piece_Type_ENUMs.QUEEN,
		Piece_Type_ENUMs.KNIGHT: Piece_Type_ENUMs.CHANCELLOR,
		Piece_Type_ENUMs.ARCHBISHOP: Piece_Type_ENUMs.AMAZON,
		Piece_Type_ENUMs.ROYALBISHOP: Piece_Type_ENUMs.ROYALQUEEN,
		# Same reasoning as Short Bishop above: "R4" is a strict subset of "R".
		Piece_Type_ENUMs.SHORTROOK: Piece_Type_ENUMs.ROOK,
		# Straight replacement, not a subset simplification -- see "knight"'s
		# PAWN entry above. Full Pawn only.
		Piece_Type_ENUMs.PAWN: Piece_Type_ENUMs.ROOK,
	},
	# King-step (one square any direction) added to a pawn's forward-only
	# step/capture strictly subsumes it -- the union simplifies to exactly
	# "WF", which is Man's actual betza already. Same union logic gives
	# Royal Knight/Bishop/Rook/Queen from the other direction (knight/bishop/
	# rook/queen + king-step) as Prince's own +knight/+bishop/+rook/+queen
	# entries do -- two paths to the same piece, depending which one you're
	# upgrading.
	"king": {
		Piece_Type_ENUMs.PAWN: Piece_Type_ENUMs.MAN,
		Piece_Type_ENUMs.KNIGHT: Piece_Type_ENUMs.ROYALKNIGHT,
		Piece_Type_ENUMs.BISHOP: Piece_Type_ENUMs.ROYALBISHOP,
		Piece_Type_ENUMs.ROOK: Piece_Type_ENUMs.ROYALROOK,
		Piece_Type_ENUMs.QUEEN: Piece_Type_ENUMs.ROYALQUEEN,
	},
	# Bishop/Rook landing on Queen here overlaps with what the "bishop"/
	# "rook" cards above already do for those same pieces -- that's fine,
	# multiple cards are allowed to reach the same result on the same piece.
	"queen": {
		Piece_Type_ENUMs.KNIGHT: Piece_Type_ENUMs.AMAZON,
		Piece_Type_ENUMs.BISHOP: Piece_Type_ENUMs.QUEEN,
		Piece_Type_ENUMs.ROOK: Piece_Type_ENUMs.QUEEN,
		Piece_Type_ENUMs.PRINCE: Piece_Type_ENUMs.ROYALQUEEN,
		# Symmetric with "king" table's QUEEN entry above.
		Piece_Type_ENUMs.KING: Piece_Type_ENUMs.ROYALQUEEN,
		# Straight replacement, not a subset simplification -- see "knight"'s
		# PAWN entry above. Full Pawn only.
		Piece_Type_ENUMs.PAWN: Piece_Type_ENUMs.QUEEN,
	},
}

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
