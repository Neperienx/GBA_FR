# GBA Automation Bridge (Lua ↔ Python)

## 🎯 Goal

The goal of this project is to create a **bi-directional interface** between a GBA emulator (e.g. mGBA or BizHawk) and **Python**, allowing advanced automation and AI-driven gameplay logic.

The first target use case is **shiny Pokémon hunting and training automation**:
- Run between PokéCenter and grass patches.
- Detect encounters and check if the Pokémon is shiny.
- Fight or run automatically depending on context.
- Manage PP, HP, and healing at PokéCenter.
- Log encounters and outcomes.

Eventually, this bridge can be reused for:
- Speedrunning or TAS-style automation.
- Data extraction (e.g., reading battle stats, encounter rates).
- Reinforcement learning / AI experiments.

---

## 🧩 Architecture Overview

### Core Idea

We split responsibilities between **Lua (inside emulator)** and **Python (external controller)**:

| Layer | Language | Role |
|-------|-----------|------|
| Emulator | **Lua script** | Low-level bridge to memory & button input |
| External Bot | **Python script** | High-level decision logic & automation loops |

---

## 🛠️ Getting Started

### 1. Install Python and Create an Isolated Environment

1. Install **Python 3.12.x** (3.12.6 is confirmed to work). If you already have Python 3.12 available, you can skip this step.
2. Open a terminal (PowerShell on Windows, Terminal on macOS/Linux) and move into the project directory:
   ```bash
   cd /path/to/GBA_FR
   ```
3. Create a virtual environment so that the project has its own copy of Python and packages:
   ```bash
   python3.12 -m venv .venv
   ```
   - On Windows you can also run `py -3.12 -m venv .venv`.
4. Activate the environment:
   - **macOS/Linux:** `source .venv/bin/activate`
   - **Windows (PowerShell):** `.venv\\Scripts\\Activate.ps1`
5. Upgrade `pip` and install the project requirements:
   ```bash
   python -m pip install --upgrade pip
   pip install -r requirements.txt
   ```
   The project currently relies only on Python's standard library, but the `requirements.txt` file is provided so you can track
   future dependencies and install them with a single command if they are added later.

When the environment is active your prompt will usually show `(.venv)` in front of it. Run `deactivate` to leave the
environment when you are done working on the project.

### 2. Prepare the Emulator

Pick the option that matches your emulator:

