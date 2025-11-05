"""BizHawk emulator launcher abstraction."""

from __future__ import annotations

import logging
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence

_LOGGER = logging.getLogger(__name__)


@dataclass
class BizHawkLauncher:
    """Launch BizHawk with a ROM and optional Lua automation script."""

    executable_path: Path

    def build_command(
        self,
        *,
        rom_path: Path,
        lua_script: Path,
        extra_args: Sequence[str] | None = None,
    ) -> List[str]:
        """Construct the command used to start BizHawk.

        Args:
            rom_path: Path to the Game Boy Advance ROM to load.
            lua_script: Path to the Lua script executed on startup.
            extra_args: Additional command-line arguments passed verbatim.

        Returns:
            A list of command tokens ready for subprocess execution.
        """

        command = [str(self.executable_path), f"--lua={lua_script}", str(rom_path)]
        if extra_args:
            command.extend(extra_args)
        return command

    def launch(
        self,
        *,
        rom_path: Path,
        lua_script: Path,
        extra_args: Sequence[str] | None = None,
        wait: bool = False,
    ) -> subprocess.Popen:
        """Spawn a BizHawk process configured with automation hooks.

        Args:
            rom_path: Path to the Game Boy Advance ROM to load.
            lua_script: Path to the Lua automation entry point.
            extra_args: Additional command-line arguments passed verbatim.
            wait: When ``True`` the call blocks until the emulator exits.

        Returns:
            The :class:`subprocess.Popen` handle for the BizHawk process.
        """

        command = self.build_command(rom_path=rom_path, lua_script=lua_script, extra_args=extra_args)
        _LOGGER.info("Launching BizHawk: %s", " ".join(shlex.quote(part) for part in command))

        process = subprocess.Popen(command)
        if wait:
            process.wait()
        return process


__all__ = ["BizHawkLauncher"]
