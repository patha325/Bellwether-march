extends Control

const TILE := 68
const COLS := 8
const ROWS := 7
const OLLAMA_CLIENT_SCRIPT := preload("res://scripts/ollama_client.gd")
const CLASS_NAMES := ["Fighter", "Rogue", "Cleric", "Wizard"]
const CLASS_KITS := {
  "Fighter": {"level":1, "max_hp":12, "ac":16, "str":16, "dex":12, "con":14, "int":10, "wis":10, "cha":10, "prof":2, "speed":6, "attack_name":"Longsword", "attack_mode":"weapon", "attack_ability":"str", "attack_range":1, "damage_sides":8, "damage_dice":1, "damage_bonus":3, "special_name":"Second Wind", "special_kind":"second_wind", "special_uses":1, "spell_slots":0, "skills":["athletics"]},
  "Rogue": {"level":1, "max_hp":9, "ac":14, "str":10, "dex":16, "con":12, "int":12, "wis":12, "cha":10, "prof":2, "speed":6, "attack_name":"Shortbow", "attack_mode":"weapon", "attack_ability":"dex", "attack_range":12, "damage_sides":6, "damage_dice":1, "damage_bonus":3, "special_name":"Hide", "special_kind":"hide", "special_uses":0, "spell_slots":0, "skills":["acrobatics", "investigation", "perception", "sleight_of_hand", "stealth"], "expertise":["stealth", "perception"]},
  "Cleric": {"level":1, "max_hp":10, "ac":16, "str":12, "dex":10, "con":14, "int":10, "wis":16, "cha":13, "prof":2, "speed":6, "attack_name":"Sacred Flame", "attack_mode":"save", "attack_ability":"wis", "save_ability":"dex", "attack_range":8, "damage_sides":8, "damage_dice":1, "damage_bonus":0, "special_name":"Healing Word", "special_kind":"healing_word", "special_uses":0, "spell_slots":2, "skills":["insight", "medicine", "religion"]},
  "Wizard": {"level":1, "max_hp":8, "ac":12, "str":8, "dex":14, "con":12, "int":16, "wis":12, "cha":10, "prof":2, "speed":6, "attack_name":"Fire Bolt", "attack_mode":"spell_attack", "attack_ability":"int", "attack_range":24, "damage_sides":10, "damage_dice":1, "damage_bonus":0, "special_name":"Burning Hands", "special_kind":"burning_hands", "special_uses":0, "spell_slots":2, "skills":["arcana", "history"]}
}

var party: Array[Dictionary] = [
  {"id":"mara", "name":"Mara Venn", "pos":Vector2i(1, 3), "class_name":"Fighter"},
  {"id":"talia", "name":"Talia Reed", "pos":Vector2i(1, 4), "class_name":"Rogue"},
  {"id":"ansel", "name":"Brother Ansel", "pos":Vector2i(1, 5), "class_name":"Cleric"}
]
var guard := {"name":"Warden Edda", "attitude":"wary", "trust":0, "knows":"The abbey bell rang after midnight, though the tower has been sealed for years."}
var enemies: Array[Dictionary] = []
var story_flags := {"gate_open":false, "clue_found":false, "guard_trust":0, "encounter_won":false}
var story_phase := "graveyard"
var story_ending := ""
var selected_party_index := 0
var selected_pos := Vector2i(1, 3)
var turn := "exploration"
var round_no := 1
var turn_order: Array[Dictionary] = []
var turn_index := -1
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
var class_selectors: Array[OptionButton] = []
var roster_buttons: Array[Button] = []
var move_button: Button
var attack_button: Button
var shove_button: Button
var special_button: Button
var end_turn_button: Button
var story_button: Button

func _ready() -> void:
  for i in range(party.size()):
    _set_class(i, str(party[i].get("class_name", "Fighter")), false)
  _reset_enemies()
  _build_ui()
  ollama = OLLAMA_CLIENT_SCRIPT.new()
  add_child(ollama)
  ollama.response_received.connect(_on_action_proposed)
  ollama.request_failed.connect(_on_ollama_failed)
  _say("Bellwether's graveyard is quiet except for the sealed abbey bell. Warden Edda blocks the gate; fresh earth lies open beside two disturbed graves.")
  _say("Choose the party's classes, question Edda, or investigate the graves before approaching the abbey.")
  _refresh()

func _reset_enemies() -> void:
  enemies = [
    {"id":"zealot", "name":"Ash-Cloaked Zealot", "hp":9, "max_hp":9, "ac":12, "pos":Vector2i(6, 1), "str":12, "dex":12, "con":12, "wis":10, "prof":2, "speed":6, "attack_bonus":3, "damage_sides":6, "damage_bonus":1, "conditions":[], "attack_kind":"melee"},
    {"id":"robber", "name":"Grave-Robber", "hp":7, "max_hp":7, "ac":12, "pos":Vector2i(6, 3), "str":12, "dex":14, "con":10, "wis":10, "prof":2, "speed":6, "attack_bonus":3, "damage_sides":6, "damage_bonus":1, "conditions":[], "attack_kind":"melee"}
  ]

