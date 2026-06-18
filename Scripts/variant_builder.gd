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


static func build(roster, board_length = 8, variant_name = "generated"):
	var enum_to_char = {}
	var char_to_enum = {}
	var used = {}

	# Assign letters: prefer each piece's registry letter, else the next free one.
	for e in roster:
		if not Globals.PIECE_REGISTRY.has(e):
			continue
		var letter = Globals.PIECE_REGISTRY[e]["fen"]
		if used.has(letter):
			letter = _next_free(used)
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


# The full current roster (every registered piece) — handy default / test case.
static func full_roster():
	return Globals.PIECE_REGISTRY.keys()


# Write a generated variant to user://<filename>; returns the absolute path for
# the engine's VariantPath option.
static func write_variant_file(text, filename = "generated_variant.ini"):
	var dst = "user://" + filename
	var f = FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	return ProjectSettings.globalize_path(dst)
