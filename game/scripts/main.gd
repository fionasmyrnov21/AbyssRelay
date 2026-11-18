extends Node

const Simulation = preload("res://scripts/simulation.gd")
const Store = preload("res://scripts/save_store.gd")
const Content = preload("res://scripts/content.gd")
const World = preload("res://scripts/ocean_world.gd")
const MenuLife = preload("res://scripts/menu_life.gd")
const INK = Color("e3eee8")
const MUTED = Color("7e9f9f")
const TEAL = Color("7ed9c6")
const AMBER = Color("e5bd80")
const RED = Color("ed967d")
const PANEL = Color(0.035,0.095,0.12,0.96)
var sim
var world
var ui: Control
var menu: Control
var hud: Control
var sidebar: PanelContainer
var sidebar_scroll: ScrollContainer
var side_content: VBoxContainer
var panel_mode = ""
var selected = -1
var finding_id = ""
var build_choice = ""
var build_category = "all"
var pending_cell = Vector2i(999,999)
var build_rotation = 0
var link_source = -1
var labels = {}
var refresh_clock = 0.0
var toast_clock = 0.0
var toast_text = ""
var running = false
var settings = {"lang":"en","volume":0.5,"reduced_motion":false,"auto_pause":true,"text_scale":1.0}
var ambient: AudioStreamPlayer
var sfx: AudioStreamPlayer
var font: Font
var known_research_count = 0
var known_build_count = 0
var transition: Control
var settings_return = ""
var last_event_count = 0
var mobile = true
var sheet_expanded = false
var layout_pending = false
var navigation_top = 0.0
var mission_bottom = 0.0
var mission_panel: Control
var camera_controls: Control
var safe_top = 16.0
var safe_bottom = 16.0
var route_resource = "alloy"
var failure_shown = false
var victory_shown = false
var native_bridge
var snapshot_clock=0.0
var settings_path="user://settings.json"

func _ready():
	if "--qa" in OS.get_cmdline_user_args() or "--smoke" in OS.get_cmdline_user_args():
		Store.prefix = "user://qa_relay_"
		settings_path="user://qa_settings.json"
	mobile = true
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	var font_variation = FontVariation.new()
	font_variation.base_font = load("res://assets/Manrope.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 550.0}
	font = font_variation
	_load_settings()
	sim = Simulation.new(); sim.new_game(); sim.paused = true
	sim.auto_pause = bool(settings.auto_pause)
	world = World.new(); world.sim = sim; world.reduced_motion = bool(settings.reduced_motion)
	add_child(world)
	world.cell_selected.connect(_cell_clicked)
	world.module_selected.connect(_module_clicked)
	world.finding_selected.connect(_finding_clicked)
	var canvas = CanvasLayer.new(); add_child(canvas)
	ui = Control.new(); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var theme = Theme.new(); theme.default_font = font; theme.default_font_size = 15
	theme.default_font_size = 24
	theme.set_color("font_color","Label",INK)
	theme.set_color("font_color","Button",INK)
	ui.theme = theme
	_setup_audio()
	_show_menu()
	get_viewport().size_changed.connect(_request_layout)
	if Engine.has_singleton("RelayLifecycle"):
		native_bridge=Engine.get_singleton("RelayLifecycle")
		native_bridge.register_controller(get_instance_id())
	var args = OS.get_cmdline_user_args()
	if "--demo" in args or "--smoke" in args or "--qa" in args:
		_start(false)
	if "--qa" in args:
		await _qa_panels()
	if "--smoke" in args:
		await get_tree().create_timer(5.0).timeout
		Store.save_game(sim,"3")
		print("UI_SMOKE_OK modules=",sim.modules.size()," drones=",sim.drones.size())
		get_tree().quit()
	if "--capture" in args:
		await get_tree().create_timer(4.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../output/gameplay.png")
		print("SCREENSHOT_SAVED")
	if "--capture-menu" in args:
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../output/menu.png")
		get_tree().quit()

func _setup_audio():
	ambient = AudioStreamPlayer.new(); sfx = AudioStreamPlayer.new()
	add_child(ambient); add_child(sfx)
	var stream = load("res://assets/audio/ocean.wav")
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD; stream.loop_end = 22050*16
	ambient.stream = stream
	_set_volume(float(settings.volume))
	if DisplayServer.get_name() != "headless":
		ambient.play()

func sound(name:String):
	if DisplayServer.get_name() == "headless":
		return
	sfx.stream = load("res://assets/audio/"+name+".wav"); sfx.play()

func _set_volume(value:float):
	settings.volume = value
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(value,0.001)))

func _load_settings():
	var migrate_language=false
	if FileAccess.file_exists(settings_path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
		if saved is Dictionary:
			migrate_language=saved.get("lang","en")!="en"
			for key in settings:
				if key!="lang" and saved.has(key):
					settings[key] = saved[key]
	settings.lang = "en"
	TranslationServer.set_locale("en")
	if migrate_language:
		_save_settings()

func _save_settings():
	var file = FileAccess.open(settings_path,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings))

func style(bg:Color,border:Color=Color.TRANSPARENT,radius:int=10) -> StyleBoxFlat:
	var box = StyleBoxFlat.new(); box.bg_color = bg
	box.border_color = border; box.set_border_width_all(1 if border.a>0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14; box.content_margin_right = 14; box.content_margin_top = 10; box.content_margin_bottom = 10
	return box

func rect(control:Control,x:float,y:float,w:float,h:float):
	control.position = Vector2(x,y); control.size = Vector2(w,h)

func label(parent:Node,text:String,size:int=15,color:Color=INK) -> Label:
	var node = Label.new(); node.text = text; node.add_theme_font_size_override("font_size",roundi(size*float(settings.text_scale)*1.65)); node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent is VBoxContainer:
		node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func paragraph(parent:Node,text:String,size:int=14,color:Color=MUTED) -> Label:
	var node = label(parent,text,size,color); node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func button(parent:Node,text:String,action:Callable,primary:bool=false) -> Button:
	var b = Button.new(); b.text = text; b.custom_minimum_size = Vector2(0,84)
	b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode=Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",roundi(14*float(settings.text_scale)*1.65))
	b.add_theme_stylebox_override("normal",style(Color("79d5bf") if primary else Color("112f39"),Color("24434a") if not primary else Color.TRANSPARENT,7))
	b.add_theme_stylebox_override("hover",style(Color("a0e8d4") if primary else Color("1d424a"),Color("659b91"),7))
	b.add_theme_stylebox_override("pressed",style(Color("60b7a7") if primary else Color("254e54"),TEAL,7))
	b.add_theme_stylebox_override("disabled",style(Color("0d252e"),Color("19353d"),7))
	b.add_theme_color_override("font_color",Color("102c32") if primary else INK)
	b.add_theme_color_override("font_hover_color",Color("102c32") if primary else INK)
	b.add_theme_color_override("font_disabled_color",Color("4b6c71"))
	# Panel actions may replace the pressed control; finish its input event first.
	b.pressed.connect(func():sound("click");action.call_deferred();_cache_android_snapshot.call_deferred())
	parent.add_child(b)
	return b

func row(parent:Node,gap:int=8) -> HBoxContainer:
	var r = HBoxContainer.new(); r.add_theme_constant_override("separation",gap); r.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(r); return r

func column(parent:Node,gap:int=8) -> VBoxContainer:
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation",gap); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(v); return v

func panel(parent:Node,area:Rect2,padding:int=18) -> VBoxContainer:
	var box=style(PANEL,Color("24424a"),12)
	for side in ["left","right","top","bottom"]:box.set("content_margin_"+side,0)
	var p = PanelContainer.new(); p.add_theme_stylebox_override("panel",box); parent.add_child(p); p.position = area.position; p.size = area.size
	var margin = MarginContainer.new(); p.add_child(margin)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,padding)
	return column(margin,10)

