"""Automation package for the Fire Red shiny hunting bot."""

from .bot import ShinyHunterBot
from .bridge import MgbaBridge
from .config import BotConfig, BridgeMode
from .logger import EncounterLogger
from .state import BotMode, Encounter, GameState

__all__ = [
    "ShinyHunterBot",
    "MgbaBridge",
    "BotConfig",
    "BridgeMode",
    "EncounterLogger",
    "BotMode",
    "Encounter",
    "GameState",
]
