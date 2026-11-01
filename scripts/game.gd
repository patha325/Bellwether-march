extends Control

const TILE := 68
const COLS := 8
const ROWS := 7
const START := Vector2i(1, 5)
const GUARD := Vector2i(3, 2)
const CULTIST_A := Vector2i(6, 1)
const CULTIST_B := Vector2i(6, 3)
const OLLAMA_CLIENT_SCRIPT := preload("res://scripts/ollama_client.gd")

var hero := {"name":"Mara Venn", "level":1, "hp":11, "max_hp":11, "ac":15, "prof":2, "str":14, "dex":14, "con":12, "int":10, "wis":13, "cha":12, "weapon":"longsword", "damage":"1d8+2"}
var guard := {"name":"Warden Edda", "attitude":"wary", "trust":0, "knows":"The abbey bell rang after midnight, though the tower has been sealed for years."}
var enemies := []
var hero_pos := START
var selected_pos := START
var turn := "exploration"
var round_no := 1
var action_used := false
var moved := false
var story_flags := {"gate_open":false, "clue_found":false, "guard_warned":false}
var event_log: Array[String] = []
var pending_action := {}
var ollama
var test_roll_queue: Array[int] = []

var board: Control
var log_label: RichTextLabel
var intent_input: LineEdit
var status_label: Label
var hp_label: Label
var model_input: LineEdit
var result_label: Label
var roll_button: Button
var move_button: Button
var attack_button: Button

func _ready() -> void:
  enemies = [
    {"name":"Ash-Cloaked Zealot", "hp":9, "max_hp":9, "ac":12, "pos":CULTIST_A},
    {"name":"Grave-Robber", "hp":7, "max_hp":7, "ac":12, "pos":CULTIST_B}
  ]
  _build_ui()
  ollama = OLLAMA_CLIENT_SCRIPT.new()
  add_child(ollama)
  ollama.response_received.connect(_on_action_proposed)
  ollama.request_failed.connect(_on_ollama_failed)
  _say("The plague has emptied the lanes around Bellwether's old abbey. Warden Edda blocks the way. Two figures move among the graves.")
  _refresh()

func _build_ui() -> void:
  var bg := ColorRect.new()
  bg.color = Color("171b1d")
  bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(bg)
  var root := HBoxContainer.new()
  root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  root.add_theme_constant_override("separation", 18)
  root.add_theme_constant_override("margin_left", 24)
  root.add_theme_constant_override("margin_right", 24)
  root.add_theme_constant_override("margin_top", 20)
  root.add_theme_constant_override("margin_bottom", 20)
  add_child(root)
  var left := VBoxContainer.new()
  left.custom_minimum_size = Vector2(600, 0)
  left.size_flags_vertical = Control.SIZE_EXPAND_FILL
  root.add_child(left)
  var title := Label.new()
  title.text = "BELLWETHER MARCH  ·  THE SEALED ABBEY"
  title.add_theme_font_size_override("font_size", 22)
  title.add_theme_color_override("font_color", Color("e8d8b4"))
  left.add_child(title)
  status_label = Label.new()
  status_label.add_theme_color_override("font_color", Color("b4c4b9"))
  left.add_child(status_label)
  board = Control.new()
  board.custom_minimum_size = Vector2(COLS * TILE, ROWS * TILE)
  board.mouse_filter = Control.MOUSE_FILTER_STOP
  board.draw.connect(_draw_board)
  board.gui_input.connect(_on_board_input)
  left.add_child(board)
  var controls := HBoxContainer.new()
  left.add_child(controls)
  move_button = _button("Move", _on_move_pressed)
  attack_button = _button("Attack", _on_attack_pressed)
  roll_button = _button("End turn", _on_end_turn)
  controls.add_child(move_button)
  controls.add_child(attack_button)
  controls.add_child(roll_button)
  hp_label = Label.new()
  hp_label.add_theme_color_override("font_color", Color("f0d8c0"))
  left.add_child(hp_label)
  var right := VBoxContainer.new()
  right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  right.size_flags_vertical = Control.SIZE_EXPAND_FILL
  root.add_child(right)
  var model_row := HBoxContainer.new()
  right.add_child(model_row)
  var model_caption := Label.new()
  model_caption.text = "Ollama model"
  model_row.add_child(model_caption)
  model_input = LineEdit.new()
  model_input.text = "qwen2.5:7b"
  model_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  model_row.add_child(model_input)
  var log_title := Label.new()
  log_title.text = "STORY & ROLLS"
  log_title.add_theme_color_override("font_color", Color("e8d8b4"))
  right.add_child(log_title)
  log_label = RichTextLabel.new()
  log_label.bbcode_enabled = true
  log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
  log_label.custom_minimum_size = Vector2(0, 300)
  right.add_child(log_label)
  var prompt_label := Label.new()
  prompt_label.text = "What do you try? Describe your intent."
  right.add_child(prompt_label)
  intent_input = LineEdit.new()
  intent_input.placeholder_text = "e.g. Ask Edda what she heard at the abbey..."
  intent_input.text_submitted.connect(_on_submit_intent)
  right.add_child(intent_input)
  var submit := _button("Try it", _on_submit_button)
  right.add_child(submit)
  result_label = Label.new()
  result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  result_label.add_theme_color_override("font_color", Color("d6c49c"))
  right.add_child(result_label)