func divider(parent:Node):
	var line = HSeparator.new()
	var stroke = StyleBoxFlat.new();stroke.bg_color=Color("233c43")
	line.add_theme_stylebox_override("separator",stroke);line.custom_minimum_size.y=1;parent.add_child(line)

func clear(node:Node):
	for child in node.get_children():
		node.remove_child(child); child.queue_free()

func _show_menu():
	running=false; sim.paused=true; world.visible=false; world.interaction_enabled=false
	if is_instance_valid(hud):hud.queue_free()
	if is_instance_valid(menu):menu.queue_free()
	var area=_screen_size();_read_safe_area()
	menu=Control.new();ui.add_child(menu);rect(menu,0,0,area.x,area.y)
	var image=TextureRect.new();image.texture=load("res://assets/menu-ocean.png")
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu.add_child(image);rect(image,0,0,area.x,area.y)
	var life=MenuLife.new();life.reduced=bool(settings.reduced_motion);menu.add_child(life)
	var fade=Gradient.new()
	fade.set_color(0,Color(0.01,0.035,0.045,0.54));fade.set_color(1,Color(0.01,0.035,0.045,0.94));fade.add_point(0.5,Color(0.01,0.035,0.045,0.08))
	var texture=GradientTexture2D.new();texture.gradient=fade;texture.fill_from=Vector2(0,0);texture.fill_to=Vector2(0,1)
	var shade=TextureRect.new();shade.texture=texture;menu.add_child(shade);rect(shade,0,0,area.x,area.y)
	var content=column(menu,12);rect(content,36,safe_top+area.y*0.075,area.x-72,340)
	label(content,"A DEEP-SEA RESEARCH EXPEDITION",11,TEAL)
	var title=label(content,"ABYSS\nRELAY",54,INK);title.add_theme_font_size_override("font_size",90);title.add_theme_constant_override("line_spacing",-12)
	paragraph(content,"Beyond the light.\nWithin your control.",17,Color("a0bebc"))
	var has_save=Store.exists()
	var actions=column(menu,12);rect(actions,36,area.y-safe_bottom-354,area.x-72,330)
	label(actions,"↓ 320 M   /   SHELF EDGE",11,TEAL)
	if has_save:button(actions,"CONTINUE DESCENT  →",func():_start(true),true)
	button(actions,"NEW EXPEDITION" if has_save else "BEGIN EXPEDITION  →",func():
		if Store.exists():_confirm_new()
		else:_start(false),not has_save)
	button(actions,"Settings",_menu_settings)
	var footer=label(menu,"EXPLORE. CONNECT. ENDURE.",9,MUTED);footer.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	rect(footer,24,area.y-safe_bottom-28,area.x-48,24)

func _confirm_new():
	var dialog=ConfirmationDialog.new();dialog.title="New expedition"
	dialog.dialog_text="Start again? Autosave will be replaced. Manual slots are retained."
	dialog.theme=ui.theme;dialog.dialog_autowrap=true;dialog.ok_button_text="Start";dialog.cancel_button_text="Cancel";ui.add_child(dialog)
	dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialog.get_ok_button().custom_minimum_size=Vector2(200,84);dialog.get_cancel_button().custom_minimum_size=Vector2(200,84)
	dialog.confirmed.connect(func():dialog.queue_free();_start(false));dialog.canceled.connect(func():dialog.queue_free())
	dialog.popup_centered(Vector2i(int(_screen_size().x)-48,360))

func _menu_settings():
	settings_return = "menu"
	if is_instance_valid(menu):
		menu.visible = false
	_build_hud(); hud.visible = true; _open_panel("settings")
	world.visible = true; world.interaction_enabled = false
	_refresh_hud()

func _start(resume:bool):
	if resume:
		if not Store.load_game(sim):
			_toast("Save unavailable"); return
	else:
		sim.new_game(); Store.save_game(sim)
	sim.auto_pause = bool(settings.auto_pause)
	failure_shown=false;victory_shown=false
	for outcome in ["ExpeditionDefeat","ExpeditionVictory"]:
		var overlay=ui.get_node_or_null(outcome)
		if overlay:overlay.queue_free()
	if is_instance_valid(menu):
		menu.queue_free()
	world.visible = true; world.interaction_enabled = true
	world.pan = Vector2.ZERO; world.zoom = 1.0; world.sim = sim
	sheet_expanded=false
	world.selected = -1; selected = -1
	running = true; settings_return = ""; panel_mode = ""; build_choice = ""; world.build_kind = ""
	known_research_count = sim.researched.size(); known_build_count = sim.statistics.built
	_build_hud()
	world.frame_station()
	sim.paused = resume
	_refresh_hud()
	if not resume:
		_intro()

func _intro():
	if is_instance_valid(transition):transition.queue_free()
	transition=ColorRect.new();transition.color=Color(0.01,0.03,0.04,0.94);ui.add_child(transition)
	transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var area=_screen_size()
	var text=column(transition,24);rect(text,36,area.y*0.32,area.x-72,420)
	var chapter=label(text,"DESCENT %02d"%(sim.sector+1),14,TEAL);chapter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var title=label(text,Content.title(sim.db.sectors[sim.sector]),30,INK);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var desc=paragraph(text,"Uplink established. Welcome to the deep.",16,MUTED);desc.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	button(text,"Continue  →",func():transition.queue_free())
	var tween=create_tween();tween.tween_property(transition,"modulate:a",0.0,1.2).set_delay(2.0)
	tween.tween_callback(func():if is_instance_valid(transition):transition.queue_free())
	sound("sonar")

