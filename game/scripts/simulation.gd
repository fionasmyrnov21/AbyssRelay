extends RefCounted

const Content = preload("res://scripts/content.gd")
const SAVE_VERSION = 3
const STEP = 0.05
const LIMIT = 10
var db: Dictionary
var modules: Array = []
var drones: Array = []
var links: Array = []
var findings: Array = []
var deposits: Array = []
var shipments: Array = []
var events: Array = []
var logbook: Array = []
var researched: Array = []
var claimed: Array = []
var sectors_open: Array = [0]
var research: Dictionary = {}
var sector = 0
var time = 0.0
var speed = 1
var paused = false
var credits = 180
var next_id = 1
var accumulator = 0.0
var next_event = 110.0
var next_autosave = 90.0
var tutorial = 0
var completed = false
var failed = false
var rescue_used = false
var statistics = {"delivered": 0, "built": 0, "repairs": 0, "scanned": 0}
var metrics: Dictionary = {}
var rng = RandomNumberGenerator.new()
var last_error = ""
var auto_pause = true
var needs_save = false
var _graph_signature = -1
var _power_groups: Array = []
var _air_groups: Array = []
var _visual_pairs: Array = []
var _signal_emitters: Dictionary = {}

func _init():
	db = Content.load_data()

func new_game():
	_graph_signature = -1
	modules.clear(); drones.clear(); links.clear(); events.clear(); logbook.clear()
	shipments.clear()
	researched.clear(); claimed.clear(); research.clear()
	findings = db.findings.duplicate(true)
	deposits = []
	for s in range(db.sectors.size()):
		for item in db.sectors[s].deposits:
			var deposit = item.duplicate(true); deposit.sector = s
			deposits.append(deposit)
	for f in findings:
		f.status = "unknown"
	sectors_open = [0]
	time = 0.0; speed = 1; paused = false; credits = 180; sector = 0
	next_id = 1; accumulator = 0.0; next_event = 110.0; next_autosave = 90.0
	tutorial = 0; completed = false; failed = false; rescue_used = false
	statistics = {"delivered": 0, "built": 0, "repairs": 0, "scanned": 0}
	rng.seed = 739184
	_bootstrap(0)
	_add_module("mine", 2, 0, 0)
	_add_module("refinery", 1, 1, 0)
	_add_module("lab", -1, -1, 0)
	message("Expedition deployed. Survey the signal and build a relay.")
	_tick_networks(0.0)

func _bootstrap(s: int):
	var core = _add_module("core", 0, 0, s)
	core.stock = {"alloy": 130 if s == 0 else 60, "ore": 20, "parts": 20 if s == 0 else 8, "fuel": 12 if s == 0 else 5, "data": 22 if s == 0 else 0, "quartz": 12, "samples": 0, "electronics": 0, "composite": 0}
	_add_module("generator", -1, 0, s)
	_add_module("oxygen", 0, -1, s)
	_add_module("warehouse", 1, 0, s)
	_add_module("dock", 0, 1, s)
	_add_module("battery", -1, 1, s)
	for kind in ["scout", "cargo", "engineer", "miner"]:
		_add_drone(kind, s)

func _add_module(kind: String, x: int, y: int, s: int, built: bool = true) -> Dictionary:
	var d = db.modules[kind]
	var m = {"id": next_id, "kind": kind, "x": x, "y": y, "sector": s, "built": built, "stock": {}, "reserved": {}, "incoming": {}, "hp": 100.0, "water": 0.0, "oxygen": 75.0, "battery": 5.0 if kind == "battery" else 0.0, "sealed": false, "priority": 0 if d.category == "life" else 1 if kind == "dock" else 2 if d.category == "infrastructure" else 3, "enabled": true, "powered": false, "connected": false, "signal": true, "leak": 0.0, "fault": 0.0, "progress": 0.0, "work": 0.0, "reason": "", "group": -1}
	next_id += 1
	m.staff = int(d.crew)
	m.orientation = 0
	if not built:
		m.oxygen = 0.0; m.battery = 0.0
	modules.append(m)
	return m

func _add_drone(kind: String, s: int):
	var dock = first_module("dock", s)
	var pos = [0.0, 1.0] if dock.is_empty() else [float(dock.x), float(dock.y)]
	drones.append({"id": next_id, "kind": kind, "sector": s, "pos": pos, "prev": pos.duplicate(), "battery": 100.0, "hp": 100.0, "task": {}, "cargo": {}, "path": [], "state": "idle", "progress": 0.0, "upgrades": [], "protocol": "return", "reserve": 22.0})
	next_id += 1

func module_by_id(id: int) -> Dictionary:
	for m in modules:
		if int(m.id) == id:
			return m
	return {}

func first_module(kind: String, s: int) -> Dictionary:
	for m in modules:
		if m.kind == kind and int(m.sector) == s and m.built:
			return m
	return {}

func at_cell(cell: Vector2i, s: int) -> Dictionary:
	for m in modules:
		if m.sector == s and m.x == cell.x and m.y == cell.y:
			return m
	return {}

func cell_blocked(cell: Vector2i, s: int) -> bool:
	if absi(cell.x) > LIMIT or absi(cell.y) > LIMIT:
		return true
	if absi(cell.x) <= 3 and absi(cell.y) <= 3:
		return false
	for f in findings:
		if f.sector == s and f.cell[0] == cell.x and f.cell[1] == cell.y:
			return false
	return posmod(cell.x * 37 + cell.y * 19 + s * 13, 31) == 0

func totals(s: int = -1) -> Dictionary:
	var result = {}
	for key in db.resources:
		result[key] = 0
	for m in modules:
		if m.built and (s < 0 or int(m.sector) == s):
			for key in m.stock:
				result[key] = int(result.get(key, 0)) + int(m.stock[key])
	return result

func total_physical(resource: String) -> int:
	var amount = 0
	for m in modules:
		amount += int(m.stock.get(resource, 0))
	for d in drones:
		amount += int(d.cargo.get(resource, 0))
	for shipment in shipments:
		if shipment.resource == resource:
			amount += int(shipment.amount)
	return amount

func _available(m: Dictionary, key: String) -> int:
	return maxi(0, int(m.stock.get(key, 0)) - int(m.reserved.get(key, 0)))