func _set_class(member_index: int, role_name: String, update_ui := true) -> void:
  if member_index < 0 or member_index >= party.size() or not CLASS_KITS.has(role_name):
    return
  if story_phase != "graveyard" and update_ui:
    _say("The party's classes are locked once the encounter begins.")
    return
  var member: Dictionary = party[member_index]
  var identity := {"id":member.id, "name":member.name, "pos":member.pos, "class_name":role_name}
  var kit: Dictionary = CLASS_KITS[role_name].duplicate(true)
  for key in kit:
    identity[key] = kit[key]
  identity["hp"] = kit.max_hp
  identity["conditions"] = []
  identity["moved"] = false
  identity["action_used"] = false
  identity["bonus_used"] = false
  identity["hidden"] = false
  identity["sneak_attack_used"] = false
  party[member_index] = identity
  if is_instance_valid(board):
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
  status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  status_label.add_theme_color_override("font_color", Color("b4c4b9"))
  left.add_child(status_label)
  board = Control.new()
  board.custom_minimum_size = Vector2(COLS * TILE, ROWS * TILE)
  board.mouse_filter = Control.MOUSE_FILTER_STOP
  board.draw.connect(_draw_board)
  board.gui_input.connect(_on_board_input)
  left.add_child(board)
  var controls := HBoxContainer.new()
  controls.add_theme_constant_override("separation", 5)
  left.add_child(controls)
  move_button = _button("Move 30 ft", _on_move_pressed, 104)
  attack_button = _button("Attack", _on_attack_pressed, 82)
  shove_button = _button("Shove", _on_shove_pressed, 82)
  special_button = _button("Special", _on_special_pressed, 120)
  end_turn_button = _button("End turn", _on_end_turn, 90)
  for button in [move_button, attack_button, shove_button, special_button, end_turn_button]:
    controls.add_child(button)
  story_button = _button("Approach Abbey", _on_story_button, 170)
  left.add_child(story_button)
  hp_label = Label.new()
  hp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
  var roster_title := Label.new()
  roster_title.text = "PARTY CREATION · choose a class for each adventurer"
  roster_title.add_theme_color_override("font_color", Color("e8d8b4"))
  right.add_child(roster_title)
  for i in range(party.size()):
    var row := HBoxContainer.new()
    right.add_child(row)
    var select_member := _button(str(party[i].name), _select_member.bind(i), 150)
    roster_buttons.append(select_member)
    row.add_child(select_member)
    var option := OptionButton.new()
    option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for role in CLASS_NAMES:
      option.add_item(role)
    option.select(CLASS_NAMES.find(str(party[i].get("class_name", "Fighter"))))
    option.item_selected.connect(_on_class_selected.bind(i))
    class_selectors.append(option)
    row.add_child(option)
  var legend := Label.new()
  legend.text = "Blue tiles: movement · Gold outline: selected tile · Red ring: attack range"
  legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  legend.add_theme_color_override("font_color", Color("aeb8ae"))
  right.add_child(legend)
  var log_title := Label.new()
  log_title.text = "STORY, TURNS & ROLLS"
  log_title.add_theme_color_override("font_color", Color("e8d8b4"))
  right.add_child(log_title)
  log_label = RichTextLabel.new()
  log_label.bbcode_enabled = true
  log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
  log_label.custom_minimum_size = Vector2(0, 270)
  right.add_child(log_label)
  var prompt_label := Label.new()
  prompt_label.text = "Describe an action or conversation intent."
  right.add_child(prompt_label)
  intent_input = LineEdit.new()
  intent_input.placeholder_text = "e.g. Convince Edda to let us pass; inspect the boot prints..."
  intent_input.text_submitted.connect(_on_submit_intent)
  right.add_child(intent_input)
  var submit := _button("Try it", _on_submit_button, 110)
  right.add_child(submit)
  result_label = Label.new()
  result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  result_label.add_theme_color_override("font_color", Color("d6c49c"))
  right.add_child(result_label)

func _button(text_value: String, callback: Callable, width := 110) -> Button:
  var button := Button.new()
  button.text = text_value
  button.custom_minimum_size = Vector2(width, 38)
  button.pressed.connect(callback)
  return button

func _on_class_selected(option_index: int, member_index: int) -> void:
  if option_index >= 0 and option_index < CLASS_NAMES.size():
    _set_class(member_index, CLASS_NAMES[option_index])

func _select_member(member_index: int) -> void:
  if member_index < 0 or member_index >= party.size():
    return
  if turn == "combat":
    _say("Only the character whose name is at the top of the initiative turn may act.")
    return
  selected_party_index = member_index
  selected_pos = party[member_index].pos
  _refresh()

func _draw_board() -> void:
  var active := _current_actor()
  var in_combat := story_phase == "combat" and not active.is_empty() and str(active.get("side", "")) == "party"
  var mover: Dictionary = _get_actor(str(active.get("id", ""))) if in_combat else party[selected_party_index]
  for y in range(ROWS):
    for x in range(COLS):
      var tile := Vector2i(x, y)
      var rect := Rect2(x * TILE, y * TILE, TILE - 2, TILE - 2)
      var color := Color("353b3a") if (x + y) % 2 == 0 else Color("2e3433")
      if tile == Vector2i(3, 2) and story_phase == "graveyard":
        color = Color("554b3f")
      if in_combat and not bool(mover.get("moved", false)) and _tile_distance(tile, mover.pos) <= _movement_limit(mover) and not _occupied(tile, str(mover.id)):
        color = Color("31535a")
      board.draw_rect(rect, color)
      if in_combat and int(mover.get("attack_range", 1)) >= _tile_distance(tile, mover.pos) and _tile_has_enemy(tile):
        board.draw_rect(rect, Color("8c4240"), false, 3.0)
      if tile == selected_pos:
        board.draw_rect(rect, Color("d9bb77"), false, 3.0)
  if story_phase == "graveyard":
    _draw_token(Vector2i(3, 2), Color("c7a56b"), "E", 0, 1)
  for member in party:
    var token_color := Color("86b5c7") if str(member.id) != str(mover.get("id", "")) else Color("b1d6e2")
    _draw_token(member.pos, token_color, str(member.name).substr(0, 1), int(member.hp), int(member.max_hp))
  if story_phase == "combat" or story_phase == "abbey":
    for enemy in enemies:
      if int(enemy.hp) > 0:
        _draw_token(enemy.pos, Color("b86a66"), str(enemy.name).substr(0, 1), int(enemy.hp), int(enemy.max_hp))
  if story_flags.clue_found:
    board.draw_string(ThemeDB.fallback_font, Vector2(10, ROWS * TILE - 7), "CLUE: tracks lead to the north door", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("dfcf9f"))

func _draw_token(pos: Vector2i, color: Color, letter: String, hp := 0, max_hp := 1) -> void:
  var center := Vector2(pos.x * TILE + TILE / 2.0, pos.y * TILE + TILE / 2.0)
  board.draw_circle(center, 22, color)
  board.draw_string(ThemeDB.fallback_font, center + Vector2(-6, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("171b1d"))
  if hp > 0:
    var bar := Rect2(center.x - 18, center.y - 29, 36, 4)
    board.draw_rect(bar, Color("1c2020"))
    board.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(hp) / maxf(1.0, float(max_hp)), bar.size.y)), Color("9ec27c"))

