"""Entry point for launching mGBA with automation scripts."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path
from typing import Sequence

from gba_automation import AppConfig
from gba_automation.emulator import MGbaLauncher


_LOGGER = logging.getLogger(__name__)


def _parse_arguments() -> argparse.Namespace:
    """Parse command-line options for configuring the launcher."""

    parser = argparse.ArgumentParser(description="Launch mGBA with automation helpers")
    parser.add_argument(
        "--emulator",
        dest="emulator_path",
        help="Path to the mGBA executable (defaults to $GBA_AUTOMATION_EMULATOR)",
    )
    parser.add_argument(
        "--rom",
        dest="rom_path",
        help="Path to the Pokémon Fire Red ROM (defaults to $GBA_AUTOMATION_ROM)",
    )
    parser.add_argument(
        "--lua",
        dest="lua_script",
        default="start_game.lua",
        help=(
            "Lua script executed on startup."
            " Relative paths resolve from the 'gba_automation/lua' directory."
        ),
    )
    parser.add_argument(
        "--wait",
        action="store_true",
        help="Block until the emulator process exits",
    )
    parser.add_argument(
        "--extra-arg",
        dest="extra_args",
        action="append",
        default=[],
        help="Additional arguments passed verbatim to the mGBA process",
    )

    return parser.parse_args()


def _configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(name)s | %(message)s")


def _resolve_config(args: argparse.Namespace) -> AppConfig:
    project_root = Path(__file__).resolve().parent
    return AppConfig.from_sources(
        emulator_path=args.emulator_path,
        rom_path=args.rom_path,
        lua_script=args.lua_script,
        project_root=project_root,
        emulator_description="mGBA",
    )


def _launch_mgba(config: AppConfig, extra_args: Sequence[str], wait: bool) -> None:
    launcher = MGbaLauncher(executable_path=config.emulator_path)
    launcher.launch(
        rom_path=config.rom_path,
        lua_script=config.lua_script,
        extra_args=list(extra_args) or None,
        wait=wait,
    )


def main() -> None:
    args = _parse_arguments()
    _configure_logging()

    try:
        config = _resolve_config(args)
    except FileNotFoundError as exc:
        _LOGGER.error("%s", exc)
        raise SystemExit(1) from exc

    _LOGGER.info(
        "Launching mGBA with ROM '%s' and Lua script '%s'",
        config.rom_path,
        config.lua_script,
    )

    _launch_mgba(config, args.extra_args, args.wait)


if __name__ == "__main__":
    main()