func _source(key: String, amount: int, s: int, except_id: int = -1) -> Dictionary:
	for m in modules:
		if m.built and m.enabled and m.sector == s and m.id != except_id and _available(m, key) >= amount:
			return m
	return {}

func can_pay(cost: Dictionary, s: int) -> bool:
	for key in cost:
		var available = 0
		for m in modules:
			if m.built and m.sector == s:
				available += _available(m, key)
		if available < int(cost[key]):
			return false
	return true

func pay(cost: Dictionary, s: int) -> bool:
	if not can_pay(cost, s):
		return false
	for key in cost:
		var remaining = int(cost[key])
		for m in modules:
			if m.built and m.sector == s:
				var count = mini(remaining, _available(m, key))
				m.stock[key] = int(m.stock.get(key, 0)) - count
				remaining -= count
	return true

func add_stock(resource: String, amount: int, s: int):
	var hub = first_module("core", s)
	if not hub.is_empty():
		hub.stock[resource] = int(hub.stock.get(resource, 0)) + amount

func unlocked(kind: String) -> bool:
	var key = str(db.modules[kind].unlock)
	if key.begins_with("life_"):
		key = key.replace("life_", "hull_")
	return key.is_empty() or key in researched

func depth_limit(kind: String) -> int:
	var bonus = 0
	for i in range(1, 7):
		if "hull_%d" % i in researched:
			bonus += 1200
	return int(db.modules[kind].depth) + bonus

func placement_error(kind: String, cell: Vector2i, s: int) -> String:
	if not db.modules.has(kind) or kind == "core":
		return "unknown"
	if not unlocked(kind):
		return "research"
	if not at_cell(cell, s).is_empty() or cell_blocked(cell, s):
		return "occupied"
	if kind == "mine" and deposit_at(cell, s).is_empty():
		return "deposit"
	if kind == "geothermal":
		var vent_present = false
		for vent in db.sectors[s].vents:
			if int(vent[0]) == cell.x and int(vent[1]) == cell.y:
				vent_present = true
		if not vent_present:
			return "vent"
	if kind == "tidal" and absi(cell.x) < 4 and absi(cell.y) < 4:
		return "current"
	if depth_limit(kind) < int(db.sectors[s].depth):
		return "pressure"
	var adjacent = false
	for m in modules:
		if m.sector == s and absi(int(m.x) - cell.x) + absi(int(m.y) - cell.y) == 1:
			adjacent = true
	if not adjacent:
		return "adjacent"
	if not can_pay(db.modules[kind].cost, s):
		return "resources"
	return ""

func deposit_at(cell: Vector2i, s: int) -> Dictionary:
	for deposit in deposits:
		if int(deposit.sector) == s and int(deposit.cell[0]) == cell.x and int(deposit.cell[1]) == cell.y:
			return deposit
	return {}

func place(kind: String, cell: Vector2i, s: int) -> Dictionary:
	last_error = placement_error(kind, cell, s)
	if not last_error.is_empty():
		return {}
	# Reserve through construction deliveries, never debit and duplicate stock.
	var site = _add_module(kind, cell.x, cell.y, s, false)
	for resource in db.modules[kind].cost:
		var remaining = int(db.modules[kind].cost[resource])
		for source in modules:
			if not source.built or source.sector != s:
				continue
			var count = mini(remaining, _available(source, resource))
			if count > 0:
				source.reserved[resource] = int(source.reserved.get(resource, 0)) + count
				if not site.has("supply"):
					site.supply = []
				var left = count
				while left > 0:
					var shipment = mini(10, left)
					site.supply.append({"source": source.id, "resource": resource, "amount": shipment, "assigned": false, "reserved": true})
					left -= shipment
				remaining -= count
	return site

func cancel_site(id: int) -> bool:
	var site = module_by_id(id)
	if site.is_empty() or site.built:
		return false
	for d in drones:
		if int(d.task.get("target", -1)) == id:
			cancel_drone(int(d.id))
	for item in site.get("supply", []):
		if not item.assigned and item.get("reserved", true):
			var source = module_by_id(int(item.source))
			if not source.is_empty():
				source.reserved[item.resource] = maxi(0, int(source.reserved.get(item.resource, 0)) - int(item.amount))
	# Delivered goods are returned to a real store before the site is removed.
	for key in site.stock:
		add_stock(key, int(site.stock[key]), int(site.sector))
	modules.erase(site)
	return true

func set_enabled(id: int):
	var m = module_by_id(id)
	if not m.is_empty():
		m.enabled = not m.enabled

func change_staff(id: int, delta: int) -> bool:
	var m = module_by_id(id)
	if m.is_empty() or not m.built or m.sealed:
		return false
	var free = 8
	for other in modules:
		if other.sector == m.sector and other.built:
			free += 6 if other.kind == "habitat" else 0
			free -= int(other.get("staff", 0))
	var next = int(m.get("staff", 0)) + delta
	if next < 0 or next > int(db.modules[m.kind].crew) or delta > free:
		return false
	m.staff = next
	return true

func demolish(id: int) -> bool:
	var m = module_by_id(id)
	if m.is_empty() or not m.built or m.kind == "core":
		return false
	for d in drones:
		if int(d.task.get("target", -1)) == id or int(d.task.get("source", -1)) == id:
			cancel_drone(int(d.id))
	# Unassigned site reservations referring to this store are rescheduled.
	for site in modules:
		for supply in site.get("supply", []):
			if supply.source == id and not supply.assigned:
				supply.reserved = false
	for key in m.stock:
		add_stock(key, int(m.stock[key]), int(m.sector))
	for key in db.modules[m.kind].cost:
		add_stock(key, int(db.modules[m.kind].cost[key]) / 2, int(m.sector))
	for link in links.duplicate():
		if link.a == id or link.b == id:
			links.erase(link)
	modules.erase(m)
	return true

func add_link(a: int, b: int) -> bool:
	var ma = module_by_id(a); var mb = module_by_id(b)
	if ma.is_empty() or mb.is_empty() or a == b or ma.sector != mb.sector:
		return false
	for l in links:
		if (l.a == a and l.b == b) or (l.b == a and l.a == b):
			return false
	if Vector2(ma.x, ma.y).distance_to(Vector2(mb.x, mb.y)) > 6.0:
		return false
	if not pay({"alloy": 2}, int(ma.sector)):
		return false
	links.append({"a": a, "b": b, "enabled": true})
	return true

