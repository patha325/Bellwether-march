extends SceneTree

var failures: Array[String] = []
var model_response: Dictionary = {}
var model_completed := false
var tests_finished := false

func _initialize() -> void:
  call_deferred("_arm_watchdog")
  call_deferred("_run")

func _arm_watchdog() -> void:
  await create_timer(20.0).timeout
  if not tests_finished:
    push_error("Runtime smoke tests timed out before completing.")
    quit(2)

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
    _check("game script loaded", false, true)
    _finish()
    return
  if game.ollama == null:
    _check("game initialization completed", false, true)
    _finish()
    return

  var strong_success: Dictionary = game.resolve_check(15, 4, 15)
  _check("ability check succeeds at DC", strong_success.success, true)
  _check("check total is computed", strong_success.total, 19)

  var natural_twenty: Dictionary = game.resolve_check(20, -1, 25)
  _check("natural 20 succeeds", natural_twenty.success, true)
  var natural_one: Dictionary = game.resolve_check(1, 20, 5)
  _check("natural 1 fails", natural_one.success, false)

  var miss: Dictionary = game.resolve_attack(1, 10, 12)
  _check("natural 1 misses", miss.hit, false)
  var critical: Dictionary = game.resolve_attack(20, 4, 25)
  _check("natural 20 hits and is critical", critical.hit and critical.critical, true)

  game._apply_story_consequence("persuade", true, "Warden Edda")
  _check("successful social check opens gate", game.story_flags.gate_open, true)
  _check("successful social check changes attitude", game.guard.attitude, "helpful")
  game.story_flags.clue_found = false
  game._apply_story_consequence("investigate", false, "ossuary")
  _check("failed investigation does not set clue", game.story_flags.clue_found, false)
  game._apply_story_consequence("investigate", true, "ossuary")
  _check("investigation clue persists", game.story_flags.clue_found, true)

  game.turn = "combat"
  game.hero_pos = Vector2i(1, 5)
  game.selected_pos = Vector2i(2, 5)
  game.moved = false
  game.action_used = false
  game._on_move_pressed()
  _check("combat movement uses a turn movement", game.hero_pos, Vector2i(2, 5))
  _check("movement is marked spent", game.moved, true)

  game.hero_pos = Vector2i(1, 5)
  game.enemies[0].pos = Vector2i(2, 5)
  game.enemies[0].hp = 9
  game.action_used = false
  game.moved = false
  game.test_roll_queue.clear()
  game.test_roll_queue.append_array([20, 4, 4])
  game._on_attack_pressed()
  _check("critical attack applies damage", game.enemies[0].hp < 9, true)
  _check("attack spends action", game.action_used, true)

  var client = game.ollama
  client.base_url = "http://127.0.0.1:11434"
  client.model = "test-model"
  client.response_received.connect(_on_model_response, CONNECT_ONE_SHOT)
  client.request_failed.connect(_on_model_failed, CONNECT_ONE_SHOT)
  client.ask_for_action("Convince the warden to open the gate", "Mock scene for integration test")
  await create_timer(5.0).timeout
  _check("Ollama chat endpoint returns structured action", model_completed, true)
  _check("structured action selects persuasion", model_response.get("action", ""), "persuade")

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
  if failures.is_empty():
    print("Runtime smoke tests passed.")
    quit(0)
  else:
    for failure in failures:
      push_error(failure)
    quit(1)