func _on_board_input(event: InputEvent) -> void:
  if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
    var tile := Vector2i(int(event.position.x / TILE), int(event.position.y / TILE))
    if tile.x < 0 or tile.x >= COLS or tile.y < 0 or tile.y >= ROWS:
      return
    selected_pos = tile
    board.queue_redraw()

func _on_submit_button() -> void:
  _on_submit_intent(intent_input.text)

func _on_submit_intent(text_value: String) -> void:
  var text := text_value.strip_edges()
  if text.is_empty():
    return
  if story_phase == "combat" and (not _is_party_turn() or bool(_active_party_actor().get("action_used", false))):
    _say("Only the active party member may take an unused action.")
    return
  intent_input.clear()
  var actor := _active_party_actor()
  _say("%s: %s" % [actor.get("name", "The party"), text])
  pending_action = {"intent":text, "actor_id":actor.get("id", "")}
  ollama.model = model_input.text.strip_edges()
  if ollama.model.is_empty():
    ollama.model = "qwen2.5:7b"
  ollama.ask_for_action(text, _world_context())

func _fallback_intent(text: String) -> Dictionary:
  var low := text.to_lower()
  var action := "investigate"
  var ability := "wisdom"
  var skill := "perception"
  if "persuade" in low or "convince" in low or "talk" in low or "ask" in low:
    action = "persuade"; ability = "charisma"; skill = "persuasion"
  elif "lie" in low or "pretend" in low or "deceive" in low:
    action = "deceive"; ability = "charisma"; skill = "deception"
  elif "threat" in low or "intimidate" in low:
    action = "intimidate"; ability = "charisma"; skill = "intimidation"
  elif "sneak" in low or "hide" in low:
    action = "stealth"; ability = "dexterity"; skill = "stealth"
  elif "climb" in low or "push" in low or "force" in low:
    action = "athletics"; ability = "strength"; skill = "athletics"
  elif "heal" in low or "treat" in low:
    action = "medicine"; ability = "wisdom"; skill = "medicine"
  elif "search" in low or "look" in low or "inspect" in low or "track" in low or "clue" in low:
    action = "investigate"; ability = "intelligence"; skill = "investigation"
  return {"narration":"The scene responds to your approach.", "action":action, "ability":ability, "skill":skill, "target":"scene", "dc":12, "consequence_on_success":"You gain a useful lead.", "consequence_on_failure":"You lose time and draw attention."}

func _on_action_proposed(payload: Dictionary) -> void:
  if str(pending_action.get("actor_id", "")) != str(_active_party_actor().get("id", "")):
    _say("That response arrived after the active character changed; the action was discarded.")
    return
  _resolve_action(payload)

func _on_ollama_failed(reason: String) -> void:
  _say("[color=#d2a27b]Ollama unavailable: %s Using local intent handling.[/color]" % reason)
  _resolve_action(_fallback_intent(str(pending_action.get("intent", "investigate"))))

func _resolve_action(proposal: Dictionary) -> void:
  var actor := _active_party_actor()
  var action := str(proposal.get("action", "investigate"))
  if action == "invalid":
    _say(str(proposal.get("narration", "The conversation continues.")))
    pending_action.clear()
    return
  if story_phase == "combat" and bool(actor.get("action_used", false)):
    _say("%s has already used an action this turn." % actor.get("name", "The character"))
    pending_action.clear()
    return
  var ability_name := str(proposal.get("ability", "wisdom")).to_lower()
  var ability_key := {"strength":"str", "dexterity":"dex", "constitution":"con", "intelligence":"int", "wisdom":"wis", "charisma":"cha"}.get(ability_name, ability_name)
  var skill := str(proposal.get("skill", _skill_for_action(action))).to_lower()
  var bonus := _ability_modifier(int(actor.get(ability_key, 10)))
  if skill in actor.get("skills", []):
    bonus += int(actor.prof) * (2 if skill in actor.get("expertise", []) else 1)
  var roll := _roll_die(20)
  var dc := clampi(int(proposal.get("dc", 12)), 5, 25)
  var check: Dictionary = resolve_check(roll, bonus, dc)
  var succeeded: bool = check.success
  var narration := str(proposal.get("narration", "You act, and the moment hangs in the balance."))
  _say("[color=#e8d8b4]%s[/color]\n%s: d20 %d + %d = %d vs DC %d — %s" % [narration, skill.capitalize(), roll, bonus, check.total, dc, "SUCCESS" if succeeded else "FAILURE"])
  var consequence_key := "consequence_on_success" if succeeded else "consequence_on_failure"
  _say("[color=#c0c9bb]%s[/color]" % str(proposal.get(consequence_key, "The world reacts to your choice.")))
  _apply_story_consequence(action, succeeded, str(proposal.get("target", "")), actor)
  if story_phase == "combat":
    actor.action_used = true
    _store_actor(actor)
  pending_action.clear()
  _refresh()

func _skill_for_action(action: String) -> String:
  return {"persuade":"persuasion", "deceive":"deception", "intimidate":"intimidation", "investigate":"investigation", "stealth":"stealth", "athletics":"athletics", "insight":"insight", "medicine":"medicine", "survival":"survival", "history":"history", "arcana":"arcana", "perception":"perception"}.get(action, action)

func _apply_story_consequence(action: String, succeeded: bool, target: String, actor := {}) -> void:
  if not succeeded:
    if story_phase == "graveyard" and action in ["persuade", "deceive", "intimidate"]:
      guard.attitude = "suspicious"
      _say("Edda tightens her grip on the gate key.")
    return
  if story_phase == "graveyard" and action in ["persuade", "deceive", "intimidate"]:
    guard.attitude = "helpful"
    guard.trust = int(guard.trust) + 1
    story_flags.guard_trust = int(guard.trust)
    story_flags.gate_open = true
    _say("Edda steps aside. 'The dead are walking toward the abbey. Find who rang that bell.'")
  elif action in ["investigate", "perception", "history", "arcana", "survival"]:
    story_flags.clue_found = true
    if story_phase == "graveyard":
      _say("You find a fresh boot print leading from the ossuary to the abbey's north door.")
    else:
      _say("The tracks match the keeper's iron-soled boots; the bell was rung from inside the abbey.")
  elif action == "medicine" and not actor.is_empty():
    var healed: Dictionary = actor
    healed.hp = mini(int(healed.max_hp), int(healed.hp) + 1)
    _store_actor(healed)
    _say("%s binds a wound and recovers 1 hit point." % healed.name)

