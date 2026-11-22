extends Node2D

const FONT = preload("res://assets/arcade.ttf")
const MONSTER_POSES = preload("res://assets/monster_poses.png")
const ACTOR_SPRITE = preload("res://scripts/jump_sprite.gd")
const ICE = Color("b7f4ff")
const WHITE = Color("effcff")
# Gameplay calibration, not measured FC constants. See docs/VIDEO_ANALYSIS.md.
const LOGIC_WIDTH = 960.0
const PLAYER_MOVE_SPEED = LOGIC_WIDTH*.22
const PLAYER_RED_SPEED = PLAYER_MOVE_SPEED*1.3
const SNOW_MAX = 6
const BALL_RADIUS = 24.0
const RIDE_ENTRY_INVINCIBILITY = .75
const PUSH_SPEED = 68.0
const RED_PUSH_SPEED = 110.0
const ROLL_SPEED = LOGIC_WIDTH*1.27
const ROLL_DROP_SPEED = 620.0
const BALL_FOOT_MARGIN = 12.0
const STACK_DISTANCE = 14.0
const BALL_FRICTION = 2.0
const BALL_WALL_RESTITUTION = 0.97
const BALL_ENEMY_RETENTION = 0.995
const SHOT_SPEED = LOGIC_WIDTH*1.95
const SHOT_CRUISE_TIME = .10
const SHOT_LONG_CRUISE_TIME = .20
const SHOT_BRAKE_TIME = .20
const SHOT_END_SPEED_RATIO = .12
const SHOT_CRUISE_RISE = LOGIC_WIDTH*.0015
const SHOT_SINK = LOGIC_WIDTH*.025
const SHOT_DRIFT_TIME = .46
const SHOT_DRIFT_SPEED_Y = 316.0
const SHOT_FLUTTER_START = .66
const SHOT_FLUTTER_AMPLITUDE = .8
# Fitting start from the user's normalized measurements, using feet position.
const PLAYER_JUMP_HEIGHT = LOGIC_WIDTH*.16
const PLAYER_APEX_TIME = .36
const PLAYER_JUMP_SPEED = 2.0*PLAYER_JUMP_HEIGHT/PLAYER_APEX_TIME
const PLAYER_GRAVITY = 2.0*PLAYER_JUMP_HEIGHT/(PLAYER_APEX_TIME*PLAYER_APEX_TIME)
# A slightly quicker fall gives touchdown weight without changing the measured arc up.
const PLAYER_FALL_TIME = .32
const PLAYER_FALL_GRAVITY = 2.0*PLAYER_JUMP_HEIGHT/(PLAYER_FALL_TIME*PLAYER_FALL_TIME)
const PLAYER_JUMP_BUFFER = 5.0/60.0
const PLAYER_LEDGE_GRACE = 3.0/60.0
const PLAYER_LANDING_POSE = .085
# Monster horns and tumbling enemies each need room above the playfield.
const ROOM_TOP = 96.0
const ENEMY_CEILING = ROOM_TOP + 48.0
const DEFEATED_CEILING = ROOM_TOP + 56.0
var platforms: Array[Rect2] = [Rect2(36,492,888,28),Rect2(36,388,240,20),Rect2(360,388,240,20),Rect2(684,388,240,20),Rect2(105,280,280,20),Rect2(575,280,280,20),Rect2(36,172,240,20),Rect2(360,172,240,20),Rect2(684,172,240,20)]
var player: Dictionary
var enemies: Array = []
var shots: Array = []
var particles: Array = []
var gifts: Array = []
var float_text: Array = []
var defeated: Array = []
var chains = {}
var next_chain = 1
var next_shot = 0
var combo_time = 0.0
var practice_case = 0
var jump_active = false
var jump_angle = 0.0
var jump_spin_dir = 1
var jump_buffer = 0.0
var ledge_grace = 0.0
var landing_pose = 0.0
var landing_strength = 0.0
var stride_distance = 0.0
var stage_scroll_y := 0.0
var score = 0
var high_score = 40000
var lives = 3
var state = "title"
var clock = 0.0
var cooldown = 0.0
var invincible = 0.0
var elapsed = 0.0
var paused = false
var muted = false
var touch_left = false
var touch_right = false
var touch_fire = false
var jump_request = false
var touch_inputs = {}
var practice = false
var speed_up = false
var power_up = false
var range_up = false
var notice = ""
var notice_time = 0.0
var hit_flash = 0.0
var combo = 0
var pair_contacts = {}
var music: AudioStreamPlayer
var web_mode = OS.has_feature("web")
var web_axis = 0.0
var web_shell
var web_callback
var web_state_elapsed = 0.0

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color("071729"))
	if web_mode: Engine.max_fps=60
	setup_audio()
	reset()
	state = "title"
	if OS.has_feature("web"):
		web_shell=JavaScriptBridge.get_interface("SnowBro")
		if web_shell!=null:
			web_callback=JavaScriptBridge.create_callback(_web_command)
			web_shell.attach(web_callback)

func setup_audio():
	# Web audio is owned by the page. Never start the engine's audio driver
	# or create browser-side sample players on the first touch.
	if web_mode: return
	music=AudioStreamPlayer.new()
	music.stream=load("res://assets/forest.ogg")
	music.volume_db=-18
	music.finished.connect(func(): music.play())
	add_child(music)
	build_sounds()

func start_audio():
	if not web_mode and is_instance_valid(music): music.play()

func release_controls():
	web_axis=0.0; touch_left=false; touch_right=false; touch_fire=false; jump_request=false; jump_buffer=0.0; touch_inputs.clear()

func _web_command(arguments):
	if arguments.is_empty(): return
	var parser=JSON.new()
	if parser.parse(str(arguments[0]))!=OK: return
	var data=parser.data
	if not data is Dictionary: return
	match str(data.get("type","")):
		"input":
			web_axis=clampf(float(data.get("axis",0)), -1.0, 1.0)
			touch_fire=bool(data.get("fire",false))
		"jump":
			if state=="play" and not paused: jump_request=true
		"start": reset(); start_audio()
		"restart": reset(practice); start_audio()
		"practice": reset(true,clampi(int(data.get("case",0)),0,3))
		"pause": paused=bool(data.get("paused",true)); release_controls()
		"mute":
			muted=bool(data.get("muted",true))
			if is_instance_valid(music): music.volume_db=-80 if muted else -18
		"release": release_controls()

func sync_web_state(dt):
	if web_shell==null: return
	web_state_elapsed+=dt
	if web_state_elapsed<.1: return
	web_state_elapsed=0
	web_shell.update(JSON.stringify({"state":state,"paused":paused,"practice":practice,"case":practice_case,"score":score,"lives":lives}))

func new_enemy(pos, id, snow=0):
	return {"id":id,"p":pos,"v":Vector2.ZERO,"dir":1 if id%2==0 else -1,"ground":true,"snow":snow,"roll":false,"thaw":12.0,"jump":2.0+id*0.4,"chain":0,"spin":0.0,"impact":0.0,"flash":0.0,"bounces":0,"floor_bounces":0,"stack_tone":0,"travel":[],"credited":false,"dead":false,"chain_id":0,"previous":pos}

