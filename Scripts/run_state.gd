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
var veteran_kills := {}    # army origin square -> captures made by a "veteran" piece this run
var dice_used_floor := -1  # Loaded Dice: the floor whose shop already used its free reroll

# --- AI difficulty (Elo) ---
# A player preference, not run state -- deliberately NOT reset by start_run()/
# start_test_shop(), same as a settings value would persist across runs. No
# picker UI yet (see Globals.ELO_TIERS); these just need to already work once
# one exists. "manual" reads manual_elo instead of an ELO_TIERS entry.
var difficulty_tier := "intermediate"  # a Globals.ELO_TIERS key, or "manual"
var manual_elo := 1200                 # only read when difficulty_tier == "manual"


func start_run():
	in_run = true
	test_mode = false
	test_hotseat = false
	floor = 1
	gold = 0
	lost_origins = []
	relics = []
	veteran_kills = {}
	dice_used_floor = -1
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
	veteran_kills = {}
	dice_used_floor = -1
	army = _default_army()
	gold_changed.emit(gold)


func advance():
	floor += 1
	if has_relic("war_chest"):
		add_gold(15, "war_chest")
	# Field Medic: advance() only runs after a won battle, so this is "after
	# each win" -- one random lost slot comes back as a Short Pawn.
	if has_relic("field_medic") and not lost_origins.is_empty():
		var slot = lost_slots()[randi() % lost_origins.size()]
		add_pawn(slot["rank"], slot["file"])
		print("[run] Field Medic restored the slot at %s" % slot["origin"])


# Veteran modifier: a capture made by the piece from this army slot.
func add_veteran_kill(origin):
	if origin != "":
		veteran_kills[origin] = veteran_kills.get(origin, 0) + 1


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


# A piece permanently removed from the run army (e.g. a blood piece that died,
# or a brittle-curse shatter). The sole choke point for every permanent-loss
# source in the game, which is what makes Insurance Policy a single check
# here instead of needing a separate guard at each call site: it consumes
# itself (removed from `relics` entirely, not just "used this floor") the
# first time ANY of them would otherwise take effect, then never helps again.
func lose_piece(origin):
	if origin == "" or origin in lost_origins:
		return
	if has_relic("insurance_policy"):
		relics.erase("insurance_policy")
		print("[run] Insurance Policy saved the piece from %s (relic consumed)" % origin)
		return
	lost_origins.append(origin)
	veteran_kills.erase(origin)  # whatever refills this slot later starts fresh
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
		# apply_config() reads the per-side keys, not a single "head_of_snake";
		# a floor setting it gets it on both sides.
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
	if has_relic("opening_book"):
		cfg["opening_book"] = 1  # one bonus move = 2 moves before the enemy's first


# --- Opponent effects (Globals.EFFECTS) ---
# Mutates a battle config's ENEMY side only -- the player's own army (and its
# "Big"/movement-upgraded Frankenstein pieces) is never touched. Not wired
# into _floor_config()/current_battle() yet (no floor picks one of these on
# its own) -- this is just the pool and its mechanics, ready for whenever
# floor selection (random roll vs. fixed per floor) gets figured out. Call
# manually for now, e.g. RunState.apply_effect(cfg, "twin_crown") right after
# current_battle()/test_battle() builds cfg and before it's handed to the board.
func apply_effect(cfg, effect_id):
	if has_relic("cursebreaker") and randf() < 0.5:
		print("[run] Cursebreaker: %s fizzled" % effect_id)
		return
	match effect_id:
		"twin_crown":
			_apply_twin_crown_effect(cfg)
		"chess960":
			_apply_chess960_effect(cfg)
		"cold_comfort":
			cfg["draws_favor_black"] = true
		"hollow_crown":
			cfg["brittle_curse"] = true
		"reversed_siege":
			cfg["disable_white_castling"] = true
		"mirror_match":
			cfg["flip_white_king_queen"] = true
		"clipped_wings":
			_apply_clipped_wings_effect(cfg)


# Twin Crown: finds the enemy's actual Queen/King files on whichever rank this
# floor's back rank lives on, then mirrors a second King onto the opposite
# side of the Queen from the real one -- same mirrored-offset rule the player-
# facing version used, just aimed at cfg["layout"]["black"] instead of
# RunState.army. Overwrites whatever's on that square already (nothing, on
# the early "dwarf" floors; a Bishop or Archbishop on later ones) -- same
# one-way trade-off as any other board mutation in this file. Bumps
# royal_count so VariantBuilder keeps both enemy Kings registered as
# pseudo-royal (a shared royal_count only needs to be >= the larger side's
# count, so this doesn't loosen anything for the player's own royal(s)).
func _apply_twin_crown_effect(cfg):
	var E = Globals.Piece_Type_ENUMs
	var black = cfg["layout"].get("black", {})
	var back_rank = -1
	var queen_file = -1
	var king_file = -1
	for rank in black:
		var row = black[rank]
		if not (row is Array):
			continue
		for f in row.size():
			if row[f] == E.QUEEN:
				queen_file = f
				back_rank = rank
			elif row[f] == E.KING:
				king_file = f
	if queen_file == -1 or king_file == -1:
		return  # this floor's enemy has no Queen/King pair to mirror off of
	var mirror_file = queen_file - (king_file - queen_file)
	if mirror_file < 0 or mirror_file >= black[back_rank].size():
		return
	black[back_rank][mirror_file] = E.KING
	cfg["royal_count"] = max(cfg.get("royal_count", 1), 2)