func _button(text_value: String, callback: Callable) -> Button:
  var b := Button.new()
  b.text = text_value
  b.custom_minimum_size = Vector2(110, 38)
  b.pressed.connect(callback)
  return b

func _draw_board() -> void:
  for y in range(ROWS):
    for x in range(COLS):
      var rect := Rect2(x * TILE, y * TILE, TILE - 2, TILE - 2)
      var c := Color("353b3a") if (x + y) % 2 == 0 else Color("2e3433")
      if Vector2i(x, y) == GUARD: c = Color("554b3f")
      if Vector2i(x, y) in [CULTIST_A, CULTIST_B]: c = Color("493738")
      board.draw_rect(rect, c)
      if Vector2i(x, y) == selected_pos:
        board.draw_rect(rect, Color("d9bb77"), false, 3.0)
  _draw_token(hero_pos, Color("86b5c7"), "M")
  if not story_flags.gate_open:
    _draw_token(GUARD, Color("c7a56b"), "E")
  for enemy in enemies:
    if enemy.hp > 0:
      _draw_token(enemy.pos, Color("b86a66"), "Z")
  if story_flags.clue_found:
    board.draw_string(ThemeDB.fallback_font, Vector2(12, ROWS * TILE - 8), "Clue recorded", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("dfcf9f"))

