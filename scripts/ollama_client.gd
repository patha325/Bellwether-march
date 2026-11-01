extends Node
class_name OllamaClient

signal response_received(payload: Dictionary)
signal request_failed(reason: String)

var base_url := "http://localhost:11434"
var model := "qwen2.5:7b"
var _request: HTTPRequest

const OUTPUT_SCHEMA := {
  "type": "object",
  "properties": {
    "narration": {"type": "string"},
    "action": {"type": "string", "enum": ["persuade", "deceive", "intimidate", "investigate", "stealth", "athletics", "insight", "medicine", "survival", "history", "arcana", "perception", "help", "invalid"]},
    "ability": {"type": "string", "enum": ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]},
    "target": {"type": "string"},
    "dc": {"type": "integer", "minimum": 5, "maximum": 25},
    "consequence_on_success": {"type": "string"},
    "consequence_on_failure": {"type": "string"}
  },
  "required": ["narration", "action", "ability", "target", "dc", "consequence_on_success", "consequence_on_failure"]
}

func _ready() -> void:
  _request = HTTPRequest.new()
  _request.timeout = 90.0
  _request.use_threads = true
  add_child(_request)
  _request.request_completed.connect(_on_request_completed)

func ask_for_action(player_text: String, world_context: String) -> void:
  var system_text := """
You are the scene interpreter for a single-player medieval fantasy adventure. Convert the player's stated intent into one plausible D&D 5e-style ability check and write a concise in-world response. Never decide a roll result, grant an item, change a stat, or invent a success. The game engine rolls and applies consequences. Only use information in the context. If the intent is conversation without a risky action, use action=invalid and DC=5. Keep narration suitable for a grounded plague-era medieval setting. Return only the required JSON object.
"""
  var user_text := "WORLD STATE:\n%s\n\nPLAYER INTENT:\n%s" % [world_context, player_text]
  var body := {
    "model": model,
    "stream": false,
    "format": OUTPUT_SCHEMA,
    "messages": [
      {"role": "system", "content": system_text},
      {"role": "user", "content": user_text}
    ],
    "options": {"temperature": 0.7}
  }
  var err := _request.request(base_url + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
  if err != OK:
    request_failed.emit("Could not contact Ollama. Check that it is running at %s." % base_url)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
  if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
    request_failed.emit("Ollama request failed (HTTP %d)." % response_code)
    return
  var parsed = JSON.parse_string(body.get_string_from_utf8())
  if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("message"):
    request_failed.emit("Ollama returned an unreadable response.")
    return
  var content = JSON.parse_string(str(parsed.message.get("content", "")))
  if typeof(content) != TYPE_DICTIONARY:
    request_failed.emit("The model response did not match the expected action format.")
    return
  response_received.emit(content)
