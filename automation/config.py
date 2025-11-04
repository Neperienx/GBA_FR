"""Configuration models for the shiny hunting bot."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Iterable, List, Sequence


class BridgeMode(str, Enum):
    """Describes which side of the link hosts the TCP server."""

    PYTHON_CLIENT = "python_client"
    PYTHON_SERVER = "python_server"

    @classmethod
    def from_string(cls, value: str) -> "BridgeMode":
        """Parse ``value`` into :class:`BridgeMode` with validation."""

        normalized = value.strip().lower()
        try:
            return cls(normalized)
        except ValueError as exc:  # pragma: no cover - configuration error path
            options = ", ".join(mode.value for mode in cls)
            raise ValueError(f"Invalid bridge mode: {value!r} (expected one of: {options})") from exc


@dataclass
class MacroStep:
    """Represents a single macro step (button hold for a duration)."""

    duration: int
    buttons: Sequence[str] = field(default_factory=list)

    def serialize(self) -> dict:
        return {"duration": int(self.duration), "buttons": list(self.buttons)}


@dataclass
class BotConfig:
    """Top level configuration for the shiny hunting bot."""

    host: str = "127.0.0.1"
    port: int = 8765
    bridge_mode: BridgeMode = BridgeMode.PYTHON_CLIENT
    encounter_log_path: Path = Path("logs/encounters.log")
    to_grass_macro: Sequence[MacroStep] = field(default_factory=list)
    to_center_macro: Sequence[MacroStep] = field(default_factory=list)
    pp_threshold: int = 4
    pp_recovery_moves: Iterable[int] = field(default_factory=lambda: (0,))

    def serialize_macro(self, macro: Sequence[MacroStep]) -> List[dict]:
        return [step.serialize() for step in macro]
