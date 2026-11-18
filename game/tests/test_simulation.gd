extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Store = preload("res://scripts/save_store.gd")
var passed = 0
var failed = 0

func check(condition:bool,description:String):
	if condition:
		passed+=1;print("PASS ",description)
	else:
		failed+=1;push_error("FAIL "+description)

func fresh():
	var s=Sim.new();s.new_game();s.auto_pause=false;s.next_event=1e12
	return s

func run_for(s,seconds:float):
	for i in range(roundi(seconds/Sim.STEP)):
		s.tick(Sim.STEP)

func quiet(s):
	for m in s.modules:
		if m.kind in ["mine","refinery","lab"]:
			m.enabled=false

func _initialize():
	Store.prefix = "user://test_relay_"
	var s=fresh()
	check(s.modules.size()==9 and s.drones.size()==4,"Initial base is connected and has four drone classes")
	check(s.db.modules.size()==24 and s.db.research.size()==30 and s.db.events.size()==24 and s.findings.size()==18,"Content catalogue has the planned counts")
	check(s.first_module("lab",0).powered,"Initial laboratory receives power")
	var start_time=s.time;s.paused=true;s.advance(1)
	check(s.time==start_time,"Pause freezes simulation")
	s.paused=false;s.speed=4;s.advance(0.25)
	check(absf(s.time-start_time-1)<0.001,"4x speed runs exactly one second for 0.25 wall seconds")

	s=fresh();quiet(s)
	var before=s.total_physical("alloy")
	var site=s.place("relay",Vector2i(-2,0),0)
	check(not site.is_empty() and s.total_physical("alloy")==before,"Blueprint reserves without creating or consuming cargo")
	check(not s.can_pay({"alloy":120},0),"Reserved materials cannot be spent twice")
	check(s.cancel_site(int(site.id)) and s.total_physical("alloy")==before,"Cancelling before pickup conserves materials")
	check(s.can_pay({"alloy":before},0),"Cancelling releases all source reservations")

	s=fresh();quiet(s);before=s.total_physical("alloy")
	site=s.place("relay",Vector2i(-2,0),0)
	run_for(s,3)
	check(s.cancel_site(int(site.id)),"Cancelling a blueprint during a delivery succeeds")
	run_for(s,20)
	check(s.total_physical("alloy")==before,"Mid-delivery cancellation conserves all alloy")
	check(s.can_pay({"alloy":before},0),"Mid-delivery cancellation does not leak reservations")

	s=fresh();quiet(s);before=s.total_physical("alloy")
	site=s.place("relay",Vector2i(-2,0),0)
	run_for(s,70)
	check(site.built,"Drones deliver and engineer completes construction")
	check(s.total_physical("alloy")==before-30,"Construction consumes exactly its recipe cost")
	check(s.statistics.built==1,"Construction completes once")

	s=fresh();quiet(s)
	var source=s.first_module("core",0);var target=s.first_module("warehouse",0)
	var d=s.drones[1]
	before=s.total_physical("alloy")
	s._assign_transfer(d,source,target,"alloy",10)
	check(s._available(source,"alloy")==120,"Cargo pickup is exclusively reserved")
	s.cancel_drone(int(d.id));run_for(s,8)
	check(s.total_physical("alloy")==before and s._available(source,"alloy")==before,"Cancelling a queued transport releases reservations")

	s=fresh();var gen=s.first_module("generator",0);gen.enabled=false
	var battery=s.first_module("battery",0);battery.battery=0
	s._tick_networks(0.05)
	check(not s.first_module("oxygen",0).powered,"Disconnected generation and empty battery disable consumers")
	battery.battery=1.0;s._tick_networks(1.0)
	check(s.first_module("oxygen",0).powered and battery.battery<1,"Battery supplies deficit using kWh units")

	s=fresh();var isolated=s.first_module("lab",0);isolated.sealed=true;isolated.oxygen=0.1
	s._tick_networks(10)
	check(isolated.oxygen<=0.1,"A sealed compartment cannot borrow oxygen from the global reserve")

	s=fresh();s.trigger_event("leak");check(s.events.size()==1 and s.events[0].phase=="warning","Incidents start with a warning")
	run_for(s,float(s.events[0].remaining)+1)
	var leaking=s.module_by_id(int(s.events[0].target)) if not s.events.is_empty() else {}
	check(not leaking.is_empty() and leaking.leak>0,"Leak develops after the warning window")
	run_for(s,50)
	check(s.statistics.repairs>=1,"Engineer delivers repair materials and repairs autonomously")

	s=fresh();check(s.dispatch("find_0"),"Scout expedition can be dispatched")
	run_for(s,65)
	var f=s.findings[0]
	check(f.status=="recovered" and s.statistics.scanned==1,"Scout recovers the discovery exactly once")
	check(s.totals(0).samples>=2 or s.total_physical("data")>22,"Samples or their processed data return to the base")
	check(not s.dispatch("find_0"),"Recovered discoveries cannot be harvested repeatedly")

	s=fresh();before=s.total_physical("data")
	check(s.start_research("hull_1"),"Research starts with a powered lab and available data")
	check(s.total_physical("data")==before-21,"Research data is charged once")
	check(not s.start_research("hull_2"),"Parallel research is rejected")
	run_for(s,20)
	check("hull_1" in s.researched,"Research unlocks pressure hull technology")

	s=fresh();var c=s.db.contracts[0]
	check(s.claim_contract(c.id),"Contract consumes available stock")
	var credits=s.credits
	check(not s.claim_contract(c.id) and s.credits==credits,"Contract rewards cannot be claimed twice")

	s=fresh();check(not s.open_sector(1),"Next sector enforces prerequisites")
	s.researched.append("hull_1");s.findings[0].status="recovered";s.findings[1].status="recovered"
	s._add_module("relay",-2,0,0);s._tick_networks(0)
	check(s.open_sector(1) and s.sectors_open.size()==2,"Prepared relay opens the next depth")
	check(s.first_module("core",1).stock.alloy==60,"New outpost receives its accounted starter cargo")

	s=fresh();s.dispatch("find_1");s.place("relay",Vector2i(-2,0),0);run_for(s,4)
	var state=s.snapshot();var restored=fresh()
	check(restored.restore(JSON.parse_string(JSON.stringify(state))),"Save round-trip restores in-flight tasks and reservations")
	check(restored.paused and restored.total_physical("alloy")==s.total_physical("alloy"),"Load preserves cargo and starts paused")
	run_for(restored,70)
	check(restored.statistics.built==1 and restored.statistics.scanned==1,"Restored assignments complete correctly")
	var bad=state.duplicate(true);bad.version=999
	var prior=restored.time
	check(not restored.restore(bad) and restored.time==prior,"Unsupported saves do not mutate live state")
	check(Store.save_game(s,"3")==OK,"Atomic save writes a verified snapshot")
	check(Store.save_game(s,"3")==OK,"A second save retains a backup")
	var file=FileAccess.open(Store.prefix+"3.json",FileAccess.WRITE);file.store_string("corrupted");file.close()
	check(Store.load_game(restored,"3"),"Corrupted primary save recovers from backup")

	s=fresh();quiet(s);s.credits=1000
	for i in range(8):s._add_drone("cargo",0)
	var started=Time.get_ticks_msec();run_for(s,180)
	var valid=true
	for m in s.modules:
		for key in m.stock:
			if int(m.stock[key])<0:valid=false
		for key in m.reserved:
			if int(m.reserved[key])<0 or int(m.reserved[key])>int(m.stock.get(key,0)):valid=false
	check(valid,"Long simulation never produces negative inventory or impossible reservations")
	print("SIMULATION_RUN_MS ",Time.get_ticks_msec()-started)
	print("RESULT ",passed," passed, ",failed," failed")
	quit(1 if failed>0 else 0)