func _draw_token(pos: Vector2i, color: Color, letter: String) -> void:
  var center := Vector2(pos.x * TILE + TILE / 2.0, pos.y * TILE + TILE / 2.0)
  board.draw_circle(center, 22, color)
  board.draw_string(ThemeDB.fallback_font, center + Vector2(-6, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("171b1d"))

func _on_board_input(event: InputEvent) -> void:
  if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
    selected_pos = Vector2i(int(event.position.x / TILE), int(event.position.y / TILE))
    board.queue_redraw()

func _on_submit_button() -> void:
  _on_submit_intent(intent_input.text)

func _on_submit_intent(text_value: String) -> void:
  var text := text_value.strip_edges()
  if text.is_empty(): return
  if turn == "combat" and action_used:
    _say("Your action is spent this turn. Move or end the turn.")
    return
  intent_input.clear()
  if not story_flags.gate_open and _near(hero_pos, GUARD, 3):
    _say("You: " + text)
    ollama.model = model_input.text.strip_edges()
    ollama.ask_for_action(text, _world_context())
  else:
    var proposal := _fallback_intent(text)
    _resolve_action(proposal)

func _fallback_intent(text: String) -> Dictionary:
  var low := text.to_lower()
  var action := "investigate"
  var ability := "wis"
  if "convince" in low or "persuade" in low or "ask" in low or "talk" in low: action = "persuade"; ability = "cha"
  elif "lie" in low or "pretend" in low or "deceive" in low: action = "deceive"; ability = "cha"
  elif "threat" in low or "intimidate" in low: action = "intimidate"; ability = "cha"
  elif "sneak" in low or "hide" in low: action = "stealth"; ability = "dex"
  elif "climb" in low or "push" in low or "force" in low: action = "athletics"; ability = "str"
  elif "heal" in low or "treat" in low: action = "medicine"; ability = "wis"
  elif "search" in low or "look" in low or "inspect" in low: action = "investigate"; ability = "int"
  return {"narration":"The scene waits on your choice. Ollama is offline, so a local intent guess will be used.", "action":action, "ability":ability, "target":"scene", "dc":12, "consequence_on_success":"You find a useful lead.", "consequence_on_failure":"You lose time and draw attention."}

func _on_action_proposed(payload: Dictionary) -> void:
  _resolve_action(payload)

func _on_ollama_failed(reason: String) -> void:
  _say("[color=#d2a27b]Ollama: %s Falling back to local intent handling.[/color]" % reason)
  var proposal := _fallback_intent("investigate")
  _resolve_action(proposal)

func _resolve_action(proposal: Dictionary) -> void:
  var action := str(proposal.get("action", "investigate"))
  var ability := str(proposal.get("ability", "wis"))
  var narration := str(proposal.get("narration", "You act, and the moment hangs in the balance."))
  if action == "invalid":
    _say(narration)
    return
  var stat_key := {"strength":"str", "dexterity":"dex", "constitution":"con", "intelligence":"int", "wisdom":"wis", "charisma":"cha"}.get(ability, ability)
  var mod := int(floor((int(hero.get(stat_key, 10)) - 10) / 2.0))
  var d20 := _roll_die(20)
  var total := d20 + mod + int(hero.prof)
  var dc := clampi(int(proposal.get("dc", 12)), 5, 25)
  var check_result := resolve_check(d20, mod + int(hero.prof), dc)
  var success: bool = check_result.success
  var result_text := "d20 %d + %d = %d vs DC %d: %s" % [d20, mod + int(hero.prof), total, dc, "SUCCESS" if success else "FAILURE"]
  _say("[color=#e8d8b4]%s[/color]\n%s" % [narration, result_text])
  _say("[color=#c0c9bb]%s[/color]" % str(proposal.get("consequence_on_success" if success else "consequence_on_failure", "The world reacts to your choice.")))
  _apply_story_consequence(action, success, str(proposal.get("target", "")))
  if turn == "combat": action_used = true
  _refresh()

func _apply_story_consequence(action: String, success: bool, target: String) -> void:
  if not success: return
  if action in ["persuade", "deceive", "intimidate"] and not story_flags.gate_open:
    story_flags.gate_open = true
    guard.attitude = "helpful"
    guard.trust += 1
    story_flags.guard_warned = true
    _say("Edda steps aside. 'The dead are walking toward the abbey. Do not let them ring that bell.'")
  elif action in ["investigate", "perception", "history", "arcana"]:
    story_flags.clue_found = true
    _say("You find a fresh boot print leading from the ossuary to the abbey's north door.")

func _on_move_pressed() -> void:
  if turn != "combat":
    turn = "combat"
    _say("Combat begins. Roll initiative: d20 + Dexterity modifier.")
    var initiative := _roll_die(20) + int(floor((int(hero.dex) - 10) / 2.0))
    _say("Mara's initiative: %d. The enemy moves after your turn." % initiative)
  if moved: return
  var distance := abs(selected_pos.x - hero_pos.x) + abs(selected_pos.y - hero_pos.y)
  if distance > 6:
    _say("That tile is beyond your 30-foot movement. Choose a closer tile.")
    return
  if _occupied(selected_pos):
    _say("A creature occupies that tile.")
    return
  hero_pos = selected_pos
  moved = true
  board.queue_redraw()
  _say("Mara moves up to 30 feet.")
  _enemy_turn_if_done()

func _on_attack_pressed() -> void:
  if turn != "combat":
    _say("There is no active combat. The story begins with Edda at the abbey gate.")
    return
  if action_used: _say("You have already taken an action this turn."); return
  var target_idx := -1
  for i in range(enemies.size()):
    if enemies[i].hp > 0 and _near(hero_pos, enemies[i].pos, 1): target_idx = i; break
  if target_idx < 0:
    _say("No enemy is within 5 feet. Move adjacent to a target first.")
    return
  var enemy: Dictionary = enemies[target_idx]
  var d20 := _roll_die(20)
  var attack_total := d20 + 4
  var hit := d20 == 20 or (d20 != 1 and attack_total >= int(enemy.ac))
  if hit:
    var damage := _roll_die(8) + 2
    if d20 == 20: damage += _roll_die(8)
    enemy.hp = max(0, int(enemy.hp) - damage)
    enemies[target_idx] = enemy
    _say("Mara attacks %s: d20 %d + 4 vs AC %d — HIT for %d damage. (%d/%d HP)" % [enemy.name, d20, enemy.ac, damage, enemy.hp, enemy.max_hp])
    if enemy.hp == 0: _say("%s falls among the graves." % enemy.name)
  else:
    _say("Mara attacks %s: d20 %d + 4 vs AC %d — MISS." % [enemy.name, d20, enemy.ac])
  action_used = true
  board.queue_redraw()
  _refresh()
  _enemy_turn_if_done()

func _on_end_turn() -> void:
  if turn == "exploration":
    _say("Choose an intent or step toward the abbey gate to begin the encounter.")
    return
  _enemy_turn()

func _enemy_turn_if_done() -> void:
  if action_used and moved: _enemy_turn()

func _enemy_turn() -> void:
  var alive := false
  for i in range(enemies.size()):
    var enemy: Dictionary = enemies[i]
    if enemy.hp <= 0: continue
    alive = true
    var dist := abs(enemy.pos.x - hero_pos.x) + abs(enemy.pos.y - hero_pos.y)
    if dist <= 1:
      var attack := _roll_die(20) + 3
      if attack >= int(hero.ac):
        var damage := _roll_die(6) + 1
        hero.hp = max(0, int(hero.hp) - damage)
        _say("%s strikes Mara: d20 + 3 = %d vs AC %d — HIT for %d damage." % [enemy.name, attack, hero.ac, damage])
      else:
        _say("%s lunges at Mara and misses." % enemy.name)
    else:
      var step := Vector2i(sign(hero_pos.x - enemy.pos.x), 0)
      if enemy.pos.x == hero_pos.x: step = Vector2i(0, sign(hero_pos.y - enemy.pos.y))
      var next_pos: Vector2i = enemy.pos + step
      if not _occupied(next_pos): enemy.pos = next_pos
      enemies[i] = enemy
  if not alive:
    _say("The graveyard falls quiet. The path to the abbey is open.")
    turn = "exploration"
    return
  if hero.hp <= 0:
    _say("Mara falls. The story ends here for now.")
    return
  round_no += 1
  action_used = false
  moved = false
  _say("Round %d — Mara's turn." % round_no)
  _refresh()

func _world_context() -> String:
  var known := "none"
  if story_flags.clue_found: known = "Fresh boot print leads from ossuary to north door"
  return "Scene: Bellwether March, plague-era graveyard outside sealed abbey. Target: Warden Edda, currently %s. She knows: %s. Player already knows: %s. Hero: level 1, proficient with longsword, Charisma +1, Wisdom +1, Intelligence +0. Combat: %s." % [guard.attitude, guard.knows, known, str(turn == "combat")]

func _near(a: Vector2i, b: Vector2i, d: int) -> bool:
  return abs(a.x - b.x) + abs(a.y - b.y) <= d

func _occupied(pos: Vector2i) -> bool:
  if pos == hero_pos or (not story_flags.gate_open and pos == GUARD): return true
  for e in enemies:
    if e.hp > 0 and e.pos == pos: return true
  return false

func _say(text: String) -> void:
  event_log.append(text)
  while event_log.size() > 18: event_log.pop_front()
  if is_instance_valid(log_label):
    log_label.clear()
    for line in event_log: log_label.append_text(line + "\n\n")
    log_label.scroll_to_line(log_label.get_line_count())

func _refresh() -> void:
  if is_instance_valid(status_label):
    status_label.text = "EXPLORATION" if turn == "exploration" else "COMBAT · ROUND %d · ACTION %s · MOVE %s" % [round_no, "SPENT" if action_used else "READY", "SPENT" if moved else "READY"]
    hp_label.text = "Mara Venn  ·  Level 1  ·  HP %d/%d  ·  AC %d  ·  Longsword +4 (1d8+2)" % [hero.hp, hero.max_hp, hero.ac]
    board.queue_redraw()

func _on_model_changed(_new_text: String) -> void:
  pass

func resolve_check(roll: int, bonus: int, dc: int) -> Dictionary:
  var total := roll + bonus
  return {"roll":roll, "bonus":bonus, "dc":dc, "total":total, "success":roll == 20 or (roll != 1 and total >= dc)}

func resolve_attack(roll: int, bonus: int, target_ac: int) -> Dictionary:
  var total := roll + bonus
  return {"roll":roll, "bonus":bonus, "ac":target_ac, "total":total, "hit":roll == 20 or (roll != 1 and total >= target_ac), "critical":roll == 20}

func _roll_die(sides: int) -> int:
  if not test_roll_queue.is_empty():
    return clampi(test_roll_queue.pop_front(), 1, sides)
  return randi_range(1, sides)