func _on_move_pressed() -> void:
  var actor := _active_party_actor()
  if story_phase == "combat" and (not _is_party_turn() or bool(actor.get("moved", false))):
    _say("This character has already moved, or it is not the party's turn.")
    return
  var distance := _tile_distance(selected_pos, actor.pos)
  if distance > _movement_limit(actor):
    _say("That destination exceeds this character's remaining speed.")
    return
  if _occupied(selected_pos, str(actor.id)):
    _say("A creature occupies that tile.")
    return
  actor.pos = selected_pos
  if story_phase == "combat":
    actor.moved = true
    if "prone" in actor.conditions:
      actor.conditions.erase("prone")
      _say("%s stands, spending half their movement." % actor.name)
  _store_actor(actor)
  _say("%s moves %d feet." % [actor.name, distance * 5])
  _refresh()

func _on_attack_pressed() -> void:
  if story_phase != "combat" or not _is_party_turn():
    _say("There is no active party combat turn.")
    return
  var actor := _active_party_actor()
  if actor.action_used:
    _say("%s has already used an action this turn." % actor.name)
    return
  var enemy_index := _enemy_index_at(selected_pos)
  if enemy_index < 0:
    _say("Select a visible enemy on the map first.")
    return
  var target: Dictionary = enemies[enemy_index]
  var distance := _tile_distance(actor.pos, target.pos)
  var attack_range := int(actor.attack_range)
  if distance > attack_range:
    _say("%s is outside %s range." % [target.name, actor.attack_name])
    return
  if str(actor.attack_mode) == "save":
    _use_sacred_flame(actor, enemy_index)
    return
  var advantage := _attack_advantage(actor, target, distance)
  var roll_a := _roll_die(20)
  var roll_b := _roll_die(20) if advantage != 0 else roll_a
  var attack: Dictionary = resolve_attack_roll(roll_a, roll_b, _attack_bonus(actor), int(target.ac), advantage)
  var damage := 0
  if attack.hit:
    damage = _roll_damage(actor)
    if attack.critical:
      damage += _roll_damage(actor, false)
    if str(actor["class_name"]) == "Rogue" and not actor.sneak_attack_used and _ally_adjacent_to_enemy(str(actor.id), target):
      damage += _roll_die(6)
      actor.sneak_attack_used = true
      _say("Sneak Attack adds 1d6 damage.")
    target.hp = maxi(0, int(target.hp) - damage)
    enemies[enemy_index] = target
    _say("%s uses %s: %s vs AC %d — HIT for %d %s (%d/%d HP)." % [actor.name, actor.attack_name, _attack_roll_text(attack), target.ac, damage, actor.get("damage_type", "weapon"), target.hp, target.max_hp])
    if target.hp == 0:
      _say("%s falls among the graves." % target.name)
  else:
    _say("%s uses %s: %s vs AC %d — MISS." % [actor.name, actor.attack_name, _attack_roll_text(attack), target.ac])
  actor.action_used = true
  actor.hidden = false
  _store_actor(actor)
  if _alive_enemy_count() == 0:
    _finish_combat()
  else:
    _refresh()

func _use_sacred_flame(actor: Dictionary, enemy_index: int) -> void:
  var target: Dictionary = enemies[enemy_index]
  var save_roll := _roll_die(20)
  var save_bonus := _ability_modifier(int(target.get("dex", 10)))
  var dc := 8 + int(actor.prof) + _ability_modifier(int(actor.get("wis", 10)))
  var save: Dictionary = resolve_save(save_roll, save_bonus, dc)
  actor.action_used = true
  _store_actor(actor)
  if save.success:
    _say("%s casts Sacred Flame. %s succeeds on a Dexterity save (d20 %d + %d vs DC %d); no damage." % [actor.name, target.name, save_roll, save_bonus, dc])
  else:
    var damage := _roll_die(8)
    target.hp = maxi(0, int(target.hp) - damage)
    enemies[enemy_index] = target
    _say("Sacred Flame: %s fails the Dexterity save and takes %d radiant damage." % [target.name, damage])
  if _alive_enemy_count() == 0:
    _finish_combat()
  else:
    _refresh()

func _on_shove_pressed() -> void:
  if story_phase != "combat" or not _is_party_turn():
    _say("Shove is available on an active party combat turn.")
    return
  var actor := _active_party_actor()
  if actor.action_used:
    _say("The action is already spent.")
    return
  var enemy_index := _enemy_index_at(selected_pos)
  if enemy_index < 0 or _tile_distance(actor.pos, enemies[enemy_index].pos) > 1:
    _say("Choose an enemy within 5 feet to shove.")
    return
  var target: Dictionary = enemies[enemy_index]
  var attack_roll := _roll_die(20)
  var attack_bonus := _ability_modifier(int(actor.str)) + int(actor.prof) if "athletics" in actor.get("skills", []) else _ability_modifier(int(actor.str))
  var defender_ability := maxi(int(target.get("str", 10)), int(target.get("dex", 10)))
  var defense_roll := _roll_die(20)
  var contest: Dictionary = resolve_contest(attack_roll, attack_bonus, defense_roll, _ability_modifier(defender_ability))
  actor.action_used = true
  _store_actor(actor)
  if contest.attacker_wins:
    if not ("prone" in target.conditions): target.conditions.append("prone")
    var direction := Vector2i(sign(target.pos.x - actor.pos.x), sign(target.pos.y - actor.pos.y))
    var pushed_pos: Vector2i = target.pos + direction
    if _tile_distance(target.pos, actor.pos) == 1 and _inside_map(pushed_pos) and not _occupied(pushed_pos, str(target.id)):
      target.pos = pushed_pos
    enemies[enemy_index] = target
    _say("Shove succeeds (%d vs %d): %s is knocked prone." % [contest.attacker_total, contest.defender_total, target.name])
  else:
    _say("Shove fails (%d vs %d); %s holds their footing." % [contest.attacker_total, contest.defender_total, target.name])
  _refresh()

