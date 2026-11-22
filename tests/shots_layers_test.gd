extends SceneTree
var game
var original_platforms: Array[Rect2]
var passes=0
var failures=0
const DT=1.0/120.0
func _initialize():
	game=load('res://scenes/main.tscn').instantiate()
	root.add_child.call_deferred(game);run.call_deferred()
func check(ok,message):
	if ok: passes+=1;print('PASS: '+message)
	else: failures+=1;push_error('FAIL: '+message)
func fixture():
	game.reset(true);game.set_physics_process(false);game.muted=true
	game.enemies.clear();game.gifts.clear();game.invincible=99
	game.platforms.assign(original_platforms)
func ball(pos,id=0): return game.new_enemy(pos,id,game.SNOW_MAX)
func pickup(kind):
	game.gifts=[{'p':game.player.p,'life':2.0,'kind':kind}];game.step_game(.001)
func fire():
	game.attack();return game.shots.back()
func run():
	await process_frame
	original_platforms.assign(game.platforms)
	fixture()
	var shot=fire()
	var normal_size: Vector2=game.shot_extent(shot)
	var normal_life: float=shot.duration
	var start: Vector2=shot.p
	var normal_reach:float=game.shot_path(shot,shot.duration).x-shot.origin.x
	for i in 6: game.update_shots(DT)
	check((shot.p.x-start.x)/.05/960.0>1.85 and (shot.p.x-start.x)/.05/960.0<2.08,'snow initial horizontal speed matches the normalized reference')
	check(absf(shot.p.y-start.y)<2,'snow leaves almost level rather than bending downward immediately')
	fixture();game.player.dir=-1;shot=fire();start=shot.p
	for i in 6:game.update_shots(DT)
	check(shot.p.x<start.x-90 and absf(shot.p.y-start.y)<2,'left-facing snow has the same fast near-level launch')
	fixture();pickup('blue');shot=fire()
	var blue_size: Vector2=game.shot_extent(shot)
	check(blue_size.x>normal_size.x*1.5 and blue_size.y>normal_size.y*1.5 and shot.power==2,'blue bottle enlarges the flake in both dimensions and increases snow power')
	check(is_equal_approx(shot.life,normal_life) and not shot.extended,'blue alone leaves long-range behavior independent')
	fixture();pickup('yellow');shot=fire()
	var yellow_size: Vector2=game.shot_extent(shot)
	check(yellow_size.x>normal_size.x*2 and is_equal_approx(yellow_size.y,normal_size.y),'yellow bottle visibly lengthens snow without making it blue-sized')
	check(game.shot_path(shot,shot.duration).x-shot.origin.x>normal_reach*1.4 and shot.power==1,'yellow also extends range without changing snow power')
	fixture();pickup('blue');pickup('yellow');shot=fire()
	var combined_size: Vector2=game.shot_extent(shot)
	check(combined_size.x>blue_size.x*2 and is_equal_approx(combined_size.y,blue_size.y),'blue and yellow upgrades combine size and length')
	fixture();shot=fire();pickup('blue');pickup('yellow')
	check(game.shot_extent(shot)==normal_size,'picking up a bottle does not reshape snow already in flight')
	fixture();var target=game.new_enemy(Vector2(150,517),0);game.enemies=[target];fire();game.update_shots(.001)
	check(target.snow==0,'normal flake misses a target outside its vertical reach')
	fixture();pickup('blue');target=game.new_enemy(Vector2(150,517),0);game.enemies=[target];fire();game.update_shots(.001)
	check(target.snow==2,'blue enlargement increases the real hit area')
	fixture();target=game.new_enemy(Vector2(180,492),0);game.enemies=[target];fire();game.update_shots(.001)
	check(target.snow==0,'normal flake does not hit ahead of its visible body')
	fixture();pickup('yellow');target=game.new_enemy(Vector2(180,492),0);game.enemies=[target];fire();game.update_shots(.001)
	check(target.snow==1,'yellow length increases the real horizontal hit area')
	fixture();var near_target=game.new_enemy(Vector2(165,492),0);var far_target=game.new_enemy(Vector2(170,492),1)
	game.enemies=[far_target,near_target];fire();game.update_shots(.001)
	check(near_target.snow==1 and far_target.snow==0,'snow hits the nearest target first regardless of enemy list order')
	fixture();var a=ball(Vector2(300,492),0);var b=ball(Vector2(315,492),1);game.enemies=[a,b]
	for i in 60:game.step_game(DT)
	check(a.p==Vector2(300,492) and b.p==Vector2(315,492),'idle full snowballs can remain overlapped without separation')
	fixture();a=ball(Vector2(300,492),0);b=ball(Vector2(400,492),1);game.enemies=[a,b];game.player.p=Vector2(262,492);game.web_axis=1
	for i in 210:game.step_game(DT)
	check(absf(a.p.x-b.p.x)<2 and b.p.x>410,'walking can push one snowball into another and then move the overlapped stack')
	check(not a.roll and not b.roll and game.score==0,'overlap pushing never becomes an attack or credits a kick')
	check(game.player.p.x<minf(a.p.x,b.p.x)-36,'player remains outside the pushed snowballs')
	fixture()
	for i in 3:game.enemies.push_front(ball(Vector2(300+i*20,492),i))
	game.player.p=Vector2(262,492);game.web_axis=1
	for i in 150:game.step_game(DT)
	var leftmost: float=game.enemies.map(func(e):return e.p.x).min()
	var rightmost: float=game.enemies.map(func(e):return e.p.x).max()
	check(rightmost-leftmost<2 and leftmost>370,'three balls also merge while pushing in reversed entity order')
	fixture()
	for i in 3:game.enemies.append(ball(Vector2(895+i*7,492),i))
	game.player.p=Vector2(857,492);game.web_axis=1
	for i in 120:game.step_game(DT)
	check(game.enemies.all(func(e):return e.p.x<=910 and e.p.x>=908 and not e.roll),'overlapped push remains bounded at a wall')
	fixture();a=ball(Vector2(300,492));game.enemies=[a];game.player.p=Vector2(262,492);game.web_axis=1
	for i in 120:game.step_game(DT)
	var normal_push: float=a.p.x-300
	fixture();pickup('red');a=ball(Vector2(300,492));game.enemies=[a];game.player.p=Vector2(262,492);game.web_axis=1
	for i in 120:game.step_game(DT)
	check(a.p.x-300>normal_push*1.4 and not a.roll,'red bottle increases slow-push speed while keeping it a push')
	fixture()
	for i in 3:game.enemies.append(ball(Vector2(300+i*.5,492),i))
	game.player.p=Vector2(262,492);game.attack();a=game.enemies[0]
	check(game.enemies.all(func(e):return e.roll and e.chain_id==a.chain_id) and game.score==1500,'kicking an overlapped stack releases all members in one scoring chain')
	for i in 20:game.step_game(DT)
	check(game.enemies.all(func(e):return e.p.y==492 and e.v.x>570) and absf(game.enemies[2].p.x-a.p.x)<2,'released stack stays overlapped and does not bounce against itself')
	fixture();a=ball(Vector2(300,388),0);b=ball(Vector2(347,396),1);game.kick_ball(a,1)
	var pa: Vector2=a.p;var pb: Vector2=b.p
	game.collide_balls(a,b)
	check(a.p==pa and b.p==pb and a.v.y==0 and b.v.y==0,'ball collision changes horizontal momentum without pushing bodies upward')
	check(a.v.x<0 and b.v.x>0 and a.roll and b.roll,'separate ball contact still rebounds and propagates the attack')
	a.v.x=580;b.v.x=-580;game.collide_balls(a,b)
	check(a.v.x==580 and b.v.x==-580,'one continuous overlap cannot repeatedly pump collision impulses')
	b.p.x=450;game.collide_balls(a,b);b.p.x=347;game.collide_balls(a,b)
	check(a.v.x<0 and b.v.x>0,'after separating the same snowballs can collide again')
	fixture();game.platforms.clear()
	for y in [492,388,280]:game.platforms.append(Rect2(36,y,888,20))
	a=ball(Vector2(400,200));game.kick_ball(a,1);a.ground=false;a.v.y=3000
	game.move_ball(a,.12)
	check(a.p.y==280 and a.ground,'fast falling snowball lands on the first crossed platform despite bottom-first storage order')
	check(a.v.y==0,'rolling landing settles instead of bouncing back up through the previous layer')
	fixture();a=ball(Vector2(909,172));game.kick_ball(a,1);game.move_ball(a,DT)
	check(a.bounces==1 and a.p.y==172 and not a.dead,'wall rebound on a supported upper floor does not teleport the ball down')
	fixture();a=ball(Vector2(611,172));game.kick_ball(a,1);game.move_ball(a,DT)
	check(a.p.y>176 and a.v.y>=game.ROLL_DROP_SPEED,'leaving a ledge starts the fast downward roll seen in the reference')
	fixture();a=ball(Vector2(480,172));game.kick_ball(a,1)
	var rows=[172.0];var monotonic=true;var previous_y=172.0
	for i in 800:
		game.move_ball(a,DT)
		if a.p.y<previous_y-.01:monotonic=false
		previous_y=a.p.y
		if a.ground and not rows.has(a.p.y):rows.append(a.p.y)
		if a.dead:break
	print('Observed game route: ',rows)
	check(rows==[172.0,280.0,388.0,492.0],'actual level route catches all available lower floors in order')
	check(monotonic,'ordinary rolling and collisions do not climb to an earlier layer')
	fixture();a=ball(Vector2(480,172));b=a.duplicate(true);game.kick_ball(a,1);game.kick_ball(b,1)
	game.enemies=[a]
	for i in 72:game._physics_process(1.0/30)
	var route_position: Vector2=a.p
	game.enemies=[b]
	for i in 288:game._physics_process(DT)
	check(route_position.distance_to(b.p)<.2,'fall, landing and wall route agree at 30 Hz and 120 Hz')
	print('%d SHOT / STACK / LAYER CHECKS PASSED, %d FAILED'%[passes,failures]);quit(1 if failures else 0)
