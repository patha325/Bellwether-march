extends SceneTree

var failures: Array[String] = []
var model_response: Dictionary = {}
var model_completed := false
var tests_finished := false
var watchdog: Timer

func _initialize() -> void:
  watchdog = Timer.new()
  watchdog.one_shot = true
  watchdog.wait_time = 25.0
  watchdog.autostart = true
  watchdog.timeout.connect(_on_watchdog_timeout)
  root.add_child(watchdog)
  call_deferred("_run")

func _on_watchdog_timeout() -> void:
  if not tests_finished:
    failures.append("FAIL: runtime smoke tests timed out before completing")
    _finish()

func _run() -> void:
  var packed := load("res://main.tscn") as PackedScene
  _check("main scene loads", packed != null, true)
  if packed == null:
    _finish()
    return

  var game = packed.instantiate()
  root.add_child(game)
  await process_frame
  if not game.has_method("resolve_check"):
    _check("game script loads", false, true)
    _finish()
    return
  _check("game script and Ollama client initialize", game.ollama != null, true)
  _check("three-person party is created", game.party.size(), 3)
  _check("party begins with distinct 5e classes", [game.party[0]["class_name"], game.party[1]["class_name"], game.party[2]["class_name"]], ["Fighter", "Rogue", "Cleric"])
  _check("Fighter level-one hit points", game.party[0].max_hp, 12)
  _check("Rogue expertise is recorded", game.party[1].expertise.has("stealth"), true)
  _check("Cleric has two level-one spell slots", game.party[2].spell_slots, 2)

  var check_20_fail: Dictionary = game.resolve_check(20, 0, 21)
  var check_1_success: Dictionary = game.resolve_check(1, 10, 5)
  _check("natural 20 does not bypass ability-check DC", check_20_fail.success, false)
  _check("natural 1 does not bypass ability-check modifier", check_1_success.success, true)
  var save_20_fail: Dictionary = game.resolve_save(20, 0, 21)
  var save_1_success: Dictionary = game.resolve_save(1, 10, 5)
  _check("natural 20 does not bypass saving-throw DC", save_20_fail.success, false)
  _check("natural 1 does not bypass saving-throw modifier", save_1_success.success, true)
  var miss: Dictionary = game.resolve_attack(1, 20, 12)
  var critical: Dictionary = game.resolve_attack(20, -2, 30)
  _check("natural 1 always misses an attack", miss.hit, false)
  _check("natural 20 always hits and critically hits", critical.hit and critical.critical, true)

  _check("six-second movement is 30 feet for the Fighter", game._movement_limit(game.party[0]) * 5, 30)
  game.party[0].conditions.append("prone")
  _check("prone halves movement speed", game._movement_limit(game.party[0]) * 5, 15)
  game.party[0].conditions.clear()
  _check("advantage keeps the higher d20", game.resolve_attack_roll(4, 17, 2, 12, 1).roll, 17)
  _check("disadvantage keeps the lower d20", game.resolve_attack_roll(4, 17, 2, 12, -1).roll, 4)

  var endings := {"clue_found":false, "guard_trust":0}
  _check("story supports an unknown-culprit ending", game.ending_for(endings), "bell_silenced_unknown")
  endings.guard_trust = 1
  _check("story supports a guard-helped ending", game.ending_for(endings), "guard_helped")
  endings.clue_found = true
  _check("story supports a clue-only ending", game.ending_for(endings), "sexton_exposed")
  endings.guard_trust = 2
  _check("story supports the joint investigation ending", game.ending_for(endings), "sexton_exposed_with_guard")

  game._apply_story_consequence("persuade", true, "Warden Edda", game.party[0])
  _check("successful social action earns guard trust", game.story_flags.guard_trust, 1)
  _check("successful social action opens the gate", game.story_flags.gate_open, true)
  game._apply_story_consequence("investigate", true, "ossuary", game.party[1])
  _check("successful exploration action records a clue", game.story_flags.clue_found, true)

  # Use a deterministic initiative lineup and exercise one real player turn.
  game.test_roll_queue.append_array([19, 18, 17, 1, 2])
  game._start_combat()
  _check("initiative includes every living combatant", game.turn_order.size(), 5)
  _check("highest initiative is selected first", game._current_actor().side, "party")
  var active_id: String = game._current_actor().id
  var active_index: int = game._party_index_for_id(active_id)
  game.test_roll_queue.clear()
  var target_index := 0
  game.enemies[target_index].pos = game.party[active_index].pos + Vector2i(2, 0)
  game.enemies[target_index].hp = game.enemies[target_index].max_hp
  game.selected_pos = game.enemies[target_index].pos
  game.test_roll_queue.append_array([20, 4, 4])
  game._on_attack_pressed()
  _check("party attack spends its action", game._get_actor(active_id).action_used, true)
  _check("critical attack applies weapon damage", game.enemies[target_index].hp < game.enemies[target_index].max_hp, true)

  var client = game.ollama
  client.base_url = "http://127.0.0.1:11434"
  client.model = "test-model"
  client.response_received.connect(_on_model_response, CONNECT_ONE_SHOT)
  client.request_failed.connect(_on_model_failed, CONNECT_ONE_SHOT)
  client.ask_for_action("Convince the warden to open the gate", "Mock scene for integration test")
  await create_timer(5.0).timeout
  _check("Ollama chat endpoint returns structured action", model_completed, true)
  _check("structured action selects persuasion", model_response.get("action", ""), "persuade")
  _check("structured action includes a 5e skill", model_response.get("skill", ""), "persuasion")

  _finish()

func _on_model_response(payload: Dictionary) -> void:
  model_response = payload
  model_completed = true

func _on_model_failed(reason: String) -> void:
  model_response = {"failure":reason}
  model_completed = true

func _check(label: String, actual: Variant, expected: Variant) -> void:
  if actual != expected:
    failures.append("FAIL: %s (expected %s, got %s)" % [label, str(expected), str(actual)])
  else:
    print("PASS: %s" % label)

func _finish() -> void:
  tests_finished = true
  for child in root.get_children():
    child.free()
  if failures.is_empty():
    print("Runtime smoke tests passed.")
    call_deferred("_exit_after_cleanup", 0)
  else:
    for failure in failures:
      push_error(failure)
    call_deferred("_exit_after_cleanup", 1)

func _exit_after_cleanup(exit_code: int) -> void:
  await process_frame
  quit(exit_code)