func reset(training=false, case_index=-1):
	if case_index>=0: practice_case=case_index%4
	practice=training
	release_controls()
	player = {"p":Vector2(130,492),"v":Vector2.ZERO,"dir":1,"ground":true,"ride":-1,"ride_lock":0.0,"standing":-1,"pushing":false,"attack":0.0,"momentum":0.0}
	enemies.clear(); shots.clear(); particles.clear(); gifts.clear(); float_text.clear(); pair_contacts.clear(); defeated.clear(); chains.clear(); next_chain=1; next_shot=0; combo_time=0
	jump_active=false; jump_angle=0; jump_spin_dir=1
	ledge_grace=0.0; landing_pose=0.0; landing_strength=0.0; stride_distance=0.0
	if practice:
		match practice_case:
			0:
				for i in 2: enemies.append(new_enemy(Vector2(295+i*155,492),i,SNOW_MAX))
				enemies.append(new_enemy(Vector2(760,492),2))
				enemies.append(new_enemy(Vector2(480,388),3,SNOW_MAX))
				for i in 3: gifts.append({"p":Vector2(570+i*45,492),"life":999.0,"kind":["red","blue","yellow"][i]})
			1:
				player.p=Vector2(225,492)
				enemies.append(new_enemy(Vector2(280,492),0,SNOW_MAX))
				for i in 4: enemies.append(new_enemy(Vector2(420+i*110,492),i+1,i%3))
			2:
				player.p=Vector2(410,172)
				var ball_x := [465, 500, 566]
				for i in ball_x.size():
					enemies.append(new_enemy(Vector2(ball_x[i],172),i,SNOW_MAX))
				gifts.append({"p":Vector2(365,172),"life":999.0,"kind":"red"})
			3:
				player.p=Vector2(180,492)
				enemies.append(new_enemy(Vector2(340,492),0,1))
				enemies.append(new_enemy(Vector2(600,388),1,2))
				gifts.append({"p":Vector2(245,492),"life":999.0,"kind":"blue"})
				gifts.append({"p":Vector2(720,492),"life":999.0,"kind":"yellow"})
	else:
		var spawns=[Vector2(180,172),Vector2(480,172),Vector2(780,172),Vector2(230,280),Vector2(720,280),Vector2(470,388)]
		for i in spawns.size(): enemies.append(new_enemy(spawns[i],i))
	score=0; lives=3; invincible=1.5; elapsed=0; paused=false; state="play"
	speed_up=false; power_up=false; range_up=false; combo=0; notice_time=0; hit_flash=0
	stage_scroll_y = 0.0
	position = Vector2.ZERO
	if practice: announce(["1: PUSH / STAND / BUMP / KICK","2: ONE BALL / FOUR TARGETS","3: RED POTION / PUSH TWO / TOP JUMP","4: SNOW ARC / BLUE SIZE / YELLOW LENGTH"][practice_case],4.0)

func announce(message, duration=1.6):
	notice=message; notice_time=duration

func key(k):
	return Input.is_physical_key_pressed(k)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ENTER and state != "play": reset(); start_audio()
		if event.physical_keycode == KEY_T: reset(not practice); start_audio()
		if event.physical_keycode == KEY_R: reset(practice); start_audio()
		if event.physical_keycode == KEY_Q and practice: reset(true,(practice_case+1)%4)
		if event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]: reset(true,event.physical_keycode-KEY_1)
		if event.physical_keycode in [KEY_P,KEY_ESCAPE]:
			paused = not paused
			release_controls()
		if event.physical_keycode == KEY_M:
			muted = not muted
			if is_instance_valid(music): music.volume_db = -80 if muted else -18
			if web_shell!=null: web_shell.setSound(not muted)
		if state=="play" and not paused and event.physical_keycode in [KEY_SPACE,KEY_W,KEY_UP]: jump_request=true
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if web_mode: return
		var finger=event.index if event is InputEventScreenTouch else -1
		if paused and event.pressed:
			paused=false; return
		if state!="play" and event.pressed:
			reset(); start_audio(); return
		if event.pressed:
			if practice and event.position.y>600 and event.position.x>800:
				reset(true,(practice_case+1)%4); return
			if event.position.y<90 and event.position.x>330 and event.position.x<640:
				reset(not practice); return
			if event.position.y>530:
				if event.position.x<150: touch_inputs[finger]="left"
				elif event.position.x<300: touch_inputs[finger]="right"
				elif event.position.x<740: jump_request=true
				else: touch_inputs[finger]="fire"
		else: touch_inputs.erase(finger)
		touch_left=touch_inputs.values().has("left"); touch_right=touch_inputs.values().has("right"); touch_fire=touch_inputs.values().has("fire")

func move_body(b,dt,gravity=1000.0):
	var old: Vector2=b.p
	b.v.y+=gravity*dt; b.p+=b.v*dt
	if b.p.y<ENEMY_CEILING:
		b.p.y=ENEMY_CEILING; b.v.y=maxf(b.v.y,0.0)
	b.ground=false
	if b.p.x<52: b.p.x=52; b.dir=1; b.v.x=absf(b.v.x)
	if b.p.x>908: b.p.x=908; b.dir=-1; b.v.x=-absf(b.v.x)
	if b.v.y>=0:
		for plat in platforms:
			if old.y<=plat.position.y+1 and b.p.y>=plat.position.y and b.p.x>plat.position.x-9 and b.p.x<plat.end.x+9:
				b.p.y=plat.position.y; b.v.y=0; b.ground=true; break

func burst(pos,color,n=12):
	for i in n: particles.append({"p":pos,"v":Vector2(randf_range(-120,120),randf_range(-190,20)),"life":randf_range(.3,.65),"color":color})

func award(points,pos):
	score+=points; high_score=maxi(high_score,score)
	float_text.append({"text":str(points),"p":pos,"life":1.0,"color":Color("ffda83")})

func credit_ball(e):
	if not e.credited: e.credited=true; award(500,e.p-Vector2(0,40))

func kick_ball(e, direction, chain_id=0):
	var vertical: float=e.v.y if not e.ground else 0.0
	e.roll=true; e.stack_tone=0; e.dir=direction; e.v=Vector2(direction*ROLL_SPEED,vertical)
	e.impact=0.65; e.impact_side=false; e.thaw=12; credit_ball(e)
	if chain_id==0:
		e.chain_id=next_chain; chains[next_chain]=0; next_chain+=1
	else: e.chain_id=chain_id
	play_sfx("kick")
	burst(e.p-Vector2(0,22),ICE,8)

func ball_before(a, b):
	if a.p.x == b.p.x: return a.id < b.id
	return a.p.x < b.p.x

func idle_ball_row(seed):
	if not seed.ground: return [seed]
	var row = []
	for ball in enemies:
		if not ball.dead and not ball.roll and ball.snow >= SNOW_MAX and ball.ground and is_equal_approx(ball.p.y, seed.p.y):
			row.append(ball)
	row.sort_custom(ball_before)
	return row

func tint_ball_row(row):
	var index := 0
	for i in row.size():
		if i == 0 or row[i].p.x - row[i-1].p.x > STACK_DISTANCE + .01:
			index = 0
		match index % 3:
			0: row[i].stack_tone = 0
			1: row[i].stack_tone = 1 if posmod(int(row[i].id), 2) == 0 else 2
			2: row[i].stack_tone = 3 - int(row[i-1].stack_tone)
		index += 1

func space_ball_row(row):
	# The wall constrains the whole row. A second pass only acts when the
	# forward pass would put the rightmost center outside the arena.
	var left_limit := 50.0
	for ball in row:
		ball.p.x = maxf(ball.p.x, left_limit)
		left_limit = ball.p.x + STACK_DISTANCE
	if not row.is_empty() and row.back().p.x > 910.0:
		var right_limit := 910.0
		for i in range(row.size()-1,-1,-1):
			row[i].p.x = minf(row[i].p.x, right_limit)
			right_limit = row[i].p.x - STACK_DISTANCE
	tint_ball_row(row)

func settle_idle_balls(balls):
	var rows = {}
	for ball in balls:
		ball.stack_tone = 0
		if ball.dead or ball.roll or not ball.ground: continue
		if not rows.has(ball.p.y): rows[ball.p.y] = []
		rows[ball.p.y].append(ball)
	for row in rows.values():
		if row.size() < 2: continue
		row.sort_custom(ball_before)
		space_ball_row(row)

func push_ball_group(seed, push_distance):
	var row = idle_ball_row(seed)
	space_ball_row(row)
	var direction := signf(push_distance)
	if direction < 0.0: row.reverse()
	var start: int = row.find(seed)
	var wall := 910.0 if direction > 0.0 else -50.0
	# Each ball ahead needs one visible rim's worth of space at the wall.
	var proposed := minf(seed.p.x * direction + absf(push_distance), wall - (row.size()-1-start) * STACK_DISTANCE)
	for i in range(start, row.size()):
		var ball = row[i]
		var old_x: float = ball.p.x
		if old_x * direction > proposed + .01: break
		ball.p.x = maxf(old_x * direction, proposed) * direction
		ball.spin += (ball.p.x-old_x) / BALL_RADIUS
		ball.thaw = 12.0
		proposed = ball.p.x * direction + STACK_DISTANCE
	if direction < 0.0: row.reverse()
	tint_ball_row(row)

func kick_stack(seed,direction):
	player.ride_lock = maxf(player.ride_lock, .12)
	var row = idle_ball_row(seed)
	space_ball_row(row)
	var start: int = row.find(seed)
	var first := start
	var last := start
	while first > 0 and row[first].p.x - row[first-1].p.x <= STACK_DISTANCE + .01:
		first -= 1
	while last+1 < row.size() and row[last+1].p.x - row[last].p.x <= STACK_DISTANCE + .01:
		last += 1
	kick_ball(seed,direction)
	for i in range(first,last+1):
		if i != start: kick_ball(row[i],direction,seed.chain_id)

