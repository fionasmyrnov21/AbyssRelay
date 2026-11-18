extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var passed=0
var failed=0
func check(value:bool,name:String):
	if value:passed+=1;print("PASS ",name)
	else:failed+=1;push_error("FAIL "+name)
func fresh():
	var s=Sim.new();s.new_game();s.auto_pause=false;s.next_event=1e12;return s
func _initialize():
	var s=fresh();var lab=s.first_module("lab",0)
	check(s.change_staff(int(lab.id),-1) and lab.staff==1,"Specialists can be reassigned")
	lab.sealed=true
	check(not s.change_staff(int(lab.id),1),"Sealed compartments reject crew transfers")
	lab.sealed=false;s.change_staff(int(lab.id),-1)
	var data=s.total_physical("data");s.tick(0.05)
	check(lab.reason=="crew","Unstaffed production explains its stop")
	check(s.placement_error("mine",Vector2i(-2,0),0)=="deposit","Mining requires a physical deposit")
	var mine=s.first_module("mine",0);var dep=s.deposit_at(Vector2i(mine.x,mine.y),0)
	dep.amount=2;s.tick(0.05)
	check(mine.reason=="depleted","Finite deposits stop extraction")
	var snap=s.snapshot();var copy=fresh()
	check(copy.restore(JSON.parse_string(JSON.stringify(snap))) and copy.deposits[0].amount==2,"Depletion survives save/load")
	var old=snap.duplicate(true);old.version=1;old.erase("deposits")
	check(copy.restore(old),"Development save v1 migrates to the current format")
	var broken=snap.duplicate(true);broken.modules[0].erase("oxygen")
	check(not copy.restore(broken),"Malformed entity snapshots are rejected before mutation")
	broken=snap.duplicate(true);broken.drones[0].pos=[]
	check(not copy.restore(broken),"Malformed drone positions are rejected")
	var legacy=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-v1.json"))
	copy=fresh();check(copy.restore(legacy),"Actual first Android build save migrates successfully")
	check(copy.first_module("lab",0).staff==2 and copy.start_research("hull_1"),"Migrated Android saves preserve a usable staffed laboratory")

	s=fresh();var drone=s.drones[0];drone.pos=[9.0,9.0];drone.protocol="wait";drone.task={"kind":"survey","finding":"find_0","elapsed":0.0};drone.state="survey"
	s._tick_drones(0.05)
	check(drone.state=="link_wait","Lost-link wait protocol preserves the assignment")
	s._add_module("relay",7,7,0);s.add_link(int(s.first_module("generator",0).id),int(s.modules.back().id));s.modules.back().powered=true;s._signal_emitters[0].append(s.modules.back())
	s._tick_drones(0.05)
	check(drone.state!="link_wait","Restoring coverage resumes the assignment")

	s=fresh();var wh=s.first_module("warehouse",0);wh.stock.alloy=12
	var before=s.total_physical("alloy")
	check(s.demolish(int(wh.id)),"Dismantling removes a module")
	check(s.total_physical("alloy")==before+7,"Dismantling returns stored cargo and exactly 50 percent of alloy cost")
	check(not s.demolish(int(s.first_module("core",0).id)),"Command core cannot be accidentally dismantled")

	s=fresh();var contract=s.db.contracts[1]
	check(not s.claim_contract(contract.id),"Repair contracts enforce the actual objective")
	s.statistics.repairs=1
	check(s.claim_contract(contract.id),"Repair contract rewards completed engineering work")

	s=fresh();s.researched=["hull_1","hull_2","hull_3","ocean_6"]
	for next in range(1,4):
		var previous=next-1;s.add_stock("alloy",200,previous);s.add_stock("parts",20,previous);s.add_stock("fuel",10,previous)
		for f in s.findings:
			if f.sector==previous:f.status="recovered"
		s._add_module("relay",-2,0,previous);s._tick_networks(0)
		check(s.open_sector(next),"Campaign gate opens depth %d"%next)
	for f in s.findings:
		if f.sector==3:f.status="recovered"
	s._add_module("beacon",-2,0,3);s.tick(0.05)
	check(s.completed,"Final observatory completes the campaign and keeps the world playable")

	s=fresh();s.sectors_open.append(1);s._bootstrap(1)
	check(not s.send_shipment(0,1,"alloy",10),"Inter-outpost cargo requires a working relay chain")
	var relay=s._add_module("relay",-2,0,0);s._tick_networks(0)
	before=s.total_physical("alloy")
	check(s.send_shipment(0,1,"alloy",10),"Prepared outposts can dispatch a physical cargo shipment")
	check(s.total_physical("alloy")==before and s.shipments.size()==1,"In-transit cargo remains in the conservation ledger")
	relay.enabled=false;s._tick_networks(0);var remaining=s.shipments[0].remaining;s._tick_shipments(50)
	check(s.shipments[0].remaining==remaining,"Relay failure pauses cargo instead of teleporting it")
	copy=fresh();check(copy.restore(JSON.parse_string(JSON.stringify(s.snapshot()))) and copy.shipments.size()==1,"In-transit cargo and destination reservations survive save/load")
	copy.first_module("relay",0).enabled=true;copy._tick_networks(0);copy._tick_shipments(50)
	check(copy.shipments.is_empty() and copy.first_module("core",1).stock.alloy==70,"Restored relay resumes and completes delivery")
	check(copy.total_physical("alloy")==before,"Delivery conserves cargo across stations")
	check(copy.first_module("core",1).incoming.alloy==0,"Arrival releases destination reservation")
	copy.first_module("core",1).stock.alloy=219
	check(not copy.send_shipment(0,1,"alloy",10),"A full destination rejects cargo before debit")

	s=fresh();s.rescue_used=true;s.first_module("core",0).hp=0;s.tick(0.05)
	check(s.failed and s.paused,"Loss of all command cores ends the expedition after rescue is exhausted")

	s=fresh();s.modules.clear();s.drones.clear()
	for x in range(-7,8):
		for y in range(-6,7):
			var kind="generator" if x%3==0 and y%3==0 else "warehouse"
			s._add_module(kind,x,y,0)
	for i in range(30):s._add_drone("cargo",0)
	s.add_stock("fuel",1000,0)
	var start=Time.get_ticks_usec()
	for i in range(200):s.tick(0.05)
	var average=float(Time.get_ticks_usec()-start)/200.0/1000.0
	check(s.modules.size()==195 and s.drones.size()==30,"Stress scene contains 195 modules and 30 drones")
	print("STRESS_MEAN_TICK_MS ",average)
	print("RESULT ",passed," passed, ",failed," failed")
	quit(1 if failed else 0)
