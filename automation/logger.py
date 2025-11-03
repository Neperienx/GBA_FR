"""Encounter logging utilities."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TextIO

from .state import Encounter


@dataclass
class EncounterLogger:
    """Append-only logger for encounters."""

    path: Path

    def __post_init__(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def log(self, encounter: Encounter, encounters_seen: int) -> None:
        line = self._format_line(encounter, encounters_seen)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")

    def _format_line(self, encounter: Encounter, encounters_seen: int) -> str:
        timestamp = datetime.utcnow().isoformat(timespec="seconds")
        shiny_flag = "⭐" if encounter.is_shiny else "✖"
        return (
            f"[{timestamp}] #{encounters_seen:06d} Species={encounter.species} "
            f"TID={encounter.trainer_id} SID={encounter.secret_id} PID={encounter.personality} "
            f"Shiny={shiny_flag}"
        )
