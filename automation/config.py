"""Configuration models for the shiny hunting bot."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, List, Sequence


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
    encounter_log_path: Path = Path("logs/encounters.log")
    to_grass_macro: Sequence[MacroStep] = field(default_factory=list)
    to_center_macro: Sequence[MacroStep] = field(default_factory=list)
    pp_threshold: int = 4
    pp_recovery_moves: Iterable[int] = field(default_factory=lambda: (0,))

    def serialize_macro(self, macro: Sequence[MacroStep]) -> List[dict]:
        return [step.serialize() for step in macro]
