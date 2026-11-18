extends Node2D

signal cell_selected(cell: Vector2i)
signal module_selected(id: int)
signal finding_selected(id: String)

const Content = preload("res://scripts/content.gd")
var sim
var origin = Vector2(360, 640)
var view_size = Vector2(720,1280)
var interaction_rect = Rect2(0,0,720,1280)
var gesture_was_pinch = false
var pan = Vector2.ZERO
var zoom = 1.0
var selected = -1
var selected_finding = ""
var build_kind = ""
var hover = Vector2i(999,999)
var layer = "normal"
var elapsed = 0.0
var dragging = false
var drag_start = Vector2.ZERO
var last_pointer = Vector2.ZERO
var touches = {}
var pinch_distance = 0.0
var reduced_motion = false
var font: Font
var glows: Texture2D
var terrain: Array = []
var particles: Array = []
var details: Array = []
var interaction_enabled = true
var seabed: Texture2D

func _ready():
	var font_variation = FontVariation.new()
	font_variation.base_font = load("res://assets/Manrope.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	font = font_variation
	seabed = load("res://assets/seabed.png")
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.2,0.9,0.8,0.14)); gradient.set_color(1, Color(0.1,0.6,0.6,0))
	var tex = GradientTexture2D.new(); tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL; tex.fill_from = Vector2(0.5,0.5); tex.fill_to = Vector2(1,0.5)
	tex.width = 128; tex.height = 128; glows = tex
	var random = RandomNumberGenerator.new(); random.seed = 621
	for i in range(120):
		particles.append([Vector2(random.randf(),random.randf()), random.randf_range(0.6,2.0),random.randf_range(4,12)])
	for x in range(-10,11):
		for y in range(-10,11):
			terrain.append([x,y,random.randf()])
	for i in range(65):
		details.append([random.randf_range(-10,10),random.randf_range(-10,10),random.randf(),random.randf()])

func iso(v: Vector2) -> Vector2:
	return origin + pan + Vector2((v.x-v.y)*62,(v.x+v.y)*31)*zoom

func unproject(v: Vector2) -> Vector2:
	var local = (v-origin-pan)/zoom
	return Vector2(local.x/124+local.y/62,local.y/62-local.x/124)

func screen_cell(v: Vector2) -> Vector2i:
	var p = unproject(v)
	return Vector2i(roundi(p.x),roundi(p.y))

func center_on(cell: Vector2):
	pan = -Vector2((cell.x-cell.y)*62,(cell.x+cell.y)*31)*zoom

func frame_station():
	var low=Vector2(INF,INF);var high=Vector2(-INF,-INF)
	for m in sim.modules:
		if int(m.sector)!=sim.sector:continue
		var p=Vector2((m.x-m.y)*62,(m.x+m.y)*31)
		low=low.min(p+Vector2(-55,-90));high=high.max(p+Vector2(55,50))
	if not low.is_finite():return
	var extent=high-low
	var available=interaction_rect.size-Vector2(64,40)
	zoom=clampf(minf(available.x/maxf(1,extent.x),available.y/maxf(1,extent.y)),0.45,1.15)
	pan=-(low+high)*0.5*zoom

func zoom_at(factor:float,anchor:Vector2):
	var before=unproject(anchor)
	zoom=clampf(zoom*factor,0.45,1.65)
	pan+=anchor-iso(before)

func _process(delta):
	elapsed += delta if not reduced_motion else 0.0
	queue_redraw()