func ball_impact(e, strength, contact_normal = Vector2.ZERO):
	e.impact = clampf(strength, .2, 1.0)
	e.impact_side = absf(contact_normal.x) > .5
	if contact_normal == Vector2.ZERO:
		burst(e.p - Vector2(0,22), ICE, int(4 + strength * 6))
		return
	var contact: Vector2 = e.p - Vector2(0, BALL_RADIUS) + contact_normal * (BALL_RADIUS - 3.0)
	for i in int(4 + strength * 4):
		var spray: Vector2 = -contact_normal * randf_range(55, 145)
		spray += contact_normal.orthogonal() * randf_range(-92, 35) + Vector2.UP * 55
		particles.append({"p":contact,"v":spray,"life":randf_range(.16,.32),"color":ICE})

func support_at(pos,margin):
	for plat in platforms:
		if absf(pos.y-plat.position.y)<1.0 and pos.x>plat.position.x-margin and pos.x<plat.end.x+margin: return plat
	return null

func first_landing(old,next,margin):
	if next.y<old.y: return null
	var best=null
	var best_time=INF
	for plat in platforms:
		var y: float=plat.position.y
		if old.y>y+1.0 or next.y<y: continue
		if absf(old.y-y)<1.0 and (next.x<=plat.position.x-margin or next.x>=plat.end.x+margin): continue
		var t: float=clampf((y-old.y)/maxf(next.y-old.y,.0001),0,1)
		var x: float=lerpf(old.x,next.x,t)
		if x>plat.position.x-margin and x<plat.end.x+margin and t<best_time:
			best=plat; best_time=t
	return best

func ball_velocity(e, dt) -> Vector2:
	var velocity: Vector2 = e.v
	if e.ground:
		velocity.x = move_toward(velocity.x, 0.0, (BALL_FRICTION if e.roll else 380.0) * dt)
	if e.roll and velocity.y >= 0.0:
		var next_foot: Vector2 = e.p + Vector2(velocity.x * dt, 0.0)
		if not e.ground or support_at(next_foot, BALL_FOOT_MARGIN) == null:
			velocity.y = maxf(velocity.y, ROLL_DROP_SPEED)
	velocity.y += 1000.0 * dt
	return velocity

func advance_ball(e, dt, from_time, to_time):
	var old: Vector2 = e.p
	e.v = ball_velocity(e, dt)
	e.p += e.v * dt
	if e.p.y<ENEMY_CEILING:
		e.p.y=ENEMY_CEILING; e.v.y=maxf(e.v.y,0.0)
	e.ground = false
	if e.v.y >= 0.0:
		var platform = first_landing(old, e.p, BALL_FOOT_MARGIN)
		if platform != null:
			var landing_speed: float = e.v.y
			e.p.y = platform.position.y
			e.v.y = -landing_speed * .18 if not e.roll and landing_speed > 180.0 else 0.0
			e.ground = e.v.y == 0.0 and support_at(e.p, BALL_FOOT_MARGIN) != null
			if landing_speed > 180.0: ball_impact(e, .3)
	if e.roll:
		e.travel.append([from_time, to_time, old, e.p])
		if e.ground and absf(e.v.x) < 65.0: e.roll = false
	e.spin += (e.p.x - old.x) / BALL_RADIUS
	e.impact = move_toward(e.impact, 0.0, dt * 5.0)

func move_ball(e, dt):
	advance_snowballs([e], [], dt)

func hit_ball_wall(e, wall_x):
	e.p.x = wall_x
	if not e.roll:
		e.v.x = 0.0
		return
	e.v.x *= -BALL_WALL_RESTITUTION
	e.dir = signf(e.v.x)
	e.bounces += 1
	if e.ground and not platforms.any(func(plat): return plat.position.y > e.p.y + 1.0):
		e.floor_bounces += 1
	ball_impact(e, .65, Vector2(-e.dir, 0))
	if e.floor_bounces >= 2 or e.bounces >= 15:
		e.dead = true
		burst(e.p - Vector2(0,22), WHITE)

# Time on the moving relative segment when the two circular bodies first touch.
# An overlap at the start counts, including a ball kicked next to a target.
func contact_fraction(offset: Vector2, motion: Vector2, radius: float) -> float:
	var outside := offset.length_squared() - radius * radius
	if outside <= 0.0: return 0.0
	var travel_squared := motion.length_squared()
	var toward := -offset.dot(motion)
	if travel_squared < .000001 or toward <= 0.0: return INF
	var discriminant := toward * toward - travel_squared * outside
	if discriminant < 0.0: return INF
	var at := outside / (toward + sqrt(discriminant))
	return at if at <= 1.0 else INF

func pair_key(a, b) -> String:
	return "%d:%d" % [mini(a.id, b.id), maxi(a.id, b.id)]

func next_ball_contact(balls, targets, dt, progress):
	var hit = {"at": INF}
	var motion = {}
	for ball in balls:
		if ball.dead: continue
		var end: Vector2 = ball.p + ball_velocity(ball, dt) * dt
		var platform = first_landing(ball.p, end, BALL_FOOT_MARGIN)
		if platform != null: end.y = platform.position.y
		var travel: Vector2 = end - ball.p
		motion[ball.id] = travel
		if travel.x != 0.0:
			var wall_x := 910.0 if travel.x > 0.0 else 50.0
			var wall_at: float = (wall_x - ball.p.x) / travel.x
			if wall_at >= 0.0 and wall_at <= 1.0 and wall_at < hit.at:
				hit = {"at": wall_at, "kind": "wall", "a": ball, "x": wall_x}
		if not ball.roll: continue
		for target in targets:
			if target.dead: continue
			var start: Vector2 = target.previous.lerp(target.p, progress)
			var at := contact_fraction(ball.p - start, travel - (target.p - start), 40.0)
			if at < hit.at:
				hit = {"at": at, "kind": "enemy", "a": ball, "b": target}
	for i in balls.size():
		var a = balls[i]
		if a.dead: continue
		for j in range(i + 1, balls.size()):
			var b = balls[j]
			if b.dead or (not a.roll and not b.roll): continue
			var key_string := pair_key(a, b)
			var offset: Vector2 = b.p - a.p
			if offset.length_squared() > (BALL_RADIUS * 2.0 + .02) ** 2:
				pair_contacts.erase(key_string)
			if pair_contacts.has(key_string): continue
			if a.roll and b.roll and signf(a.v.x) == signf(b.v.x): continue
			var relative: Vector2 = motion[b.id] - motion[a.id]
			var at := contact_fraction(offset, relative, BALL_RADIUS * 2.0)
			if at >= hit.at: continue
			var delta := offset + relative * at
			if absf(delta.y) > 36.0: continue
			var normal := signf(delta.x) if absf(delta.x) > .01 else signf(a.v.x - b.v.x)
			if (a.v.x - b.v.x) * normal > 0.0:
				hit = {"at": at, "kind": "pair", "a": a, "b": b, "normal": normal}
	return hit

func advance_snowballs(balls, targets, dt):
	for ball in balls:
		ball.previous = ball.p
		ball.travel.clear()
	var progress := 0.0
	while progress < 1.0 and not balls.is_empty():
		var hit = next_ball_contact(balls, targets, dt * (1.0 - progress), progress)
		var end := lerpf(progress, 1.0, minf(hit.at, 1.0))
		if end > progress:
			for ball in balls:
				if not ball.dead: advance_ball(ball, (end - progress) * dt, progress, end)
		progress = end
		match hit.get("kind", ""):
			"wall": hit_ball_wall(hit.a, hit.x)
			"pair": respond_to_pair(hit.a, hit.b, hit.normal)
			"enemy":
				hit.b.p = hit.b.previous.lerp(hit.b.p, progress)
				roll_hit(hit.a, hit.b)

func collide_balls(a, b):
	var key_string := pair_key(a, b)
	var delta: Vector2 = b.p - a.p
	if a.dead or b.dead or delta.length_squared() > (BALL_RADIUS * 2.0) ** 2 or absf(delta.y) > 36.0:
		pair_contacts.erase(key_string)
		return
	if not a.roll and not b.roll: return
	if a.roll and b.roll and signf(a.v.x) == signf(b.v.x): return
	if pair_contacts.has(key_string): return
	var normal := signf(delta.x) if absf(delta.x) > .01 else signf(a.v.x - b.v.x)
	if (a.v.x - b.v.x) * normal > 0.0: respond_to_pair(a, b, normal)

