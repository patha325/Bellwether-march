# Bellwether March

A Godot 4 single-player, top-down tactical RPG prototype. Ollama interprets free-form player intentions into constrained ability-check proposals; the game engine owns dice rolls, character statistics, combat resolution, and persistent story flags.

## Run

1. Install Godot 4.3 or newer and Ollama.
2. Pull a local chat model, for example `ollama pull qwen2.5:7b`.
3. Start Ollama (`ollama serve`) and run `project.godot` in Godot.
4. Enter the exact installed model tag in the Ollama model field.

The default endpoint is `http://localhost:11434/api/chat`. If Ollama is unavailable, the prototype uses a small local intent matcher so the encounter remains playable.

## Controls

- Type an intention in the right panel and press Enter or **Try it**.
- Click a destination tile and press **Move**.
- Press **Attack** when adjacent to a hostile creature.
- **End turn** advances the enemies and begins the next round.

## Runtime checks

Run the headless runtime smoke suite with:

```sh
bash tests/run_runtime_tests.sh
```

The suite checks scene loading, natural 1/20 handling, ability checks, attack rolls, story-state persistence, movement, critical damage, and the Ollama-compatible chat request/response path against a deterministic local mock server. GitHub Actions runs these checks on pushes and pull requests.

## Rules scope

The prototype uses SRD 5.1 / 2014 fifth-edition-style ability checks, proficiency bonus, d20 attack rolls, Armor Class, hit points, initiative, movement, actions, and weapon damage. It is a focused prototype rather than a complete implementation of every player option or rule. AI proposals are constrained and treated as suggestions; the game validates DC bounds and applies all game-state changes itself.

## Attribution

This work includes material taken from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.

This game is compatible with fifth edition. Bellwether March and its characters are original material.
