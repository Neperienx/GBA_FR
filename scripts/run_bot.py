"""CLI entrypoint that starts the shiny hunting bot."""

from __future__ import annotations

import argparse
import signal
import sys
from pathlib import Path

from automation import BotConfig, EncounterLogger, MgbaBridge, ShinyHunterBot
from automation.config import MacroStep


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Fire Red shiny hunting bot")
    parser.add_argument("--host", default="127.0.0.1", help="Lua bridge host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8765, help="Lua bridge TCP port")
    parser.add_argument(
        "--log",
        type=Path,
        default=Path("logs/encounters.log"),
        help="Path to encounter log file",
    )
    return parser.parse_args()


def build_default_config(args: argparse.Namespace) -> BotConfig:
    # Example macros that need to be adapted to the specific Pokecenter layout.
    to_grass = (
        MacroStep(duration=60, buttons=["UP"]),
        MacroStep(duration=20, buttons=["RIGHT"]),
    )
    to_center = (
        MacroStep(duration=20, buttons=["LEFT"]),
        MacroStep(duration=60, buttons=["DOWN"]),
    )
    return BotConfig(
        host=args.host,
        port=args.port,
        encounter_log_path=args.log,
        to_grass_macro=to_grass,
        to_center_macro=to_center,
        pp_threshold=4,
        pp_recovery_moves=(0,),
    )


def main() -> int:
    args = parse_args()
    config = build_default_config(args)
    bridge = MgbaBridge(config)
    logger = EncounterLogger(config.encounter_log_path)
    bot = ShinyHunterBot(bridge=bridge, config=config, logger=logger)

    def handle_sigint(signum, frame):  # type: ignore[unused-argument]
        print("\n[bot] stopping...")
        bridge.reset_input()
        bridge.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sigint)
    bot.start()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
