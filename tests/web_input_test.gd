extends SceneTree
var game
var failures=0
var passes=0
func _initialize(): run.call_deferred()
func check(ok,message):
	if ok: passes+=1;print('PASS: '+message)
	else: failures+=1;push_error('FAIL: '+message)
func command(value):game._web_command([JSON.stringify(value)])
func run():
	game=load('res://scenes/main.tscn').instantiate();root.add_child(game);game.set_physics_process(false)
	game.web_mode=true
	game.music.free();game.music=null;game.sound_bank.clear()
	var children=game.get_child_count();game.setup_audio();game.start_audio();game.play_sfx('snow')
	check(game.get_child_count()==children and game.sound_bank.is_empty(),'Web first-touch path creates no native audio players or sample buffers')
	game.state='title'
	var click=InputEventMouseButton.new();click.pressed=true;click.position=Vector2(480,600)
	game._input(click)
	check(game.state=='title','Web canvas clicks do not invoke legacy reset or audio start')
	command({'type':'start'})
	check(game.state=='play' and game.get_child_count()==children,'Web start command resets scene without starting engine audio')
	game.enemies.clear();game.gifts.clear();game.practice=true;game.invincible=10
	command({'type':'input','axis':.5,'fire':true});command({'type':'jump'})
	game.step_game(1.0/120)
	check(game.player.dir==1 and absf(game.player.v.x/960.0-.11)<.001,'analog joystick preserves a valid facing and half of the calibrated walk speed')
	check(game.player.v.y<0 and not game.shots.is_empty(),'simultaneous joystick, jump and held fire all reach gameplay')
	command({'type':'pause','paused':true})
	check(game.paused and game.web_axis==0 and not game.touch_fire and not game.jump_request,'settings pause releases all held controls')
	command({'type':'pause','paused':false});command({'type':'input','axis':-10,'fire':true})
	check(game.web_axis==-1,'Web input axis is clamped')
	command({'type':'release'})
	check(game.web_axis==0 and not game.touch_fire,'pointer cancel and background release clear inputs')
	for i in 4:
		command({'type':'practice','case':i})
		check(game.practice and game.practice_case==i,'Web practice selector case %d'%i)
	game._web_command(['not-json']);game._web_command(['null']);game._web_command([])
	check(game.state=='play','invalid bridge messages are ignored safely')
	command({'type':'mute','muted':false});check(not game.muted,'Web sound setting works without a native music node')
	for i in 100: command({'type':'start'})
	check(game.get_child_count()==children,'repeated start commands do not grow native audio nodes')
	print('%d WEB INPUT CHECKS PASSED, %d FAILED'%[passes,failures]);game.queue_free();await process_frame;quit(1 if failures else 0)
