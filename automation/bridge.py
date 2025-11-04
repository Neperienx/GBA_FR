"""Networking layer that talks to the Lua automation bridge."""

from __future__ import annotations

import json
import socket
import threading
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, Iterable, Optional

from .config import BotConfig, BridgeMode, MacroStep
from .state import GameState


class ConnectionState(Enum):
    """Internal connection state."""

    DISCONNECTED = "disconnected"
    LISTENING = "listening"
    CONNECTED = "connected"


@dataclass
class MgbaBridge:
    """Manages the TCP connection with the Lua bridge."""

    config: BotConfig
    _sock: Optional[socket.socket] = field(default=None, init=False)
    _reader: Optional[socket.SocketIO] = field(default=None, init=False)
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False)
    _server: Optional[socket.socket] = field(default=None, init=False)
    _state: ConnectionState = field(default=ConnectionState.DISCONNECTED, init=False)

    # ------------------------------------------------------------------
    # Lifecycle --------------------------------------------------------
    # ------------------------------------------------------------------

    def connect(self) -> None:
        if self._sock:
            return
        if self.config.bridge_mode is BridgeMode.PYTHON_CLIENT:
            self._connect_as_client()
        else:
            self._connect_as_server()

    def _connect_as_client(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect((self.config.host, self.config.port))
        except OSError:
            sock.close()
            raise
        self._sock = sock
        self._reader = sock.makefile("r")
        self._state = ConnectionState.CONNECTED

    def _connect_as_server(self) -> None:
        server = self._ensure_server()
        try:
            client, _ = server.accept()
        except (BlockingIOError, InterruptedError) as exc:
            raise OSError("bridge accept interrupted") from exc
        except socket.timeout as exc:
            raise OSError("bridge waiting for emulator connection") from exc
        self._sock = client
        self._reader = client.makefile("r")
        self._state = ConnectionState.CONNECTED

    def _ensure_server(self) -> socket.socket:
        if self._server and self._state is not ConnectionState.DISCONNECTED:
            return self._server
        if not self._server:
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind((self.config.host, self.config.port))
            server.listen(1)
            server.settimeout(1.0)
            self._server = server
        self._state = ConnectionState.LISTENING
        return self._server

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
            if self._server:
                try:
                    self._server.close()
                except OSError:
                    pass
                self._server = None
            self._state = ConnectionState.DISCONNECTED

    # ------------------------------------------------------------------
    # Command helpers --------------------------------------------------
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
