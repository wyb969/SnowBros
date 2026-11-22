extends SceneTree
var game
var passes=0
var failures=0
const DT=1.0/120.0
func _initialize():
	game=load('res://scenes/main.tscn').instantiate()
	root.add_child.call_deferred(game);run.call_deferred()
func check(ok,message):
	if ok:passes+=1;print('PASS: '+message)
	else:failures+=1;push_error('FAIL: '+message)
func fixture():
	game.reset(true);game.set_physics_process(false);game.muted=true;game.invincible=99
	game.enemies.clear();game.gifts.clear();game.platforms.clear();game.platforms.append(Rect2(36,492,888,28))
func jump_flight():
	var start:float=game.player.p.y
	var data={'height':0.0,'apex_time':0.0,'duration':0.0}
	game.jump_request=true
	for i in 180:
		game.update_player(DT,0);data.duration+=DT
		if start-game.player.p.y>data.height:data.height=start-game.player.p.y;data.apex_time=data.duration
		if game.player.ground:break
	return data
func run():
	await process_frame
	fixture();game.player.p.x=102.0/220.0*960.0
	var positions=[102.0];var match_sample=true
	for i in 5:
		for j in 20:game.update_player(DT,1)
		var normalized_x:float=game.player.p.x/960.0*220.0
		positions.append(normalized_x)
		if absf(normalized_x-(110+i*8))>.5:match_sample=false
	print('Walk sequence at W=220, 1/6 s intervals: ',positions)
	check(match_sample,'measured six-position walk sequence is reproduced within half a sample pixel')
	check(absf(game.player.v.x/960.0-.22)<.001,'steady walking matches 0.22 screen widths per second')
	fixture();var start:Vector2=game.player.p
	for i in 120:game.update_player(DT,.5)
	check(absf((game.player.p.x-start.x)/960.0-.11)<.001,'half joystick keeps half of the normalized steady speed')
	fixture();game.gifts=[{'p':game.player.p,'life':2.0,'kind':'red'}];game.step_game(.001);game.update_player(DT,1)
	check(game.player.v.x/960.0>.27 and game.speed_up,'red bottle still boosts walking')
	fixture();game.touch_fire=true
	for i in 23:game.step_game(DT)
	check(game.shots.size()>=2 and game.next_shot>=2,'held fire keeps multiple independent snow effects in flight')
	fixture();var enemy=game.new_enemy(Vector2(330,492),0);game.enemies=[enemy];game.touch_fire=true
	for i in 60:game.step_game(DT)
	check(enemy.snow>0 and enemy.snow<game.SNOW_MAX and not enemy.roll,'actual repeated fire exposes a partial-snow state before a full ball')
	for i in 120:game.step_game(DT)
	check(enemy.snow==game.SNOW_MAX and not enemy.roll and enemy.p==Vector2(330,492),'full snow remains stationary after more distant snow shots')
	game.touch_fire=false;game.player.p=Vector2(292,492);game.attack()
	check(enemy.roll and enemy.v.x/960.0>1.24,'a separate close-range attack launches the completed ball')
	fixture();var jump=jump_flight()
	print('Feet: jump height=',jump.height,' px, apex=',jump.apex_time,' s, same-height test flight=',jump.duration,' s')
	check(jump.height/960.0>=.15 and jump.height/960.0<=.18,'foot height fits the proposed 0.15–0.18 width range')
	check(jump.apex_time>=.33 and jump.apex_time<=.40,'foot apex fits the proposed 0.33–0.40 second window')
	check(game.player.p.y==492 and game.player.ground and not game.jump_active,'same-height fit returns to exact floor contact with the turn complete')
	var same_height_time:float=jump.duration
	fixture();game.platforms.append(Rect2(36,388,888,20));jump=jump_flight()
	check(game.player.p.y==388 and jump.duration<same_height_time,'higher-platform landing is handled separately from the same-height test')
	fixture();var ball=game.new_enemy(Vector2(200,492),0,game.SNOW_MAX);game.kick_ball(ball,1)
	for i in 40:game.move_ball(ball,DT)
	var normalized_roll:float=(ball.p.x-200)/960.0/(40.0/120.0)
	print('Roll: ',normalized_roll,' W/s, displacement at W=220 in 1/3 s=',(ball.p.x-200)/960.0*220.0)
	check(normalized_roll>1.24 and normalized_roll<1.30,'unobstructed ball travel matches about 1.27 screen widths per second')
	check(absf((ball.p.x-200)/960.0*220.0-94.0)<2,'rolling sample covers about 94 pixels on a 220-wide frame')
	check(normalized_roll/.22>5.4 and normalized_roll/.22<6.1,'ball-to-walk speed ratio follows the supplied samples')
	fixture();game.web_axis=1;game.jump_request=true
	for i in 12:game._physics_process(1.0/30)
	var at_30:Vector2=game.player.p
	fixture();game.web_axis=1;game.jump_request=true
	for i in 48:game._physics_process(DT)
	check(at_30.distance_to(game.player.p)<.01,'walking and foot trajectory agree at 30 Hz and 120 Hz')
	print('%d REFERENCE FEEL CHECKS PASSED, %d FAILED'%[passes,failures]);quit(1 if failures else 0)
