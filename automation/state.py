"""Dataclasses representing bridge state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import Dict, Optional


class BotMode(Enum):
    """High level state machine for the automation bot."""

    IDLE = auto()
    WALK_TO_GRASS = auto()
    ENCOUNTER = auto()
    CATCH_SHINY = auto()
    BATTLE = auto()
    HEAL = auto()
    RETURN_TO_GRASS = auto()


@dataclass
class Encounter:
    """Information about the current wild battle encounter."""

    species: int
    is_shiny: bool
    trainer_id: int
    secret_id: int
    personality: int


@dataclass
class GameState:
    """State snapshot transmitted from Lua bridge."""

    raw: Dict[str, int]

    @property
    def in_battle(self) -> bool:
        return bool(self.raw.get("in_battle_flag", 0))

    @property
    def player_hp(self) -> int:
        return int(self.raw.get("player_hp", 0))

    @property
    def player_max_hp(self) -> int:
        return int(self.raw.get("player_max_hp", 0))

    @property
    def pp_values(self) -> Dict[int, int]:
        return {
            0: int(self.raw.get("battle_pp_1", 0)),
            1: int(self.raw.get("battle_pp_2", 0)),
            2: int(self.raw.get("battle_pp_3", 0)),
            3: int(self.raw.get("battle_pp_4", 0)),
        }

    @property
    def encounter(self) -> Optional[Encounter]:
        if not self.in_battle:
            return None
        species = int(self.raw.get("enemy_species", 0))
        if species <= 0:
            return None
        return Encounter(
            species=species,
            is_shiny=self._is_shiny(),
            trainer_id=int(self.raw.get("enemy_tid", 0)),
            secret_id=int(self.raw.get("enemy_sid", 0)),
            personality=int(self.raw.get("enemy_personality", 0)),
        )

    def _is_shiny(self) -> bool:
        tid = int(self.raw.get("enemy_tid", 0))
        sid = int(self.raw.get("enemy_sid", 0))
        pid = int(self.raw.get("enemy_personality", 0))
        xor = tid ^ sid ^ (pid & 0xFFFF) ^ (pid >> 16)
        return xor < 8
