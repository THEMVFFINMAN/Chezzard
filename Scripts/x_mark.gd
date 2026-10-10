class_name XMark
extends Node2D

# Crude red X drawn over a board piece that isn't a legal target for the
# card currently being tested (shop.gd's test-queue flow). Placeholder
# until there's real icon art.

var size := 16.0


func _draw() -> void:
	var c = Color(0.9, 0.1, 0.1, 0.9)
	draw_line(Vector2(-size, -size), Vector2(size, size), c, 4.0)
	draw_line(Vector2(-size, size), Vector2(size, -size), c, 4.0)