func _build_hud():
	if is_instance_valid(hud):
		ui.remove_child(hud);hud.queue_free()
	hud=Control.new();hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	labels.clear();_read_safe_area();_build_mobile_hud()

func _create_sidebar():
	sidebar=PanelContainer.new();hud.add_child(sidebar)
	sidebar.add_theme_stylebox_override("panel",style(PANEL,Color("31565e"),18))
	var margin=MarginContainer.new();sidebar.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	var v=column(margin,8)
	var heading=row(v,8)
	labels.panel_title=label(heading,"",18,INK);labels.panel_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	labels.panel_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	labels.expand=button(heading,"Map" if sheet_expanded else "Expand",func():sheet_expanded=not sheet_expanded;_layout_sidebar())
	labels.expand.custom_minimum_size=Vector2(104,72);labels.expand.add_theme_font_size_override("font_size",20)
	var close=button(heading,"×",_close_panel);close.custom_minimum_size=Vector2(72,72)
	divider(v)
	sidebar_scroll=ScrollContainer.new();sidebar_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sidebar_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_scroll.follow_focus=true;v.add_child(sidebar_scroll)
	side_content=column(sidebar_scroll,12);side_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sidebar.visible=not panel_mode.is_empty();_layout_sidebar()
	sidebar.minimum_size_changed.connect(_layout_sidebar.call_deferred)

func _open_panel(mode:String):
	var previous=panel_mode
	panel_mode="" if panel_mode==mode else mode
	world.interaction_enabled=settings_return!="menu"
	if previous!=panel_mode:
		sheet_expanded=false;sidebar_scroll.scroll_vertical=0
	if panel_mode!="build":
		world.build_kind="";build_choice="";pending_cell=Vector2i(999,999)
	sidebar.visible=not panel_mode.is_empty()
	_refresh_panel();_layout_sidebar()

func _close_panel():
	if settings_return=="menu":
		settings_return="";_show_menu();return
	panel_mode="";world.build_kind="";build_choice="";link_source=-1;sidebar.visible=false;sheet_expanded=false
	_layout_sidebar()

func _refresh_panel():
	if panel_mode.is_empty() or not is_instance_valid(side_content):
		return
	var scroll_position = sidebar_scroll.scroll_vertical
	clear(side_content)
	labels.panel_title.text = {"build":"Construction","inspect":"Module","drones":"Drone fleet","research":"Research","expeditions":"Expeditions","contracts":"Contracts","journal":"Journal","sectors":"Depth chart","events":"Diagnostics","settings":"Settings","about":"About","routes":"Cargo routes","navigation":"Expedition"}.get(panel_mode,"")
	match panel_mode:
		"build": _build_panel()
		"inspect": _inspect_panel()
		"drones": _drones_panel()
		"research": _research_panel()
		"expeditions": _expeditions_panel()
		"contracts": _contracts_panel()
		"journal": _journal_panel()
		"sectors": _sectors_panel()
		"events": _events_panel()
		"settings": _settings_panel()
		"navigation": _navigation_panel()
		"routes": _routes_panel()
		"about": _about_panel()
	sidebar_scroll.set_deferred("scroll_vertical",scroll_position)
	_layout_sidebar()