func _neighbors(m: Dictionary, air: bool = false) -> Array:
	var result = []
	for other in modules:
		if not other.built or other.sector != m.sector or other.id == m.id:
			continue
		var connected = absi(int(m.x) - int(other.x)) + absi(int(m.y) - int(other.y)) == 1
		if not air and not connected:
			for l in links:
				if l.enabled and ((l.a == m.id and l.b == other.id) or (l.b == m.id and l.a == other.id)):
					connected = true
		if air and (m.sealed or other.sealed):
			connected = false
		if connected:
			result.append(other)
	return result

func _components(air: bool = false) -> Array:
	_ensure_graphs()
	return _air_groups if air else _power_groups

func visual_connections() -> Array:
	_ensure_graphs()
	return _visual_pairs

func _ensure_graphs():
	var topology = []
	for m in modules:
		topology.append([m.id, m.x, m.y, m.sector, m.built, m.sealed])
	for link in links:
		topology.append([link.a, link.b, link.enabled])
	var signature = hash(topology)
	if signature == _graph_signature:
		return
	_graph_signature = signature
	_power_groups = _compute_components(false)
	_air_groups = _compute_components(true)
	_visual_pairs = []
	for m in modules:
		for other in modules:
			if other.id > m.id and other.sector == m.sector and absi(int(m.x)-int(other.x)) + absi(int(m.y)-int(other.y)) == 1:
				_visual_pairs.append([m, other])

func _compute_components(air: bool = false) -> Array:
	var visited = {}; var result = []
	for m in modules:
		if not m.built or visited.has(m.id):
			continue
		var group = []; var queue = [m]
		visited[m.id] = true
		while not queue.is_empty():
			var current = queue.pop_front()
			group.append(current)
			for n in _neighbors(current, air):
				if not visited.has(n.id):
					visited[n.id] = true
					queue.append(n)
		result.append(group)
	return result

func _tick_networks(dt: float):
	metrics = {}
	_signal_emitters = {}
	var fuel_available = {}
	for m in modules:
		if m.built and _available(m, "fuel") > 0:
			fuel_available[int(m.sector)] = true
	for s in sectors_open:
		metrics[int(s)] = {"generation": 0.0, "demand": 0.0, "stored": 0.0, "oxygen": 0.0, "oxygen_rate": 0.0, "noise": 0.0, "signal": 100.0, "flood": 0.0, "crew": 0}
	for m in modules:
		m.powered = false; m.connected = false
	for group in _components():
		var generation = 0.0; var demand = 0.0; var batteries = []; var consumers = []
		var s = int(group[0].sector)
		for m in group:
			m.group = int(group[0].id)
			if not m.enabled or float(m.water) >= 95 or float(m.hp) <= 0:
				m.reason = "disabled" if not m.enabled else "flooded"
				continue
			var def = db.modules[m.kind]; var power = float(def.power)
			if m.fault > 0:
				m.reason = "fault"
			if power < 0 and float(m.fault) <= 0:
				var fuel_ok = m.kind != "generator" or fuel_available.get(s, false)
				if fuel_ok:
					var output = -power
					if m.kind == "tidal":
						output *= 0.65 + 0.35 * sin(time / 28.0)
					generation += output
					m.powered = true
					if m.kind == "generator":
						m.progress += dt
						if m.progress >= 200.0:
							pay({"fuel": 1}, s); m.progress -= 200.0
				else:
					m.reason = "fuel"
			elif power >= 0:
				demand += power; consumers.append(m)
			if m.kind == "battery":
				batteries.append(m)
		consumers.sort_custom(func(a, b): return a.priority < b.priority if a.priority != b.priority else a.id < b.id)
		var stored = 0.0
		for b in batteries:
			stored += float(b.battery)
		var available = generation + minf(60.0, stored * 3600.0 / maxf(dt, STEP))
		var used = 0.0
		for m in consumers:
			var need = maxf(0.0, float(db.modules[m.kind].power))
			m.connected = generation > 0 or not batteries.is_empty()
			if float(m.fault) > 0:
				m.reason = "fault"
			elif used + need <= available + 0.001:
				m.powered = true; m.reason = ""; used += need
			else:
				m.reason = "power" if m.connected else "disconnected"
		var change = (generation - used) * dt / 3600.0
		for b in batteries:
			if change > 0:
				var charge = minf(change, (10.0 if "energy_3" in researched else 5.0) - float(b.battery))
				b.battery += charge; change -= charge
			else:
				var draw = minf(-change, float(b.battery))
				b.battery -= draw; change += draw
		metrics[s].generation += generation; metrics[s].demand += demand; metrics[s].stored += stored
	for group in _components(true):
		var oxygen = 0.0; var capacity = 0.0; var rate = 0.0
		for m in group:
			capacity += 180.0 if m.kind == "oxygen_tank" else 100.0
			oxygen += float(m.oxygen)
			rate += 0.5 if m.kind == "oxygen" and m.powered else 0.0
			var occupants = int(m.get("staff", db.modules[m.kind].crew))
			if m.kind == "core":
				occupants += 8
			rate -= occupants * 0.025 + float(m.leak) * 0.45
		var next_o2 = clampf(oxygen + rate * dt, 0.0, capacity)
		for m in group:
			m.oxygen = next_o2 * (180.0 if m.kind == "oxygen_tank" else 100.0) / capacity
			metrics[int(m.sector)].oxygen += float(m.oxygen)
		metrics[int(group[0].sector)].oxygen_rate += rate
	for m in modules:
		if not m.built:
			continue
		var s = int(m.sector)
		metrics[s].crew += int(db.modules[m.kind].crew)
		if m.oxygen < 0.1 and int(m.get("staff", 0)) > 0:
			m.reason = "oxygen"
		m.fault = maxf(0.0, float(m.fault) - dt)
		m.water = clampf(float(m.water) + float(m.leak) * dt * 0.38, 0.0, 100.0)
		if m.leak > 0:
			m.hp = maxf(1.0, float(m.hp) - dt * float(m.leak) * 0.035)
		if m.water > 90 or m.oxygen <= 0.1 and (int(m.get("staff", 0)) > 0 or m.kind == "core"):
			m.hp = maxf(0.0, float(m.hp) - dt * 0.12)
		if m.kind == "pump" and m.powered:
			for n in _neighbors(m, true) + [m]:
				n.water = maxf(0.0, float(n.water) - dt * 1.8)
		metrics[s].flood = maxf(metrics[s].flood, float(m.water))
		if m.powered:
			if m.kind in ["core", "relay", "beacon"]:
				if not _signal_emitters.has(s):
					_signal_emitters[s] = []
				_signal_emitters[s].append(m)
			metrics[s].noise += 8.0 if m.kind == "mine" else 3.0 if db.modules[m.kind].category == "industry" else 0.3
			if m.kind == "silencer":
				metrics[s].noise -= 15.0
	for s in metrics:
		for drone in drones:
			if int(drone.sector) == s and not drone.path.is_empty():
				metrics[s].noise += 0.25 if "quiet" in drone.upgrades else 1.1
		metrics[s].noise = maxf(0.0, metrics[s].noise)
		metrics[s].signal = clampf(100.0 - maxf(0.0, float(metrics[s].noise) - 25.0) * 1.5, 15, 100)

