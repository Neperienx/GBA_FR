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

## Quick start

1. Install [BizHawk](https://tasvideos.org/BizHawk) and note the path to `EmuHawk.exe`.
2. Ensure the Pokémon Fire Red (French) ROM is available locally. By default the launcher uses:<br>
   `C:\Bizhawk\GBA\SaveRAM\Pokemon - Version Rouge Feu (France).gba`
3. Run the automation launcher:

   ```bash
   python main.py --emulator "C:\\BizHawk\\EmuHawk.exe" --wait
   ```

   The `--wait` flag keeps the Python process alive until BizHawk exits.

4. The default Lua script (`gba_automation/lua/start_game.lua`) repeatedly presses `A` to advance the
   intro screens until the game starts. Additional scripts can be added to `gba_automation/lua/` and
   registered via the `LuaScriptRegistry` in `main.py`.