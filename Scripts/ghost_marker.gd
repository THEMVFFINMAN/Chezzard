class_name GhostMarker
extends Node2D

# Marks a blank, clickable square during shop board-testing (e.g. a Grow Pawn
# target) that has no real piece sprite to click on.
var size := 16.0


func _draw() -> void:
	var c = Color(0.3, 0.9, 0.4, 0.55)
	draw_line(Vector2(-size, 0), Vector2(size, 0), c, 3.0)
	draw_line(Vector2(0, -size), Vector2(0, size), c, 3.0)