func _unhandled_input(event):
	if not interaction_enabled or sim == null:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if interaction_rect.has_point(event.position):zoom_at(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.91,event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not interaction_rect.has_point(event.position) or gesture_was_pinch:return
				dragging = true; drag_start = event.position; last_pointer = event.position
			else:
				if dragging and not gesture_was_pinch and event.position.distance_to(drag_start) < 8:
					_select_at(event.position)
				dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			build_kind = ""; selected = -1
	elif event is InputEventMouseMotion:
		if gesture_was_pinch:return
		hover = screen_cell(event.position)
		if dragging:
			pan += event.position-last_pointer
		last_pointer = event.position
	elif event is InputEventScreenTouch:
		if event.pressed:
			if not interaction_rect.has_point(event.position):return
			if touches.is_empty():gesture_was_pinch=false
			touches[event.index] = event.position
		else:
			touches.erase(event.index); pinch_distance = 0.0
			if touches.is_empty() and gesture_was_pinch:
				dragging=false;gesture_was_pinch=false
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):return
		touches[event.index] = event.position
		if touches.size() == 2:
			var positions = touches.values(); var distance = positions[0].distance_to(positions[1])
			if pinch_distance > 0:
				zoom_at(distance/pinch_distance,(positions[0]+positions[1])*0.5)
			pinch_distance = distance
			dragging = false;gesture_was_pinch=true
		elif not build_kind.is_empty():
			hover = screen_cell(event.position)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.factor,event.position)
	elif event is InputEventPanGesture:
		pan -= event.delta*12

func _select_at(point: Vector2):
	var cell = screen_cell(point)
	if not build_kind.is_empty():
		hover = cell; cell_selected.emit(cell); return
	# Raised roofs project above their logical footprint.
	var candidates = sim.modules.duplicate()
	candidates.sort_custom(func(a,b):return int(a.x)+int(a.y)>int(b.x)+int(b.y))
	for m in candidates:
		if m.sector != sim.sector:
			continue
		var p = iso(Vector2(m.x,m.y))
		if Rect2(p-Vector2(48,72)*zoom,Vector2(96,94)*zoom).has_point(point):
			selected = int(m.id); module_selected.emit(selected); return
	for f in sim.findings:
		if f.sector == sim.sector and f.status != "unknown" and iso(Vector2(f.cell[0],f.cell[1])).distance_to(point)<32*zoom:
			selected_finding = f.id; finding_selected.emit(f.id); return
	selected = -1; module_selected.emit(-1)

