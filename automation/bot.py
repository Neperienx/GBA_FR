"""High level automation logic for shiny hunting."""

from __future__ import annotations

import itertools
import time
from dataclasses import dataclass, field
from typing import Iterable, Optional

from .config import BotConfig, MacroStep
from .logger import EncounterLogger
from .state import BotMode, Encounter, GameState
from .bridge import MgbaBridge


@dataclass
class ShinyHunterBot:
    """Event loop implementing the shiny hunting state machine."""

    bridge: MgbaBridge
    config: BotConfig
    logger: EncounterLogger
    poll_interval: float = 0.05
    mode: BotMode = BotMode.IDLE
    encounters_seen: int = 0
    _current_encounter: Optional[Encounter] = field(default=None, init=False)

    def start(self) -> None:
        self.bridge.connect()
        self.mode = BotMode.WALK_TO_GRASS
        try:
            while True:
                state = self.bridge.receive_state()
                if state is None:
                    time.sleep(self.poll_interval)
                    continue
                self._step(state)
        finally:
            self.bridge.close()

    # ------------------------------------------------------------------

    def _step(self, state: GameState) -> None:
        if self.mode == BotMode.WALK_TO_GRASS:
            self._ensure_macro_running(self.config.to_grass_macro)
            if state.in_battle:
                self.mode = BotMode.ENCOUNTER
        elif self.mode == BotMode.ENCOUNTER:
            self._handle_encounter(state)
        elif self.mode == BotMode.CATCH_SHINY:
            self._catch_sequence(state)
        elif self.mode == BotMode.BATTLE:
            self._handle_battle(state)
        elif self.mode == BotMode.HEAL:
            self._ensure_macro_running(self.config.to_center_macro)
            if not state.in_battle and state.player_hp == state.player_max_hp:
                self.mode = BotMode.RETURN_TO_GRASS
        elif self.mode == BotMode.RETURN_TO_GRASS:
            self._ensure_macro_running(self.config.to_grass_macro)
            if state.in_battle:
                self.mode = BotMode.ENCOUNTER

    # ------------------------------------------------------------------

    def _ensure_macro_running(self, macro: Iterable[MacroStep]) -> None:
        if not macro:
            return
        self.bridge.send_macro(macro)

    def _handle_encounter(self, state: GameState) -> None:
        encounter = state.encounter
        if encounter is None:
            return
        if encounter is not self._current_encounter:
            self.encounters_seen += 1
            self._current_encounter = encounter
            self.logger.log(encounter, self.encounters_seen)
        if encounter.is_shiny:
            self.mode = BotMode.CATCH_SHINY
            self.bridge.reset_input()
        else:
            self._decide_non_shiny_action(state)

    def _decide_non_shiny_action(self, state: GameState) -> None:
        if self._pp_low(state):
            self.mode = BotMode.HEAL
            self.bridge.send_macro(self.config.to_center_macro)
            return
        self._attack_with_best_move(state)

    def _pp_low(self, state: GameState) -> bool:
        pp_values = state.pp_values
        monitored = [pp_values.get(move_index, 0) for move_index in self.config.pp_recovery_moves]
        return all(pp <= self.config.pp_threshold for pp in monitored)

    def _attack_with_best_move(self, state: GameState) -> None:
        # Basic implementation: just press A twice to select move 1.
        self.bridge.send_macro(
            (
                MacroStep(duration=2, buttons=["A"]),
                MacroStep(duration=2, buttons=["A"]),
            )
        )
        self.mode = BotMode.WALK_TO_GRASS

    def _catch_sequence(self, state: GameState) -> None:
        if not state.in_battle:
            self.mode = BotMode.RETURN_TO_GRASS
            return
        self.bridge.send_macro(
            (
                MacroStep(duration=2, buttons=["B"]),  # close text boxes if any
                MacroStep(duration=2, buttons=["DOWN"]),
                MacroStep(duration=2, buttons=["A"]),  # select bag
                MacroStep(duration=2, buttons=["A"]),  # use ball
            )
        )

    def _handle_battle(self, state: GameState) -> None:
        if not state.in_battle:
            if self.mode == BotMode.HEAL:
                self.mode = BotMode.RETURN_TO_GRASS
            else:
                self.mode = BotMode.WALK_TO_GRASS
            return
        self._attack_with_best_move(state)