func _recipe(kind: String) -> Dictionary:
	match kind:
		"mine": return {"input": {}, "output": {"ore": 3, "quartz": 1}, "seconds": 10.0}
		"refinery": return {"input": {"ore": 3}, "output": {"alloy": 4}, "seconds": 12.0}
		"chemical": return {"input": {"ore": 2}, "output": {"fuel": 2}, "seconds": 24.0}
		"electronics": return {"input": {"quartz": 2, "alloy": 1}, "output": {"electronics": 2}, "seconds": 18.0}
		"composite": return {"input": {"ore": 2, "quartz": 1}, "output": {"composite": 2}, "seconds": 20.0}
		"repair_shop": return {"input": {"alloy": 2}, "output": {"parts": 3}, "seconds": 20.0}
		"lab": return {"input": {"samples": 1}, "output": {"data": 10 if "ocean_1" in researched else 8}, "seconds": 18.0}
		"observatory": return {"input": {}, "output": {"data": 2}, "seconds": 22.0}
	return {}

func _production(dt: float):
	for m in modules:
		if not m.built or not m.powered or not m.enabled or m.oxygen < 1 and db.modules[m.kind].crew > 0:
			continue
		var required_crew = int(db.modules[m.kind].crew)
		if required_crew > 0 and int(m.get("staff", required_crew)) == 0:
			m.reason = "crew"
			continue
		var recipe = _recipe(m.kind)
		if recipe.is_empty():
			continue
		var deposit = deposit_at(Vector2i(m.x, m.y), int(m.sector)) if m.kind == "mine" else {}
		if m.kind == "mine" and (deposit.is_empty() or int(deposit.amount) < 3):
			m.reason = "depleted"
			continue
		if m.kind == "mine":
			var attended = false
			for drone in drones:
				if drone.kind == "miner" and drone.state == "working" and drone.path.is_empty() and int(drone.task.get("target",-1)) == int(m.id):
					attended = true
			if not attended:
				m.reason = "drone"
				continue
		var ready = true
		for key in recipe.input:
			if _available(m, key) < int(recipe.input[key]):
				ready = false; m.reason = "input"
		for key in recipe.output:
			if int(m.stock.get(key, 0)) + int(recipe.output[key]) > 40:
				ready = false; m.reason = "storage"
		if not ready:
			continue
		m.reason = ""
		var efficiency = 1.2 if "energy_5" in researched and m.kind == "chemical" else 1.0
		m.progress += dt * efficiency * (float(m.get("staff", required_crew)) / required_crew if required_crew > 0 else 1.0)
		if m.progress >= float(recipe.seconds):
			m.progress -= float(recipe.seconds)
			if m.kind == "mine":
				deposit.amount -= 3
			for key in recipe.input:
				m.stock[key] = int(m.stock.get(key, 0)) - int(recipe.input[key])
			for key in recipe.output:
				m.stock[key] = int(m.stock.get(key, 0)) + int(recipe.output[key])

func path_between(start: Vector2, end: Vector2, s: int) -> Array:
	var a = Vector2i(roundi(start.x), roundi(start.y)); var b = Vector2i(roundi(end.x), roundi(end.y))
	if a == b:
		return [[end.x, end.y]]
	var frontier = [a]; var previous = {a: a}; var found = false
	while not frontier.is_empty():
		var p = frontier.pop_front()
		if p == b:
			found = true; break
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var q = p + offset
			if not previous.has(q) and not cell_blocked(q, s):
				previous[q] = p; frontier.append(q)
	if not found:
		return []
	var result = []; var cursor = b
	while cursor != a:
		result.push_front([float(cursor.x), float(cursor.y)])
		cursor = previous[cursor]
	return result

func _go(d: Dictionary, cell: Vector2, state: String) -> bool:
	var path = path_between(Vector2(d.pos[0], d.pos[1]), cell, int(d.sector))
	if path.is_empty():
		d.state = "blocked"; d.progress = 0.0
		return false
	d.path = path; d.state = state
	return true

func _active_target(id: int, kind: String) -> bool:
	for d in drones:
		if int(d.task.get("target", -1)) == id and d.task.get("kind", "") == kind:
			return true
	return false

func _assign_transfer(d: Dictionary, source: Dictionary, target: Dictionary, resource: String, amount: int, reserved: bool = false) -> bool:
	var capacity = int(db.modules[target.kind].capacity) if target.built else int(db.modules[target.kind].cost.get(resource, 0))
	var free = capacity - int(target.stock.get(resource, 0)) - int(target.incoming.get(resource, 0))
	if amount <= 0 or amount > free:
		return false
	if not reserved:
		source.reserved[resource] = int(source.reserved.get(resource, 0)) + amount
	target.incoming[resource] = int(target.incoming.get(resource, 0)) + amount
	d.task = {"kind": "transfer", "source": source.id, "target": target.id, "resource": resource, "amount": amount, "picked": false, "elapsed": 0.0}
	return _go(d, Vector2(source.x, source.y), "pickup")