func _on_special_pressed() -> void:
  if story_phase != "combat" or not _is_party_turn():
    _say("Class features are available during the active character's turn.")
    return
  var actor := _active_party_actor()
  var kind := str(actor.get("special_kind", ""))
  if kind == "second_wind":
    if actor.action_used or actor.bonus_used or int(actor.special_uses) <= 0:
      _say("Second Wind is unavailable; it needs an unspent bonus action and a remaining use.")
      return
    var healing := _roll_die(10) + int(actor.level)
    var old_hp := int(actor.hp)
    actor.hp = mini(int(actor.max_hp), old_hp + healing)
    actor.special_uses = int(actor.special_uses) - 1
    actor.bonus_used = true
    _store_actor(actor)
    _say("Second Wind restores %d HP to %s." % [int(actor.hp) - old_hp, actor.name])
  elif kind == "healing_word":
    _use_healing_word(actor)
  elif kind == "burning_hands":
    _use_burning_hands(actor)
  elif kind == "hide":
    _use_hide(actor)
  else:
    _say("This class has no available special feature.")
  _refresh()

func _use_healing_word(actor: Dictionary) -> void:
  if actor.bonus_used or int(actor.spell_slots) <= 0:
    _say("Healing Word needs an unused bonus action and a spell slot.")
    return
  var target_index := _party_index_at(selected_pos)
  if target_index < 0 or _tile_distance(actor.pos, party[target_index].pos) > 6:
    _say("Select a party member within 30 feet for Healing Word.")
    return
  var target: Dictionary = party[target_index]
  var old_hp := int(target.hp)
  var healing := _roll_die(4) + _ability_modifier(int(actor.wis))
  target.hp = mini(int(target.max_hp), old_hp + healing)
  party[target_index] = target
  actor.bonus_used = true
  actor.spell_slots = int(actor.spell_slots) - 1
  _store_actor(actor)
  _say("Healing Word restores %d HP to %s; %d cleric spell slot(s) remain." % [int(target.hp) - old_hp, target.name, actor.spell_slots])

func _use_burning_hands(actor: Dictionary) -> void:
  if actor.action_used or int(actor.spell_slots) <= 0:
    _say("Burning Hands needs an unused action and a spell slot.")
    return
  var direction := Vector2i(sign(selected_pos.x - actor.pos.x), sign(selected_pos.y - actor.pos.y))
  if direction == Vector2i.ZERO:
    _say("Select a direction on the map for the 15-foot cone.")
    return
  var hits := 0
  for i in range(enemies.size()):
    var target: Dictionary = enemies[i]
    if int(target.hp) <= 0:
      continue
    if _in_burning_hands_cone(actor.pos, target.pos, direction):
      hits += 1
      var dc := 8 + int(actor.prof) + _ability_modifier(int(actor.int))
      var save_roll := _roll_die(20)
      var save_bonus := _ability_modifier(int(target.get("dex", 10)))
      var save: Dictionary = resolve_save(save_roll, save_bonus, dc)
      var damage := _roll_die(6) + _roll_die(6) + _roll_die(6)
      if save.success: damage = floori(damage / 2.0)
      target.hp = maxi(0, int(target.hp) - damage)
      enemies[i] = target
      _say("%s's Dexterity save %s (d20 %d + %d vs DC %d); Burning Hands deals %d fire damage." % [target.name, "succeeds" if save.success else "fails", save_roll, save_bonus, dc, damage])
  if hits == 0:
    _say("No enemies are caught in the cone; no action or spell slot is spent.")
    return
  actor.action_used = true
  actor.spell_slots = int(actor.spell_slots) - 1
  _store_actor(actor)
  _say("Burning Hands spent one spell slot; %d remain." % actor.spell_slots)
  if _alive_enemy_count() == 0: _finish_combat()

func _use_hide(actor: Dictionary) -> void:
  if actor.action_used:
    _say("Hide uses an action, which is already spent.")
    return
  var roll := _roll_die(20)
  var bonus := _ability_modifier(int(actor.dex)) + int(actor.prof) * (2 if "stealth" in actor.get("expertise", []) else 1)
  var check: Dictionary = resolve_check(roll, bonus, 12)
  actor.action_used = true
  actor.hidden = check.success
  _store_actor(actor)
  _say("Hide: Dexterity (Stealth) d20 %d + %d vs DC 12 — %s." % [roll, bonus, "hidden; next attack has advantage" if check.success else "you remain visible"])

func _in_burning_hands_cone(origin: Vector2i, target: Vector2i, direction: Vector2i) -> bool:
  var delta: Vector2i = target - origin
  var forward := delta.x * direction.x + delta.y * direction.y
  var side := abs(delta.x * direction.y - delta.y * direction.x)
  return forward >= 1 and forward <= 3 and side <= forward / 2

func _on_end_turn() -> void:
  if story_phase != "combat" or not _is_party_turn():
    return
  var actor := _active_party_actor()
  _say("%s ends their turn." % actor.name)
  _advance_to_next_actor()

func _on_story_button() -> void:
  if story_phase == "graveyard":
    _start_combat()
  elif story_phase == "abbey":
    _resolve_abbey()
  elif story_phase == "defeat":
    _retry_encounter()

func _start_combat() -> void:
  if story_phase != "graveyard":
    return
  story_phase = "combat"
  turn = "combat"
  round_no = 1
  turn_order.clear()
  for member in party:
    member.action_used = false
    member.moved = false
    member.bonus_used = false
    member.sneak_attack_used = false
    var initiative := _roll_die(20) + _ability_modifier(int(member.dex))
    turn_order.append({"id":member.id, "side":"party", "initiative":initiative})
  for enemy in enemies:
    var initiative := _roll_die(20) + _ability_modifier(int(enemy.dex))
    turn_order.append({"id":enemy.id, "side":"enemy", "initiative":initiative})
  turn_order.sort_custom(_initiative_before)
  _say("The zealot and grave-robber lunge from the graves. Initiative order: %s." % _initiative_summary())
  turn_index = -1
  _advance_to_next_actor()

