extends SceneTree
var game
var passes=0
var failures=0
func _initialize():
	game=load('res://scenes/main.tscn').instantiate()
	root.add_child.call_deferred(game); run.call_deferred()
func check(ok,message):
	if not ok:
		push_error('FAIL: '+message); failures+=1; return
	passes+=1; print('PASS: '+message)
func fixture():
	game.practice_case=0; game.reset(true); game.muted=true; game.enemies.clear(); game.gifts.clear(); game.invincible=0; game.set_physics_process(false)
func ball(pos,id=0):
	return game.new_enemy(pos,id,game.SNOW_MAX)
func run():
	await process_frame
	fixture()
	var b=ball(Vector2(300,492));game.enemies=[b]
	game.player.p=Vector2(280,492)
	game.update_player(1.0/120,0)
	check(game.player.p.x<=b.p.x-38,'idle snowball physically blocks player')
	var start: float=b.p.x
	for i in 120: game.update_player(1.0/120,1)
	check(absf(b.p.x-start-68)<.1 and game.player.pushing,'directional contact pushes slowly without attack')
	check(not b.roll,'slow pushing does not activate fast roll')
	game.player.p=b.p-Vector2(0,64); game.player.v=Vector2(0,220)
	game.update_player(.08,0)
	check(game.player.ground and absf(game.player.p.y-(b.p.y-46))<.1,'falling player can stand on ball')
	fixture(); b=ball(Vector2(480,388)); game.enemies=[b]
	game.player.p=Vector2(480,480); game.begin_jump()
	for i in 12: game.update_player(1.0/120,0)
	check(b.v.y<-200 and not b.roll,'jumping from below bumps ball upward without kicking')
	fixture(); b=ball(Vector2(300,492)); game.enemies=[b]
	game.player.p=Vector2(262,492); game.player.dir=-1; game.attack()
	check(not b.roll and game.shots.size()==1,'ball behind player is not remotely kicked')
	game.player.dir=1; game.attack()
	check(b.roll and b.v.x>=570 and game.score==500,'front contact attack launches ball and awards once')
	game.kick_ball(b,1)
	check(game.score==500,'repeated kicks do not duplicate capture score')
	fixture(); b=ball(Vector2(200,492)); game.kick_ball(b,1); b.v.y=0
	var launch_speed:float=b.v.x
	for i in 30: game.move_ball(b,1.0/120)
	check(b.v.x/launch_speed>.998,'unobstructed ice glide retains near launch speed')
	fixture(); b=ball(Vector2(909,172));game.kick_ball(b,1);b.v.y=0
	game.move_ball(b,1.0/120)
	check(b.v.x<-560 and not b.dead,'upper wall rebound keeps most speed')
	fixture(); var a=ball(Vector2(300,492),0);b=ball(Vector2(347,492),1)
	game.kick_ball(a,1);game.kick_ball(b,-1);game.enemies=[a,b]
	game.collide_balls(a,b)
	check(a.v.x<0 and b.v.x>0 and not a.dead and not b.dead,'opposing snowballs rebound and both survive')
	check(game.combo_time>0 and game.notice_time>0,'ball collision has local effects and UI feedback')
	fixture();a=ball(Vector2(300,492),0);b=ball(Vector2(347,492),1);game.enemies=[a,b]
	game.kick_ball(a,1);game.collide_balls(a,b)
	check(b.roll and b.v.x>550,'rolling ball transfers momentum to idle ball')
	fixture(); b=ball(Vector2(300,492));game.kick_ball(b,1);game.enemies=[b]
	game.player.p=Vector2(290,492);game.update_player(1.0/120,0)
	check(game.player.ride==b.id,'player is carried by contacting rolling ball')
	game.jump_request=true;game.update_player(1.0/120,0)
	check(game.player.ride==-1 and game.player.v.y<-400 and game.player.ride_lock>0,'jump leaves ball and prevents immediate reentry')
	fixture(); b=ball(Vector2(600,388));game.kick_ball(b,1);
	for i in 15: game.move_ball(b,1.0/120)
	check(b.p.x>600 and b.p.y>388,'ball falls after leaving platform edge')
	fixture(); var target=game.new_enemy(Vector2(450,492),0);game.enemies=[target]
	game.player.p=Vector2(130,492)
	for i in game.SNOW_MAX:
		game.shots.append({'p':Vector2(450,470),'dir':1,'life':.5,'power':1})
		game.step_game(.001)
	check(target.snow==game.SNOW_MAX and not target.roll,'normal model hits freeze to solid idle ball')
	fixture();game.enemies=[game.new_enemy(Vector2(850,172),0)]
	for kind in ['red','blue','yellow']:
		game.gifts=[{'p':game.player.p,'life':2.0,'kind':kind}];game.step_game(.001)
	check(game.speed_up and game.power_up and game.range_up and game.notice_time>0,'three pickups update powers and notice')
	game.attack(); var shot=game.shots.back()
	check(shot.power==2 and shot.extended and shot.life>.35,'power and range affect projectile separately')
	fixture();b=ball(Vector2(300,492));game.enemies=[b];game.kick_ball(b,1)
	var victim=game.new_enemy(Vector2(335,492),1);game.enemies.append(victim);game.step_game(.001)
	check(game.enemies.size()==1 and game.defeated.size()==1 and game.gifts.is_empty() and game.score==1500,'rolling hit starts defeated flight before reward drop')
	game.practice=false;game.enemies.clear();game.gifts.clear();game.step_game(.001)
	check(game.state=='play','clear waits for defeated flight and pending drops')
	game.defeated.clear();game.step_game(.001)
	check(game.state=='clear','empty cleared playfield ends first level')
	fixture();game.lives=1;game.enemies=[game.new_enemy(game.player.p,0)];game.step_game(.001)
	check(game.state=='over','enemy contact with last life ends game')
	fixture();a=ball(Vector2(200,492));b=a.duplicate(true);game.kick_ball(a,1);game.kick_ball(b,1)
	game.enemies=[a];for i in 30: game._physics_process(1.0/30)
	var pos: Vector2=a.p
	game.enemies=[b];for i in 120: game._physics_process(1.0/120)
	check(pos.distance_to(b.p)<.2,'substeps preserve trajectory at 30Hz and 120Hz')

	fixture();b=ball(Vector2(200,492));game.enemies=[b];game.kick_ball(b,1);game.player.p=Vector2(130,172)
	for i in 4: game.enemies.append(game.new_enemy(Vector2(350+i*130,492),i+1,i%3))
	for i in 132:
		game.step_game(1.0/120)
		if game.chains[b.chain_id]>=4:break
	check(game.score==10500 and game.chains[b.chain_id]==4,'one ball hits four targets for 500 + 1000 + 2000 + 3000 + 4000')
	check(not b.dead and b.v.x>game.ROLL_SPEED*.95,'four impacts do not stop the attacking ball')
	check(game.defeated.size()==4,'defeated targets remain visible in flight')
	var previous_score: int=game.score
	game.roll_hit(b,game.defeated[0])
	check(game.score==previous_score,'already defeated target cannot score twice')
	for i in 360: game.update_defeated(1.0/120)
	check(game.defeated.is_empty() and game.gifts.size()==4,'each defeated flight produces exactly one settled reward')
	for i in 60: game.update_defeated(1.0/120)
	check(game.gifts.size()==4,'settled rewards are not duplicated')
	fixture()
	for i in 3: game.enemies.append(ball(Vector2(300+i*150,492),i))
	a=game.enemies[0];game.kick_ball(a,1);game.player.p=Vector2(130,172)
	for i in 50:
		game.step_game(1.0/120)
		if game.enemies.size()==3 and game.enemies.all(func(e):return e.roll):break
	check(game.enemies.size()==3 and game.enemies.all(func(e):return e.roll and e.credited),'chain activates all three balls without deleting them')
	check(game.enemies.all(func(e):return absf(e.v.x)>300),'incoming ball keeps moving after chain activation')
	check(game.enemies.all(func(e):return e.chain_id==a.chain_id),'propagated balls share the same scoring chain')
	check(game.score==1500,'three activated balls credit each frozen enemy once')
	fixture();var partial=game.new_enemy(Vector2(400,492),1,2);game.enemies=[partial]
	game.snow_hit(partial,{'p':Vector2(400,470),'dir':1,'power':1})
	var partial_start: Vector2=partial.p
	check(partial.snow==3 and partial.v==Vector2.ZERO and partial.ground and not partial.dead,'snow hit freezes living target in place without impulse')
	for i in 4: game.step_game(1.0/120)
	check(partial.p.is_equal_approx(partial_start),'half-frozen target remains stationary after hit')
	check(game.defeated.is_empty() and game.gifts.is_empty() and game.score==10,'ordinary snow does not produce a defeated flight or kill reward')
	game.practice=false
	for i in 90: game.step_game(1.0/120)
	check(partial.p.is_equal_approx(partial_start) and partial.snow==3 and not partial.dead,'active AI cannot move a partially frozen enemy')
	game.snow_hit(partial,{'p':Vector2(400,470),'dir':-1,'power':1})
	for i in 30: game.step_game(1.0/120)
	check(partial.p.is_equal_approx(partial_start) and partial.v==Vector2.ZERO and partial.snow==4,'repeated shots from either side add snow without pushing')
	b=ball(Vector2(360,492));game.kick_ball(b,1);game.roll_hit(b,partial)
	check(partial.dead and game.defeated.size()==1,'rolling attack defeats partial enemy through a separate flight state')
	fixture();partial=game.new_enemy(Vector2(400,340),1,1);partial.ground=false;partial.v=Vector2(48,120);game.enemies=[partial]
	game.snow_hit(partial,{'p':Vector2(400,318),'dir':-1,'power':1})
	check(partial.v==Vector2(0,120),'airborne snow hit adds no upward or sideways impulse')
	for i in 10: game.step_game(1.0/120)
	check(is_equal_approx(partial.p.x,400) and partial.p.y>340,'airborne frozen target falls under gravity without horizontal recoil')
	fixture();b=ball(Vector2(300,492));game.enemies=[b]
	game.snow_hit(b,{'p':Vector2(300,470),'dir':1,'power':2})
	check(not b.roll and b.v==Vector2.ZERO,'distant snow shot cannot launch a completed ball')
	fixture();b=ball(Vector2(200,492));game.enemies=[b];game.kick_ball(b,1);b.v.x=5000;game.player.p=Vector2(130,172)
	game.enemies.append(game.new_enemy(Vector2(300,492),1))
	game.enemies.append(game.new_enemy(Vector2(400,492),2))
	game.step_game(.05)
	check(game.chains[b.chain_id]==2,'swept attack catches targets crossed between frame positions')
	# Coarse single steps deliberately exceed a ball diameter and cross several
	# contacts. These catch endpoint-only or storage-order-dependent collisions.
	fixture(); a=ball(Vector2(300,492),0); b=ball(Vector2(412,492),1)
	game.enemies=[b,a]; game.kick_ball(a,1); game.kick_ball(b,-1)
	a.v.x=2000; b.v.x=-2000; game.step_game(.04)
	check(a.v.x<0 and b.v.x>0 and a.p.x<300 and b.p.x>412, 'crossing fast balls rebound at first contact and use the rest of the frame')
	fixture(); a=ball(Vector2(300,492),0); b=ball(Vector2(370,492),1)
	victim=game.new_enemy(Vector2(430,492),2)
	game.enemies=[victim,b,a]; game.kick_ball(a,1); a.v.x=3000; game.step_game(.05)
	check(a.p.x<300 and b.p.x>430 and victim.dead and game.defeated.size()==1, 'rebound and transmitted roll resolve in order, even with reversed enemy storage')
	check(a.chain_id==b.chain_id and game.chains[a.chain_id]==1 and game.score==2000, 'the transmitted hit is scored once on the original chain')
	fixture(); a=ball(Vector2(870,492)); victim=game.new_enemy(Vector2(808,492),1)
	game.enemies=[victim,a]; game.kick_ball(a,1); game.step_game(.12)
	check(a.floor_bounces==1 and a.p.x<820 and not a.dead and victim.dead and game.defeated[0].v.x<0, 'floor wall returns the ball and can hit a target on the reflected leg')
	a.p=Vector2(51,492); a.ground=true; game.move_ball(a,.01)
	check(a.dead and a.floor_bounces==2, 'second floor-wall contact ends the run after one return sweep')
	fixture(); a=ball(Vector2(500,492)); victim=game.new_enemy(Vector2(550,540),1)
	victim.previous=Vector2(550,440); game.kick_ball(a,1); a.v.x=2000
	game.advance_snowballs([a],[victim],.05)
	check(victim.dead and game.defeated[0].origin.y<505, 'moving target crossing the swept ball is hit at its actual contact position')
	fixture(); a=ball(Vector2(300,492)); game.enemies=[a]; game.kick_ball(a,1); a.v.x=5000
	game.player.p=Vector2(420,492); game.step_game(.05)
	check(game.player.ride==a.id and game.player.p==a.p, 'fast ball crossing between player samples carries the player to its resolved position')
	game.jump_request=true; game.step_game(1.0/120)
	check(game.player.ride==-1 and game.player.v.y<0 and game.player.ride_lock>0, 'jumping out of a swept pickup does not reattach in the same tick')
	for case_id in 4:
		game.reset(true,case_id)
		check(game.practice and game.practice_case==case_id and not game.enemies.is_empty(),'practice case %d initializes'%case_id)
	check(game.sound_bank.size()==7,'synthesized feedback sound bank initializes')

	print('%d CHECKS PASSED, %d FAILED'%[passes,failures]);quit(1 if failures>0 else 0)