func _schedule(d: Dictionary):
	if d.battery < d.reserve:
		_return_home(d); return
	if not d.cargo.is_empty():
		_return_home(d); return
	var s = int(d.sector)
	if d.kind == "engineer":
		for m in modules:
			if m.sector == s and m.built and (m.leak > 0 or m.hp < 85 or m.fault > 0) and not _active_target(int(m.id), "repair"):
				var source = _source("parts", 2, s)
				if source.is_empty():
					continue
				source.reserved.parts = int(source.reserved.get("parts", 0)) + 2
				d.task = {"kind": "repair", "source": source.id, "target": m.id, "resource": "parts", "amount": 2, "picked": false, "elapsed": 0.0}
				_go(d, Vector2(source.x, source.y), "pickup"); return
		for m in modules:
			if m.sector != s or m.built or _active_target(int(m.id), "build"):
				continue
			var ready = true
			for key in db.modules[m.kind].cost:
				if int(m.stock.get(key, 0)) < int(db.modules[m.kind].cost[key]):
					ready = false
			if ready:
				d.task = {"kind": "build", "target": m.id, "elapsed": 0.0}
				_go(d, Vector2(m.x, m.y), "working"); return
	if d.kind == "miner":
		for m in modules:
			if m.sector == s and m.kind == "mine" and m.built and m.powered and not _active_target(int(m.id), "mine"):
				var deposit = deposit_at(Vector2i(m.x,m.y), s)
				if not deposit.is_empty() and int(deposit.amount) >= 3:
					d.task = {"kind":"mine","target":m.id,"elapsed":0.0}
					_go(d,Vector2(m.x,m.y),"working")
					return
	if d.kind == "cargo":
		for m in modules:
			if m.sector != s or m.built:
				continue
			for item in m.get("supply", []):
				if not item.assigned:
					var source = module_by_id(int(item.source))
					if not item.get("reserved", true):
						source = _source(str(item.resource), int(item.amount), s)
						if source.is_empty():
							continue
						source.reserved[item.resource] = int(source.reserved.get(item.resource, 0)) + int(item.amount)
						item.source = source.id; item.reserved = true
					if not source.is_empty():
						item.assigned = true
						_assign_transfer(d, source, m, str(item.resource), int(item.amount), true); return
		for target in modules:
			if target.sector != s or not target.built or not target.enabled:
				continue
			var recipe = _recipe(target.kind)
			for key in recipe.get("input", {}):
				if int(target.stock.get(key, 0)) + int(target.incoming.get(key, 0)) >= int(recipe.input[key]) * 3:
					continue
				var source = _source(key, 1, s, int(target.id))
				if not source.is_empty():
					var count = mini(8, _available(source, key))
					_assign_transfer(d, source, target, key, count); return
		var hub = first_module("core", s)
		for source in modules:
			if source.sector != s or not source.built or source.kind in ["core", "warehouse", "terminal"]:
				continue
			var recipe = _recipe(source.kind)
			for key in recipe.get("output", {}):
				if _available(source, key) >= 4:
					_assign_transfer(d, source, hub, key, mini(10, _available(source, key))); return
	if d.kind == "scout":
		# Passive scouting stops at coverage boundaries; explicit expeditions handle recovery.
		for f in findings:
			if f.sector == s and f.status == "unknown":
				f.status = "revealed"
				message("Sonar detected a site. Dispatch a scout.")
				break

func dispatch(find_id: String) -> bool:
	for f in findings:
		if f.id != find_id or f.status not in ["unknown", "revealed"]:
			continue
		for d in drones:
			if d.kind == "scout" and d.sector == f.sector and d.task.is_empty() and d.battery >= 35:
				d.task = {"kind": "survey", "finding": find_id, "elapsed": 0.0}
				f.status = "assigned"
				_go(d, Vector2(f.cell[0], f.cell[1]), "survey")
				return true
	return false

func _return_home(d: Dictionary):
	var dock = first_module("dock", int(d.sector))
	if dock.is_empty():
		d.state = "stranded"; return
	_go(d, Vector2(dock.x, dock.y), "return")

func cancel_drone(id: int):
	for d in drones:
		if d.id != id:
			continue
		var task = d.task
		if not task.is_empty():
			var source = module_by_id(int(task.get("source", -1)))
			var target = module_by_id(int(task.get("target", -1)))
			var resource = str(task.get("resource", "")); var amount = int(task.get("amount", 0))
			if not task.get("picked", false) and not source.is_empty():
				source.reserved[resource] = maxi(0, int(source.reserved.get(resource, 0)) - amount)
			if task.get("kind", "") == "transfer" and not target.is_empty():
				target.incoming[resource] = maxi(0, int(target.incoming.get(resource, 0)) - amount)
				if not target.built:
					for supply in target.get("supply", []):
						if supply.source == task.source and supply.resource == resource and supply.assigned:
							supply.assigned = false
							supply.reserved = false
							break
			if task.get("kind", "") == "survey":
				for f in findings:
					if f.id == task.finding:
						f.status = "revealed"
		d.task = {}; d.path = []
		_return_home(d)

func _tick_drones(dt: float):
	for d in drones:
		d.prev = d.pos.duplicate()
		var signal_quality = signal_at(Vector2(d.pos[0], d.pos[1]), int(d.sector))
		d.signal = signal_quality
		if d.state == "link_wait":
			if signal_quality > 0:
				d.state = d.get("resume_state", "idle")
			else:
				continue
		if signal_quality <= 0 and not d.task.is_empty() and d.state != "return":
			if d.protocol == "wait":
				d.resume_state = d.state; d.state = "link_wait"
				continue
			else:
				cancel_drone(int(d.id))
		if not d.task.is_empty():
			d.task.elapsed = float(d.task.get("elapsed", 0.0)) + dt
			if d.task.elapsed > 180:
				cancel_drone(int(d.id)); continue
		if not d.path.is_empty():
			var destination = Vector2(d.path[0][0], d.path[0][1]); var pos = Vector2(d.pos[0], d.pos[1])
			var move_speed = 0.9 if d.kind == "cargo" else 1.2
			if "auto_5" in researched:
				move_speed *= 1.15
			if "quiet" in d.upgrades:
				move_speed *= 0.8
			var moved = pos.move_toward(destination, dt * move_speed)
			d.pos = [moved.x, moved.y]; d.battery = maxf(0.0, float(d.battery) - dt * 0.15)
			if moved.distance_to(destination) < 0.001:
				d.path.pop_front()
			continue
		if d.state == "return":
			var dock = first_module("dock", int(d.sector))
			if not dock.is_empty() and dock.powered:
				for key in d.cargo:
					add_stock(key, int(d.cargo[key]), int(d.sector))
				var battery_capacity = 140.0 if "battery" in d.upgrades else 100.0
				d.cargo.clear(); d.battery = minf(battery_capacity, float(d.battery) + dt * 6.0)
				if d.battery >= battery_capacity * 0.98:
					d.state = "idle"; d.task = {}
			else:
				d.state = "waiting_dock"
		elif d.state == "waiting_dock":
			var dock = first_module("dock", int(d.sector))
			if not dock.is_empty() and dock.powered:
				d.state = "return"
		elif d.state == "blocked":
			d.progress += dt
			if d.progress > 3:
				cancel_drone(int(d.id))
		elif d.task.is_empty():
			d.state = "idle"
			d.schedule_wait = float(d.get("schedule_wait", 0.0)) - dt
			if d.schedule_wait <= 0:
				d.schedule_wait = 0.35
				_schedule(d)
		else:
			_execute_task(d, dt)

