extends Node2D
var time=0.0
var reduced=false
func _process(delta):
	if not reduced:time+=delta
	queue_redraw()
func _draw():
	var area=get_viewport_rect().size
	for i in range(48):
		var x=fposmod(i*137.7+sin(time*0.1+i)*12,area.x)
		var y=fposmod(i*83.1-time*(2+i%4),area.y+20)
		draw_circle(Vector2(x,y),1.0+i%3*0.5,Color(0.4,0.9,0.85,0.10))
	for i in range(3):
		var p=Vector2(fposmod(time*(8+i*3)+i*400,area.x+200)-100,area.y*(0.27+i*0.2))
		var size_factor=0.7+i*0.25
		var points=PackedVector2Array([p+Vector2(-26,0)*size_factor,p+Vector2(0,-8)*size_factor,p+Vector2(28,0)*size_factor,p+Vector2(2,8)*size_factor])
		draw_colored_polygon(points,Color(0.03,0.15,0.18,0.45))
		draw_colored_polygon(PackedVector2Array([p+Vector2(-26,0)*size_factor,p+Vector2(-39,-9)*size_factor,p+Vector2(-39,9)*size_factor]),Color(0.03,0.15,0.18,0.45))