- **mGBA** – Use the latest nightly build of [mGBA](https://mgba.io/) (or another emulator with Lua + socket support).
  Load your Pokémon Fire Red ROM (v1.0 is expected by the memory map) and run
  [`lua/automation_bridge.lua`](lua/automation_bridge.lua) from the Lua console. The script opens a TCP server on
  `127.0.0.1:8765` and streams game state once per frame.
- **BizHawk** – Install [BizHawk](https://tasvideos.org/BizHawk) and point `config.toml` at your EmuHawk executable.
  The launcher automatically copies [`lua/bizHawk_automation_bridge.lua`](lua/bizHawk_automation_bridge.lua) into BizHawk's Lua
  folder before starting the emulator, so you always run the latest bridge. No manual script selection is required.

In both cases, ensure the chosen port is not blocked by a firewall.

### 3. Configure the One-Click Launcher

The repository ships with [`config.example.toml`](config.example.toml). Copy it to `config.toml` and edit the values so they
match your machine:

```bash
cp config.example.toml config.toml
```

Key sections inside the file:

- `[bridge]` – host/port used by both the Lua script and the Python bot. Leave as `127.0.0.1:8765` unless you have a port
  conflict. The optional `mode` key selects which side opens the TCP server:
  - `python_client` (default) – Lua hosts the server and the Python bot connects to it. Works out of the box with both the
    mGBA and BizHawk bridge scripts, and the launcher passes the configured host/port through the `GBA_BRIDGE_HOST` /
    `GBA_BRIDGE_PORT` environment variables so the Lua script binds to the expected endpoint.
  - `python_server` – The Python launcher listens for the emulator to connect. Use this only for advanced setups where the
    emulator must act as the TCP client.
- `[emulator]` – points to your emulator executable, ROM, and destination folder for the Lua script. Set `enabled = false` if
  you prefer launching the emulator manually. The launcher copies the configured Lua bridge (mGBA or BizHawk) to the destination
  on every run so the emulator always executes the latest version. When `lua_source` is omitted, the launcher auto-selects the
  correct script based on `profile = "bizhawk"` or by detecting an `EmuHawk` executable path.
- `[bot]` – runtime behaviour of the automation bot.
  - `log_path` controls where encounter logs are written.
  - `pp_threshold` and `pp_recovery_moves` control when the bot returns to heal.
  - `to_grass_macro` and `to_center_macro` describe the walking routes as ordered sequences of `duration` and `buttons` pairs.
    Each duration is measured in frames, so `duration = 45` with `buttons = ["UP"]` holds UP for 45 frames.

### 4. Run the Automation Bot

```bash
python main.py
```

The launcher performs the following steps:

1. Copies the Lua bridge script to the configured BizHawk directory (unless `copy_lua = false`).
2. Starts the emulator with the correct socket arguments and ROM (skip this step with `--no-launch`). When `bridge.mode` is
   `python_client`, the launcher omits `--socket_ip/--socket_port` so BizHawk keeps listening for the Python bot instead of
   trying to connect to a missing server.
3. Connects to the Lua bridge, retrying until it becomes available, and starts the shiny hunting state machine.

Use `python main.py --config custom_config.toml` if you store multiple setups, or `python main.py --no-launch` when the
emulator is already running with the Lua script loaded.

### 5. Configure Movement Macros Programmatically

Macros are sequences of button presses with a frame duration. You can customize them either by editing the `to_grass_macro`
and `to_center_macro` blocks inside `config.toml` or by instantiating `BotConfig` manually in a bespoke script. Example:

```python
from automation import BotConfig, MgbaBridge, ShinyHunterBot, EncounterLogger
from automation.config import MacroStep

config = BotConfig(
    to_grass_macro=(
        MacroStep(duration=45, buttons=["UP"]),
        MacroStep(duration=10, buttons=["RIGHT"]),
    ),
    to_center_macro=(
        MacroStep(duration=10, buttons=["LEFT"]),
        MacroStep(duration=45, buttons=["DOWN"]),
    ),
)

bridge = MgbaBridge(config)
logger = EncounterLogger(config.encounter_log_path)
bot = ShinyHunterBot(bridge, config, logger)
bot.start()
```

### 6. Encounter Logging

Every encounter is appended to `logs/encounters.log` with timestamp, encounter count, species, IDs, and whether it was shiny. Use this file to track hunt statistics.

---

## 🧪 Game State Extracted by Lua

The Lua bridge reads the following Fire Red memory offsets every frame:

| Field | Address | Description |
|-------|---------|-------------|
| `in_battle_flag` | `0x02022F2C` | Non-zero when in battle |
| `battle_mode` | `0x02022F2D` | Battle mode bit-field |
| `player_hp` | `0x02024284` | Current HP of lead Pokémon |
| `player_max_hp` | `0x02024286` | Max HP of lead Pokémon |
| `battle_pp_1..4` | `0x0202405A-0x0202405D` | PP for moves 1-4 |
| `enemy_personality` | `0x020240A4` | Personality value (used for shiny check) |
| `enemy_tid` | `0x020240A0` | Trainer ID of opponent |
| `enemy_sid` | `0x020240A2` | Secret ID of opponent |
| `enemy_species` | `0x020240A8` | Pokédex species ID |

### Shiny Detection

A Pokémon is flagged as shiny if `(TID XOR SID XOR (PID & 0xFFFF) XOR (PID >> 16)) < 8`.  The Python side performs this calculation and switches into the `CATCH_SHINY` state when triggered.

---

## ♻️ Automation Loop Summary

1. **Walk to grass** using the configured macro.
2. **Encounter Pokémon**.  Every encounter is logged.
3. **Shiny?**
   - **Yes** → Execute catch macro and then return to grass.
   - **No** → Check PP thresholds.
     - If PP low → Run heal macro back to PokéCenter, then return to grass.
     - Otherwise → Attack using default move macro.
4. Repeat until manually stopped.

---

## 📁 Project Structure

```
.
├── automation/          # Python package (bridge + bot)
├── lua/                 # Lua script for emulator bridge
├── logs/                # Encounter logs (created automatically)
└── scripts/             # Command line entry point
```

---

## 🚧 Next Steps

- Improve macro scheduling so multiple commands can queue without overlap.
- Add battle strategy scripting (e.g., item usage, move prioritization).
- Expand memory watch list to include inventory / repel timers / bag data.
- Bundle configuration files per hunt location.

---

## ⚠️ Disclaimer

This project is provided for educational purposes.  Use responsibly and respect the terms of service of your games and hardware.