func _initiative_before(a: Dictionary, b: Dictionary) -> bool:
  if int(a.initiative) == int(b.initiative):
    return str(a.side) == "party" and str(b.side) != "party"
  return int(a.initiative) > int(b.initiative)

func _initiative_summary() -> String:
  var names: Array[String] = []
  for entry in turn_order:
    names.append("%s (%d)" % [_get_actor(str(entry.id)).get("name", entry.id), entry.initiative])
  return ", ".join(names)

func _advance_to_next_actor() -> void:
  if story_phase != "combat" or turn_order.is_empty():
    return
  var checked := 0
  while checked <= turn_order.size():
    turn_index += 1
    if turn_index >= turn_order.size():
      turn_index = 0
      round_no += 1
      _reset_round_actions()
    var entry: Dictionary = turn_order[turn_index]
    var actor := _get_actor(str(entry.id))
    if actor.is_empty() or int(actor.get("hp", 0)) <= 0:
      checked += 1
      continue
    if str(entry.side) == "enemy":
      _run_enemy_turn(str(entry.id))
      if story_phase != "combat":
        return
      checked += 1
      continue
    selected_party_index = _party_index_for_id(str(actor.id))
    selected_pos = actor.pos
    _say("Round %d — %s's turn. Move %d ft; one action and one bonus action are available." % [round_no, actor.name, _movement_limit(actor) * 5])
    _refresh()
    return
  if _alive_enemy_count() == 0: _finish_combat()

func _reset_round_actions() -> void:
  for member in party:
    member.action_used = false
    member.moved = false
    member.bonus_used = false
    member.sneak_attack_used = false
  for enemy in enemies:
    enemy.action_used = false
    enemy.moved = false

func _run_enemy_turn(enemy_id: String) -> void:
  var enemy := _get_actor(enemy_id)
  if enemy.is_empty() or int(enemy.hp) <= 0:
    return
  var target := _choose_enemy_target(enemy)
  if target.is_empty():
    story_phase = "defeat"
    _say("The party has fallen. Retry the encounter or return to the graveyard.")
    _refresh()
    return
  var speed := int(enemy.speed)
  if "prone" in enemy.conditions:
    speed = int(floor(speed / 2.0))
    enemy.conditions.erase("prone")
    _say("%s stands, spending half its movement." % enemy.name)
  var steps := 0
  while _tile_distance(enemy.pos, target.pos) > 1 and steps < speed:
    var next_pos := _next_step_toward(enemy.pos, target.pos)
    if not _inside_map(next_pos) or _occupied(next_pos, enemy_id):
      break
    enemy.pos = next_pos
    steps += 1
  _store_actor(enemy)
  target = _get_actor(str(target.id))
  if _tile_distance(enemy.pos, target.pos) <= 1:
    var advantage := 0
    if "prone" in enemy.conditions or "poisoned" in enemy.conditions: advantage -= 1
    if "prone" in target.conditions: advantage += 1
    var first := _roll_die(20)
    var second := _roll_die(20) if advantage != 0 else first
    var attack: Dictionary = resolve_attack_roll(first, second, int(enemy.attack_bonus), int(target.ac), advantage)
    if attack.hit:
      var damage := _roll_die(int(enemy.damage_sides)) + int(enemy.damage_bonus)
      target.hp = maxi(0, int(target.hp) - damage)
      _store_actor(target)
      _say("%s attacks %s: %s vs AC %d — HIT for %d damage." % [enemy.name, target.name, _attack_roll_text(attack), target.ac, damage])
      if str(enemy.id) == "zealot" and int(target.hp) > 0:
        var save_roll := _roll_die(20)
        var con_bonus := _ability_modifier(int(target.con))
        var save: Dictionary = resolve_save(save_roll, con_bonus, 11)
        if not save.success and not ("poisoned" in target.conditions):
          target.conditions.append("poisoned")
          _store_actor(target)
          _say("The plague-blade poisons %s; attacks and ability checks are at disadvantage." % target.name)
    else:
      _say("%s attacks %s: %s vs AC %d — MISS." % [enemy.name, target.name, _attack_roll_text(attack), target.ac])
  if _alive_party_count() == 0:
    story_phase = "defeat"
    turn = "defeat"
    _say("The party is down. Retry the graveyard encounter.")
    _refresh()

func _choose_enemy_target(enemy: Dictionary) -> Dictionary:
  var best: Dictionary = {}
  var best_score := 1_000_000
  for member in party:
    if int(member.hp) <= 0:
      continue
    var score := _tile_distance(enemy.pos, member.pos) * 20 + int(member.hp)
    if "prone" in member.conditions: score -= 2
    if score < best_score:
      best_score = score
      best = member
  return best

func _next_step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
  var dx := sign(to.x - from.x)
  var dy := sign(to.y - from.y)
  if abs(to.x - from.x) >= abs(to.y - from.y) and dx != 0:
    return from + Vector2i(dx, 0)
  if dy != 0:
    return from + Vector2i(0, dy)
  return from

func _finish_combat() -> void:
  if story_phase != "combat":
    return
  story_phase = "abbey"
  turn = "exploration"
  story_flags.encounter_won = true
  _say("The graveyard falls quiet. The abbey's north door stands open; the tracks and Edda's testimony may reveal who rang the bell.")
  if story_flags.clue_found:
    _say("The boot prints continue through the north doorway.")
  _refresh()

func _resolve_abbey() -> void:
  if story_phase != "abbey":
    return
  story_ending = ending_for(story_flags)
  story_phase = "complete"
  turn = "complete"
  var endings := {
    "sexton_exposed_with_guard":"Edda recognizes the tracks. Together, you expose the abbey sexton and silence the bell before the plague spreads.",
    "sexton_exposed":"The boot prints identify the sexton's route. You silence the bell, though the town watch must pursue the culprit without Edda's help.",
    "guard_helped":"Edda guides you through the service passage. The bell is silenced, but the sexton's identity remains unknown.",
    "bell_silenced_unknown":"You force the bell quiet. The graveyard is safe for now, but whoever called the dead has escaped unseen."
  }
  result_label.text = endings[story_ending]
  _say(endings[story_ending])
  _refresh()