func _execute_task(d: Dictionary, dt: float):
	var t = d.task
	if d.state == "pickup":
		var source = module_by_id(int(t.source))
		if source.is_empty() or int(source.stock.get(t.resource, 0)) < int(t.amount):
			cancel_drone(int(d.id)); return
		source.stock[t.resource] = int(source.stock[t.resource]) - int(t.amount)
		source.reserved[t.resource] = maxi(0, int(source.reserved.get(t.resource, 0)) - int(t.amount))
		d.cargo[t.resource] = int(t.amount); t.picked = true
		var target = module_by_id(int(t.target))
		if target.is_empty():
			cancel_drone(int(d.id)); return
		_go(d, Vector2(target.x, target.y), "deliver" if t.kind == "transfer" else "working")
	elif d.state == "deliver":
		var target = module_by_id(int(t.target))
		if target.is_empty():
			cancel_drone(int(d.id)); return
		var amount = int(d.cargo.get(t.resource, 0))
		target.stock[t.resource] = int(target.stock.get(t.resource, 0)) + amount
		target.incoming[t.resource] = maxi(0, int(target.incoming.get(t.resource, 0)) - int(t.amount))
		d.cargo.clear(); d.task = {}; d.state = "idle"
		statistics.delivered += amount
	elif d.state == "working":
		var target = module_by_id(int(t.target))
		if target.is_empty():
			cancel_drone(int(d.id)); return
		d.progress += dt
		if t.kind == "mine":
			d.battery = maxf(0.0,float(d.battery)-dt*0.06)
			if d.battery < d.reserve:
				d.task = {}; d.progress = 0.0; _return_home(d)
		elif t.kind == "repair" and d.progress >= 7.0:
			target.leak = 0.0; target.hp = 100.0; target.fault = 0.0
			d.cargo.clear(); statistics.repairs += 1
			message("Engineer completed repairs.")
			d.task = {}; d.progress = 0.0; _return_home(d)
		elif t.kind == "build":
			target.work += dt
			if target.work >= float(db.modules[target.kind].build_time):
				for key in db.modules[target.kind].cost:
					target.stock[key] = int(target.stock.get(key, 0)) - int(db.modules[target.kind].cost[key])
				target.built = true; target.erase("supply")
				statistics.built += 1
				message("Module commissioned.")
				d.task = {}; d.progress = 0.0; _return_home(d)
	elif d.state == "survey":
		d.progress += dt
		if d.progress >= 8.0:
			for f in findings:
				if f.id == t.finding:
					f.status = "recovered"; d.cargo = {"data": int(f.data), "samples": int(f.samples) + (1 if "ocean_3" in researched else 0)}
					statistics.scanned += 1
					message(f.name_en + ": sample recovered.")
			d.progress = 0.0; d.task = {}; _return_home(d)

func start_research(id: String) -> bool:
	if not research.is_empty() or id in researched:
		return false
	for r in db.research:
		if r.id != id:
			continue
		for requirement in r.requires:
			if requirement not in researched:
				return false
		var lab = first_module("lab", sector)
		if lab.is_empty() or not lab.powered or not pay({"data": int(r.cost)}, sector):
			return false
		research = {"id": id, "progress": 0.0, "duration": float(r.duration), "sector": sector}
		return true
	return false

func _tick_research(dt: float):
	if research.is_empty():
		return
	var lab = first_module("lab", int(research.sector))
	if not lab.is_empty() and lab.powered and lab.oxygen > 1 and int(lab.get("staff", 0)) > 0:
		research.progress += dt
		if research.progress >= research.duration:
			researched.append(research.id)
			message("Research complete. New capabilities unlocked.")
			research = {}; needs_save = true

func claim_contract(id: String) -> bool:
	if id in claimed:
		return false
	for c in db.contracts:
		if c.id == id and contract_progress(c) >= int(c.target):
			if c.kind == "delivery" and not pay({c.resource: int(c.amount)}, sector):
				return false
			claimed.append(id); credits += int(c.credits); add_stock("data", int(c.data), sector)
			message("Contract fulfilled. Reward received.")
			return true
	return false

func contract_progress(c: Dictionary) -> int:
	match str(c.kind):
		"repair": return int(statistics.repairs)
		"survey": return int(statistics.scanned)
		"quiet": return int(statistics.get("quiet_time", 0.0))
		"uptime": return int(statistics.get("uptime", 0.0))
		"research": return researched.size()
		"relay":
			var count = 0
			for m in modules:
				if m.kind == "relay" and m.built and m.powered:
					count += 1
			return count
	var available = 0
	for m in modules:
		if m.built and m.sector == sector:
			available += _available(m, str(c.resource))
	return available

func sector_error(s: int) -> String:
	if s in sectors_open:
		return ""
	if s != sectors_open.size() or s >= db.sectors.size():
		return "previous"
	var count = 0
	for f in findings:
		if f.sector == s - 1 and f.status == "recovered":
			count += 1
	if count < 2:
		return "findings"
	var relay = first_module("relay", s - 1)
	if relay.is_empty() or not relay.powered:
		return "relay"
	if "hull_%d" % s not in researched:
		return "pressure"
	if credits < 60 or not can_pay({"alloy": 80, "parts": 8, "fuel": 5}, s - 1):
		return "resources"
	return ""

