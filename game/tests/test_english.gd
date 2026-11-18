extends SceneTree
const Main=preload("res://scripts/main.gd")
const Content=preload("res://scripts/content.gd")
const Sim=preload("res://scripts/simulation.gd")
var passed=0
var failed=0
var cyrillic=RegEx.create_from_string("[\\x{0400}-\\x{052f}]")
func check(condition:bool,description:String):
	if condition:passed+=1;print("PASS ",description)
	else:failed+=1;push_error("FAIL "+description)
func english_values(value) -> bool:
	if value is String:return cyrillic.search(value)==null
	if value is Dictionary:
		for key in value:
			if not english_values(value[key]):return false
	elif value is Array:
		for item in value:
			if not english_values(item):return false
	return true
func _initialize():
	check(not english_values(String.chr(0x0420)),"Language validator detects Cyrillic characters")
	check(english_values("PRESSURE / Power / Oxygen"),"Language validator accepts English text")
	var main=Main.new()
	main.settings_path="user://english_settings_test.json"
	var file=FileAccess.open(main.settings_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"lang":"ru","volume":0.35,"reduced_motion":true,"auto_pause":false,"text_scale":1.15}));file.close()
	TranslationServer.set_locale("ru")
	main._load_settings()
	check(main.settings.lang=="en" and TranslationServer.get_locale().begins_with("en"),"Legacy Russian settings and system locale resolve to English")
	var migrated=JSON.parse_string(FileAccess.get_file_as_string(main.settings_path))
	check(migrated.lang=="en","English preference is persisted for existing installations")
	check(is_equal_approx(main.settings.volume,0.35) and main.settings.reduced_motion and not main.settings.auto_pause and is_equal_approx(main.settings.text_scale,1.15),"Language migration preserves all other preferences")
	DirAccess.remove_absolute(main.settings_path)
	main._load_settings()
	check(main.settings.lang=="en","Clean installations default to English")
	main.free()
	var db=Content.load_data()
	check(english_values(db),"Every shipped content string is English")
	check(db.resources.alloy=="Alloy" and Content.title(db.modules.core)=="Command module","Resource and module names are English")
	var sim=Sim.new();sim.new_game()
	check(english_values(sim.logbook),"New expedition journal entries are English")
	sim.auto_pause=false;sim.trigger_event("leak")
	check(english_values(sim.events) and english_values(sim.logbook),"Incident titles and warnings are English")
	var legacy=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-v1.json"))
	var restored=Sim.new();restored.new_game()
	check(restored.restore(legacy) and english_values(restored.snapshot()),"Existing bilingual saves resume with English text only")
	check(restored.modules.size()==legacy.modules.size() and restored.credits==int(legacy.credits) and restored.statistics==legacy.statistics,"Language migration preserves gameplay progress")
	for path in ["main.gd","content.gd","simulation.gd","ocean_world.gd"]:
		check(cyrillic.search(FileAccess.get_file_as_string("res://scripts/"+path))==null,"Runtime source contains no Russian strings: "+path)
	print("RESULT ",passed," passed, ",failed," failed")
	quit(1 if failed else 0)