func respond_to_pair(a, b, normal):
	var one_active = bool(a.roll) != bool(b.roll)
	if one_active:
		var incoming = a if a.roll else b
		var target = b if a.roll else a
		var launch: float = signf(incoming.v.x) * maxf(absf(incoming.v.x), ROLL_SPEED * .92)
		if a.p.distance_to(b.p) > STACK_DISTANCE: incoming.v.x *= -.96
		target.v.x = launch * .98
		target.chain_id = incoming.chain_id
	else:
		var impulse: float = (a.v.x - b.v.x) * normal * .99
		a.v.x -= normal * impulse
		b.v.x += normal * impulse
	a.dir = signf(a.v.x)
	b.dir = signf(b.v.x)
	pair_contacts[pair_key(a,b)] = true
	a.roll = true
	b.roll = true
	credit_ball(a)
	credit_ball(b)
	combo_time = 2.0
	hit_flash = .14
	ball_impact(a, 1.0, Vector2(normal, 0))
	ball_impact(b, 1.0, Vector2(-normal, 0))
	play_sfx("chain")
	announce("CHAIN REACTION", 1.0)
	float_text.append({"text":"CHAIN","p":(a.p+b.p)*.5-Vector2(0,55),"life":.8,"color":ICE})

func catch_passing_ball(balls, player_start):
	if player.ride >= 0 or player.ride_lock > 0.0 or player.standing >= 0: return
	var earliest := INF
	var carrier = null
	for ball in balls:
		if ball.dead or not ball.roll: continue
		for segment in ball.travel:
			var start: Vector2 = player_start.lerp(player.p, segment[0])
			var end: Vector2 = player_start.lerp(player.p, segment[1])
			var at := contact_fraction(start - segment[2], (end - start) - (segment[3] - segment[2]), 37.0)
			if at == INF: continue
			var contact_time := lerpf(segment[0], segment[1], at)
			if contact_time < earliest:
				earliest = contact_time
				carrier = ball
	if carrier != null: begin_ride(carrier)

func snow_hit(e,shot):
	var center: Vector2 = e.p-Vector2(0,22)
	var outward: Vector2 = shot.p-center
	if outward.is_zero_approx(): outward = Vector2(-shot.dir,0)
	var impact := center+outward.normalized()*(22.0 if e.snow >= SNOW_MAX else 16.0)
	e.flash = .08
	burst(impact,ICE,4)
	if e.snow>=SNOW_MAX: return
	score+=10; high_score=maxi(high_score,score)
	e.snow=mini(SNOW_MAX,e.snow+shot.power); e.thaw=12.0
	# Ordinary snow arrests walking. It never launches a living target.
	# A target already airborne still follows gravity, without added impulse.
	e.v.x=0.0
	if e.snow==SNOW_MAX:
		play_sfx("freeze")
		space_ball_row(idle_ball_row(e))

func roll_hit(ball,target):
	if target.dead: return
	if ball.chain_id==0:
		ball.chain_id=next_chain; chains[next_chain]=0; next_chain+=1
	chains[ball.chain_id]=chains.get(ball.chain_id,0)+1
	var count: int=chains[ball.chain_id]
	combo=count; combo_time=2.5
	# 1000/2000/3000/4000 is visible at source 01:17.8–01:18.4.
	# The cap above that observed range remains a tuning choice.
	award(1000*mini(count,8),target.p-Vector2(0,32))
	target.dead=true
	var body=target.duplicate(true)
	body.snow=0; body.flash=0.0; body.roll=false
	body.v=Vector2(signf(ball.v.x)*110.0, -room_launch_speed(body.p.y, DEFEATED_CEILING, 560.0, 470.0))
	body.life=2.5; body.age=0.0; body.spin=0.0
	body.origin=target.p; body.kind=["blue","red","yellow","points"][target.id%4]
	defeated.append(body)
	ball.v.x*=BALL_ENEMY_RETENTION
	ball_impact(ball, .8, Vector2(signf(ball.v.x), 0)); play_sfx("hit")
	if count>1: announce("%d HIT CHAIN  +%d"%[count,1000*mini(count,8)],1.0)

func update_defeated(dt):
	for body in defeated:
		var previous: Vector2=body.p
		body.age+=dt; body.life-=dt
		body.v.y+=560.0*dt; body.p+=body.v*dt; body.spin+=dt*8.0
		if body.p.y<DEFEATED_CEILING:
			body.p.y=DEFEATED_CEILING; body.v.y=maxf(body.v.y,0.0)
		if body.p.x<52 or body.p.x>908:
			body.p.x=clampf(body.p.x,52,908); body.v.x=-body.v.x*.7
		var landed=false
		if body.v.y>0:
			for plat in platforms:
				if previous.y<=plat.position.y+1 and body.p.y>=plat.position.y and body.p.x>plat.position.x and body.p.x<plat.end.x:
					body.p.y=plat.position.y; landed=true; break
		if landed or body.life<=0 or body.p.y>520:
			if not landed:
				body.p=body.origin
			gifts.append({"p":body.p,"life":10.0,"kind":body.kind})
			body.life=0; burst(body.p-Vector2(0,12),Color("ffcf82"),5)
	defeated=defeated.filter(func(body): return body.life>0)

func find_ball(id):
	for e in enemies:
		if e.id==id and not e.dead: return e
	return null

func begin_ride(carrier):
	if player.ride >= 0: return
	# Covers the transition even if the carrier breaks on the next wall.
	# Contact protection while already riding is independent of this timer.
	invincible=maxf(invincible,RIDE_ENTRY_INVINCIBILITY)
	player.ride=carrier.id
	player.p=carrier.p
	player.v=carrier.v
	player.ground=false
	player.standing=-1
	player.pushing=false
	jump_active=false; jump_angle=0.0
	jump_buffer=0.0; ledge_grace=0.0; landing_pose=0.0

func room_launch_speed(feet_y: float, ceiling: float, gravity: float, maximum: float) -> float:
	return minf(maximum, sqrt(2.0*gravity*maxf(feet_y-ceiling,0.0)))

func begin_jump():
	player.v.y=-PLAYER_JUMP_SPEED; player.ground=false
	jump_active=true; jump_angle=0.0; jump_spin_dir=player.dir
	jump_buffer=0.0; ledge_grace=0.0; landing_pose=0.0
	play_sfx("jump")

# Time from a descending foot to a one-way surface. Negative means unreachable.
func falling_contact_time(start_y: float, velocity: float, surface_y: float) -> float:
	var drop := surface_y-start_y
	if drop < -.001: return -1.0
	var final_speed := sqrt(velocity*velocity+2.0*PLAYER_FALL_GRAVITY*maxf(drop,0.0))
	return (final_speed-velocity)/PLAYER_FALL_GRAVITY

func descent_time(surface_y):
	return falling_contact_time(player.p.y,player.v.y,surface_y)

func move_player_body(dt: float) -> float:
	var start: Vector2 = player.p
	var vx: float = player.v.x
	var end_x := start.x+vx*dt
	player.p.x=clampf(end_x,52,908)
	if end_x<52.0 or end_x>908.0:
		player.v.x=0.0
		player.momentum=0.0
	player.ground=false

	# Split the tick at its apex so trajectories agree at any substep rate.
	var rising_time := clampf(-player.v.y/PLAYER_GRAVITY,0.0,dt)
	player.p.y+=player.v.y*rising_time+.5*PLAYER_GRAVITY*rising_time*rising_time
	player.v.y+=PLAYER_GRAVITY*rising_time
	var falling_time := dt-rising_time
	if falling_time<=0.0: return 0.0

	var downward_speed := maxf(0.0,player.v.y)
	var final_y: float=player.p.y+downward_speed*falling_time+.5*PLAYER_FALL_GRAVITY*falling_time*falling_time
	var earliest := INF
	var surface_y := 0.0
	for platform in platforms:
		if platform.position.y>final_y+.001 or platform.position.y<player.p.y-.001: continue
		var t := falling_contact_time(player.p.y,downward_speed,platform.position.y)
		if t<0.0 or t>falling_time or t>=earliest: continue
		var contact_x := clampf(start.x+vx*(rising_time+t),52,908)
		# Test support under the new foot when already resting on the platform.
		if t<=.00001 and rising_time==0.0: contact_x=player.p.x
		if contact_x<=platform.position.x-9.0 or contact_x>=platform.end.x+9.0: continue
		earliest=t
		surface_y=platform.position.y
	if earliest<INF:
		player.p.y=surface_y
		player.v.y=0.0
		player.ground=true
		return downward_speed+PLAYER_FALL_GRAVITY*earliest
	player.p.y=final_y
	player.v.y=downward_speed+PLAYER_FALL_GRAVITY*falling_time
	return player.v.y