func _draw():
	draw_rect(Rect2(-4000,-4000,10000,10000),Color("061922"))
	if sim == null:
		return
	if seabed:
		var texture_size=Vector2(seabed.get_size())
		var cover_scale=maxf(view_size.x/texture_size.x,view_size.y/texture_size.y)
		var cover_size=texture_size*cover_scale
		draw_texture_rect(seabed,Rect2((view_size-cover_size)*0.5,cover_size),false,Color(0.8,0.9,0.94,0.78))
		draw_rect(Rect2(Vector2.ZERO,view_size),Color(0.015,0.045,0.06,0.27))
	var accent = Color(sim.db.sectors[sim.sector].color)
	# Soft fields and subtle grid give the station a sense of scale.
	draw_texture_rect(glows,Rect2(iso(Vector2.ZERO)-Vector2(780,390)*zoom,Vector2(1560,780)*zoom),false,Color(0.25,0.65,0.62,0.8))
	for tile in terrain:
		var cell = Vector2(tile[0],tile[1]); var p = iso(cell)
		if p.x < -160 or p.x>view_size.x+160 or p.y < -100 or p.y>view_size.y+100:
			continue
		var floor_color = Color(0.075,0.16,0.18,0.25+float(tile[2])*0.12)
		if sim.cell_blocked(Vector2i(tile[0],tile[1]),sim.sector):
			floor_color = Color(0.08,0.14,0.16,0.7)
		_poly([p+Vector2(0,-31)*zoom,p+Vector2(62,0)*zoom,p+Vector2(0,31)*zoom,p+Vector2(-62,0)*zoom],floor_color)
		var grid_alpha = 0.13 if not build_kind.is_empty() else 0.012
		_line_loop([p+Vector2(0,-31)*zoom,p+Vector2(62,0)*zoom,p+Vector2(0,31)*zoom,p+Vector2(-62,0)*zoom],Color(0.4,0.76,0.74,grid_alpha),1)
		if sim.cell_blocked(Vector2i(tile[0],tile[1]),sim.sector):
			_rock(p,float(tile[2]))
	for item in details:
		var p = iso(Vector2(item[0],item[1]))
		if sim.at_cell(Vector2i(roundi(item[0]),roundi(item[1])),sim.sector).is_empty():
			_coral(p,item[2],item[3],accent)
	for deposit in sim.deposits:
		if int(deposit.sector) != sim.sector or int(deposit.amount) <= 0:
			continue
		var p = iso(Vector2(deposit.cell[0],deposit.cell[1]))
		for i in range(5):
			var q = p+Vector2((i-2)*9,sin(i*2.0)*5)*zoom
			_poly([q+Vector2(-5,2)*zoom,q+Vector2(-2,-9-i%3*3)*zoom,q+Vector2(4,-6)*zoom,q+Vector2(7,4)*zoom],Color("786d53"))
		if build_kind == "mine":
			draw_arc(p,25*zoom,0,TAU,32,Color("dbbc7f"),1.5,true)
			draw_string(font,p+Vector2(-20,34)*zoom,str(int(deposit.amount)),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("dbbc7f"))
	for vent in sim.db.sectors[sim.sector].vents:
		var p=iso(Vector2(vent[0],vent[1]))
		draw_texture_rect(glows,Rect2(p-Vector2(50,35)*zoom,Vector2(100,70)*zoom),false,Color(1.0,0.45,0.2,0.5))
		_rock(p,0.8)
	# Seabed cables and glazed connections.
	for pair in sim.visual_connections():
		var m = pair[0]; var other = pair[1]
		if m.sector == sim.sector:
			_connection(iso(Vector2(m.x,m.y)),iso(Vector2(other.x,other.y)),m,other)
	for link in sim.links:
		var a = sim.module_by_id(int(link.a)); var b = sim.module_by_id(int(link.b))
		if not a.is_empty() and not b.is_empty() and a.sector == sim.sector:
			var color = Color("e3b56e") if layer == "power" else Color("35565b")
			draw_line(iso(Vector2(a.x,a.y)),iso(Vector2(b.x,b.y)),color,3*zoom,true)
	for f in sim.findings:
		if f.sector == sim.sector and f.status != "unknown":
			_finding(f,accent)
	var objects = []
	for m in sim.modules:
		if m.sector == sim.sector:
			objects.append(m)
	objects.sort_custom(func(a,b):return int(a.x)+int(a.y)<int(b.x)+int(b.y))
	for m in objects:
		_module(m)
	for d in sim.drones:
		if d.sector == sim.sector:
			_drone(d)
	if not build_kind.is_empty() and hover.x != 999:
		var error = sim.placement_error(build_kind,hover,sim.sector)
		var p = iso(Vector2(hover))
		var color = Color(0.35,0.9,0.75,0.4) if error.is_empty() else Color(0.95,0.4,0.34,0.4)
		_poly([p+Vector2(0,-31)*zoom,p+Vector2(62,0)*zoom,p+Vector2(0,31)*zoom,p+Vector2(-62,0)*zoom],color)
		_line_loop([p+Vector2(0,-31)*zoom,p+Vector2(62,0)*zoom,p+Vector2(0,31)*zoom,p+Vector2(-62,0)*zoom],color.lightened(0.3),2)
	# Slow ocean life is visually separate from the simulation.
	for i in range(8):
		var fish = Vector2(fposmod(elapsed*(9+i*2)+i*227,view_size.x+300)-150,120+fposmod(i*137.0,view_size.y-160))
		_creature(fish,i,accent)
	for particle in particles:
		var p = particle[0]*view_size+Vector2(sin(elapsed*0.13+particle[0].y)*9,-fposmod(elapsed*particle[2],view_size.y))
		p.y = fposmod(p.y,view_size.y)
		draw_circle(p,particle[1],Color(0.5,0.85,0.82,0.14))

func _poly(points: Array, color: Color):
	draw_colored_polygon(PackedVector2Array(points),color)

