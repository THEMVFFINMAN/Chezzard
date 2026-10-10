extends Node

# Run-wide state: a persistent army, gold, and a 10-floor climb. Drives the
# roguelike loop — board_container reads current_battle(); the shop edits army.
signal gold_changed(total)

const FLOOR_COUNT = 10

var gold := 0
var floor := 0
var in_run := false
var lost_origins := []     # army start-squares lost permanently (e.g. blood deaths)
var army := {}             # persistent white layout { rank: [cells] }
var relics := []           # owned relic ids (run-wide passives, see Globals.RELICS)
var test_mode := false     # debug: shop shows every card/relic, no rolling/filtering, repeat buys allowed
var test_hotseat := false  # debug: next battle is human-vs-human instead of vs the AI


func start_run():
	in_run = true
	test_mode = false
	test_hotseat = false
	floor = 1
	gold = 0
	lost_origins = []
	relics = []
	army = _default_army()
	gold_changed.emit(gold)


# Debug/testing: jump straight to the shop with a fresh army and plenty of
# gold, skipping the run/battle loop entirely -- lets you buy an upgrade,
# place it, then play floor 1 for real to test the result without having to
# Start Run + Auto-Win every time. test_mode tells the shop to show every
# card and relic at once instead of rolling a random sample, and to allow
# buying the same card repeatedly (e.g. Big on every short piece in turn).
# Same starting army as a real run -- all short -- so the short-piece-first
# progression is actually exercised, not skipped.
func start_test_shop():
	in_run = true
	test_mode = true
	test_hotseat = false
	floor = 1
	gold = 99999
	lost_origins = []
	relics = []
	army = _default_army()
	gold_changed.emit(gold)


func advance():
	floor += 1
	if has_relic("war_chest"):
		add_gold(15, "war_chest")


func has_relic(id):
	return id in relics


func add_relic(id):
	if id not in relics:
		relics.append(id)


func is_complete():
	return floor > FLOOR_COUNT


func add_gold(amount, reason = ""):
	gold += amount
	gold_changed.emit(gold)
	print("[gold] +%d (%s) -> %d total" % [amount, reason, gold])


# A piece permanently removed from the run army (e.g. a blood piece that died).
func lose_piece(origin):
	if origin != "" and origin not in lost_origins:
		lost_origins.append(origin)
		print("[run] permanently lost the piece from %s" % origin)


const GROWTH_ROW = 3  # one rank ahead of the starting pawn row (rank 2) -- where a grown pawn lands


# --- Army growth (shop "Grow Pawn"/"Grow Short Pawn" cards) ---
# Unlike lost_slots() below, this isn't a refill -- it adds a brand new piece
# past the starting 16, onto a blank square one rank ahead of your pawn row.
func growth_slots():
	var slots := []
	var row = army.get(GROWTH_ROW, [])
	for file in 8:
		if file >= row.size() or row[file] == null:
			slots.append({"rank": GROWTH_ROW, "file": file})
	return slots


func grow_pawn(file: int, short: bool) -> void:
	if not army.has(GROWTH_ROW):
		army[GROWTH_ROW] = [null, null, null, null, null, null, null, null]
	army[GROWTH_ROW][file] = Globals.Piece_Type_ENUMs.SHORTPAWN if short else Globals.Piece_Type_ENUMs.PAWN


# --- Lost-slot recovery (shop "Refill Pawn" card) ---
# lose_piece() never actually clears the slot in `army` -- it just masks it
# out of battle layouts via lost_origins -- so these slots still technically
# hold their old (dead) piece data until refilled.
func lost_slots():
	var slots := []
	for origin in lost_origins:
		var file = origin.unicode_at(0) - "a".unicode_at(0)
		var rnk = int(origin.substr(1))
		slots.append({"rank": rnk, "file": file, "origin": origin})
	return slots


# Refill a lost slot with a fresh Short Pawn -- it's alive again, as a plain
# pawn regardless of what used to be there.
func add_pawn(rank, file):
	var origin = "%s%d" % [String.chr(97 + file), rank]
	lost_origins.erase(origin)
	army[rank][file] = Globals.Piece_Type_ENUMs.SHORTPAWN


# Battle config for the current floor: your army vs the floor's enemy.
func current_battle():
	var f = _floor_config(floor)
	var cfg = {
		"generated": true,
		"layout": {"white": _army_layout(), "black": f["enemy"]},
		"rules": f.get("rules", []),
		"royal_count": f.get("royal_count", 1),
		# apply_config() reads the per-side keys, not a single "head_of_snake" --
		# the Wizard floor (the only place this is set) wants it on both sides.
		"head_of_snake_white": f.get("head_of_snake", false),
		"head_of_snake_black": f.get("head_of_snake", false),
		"unroyal": f.get("unroyal", false),
		"three_check": f.get("three_check", false),
		"name": f.get("name", "Floor %d" % floor),
	}
	_apply_relic_battle_effects(cfg)
	return cfg


