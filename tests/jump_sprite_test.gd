extends SceneTree

const Sprite = preload("res://scripts/jump_sprite.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	var sheet := Image.new()
	check(sheet.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/snowbro.png")) == OK, "Original sprite atlas decodes.")
	var actor := {"attack": 0.0, "attack_kind": "snow", "ground": true, "pushing": false, "v": Vector2.ZERO}
	check(Sprite.turn_frame(0) == Sprite.turn_frame(TAU), "The turn returns to its takeoff cel.")
	var distinct := {}
	for index in Sprite.TURN_FRAMES:
		var angle := TAU * index / Sprite.TURN_FRAMES
		var frame := Sprite.turn_frame(angle)
		var turn := sheet.get_region(Rect2i(Sprite.region(frame)))
		var trimmed := turn.get_used_rect()
		check(trimmed.grow(1).intersection(Rect2i(0, 0, 40, 40)) == trimmed.grow(1), "Turn stays inside its cel.")
		distinct[hash(turn.get_data())] = true
		for aim in [-1, 1]:
			var armed := sheet.get_region(Rect2i(Sprite.region(Sprite.turn_frame(angle, aim))))
			check(armed.get_data() != turn.get_data(), "Airborne snow casts must visibly extend a glove.")
	check(distinct.size() == Sprite.TURN_FRAMES, "Each sampled angle has its own rasterized silhouette.")
	var upright := sheet.get_region(Rect2i(Sprite.region(Sprite.turn_frame(0))))
	var inverted := sheet.get_region(Rect2i(Sprite.region(Sprite.turn_frame(PI))))
	check(inverted.get_used_rect().size.y < upright.get_used_rect().size.y, "Hero draws knees in at apex.")
	check(upright.get_used_rect().size.y > upright.get_used_rect().size.x, "Takeoff silhouette is upright.")
	var atlas_bounds := Rect2i(Vector2i.ZERO, sheet.get_size())
	for frame in range(Sprite.Frame.TURN_THROW_REVERSE + Sprite.TURN_FRAMES):
		var cell := Rect2i(Sprite.region(frame))
		check(atlas_bounds.intersection(cell) == cell, "Cel lies inside atlas.")
		check(sheet.get_region(cell).get_used_rect().has_area(), "Every selectable cel contains pixel art.")
	var idle := Sprite.ground_frame(actor, 0, 0, 0, 0)
	actor.v.x = -200.0
	var step_a := Sprite.ground_frame(actor, 0, 0, 0, 0)
	var step_b := Sprite.ground_frame(actor, 22, 0, 0, 0)
	check(step_a != idle and step_a != step_b, "Walking advances with distance in either direction.")
	actor.pushing = true
	check(Sprite.ground_frame(actor, 0, 0, 0, 0) == Sprite.Frame.PUSH, "Pushing braces the hands.")
	actor.attack = 0.15
	check(Sprite.ground_frame(actor, 0, 0, 0, 0) == Sprite.Frame.THROW_OUT, "Snow leaves an extended glove on the attack tick.")
	actor.attack_kind = "kick"
	check(Sprite.ground_frame(actor, 0, 0, 0, 0) == Sprite.Frame.KICK_OUT, "Kicking extends a boot on contact.")
	actor.attack = 0.02
	check(Sprite.ground_frame(actor, 0, 0, 0, 0) == Sprite.Frame.KICK_BACK, "Kicking has a recovery silhouette.")
	actor.attack = 0.0
	actor.ground = false
	check(Sprite.ground_frame(actor, 0, 0, 0, 0) == Sprite.Frame.FALL, "Walking off a ledge opens the arms.")
	actor.ground = true
	check(Sprite.ground_frame(actor, 0, 0, 0.08, 0.8) == Sprite.Frame.LAND_LOW, "Hard contact compresses the knees.")
	check(Sprite.ground_frame(actor, 0, 0, 0.02, 0.8) == Sprite.Frame.LAND, "Legs extend through the end of landing.")
	for frame in [Sprite.Frame.IDLE, Sprite.Frame.LAND, Sprite.Frame.LAND_LOW, Sprite.Frame.KICK_OUT]:
		var box := sheet.get_region(Rect2i(Sprite.region(frame))).get_used_rect()
		check(box.end.y == int(Sprite.FEET.y), "At least one boot remains planted.")
	check_speed_boots(sheet)
	print("%d sprite checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check_speed_boots(normal: Image):
	var sheet := Image.new()
	check(sheet.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/snowbro_speed.png")) == OK, "Red-potion sprite atlas decodes.")
	var actor := {"attack": 0.0, "ground": true, "v": Vector2.ZERO, "pushing": false}
	var idle := Sprite.ground_frame(actor, 0, 0, 0, 0)
	for frame in range(Sprite.Frame.TURN_THROW_REVERSE + Sprite.TURN_FRAMES):
		var phases := {}
		var valid_bounds := true
		var upper_matches := true
		var foot_planted := true
		var original := normal.get_region(Rect2i(Sprite.region(frame)))
		for i in Sprite.SPEED_PHASES:
			var sample_time := (i + 0.5) / Sprite.SPEED_FRAMES_PER_SECOND
			var cell := Rect2i(Sprite.speed_region(frame, sample_time))
			valid_bounds = valid_bounds and Rect2i(Vector2i.ZERO, sheet.get_size()).intersection(cell) == cell
			var sample := sheet.get_region(cell)
			phases[hash(sample.get_data())] = true
			if frame < Sprite.Frame.FALL:
				upper_matches = upper_matches and sample.get_region(Rect2i(0, 0, 40, 21)).get_data() == original.get_region(Rect2i(0, 0, 40, 21)).get_data()
				foot_planted = foot_planted and sample.get_used_rect().end.y == int(Sprite.FEET.y)
		check(valid_bounds and phases.size() == Sprite.SPEED_PHASES, "Four leg poses stay distinct for action cel %d." % frame)
		if frame < Sprite.Frame.FALL:
			check(upper_matches and foot_planted, "Speed preserves the grounded action and sole contact for cel %d." % frame)
	var cycle: float = Sprite.SPEED_PHASES / Sprite.SPEED_FRAMES_PER_SECOND
	check(idle == Sprite.ground_frame(actor, 0, cycle * 0.5, 0, 0) and Sprite.speed_region(idle, 0) != Sprite.speed_region(idle, cycle * 0.5), "A stationary red-potion player cycles boots independently of an unchanged idle cel.")
	check(Sprite.speed_region(idle, 0) == Sprite.speed_region(idle, cycle), "The fast gait loops at its configured cadence.")
