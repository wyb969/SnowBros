extends SceneTree
var game
var passes=0
var failures=0
func _initialize():
	game=load('res://scenes/main.tscn').instantiate()
	root.add_child.call_deferred(game);run.call_deferred()
func check(ok,message):
	if ok:passes+=1;print('PASS: '+message)
	else:failures+=1;push_error('FAIL: '+message)
func shot(extended=false,direction=1,power=1,phase=0.0):
	var s=game.make_shot(Vector2(100,300),direction,power,extended)
	s.phase=phase;return s
func reset_shots():
	game.reset(true)
	game.enemies.clear()
	game.gifts.clear()
	game.muted=true
	game.set_physics_process(false)

func maximum_ground_spacing(blue: bool,yellow: bool) -> int:
	var muzzle:Vector2=game.player.p+Vector2(20,-24)
	var near:=36
	var far:=750
	while far-near>1:
		var gap:=floori((near+far)*.5)
		var target=game.new_enemy(game.player.p+Vector2(gap,0),0)
		var flake=game.make_shot(muzzle,1,2 if blue else 1,yellow)
		flake.phase=0.0
		game.enemies=[target];game.shots=[flake];game.update_shots(flake.duration)
		if target.snow>0: near=gap
		else: far=gap
	return near

func test_volley_and_range():
	for hz in [60,120,144]:
		reset_shots()
		game.set_touch_fire(true)
		var events: Array[float]=[]
		var dt:=1.0/float(hz)
		for frame in range(hz*2):
			var count:int=game.next_shot
			game.step_game(dt)
			if game.next_shot!=count: events.append(frame*dt)
		var on_time:=events.size()>=2 and events[0]==0.0
		for i in events.size():
			if absf(events[i]-i*game.SHOT_INTERVAL)>dt+.00001: on_time=false
		check(on_time,'held shots at %d Hz keep their interval within a single tick over two seconds'%hz)
		check(events.size()>8 and absf(events[8]-events[0]-1.60)<=dt+.00001,'first-to-ninth shot follows the 1.60 s stationary arcade sample at %d Hz'%hz)
	for hz in [30,60,120]:
		for mode in ["tap","held","spam"]:
			reset_shots()
			var tick_step:=roundi(float(hz)/10.0)
			var events: Array[int]=[]
			for frame in range(hz):
				var n:int=game.next_shot
				if mode=="held" or mode=="spam" or frame%tick_step==0:
					game._web_command(['{"type":"input","fire":true}'])
					if mode!="held":
						game._web_command(['{"type":"input","fire":false}'])
				game._physics_process(1.0/hz)
				if game.next_shot!=n: events.append(frame)
			var count:=5 if mode=="held" else 10
			check(events.size()==count and events[0]==0,'%s at %d Hz respects distinct held and fresh-edge caps over one second'%[mode,hz])
	reset_shots()
	var dt:=1.0/120.0
	# Both touch transitions may reach Godot between the same two physics ticks.
	game._web_command(['{"type":"input","fire":true}'])
	game._web_command(['{"type":"input","fire":false}'])
	game.step_game(dt)
	check(game.next_shot==1 and not game.touch_fire,'a tap ending between simulation ticks fires once')
	var ticks:int=roundi(game.SHOT_INTERVAL/dt)
	for i in range(ticks-1):
		game.step_game(dt)
	game._web_command(['{"type":"input","fire":true}'])
	game._web_command(['{"type":"input","fire":false}'])
	game.step_game(dt)
	check(game.next_shot==2,'a released tap on the recovery boundary fires on the next eligible tick')
	for i in range(2*ticks):game.step_game(dt)
	check(game.next_shot==2,'a released button does not start automatic fire')
	game.set_touch_fire(true); game.set_touch_fire(false); game.release_controls(); game.step_game(dt)
	check(game.next_shot==2,'cancel or pause discards pending taps')
	reset_shots()
	game.set_touch_fire(true);game.step_game(dt);game.set_touch_fire(false)
	for i in 3:game.step_game(dt)
	game.set_touch_fire(true);game.set_touch_fire(false)
	for i in 6:game.step_game(dt)
	check(game.next_shot==1,'a too-early released tap cannot queue an attack indefinitely')
	game.set_touch_fire(true);game.set_touch_fire(false)
	for i in 3:game.step_game(dt)
	check(game.next_shot==2,'an edge near the manual recovery boundary survives release for the remaining ticks')
	game.set_touch_fire(true);game.step_game(dt);reset_shots()
	game.set_touch_fire(true);game.step_game(dt)
	check(game.next_shot==1,'restart clears the previous shot cooldown and accepts the first press')
	for yellow in [false,true]:
		for blue in [false,true]:
			reset_shots()
			var muzzle:Vector2=game.player.p+Vector2(20,-24)
			var s=game.make_shot(muzzle,1,2 if blue else 1,yellow)
			s.phase=0.0;game.shots=[s];game.update_shots(s.duration)
			var on_floor:float=s.p.x-muzzle.x
			var ground_time:float=s.age
			var end:Vector2=game.shot_path(s,s.duration)-muzzle
			var target_gap:=maximum_ground_spacing(blue,yellow)
			print('Range measurements blue=',blue,' yellow=',yellow,' muzzle to floor=',on_floor,' first contact at ',ground_time,
				' s; unobstructed max=',end,' target center to player center=',target_gap)
			check(on_floor>0 and end.x>=on_floor and target_gap>on_floor,'floor contact, open-air fall and target-center range measured independently')
			if not blue and not yellow:
				check(on_floor>=160 and on_floor<=180,'ordinary standing flake reaches the original first-floor muzzle-to-contact range band')
			if blue and yellow:
				check(on_floor>=306 and on_floor<=318 and absf(ground_time-.30)<.035,'blue plus yellow on a platform reaches the recorded glove-to-last-center band in about 18 video frames')

