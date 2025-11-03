"""Networking layer that talks to the Lua automation bridge."""

from __future__ import annotations

import json
import socket
import threading
from dataclasses import dataclass, field
from typing import Dict, Iterable, Optional

from .config import BotConfig, MacroStep
from .state import GameState


@dataclass
class MgbaBridge:
    """Manages the TCP connection with the Lua bridge."""

    config: BotConfig
    _sock: Optional[socket.socket] = field(default=None, init=False)
    _reader: Optional[socket.SocketIO] = field(default=None, init=False)
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False)

    def connect(self) -> None:
        if self._sock:
            return
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((self.config.host, self.config.port))
        self._sock = sock
        self._reader = sock.makefile("r")

    def close(self) -> None:
        with self._lock:
            if self._reader:
                try:
                    self._reader.close()
                except OSError:
                    pass
                self._reader = None
            if self._sock:
                try:
                    self._sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self._sock.close()
                self._sock = None

    # ------------------------------------------------------------------
    # Command helpers
    # ------------------------------------------------------------------

    def send_buttons(self, buttons: Iterable[str]) -> None:
        payload = {"type": "input", "buttons": list(buttons)}
        self._send(payload)

    def send_macro(self, steps: Iterable[MacroStep]) -> None:
        payload = {"type": "macro", "steps": [step.serialize() for step in steps]}
        self._send(payload)

    def reset_input(self) -> None:
        self._send({"type": "reset"})

    # ------------------------------------------------------------------
    # Receiving state --------------------------------------------------
    # ------------------------------------------------------------------

    def receive_state(self) -> Optional[GameState]:
        if not self._reader:
            return None
        line = self._reader.readline()
        if not line:
            return None
        message = json.loads(line)
        if message.get("type") != "state":
            return None
        return GameState(message["data"])

    # ------------------------------------------------------------------

    def _send(self, payload: Dict) -> None:
        if not self._sock:
            raise RuntimeError("Bridge is not connected")
        data = json.dumps(payload) + "\n"
        with self._lock:
            self._sock.sendall(data.encode("utf-8"))