func open_sector(s: int) -> bool:
	last_error = sector_error(s)
	if not last_error.is_empty():
		return false
	if s not in sectors_open:
		pay({"alloy": 80, "parts": 8, "fuel": 5}, s - 1); credits -= 60
		sectors_open.append(s); _bootstrap(s)
		message("New research outpost deployed.")
	sector = s; needs_save = true
	return true

func buy_drone(kind: String) -> bool:
	if credits < 65 or not pay({"alloy": 15, "parts": 2}, sector):
		return false
	credits -= 65; _add_drone(kind, sector)
	return true

func route_error(source: int, target: int) -> String:
	if source not in sectors_open or target not in sectors_open or source == target:
		return "sector"
	for s in range(mini(source,target),maxi(source,target)):
		var relay = first_module("relay", s)
		if relay.is_empty() or not relay.powered:
			return "relay"
	for s in [source,target]:
		var dock = first_module("dock", s)
		if dock.is_empty() or not dock.powered:
			return "dock"
	return ""

func send_shipment(source: int, target: int, resource: String, amount: int) -> bool:
	if not db.resources.has(resource) or amount <= 0 or not route_error(source,target).is_empty():
		return false
	var hub = first_module("core",target)
	if int(hub.stock.get(resource,0)) + int(hub.incoming.get(resource,0)) + amount > int(db.modules.core.capacity):
		return false
	if not pay({resource:amount},source):
		return false
	hub.incoming[resource] = int(hub.incoming.get(resource,0)) + amount
	var duration = 30.0 + absf(float(db.sectors[source].depth)-float(db.sectors[target].depth))/100.0
	shipments.append({"id":next_id,"source":source,"target":target,"resource":resource,"amount":amount,"duration":duration,"remaining":duration,"reason":""})
	next_id += 1
	message("Cargo dispatched through the Relay network.")
	return true

func _tick_shipments(dt: float):
	for shipment in shipments.duplicate():
		shipment.reason = route_error(int(shipment.source),int(shipment.target))
		if not shipment.reason.is_empty():
			continue
		shipment.remaining -= dt
		if shipment.remaining <= 0:
			var hub = first_module("core",int(shipment.target))
			hub.incoming[shipment.resource] = maxi(0,int(hub.incoming.get(shipment.resource,0))-int(shipment.amount))
			add_stock(str(shipment.resource),int(shipment.amount),int(shipment.target))
			shipments.erase(shipment)
			message("Inter-outpost cargo delivered.")

func upgrade_drone(id: int, kind: String) -> bool:
	for d in drones:
		if d.id == id and kind not in d.upgrades and credits >= 35 and pay({"alloy": 8}, int(d.sector)):
			d.upgrades.append(kind); credits -= 35
			if kind == "battery":
				d.reserve = 15.0
			return true
	return false

func rescue() -> bool:
	if rescue_used:
		return false
	rescue_used = true; add_stock("parts", 8, sector); add_stock("fuel", 6, sector); add_stock("alloy", 25, sector)
	for core in modules:
		if core.kind == "core":
			core.hp = maxf(60.0,float(core.hp)); core.oxygen = maxf(50.0,float(core.oxygen)); core.water = 0.0; core.leak = 0.0
	message("Emergency supply delivered. Expedition reserve used.")
	return true

func trigger_event(kind: String = "leak"):
	if events.size() >= 2:
		return
	var options = []
	for m in modules:
		if m.built and m.sector == sector and m.kind != "core" and m.leak <= 0:
			options.append(m)
	if options.is_empty():
		return
	var templates = []
	for e in db.events:
		if e.kind == kind:
			templates.append(e)
	if templates.is_empty():
		return
	var template = templates[rng.randi_range(0, mini(templates.size() - 1, sector + 2))].duplicate(true)
	var target = options[rng.randi_range(0, options.size() - 1)]
	template.target = target.id; template.phase = "warning"; template.remaining = float(template.warning)
	events.append(template); speed = 1
	message("Warning: " + template.name_en)
	if auto_pause:
		paused = true

func signal_at(pos: Vector2, s: int) -> float:
	var quality = 0.0
	for m in _signal_emitters.get(s, []):
		if not m.powered:
			continue
		var radius = 7.0 - s * 0.2 if m.kind == "core" else 11.0
		if "relay_3" in researched:
			radius += 3.0
		var distance = pos.distance_to(Vector2(m.x, m.y))
		if distance <= radius:
			quality = maxf(quality, 100.0 - distance / radius * 65.0)
	var noise = float(metrics.get(s, {}).get("noise", 0.0))
	return maxf(0.0, quality - maxf(0.0, noise - 30.0) * (0.5 if "relay_5" in researched else 1.0))

func _tick_events(dt: float):
	for e in events.duplicate():
		e.remaining -= dt
		var target = module_by_id(int(e.target))
		if target.is_empty():
			events.erase(e); continue
		if e.phase == "warning" and e.remaining <= 0:
			e.phase = "active"; e.remaining = float(e.duration)
			match e.kind:
				"leak": target.leak = 1.2; target.hp = 75.0
				"power": target.fault = float(e.duration)
				"current": target.leak = 0.35
				"bio": target.fault = float(e.duration) * 0.6
			message("Incident: " + e.name_en)
		elif e.phase == "active" and ((e.kind in ["leak", "current"] and target.leak <= 0) or (e.kind in ["power", "bio"] and target.fault <= 0)):
			events.erase(e)
		elif e.phase == "active" and e.remaining <= -90:
			events.erase(e)
	if time >= next_event:
		var types = ["leak", "power", "current", "bio"]
		trigger_event(types[rng.randi_range(0, 3)])
		next_event = time + rng.randf_range(160.0, 240.0)

func message(en: String):
	logbook.push_front({"en": en, "time": time})
	if logbook.size() > 80:
		logbook.pop_back()

func advance(delta: float):
	if paused or failed:
		return
	accumulator += minf(delta, 0.25) * speed
	var steps = 0
	while accumulator + 0.0000001 >= STEP and steps < 20:
		tick(STEP); accumulator = maxf(0.0, accumulator - STEP); steps += 1
		if paused:
			break