func run():
	await process_frame
	test_volley_and_range()
	game.set_physics_process(false);game.reset(true);game.muted=true;game.enemies.clear();game.gifts.clear();game.platforms.clear()
	var traces=[]
	for extended in [false,true]:
		var s=shot(extended)
		var label='long' if extended else 'normal'
		var samples=[];var positive=true;var previous_x=0.0
		for i in 401:
			var t=i/400.0
			var p:Vector2=game.shot_path(s,s.duration*t)
			if i>0 and p.x<=previous_x:positive=false
			previous_x=p.x
			samples.append({'t':t,'x':p.x-100,'y':p.y-300,'base_y':game.shot_path(s,s.duration*t,false).y-300})
		var early:Vector2=game.shot_path(s,1.0/30)
		check(game.shot_path(s,0)==s.origin,label+': snow starts at the muzzle without a position jump')
		if extended:
			check((early.x-100)*30.0/960.0>1.85 and (early.x-100)*30.0/960.0<2.08,'fast long shot retains the earlier 1.85–2.08 width/s initial-speed sample')
		else:
			var observed=[11.5,9.5,8.5,4.5,4.5,5.0,4.0,2.5]
			var first:Vector2=game.shot_path(s,1.0/60)
			var previous:Vector2=first
			var worst:=0.0
			for i in observed.size():
				var sample:Vector2=game.shot_path(s,1.0/60+(i+1)/30.0)
				worst=maxf(worst,absf((sample.x-previous.x)/3.0-observed[i]))
				previous=sample
			check(worst<=2.1 and absf((previous.x-first.x)/3.0-50.0)<1.0,'normal flake matches the track of its center across source frames 41–57 at width 320')
		if not extended: check(absf(game.shot_path(s,s.cruise).y-300)<2,label+': early flight stays almost level')
		var steps=[];var last_x=game.shot_path(s,s.cruise).x
		for i in 6:
			var x:float=game.shot_path(s,s.cruise+(i+1)/30.0).x
			steps.append((x-last_x)/960.0*260.0);last_x=x
		var slowing=true
		for i in range(1,steps.size()):
			if steps[i]>=steps[i-1]:slowing=false
		if not extended: check(slowing,label+': each sampled horizontal step shortens as the shot brakes')
		if extended:
			var first:Vector2=game.shot_path(s,1.0/60.0,false)
			var before:=first
			var sampled := true
			var expected=[8,8,8,8,8,8,8,3,3,3,3,2,1,2,1,1,0]
			for i in expected.size():
				var after:Vector2=game.shot_path(s,(i+2)/60.0,false)
				if absf((after.x-before.x)/3.75-expected[i])>.08: sampled=false
				before=after
			check(sampled and absf((before.x-first.x)/3.75-75)<.1,'yellow trace follows the 8 px cruise, repeated 3 px braking and 75 px total over tutorial frames 1936–1953')
			check(game.shot_path(s,5.0/60).y<first.y-5 and before.y>first.y+10,'long flake rises above the glove before settling below its release height')
			var end:Vector2=game.shot_path(s,s.duration)
			check(end.x-before.x<3.0 and end.y-before.y>100,'after the last visible sample the airborne flake falls one tier with less than three more pixels of reach')
		var late_sink=[]
		for i in range(3,6):
			var p0:Vector2=game.shot_path(s,s.cruise+i/30.0,false)
			var p1:Vector2=game.shot_path(s,s.cruise+(i+1)/30.0,false)
			late_sink.append((p1.y-p0.y)/960.0*260.0)
		if not extended: check(late_sink.min()>.6 and late_sink.max()<1.5 and late_sink.max()-late_sink.min()<.15,label+': braking phase develops a gentle, nearly constant sink')
		check(positive,label+': braking does not reverse or stop the flake before expiry')
		print(label,' tail dx per 1/30 s at W=260: ',steps,'; tail dy: ',late_sink)
		traces.append({'label':label,'samples':samples,'tail_steps':steps,'tail_sink':late_sink})
		var combat=shot(extended)
		var end:Vector2=game.shot_path(combat,combat.cruise+combat.brake)
		var ground_target=game.new_enemy(Vector2(end.x-10,combat.origin.y+24),0)
		game.enemies=[ground_target];game.shots=[combat]
		for i in int(ceil(combat.duration*120.0))+1:game.update_shots(1.0/120)
		check(ground_target.snow==1,label+': slowing snow can still hit a same-floor enemy near the end of its braking phase')
	var bounded=true;var early_clean=true;var continuous=true;var both_signs=false
	for phase_index in 12:
		var s=shot(false,1,1,phase_index*.6)
		var low=0.0;var high=0.0;var previous=0.0
		for i in 401:
			var t=i/400.0
			var p:Vector2=game.shot_path(s,s.duration*t)
			var base:Vector2=game.shot_path(s,s.duration*t,false)
			var delta=p.y-base.y
			low=minf(low,delta);high=maxf(high,delta)
			if absf(delta)>.801 or absf(p.x-base.x)>.0001:bounded=false
			if t*s.duration <= s.cruise+s.brake*game.SHOT_FLUTTER_START and absf(delta)>.0001:early_clean=false
			if absf(delta-previous)>.12:continuous=false
			previous=delta
		if low<-.1 and high>.1:both_signs=true
	check(bounded,'flutter stays below one pixel without changing horizontal braking')
	check(early_clean,'flutter remains confined to the terminal part')
	check(continuous and both_signs,'flutter fades in smoothly and moves around the settled path')
	var right=shot();var left=shot(false,-1);var mirrored=true
	for i in 101:
		var r:Vector2=game.shot_path(right,right.duration*i/100.0)
		var l:Vector2=game.shot_path(left,left.duration*i/100.0)
		if absf(r.y-l.y)>.0001 or absf(r.x+l.x-200)>.0001:mirrored=false
	check(mirrored,'left and right fire are mirrored')
	var blue=shot(false,1,2);var long_shot=shot(true)
	check(game.shot_path(blue,.2)==game.shot_path(right,.2),'blue size does not change the trajectory center')
	var pre_yellow_travel:float=(game.shot_path(blue,19.0/60).x-game.shot_path(blue,1.0/60).x)/3.75
	var post_yellow_travel:float=(game.shot_path(long_shot,18.0/60).x-game.shot_path(long_shot,1.0/60).x)/3.75
	check(absf(pre_yellow_travel-43.0)<1.1 and absf(post_yellow_travel-75.0)<.1,'blue and blue-plus-yellow free-flight centers span the recorded 43 and 75 native pixels over their respective capture windows')
	var a=shot();var b=a.duplicate(true);game.enemies.clear();game.shots=[a]
	for i in 8:game.update_shots(1.0/30)
	game.shots=[b]
	for i in 32:game.update_shots(1.0/120)
	check(a.p.distance_to(b.p)<.001 and absf(a.life-b.life)<.001,'braking, sinking and flutter agree at 30 Hz and 120 Hz')
	game.shots=[a];game.update_shots(1.0)
	check(game.shots.is_empty() and a.age==a.duration,'expiry stops at the designed range')
	var terminal=shot();var terminal_end:Vector2=game.shot_path(terminal,terminal.duration)
	var target=game.new_enemy(terminal_end+Vector2(0,22),0)
	game.enemies=[target];game.shots=[terminal];game.update_shots(terminal.duration*1.1)
	check(target.snow==1,'the final valid portion can hit before expiry')
	var beyond=shot();target=game.new_enemy(game.shot_path(beyond,beyond.duration)+Vector2(60,22),0)
	game.enemies=[target];game.shots=[beyond];game.update_shots(beyond.duration*1.1)
	check(target.snow==0,'a long step cannot extend the range past expiry')
	var flake=shot()
	var brake_end:Vector2=game.shot_path(flake,flake.cruise+flake.brake,false)
	var drift_end:Vector2=game.shot_path(flake,flake.duration,false)
	check(drift_end.y-brake_end.y>95 and drift_end.x-brake_end.x<40, 'spent snow tips over and drops approximately one platform spacing with little forward drift')
	var upper=game.new_enemy(Vector2(drift_end.x+3,brake_end.y+72),0)
	var lower=game.new_enemy(Vector2(drift_end.x-2,brake_end.y+105),1)
	game.enemies=[lower,upper];game.shots=[flake];game.update_shots(flake.duration)
	check(upper.snow==1 and lower.snow==0, 'the first enemy on the descending arc is hit even when the lower enemy is earlier in the array and nearer in X')
	var platform_y=350.0
	game.platforms.append(Rect2(230,platform_y,540,18))
	var under=game.new_enemy(Vector2(drift_end.x,platform_y+52),0)
	game.enemies=[under];game.particles.clear()
	var coarse=shot();game.shots=[coarse];game.update_shots(coarse.duration)
	check(game.shots.is_empty() and under.snow==0 and absf(coarse.p.y+game.shot_extent(coarse).y-platform_y)<.01, 'falling snow spatters at the first platform top and cannot freeze an enemy through it')
	check(game.particles.size()==3 and game.particles.all(func(p):return p.p.y<=platform_y), 'a floor impact gives a small spray at the contact point')
	var fine=shot();game.shots=[fine]
	for i in 120:game.update_shots(1.0/120)
	check(fine.p.distance_to(coarse.p)<.2, 'coarse and fine stepping find the same platform impact along the curved path')
	game.platforms.clear();game.enemies.clear()
	game.platforms.append(Rect2(20,platform_y,165,16))
	game.platforms.append(Rect2(225,platform_y+45,480,16))
	var ledge=shot();game.shots=[ledge];game.update_shots(ledge.duration)
	check(absf(ledge.p.y+game.shot_extent(ledge).y-(platform_y+45))<.01, 'a shot over a ledge passes the gap and can touch the next lower platform')
	game.enemies.clear();game.platforms.clear()
	var chord=shot()
	var never=game.new_enemy(chord.origin.lerp(game.shot_path(chord,chord.duration),.50)+Vector2(0,22),0)
	game.enemies=[never];game.shots=[chord];game.update_shots(1.0)
	check(never.snow==0, 'a coarse frame follows cruise and descent instead of cutting a diagonal shortcut through an unrelated target')
	var powered=shot(true,1,2)
	game.platforms.append(Rect2(250,380,620,20));game.enemies.clear()
	game.shots=[powered];game.update_shots(powered.duration)
	var lip:Vector2=game.tilted_extent(game.shot_extent(powered),game.shot_tilt(powered,powered.age))
	check(lip.y>game.shot_extent(powered).y+3 and absf(powered.p.y+lip.y-380)<.12, 'the nose-down long blue flake hits the ledge with its visibly taller edge')
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with('--dump='):
			var file=FileAccess.open(arg.trim_prefix('--dump='),FileAccess.WRITE)
			file.store_string(JSON.stringify(traces))
	print('%d SHOT MOTION CHECKS PASSED, %d FAILED'%[passes,failures]);quit(1 if failures else 0)
