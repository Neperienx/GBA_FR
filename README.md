The Goal of this project is to do a LUA automation for Pokemon Fire red french edition.
The main goal will be to automate the game, form load up, to catching shiny pokemons.

Features will have to include:

1. finding a grass area.
2. checking if we have an encounter
3. check of pokemon is shiny
4. if shiny wait for user input
5. if not shiny battle pokemon for exp (we need a pp management system)
6. repeat until a shiny is found or we are out of pp.
7. if out of pp we have to go back to the nearest pokecenter and heal.
8. repeat by walking back to grass

## Roadmap for full automation

The long-term loop (encounter → evaluate → recover → return) breaks down into the following
building blocks:

1. **Reliable game-state tracking**
   * Read overworld context from memory (map group/number, player position, tile behavior).
   * Detect party composition, PP counts, and Poké Center location for the current route.
   * Monitor encounter/battle state changes (wild encounter flag, active battle menu, etc.).
2. **Encounter loop orchestration**
   * Navigate between safe tiles and tall grass patches while tracking step count.
   * Trigger encounters and enter the battle flow state machine.
3. **Battle resolution logic**
   * Perform a shiny check before any action; pause and alert when a shiny is found.
   * Implement scripted move selection with PP safety checks and configurable flee/attack rules.
   * Detect end-of-battle transitions (victory, faint, or forced exit).
4. **Resource management**
   * Continuously evaluate PP / HP / item thresholds.
   * Path back to the nearest Poké Center when thresholds are crossed, then heal and restock.
   * Return to the designated grass tile and resume the encounter loop.

The `start_game.lua` script now emits a snapshot of the overworld state after the intro skip to
bootstrap the first bullet point. Subsequent scripts can reuse the logged addresses to build richer
state machines.

## Quick start

1. Install [BizHawk](https://tasvideos.org/BizHawk) and note the path to `EmuHawk.exe`.
2. Ensure the Pokémon Fire Red (French) ROM is available locally. By default the launcher uses:<br>
   `C:\Bizhawk\GBA\SaveRAM\Pokemon - Version Rouge Feu (France).gba`
3. Point the tooling at your mGBA executable. You can either:

   * pass the path on the command line each time:

     ```bash
     python main.py --emulator "C:\\BizHawk\\EmuHawk.exe" --wait
     ```

   * or set the `GBA_AUTOMATION_EMULATOR` environment variable once in your shell profile
     so the launcher can discover it automatically:

     ```bash
     setx GBA_AUTOMATION_EMULATOR "C:\\BizHawk\\EmuHawk.exe"   # Windows PowerShell / CMD
     export GBA_AUTOMATION_EMULATOR="/Applications/mGBA.app/Contents/MacOS/mGBA"  # macOS/Linux
     python main.py --wait
     ```

   The `--wait` flag keeps the Python process alive until BizHawk exits. If neither the command
   line flag nor the environment variable is provided you will see the
   `Configuration error: No path configured for the mGBA emulator` message at startup.

4. The default Lua script (`gba_automation/lua/start_game.lua`) repeatedly presses `A` to advance the
   intro screens until the game starts. Additional scripts can be added to `gba_automation/lua/` and
   registered via the `LuaScriptRegistry` in `main.py`.