"""Command-line entry point for the Fire Red automation tooling."""

from __future__ import annotations

import argparse
import logging
from enum import Enum
from pathlib import Path
from typing import Optional

from gba_automation import AppConfig
from gba_automation.emulator import BizHawkLauncher, MGbaLauncher
from gba_automation.scripts import LuaScriptRegistry

_DEFAULT_MGBA_PATH = r"C:\\Program Files\\mGBA\\mGBA.exe"
_DEFAULT_BIZHAWK_PATH = r"C:\\Program Files\\BizHawk\\EmuHawk.exe"
_DEFAULT_ROM_PATH = r"C:\\Users\\nicol\\Documents\\GB_Emulator\\Rouge Feu\\Pokemon - Version Rouge Feu (France).gba"


class EmulatorKind(str, Enum):
    """Enumerates the supported emulator integrations."""

    BIZHAWK = "bizhawk"
    MGBA = "mgba"

    @property
    def default_path(self) -> str:
        """Return the OS-level default executable location for the emulator."""

        if self is EmulatorKind.BIZHAWK:
            return _DEFAULT_BIZHAWK_PATH
        return _DEFAULT_MGBA_PATH

    @property
    def description(self) -> str:
        """Provide a human-readable name for logging and error messages."""

        if self is EmulatorKind.BIZHAWK:
            return "BizHawk emulator"
        return "mGBA emulator"

    def create_launcher(self, executable_path: Path) -> "MGbaLauncher | BizHawkLauncher":
        """Instantiate the launcher associated with the emulator kind."""

        if self is EmulatorKind.BIZHAWK:
            return BizHawkLauncher(executable_path=executable_path)
        return MGbaLauncher(executable_path=executable_path)


def configure_logging(verbose: bool) -> None:
    """Initialise the root logger with a simple configuration."""

    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")


def build_argument_parser() -> argparse.ArgumentParser:
    """Create the CLI argument parser."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--emulator-type",
        choices=[kind.value for kind in EmulatorKind],
        default=EmulatorKind.BIZHAWK.value,
        help="Which emulator integration to use (determines defaults and launch syntax).",
    )
    parser.add_argument(
        "--emulator",
        help="Path to the emulator executable. Defaults depend on --emulator-type.",
        default=None,
    )
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


def resolve_configuration(
    args: argparse.Namespace,
    project_root: Path,
    *,
    emulator_kind: EmulatorKind,
    emulator_path: str,
) -> AppConfig:
    """Resolve all runtime configuration details from CLI arguments."""

    registry = LuaScriptRegistry(base_directory=project_root / "gba_automation" / "lua")
    registry.register("start_game", "start_game.lua")

    script_name: str = args.script
    script = registry.get(script_name)

    config = AppConfig.from_sources(
        emulator_path=emulator_path,
        rom_path=args.rom,
        lua_script=str(script.path),
        project_root=project_root,
        emulator_description=emulator_kind.description,
    )
    return config


def main(argv: Optional[list[str]] = None) -> int:
    """Entry point used by the ``python -m`` mechanism and ``main.py`` script."""

    parser = build_argument_parser()
    args = parser.parse_args(argv)

    configure_logging(verbose=args.verbose)
    project_root = Path(__file__).resolve().parent

    emulator_kind = EmulatorKind(args.emulator_type)
    emulator_path = args.emulator or emulator_kind.default_path

    try:
        config = resolve_configuration(
            args,
            project_root,
            emulator_kind=emulator_kind,
            emulator_path=emulator_path,
        )
    except FileNotFoundError as error:
        logging.getLogger(__name__).error("Configuration error: %s", error)
        return 1

    launcher = emulator_kind.create_launcher(config.emulator_path)
    launcher.launch(rom_path=config.rom_path, lua_script=config.lua_script, wait=args.wait)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
