extends SceneTree
var game
var passes=0
var failures=0
const DT=1.0/120.0
const Sprite=preload("res://scripts/jump_sprite.gd")
func _initialize():
	game=load('res://scenes/main.tscn').instantiate()
	root.add_child.call_deferred(game); run.call_deferred()
func check(ok,message):
	if not ok:
		push_error('FAIL: '+message); failures+=1; return
	passes+=1; print('PASS: '+message)
func fixture():
	game.reset(true);game.set_physics_process(false);game.muted=true;game.invincible=99
	game.enemies.clear();game.gifts.clear()
	game.platforms.clear();game.platforms.append(Rect2(36,492,888,28))
func flight(axis=0.0,stop_at_ball=false):
	var start_y: float=game.player.p.y
	var result={'time':0.0,'height':0.0,'apex_angle':0.0,'last_angle':0.0,'monotonic':true,'apex_seen':false,'at_half_second':0.0}
	game.jump_request=true
	for i in 240:
		var direction: float=0.0 if stop_at_ball and game.player.p.x>=300 else axis
		game.update_player(DT,direction)
		result.time+=DT
		result.height=maxf(result.height,start_y-game.player.p.y)
		if game.jump_angle<result.last_angle-.001: result.monotonic=false
		if game.player.v.y>=0 and not result.apex_seen:
			result.apex_seen=true;result.apex_angle=game.jump_angle
		if i==59: result.at_half_second=game.jump_angle
		if game.player.ground: break
		result.last_angle=game.jump_angle
	return result
func complete_turn(result,label):
	check(result.monotonic and game.jump_angle<=TAU+.001,label+': one forward turn, never rewinds or repeats')
	check(absf(result.apex_angle-PI)<.13,label+': upside down at apex')
	check(result.last_angle>TAU-.22 and is_equal_approx(game.jump_angle,TAU),label+': second half-turn reaches upright on landing without a large snap')
	check(game.player.ground and not game.jump_active,label+': landing ends the jump pose')
func check_stage_view():
	fixture()
	game.jump_request=true
	var fixed_view := true
	for tick in 100:
		game.step_game(DT)
		fixed_view = fixed_view and game.position == Vector2.ZERO
	check(fixed_view,'lower-floor jump leaves the stage and HUD framing fixed')

	for boosted in [false,true]:
		fixture()
		var upper_platform := Rect2(36,172,888,20)
		game.platforms.append(upper_platform)
		game.enemies=[game.new_enemy(Vector2(420,172),0,game.SNOW_MAX)]
		game.player.p=Vector2(420,126)
		game.step_game(DT)
		game.speed_up=boosted
		game.touch_fire=true
		var atlas := Image.new()
		var path := "res://assets/snowbro_speed.png" if boosted else "res://assets/snowbro.png"
		check(atlas.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,'camera test reads the selected actor atlas')
		game.jump_request=true
		var min_head := INF
		var max_boot := -INF
		var peak_scroll := 0.0
		var peak_foot := INF
		for tick in 120:
			game.step_game(DT)
			var aim := 1 if game.player.attack>.065 else 0
			var frame := Sprite.turn_frame(game.jump_angle,aim) if game.jump_active else Sprite.ground_frame(game.player,game.stride_distance,game.elapsed,game.landing_pose,game.landing_strength)
			var region := Sprite.speed_region(frame,game.elapsed) if boosted else Sprite.region(frame)
			var ink := atlas.get_region(Rect2i(region)).get_used_rect()
			var screen_foot := roundf(game.player.p.y)+float(game.position.y)
			min_head=minf(min_head,screen_foot+(ink.position.y-Sprite.FEET.y)*Sprite.PIXEL_SIZE)
			max_boot=maxf(max_boot,screen_foot+(ink.end.y-Sprite.FEET.y)*Sprite.PIXEL_SIZE)
			peak_scroll=maxf(peak_scroll,game.position.y)
			peak_foot=minf(peak_foot,game.player.p.y)
			if game.player.ground: break
		check(peak_foot<0 and min_head>=96 and max_boot<=522,
			'every sampled cel of an upper-snowball jump stays inside the visible playfield, red boots=%s'%boosted)
		check(game.player.standing==0 and game.position.y<peak_scroll and game.position.y>0,
			'camera descends after the apex and keeps the high-ball landing in view')
		if boosted:
			game.reset()
			check(game.position==Vector2.ZERO and game.stage_scroll_y==0.0,'reset restores the original frame during an elevated view')
		else:
			game.enemies.clear();game.platforms.erase(upper_platform)
			for tick in 150: game.step_game(DT)
			check(game.player.p.y==492 and game.position==Vector2.ZERO and game.stage_scroll_y==0.0,
				'falling back to the bottom floor naturally restores the original frame')