# Fischer's Gambit: replaces the enemy's own King-bearing back rank with a
# freshly randomized Chess960 arrangement (GameModes' own generator) --
# literal Rook/Knight/Bishop/Queen/King only, so this discards any
# floor-specific pieces on that rank (e.g. the Wizard floor's Archbishops) --
# whoever wires floor selection should decide whether that floor is even
# eligible. The player's side is untouched; board.gd's castling-file tracking
# is already per-side independent (see game_modes.gd's own Chess960 mode), so
# this coexists with whatever non-standard army the player is fielding.
func _apply_chess960_effect(cfg):
	var E = Globals.Piece_Type_ENUMs
	var black = cfg["layout"].get("black", {})
	var back_rank = -1
	for rank in black:
		if black[rank] is Array and E.KING in black[rank]:
			back_rank = rank
			break
	if back_rank == -1:
		return  # this floor's enemy has no King-bearing back rank to shuffle
	black[back_rank] = GameModes._random_960_back_rank()
	cfg["chess960"] = true
	cfg["rules"] = cfg.get("rules", []) + ["chess960 = true"]


# Clipped Wings: every compound piece on the PLAYER's side (cfg["layout"]["white"],
# not "black" like the two effects above) gets replaced with
# Globals.simplify_target()'s single-strongest-component result. Battle-scoped
# only, like every other effect here -- this reads/rebuilds the battle config's
# layout, never RunState.army itself, so next floor your Queen is still a Queen
# regardless of what happened to it this fight. Cells carrying a material/
# modifier dict are duplicated before their "piece" field is swapped, so this
# never mutates the actual persistent army cell out from under RunState.
func _apply_clipped_wings_effect(cfg):
	var white = cfg["layout"].get("white", {})
	for rank in white:
		var row = white[rank]
		if not (row is Array):
			continue
		for f in row.size():
			var cell = row[f]
			var piece_type = cell["piece"] if cell is Dictionary else cell
			if piece_type == null:
				continue
			var simplified = Globals.simplify_target(piece_type)
			if simplified == piece_type:
				continue  # not a compound (or royal) -- left alone
			if cell is Dictionary:
				var d = cell.duplicate()
				d["piece"] = simplified
				row[f] = d
			else:
				row[f] = simplified


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


# Escalating enemy per floor; floor 10 is the Wizard (placeholder -- will
# eventually rotate through rulesets at random).
func _floor_config(f):
	var E = Globals.Piece_Type_ENUMs
	var cfg := {"name": "Floor %d" % f}
	if f >= FLOOR_COUNT:
		cfg["name"] = "The Wizard"
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


# --- AI difficulty (Elo) ---
# Target engine Elo for floor f (1-FLOOR_COUNT): linearly ramps the chosen
# tier's start->end across the run (floor 1 = the tier's low end, floor
# FLOOR_COUNT = its high end), then layers a FRESH +/-100 roll on top --
# rerolled every single floor, never one offset locked in for the whole run.
# This is the nominal/displayable target; it is NOT yet clamped to what the
# engine will actually accept -- see elo_to_uci_elo() for that.
func floor_elo(f):
	var start
	var end
	if difficulty_tier == "manual":
		end = manual_elo
		start = manual_elo - Globals.MANUAL_ELO_SPAN
	else:
		var tier = Globals.ELO_TIERS.get(difficulty_tier, Globals.ELO_TIERS["intermediate"])
		start = tier["start"]
		end = tier["end"]
	var t = float(f - 1) / float(FLOOR_COUNT - 1)
	var target = lerp(float(start), float(end), t)
	return int(round(target)) + (randi() % 201 - 100)  # fresh +/-100 roll


# Clamp a target Elo to what Fairy-Stockfish's own UCI_Elo option actually
# accepts (500-2850 -- see native/Fairy-Stockfish/src/ucioption.cpp). Called
# right before the value is sent to the engine, NOT baked into floor_elo()
# itself, so a tier's nominal numbers (e.g. Beginner's "300") stay meaningful
# to display even though the engine will only ever really play as weak as 500.
func elo_to_uci_elo(target_elo):
	return clampi(target_elo, 500, 2850)


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