func jump_landing_time():
	# Pose forecast only; actual platform/ball collisions stay authoritative.
	var remaining=2.0
	for plat in platforms:
		var t: float=descent_time(plat.position.y)
		var x: float=clampf(player.p.x+player.v.x*t,52,908)
		if t>=0 and x>plat.position.x-9 and x<plat.end.x+9: remaining=minf(remaining,t)
	for e in enemies:
		if e.dead or e.snow<SNOW_MAX: continue
		var t: float=descent_time(e.p.y-46.0)
		if t>=0 and absf(player.p.x+player.v.x*t-(e.p.x+e.v.x*t))<32: remaining=minf(remaining,t)
	return remaining

func update_jump_pose(dt):
	if not jump_active: return
	if player.ground:
		jump_angle=TAU; jump_active=false; return
	if player.v.y<0:
		# First half-turn on ascent, reaching upside down at the apex.
		jump_angle=maxf(jump_angle,PI*clampf(1.0+player.v.y/PLAYER_JUMP_SPEED,0,1))
	else:
		var descending_step := minf(dt,player.v.y/PLAYER_FALL_GRAVITY)
		if descending_step<dt: jump_angle=maxf(jump_angle,PI)
		# Finish the same turn on descent, adapting to a higher platform or ball.
		# Integrate the remaining angle so a change in target cannot rewind it.
		var remaining: float=jump_landing_time()
		jump_angle=minf(TAU,jump_angle+(TAU-jump_angle)*descending_step/maxf(remaining+descending_step,.00001))

func update_player(dt,axis):
	player.ride_lock=maxf(0.0,player.ride_lock-dt); player.attack=maxf(0.0,player.attack-dt)
	if jump_request:
		jump_buffer=PLAYER_JUMP_BUFFER
		jump_request=false
	landing_pose=maxf(0.0,landing_pose-dt)
	player.pushing=false
	if absf(axis)>.01: player.dir=1 if axis>0 else -1
	if player.ride>=0:
		var carrier=find_ball(player.ride)
		if carrier==null or not carrier.roll:
			player.ride=-1; player.ride_lock=.4; player.ground=false; player.v=Vector2.ZERO
		elif jump_buffer>0.0:
			player.p=carrier.p-Vector2(0,48); player.v=Vector2(carrier.v.x*.4,0)
			player.momentum=carrier.v.x*.4; player.ride=-1; player.ride_lock=.6; invincible=maxf(invincible,.5)
			begin_jump()
		else:
			player.p=carrier.p; player.v=carrier.v; return
	var previous: Vector2=player.p
	player.momentum=move_toward(player.momentum,0.0,700.0*dt)
	player.v.x=axis*(PLAYER_RED_SPEED if speed_up else PLAYER_MOVE_SPEED)+player.momentum
	if jump_buffer>0.0 and (player.ground or ledge_grace>0.0):
		begin_jump()
	var was_grounded: bool=player.ground
	var impact_speed := move_player_body(dt)
	player.standing=-1
	var contact_ball = null
	var closest_side := INF
	for e in enemies:
		if e.snow<SNOW_MAX or e.dead: continue
		var top: float=e.p.y-46.0
		var side_distance=absf(player.p.x-e.p.x)
		if player.v.y>=0 and previous.y<=top+3 and player.p.y>=top and side_distance<32:
			player.p.y=top; player.v.y=0; player.ground=true; player.standing=e.id
			player.p.x+=e.v.x*dt
			continue
		if player.v.y<0 and previous.y-46>=e.p.y-3 and player.p.y-46<=e.p.y+2 and side_distance<33:
			# Head contact: bump without activating a fast roll.
			e.v.y=minf(e.v.y,-245.0); e.ground=false; e.thaw=12; e.impact=.5
			player.p.y=e.p.y+47; player.v.y=40; ball_impact(e,.4)
			continue
		if player.p.y<=top+4 or player.p.y-44>=e.p.y-2: continue
		if side_distance<38:
			if e.roll and player.ride_lock<=0:
				begin_ride(e); return
			var side=-1 if previous.x<e.p.x else 1
			if e.roll:
				player.p.x=e.p.x+side*38.0
			else:
				var distance := absf(previous.x-e.p.x)
				if distance < closest_side or (distance == closest_side and (contact_ball == null or e.id < contact_ball.id)):
					contact_ball = e
					closest_side = distance
	if contact_ball != null and player.standing < 0:
		var side := -1 if previous.x < contact_ball.p.x else 1
		if axis * side < -.1:
			push_ball_group(contact_ball, axis * (RED_PUSH_SPEED if speed_up else PUSH_SPEED) * dt)
			player.pushing = true
		player.p.x = contact_ball.p.x + side * 38.0
	update_jump_pose(dt)
	if player.ground:
		ledge_grace=0.0
		if absf(axis)>.01 and was_grounded:
			var step_cap: float=(PLAYER_RED_SPEED+absf(player.momentum))*dt
			stride_distance+=minf(absf(player.p.x-previous.x),step_cap)
		if not was_grounded:
			landing_pose=PLAYER_LANDING_POSE
			landing_strength=clampf(impact_speed/(PLAYER_FALL_GRAVITY*PLAYER_FALL_TIME),0.0,1.0)
	elif was_grounded and not jump_active:
		ledge_grace=PLAYER_LEDGE_GRACE
	else:
		ledge_grace=maxf(0.0,ledge_grace-dt)
	jump_buffer=maxf(0.0,jump_buffer-dt)
	if player.ground and jump_buffer>0.0:
		begin_jump()

func attack():
	var nearest = null
	var nearest_dx := INF
	for enemy in enemies:
		if enemy.snow < SNOW_MAX or enemy.roll or enemy.dead: continue
		var ahead: float = (enemy.p.x - player.p.x) * player.dir
		if ahead > 0 and ahead <= 47 and ahead < nearest_dx and absf(enemy.p.y-player.p.y) < 48:
			nearest_dx = ahead
			nearest = enemy
	if nearest != null:
		player.attack_kind = "kick"
		player.attack = .17
		kick_stack(nearest, player.dir)
		return
	player.attack_kind = "snow"
	player.attack = .15
	shots.append(make_shot(player.p + Vector2(player.dir*20,-24), player.dir, 2 if power_up else 1, range_up))
	play_sfx("snow")

func make_shot(origin, direction, power=1, extended=false):
	var cruise: float = SHOT_LONG_CRUISE_TIME if extended else SHOT_CRUISE_TIME
	var duration := cruise + SHOT_BRAKE_TIME + SHOT_DRIFT_TIME
	var shot = {"p":origin, "origin":origin, "dir":direction, "v":Vector2(direction*SHOT_SPEED,0),
		"age":0.0, "duration":duration, "cruise":cruise, "life":duration,
		"power":power, "extended":extended, "phase":next_shot*2.399963}
	next_shot += 1
	return shot

func shot_tail_weight(brake_progress):
	return smoothstep(SHOT_FLUTTER_START, 1.0, brake_progress)

func shot_path(shot, age, flutter=true):
	var flight := clampf(age, 0.0, shot.duration)
	var cruise: float = shot.cruise
	var u := clampf((flight-cruise)/SHOT_BRAKE_TIME, 0, 1)
	var drag: float = SHOT_END_SPEED_RATIO*u + (1.0-SHOT_END_SPEED_RATIO)*(1.0-pow(1.0-u,4.0))/4.0
	var distance: float = SHOT_SPEED*(minf(flight,cruise) + SHOT_BRAKE_TIME*drag)
	var sink: float = (u-.12*(1.0-exp(-u/.12)))/(1.0-.12*(1.0-exp(-1.0/.12)))
	var y: float = -SHOT_CRUISE_RISE*smoothstep(0,1,minf(flight/cruise,1.0)) + SHOT_SINK*sink
	# Once the calibrated braking phase ends the flake folds over and drifts
	# down. Integrate velocities so neither axis jumps at the transition.
	var falling := maxf(0.0, flight-cruise-SHOT_BRAKE_TIME)
	if falling > 0:
		var t := clampf(falling/SHOT_DRIFT_TIME, 0, 1)
		var final_dx := 3.0
		var entry_dx: float = SHOT_SPEED*SHOT_END_SPEED_RATIO
		distance += SHOT_DRIFT_TIME*(final_dx*t + (entry_dx-final_dx)*(1.0-pow(1.0-t,3))/3.0)
		var entry_dy: float = (SHOT_SINK/SHOT_BRAKE_TIME)*(1.0-exp(-1.0/.12))/(1.0-.12*(1.0-exp(-1.0/.12)))
		y += falling*lerpf(entry_dy, SHOT_DRIFT_SPEED_Y, t*.5)
	if flutter and u > SHOT_FLUTTER_START:
		var phase: float = (flight-cruise-SHOT_BRAKE_TIME*SHOT_FLUTTER_START)*TAU*6.5 + shot.phase
		y += shot_tail_weight(u)*sin(phase)*SHOT_FLUTTER_AMPLITUDE
	return shot.origin + Vector2(shot.dir*distance, y)