func _line_loop(points: Array,color:Color,width:float):
	var closed = points.duplicate(); closed.append(points[0])
	draw_polyline(PackedVector2Array(closed),color,width,true)

func _rock(p: Vector2,seed_value: float):
	var scale_factor = zoom*(0.5+seed_value)
	_poly([p+Vector2(-23,8)*scale_factor,p+Vector2(-30,-12)*scale_factor,p+Vector2(-4,-40)*scale_factor,p+Vector2(20,-30)*scale_factor,p+Vector2(33,8)*scale_factor],Color("102e35"))
	_poly([p+Vector2(-30,-12)*scale_factor,p+Vector2(-4,-40)*scale_factor,p+Vector2(5,-7)*scale_factor,p+Vector2(-23,8)*scale_factor],Color("193b40"))

func _coral(p:Vector2,a:float,b:float,accent:Color):
	var tint = accent; tint.a = 0.22+a*0.25
	for i in range(3):
		var end = p+Vector2((i-1)*9,-12-b*19)*zoom
		draw_line(p,end,tint,1.5*zoom,true)
		draw_circle(end,1.8*zoom,tint.lightened(0.3))

func _connection(a:Vector2,b:Vector2,ma:Dictionary,mb:Dictionary):
	var lift = Vector2(0,-13)*zoom
	draw_line(a+Vector2(0,8)*zoom,b+Vector2(0,8)*zoom,Color(0,0,0,0.25),22*zoom,true)
	draw_line(a+lift,b+lift,Color("18373e"),19*zoom,true)
	draw_line(a+lift-Vector2(0,3)*zoom,b+lift-Vector2(0,3)*zoom,Color("628583"),2*zoom,true)
	var tint = Color("5cbcb2") if ma.powered and mb.powered else Color("344e55")
	if layer == "oxygen":
		tint = Color("d8aa6b") if ma.sealed or mb.sealed else Color("7bcee0")
	elif layer == "power":
		tint = Color("ebbf71") if ma.powered and mb.powered else Color("db6c60")
	elif layer == "logistics":
		tint = Color("c6a0dc")
	draw_line(a+lift,b+lift,tint,4*zoom,true)
	for j in range(1,4):
		var p = a.lerp(b,j/4.0)+lift
		draw_line(p+Vector2(-4,-5)*zoom,p+Vector2(4,5)*zoom,Color(0.62,0.78,0.76,0.4),1.5*zoom,true)