func ending_for(flags: Dictionary) -> String:
  var has_clue := bool(flags.get("clue_found", false))
  var has_trust := int(flags.get("guard_trust", 0)) > 0
  if has_clue and has_trust: return "sexton_exposed_with_guard"
  if has_clue: return "sexton_exposed"
  if has_trust: return "guard_helped"
  return "bell_silenced_unknown"

func _retry_encounter() -> void:
  story_phase = "graveyard"
  turn = "exploration"
  round_no = 1
  story_ending = ""
  _reset_enemies()
  for i in range(party.size()):
    party[i].hp = party[i].max_hp
    party[i].conditions = []
    party[i].pos = Vector2i(1, 3 + i)
    party[i].spell_slots = CLASS_KITS[party[i]["class_name"]].get("spell_slots", 0)
  selected_party_index = 0
  selected_pos = party[0].pos
  _say("The party regroups in the graveyard. The encounter is reset; story clues and Edda's trust remain.")
  _refresh()

func _world_context() -> String:
  var known := "no boot-print clue"
  if story_flags.clue_found: known = "fresh boot prints lead from the ossuary to the abbey north door"
  var place := "graveyard outside the sealed abbey" if story_phase == "graveyard" else "inside the abbey by its bell chamber"
  var actor := _active_party_actor()
  return "Setting: Bellwether March, plague-era medieval fantasy. Scene: %s. Target: Warden Edda, currently %s, trust %d; she knows: %s. Party character: %s, level %d %s; abilities STR %d DEX %d CON %d INT %d WIS %d CHA %d. Party knows: %s. Combat active: %s. Interpret only the player's intended action; suggest an ability and skill check with DC 5–25. Do not claim the roll succeeded." % [place, guard.attitude, guard.trust, guard.knows, actor.name, actor.level, actor["class_name"], actor.str, actor.dex, actor.con, actor.int, actor.wis, actor.cha, known, str(story_phase == "combat")]

func _active_party_actor() -> Dictionary:
  if story_phase == "combat":
    var current := _current_actor()
    if str(current.get("side", "")) == "party":
      return _get_actor(str(current.get("id", "")))
  return party[selected_party_index] if selected_party_index >= 0 and selected_party_index < party.size() else {}

func _is_party_turn() -> bool:
  return story_phase == "combat" and str(_current_actor().get("side", "")) == "party"

func _current_actor() -> Dictionary:
  if turn_index < 0 or turn_index >= turn_order.size():
    return {}
  return turn_order[turn_index]

func _get_actor(actor_id: String) -> Dictionary:
  for member in party:
    if str(member.id) == actor_id: return member
  for enemy in enemies:
    if str(enemy.id) == actor_id: return enemy
  return {}

func _store_actor(actor: Dictionary) -> void:
  for i in range(party.size()):
    if str(party[i].id) == str(actor.get("id", "")):
      party[i] = actor
      return
  for i in range(enemies.size()):
    if str(enemies[i].id) == str(actor.get("id", "")):
      enemies[i] = actor
      return

func _party_index_for_id(actor_id: String) -> int:
  for i in range(party.size()):
    if str(party[i].id) == actor_id: return i
  return 0

func _party_index_at(pos: Vector2i) -> int:
  for i in range(party.size()):
    if party[i].pos == pos and int(party[i].hp) > 0: return i
  return -1

func _enemy_index_at(pos: Vector2i) -> int:
  for i in range(enemies.size()):
    if enemies[i].pos == pos and int(enemies[i].hp) > 0: return i
  return -1

func _tile_has_enemy(pos: Vector2i) -> bool:
  return _enemy_index_at(pos) >= 0

func _occupied(pos: Vector2i, except_id := "") -> bool:
  if not _inside_map(pos): return true
  if story_phase == "graveyard" and not story_flags.gate_open and pos == Vector2i(3, 2): return true
  for member in party:
    if int(member.hp) > 0 and str(member.id) != except_id and member.pos == pos: return true
  for enemy in enemies:
    if int(enemy.hp) > 0 and str(enemy.id) != except_id and enemy.pos == pos: return true
  return false

func _inside_map(pos: Vector2i) -> bool:
  return pos.x >= 0 and pos.x < COLS and pos.y >= 0 and pos.y < ROWS

func _tile_distance(a: Vector2i, b: Vector2i) -> int:
  return abs(a.x - b.x) + abs(a.y - b.y)

func _movement_limit(actor: Dictionary) -> int:
  var speed := int(actor.get("speed", 6))
  return int(floor(speed / 2.0)) if "prone" in actor.get("conditions", []) else speed

func _attack_bonus(actor: Dictionary) -> int:
  return _ability_modifier(int(actor.get(str(actor.get("attack_ability", "str")), 10))) + int(actor.get("prof", 2))

func _attack_advantage(actor: Dictionary, target: Dictionary, distance: int) -> int:
  var advantage := 0
  var melee := distance <= 1
  if "prone" in target.conditions: advantage += 1 if melee else -1
  if bool(actor.get("hidden", false)): advantage += 1
  if "poisoned" in actor.conditions: advantage -= 1
  if int(actor.get("attack_range", 1)) > 1 and distance <= 1: advantage -= 1
  return clampi(advantage, -1, 1)

func _attack_roll_text(result: Dictionary) -> String:
  var suffix := " with advantage" if result.advantage > 0 else (" with disadvantage" if result.advantage < 0 else "")
  return "d20 %d%s + %d = %d" % [result.roll, suffix, result.bonus, result.total]

func _roll_damage(actor: Dictionary, include_bonus := true) -> int:
  var damage := 0
  for i in range(int(actor.get("damage_dice", 1))):
    damage += _roll_die(int(actor.get("damage_sides", 6)))
  if include_bonus:
    damage += int(actor.get("damage_bonus", 0))
  return damage