func shot_extent(shot):
	var radius=11.0 if shot.power>1 else 6.0
	return Vector2(radius*(2.4 if shot.get("extended",false) else 1.0),radius)

func shot_tilt(shot, age: float) -> float:
	var brake := clampf((age-shot.cruise)/SHOT_BRAKE_TIME, 0, 1)
	var drift := clampf((age-shot.cruise-SHOT_BRAKE_TIME)/SHOT_DRIFT_TIME, 0, 1)
	var flutter: float = sin(age*TAU*5.5+shot.phase)*shot_tail_weight(brake)
	return shot.dir*(brake*brake*.32+drift*.72+flutter*.14)

func tilted_extent(size: Vector2, angle: float) -> Vector2:
	# The long yellow flake presents a taller profile as its nose turns down.
	if size.x == size.y: return size
	var c := cos(angle)
	var s := sin(angle)
	return Vector2(Vector2(size.x*c,size.y*s).length(),Vector2(size.x*s,size.y*c).length())

func shot_enemy_fraction(start: Vector2, end: Vector2, center: Vector2, reach: Vector2) -> float:
	# Transform the enemy + flake envelope to a unit circle and find its entry,
	# including an overlap at the muzzle or during a nearly vertical drift.
	var offset := (start-center)/reach
	var delta := (end-start)/reach
	var c := offset.length_squared()-1.0
	if c <= 0: return 0.0
	var b := offset.dot(delta)
	if b >= 0: return INF
	var a := delta.length_squared()
	var discriminant := b*b-a*c
	if discriminant < 0: return INF
	var time := c/(-b+sqrt(discriminant))
	return time if time <= 1 else INF

func trace_snow_segment(shot, end: Vector2, size: Vector2, next_size: Vector2) -> float:
	var start: Vector2 = shot.p
	var earliest := INF
	var surface_y := 0.0
	var target = null
	var closest := INF
	# Platforms catch the lower edge on descent. A shot fired below a one-way
	# ledge may pass its underside, just like the character.
	var bottom_motion := (end.y+next_size.y)-(start.y+size.y)
	if bottom_motion > 0:
		for platform in platforms:
			var height := platform.position.y
			var t := (height-size.y-start.y)/bottom_motion
			if t < 0 or t > 1 or t >= earliest: continue
			var x := lerpf(start.x,end.x,t)
			var width := lerpf(size.x,next_size.x,t)
			if x >= platform.position.x-width and x <= platform.end.x+width:
				earliest = t
				surface_y = height
	var reach := size.max(next_size) + Vector2(18,18)
	for enemy in enemies:
		if enemy.dead or enemy.roll: continue
		var center: Vector2 = enemy.p - Vector2(0,22)
		var fraction := shot_enemy_fraction(start, end, center, reach)
		if fraction == INF: continue
		var distance := start.distance_squared_to(center)
		if fraction < earliest or (target != null and is_equal_approx(fraction,earliest) and distance < closest):
			earliest = fraction
			closest = distance
			target = enemy
	if earliest == INF:
		shot.p = end
		return INF
	shot.p = start.lerp(end,earliest)
	shot.life = 0.0
	if target != null:
		snow_hit(target,shot)
	else:
		for i in 3:
			particles.append({"p":Vector2(shot.p.x,surface_y-4), "v":Vector2(shot.dir*(i-1)*34,-30-i*11),
				"life":.12+i*.015, "color":ICE if i%2 else WHITE})
	return earliest

func update_shots(dt):
	for shot in shots:
		if shot.life <= 0: continue
		if not shot.has("origin"):
			var remaining: float = shot.life
			shot.merge(make_shot(shot.p, shot.dir, shot.power, shot.get("extended",false)))
			shot.duration = remaining
		var end_age := minf(shot.duration, shot.age+dt)
		var size: Vector2 = shot_extent(shot)
		var projected := tilted_extent(size,shot_tilt(shot,shot.age))
		while shot.age < end_age:
			# Bound the chord error if a caller supplies a large simulation step.
			var next_age := minf(end_age, shot.age+1.0/90.0)
			var next: Vector2 = shot_path(shot,next_age)
			shot.v = (next-shot.p)/(next_age-shot.age)
			var next_size := tilted_extent(size,shot_tilt(shot,next_age))
			var contact := trace_snow_segment(shot,next,projected,next_size)
			if contact != INF:
				shot.age = lerpf(shot.age,next_age,contact)
				break
			shot.age = next_age
			projected = next_size
		if shot.life > 0: shot.life = maxf(0.0, shot.duration-shot.age)
	shots = shots.filter(func(s): return s.life > 0)

func _physics_process(dt):
	dt=minf(dt,.05) # Resume without a large catch-up spike.
	clock+=dt
	sync_web_state(dt)
	if is_instance_valid(music): music.stream_paused=paused
	if state!="play" or paused: queue_redraw(); return
	var steps=maxi(1,int(ceil(dt*120.0)))
	for i in steps: step_game(dt/steps)
	queue_redraw()

func step_game(dt):
	if state!="play": return
	elapsed+=dt; cooldown-=dt; combo_time=maxf(0.0,combo_time-dt); invincible=maxf(0.0,invincible-dt); notice_time-=dt; hit_flash=maxf(0.0,hit_flash-dt)
	var axis=clampf(float(key(KEY_RIGHT) or key(KEY_D) or touch_right)-float(key(KEY_LEFT) or key(KEY_A) or touch_left)+web_axis,-1.0,1.0)
	var balls = []
	var targets = []
	for e in enemies:
		e.flash = maxf(0.0, e.flash - dt)
		e.previous = e.p
		if e.snow > 0 and not e.roll and (e.snow < SNOW_MAX or not practice):
			e.thaw -= dt
			if e.thaw <= 0.0:
				e.snow -= 1
				e.thaw = 1.3
		if e.snow >= SNOW_MAX:
			balls.append(e)
			continue
		targets.append(e)
		e.v.x = e.dir * (48 + minf(elapsed / 8, 30)) if e.snow == 0 and not practice else 0.0
		e.jump -= dt
		if not practice and e.jump <= 0.0 and e.ground and e.snow == 0:
			e.jump = 2.7 + e.id * .1
			e.v.y = -room_launch_speed(e.p.y, ENEMY_CEILING, 1000.0, 470.0)
			e.dir = 1 if player.p.x > e.p.x else -1
		move_body(e, dt)
	advance_snowballs(balls, targets, dt)
	settle_idle_balls(balls)
	var player_start: Vector2 = player.p
	update_player(dt,axis)
	catch_passing_ball(balls, player_start)
	if (key(KEY_J) or key(KEY_Z) or touch_fire) and cooldown<=0 and player.ride<0:
		cooldown=.15; attack()
	update_shots(dt)
	for e in enemies:
		if e.dead: continue
		if e.snow==0 and invincible<=0 and player.ride<0 and e.p.distance_to(player.p)<29:
			lives-=1; invincible=2.5; player.p=Vector2(130,492); player.v=Vector2.ZERO
			player.ground=true; player.momentum=0; jump_active=false; jump_angle=0
			jump_request=false; jump_buffer=0.0; ledge_grace=0.0; landing_pose=0.0; stride_distance=0.0
			speed_up=false; power_up=false; range_up=false; announce("OUCH!",1.0)
			if lives<=0: state="over"
	enemies=enemies.filter(func(e): return not e.dead)
	for g in gifts:
		g.life-=dt
		if g.p.distance_to(player.p)<34:
			g.life=0
			match g.kind:
				"red": speed_up=true; announce("SPEED UP"); play_sfx("pickup")
				"blue": power_up=true; announce("BIG SNOW / POWER UP"); play_sfx("pickup")
				"yellow": range_up=true; announce("LONG SNOW / RANGE UP"); play_sfx("pickup")
				_: award(400,g.p-Vector2(0,25))
			burst(g.p-Vector2(0,14),Color("ffdb79"),8)
	gifts=gifts.filter(func(g): return g.life>0)
	update_defeated(dt)
	for p in particles: p.life-=dt; p.v.y+=400*dt; p.p+=p.v*dt
	particles=particles.filter(func(p): return p.life>0)
	for f in float_text: f.life-=dt; f.p.y-=32*dt
	float_text=float_text.filter(func(f): return f.life>0)
	if enemies.is_empty() and gifts.is_empty() and defeated.is_empty() and not practice: state="clear"; award(lives*1000,Vector2(480,260))
	update_stage_view(dt)

