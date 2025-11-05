"""Configuration management for the automation tooling."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

_ENV_EMULATOR_PATH = "GBA_AUTOMATION_EMULATOR"
_ENV_ROM_PATH = "GBA_AUTOMATION_ROM"
_ENV_LUA_SCRIPT = "GBA_AUTOMATION_LUA"


@dataclass(frozen=True)
class AppConfig:
    """Runtime configuration for launching the emulator and automation scripts."""

    emulator_path: Path
    rom_path: Path
    lua_script: Path

    @classmethod
    def from_sources(
        cls,
        *,
        emulator_path: Optional[str] = None,
        rom_path: Optional[str] = None,
        lua_script: Optional[str] = None,
        project_root: Optional[Path] = None,
    ) -> "AppConfig":
        """Build a configuration object from CLI args and environment defaults.

        Args:
            emulator_path: Optional explicit path to the BizHawk executable.
            rom_path: Optional explicit path to the Pokémon Fire Red ROM.
            lua_script: Optional explicit path to the Lua automation entry point.
            project_root: Optional root directory used for resolving relative paths.

        Returns:
            A fully resolved :class:`AppConfig` instance.
        """

        root = project_root or Path.cwd()

        emulator = _resolve_path(
            emulator_path,
            env_var=_ENV_EMULATOR_PATH,
            description="BizHawk emulator",
        )
        rom = _resolve_path(
            rom_path,
            env_var=_ENV_ROM_PATH,
            description="Pokémon Fire Red ROM",
        )
        script = _resolve_path(
            lua_script,
            env_var=_ENV_LUA_SCRIPT,
            description="Lua automation script",
            base_directory=root / "gba_automation" / "lua",
        )

        return cls(emulator_path=emulator, rom_path=rom, lua_script=script)


def _resolve_path(
    explicit: Optional[str],
    *,
    env_var: str,
    description: str,
    base_directory: Optional[Path] = None,
) -> Path:
    """Resolve a filesystem path using CLI, environment, and sensible defaults.

    Args:
        explicit: Path provided by the caller (highest priority).
        env_var: Environment variable consulted when no explicit path is provided.
        description: Human readable description used for error messages.
        base_directory: Optional base directory for relative paths.

    Returns:
        A :class:`Path` object pointing to the resolved location.

    Raises:
        FileNotFoundError: If the resulting path does not exist on disk.
    """

    candidate = explicit or os.environ.get(env_var)
    if candidate is None:
        raise FileNotFoundError(
            f"No path configured for the {description}. Set '{env_var}' or pass an argument."
        )

    path = Path(candidate)
    if not path.is_absolute() and base_directory is not None:
        path = base_directory / path

    path = path.expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"Configured {description} path does not exist: {path}")

    return path


__all__ = ["AppConfig"]
