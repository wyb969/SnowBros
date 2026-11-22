extends RefCounted
## Every cel in the actor atlas uses the same foot and turn pivot.
const TEXTURE = preload("res://assets/snowbro.png")
const CELL_SIZE = 40
const COLUMNS = 8
const FEET = Vector2(20, 34)
const TURN_PIVOT = Vector2(20, 22)
const PIXEL_SIZE = 2.0

enum Frame {
	IDLE, BREATHE, BLINK, WALK = 3, PUSH = 9,
	THROW_COIL = 13, THROW_OUT, THROW_BACK,
	KICK_COIL, KICK_OUT, KICK_BACK, LAND_LOW, LAND, FALL, TURN, RIDE = 46, TURN_THROW = 47, TURN_THROW_REVERSE = 71
}
const TURN_FRAMES = 24

static func region(frame: int) -> Rect2:
	@warning_ignore("integer_division")
	return Rect2((frame % COLUMNS) * CELL_SIZE, (frame / COLUMNS) * CELL_SIZE, CELL_SIZE, CELL_SIZE)

static func turn_frame(angle: float, aim: int = 0) -> int:
	var first := Frame.TURN
	if aim > 0: first = Frame.TURN_THROW
	elif aim < 0: first = Frame.TURN_THROW_REVERSE
	return first + posmod(roundi(angle / TAU * TURN_FRAMES), TURN_FRAMES)

static func ground_frame(actor: Dictionary, distance: float, elapsed: float, landing: float, impact: float) -> int:
	# The projectile or ball moves on the input tick, so show the extended
	# glove/boot immediately. Its recovery cels never gate input.
	if actor.attack > 0.0:
		if actor.get("attack_kind", "snow") == "kick":
			if actor.attack > 0.09: return Frame.KICK_OUT
			if actor.attack > 0.042: return Frame.KICK_COIL
			return Frame.KICK_BACK
		if actor.attack > 0.085: return Frame.THROW_OUT
		if actor.attack > 0.042: return Frame.THROW_BACK
		return Frame.THROW_COIL
	if not actor.ground:
		return Frame.FALL
	if landing > 0.0:
		return Frame.LAND_LOW if landing > 0.045 and impact > 0.55 else Frame.LAND
	if actor.pushing:
		return Frame.PUSH + int(distance / 7.0) % 4
	if absf(actor.v.x) > 1.0:
		return Frame.WALK + int(distance / 11.0) % 6
	if fmod(elapsed, 3.17) > 3.07:
		return Frame.BLINK
	return Frame.BREATHE if fmod(elapsed, 0.96) > 0.52 else Frame.IDLE
