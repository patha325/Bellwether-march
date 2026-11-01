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
- Choose Fighter, Rogue, Cleric, or Wizard for each of the three adventurers before approaching the abbey.
- Click a destination tile and press **Move** during a character's initiative turn.
- Select an enemy and use **Attack** or **Shove**; class features include Second Wind, Sneak Attack, Sacred Flame, Healing Word, and Burning Hands.
- Each active character can move, take one action, and use one bonus action. **End turn** advances initiative; enemies move and attack automatically.
- Investigate, negotiate, or use other free-form intentions in the story panel. Ollama suggests a skill check, while the game rolls and applies consequences. Clues and trust affect the adventure ending.

## Runtime checks

Run the headless runtime smoke suite with:

```sh
bash tests/run_runtime_tests.sh
```

The suite checks scene loading, class kits, standard 5e natural-roll handling, movement and advantage, story branches, initiative and an attack turn, plus the Ollama-compatible structured response against a deterministic local mock server. GitHub Actions runs these checks on pushes and pull requests.

## Rules scope

The prototype uses SRD 5.1 / 2014 fifth-edition-style level-one class kits, ability checks, saves, proficiency, attack rolls, Armor Class, hit points, initiative, movement, actions, bonus actions, spells, class features, conditions, and weapon damage. It is a focused prototype rather than a complete implementation of every player option or rule. AI proposals are constrained and treated as suggestions; the game validates DC bounds and applies all game-state changes itself.

## Attribution

This work includes material taken from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.

This game is compatible with fifth edition. Bellwether March and its characters are original material.