extends StaticBody2D

const IRON_MATERIAL = preload("res://Assets/iron_material.tres")

var white = true
var piece_type
var has_mouse = false
var chess_position = ""
var picked_up = false

var default_location = Vector2.ZERO

var previous_chess_position = ""

var SPEED = 50

var activated = false

var board

var dead_position = null

var dead = false

var promotion_piece = ""
var select_promotion_piece = false

# Material flag (e.g. "gold", "glass", "blood"); "" = plain. Drives the recolor
# shader and (later) the economy/risk effects in Globals.MATERIAL_EFFECTS.
# (Named piece_material to avoid CanvasItem's built-in "material" property.)
var piece_material = ""

# Modifier rule tags (e.g. "racist", "time1", "double") — separate from material,
# can stack. See Globals.MODIFIERS. Mechanics are WIP; this records the flags.
var piece_modifiers = []

# Ply count (board.moves.size()) at/after which a timed piece may move again.
var cooldown_until = 0

# The square this piece started the battle on — its slot in the run army.
var origin = ""

func delete_self():
	dead_position = global_position
	dead = true
	global_position= Vector2(-200, -200)
	if self not in get_parent().captured_pieces:
		get_parent().captured_pieces.append(self)

var legal_moves = []

func add_promotion_piece(piece):
	if piece not in promotion_piece:
		promotion_piece += piece
	select_promotion_piece = true


func add_legal_move(legal_move):
	if legal_move not in legal_moves:
		if !board.check_wall(legal_move):
			legal_moves.append(legal_move)


func initialize(is_white, piece_sprite, chess_location, _piece_type, _global_position):
	white = is_white
	piece_type = _piece_type
	chess_position = chess_location
	get_node("Sprite2D").play(piece_sprite)
	global_position = _global_position
	if is_white:
		add_to_group("white_pieces")
	else:
		add_to_group("black_pieces")

func _ready():
	board = get_parent()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# Hide leftover debug overlays.
	get_node("Label").visible = false
	get_node("Label2").visible = false
	# Draw modifier overlays (cooldown badge / racist bar) on top of the sprite.
	get_node("Sprite2D").show_behind_parent = true
	# Apply the recolor shader for this piece's material (iron pieces get it via
	# their type even without an explicit material flag set).
	_apply_material_visual()

# Picks the right recolor ShaderMaterial: an explicit material flag wins,
# otherwise iron pieces fall back to the iron material.
func _apply_material_visual():
	if piece_material != "" and Globals.MATERIALS.has(piece_material):
		get_node("Sprite2D").material = Globals.MATERIALS[piece_material]
	elif Globals.is_iron(piece_type):
		get_node("Sprite2D").material = IRON_MATERIAL

# Runtime hook (upgrades / tests): set a piece's material and refresh its look.
func apply_material(new_material):
	piece_material = new_material
	_apply_material_visual()

# Set the piece's modifier tags (accepts a single name or a list).
func apply_modifiers(mods):
	piece_modifiers = mods.duplicate() if mods is Array else [mods]

func has_modifier(modifier_name):
	return modifier_name in piece_modifiers


# --- Modifier overlays (rough placeholders; redrawn each turn by the board) ---
func _draw():
	# Cooldown badge: black number in a white circle with a black outline. Top-left
	# for jumpers, top-right otherwise.
	var turns = _cooldown_turns()
	if turns > 0:
		var c = Vector2(-12, -12) if _is_jumper() else Vector2(12, -12)
		draw_circle(c, 6.0, Color(1, 1, 1))
		draw_arc(c, 6.0, 0.0, TAU, 24, Color(0, 0, 0), 1.5)
		draw_string(ThemeDB.fallback_font, c + Vector2(-3, 4), str(turns),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0))
	# Racist: two bars under the piece, in the colour it can move on.
	if has_modifier("racist"):
		var bar = Color(0.95, 0.95, 0.95) if _racist_light() else Color(0.12, 0.12, 0.12)
		draw_rect(Rect2(-14, 13, 28, 2), bar)
		draw_rect(Rect2(-14, 16, 28, 2), bar)

func _cooldown_turns():
	if board == null:
		return 0
	var remaining = cooldown_until - board.moves.size()
	return int((remaining + 1) / 2) if remaining > 0 else 0

func _is_jumper():
	var E = Globals.Piece_Type_ENUMs
	return piece_type in [E.KNIGHT, E.CAMEL, E.ZEBRA, E.ALFIL, E.DABBABA, E.GIRAFFE, E.WILDEBEEST, E.BUFFALO, E.KNIGHTRIDER]

func _racist_light():
	if board == null:
		return true
	return board._square_color(chess_position) == 0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:


	if has_mouse and Input.is_action_pressed("left_click") and !picked_up and legal_moves.size() > 0:

		for move in legal_moves:
			board.get_square(move).get_node("CollisionShape2D").disabled = false
			board.get_square(move).get_node("premove").visible = true

		picked_up = true
		activated = true

		default_location = global_position

		z_index = 15

		board.held_piece = self
		board.freeze_pieces()
		board.holding_piece = true

	if picked_up:
		if board.holding_piece:
			global_position = get_global_mouse_position()
		if !Input.is_action_pressed("left_click"):
			# A square that catches a legal drop sets holding_piece to null
			# (and runs board.move). If it's still set, the piece was released
			# on a non-legal square (e.g. its own) — treat it as a cancel.
			var move_made = board.holding_piece == null
			picked_up = false
			z_index = 5
			board.holding_piece = false
			board.last_held_piece = board.held_piece
			board.held_piece = null

			get_node("CollisionShape2D").disabled = true

			if not move_made:
				board.cancel_pickup(self)


func _on_mouse_entered():
	if piece_type == Globals.Piece_Type_ENUMs.WALL:
		return

	has_mouse = true


func _on_mouse_exited():
	if piece_type == Globals.Piece_Type_ENUMs.WALL:
		return

	has_mouse = false
