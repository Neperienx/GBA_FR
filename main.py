"""Command-line entry point for the Fire Red automation tooling."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path
from typing import Optional

from gba_automation import AppConfig
from gba_automation.emulator import MGbaLauncher
from gba_automation.scripts import LuaScriptRegistry

_DEFAULT_ROM_PATH = r"C:\\Users\\nicol\\Documents\\GB_Emulator\\Rouge Feu\\Pokemon - Version Rouge Feu (France).gba"


def configure_logging(verbose: bool) -> None:
    """Initialise the root logger with a simple configuration."""

    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")


def build_argument_parser() -> argparse.ArgumentParser:
    """Create the CLI argument parser."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", help="Path to the mGBA executable.")
    parser.add_argument(
        "--rom",
        help="Path to the Pokémon Fire Red ROM. Defaults to the user's mGBA library location.",
        default=_DEFAULT_ROM_PATH,
    )
    parser.add_argument(
        "--script",
        help="Name of the Lua script to execute (registered in the automation toolkit).",
        default="start_game",
    )
    parser.add_argument("--wait", action="store_true", help="Wait for the emulator to close before exiting.")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging output.")
    return parser


def resolve_configuration(args: argparse.Namespace, project_root: Path) -> tuple[AppConfig, Path]:
    """Resolve all runtime configuration details from CLI arguments."""

    registry = LuaScriptRegistry(base_directory=project_root / "gba_automation" / "lua")
    registry.register("start_game", "start_game.lua")

    script_name: str = args.script
    script = registry.get(script_name)

    config = AppConfig.from_sources(
        emulator_path=args.emulator,
        rom_path=args.rom,
        lua_script=str(script.path),
        project_root=project_root,
    )
    return config, script.path


def main(argv: Optional[list[str]] = None) -> int:
    """Entry point used by the ``python -m`` mechanism and ``main.py`` script."""

    parser = build_argument_parser()
    args = parser.parse_args(argv)

    configure_logging(verbose=args.verbose)
    project_root = Path(__file__).resolve().parent

    try:
        config, script_path = resolve_configuration(args, project_root)
    except FileNotFoundError as error:
        logging.getLogger(__name__).error("Configuration error: %s", error)
        return 1

    launcher = MGbaLauncher(executable_path=config.emulator_path)
    launcher.launch(rom_path=config.rom_path, lua_script=script_path, wait=args.wait)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
