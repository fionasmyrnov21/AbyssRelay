extends SceneTree
const Main=preload("res://scripts/main.gd")
const Store=preload("res://scripts/save_store.gd")
var passed=0
var failed=0
var game
func check(condition:bool,description:String):
	if condition:passed+=1;print("PASS ",description)
	else:failed+=1;push_error("FAIL "+description)
func settle():
	for i in range(5):await process_frame
func within(control:Control,area:Rect2)->bool:
	return area.grow(1).encloses(control.get_global_rect())
func widths_fit(node:Node)->bool:
	if node is Control and node.get_parent() is Control:
		# Scrolling can move content vertically; it must never require horizontal scrolling.
		if node.get_parent()==game.side_content or node.get_parent() is HBoxContainer:
			if node.size.x>node.get_parent().size.x+1:
				print("WIDTH_OVERFLOW ",node.get_path()," ",node.size," parent ",node.get_parent().size);return false
	for child in node.get_children():
		if not widths_fit(child):return false
	return true
func _initialize():
	run.call_deferred()
func run():
	Store.prefix="user://portrait_test_"
	game=Main.new();game.settings_path="user://portrait_test_settings.json";root.add_child(game)
	await settle()
	check(int(ProjectSettings.get_setting("display/window/handheld/orientation"))==1,"Engine uses portrait orientation")
	var manifest=FileAccess.get_file_as_string("res://../app/src/main/AndroidManifest.xml")
	check('android:screenOrientation="portrait"' in manifest,"Android host locks the game to portrait")
	check('android:appCategory="game"' in manifest,"Android game category retains orientation rules on large screens")
	for size in [Vector2i(720,1280),Vector2i(720,1600),Vector2i(960,1280)]:
		root.size=size;await settle()
		game._rebuild_layout();await settle()
		var area=Rect2(Vector2.ZERO,game._screen_size())
		check(area.size.y>area.size.x and within(game.menu,area),"Menu fills portrait viewport %s"%size)
		game._start(false);game.sim.paused=true
		if is_instance_valid(game.transition):game.transition.queue_free()
		await settle()
		check(within(game.mission_panel,area) and within(game.camera_controls,area),"Mission and camera controls fit %s"%size)
		for text_scale in [1.0,1.15]:
			game.settings.text_scale=text_scale;game._build_hud();game._refresh_hud();await settle()
			game.selected=int(game.sim.first_module("lab",0).id)
			var panels_ok=true
			for mode in ["build","inspect","drones","research","expeditions","contracts","journal","sectors","events","settings","navigation","routes","about"]:
				game.panel_mode=mode;game.sidebar.visible=true;game._refresh_panel();await settle()
				if not within(game.sidebar,area) or game.sidebar.get_global_rect().end.y>game.navigation_top+1 or not widths_fit(game.side_content):
					print("SHEET_BOUNDS ",game.sidebar.get_global_rect()," min ",game.sidebar.get_combined_minimum_size()," title ",game.labels.panel_title.size," titlemin ",game.labels.panel_title.get_combined_minimum_size()," scrollmin ",game.sidebar_scroll.get_combined_minimum_size()," scrollsize ",game.sidebar_scroll.size);panels_ok=false;push_error("Overflow in %s at %s, text %s"%[mode,size,text_scale])
			check(panels_ok,"All 13 sheets fit %s at %d%% text"%[size,roundi(text_scale*100)])
			game.sheet_expanded=true;game._layout_sidebar();await settle()
			check(within(game.sidebar,area) and not game.mission_panel.visible,"Expanded sheet stays below header at %s"%size)
			game.sheet_expanded=false;game._close_panel()
		game.panel_mode="build";game.sidebar.visible=true;game.build_choice="corridor";game.world.build_kind="corridor";game._refresh_panel();await settle()
		var world=game.world
		var target=world.interaction_rect.get_center()
		var original_pan=world.pan
		var begin=InputEventMouseButton.new();begin.button_index=MOUSE_BUTTON_LEFT;begin.position=target;begin.pressed=true;world._unhandled_input(begin)
		var motion=InputEventMouseMotion.new();motion.position=target+Vector2(32,20);world._unhandled_input(motion)
		var release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=motion.position;world._unhandled_input(release)
		check(world.pan.is_equal_approx(original_pan+Vector2(32,20)) and game.pending_cell.x==999,"Dragging a blueprint pans without placing it at %s"%size)
		world.center_on(Vector2.ZERO)
		var anchor=world.origin+Vector2(24,10);var before=world.unproject(anchor);world.zoom_at(1.15,anchor)
		check(world.unproject(anchor).is_equal_approx(before),"Zoom preserves the seabed point under the fingers at %s"%size)
		check(within(game.sidebar,area) and world.interaction_rect.size.y>180,"Placement sheet leaves an accessible map at %s"%size)
		game._close_panel();world.frame_station()
		var station_fits=true
		for m in game.sim.modules:
			if int(m.sector)!=game.sim.sector:continue
			var point=world.iso(Vector2(m.x,m.y))
			if point.x-55*world.zoom<0 or point.x+55*world.zoom>area.size.x:station_fits=false
		check(station_fits,"Fit-station camera respects portrait width at %s"%size)
		game._close_panel();game._show_menu();await settle()
	# Test terminal outcomes and dialogs on the narrowest layout.
	root.size=Vector2i(720,1280);await settle();game._start(false);game.sim.paused=true
	if is_instance_valid(game.transition):game.transition.queue_free()
	game.sim.failed=true;game._process(0);await settle()
	var shade=game.ui.get_node("ExpeditionDefeat");var box=shade.get_child(0).get_child(0)
	check(within(box,Rect2(Vector2.ZERO,game._screen_size())),"Defeat dialog is fully visible in portrait")
	shade.queue_free();game.sim.failed=false;game.failure_shown=false;await settle()
	game._confirm_new();await settle()
	var dialog=game.ui.get_child(game.ui.get_child_count()-1)
	check(dialog is ConfirmationDialog and dialog.size.x<=game._screen_size().x,"New-expedition confirmation fits portrait width")
	dialog.queue_free();await settle()
	game.sim.completed=true;game._process(0);await settle()
	var victory=game.ui.get_node("ExpeditionVictory")
	check(within(victory.get_child(0).get_child(0),Rect2(Vector2.ZERO,game._screen_size())),"Victory and sandbox actions fit portrait")
	victory.queue_free();await settle()
	game._confirm_demolition(int(game.sim.first_module("lab",0).id));await settle()
	var demolition=game.ui.get_child(game.ui.get_child_count()-1)
	check(demolition is ConfirmationDialog and demolition.size.x<=game._screen_size().x,"Dismantling confirmation fits portrait width")
	demolition.queue_free();await settle()
	print("PORTRAIT_RESULT ",passed," passed, ",failed," failed")
	game.running=false;game.queue_free();await settle()
	quit(1 if failed else 0)
