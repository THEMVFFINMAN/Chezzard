class_name VariantBuilder
extends RefCounted

# Generates a Fairy-Stockfish variant from a roster of piece enums, assigning FEN
# letters dynamically. Standard pieces keep their fixed letters (inherited from
# the chess parent); every other piece takes its preferred registry letter if
# free, else the next available one. The SAME assignment drives the emitted .ini
# text and the char<->enum maps, so they can never drift.
#
# build() returns:
#   {
#     "variant": "generated",
#     "text": "<variants.ini section>",
#     "char_to_enum": { "a": <enum>, ... },   # lower-case letter -> enum
#     "enum_to_char": { <enum>: "a", ... },
#   }

const POOL = "abcdefghijklmnopqrstuvwxyz"


static func build(roster, board_length = 8, variant_name = "generated", rules = []):
	var enum_to_char = {}
	var char_to_enum = {}
	var used = {}

	# Two passes so fixed-letter pieces (standard + preferred) always keep their
	# letter, and pieces with no "fen" fill whatever slots remain.
	for e in roster:
		if not Globals.PIECE_REGISTRY.has(e):
			continue
		var pref = Globals.PIECE_REGISTRY[e].get("fen", "")
		if pref != "" and not used.has(pref):
			used[pref] = true
			enum_to_char[e] = pref
			char_to_enum[pref] = e
	for e in roster:
		if not Globals.PIECE_REGISTRY.has(e) or enum_to_char.has(e):
			continue
		var letter = _next_free(used)
		used[letter] = true
		enum_to_char[e] = letter
		char_to_enum[letter] = e

	# Emit the variant section.
	var lines = ["[" + variant_name + ":chess]"]
	var custom_n = 0
	var promote = ""
	var pawns = ""
	var royal = ""
	for e in roster:
		if not Globals.PIECE_REGISTRY.has(e):
			continue
		var info = Globals.PIECE_REGISTRY[e]
		var letter = enum_to_char[e]
		match info.get("kind", "custom"):
			"builtin":
				lines.append(info["builtin"] + " = " + letter)
			"immobile":
				lines.append("immobile = " + letter)
			"custom":
				custom_n += 1
				lines.append("customPiece%d = %s:%s" % [custom_n, letter, info["betza"]])
			# "standard" is inherited from chess; "wall" is game-side only (sent as
			# "*"), so neither is emitted into the variant.
		if info.get("promote", false):
			promote += letter
		if info.get("pawn", false):
			pawns += letter
		if info.get("royal", false):
			royal = letter

	if royal != "":
		lines.append("extinctionValue = loss")
		lines.append("extinctionPseudoRoyal = true")
		lines.append("extinctionPieceTypes = " + royal)
		lines.append("extinctionPieceCount = 1")
	if promote != "":
		lines.append("promotionPieceTypes = " + promote)
	lines.append("promotionRegionWhite = *" + str(board_length))
	if pawns != "":
		lines.append("promotionPawnTypes = " + pawns)
		lines.append("enPassantTypes = " + pawns)
	for extra in rules:  # per-mode rule lines, e.g. "blastOnCapture = true"
		lines.append(extra)

	return {
		"variant": variant_name,
		"text": "\n".join(lines) + "\n",
		"char_to_enum": char_to_enum,
		"enum_to_char": enum_to_char,
	}


static func _next_free(used):
	for i in POOL.length():
		if not used.has(POOL[i]):
			return POOL[i]
	push_error("[VariantBuilder] roster exceeds 26 letters")
	return "?"


# The full registry (every piece). NOTE: only valid as a roster when there are
# <= 26 pieces; otherwise use roster_for_placements(). Kept for tests/tools.
static func full_roster():
	return Globals.PIECE_REGISTRY.keys()


# Derive a roster from a placement list: every piece used, plus all promotion
# targets (so pawns can promote even if those pieces aren't on the board). Keeps
# the roster within the 26-letter limit instead of pulling in the whole registry.
static func roster_for_placements(placements):
	var roster = {}
	for p in placements:
		roster[p["piece"]] = true
	for e in Globals.PIECE_REGISTRY:
		if Globals.PIECE_REGISTRY[e].get("promote", false):
			roster[e] = true
	return roster.keys()


# Write a generated variant to user://<filename>; returns the absolute path for
# the engine's VariantPath option.
static func write_variant_file(text, filename = "generated_variant.ini"):
	var dst = "user://" + filename
	var f = FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	return ProjectSettings.globalize_path(dst)


# Build a starting FEN from a placement list, using a roster's enum->letter map
# so the letters always match the generated variant. Each placement is
# { "sq": "e1", "piece": <enum>, "white": bool, "material": optional }.
# Uppercase = white. Wall pieces keep their game letter here (board.gd turns them
# into "*" when it sends the position to the engine).
static func placements_to_fen(placements, enum_to_char, width, length):
	var grid = {}
	for p in placements:
		var sq = p["sq"]
		var file = sq.unicode_at(0) - "a".unicode_at(0)
		var rank = int(sq.substr(1))
		var ch = enum_to_char.get(p["piece"], "?")
		if p.get("white", true):
			ch = ch.to_upper()
		grid[Vector2i(file, rank)] = ch
	var rows = []
	for r in range(length, 0, -1):
		var row = ""
		var empty = 0
		for fi in range(width):
			if grid.has(Vector2i(fi, r)):
				if empty > 0:
					row += str(empty)
					empty = 0
				row += grid[Vector2i(fi, r)]
			else:
				empty += 1
		if empty > 0:
			row += str(empty)
		rows.append(row)
	return "/".join(rows)


# Extract a { square -> material } map from a placement list (for board.test_materials).
static func placements_materials(placements):
	var mats = {}
	for p in placements:
		if p.get("material", "") != "":
			mats[p["sq"]] = p["material"]
	return mats


# Expand a compact, code-friendly layout into a placement list, so a level never
# has to hand-list every square:
#   layout = { "white": { 1: [ROOK, KNIGHT, BISHOP, ...], 2: SHORTPAWN }, "black": {...} }
# A rank whose value is an Array places one piece per file (null = empty); a rank
# whose value is a single enum fills the whole rank with it.
static func layout_to_placements(layout, width = 8):
	var placements = []
	for color in layout:
		var white = (color == "white")
		for rank in layout[color]:
			var spec = layout[color][rank]
			if spec is Array:
				for f in min(spec.size(), width):
					if spec[f] != null:
						placements.append(_cell_placement(spec[f], _file_letter(f) + str(rank), white))
			elif spec != null:
				for f in width:
					placements.append(_cell_placement(spec, _file_letter(f) + str(rank), white))
	return placements


# A layout cell is either a bare piece enum or a { "piece": enum, "material": name }
# dict — so any square can carry a material (e.g. a silver mule, an iron pawn).
static func _cell_placement(cell, sq, white):
	if cell is Dictionary:
		var p = {"sq": sq, "piece": cell["piece"], "white": white}
		if cell.get("material", "") != "":
			p["material"] = cell["material"]
		if cell.get("modifiers", []).size() > 0:
			p["modifiers"] = cell["modifiers"]
		return p
	return {"sq": sq, "piece": cell, "white": white}


# Extract a { square -> modifiers list } map from a placement list.
static func placements_modifiers(placements):
	var mods = {}
	for p in placements:
		if p.get("modifiers", []).size() > 0:
			mods[p["sq"]] = p["modifiers"]
	return mods


static func _file_letter(f):
	return char("a".unicode_at(0) + f)