func update_stage_view(dt: float):
	# Follow only above the upper floors. The space between the thresholds lets
	# the actor visibly descend before the camera begins to track down again.
	var feet_y: float = player.p.y
	var upper_limit := maxf(0.0, 166.0 - feet_y)
	var lower_limit := maxf(0.0, 250.0 - feet_y)
	stage_scroll_y = maxf(stage_scroll_y, upper_limit)
	if stage_scroll_y > lower_limit:
		stage_scroll_y = move_toward(stage_scroll_y, lower_limit, 650.0 * dt)
	# A long fall or a respawn must immediately bring the feet back into view.
	stage_scroll_y = minf(stage_scroll_y, maxf(0.0, 494.0 - feet_y))
	position.y = roundf(stage_scroll_y)

func label_at(text,pos,size,color=WHITE):
	draw_string(FONT,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

# The notched, stepped silhouette stays readable at phone size, even edge-on.
var flake_outline := PackedVector2Array([
	Vector2(-.58,-.9), Vector2(.07,-1), Vector2(.68,-.62), Vector2(1,-.18),
	Vector2(1,.3), Vector2(.58,.82), Vector2(-.1,1), Vector2(-.65,.82),
	Vector2(-.08,.42), Vector2(.19,.12), Vector2(.11,-.24), Vector2(-.18,-.54)])
var flake_ridge := PackedVector2Array([
	Vector2(-.40,-.80), Vector2(.04,-.84), Vector2(.57,-.51), Vector2(.81,-.12),
	Vector2(.71,.04), Vector2(.36,-.27), Vector2(-.07,-.50)])

func draw_snow_shot(shot):
	var size: Vector2 = shot_extent(shot)
	var brake: float = clampf((shot.age-shot.cruise)/SHOT_BRAKE_TIME, 0, 1)
	var drift: float = clampf((shot.age-shot.cruise-SHOT_BRAKE_TIME)/SHOT_DRIFT_TIME, 0, 1)
	var tilt := shot_tilt(shot,shot.age)
	var pos: Vector2 = shot.p.round()
	var face := Vector2(shot.dir*size.x,size.y)
	# Loose grains trail the broad face during launch and hang above it in descent.
	var lag := Vector2(-shot.dir*(size.x+4.0)*(1.0-drift*.6),-brake*(size.y+4))
	draw_rect(Rect2(pos+lag,Vector2(3,2)), Color("93d9ed"))
	draw_rect(Rect2(pos+lag*1.48+Vector2(0,2.0*sin(tilt)+1),Vector2(2,2)), Color("639ab4"))
	draw_set_transform(pos+Vector2(0,2),tilt,face)
	draw_colored_polygon(flake_outline, Color("438ba9"))
	draw_set_transform(pos,tilt,face)
	draw_colored_polygon(flake_outline, ICE)
	draw_colored_polygon(flake_ridge, Color.WHITE)
	draw_set_transform(Vector2.ZERO)

func draw_player():
	var frame: int
	var facing: int = player.dir
	var pivot: Vector2 = ACTOR_SPRITE.FEET
	var origin: Vector2 = player.p
	var rotation_angle := 0.0
	var size: float = ACTOR_SPRITE.PIXEL_SIZE
	var carrier = find_ball(player.ride) if player.ride >= 0 else null
	if carrier != null:
		# The tucked riding cel leaves the carrier’s rim visible through the roll.
		frame = ACTOR_SPRITE.Frame.RIDE
		rotation_angle = carrier.spin
		pivot = ACTOR_SPRITE.TURN_PIVOT
		origin = carrier.p - Vector2(0, 22)
		size *= 0.86
	elif jump_active:
		# The turn is pre-rasterized; each pixel stays square through the flip.
		facing = jump_spin_dir
		var aim := int(player.dir) * facing if player.attack > 0.065 and player.get("attack_kind", "snow") == "snow" else 0
		frame = ACTOR_SPRITE.turn_frame(jump_angle, aim)
	else:
		frame = ACTOR_SPRITE.ground_frame(player, stride_distance, elapsed, landing_pose, landing_strength)
	draw_set_transform(origin.round(), rotation_angle, Vector2(facing * size, size))
	var tint := Color.WHITE
	if invincible > 0.0 and int(clock * 10.0) % 2 == 1:
		tint = Color(.75, .92, 1.0, .55)
	var sheet := ACTOR_SPRITE.SPEED_TEXTURE if speed_up else ACTOR_SPRITE.TEXTURE
	var region := ACTOR_SPRITE.speed_region(frame, elapsed) if speed_up else ACTOR_SPRITE.region(frame)
	draw_texture_rect_region(sheet, Rect2(-pivot, Vector2.ONE * ACTOR_SPRITE.CELL_SIZE), region, tint)
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow(feet: Vector2):
	var surface_y := INF
	for platform in platforms:
		if feet.x < platform.position.x or feet.x > platform.end.x: continue
		if platform.position.y >= feet.y - 1.0:
			surface_y = minf(surface_y, platform.position.y)
	if surface_y == INF: return
	var height := clampf((surface_y - feet.y) / PLAYER_JUMP_HEIGHT, 0.0, 1.0)
	var radius := lerpf(17.0, 8.0, height)
	draw_set_transform(Vector2(roundf(feet.x), surface_y), 0.0, Vector2(1.0, .22))
	draw_circle(Vector2.ZERO, radius, Color(.06, .17, .26, lerpf(.48, .17, height)))
	draw_set_transform(Vector2.ZERO)

func monster(e):
	var p: Vector2=e.p
	if e.snow>=SNOW_MAX or e.roll:
		var speed = absf(e.v.x)
		if e.roll and speed>140:
			for i in range(1,4):
				var tail=p+Vector2(-signf(e.v.x)*i*12,-22)
				draw_line(tail,tail+Vector2(-signf(e.v.x)*12,0),Color(0.6,0.9,1.0,0.22/float(i)),2)
		var squash: float = e.get("impact", 0.0)
		if e.get("impact_side", false): squash = -squash
		var scale_factor := Vector2(1.0 + squash * .17, 1.0 - squash * .14)
		draw_set_transform(p - Vector2(0, BALL_RADIUS * scale_factor.y), 0, scale_factor)
		var tone: int = e.get("stack_tone", 0) if not e.roll else 0
		var rim := Color("80c4de")
		var body := Color("caedf3")
		var light := WHITE
		if tone == 1:
			rim = Color("4383bc"); body = Color("7dbde9"); light = Color("a6d9ff")
		elif tone == 2:
			rim = Color("bc7686"); body = Color("e7a3af"); light = Color("ffc9d1")
		draw_circle(Vector2.ZERO, BALL_RADIUS, Color("305776"))
		draw_circle(Vector2(0,-1), 22.5, rim)
		draw_circle(Vector2(-1,-3), 20.5, body)
		draw_circle(Vector2(-2,-4), 18.5, light)
		var angle: float = e.get("spin", 0.0)
		draw_arc(Vector2.ZERO, 14.0, angle, angle + 1.3, 7, Color("98cfdd"), 3)
		draw_arc(Vector2.ZERO, 16.0, angle + 2.8, angle + 3.65, 6, Color("aad9e5"), 2)
		draw_circle(Vector2(8,-2).rotated(angle), 2.4, Color("bddfe8"))
		draw_line(Vector2(-12,-11), Vector2(-8,-14), Color.WHITE, 3)
		draw_set_transform(Vector2.ZERO)
		if e.flash>0: draw_arc(p-Vector2(0,22),28,0,TAU,24,Color("ffcd70"),2)
		return
	# Each art pixel spans two logical pixels. The atlas has right/left rows
	# for each enemy, with a separate row of progressively taller snow caps.
	var pose := 0
	if e.dead:
		pose = 8
	elif e.snow > 0 or e.flash > 0:
		pose = 7
	elif not e.ground:
		pose = 5 if e.v.y < 0 else 6
	elif absf(e.v.x) > 1.0:
		pose = 1 + posmod(int(floor(p.x / 6.0)), 4)
	elif fmod(clock + e.id * 0.47, 3.1) < 0.12:
		pose = 9
	var row: int = 2 * posmod(int(e.id), 2) + (1 if e.dir < 0 else 0)
	var origin := (p - Vector2(32, 50)).round()
	var dest := Rect2(origin, Vector2(64, 56))
	var tint := Color(1.20, 1.27, 1.30) if e.flash > 0 else Color.WHITE
	draw_texture_rect_region(MONSTER_POSES, dest, Rect2(pose * 32, row * 28, 32, 28), tint)
	if e.snow > 0:
		draw_texture_rect_region(MONSTER_POSES, dest, Rect2(e.snow * 32, 4 * 28, 32, 28))

func _draw():
	draw_set_transform(-position)
	draw_rect(Rect2(0,0,960,640),Color("071729"))
	for i in 70:
		var x=fmod(i*137.3,960); var y=fmod(i*67.1+clock*(8+i%4*4),520)
		draw_circle(Vector2(x,y),1+i%2,Color(.7,.9,1,.15))
	for i in 9:
		var x=i*125-40
		draw_colored_polygon(PackedVector2Array([Vector2(x,490),Vector2(x+90,130+i%3*44+roundf(stage_scroll_y*.25)),Vector2(x+180,490)]),Color("102d43"))
	draw_set_transform(Vector2.ZERO)
	for plat in platforms:
		draw_rect(plat,Color("245e7c")); draw_rect(Rect2(plat.position+Vector2(0,5),Vector2(plat.size.x,5)),Color("397f9c"))
		draw_rect(Rect2(plat.position-Vector2(0,3),Vector2(plat.size.x,7)),ICE)
		for x in range(int(plat.position.x)+9,int(plat.end.x),24):
			draw_colored_polygon(PackedVector2Array([Vector2(x,plat.position.y+4),Vector2(x+7,plat.position.y+4),Vector2(x+3,plat.position.y+14)]),Color("8cd4e9"))
	for g in gifts:
		if g.life<2 and int(clock*8)%2==0: continue
		var colors={"red":Color("ef7287"),"blue":Color("6cb9ff"),"yellow":Color("ffd26f"),"points":Color("ffcd70")}
		draw_rect(Rect2(g.p-Vector2(8,20),Vector2(16,18)),colors[g.kind])
		draw_rect(Rect2(g.p-Vector2(4,25),Vector2(8,6)),WHITE)
		draw_rect(Rect2(g.p-Vector2(4,16),Vector2(3,9)),WHITE)
	for e in enemies:
		draw_ellipse_shadow(e.p); monster(e)
	for body in defeated:
		draw_set_transform(body.p-Vector2(0,20),body.spin,Vector2.ONE)
		var sprite=body.duplicate(); sprite.p=Vector2(0,20)
		monster(sprite); draw_set_transform(Vector2.ZERO)
	if player.ride < 0: draw_ellipse_shadow(player.p)
	draw_player()
	for s in shots:
		draw_snow_shot(s)
	for p in particles: draw_rect(Rect2(p.p,Vector2(4,4)),p.color)
	for f in float_text: label_at(f.text,f.p,12,Color(f.color,clampf(f.life*2,0,1)))
	# Root position follows the actor. Score, buttons and playfield trim use viewport coordinates.
	draw_set_transform(-position)
	draw_rect(Rect2(0,0,960,94),Color("071729"))
	draw_rect(Rect2(0,523,960,117),Color("071729"))
	label_at("1UP",Vector2(38,32),12,Color("71d7e9")); label_at("%07d"%score,Vector2(38,56),20)
	label_at("SNOW / BRO",Vector2(337,37),23)
	label_at("CASE %d/4 [Q]"%(practice_case+1) if practice else "FLOOR 01 [T]",Vector2(378,60),11,Color("80b9cc"))
	label_at("LIVES",Vector2(768,29),11,Color("71d7e9"))
	for i in lives: draw_circle(Vector2(776+i*30,48),8,WHITE)
	label_at("%02d LEFT"%enemies.filter(func(e): return not e.roll).size(),Vector2(768,78),10,Color("ffc56c"))
	label_at("HI %07d"%high_score,Vector2(38,78),9,Color("80b9cc"))
	var flags=[speed_up,power_up,range_up]
	for i in 3:
		var col=[Color("ef7287"),Color("6cb9ff"),Color("ffd26f")][i]
		draw_rect(Rect2(339+i*98,72,90,14),col if flags[i] else Color("19384d"))
		label_at(["SPEED","BIG SNOW","LONG SNOW"][i],Vector2(350+i*98,82),8,Color("071729") if flags[i] else Color("62869b"))
	draw_rect(Rect2(24,96,912,426),Color("2c5368"),false,3)
	var message_y := 485 if player.p.y + position.y < 205.0 else 102
	if combo_time>0 and combo>1:
		label_at("%d HIT"%combo,Vector2(790,message_y+10),12,Color("ffd487"))
	if notice_time>0:
		draw_rect(Rect2(230,message_y,500,26),Color(.02,.08,.13,.9))
		label_at(notice,Vector2(480-notice.length()*5,message_y+18),10,Color("ffda83"))
	if not web_mode:
		label_at("A/D MOVE  SPACE JUMP  J SNOW  1-4 PRACTICE",Vector2(180,533),9,ICE)
	if (state!="play" or paused) and not web_mode:
		draw_rect(Rect2(0,90,960,435),Color(.02,.06,.11,.87))
		var title="SNOW / BRO"
		var subtitle="FREEZE. ROLL. CLEAR THE FLOOR."
		if state=="clear": title="FLOOR CLEAR!"; subtitle="BONUS +%d   SCORE %07d"%[lives*1000,score]
		elif state=="over": title="GAME OVER"; subtitle="ONE MORE SNOWBALL?"
		elif paused: title="PAUSED"; subtitle="P / TAP TO RESUME"
		label_at(title,Vector2(480-title.length()*17,224),34,WHITE)
		label_at(subtitle,Vector2(480-subtitle.length()*5,270),10,Color("ffc56c"))
		if not paused:
			label_at("HOLD J TO FREEZE ENEMIES",Vector2(296,325),12,ICE)
			label_at("A/D PUSH  SPACE JUMP/BUMP  J KICK",Vector2(224,355),12,ICE)
			label_at("T PRACTICE / 1-4 SELECT CASE",Vector2(310,392),10,Color("80b9cc"))
			label_at("ENTER / TAP TO PLAY",Vector2(336,432),16,Color("ffc56c"))
		label_at("A SNOW BROS. TRIBUTE  /  GODOT 4.7",Vector2(288,485),9,Color("6d9bb1"))

func button_style():
	var style=StyleBoxFlat.new()
	style.bg_color=Color("143449"); style.border_color=Color("326078"); style.set_border_width_all(1); style.set_corner_radius_all(5)
	return style

# Synthesized feedback cues; these are new assets, not sampled original audio.
var sound_bank={}
var sfx_gate={}
func build_sounds():
	var specs={"snow":[880.0,360.0,.045],"kick":[180.0,55.0,.10],"hit":[250.0,70.0,.09],"chain":[330.0,760.0,.14],"freeze":[720.0,1250.0,.14],"pickup":[550.0,1100.0,.18],"jump":[210.0,390.0,.07]}
	for kind in specs:
		var spec=specs[kind]; var bytes=PackedByteArray(); var phase=0.0
		var count=int(22050*spec[2]); bytes.resize(count*2)
		for i in count:
			var t=float(i)/count
			phase+=TAU*lerpf(spec[0],spec[1],t)/22050.0
			var sample=sin(phase)*pow(1.0-t,2.0)*minf(t*30.0,1.0)*.28
			bytes.encode_s16(i*2,int(sample*32767))
		var stream=AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=22050; stream.data=bytes
		sound_bank[kind]=stream

func play_sfx(kind):
	if web_mode:
		if not muted and web_shell!=null: web_shell.sound(kind)
		return
	if muted or not sound_bank.has(kind) or clock-sfx_gate.get(kind,-100.0)<.045: return
	sfx_gate[kind]=clock
	var voice=AudioStreamPlayer.new(); voice.stream=sound_bank[kind]; voice.volume_db=-12
	add_child(voice); voice.finished.connect(voice.queue_free); voice.play()

func _notification(what):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and state=="play":
		paused=true; release_controls()