# Debug/testing: your current (test) army vs. a plain, standard full army --
# deliberately NOT _floor_config()/current_battle(), since testing upgrades
# isn't simulating any particular floor (dwarf army, Hamlet King's short
# pieces, etc.) -- it's just "does this piece move right against a normal
# opponent." Used for both "Next Floor" and "Test vs Human" while test_mode.
func test_battle():
	var E = Globals.Piece_Type_ENUMs
	var cfg = {
		"generated": true,
		"layout": {
			"white": _army_layout(),
			"black": {
				8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK],
				7: E.PAWN,
			},
		},
		"name": "Test Battle",
	}
	_apply_relic_battle_effects(cfg)
	return cfg


# Board/rule-level relics (not piece-specific) -- applied to every battle's
# config, reusing existing board.gd flags rather than inventing new mechanics.
func _apply_relic_battle_effects(cfg):
	if has_relic("siege_breaker"):
		cfg["disable_black_castling"] = true
	if has_relic("checkmate_insurance"):
		cfg["draws_favor_white"] = true
	if has_relic("confusion_tactics"):
		cfg["flip_black_king_queen"] = true


# The army as a layout, with permanently-lost slots emptied.
func _army_layout():
	var out := {}
	for rank in army:
		out[rank] = army[rank].duplicate()
	for origin in lost_origins:
		var file = origin.unicode_at(0) - "a".unicode_at(0)
		var rnk = int(origin.substr(1))
		if out.has(rnk) and file >= 0 and file < out[rnk].size():
			out[rnk][file] = null
	return out


# Full 16-piece army, but every piece is the diminished "short" version --
# mirrors a real back rank (rook/knight/bishop/queen/king/bishop/knight/rook)
# using the short-piece family: Short Rook, Mule (knight slot), Short Bishop,
# Princess (short queen), Prince (king slot). The shop builds these up from here.
func _default_army():
	var E = Globals.Piece_Type_ENUMs
	return {
		1: [E.SHORTROOK, E.MULE, E.SHORTBISHOP, E.PRINCESS, E.PRINCE, E.SHORTBISHOP, E.MULE, E.SHORTROOK],
		2: [E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN],
	}


# Escalating enemy per floor; floor 10 is the Wizard (a head-of-snake boss).
func _floor_config(f):
	var E = Globals.Piece_Type_ENUMs
	var cfg := {"name": "Floor %d" % f}
	if f >= FLOOR_COUNT:
		cfg["name"] = "The Wizard"
		cfg["head_of_snake"] = true
		cfg["enemy"] = {8: [E.ROOK, E.KNIGHT, E.ARCHBISHOP, E.QUEEN, E.KING, E.ARCHBISHOP, E.KNIGHT, E.ROOK], 7: E.PAWN}
	elif f >= 7:
		cfg["enemy"] = {8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK], 7: E.PAWN}
	elif f >= 4:
		cfg["enemy"] = {8: [E.ROOK, E.KNIGHT, null, E.QUEEN, E.KING, null, E.KNIGHT, E.ROOK], 7: E.PAWN}
	else:
		# Early floors: a weak "dwarf" army — king, queen, two bishops, four pawns.
		cfg["enemy"] = {
			8: [null, E.BISHOP, null, E.QUEEN, E.KING, E.BISHOP, null, null],
			7: [null, E.PAWN, null, E.PAWN, E.PAWN, E.PAWN, null, null],
		}
	return cfg


# --- Shop helpers (mutate the army) ---
# Non-empty slots. The royal prince/king IS included -- the movement-compound
# cards (Globals.MOVEMENT_UPGRADES) specifically target it (Prince -> Royal
# Knight/Bishop/Rook/Queen), and all of those stay "royal": true, so it's an
# upgrade, not the "sell/lose your king" case this used to guard against.
func army_slots():
	var slots := []
	for rank in army:
		for file in army[rank].size():
			var cell = army[rank][file]
			if cell == null:
				continue
			var piece = cell["piece"] if cell is Dictionary else cell
			slots.append({"rank": rank, "file": file, "piece": piece})
	return slots


func _cell_dict(rank, file):
	var cell = army[rank][file]
	return cell.duplicate() if cell is Dictionary else {"piece": cell}


func set_material(rank, file, material):
	var d = _cell_dict(rank, file)
	d["material"] = material
	army[rank][file] = d


func add_modifier(rank, file, modifier):
	var d = _cell_dict(rank, file)
	var mods = d.get("modifiers", []).duplicate()
	if modifier not in mods:
		mods.append(modifier)
	d["modifiers"] = mods
	army[rank][file] = d


func transform(rank, file, new_piece):
	var d = _cell_dict(rank, file)
	d["piece"] = new_piece
	army[rank][file] = d
