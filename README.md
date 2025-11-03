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