func _module(m:Dictionary):
	var p = iso(Vector2(m.x,m.y)); var def = sim.db.modules[m.kind]
	var z = zoom
	var accent = Color(def.color)
	var powered = m.powered and m.enabled
	var top = Color("9eb6b6") if powered else Color("536a71")
	var left = Color("36545e"); var right = Color("233e49")
	if not m.built:
		top = Color(0.25,0.7,0.65,0.35); left.a = 0.4; right.a = 0.4
	if m.water>25 or m.leak>0:
		accent = Color("ed8a66")
	if layer == "power":
		accent = Color("ebbb6e") if powered else Color("dc776b")
	elif layer == "oxygen":
		accent = Color("85cce0") if m.oxygen>20 else Color("e98271")
	elif layer == "signal":
		accent = Color("7dd9bb")
	# Contact shadow, slender piles, chamfered pressure shell.
	draw_set_transform(p,0,Vector2(z,z))
	draw_ellipse_local(Vector2(0,10),Vector2(53,18),Color(0,0,0,0.3))
	for leg in [Vector2(-27,6),Vector2(26,7)]:
		draw_line(leg,leg+Vector2(0,21),Color("28464d"),5,true)
	var h = 31.0 if def.shape != "antenna" else 27.0
	var points = [Vector2(0,-26-h),Vector2(43,-5-h),Vector2(43,13-h),Vector2(0,35-h),Vector2(-43,13-h),Vector2(-43,-5-h)]
	_poly([points[4],points[3],Vector2(0,24),Vector2(-43,2)],left)
	_poly([points[3],points[2],Vector2(43,2),Vector2(0,24)],right)
	_poly(points,top)
	_line_loop(points,Color("c9d7ce") if powered else Color("657c7e"),1.0)
	# Surface panels follow the isometric axes.
	_poly([Vector2(-30,-29),Vector2(0,-44),Vector2(30,-29),Vector2(0,-14)],Color("59767a"))
	_poly([Vector2(-27,-29),Vector2(0,-42),Vector2(27,-29),Vector2(0,-16)],Color("789599"))
	var window_color = Color("f6c57b") if powered else Color("324d58")
	for i in range(4):
		var x = -35+i*8
		_poly([Vector2(x,-11+i*0.0),Vector2(x+5,-8.5),Vector2(x+5,1),Vector2(x,-1.5)],window_color)
		var rx = 7+i*8
		_poly([Vector2(rx,8-i*4),Vector2(rx+5,5.5-i*4),Vector2(rx+5,12-i*4),Vector2(rx,14.5-i*4)],accent.darkened(0.15) if powered else Color("2b4651"))
	match def.shape:
		"dome":
			draw_ellipse_local(Vector2(0,-34),Vector2(26,13),Color("b6cbc5"))
			_poly([Vector2(-24,-35),Vector2(-17,-55),Vector2(0,-65),Vector2(18,-54),Vector2(25,-35)],Color("4d8992"))
			draw_arc(Vector2(0,-35),25,PI,TAU,24,Color("aed7d0"),1.6,true)
			draw_line(Vector2(0,-60),Vector2(0,-34),Color("99c3be"),1,true)
			draw_line(Vector2(-17,-52),Vector2(18,-52),Color("95bdbb"),1,true)
			draw_line(Vector2(-24,-36),Vector2(24,-36),window_color,3,true)
		"tanks":
			for i in range(3):
				var v = Vector2(-17+i*16,-35+i*2)
				draw_line(v,v+Vector2(0,-20),Color("c6d7ce"),12,true)
				draw_line(v+Vector2(-5,-10),v+Vector2(5,-10),accent,4,true)
				draw_circle(v+Vector2(0,-20),5,Color("e0e7dc"))
		"turbine":
			draw_ellipse_local(Vector2(0,-37),Vector2(22,12),Color("293f47"))
			for i in range(6):
				var angle = i*TAU/6+elapsed*(0.8 if powered else 0)
				draw_line(Vector2(0,-37),Vector2(cos(angle)*19,-37+sin(angle)*9),accent,4,true)
			draw_circle(Vector2(0,-37),4,Color("e8d9b8"))
		"battery":
			for i in range(3):
				_poly([Vector2(-20+i*14,-40),Vector2(-10+i*14,-35),Vector2(-10+i*14,-20),Vector2(-20+i*14,-25)],accent.darkened(0.2))
				draw_line(Vector2(-18+i*14,-34),Vector2(-12+i*14,-31),Color("f4d38b"),2,true)
		"cargo":
			for i in range(3):
				_box(Vector2(-16+i*16,-35+i*3),Vector2(13,11),accent)
		"dock":
			draw_ellipse_local(Vector2(0,-30),Vector2(28,16),Color("193c47"))
			draw_arc(Vector2(0,-30),23,0,TAU,30,accent,2,true)
			for i in range(4):
				var a = i*TAU/4
				draw_circle(Vector2(cos(a)*24,-30+sin(a)*12),2.5,Color("a2efe4"))
		"drill":
			draw_line(Vector2(-19,-23),Vector2(0,-69),Color("bdc8b7"),4,true)
			draw_line(Vector2(19,-23),Vector2(0,-69),Color("bdc8b7"),4,true)
			draw_line(Vector2(0,-67),Vector2(0,-26),accent,5,true)
			for i in range(4):
				draw_line(Vector2(-5,-55+i*7),Vector2(5,-51+i*7),Color("3e4b49"),2,true)
		"antenna":
			draw_line(Vector2(0,-27),Vector2(0,-75),Color("b8cfc8"),3,true)
			draw_line(Vector2(-20,-58),Vector2(20,-58),accent,2,true)
			draw_circle(Vector2(0,-75),4,accent)
			if powered:
				var radius = 8+fposmod(elapsed*9,16)
				draw_arc(Vector2(0,-75),radius,PI*1.1,PI*1.9,20,Color(accent,0.4),1,true)
		"factory", "pump":
			_box(Vector2(-12,-39),Vector2(23,17),accent)
			draw_line(Vector2(14,-23),Vector2(14,-51),Color("9aaba6"),7,true)
			draw_ellipse_local(Vector2(14,-51),Vector2(4,2),Color("1c3540"))
		"corridor":
			draw_line(Vector2(-23,-27),Vector2(23,-27),accent,5,true)
	if not m.built:
		for i in range(3):
			draw_line(Vector2(-40,-9+i*7),Vector2(0,12+i*7),Color(0.4,0.9,0.75,0.45),1,true)
	if m.leak>0:
		draw_circle(Vector2(28,-18),5,Color("f5a37a"))
		for i in range(3):
			var t = fposmod(elapsed*0.6+i*0.3,1)
			draw_circle(Vector2(32+t*10,-20-t*30),2*(1-t),Color(0.5,0.85,0.95,0.7))
	draw_set_transform(Vector2.ZERO)
	if selected == m.id:
		var ring = [p+Vector2(0,-35)*z,p+Vector2(65,0)*z,p+Vector2(0,35)*z,p+Vector2(-65,0)*z]
		_line_loop(ring,Color("79e2cf"),2)
		var name_text = Content.title(def)
		var width = font.get_string_size(name_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		draw_style_box(_label_style(),Rect2(p+Vector2(-width/2-12,-112*z),Vector2(width+24,28)))
		draw_string(font,p+Vector2(-width/2,-92*z),name_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e7eee6"))
	elif zoom>0.75 and m.kind in ["core","dock","relay"]:
		var label_text = {"core":"RELAY 01","dock":"DOCK","relay":"UPLINK"}[m.kind]
		draw_string(font,p+Vector2(-24,43*z),label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(0.57,0.77,0.74,0.7))

func _label_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new(); style.bg_color = Color("122e36"); style.corner_radius_top_left = 5; style.corner_radius_top_right = 5; style.corner_radius_bottom_left = 5; style.corner_radius_bottom_right = 5
	return style

func _box(p:Vector2,size:Vector2,color:Color):
	_poly([p+Vector2(-size.x/2,0),p+Vector2(0,-size.y/2),p+Vector2(size.x/2,0),p+Vector2(0,size.y/2)],color.lightened(0.15))
	_poly([p+Vector2(-size.x/2,0),p+Vector2(0,size.y/2),p+Vector2(0,size.y/2+9),p+Vector2(-size.x/2,9)],color.darkened(0.3))
	_poly([p+Vector2(size.x/2,0),p+Vector2(0,size.y/2),p+Vector2(0,size.y/2+9),p+Vector2(size.x/2,9)],color.darkened(0.45))

func draw_ellipse_local(center:Vector2,radii:Vector2,color:Color):
	var points = []
	for i in range(32):
		var a = TAU*i/32
		points.append(center+Vector2(cos(a),sin(a))*radii)
	_poly(points,color)

func _drone(d:Dictionary):
	var fraction=1.0 if sim.paused else clampf(sim.accumulator/sim.STEP,0.0,1.0)
	var smooth_pos=Vector2(d.prev[0],d.prev[1]).lerp(Vector2(d.pos[0],d.pos[1]),fraction)
	var p = iso(smooth_pos)+Vector2(0,-38)*zoom
	var tint = Color("e9c384") if d.kind in ["engineer","miner"] else Color("7fd6d5")
	if not d.path.is_empty() and (layer == "logistics" or not d.task.is_empty()):
		var points = [p]
		for c in d.path:
			points.append(iso(Vector2(c[0],c[1]))+Vector2(0,-28)*zoom)
		draw_polyline(PackedVector2Array(points),Color(tint,0.16),1,true)
	draw_texture_rect(glows,Rect2(p-Vector2(30,20)*zoom,Vector2(60,40)*zoom),false,Color(tint,0.7))
	draw_set_transform(p,0,Vector2(zoom,zoom))
	draw_line(Vector2(-12,1),Vector2(12,1),Color("182d37"),11,true)
	draw_line(Vector2(-7,-4),Vector2(7,-4),tint,7,true)
	draw_circle(Vector2(10,-2),3,Color("d9fff0"))
	draw_line(Vector2(-15,-6),Vector2(-15,7),Color("a0b7b5"),2,true)
	draw_line(Vector2(15,-6),Vector2(15,7),Color("a0b7b5"),2,true)
	if not d.cargo.is_empty():
		_box(Vector2(0,7),Vector2(12,7),Color("ab9e78"))
	draw_set_transform(Vector2.ZERO)

func _finding(f:Dictionary,accent:Color):
	var p = iso(Vector2(f.cell[0],f.cell[1]))
	var recovered = f.status == "recovered"
	var tint = Color("5c898b") if recovered else Color("d9ba80")
	draw_arc(p,19*zoom,0,TAU,30,Color(tint,0.55),1,true)
	_poly([p+Vector2(0,-13)*zoom,p+Vector2(10,0)*zoom,p+Vector2(0,13)*zoom,p+Vector2(-10,0)*zoom],Color(tint,0.3))
	draw_circle(p,3*zoom,tint)
	if not recovered:
		var r = 23+fposmod(elapsed*6,18)
		draw_arc(p,r*zoom,0,TAU,40,Color(tint,0.24),1,true)

func _creature(p:Vector2,index:int,accent:Color):
	var tint = Color(accent.darkened(0.65),0.32)
	if index==0:
		var body = [p+Vector2(-75,0),p+Vector2(-48,-15),p+Vector2(15,-19),p+Vector2(63,-4),p+Vector2(81,-16),p+Vector2(73,7),p+Vector2(82,22),p+Vector2(59,8),p+Vector2(8,14),p+Vector2(-40,10)]
		_poly(body,tint)
	elif index==2:
		_poly([p+Vector2(-24,-12),p+Vector2(0,-3),p+Vector2(24,-12),p+Vector2(9,6),p+Vector2(0,9),p+Vector2(-9,6)],tint)
		draw_line(p+Vector2(0,6),p+Vector2(-5,28),tint,2,true)
	elif index==4:
		for i in range(7):
			draw_circle(p+Vector2(i*6,sin(elapsed+i*0.7)*5),3,Color(accent,0.12))
	elif index==5:
		_poly([p+Vector2(-16,0),p+Vector2(4,-6),p+Vector2(12,0),p+Vector2(4,6)],tint)
		for i in range(4):
			draw_line(p+Vector2(-13,i*2-3),p+Vector2(-33,sin(elapsed+i)*6+i*2-3),tint,1,true)
	elif index==6:
		p=Vector2(1460,640)
		for i in range(5):
			draw_line(p+Vector2(i*8,0),p+Vector2(i*8+sin(elapsed+i)*3,-25-i*3),Color(accent,0.15),2,true)
	elif index==7:
		p=Vector2(120,620)
		for i in range(7):
			var a=i*TAU/7+elapsed*0.04
			draw_circle(p+Vector2(cos(a),sin(a))*10,5,Color(accent,0.12))
	elif index==3:
		draw_arc(p,9,PI,TAU,14,Color(accent,0.18),2,true)
		for i in range(3):
			draw_line(p+Vector2(i*4-4,0),p+Vector2(i*5-4+sin(elapsed+i)*4,18),Color(accent,0.12),1,true)
	else:
		_poly([p+Vector2(-9,0),p+Vector2(1,-4),p+Vector2(9,0),p+Vector2(1,4)],tint)
		_poly([p+Vector2(-7,0),p+Vector2(-12,-4),p+Vector2(-12,4)],tint)
