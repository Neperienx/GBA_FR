"""Lua script management for the automation toolkit."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict


@dataclass
class LuaScript:
    """Represents a Lua script available to the automation runtime."""

    name: str
    path: Path


class LuaScriptRegistry:
    """Registry responsible for locating Lua automation scripts."""

    def __init__(self, base_directory: Path) -> None:
        self._base_directory = base_directory
        self._scripts: Dict[str, LuaScript] = {}

    def register(self, name: str, relative_path: str) -> None:
        """Register a script relative to the base directory."""

        path = (self._base_directory / relative_path).resolve()
        self._scripts[name] = LuaScript(name=name, path=path)

    def get(self, name: str) -> LuaScript:
        """Retrieve the script metadata by name."""

        try:
            return self._scripts[name]
        except KeyError as exc:  # pragma: no cover - defensive programming
            available = ", ".join(sorted(self._scripts)) or "<none>"
            raise KeyError(f"Unknown Lua script '{name}'. Available scripts: {available}") from exc

    @property
    def default(self) -> LuaScript:
        """Return the default automation script."""

        return self.get("start_game")


__all__ = ["LuaScript", "LuaScriptRegistry"]