func _ally_adjacent_to_enemy(attacker_id: String, target: Dictionary) -> bool:
  for member in party:
    if str(member.id) != attacker_id and int(member.hp) > 0 and _tile_distance(member.pos, target.pos) <= 1:
      return true
  return false

func _alive_enemy_count() -> int:
  var alive := 0
  for enemy in enemies:
    if int(enemy.hp) > 0: alive += 1
  return alive

func _alive_party_count() -> int:
  var alive := 0
  for member in party:
    if int(member.hp) > 0: alive += 1
  return alive

func _refresh() -> void:
  if not is_instance_valid(status_label):
    return
  if story_phase == "combat":
    var current := _current_actor()
    var actor := _get_actor(str(current.get("id", "")))
    var side := "Party" if str(current.get("side", "")) == "party" else "Enemy"
    status_label.text = "ROUND %d · %s turn: %s · Initiative %d" % [round_no, side, actor.get("name", "—"), current.get("initiative", 0)]
    if str(current.get("side", "")) == "party":
      hp_label.text = "%s · Level %d %s · HP %d/%d · AC %d · Action %s · Move %s · Bonus %s" % [actor.name, actor.level, actor["class_name"], actor.hp, actor.max_hp, actor.ac, "spent" if actor.action_used else "ready", "spent" if actor.moved else "%d ft" % (_movement_limit(actor) * 5), "spent" if actor.bonus_used else "ready"]
    else:
      hp_label.text = _party_combat_status()
  elif story_phase == "complete":
    status_label.text = "ADVENTURE COMPLETE · %s" % story_ending.replace("_", " ").to_upper()
    hp_label.text = _party_status_with_class()
  elif story_phase == "defeat":
    status_label.text = "THE PARTY HAS FALLEN · retry the encounter"
    hp_label.text = "Party: " + "  ·  ".join(["%s %d/%d HP" % [p.name, p.hp, p.max_hp] for p in party])
  else:
    status_label.text = "EXPLORATION · %s · %s" % [story_phase.to_upper(), party[selected_party_index].name]
    hp_label.text = _party_status_detailed()
  if is_instance_valid(board): board.queue_redraw()
  var combat_party_turn := _is_party_turn()
  var actor := _active_party_actor()
  move_button.disabled = story_phase == "combat" and (not combat_party_turn or bool(actor.get("moved", false)))
  attack_button.disabled = story_phase != "combat" or not combat_party_turn or bool(actor.get("action_used", false))
  shove_button.disabled = story_phase != "combat" or not combat_party_turn or bool(actor.get("action_used", false))
  special_button.text = str(actor.get("special_name", "Special"))
  special_button.disabled = story_phase != "combat" or not combat_party_turn
  end_turn_button.disabled = story_phase != "combat" or not combat_party_turn
  for option in class_selectors:
    option.disabled = story_phase != "graveyard"
  if story_phase == "graveyard":
    story_button.text = "Approach Abbey"
    story_button.disabled = false
  elif story_phase == "abbey":
    story_button.text = "Resolve Abbey"
    story_button.disabled = false
  elif story_phase == "defeat":
    story_button.text = "Retry Encounter"
    story_button.disabled = false
  else:
    story_button.text = "Adventure Complete"
    story_button.disabled = true

func _say(text: String) -> void:
  event_log.append(text)
  while event_log.size() > 22: event_log.pop_front()
  if is_instance_valid(log_label):
    log_label.clear()
    for line in event_log: log_label.append_text(line + "\n\n")
    log_label.scroll_to_line(log_label.get_line_count())

func _party_combat_status() -> String:
  var parts: Array[String] = []
  for member in party:
    parts.append("%s %d/%d" % [member.name, member.hp, member.max_hp])
  return "Allies: " + "  ·  ".join(parts)

func _party_status_with_class() -> String:
  var parts: Array[String] = []
  for member in party:
    parts.append("%s (%s) %d/%d HP" % [member.name, member["class_name"], member.hp, member.max_hp])
  return "Party: " + "  ·  ".join(parts)

func _party_status_detailed() -> String:
  var parts: Array[String] = []
  for member in party:
    parts.append("%s · %s · HP %d/%d · AC %d" % [member.name, member["class_name"], member.hp, member.max_hp, member.ac])
  return "Party: " + "  ·  ".join(parts)

func resolve_check(roll: int, bonus: int, dc: int) -> Dictionary:
  var total := roll + bonus
  return {"roll":roll, "bonus":bonus, "dc":dc, "total":total, "success":total >= dc}

func resolve_save(roll: int, bonus: int, dc: int) -> Dictionary:
  var total := roll + bonus
  return {"roll":roll, "bonus":bonus, "dc":dc, "total":total, "success":total >= dc}

func resolve_attack(roll: int, bonus: int, target_ac: int) -> Dictionary:
  var total := roll + bonus
  var critical := roll == 20
  return {"roll":roll, "bonus":bonus, "ac":target_ac, "total":total, "hit":critical or (roll != 1 and total >= target_ac), "critical":critical}

func resolve_attack_roll(roll_a: int, roll_b: int, bonus: int, target_ac: int, advantage: int) -> Dictionary:
  var roll := roll_a
  if advantage > 0: roll = maxi(roll_a, roll_b)
  elif advantage < 0: roll = mini(roll_a, roll_b)
  var result := resolve_attack(roll, bonus, target_ac)
  result["advantage"] = advantage
  result["roll_a"] = roll_a
  result["roll_b"] = roll_b
  return result

func resolve_contest(attacker_roll: int, attacker_bonus: int, defender_roll: int, defender_bonus: int) -> Dictionary:
  var attacker_total := attacker_roll + attacker_bonus
  var defender_total := defender_roll + defender_bonus
  return {"attacker_total":attacker_total, "defender_total":defender_total, "attacker_wins":attacker_total >= defender_total}

func _ability_modifier(score: int) -> int:
  return int(floor((score - 10) / 2.0))

func _roll_die(sides: int) -> int:
  if not test_roll_queue.is_empty():
    return clampi(test_roll_queue.pop_front(), 1, sides)
  return randi_range(1, sides)