func tick(dt: float):
	time += dt
	_tick_networks(dt)
	_production(dt)
	_tick_drones(dt)
	_tick_shipments(dt)
	_tick_research(dt)
	_tick_events(dt)
	var local_metrics = metrics.get(sector, {})
	if float(local_metrics.get("noise", 100.0)) <= 18.0:
		statistics.quiet_time = float(statistics.get("quiet_time", 0.0)) + dt
	else:
		statistics.quiet_time = 0.0
	if float(local_metrics.get("generation", 0.0)) >= float(local_metrics.get("demand", 0.0)) and events.is_empty():
		statistics.uptime = float(statistics.get("uptime", 0.0)) + dt
	else:
		statistics.uptime = 0.0
	if statistics.built >= 1:
		tutorial = maxi(tutorial, 1)
	if statistics.scanned >= 1:
		tutorial = maxi(tutorial, 2)
	if statistics.repairs >= 1:
		tutorial = maxi(tutorial, 3)
	if not completed and sectors_open.size() == 4:
		var beacon = first_module("beacon", 3)
		var recovered = 0
		for f in findings:
			if f.sector == 3 and f.status == "recovered":
				recovered += 1
		if not beacon.is_empty() and beacon.powered and recovered >= 3 and "ocean_6" in researched:
			completed = true; needs_save = true
			message("Signal decoded. Observatory network restored. Your expedition continues.")
	if time >= next_autosave:
		needs_save = true; next_autosave = time + 90.0
	var living_core = false
	for m in modules:
		if m.kind == "core" and m.hp > 0:
			living_core = true
	if not living_core and rescue_used and not failed:
		failed = true; paused = true; needs_save = true
		message("All command outposts lost. Expedition ended.")

func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "content_version": db.version, "modules": modules.duplicate(true), "drones": drones.duplicate(true), "links": links.duplicate(true), "findings": findings.duplicate(true), "deposits": deposits.duplicate(true), "shipments": shipments.duplicate(true), "events": events.duplicate(true), "logbook": logbook.duplicate(true), "researched": researched.duplicate(), "claimed": claimed.duplicate(), "research": research.duplicate(true), "sectors_open": sectors_open.duplicate(), "sector": sector, "time": time, "credits": credits, "next_id": next_id, "next_event": next_event, "rng": str(rng.state), "tutorial": tutorial, "completed": completed, "failed": failed, "rescue_used": rescue_used, "statistics": statistics.duplicate(true)}

func restore(data: Dictionary) -> bool:
	data = data.duplicate(true)
	if int(data.get("version", -1)) == 1:
		data.deposits = []
		for s in range(db.sectors.size()):
			for item in db.sectors[s].deposits:
				var deposit = item.duplicate(true); deposit.sector = s
				data.deposits.append(deposit)
		data.version = 2
	if int(data.get("version", -1)) == 2:
		data.shipments = []
		data.version = SAVE_VERSION
	if int(data.get("version", -1)) != SAVE_VERSION or int(data.get("content_version", -1)) != int(db.version):
		return false
	for key in ["modules", "drones", "links", "findings", "deposits", "shipments", "events", "logbook", "researched", "claimed", "sectors_open"]:
		if not data.get(key) is Array:
			return false
	if data.modules.is_empty() or data.sectors_open.is_empty():
		return false
	# JSON numbers are floats; normalize IDs before typed Array membership checks.
	data.sectors_open = data.sectors_open.map(func(value): return int(value))
	if not data.get("research") is Dictionary or not data.get("statistics") is Dictionary:
		return false
	# Old bilingual saves keep their English text and all gameplay state.
	for entry in data.logbook:
		entry.erase("ru")
	for entry in data.findings + data.events:
		for key in entry.keys():
			if str(key).ends_with("_ru"):
				entry.erase(key)
	# Validate before changing live state; reserve fields must remain nonnegative.
	var ids = {}
	for m in data.modules:
		if not m is Dictionary or not db.modules.has(m.get("kind", "")) or ids.has(int(m.get("id", -1))):
			return false
		m.staff = clampi(int(m.get("staff", db.modules[m.kind].crew)), 0, int(db.modules[m.kind].crew))
		m.orientation = int(m.get("orientation", 0))
		for key in ["id", "x", "y", "sector", "hp", "water", "oxygen", "battery", "priority", "leak", "fault", "progress", "work"]:
			if not m.get(key) is float and not m.get(key) is int:
				return false
		if int(m.sector) not in data.sectors_open or int(m.sector) < 0 or int(m.sector) >= db.sectors.size():
			return false
		for key in ["built", "enabled", "sealed", "powered", "connected"]:
			if not m.get(key) is bool:
				return false
		ids[int(m.id)] = true
		for key in ["stock", "reserved", "incoming"]:
			if not m.get(key) is Dictionary:
				return false
			for value in m[key].values():
				if not value is float and not value is int or float(value) < 0:
					return false
	for d in data.drones:
		if not d is Dictionary or d.get("kind", "") not in ["scout", "cargo", "engineer", "miner"]:
			return false
		for key in ["pos", "prev", "path", "upgrades"]:
			if not d.get(key) is Array:
				return false
		if d.pos.size() != 2 or d.prev.size() != 2 or not d.get("task") is Dictionary or not d.get("cargo") is Dictionary:
			return false
		for key in ["id", "sector", "battery", "hp", "progress", "reserve"]:
			if not d.get(key) is int and not d.get(key) is float:
				return false
		if int(d.sector) not in data.sectors_open:
			return false
	if int(data.get("sector", -1)) not in data.sectors_open:
		return false
	for key in ["modules", "drones", "links", "findings", "deposits", "shipments", "events", "logbook", "researched", "claimed", "sectors_open"]:
		set(key, data[key].duplicate(true))
	for key in ["sector", "credits", "next_id", "tutorial"]:
		set(key, int(data.get(key, 0)))
	for key in ["time", "next_event"]:
		set(key, float(data.get(key, 0)))
	research = data.get("research", {}).duplicate(true)
	statistics = data.get("statistics", {}).duplicate(true)
	completed = bool(data.get("completed", false)); rescue_used = bool(data.get("rescue_used", false))
	failed = bool(data.get("failed", false))
	rng.state = int(str(data.get("rng", "739184")))
	paused = true; speed = 1; accumulator = 0; next_autosave = time + 90
	_graph_signature = -1
	_tick_networks(0.0)
	return true