func run():
	await process_frame
	fixture()
	var result=flight()
	var floor_time: float=result.time
	var floor_height: float=result.height
	check(result.time>=.675 and result.time<=.69,'same-height airtime preserves the 0.36 s ascent and adds a 0.32 s descent')
	check(result.height>152 and result.height<155,'foot-based jump height fits the 0.16 screen-width target')
	check(result.at_half_second>PI and result.at_half_second<TAU-.5,'descent still performs second half-turn at 0.5 seconds')
	complete_turn(result,'same height')
	for i in 30: game.update_player(DT,0)
	check(game.player.ground and not game.jump_active,'consumed jump press does not auto-jump again on landing')
	fixture();game.platforms.append(Rect2(36,388,888,20))
	result=flight()
	check(is_equal_approx(game.player.p.y,388) and result.time<.60,'jump lands on the next platform before a same-height flight ends')
	complete_turn(result,'higher platform')
	fixture();game.player.p.x=240
	game.enemies=[game.new_enemy(Vector2(300,492),0,game.SNOW_MAX)]
	result=flight(1.0,true)
	check(game.player.standing==0 and is_equal_approx(game.player.p.y,446),'jump can land on a solid ball from the floor')
	complete_turn(result,'snowball top')
	fixture();game.player.p=Vector2(250,280);game.platforms.append(Rect2(100,280,200,20))
	result=flight(1.0)
	check(is_equal_approx(game.player.p.y,492) and result.time>.84,'jump past ledge lands on lower floor')
	complete_turn(result,'lower floor')
	fixture();game.jump_request=true;game.update_player(DT,1)
	var first_angle: float=game.jump_angle
	game.update_player(DT,-1)
	check(game.player.dir==-1 and game.jump_spin_dir==1 and game.jump_angle>first_angle,'air steering cannot reverse the somersault direction')
	fixture();game.player.p=Vector2(300,280);game.platforms.append(Rect2(100,280,200,20))
	for i in 15: game.update_player(DT,1)
	check(not game.player.ground and not game.jump_active and game.jump_angle==0,'walking off a ledge does not start a somersault')
	# Step off a platform, then press jump within or outside the three-frame grace.
	fixture();game.platforms.append(Rect2(100,280,200,20));game.player.p=Vector2(308,280)
	game.update_player(DT,1)
	check(not game.player.ground and game.ledge_grace>0,'natural edge exit opens the grace window')
	for i in 3: game.update_player(DT,1)
	game.jump_request=true;game.update_player(DT,1)
	check(game.jump_active and game.player.v.y<0,'jump pressed just past the ledge still takes off')
	var ascending_speed: float=game.player.v.y
	game.jump_request=true;game.update_player(DT,1)
	check(game.player.v.y>ascending_speed,'a second midair tap cannot repeat a grace jump')
	fixture();game.platforms.append(Rect2(100,280,200,20));game.player.p=Vector2(308,280)
	for i in 12: game.update_player(DT,1)
	game.jump_request=true;game.update_player(DT,1)
	check(game.player.v.y>0 and not game.jump_active,'walking well beyond a ledge cannot create a midair jump')
	fixture();game.begin_jump()
	for i in 75: game.update_player(DT,0)
	game.jump_request=true
	for i in 10: game.update_player(DT,0)
	check(game.player.v.y<0 and game.jump_active and game.jump_buffer==0,'a tap shortly before landing starts the next jump without a lost frame')
	fixture();game.begin_jump()
	for i in 55: game.update_player(DT,0)
	game.jump_request=true
	for i in 45: game.update_player(DT,0)
	check(game.player.ground and game.jump_buffer==0,'an early midair press expires before landing')
	fixture();game.begin_jump()
	for i in 120:
		game.update_player(DT,0)
		if game.player.ground: break
	check(game.landing_pose>0 and game.landing_strength>.9,'same-height contact produces a full-weight visual landing pose')
	var landed_x: float=game.player.p.x
	game.update_player(DT,1)
	check(game.player.p.x>landed_x and game.stride_distance>0.0,'landing pose allows immediate directional input and distance-based steps')
	game.jump_request=true;game.update_player(DT,1)
	check(game.player.v.y<0 and game.landing_pose==0,'ground recoil permits an immediate new jump')
	fixture();game.player.p=Vector2(908,492)
	game.update_player(DT,1)
	check(game.player.p.x==908 and game.player.dir==1 and game.player.v.x==0,'holding toward a wall keeps firing direction and planted feet')
	fixture();game.platforms.append(Rect2(36,388,888,20))
	game.player.p=Vector2(200,350);game.player.ground=false;game.player.v=Vector2(0,1500)
	game.update_player(.12,0)
	check(game.player.ground and game.player.p.y==388,'a descending foot hits the first crossed floor regardless of platform ordering')
	fixture();game.player.p=Vector2(180,172);game.platforms.append(Rect2(36,172,888,20))
	result=flight(1.0)
	check(absf(result.height-floor_height)<.01 and absf(result.time-floor_time)<DT and game.player.p.y==172,
		'top and bottom platform jumps have the same height and airtime')
	complete_turn(result,'top-floor jump')
	var jump_key=InputEventKey.new()
	jump_key.physical_keycode=KEY_SPACE; jump_key.pressed=true
	game._input(jump_key); game.update_player(DT,-1)
	check(game.player.v.y<0 and game.player.dir==-1,'upper-floor landing immediately accepts a directed jump')
	fixture();game.platforms.append(Rect2(36,172,240,20));game.platforms.append(Rect2(360,172,240,20))
	game.player.p=Vector2(272,172)
	result=flight(1.0)
	check(game.player.p.x>351.0 and game.player.p.y==172,'a top-floor hop begun inside the visible ledge crosses the original platform gap')
	fixture();game.platforms.append(Rect2(36,172,888,20))
	var high_ball=game.new_enemy(Vector2(420,172),0,game.SNOW_MAX)
	game.enemies=[high_ball]
	game.player.p=Vector2(420,120); game.player.ground=false; game.player.v=Vector2(0,150)
	for i in 12: game.update_player(DT,0)
	check(game.player.standing==high_ball.id and game.player.p.y==126,'upper-floor snowball supports a player above the highest platform')
	result=flight()
	check(absf(result.height-floor_height)<.01 and absf(result.time-floor_time)<DT and game.player.standing==high_ball.id,
		'jump from the upper snowball crests above world zero and returns to its surface with full airtime')
	complete_turn(result,'upper-floor snowball')
	game.kick_ball(high_ball,1);game.begin_ride(high_ball)
	var release_y: float=high_ball.p.y-48.0
	game._web_command([JSON.stringify({'type':'jump'})]);game.update_player(DT,0)
	var expected_y: float=release_y-game.PLAYER_JUMP_SPEED*DT+.5*game.PLAYER_GRAVITY*DT*DT
	check(game.player.ride==-1 and absf(game.player.p.y-expected_y)<.01 and game.player.v.x>0,
		'web jump dismounts immediately from the actual upper ball position with horizontal momentum')
	var peak_y: float=game.player.p.y
	for i in 120:
		game.update_player(DT,0)
		peak_y=minf(peak_y,game.player.p.y)
		if game.player.ground: break
	check(absf((release_y-peak_y)-floor_height)<.01 and game.player.ground and game.player.p.y==172,
		'dismount reaches full jump height above its release point and lands on the top platform')
	fixture();game.practice=false;game.platforms.append(Rect2(36,172,888,20))
	var enemy=game.new_enemy(Vector2(300,172),0)
	enemy.jump=0;game.enemies=[enemy]
	var highest_enemy := 172.0
	for i in 110:
		game.step_game(DT);highest_enemy=minf(highest_enemy,enemy.p.y)
	check(highest_enemy>=game.ENEMY_CEILING-.01 and highest_enemy<156 and enemy.ground,
		'top-floor AI jump keeps its horns below the HUD and returns to the platform')
	var ball=game.new_enemy(Vector2(290,172),1,game.SNOW_MAX)
	game.kick_ball(ball,1);game.roll_hit(ball,enemy)
	var highest_body := 172.0
	for i in 120:
		game.update_defeated(DT)
		if not game.defeated.is_empty(): highest_body=minf(highest_body,game.defeated.front().p.y)
	check(highest_body>=game.DEFEATED_CEILING-.01 and game.gifts.size()==1 and game.gifts[0].p.y==172,
		'upper-floor defeated opponent tumbles below the HUD and drops its reward back onto the top floor')
	check_stage_view()
	print('%d JUMP CHECKS PASSED, %d FAILED'%[passes,failures]);quit(1 if failures>0 else 0)
