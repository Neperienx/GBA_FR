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

### 1. Prepare the Emulator

1. Use the latest nightly build of [mGBA](https://mgba.io/) (or another emulator with Lua + socket support).
2. Load your Pokémon Fire Red ROM (v1.0 is expected by the memory map).
3. Open the Lua scripting console and run [`lua/automation_bridge.lua`](lua/automation_bridge.lua).
   - The script opens a TCP server on `127.0.0.1:8765` and streams game state once per frame.
   - Make sure no firewall blocks the port.

### 2. Install Python Dependencies

The project currently has no external dependencies.  Any Python 3.10+ interpreter should work.

### 3. Run the Automation Bot

```bash
python scripts/run_bot.py --log logs/encounters.log
```

The CLI creates a default configuration with placeholder macros for walking between the PokéCenter and the grass patch.  Adjust the durations and button combinations in `scripts/run_bot.py` to match your setup.

### 4. Configure Movement Macros

Macros are sequences of button presses with a frame duration.  You can customize them either by editing `scripts/run_bot.py` or instantiating `BotConfig` manually in a bespoke script.  Example:

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

### 5. Encounter Logging

Every encounter is appended to `logs/encounters.log` with timestamp, encounter count, species, IDs, and whether it was shiny.  Use this file to track hunt statistics.

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