func _build_panel():
	if not build_choice.is_empty():
		var def=sim.db.modules[build_choice]
		label(side_content,Content.title(def),18,TEAL)
		paragraph(side_content,_cost_text(def.cost)+"  ·  "+str(absi(int(def.power)))+" kW",12,AMBER)
		var error=sim.placement_error(build_choice,pending_cell,sim.sector) if pending_cell.x!=999 else ""
		paragraph(side_content,"Tap an empty cell. Drag to move the map." if pending_cell.x==999 else _error_text(error) if not error.is_empty() else "Site available. Ready to deliver and assemble.",12,MUTED if pending_cell.x==999 else RED if not error.is_empty() else TEAL)
		var actions=row(side_content,8)
		button(actions,"Rotate %d°"%build_rotation,func():build_rotation=(build_rotation+90)%360;_refresh_panel()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var confirm=button(actions,"Place blueprint",_confirm_build,true);confirm.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		confirm.disabled=pending_cell.x==999 or not error.is_empty()
		button(side_content,"← Module catalogue",func():build_choice="";world.build_kind="";pending_cell=Vector2i(999,999);sidebar_scroll.scroll_vertical=0;_refresh_panel())
		return
	paragraph(side_content,"Choose a module. The catalogue folds away so you can place it on the seabed.",12)
	var cats=row(side_content,8)
	for item in [["all","All"],["power","Power"],["life","Life"]]:
		var id=str(item[0]);var b=button(cats,str(item[1]),func():build_category=id;_refresh_panel());b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for kind in sim.db.modules:
		var def=sim.db.modules[kind]
		if kind=="core" or build_category!="all" and def.category!=build_category:continue
		var current_kind=str(kind)
		var b=button(side_content,Content.title(def),func():
			build_choice=current_kind;world.build_kind=current_kind;pending_cell=Vector2i(999,999);sheet_expanded=false;sidebar_scroll.scroll_vertical=0;_refresh_panel(),false)
		b.disabled=not sim.unlocked(kind)
		paragraph(side_content,_cost_text(def.cost)+(" · research" if not sim.unlocked(kind) else ""),11,MUTED)

func _cost_text(cost:Dictionary) -> String:
	var parts = []
	for key in cost:
		if int(cost[key])>0:
			parts.append(str(int(cost[key]))+" "+_resource_name(key))
	return " · ".join(parts)

func _resource_name(key:String) -> String:
	var entry = sim.db.resources.get(key,key)
	return str(entry).to_lower()

func _error_text(error:String) -> String:
	return {"unknown":"Unavailable module","research":"Research required","occupied":"Cell occupied or obstructed","pressure":"Next pressure hull class required","adjacent":"Place beside an existing module","deposit":"Mining rig requires a deposit","vent":"Geothermal vent required","current":"Place the turbine in the outer current zone","resources":"Not enough unreserved materials","previous":"Unlock the previous depth first","findings":"Recover two findings in the previous sector","relay":"Build and power a relay in the previous sector"}.get(error,error)

func _confirm_build():
	var site = sim.place(build_choice,pending_cell,sim.sector)
	if not site.is_empty():
		site.orientation = build_rotation
		sound("build"); _toast("Blueprint placed. Drones are delivering materials.")
		pending_cell=Vector2i(999,999); _refresh_panel()
	else:
		_toast(_error_text(sim.last_error))

func _cell_clicked(cell:Vector2i):
	pending_cell=cell; _refresh_panel()

func _module_clicked(id:int):
	if link_source>=0 and id>=0:
		_toast("Cable connected" if sim.add_link(link_source,id) else "Connection unavailable: max 6 cells, costs 2 alloy")
		link_source=-1; return
	selected=id
	if id>=0:
		panel_mode="inspect";sheet_expanded=false;sidebar_scroll.scroll_vertical=0;sidebar.visible=true;_refresh_panel()
	elif panel_mode=="inspect":
		_close_panel()

func _finding_clicked(id:String):
	finding_id=id;panel_mode="expeditions";sheet_expanded=false;sidebar_scroll.scroll_vertical=0;sidebar.visible=true;_refresh_panel()

func _inspect_panel():
	var m = sim.module_by_id(selected)
	if m.is_empty():
		_close_panel();return
	var def = sim.db.modules[m.kind]
	label(side_content,Content.title(def),20,TEAL)
	paragraph(side_content,"COMPARTMENT "+"%03d"%int(m.id)+"  ·  "+str(sim.db.sectors[sim.sector].depth)+" m",11,MUTED)
	if not m.built:
		paragraph(side_content,"Material delivery and assembly",15,AMBER)
		for key in def.cost:
			label(side_content,_resource_name(key)+": "+str(int(m.stock.get(key,0)))+" / "+str(int(def.cost[key])),14,INK)
		_meter(side_content,float(m.work)/float(def.build_time),TEAL)
		button(side_content,"Cancel construction",func():sim.cancel_site(selected);world.selected=-1;_close_panel())
		return
	var reason = _reason(m)
	paragraph(side_content,reason,15,TEAL if m.powered and m.leak<=0 else AMBER)
	_meter(side_content,float(m.hp)/100.0,TEAL)
	label(side_content,"Integrity: "+"%d%%"%m.hp,13,MUTED)
	label(side_content,"Flooding: "+"%.1f%%"%m.water,13,RED if m.water>10 else MUTED)
	label(side_content,"Oxygen: "+"%.0f"%m.oxygen,13,MUTED)
	label(side_content,"Power: "+str(int(def.power))+" kW",13,AMBER)
	if m.kind=="battery":
		label(side_content,"%.2f kWh"%m.battery,16,AMBER)
	divider(side_content)
	button(side_content,"Switch off" if m.enabled else "Switch on",func():sim.set_enabled(selected);_refresh_panel())
	button(side_content,"Open bulkhead" if m.sealed else "Seal compartment",func():m.sealed=not m.sealed;_refresh_panel())
	button(side_content,"Priority: "+str(int(m.priority)+1),func():m.priority=(int(m.priority)+1)%4;_refresh_panel())
	button(side_content,"Connect cable · 2 alloy",func():link_source=selected;sheet_expanded=false;_layout_sidebar();_toast("Select the second module on the map"))
	if m.leak>0 or m.fault>0 or m.hp<85:
		paragraph(side_content,"An engineer will respond automatically when 2 repair kits are available.",13,AMBER)
	if int(def.crew)>0:
		label(side_content,"Specialists: "+str(int(m.get("staff",def.crew)))+" / "+str(int(def.crew)),13,MUTED)
		var staffing=row(side_content,8)
		button(staffing,"−",func():sim.change_staff(selected,-1);_refresh_panel()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button(staffing,"+",func():sim.change_staff(selected,1);_refresh_panel()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if m.kind!="core":
		button(side_content,"Dismantle · recover 50%",func():_confirm_demolition(selected))
	divider(side_content)
	label(side_content,"LOCAL BUFFER",11,MUTED)
	var stocks = []
	for key in m.stock:
		if int(m.stock[key])>0:
			stocks.append(_resource_name(key)+": "+str(int(m.stock[key])))
	paragraph(side_content,"\n".join(stocks) if not stocks.is_empty() else "Buffer available",13,INK)

func _reason(m:Dictionary) -> String:
	if m.leak>0:
		return "Leak · repair requested"
	return {"":"Operational","disabled":"Disabled by operator","flooded":"Compartment flooded","fuel":"No fuel cells","fault":"Equipment fault","power":"Insufficient power","disconnected":"No source connection","input":"Awaiting input materials","storage":"Output buffer full","drone":"Awaiting mining drone","depleted":"Deposit depleted","crew":"No specialists assigned","oxygen":"Insufficient oxygen"}.get(m.reason,m.reason)

func _meter(parent:Node,fraction:float,color:Color):
	var meter = ProgressBar.new();meter.custom_minimum_size.y=5;meter.show_percentage=false;meter.value=clampf(fraction*100,0,100)
	meter.add_theme_stylebox_override("background",style(Color("19343c"),Color.TRANSPARENT,3));meter.add_theme_stylebox_override("fill",style(color,Color.TRANSPARENT,3));parent.add_child(meter)

func _drones_panel():
	paragraph(side_content,"Autonomous assignments. Charging and emergency return are automatic.")
	for d in sim.drones:
		if d.sector!=sim.sector:
			continue
		var id = int(d.id)
		label(side_content,_drone_name(d.kind)+"  /  %02d"%id,17,TEAL)
		var battery_capacity=140.0 if "battery" in d.upgrades else 100.0
		paragraph(side_content,_drone_state(d.state)+"  ·  "+"%d%%"%(float(d.battery)/battery_capacity*100),12,MUTED)
		_meter(side_content,float(d.battery)/battery_capacity,TEAL)
		if not d.cargo.is_empty():
			paragraph(side_content,"Cargo: "+_cost_text(d.cargo),12,AMBER)
		var r=row(side_content,6)
		button(r,"Recall",func():sim.cancel_drone(id);_refresh_panel()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var b=button(r,"Battery · 35",func():sim.upgrade_drone(id,"battery");_refresh_panel());b.disabled="battery" in d.upgrades
		var controls = row(side_content,6)
		button(controls,"Quiet drive · 35",func():sim.upgrade_drone(id,"quiet");_refresh_panel()).disabled="quiet" in d.upgrades
		button(controls,"Protocol",func():d.protocol="wait" if d.protocol=="return" else "return";_refresh_panel())
		paragraph(side_content,"Lost link: "+("return" if d.protocol=="return" else "wait"),11,MUTED)
		divider(side_content)
	label(side_content,"EXPAND FLEET",11,MUTED)
	button(side_content,"Inter-outpost routes",func():_open_panel("routes"))
	for kind in ["scout","cargo","engineer","miner"]:
		var drone_kind=str(kind)
		button(side_content,_drone_name(kind)+" · 65",func():_toast("Drone commissioned" if sim.buy_drone(drone_kind) else "Requires 65 credits, 15 alloy and 2 repair kits");_refresh_panel())

func _drone_name(kind:String) -> String:
	return {"scout":"Scout","cargo":"Hauler","engineer":"Engineer","miner":"Miner"}.get(kind,kind)

func _drone_state(state:String) -> String:
	return {"idle":"Ready","pickup":"Collecting cargo","deliver":"Delivering","working":"Working","survey":"Surveying","return":"Returning / charging","waiting_dock":"Dock unpowered","blocked":"Route blocked","stranded":"Dock required","link_wait":"Waiting for link"}.get(state,state)

func _research_panel():
	if not sim.research.is_empty():
		for r in sim.db.research:
			if r.id==sim.research.id:
				label(side_content,Content.title(r),17,TEAL)
		_meter(side_content,float(sim.research.progress)/float(sim.research.duration),TEAL)
		paragraph(side_content,"The laboratory requires power and oxygen.",12,MUTED)
		divider(side_content)
	var previous_branch=""
	for r in sim.db.research:
		if r.branch!=previous_branch:
			previous_branch=r.branch;label(side_content,str(r.branch_en).to_upper(),11,AMBER)
		var id=str(r.id);var done=id in sim.researched
		var b=button(side_content,("✓ " if done else "")+Content.title(r),func():
			_toast("Research started" if sim.start_research(id) else "Requires data, an available laboratory and prerequisites");_refresh_panel())
		b.disabled=done or not sim.research.is_empty()
		for requirement in r.requires:
			if requirement not in sim.researched:
				b.disabled=true
		paragraph(side_content,str(int(r.cost))+" data · "+str(int(r.duration))+" s",11,MUTED)

func _expeditions_panel():
	paragraph(side_content,"Explore signals. Scouts return data and samples to the dock.")
	for f in sim.findings:
		if f.sector!=sim.sector:
			continue
		var id=str(f.id);label(side_content,Content.title(f),17,TEAL if id==finding_id else INK)
		if f.status=="recovered":
			paragraph(side_content,str(f.lore_en),12,MUTED)
			label(side_content,"Sample recovered",12,TEAL)
		else:
			paragraph(side_content,str(int(f.data))+" data · "+str(int(f.samples))+" samples",12,AMBER)
			var b=button(side_content,"Scout deployed" if f.status=="assigned" else "Dispatch scout   →",func():
				if sim.dispatch(id):sound("sonar")
				else:_toast("An idle charged scout is required")
				_refresh_panel(),f.status!="assigned")
			b.disabled=f.status=="assigned"
		button(side_content,"Locate on chart",func():sheet_expanded=false;_layout_sidebar();world.center_on(Vector2(f.cell[0],f.cell[1]));world.selected_finding=id).custom_minimum_size.y=84
		divider(side_content)

func _contracts_panel():
	paragraph(side_content,"Supply the science consortium to earn funding and research data.")
	for c in sim.db.contracts:
		var id=str(c.id);var done=id in sim.claimed
		label(side_content,Content.title(c),17,INK)
		var objective_text = str(int(c.amount))+" "+_resource_name(c.resource) if c.kind=="delivery" else {"repair":"Repairs","survey":"Discoveries","quiet":"Quiet operation, s","uptime":"Stable power, s","relay":"Relays","research":"Research"}.get(c.kind,"")+": "+str(sim.contract_progress(c))+" / "+str(int(c.target))
		paragraph(side_content,objective_text+"  →  "+str(int(c.credits))+" credits",12,AMBER)
		var b=button(side_content,"Completed" if done else "Deliver cargo",func():
			_toast("Contract fulfilled" if sim.claim_contract(id) else "Not enough unreserved cargo in this sector");_refresh_panel())
		b.disabled=done
		divider(side_content)

func _journal_panel():
	label(side_content,"EXPEDITION ARCHIVE",11,AMBER)
	for entry in sim.logbook:
		label(side_content,_format_time(float(entry.time)),11,MUTED)
		paragraph(side_content,str(entry.get("en","Archived expedition entry.")),14,INK)
		divider(side_content)

func _sectors_panel():
	paragraph(side_content,"New outpost: 80 alloy, 8 repair kits, 5 fuel and 60 credits. Part of the cargo forms its initial reserve.")
	for i in range(sim.db.sectors.size()):
		var index=i;var s=sim.db.sectors[i]
		label(side_content,"0%d  /  "%[i+1]+Content.title(s),17,TEAL if i==sim.sector else INK)
		paragraph(side_content,"↓ "+str(int(s.depth))+" m",20,AMBER)
		var open=i in sim.sectors_open
		var error=sim.sector_error(i)
		if not open:
			paragraph(side_content,_error_text(error) if not error.is_empty() else "Ready to deploy",12,MUTED)
		var b=button(side_content,"Visit outpost" if open else "Deploy outpost",func():
			if sim.open_sector(index):
				world.pan=Vector2.ZERO;world.selected=-1;_refresh_panel();world.frame_station();sound("sonar");_intro()
			else:_toast(_error_text(sim.last_error)),i==sim.sector)
		b.disabled=not open and not error.is_empty()
		divider(side_content)

func _events_panel():
	if sim.events.is_empty():
		label(side_content,"Station stable",19,TEAL)
		paragraph(side_content,"Prepare reserve power and repair kits before a longer expedition.")
	for e in sim.events:
		label(side_content,Content.title(e),18,AMBER)
		paragraph(side_content,("Warning: " if e.phase=="warning" else "Active incident: ")+str(maxi(0,int(e.remaining)))+" s",14,RED)
		var target=sim.module_by_id(int(e.target))
		if not target.is_empty():
			var id=int(target.id)
			paragraph(side_content,Content.title(sim.db.modules[target.kind])+"\n"+_reason(target),13,MUTED)
			button(side_content,"Inspect compartment",func():world.center_on(Vector2(target.x,target.y));world.selected=id;_module_clicked(id))
		divider(side_content)
	button(side_content,"Emergency supply",func():
		_toast("Supply delivered" if sim.rescue() else "Reserve already used");_refresh_panel()).disabled=sim.rescue_used

func _settings_panel():
	label(side_content,"ABYSS RELAY",18,TEAL)
	label(side_content,"Master volume",13,MUTED)
	var slider=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=0.05;slider.value=float(settings.volume);slider.custom_minimum_size.y=84;side_content.add_child(slider)
	slider.value_changed.connect(func(value):_set_volume(value);_save_settings())
	button(side_content,"Background motion: "+("off" if settings.reduced_motion else "on"),func():settings.reduced_motion=not settings.reduced_motion;world.reduced_motion=settings.reduced_motion;_save_settings();_refresh_panel())
	button(side_content,"Incident auto-pause: "+("on" if settings.auto_pause else "off"),func():settings.auto_pause=not settings.auto_pause;sim.auto_pause=settings.auto_pause;_save_settings();_refresh_panel())
	button(side_content,"Text size: "+str(int(float(settings.text_scale)*100))+"%",func():settings.text_scale=1.15 if settings.text_scale==1.0 else 1.0;_save_settings();_build_hud();_refresh_panel())
	if settings_return=="menu":
		button(side_content,"Return to menu",func():settings_return="";_show_menu());return
	divider(side_content)
	label(side_content,"SAVES",11,AMBER)
	for i in range(1,4):
		var slot=str(i);var r=row(side_content,6)
		button(r,"Save "+slot,func():_save(slot)).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var b=button(r,"Load",func():
			if Store.load_game(sim,slot):_close_panel();world.frame_station();_refresh_hud();_toast("Loaded and paused"))
		b.disabled=not Store.exists(slot)
	button(side_content,"Training leak",func():sim.trigger_event("leak");_open_panel("events"))
	button(side_content,"Save and return to menu",func():
		if _save("auto"):_show_menu())
	paragraph(side_content,"Single-player expedition · on-device saves\nVersion 0.2.0",11,MUTED)

func _save(slot:String="auto") -> bool:
	var result=Store.save_game(sim,slot)
	_toast("Progress saved" if result==OK else "Could not write save")
	return result==OK

func _toggle_pause():
	sim.paused=not sim.paused;_refresh_hud()

func _cycle_layer():
	var layers=["normal","power","oxygen","logistics","signal"]
	world.layer=layers[(layers.find(world.layer)+1)%layers.size()];_refresh_hud()

func _format_time(value:float) -> String:
	return "%02d:%02d"%[int(value)/60,int(value)%60]

func _refresh_hud():
	if labels.is_empty() or not is_instance_valid(hud):return
	var stats=sim.metrics.get(sim.sector,{})
	var stock=sim.totals(sim.sector)
	labels.sector.text="↓ "+str(int(sim.db.sectors[sim.sector].depth))+" m  ·  "+Content.title(sim.db.sectors[sim.sector])
	labels.power.text="%.0f / %.0f"%[float(stats.get("demand",0)),float(stats.get("generation",0))]
	labels.oxygen.text="%.0f"%float(stats.get("oxygen",0))+(" O₂" if mobile else "  /  "+"reserve")
	labels.alloy.text=str(int(stock.get("alloy",0)))
	labels.data.text=str(int(stock.get("data",0)))
	labels.credits.text=str(sim.credits)+" cr"
	labels.pause.text="▶" if sim.paused else "Ⅱ"
	labels.speed.text="×"+str(sim.speed)
	var recovered=0
	for f in sim.findings:
		if f.sector==sim.sector and f.status=="recovered":recovered+=1
	labels.objective.text=_next_objective(recovered)
	var required_count=3 if sim.sector==3 else 2
	labels.progress.text="Findings: "+str(mini(recovered,required_count))+" / "+str(required_count)+"  ·  "+"Outposts: "+str(sim.sectors_open.size())+" / 4"
	labels.status.text="All primary systems nominal" if sim.events.is_empty() else "Incident detected. Inspect the compartment."
	labels.status.add_theme_color_override("font_color",TEAL if sim.events.is_empty() else AMBER)
	labels.incident.text="!" if sim.events.is_empty() else str(sim.events.size())+"!"
	labels.layer.text={"normal":"STATION OVERVIEW","power":"OVERLAY: POWER GRID","oxygen":"OVERLAY: PRESSURE & OXYGEN","logistics":"OVERLAY: CARGO ROUTES","signal":"OVERLAY: SIGNAL & ACOUSTICS"}[world.layer]
	labels.clock.text=_format_time(sim.time)+"  ·  LINK %.0f%%"%float(stats.get("signal",100))+"  ·  NOISE %.0f"%float(stats.get("noise",0))+("  ·  PAUSED" if sim.paused else "")
	labels.news.text=toast_text if toast_clock>0 else (str(sim.logbook[0].get("en","Archived expedition entry.")) if not sim.logbook.is_empty() else "")

func _toast(text:String):
	toast_text=text;toast_clock=5.0;_refresh_hud()

func _process(delta):
	if not running:return
	snapshot_clock+=delta
	if snapshot_clock>=1.0:
		snapshot_clock=0.0;_cache_android_snapshot()
	if sim.failed and not failure_shown:
		failure_shown=true;_show_failure()
	elif not sim.failed:
		failure_shown=false
	if sim.completed and not sim.failed and not victory_shown:
		victory_shown=true;sim.paused=true;_show_victory()
	elif not sim.completed:
		victory_shown=false
	sim.advance(delta)
	if sim.needs_save:
		var error=Store.save_game(sim)
		if error!=OK:
			sim.needs_save=false;_toast("Autosave failed. Check available storage.")
	if sim.researched.size()>known_research_count:
		known_research_count=sim.researched.size();sound("research")
	if int(sim.statistics.built)>known_build_count:
		known_build_count=int(sim.statistics.built);sound("build")
	if sim.events.size()>last_event_count:
		sound("alert")
	last_event_count=sim.events.size()
	toast_clock=maxf(0,toast_clock-delta);refresh_clock+=delta
	if refresh_clock>=0.75:
		refresh_clock=0;_refresh_hud()
		if panel_mode not in ["settings","build"]:
			_refresh_panel()

func _unhandled_key_input(event):
	if not event is InputEventKey or not event.pressed or event.echo or not running:return
	match event.keycode:
		KEY_SPACE:_toggle_pause()
		KEY_B:_open_panel("build")
		KEY_R:_open_panel("research")
		KEY_D:_open_panel("drones")
		KEY_TAB:_cycle_layer()
		KEY_F5:_save("1")
		KEY_F9:
			if Store.load_game(sim,"1"):_close_panel();world.frame_station();_refresh_hud()
		KEY_ESCAPE:
			if not panel_mode.is_empty():_close_panel()
			else:sim.paused=true;_open_panel("settings")

func _notification(what):
	if what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		if running:
			sim.paused=true;Store.save_game(sim)
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		if running:Store.save_game(sim)
		_save_settings();get_tree().quit()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if running:
			if panel_mode.is_empty():
				sim.paused=true;_open_panel("navigation" if mobile else "settings")
			else:
				_close_panel()
		else:
			get_tree().quit()

func _android_prepare_pause():
	if running:
		sim.paused=true
		_cache_android_snapshot()

func _cache_android_snapshot():
	if running and native_bridge!=null:
		native_bridge.cache_snapshot(Store.encoded_snapshot(sim))

func _android_did_resume():
	if running:
		sim.paused=true
		_refresh_hud()

func _confirm_demolition(id:int):
	var dialog=ConfirmationDialog.new();dialog.title="Dismantle module";dialog.theme=ui.theme;dialog.dialog_autowrap=true
	dialog.dialog_text="Connections will be removed. Stored cargo returns to base and 50% of the construction cost is recovered."
	dialog.ok_button_text="Dismantle";dialog.cancel_button_text="Cancel";ui.add_child(dialog)
	dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialog.get_ok_button().custom_minimum_size=Vector2(200,84);dialog.get_cancel_button().custom_minimum_size=Vector2(200,84)
	dialog.confirmed.connect(func():sim.demolish(id);world.selected=-1;_close_panel();dialog.queue_free())
	dialog.canceled.connect(func():dialog.queue_free())
	dialog.popup_centered(Vector2i(int(_screen_size().x)-48,400))

func _build_mobile_hud():
	var area=_screen_size();var width=area.x-32
	navigation_top=area.y-safe_bottom-192
	var top=panel(hud,Rect2(16,safe_top,width,198),10)
	var heading=row(top,10)
	var brand=column(heading,0);brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label(brand,"ABYSS RELAY",16,TEAL)
	labels.sector=label(brand,"",10,MUTED);labels.sector.autowrap_mode=TextServer.AUTOWRAP_OFF;labels.sector.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.pause=button(heading,"Ⅱ",_toggle_pause);labels.pause.custom_minimum_size=Vector2(72,64)
	labels.speed=button(heading,"×1",func():sim.speed=1 if sim.speed==4 else sim.speed*2;_refresh_hud());labels.speed.custom_minimum_size=Vector2(72,64)
	var systems=row(top,16)
	for key in ["power","oxygen"]:
		var stat=column(systems,0);stat.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label(stat,"POWER / kW" if key=="power" else "OXYGEN RESERVE",9,MUTED)
		labels[key]=label(stat,"—",18,AMBER if key=="power" else INK)
	var resources=row(top,14)
	for key in ["alloy","data","credits"]:
		var stat=row(resources,8);stat.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label(stat,key.to_upper(),9,MUTED)
		labels[key]=label(stat,"—",13,INK)
	var mission=panel(hud,Rect2(16,safe_top+210,width,100),8)
	mission_panel=mission.get_parent().get_parent()
	labels.objective=label(mission,"",14,INK)
	labels.progress=label(mission,"",10,AMBER)
	mission_bottom=safe_top+310
	labels.layer=paragraph(hud,"",9,MUTED);rect(labels.layer,24,mission_bottom+14,area.x-340,52)
	camera_controls=row(hud,8);rect(camera_controls,area.x-304,mission_bottom+10,280,64)
	labels.incident=button(camera_controls,"!",func():_open_panel("events"));labels.incident.custom_minimum_size=Vector2(64,64)
	labels.incident.tooltip_text="Diagnostics and incidents"
	for item in [["+",1.15],["−",1.0/1.15]]:
		var factor=float(item[1]);var zoom_button=button(camera_controls,str(item[0]),func():world.zoom_at(factor,world.origin));zoom_button.custom_minimum_size=Vector2(64,64)
	var center=button(camera_controls,"◎",func():world.frame_station());center.custom_minimum_size=Vector2(64,64);center.tooltip_text="Fit station to view"
	labels.clock=label(hud,"",9,MUTED);rect(labels.clock,24,navigation_top-132,width-16,28)
	labels.status=paragraph(hud,"",10,TEAL);rect(labels.status,24,navigation_top-100,width-16,30)
	labels.news=paragraph(hud,"",11,Color("a4c2bb"));rect(labels.news,24,navigation_top-66,width-16,58)
	labels.news.max_lines_visible=2;labels.news.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var bottom=panel(hud,Rect2(16,navigation_top,width,192),4)
	var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);bottom.add_child(grid)
	for item in [["build","+ Build"],["drones","Drones"],["research","Research"],["expeditions","Explore"],["contracts","Contracts"],["navigation","More"]]:
		var id=str(item[0]);var b=button(grid,str(item[1]),func():_open_panel(id));b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_create_sidebar()

func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _read_safe_area():
	safe_top=16;safe_bottom=16
	if OS.has_feature("android"):
		var safe=DisplayServer.get_display_safe_area();var screen=DisplayServer.screen_get_size()
		if screen.y>0 and safe.size.y>0:
			var scale_factor=_screen_size().y/float(screen.y)
			safe_top=maxf(16,clampf(safe.position.y*scale_factor,0,80))
			safe_bottom=maxf(16,clampf((screen.y-safe.end.y)*scale_factor,0,80))

func _layout_sidebar():
	if not is_instance_valid(sidebar):return
	var area=_screen_size()
	var height=clampf(area.y*0.43,460,740)
	if panel_mode=="build" and not build_choice.is_empty():height=440
	if sheet_expanded:height=navigation_top-safe_top-210
	rect(sidebar,16,navigation_top-height-10,area.x-32,height)
	labels.expand.text="Map" if sheet_expanded else "Expand"
	var showing=sidebar.visible and not panel_mode.is_empty()
	mission_panel.visible=not (showing and sheet_expanded)
	for key in ["clock","status","news"]:labels[key].visible=not showing
	camera_controls.visible=not (showing and sheet_expanded)
	var map_bottom=sidebar.position.y-8 if showing else navigation_top-144
	world.view_size=area
	world.interaction_rect=Rect2(0,mission_bottom,area.x,maxf(0,map_bottom-mission_bottom))
	world.origin=Vector2(area.x*0.5,(mission_bottom+map_bottom)*0.5+22)

func _request_layout():
	if layout_pending:return
	layout_pending=true;_rebuild_layout.call_deferred()

func _rebuild_layout():
	layout_pending=false
	if not is_instance_valid(ui):return
	for outcome in ["ExpeditionDefeat","ExpeditionVictory"]:
		var overlay=ui.get_node_or_null(outcome)
		if overlay:overlay.get_child(0).get_child(0).custom_minimum_size.x=_screen_size().x-48
	if running or settings_return=="menu":
		var scroll=sidebar_scroll.scroll_vertical if is_instance_valid(sidebar_scroll) else 0
		_build_hud();_refresh_hud();_refresh_panel();sidebar_scroll.set_deferred("scroll_vertical",scroll)
	else:_show_menu()

func _navigation_panel():
	for entry in [["routes","Cargo routes"],["sectors","Depth chart"],["events","Diagnostics and incidents"],["journal","Expedition journal"],["settings","Settings and saves"]]:
		var id=str(entry[0]);button(side_content,str(entry[1]),func():_open_panel(id))
	button(side_content,"Diagnostic overlay",_cycle_layer)
	button(side_content,"Center station",func():_close_panel();world.frame_station())
	button(side_content,"About and licenses",func():_open_panel("about"))

func _next_objective(recovered:int) -> String:
	if sim.completed:return "Network restored"
	if sim.sector==3:
		if recovered<3:return "Survey the abyssal signals"
		if "ocean_6" not in sim.researched:return "Decode the signal"
		return "Build and power the beacon"
	if sim.first_module("relay",sim.sector).is_empty():return "Build a relay station"
	if recovered<2:return "Dispatch a scout to the signals"
	if "hull_%d"%(sim.sector+1) not in sim.researched:return "Research stronger pressure hulls"
	return "Prepare the next outpost"

func _qa_panels():
	var english_only=_english_controls(menu)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(transition):transition.queue_free()
	selected=int(sim.first_module("lab",0).id)
	for mode in ["build","inspect","drones","research","expeditions","contracts","journal","sectors","events","settings","navigation","routes","about"]:
		panel_mode=mode;sidebar.visible=true;_refresh_panel()
		english_only=_english_controls(hud) and english_only
		await get_tree().create_timer(0.15).timeout
		print("UI_PANEL_OK ",mode)
	if DisplayServer.get_name()!="headless":
		panel_mode="build";_refresh_panel();await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../output/mobile-layout.png")
	print("UI_QA_OK")
	get_tree().quit(0 if english_only else 1)

func _english_controls(node:Node) -> bool:
	if not is_instance_valid(node):return true
	var valid=true
	var cyrillic=RegEx.create_from_string("[\\x{0400}-\\x{052f}]")
	var text=""
	if node is Label or node is Button:text=node.text
	elif node is Window:text=node.title
	if cyrillic.search(text)!=null:
		push_error("Non-English game text: "+text);valid=false
	for child in node.get_children():
		valid=_english_controls(child) and valid
	return valid

func _routes_panel():
	paragraph(side_content,"Resources travel between outposts through operational relays. A link or dock failure pauses delivery.")
	var options=OptionButton.new();options.custom_minimum_size.y=84;side_content.add_child(options)
	var keys=sim.db.resources.keys()
	for key in keys:options.add_item(_resource_name(str(key)))
	options.select(keys.find(route_resource));options.item_selected.connect(func(index):route_resource=keys[index])
	for s in sim.sectors_open:
		if s==sim.sector:continue
		var target=int(s)
		label(side_content,Content.title(sim.db.sectors[target]),16,TEAL)
		button(side_content,"Send 10 units",func():
			_toast("Cargo dispatched" if sim.send_shipment(sim.sector,target,route_resource,10) else "Check cargo, docks, relays and destination storage");_refresh_panel())
	divider(side_content)
	for shipment in sim.shipments:
		label(side_content,_resource_name(shipment.resource)+" × "+str(int(shipment.amount)),16,AMBER)
		paragraph(side_content,Content.title(sim.db.sectors[int(shipment.source)])+" → "+Content.title(sim.db.sectors[int(shipment.target)]),12,MUTED)
		_meter(side_content,1-float(shipment.remaining)/float(shipment.duration),TEAL)
		paragraph(side_content,"In transit: "+str(maxi(0,int(shipment.remaining)))+" s" if shipment.reason.is_empty() else "Delivery awaits a restored link or dock",12,MUTED)

func _show_failure():
	var v=_outcome_panel("ExpeditionDefeat","UPLINK LOST","The command outposts are lost and the rescue reserve is exhausted. Load a manual save or begin a new expedition.",AMBER)
	var shade=ui.get_node("ExpeditionDefeat")
	button(v,"Open saves",func():shade.queue_free();panel_mode="";_open_panel("settings"),true)
	button(v,"Return to menu",func():shade.queue_free();_show_menu())

func _show_victory():
	var v=_outcome_panel("ExpeditionVictory","NETWORK RESTORED","Signal decoded. The four observatories are connected, and the mystery of the deep has been revealed. Your station can continue in sandbox mode.",TEAL)
	var shade=ui.get_node("ExpeditionVictory")
	paragraph(v,"4 outposts linked  ·  %d technologies researched"%sim.researched.size(),12,AMBER)
	button(v,"Continue in sandbox",func():shade.queue_free(),true)
	button(v,"Save and return to menu",func():
		if _save("auto"):shade.queue_free();_show_menu())

func _outcome_panel(id:String,heading:String,description:String,accent:Color) -> VBoxContainer:
	var shade=ColorRect.new();shade.name=id;shade.color=Color(0.01,0.03,0.04,0.88);ui.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center=CenterContainer.new();shade.add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box=PanelContainer.new();center.add_child(box);box.custom_minimum_size.x=_screen_size().x-48
	box.add_theme_stylebox_override("panel",style(PANEL,accent.darkened(0.5),18))
	var margin=MarginContainer.new();box.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	var v=column(margin,20)
	label(v,heading,26,accent)
	paragraph(v,description,16,INK)
	return v

func _about_panel():
	label(side_content,"ABYSS RELAY  /  0.2.0",18,TEAL)
	paragraph(side_content,"A research network in the ocean depths. A single-player Android game. Progress is stored on your device.")
	label(side_content,"Godot Engine 4.5.1",15,AMBER)
	paragraph(side_content,FileAccess.get_file_as_string("res://assets/licenses/Godot-LICENSE.txt"),11,MUTED)
	label(side_content,"Manrope / SIL Open Font License",14,AMBER)
	paragraph(side_content,FileAccess.get_file_as_string("res://assets/FONT-LICENSE.txt"),11,MUTED)
