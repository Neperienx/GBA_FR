from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence

try:  # Python 3.11+
    import tomllib  # type: ignore[attr-defined]
except ModuleNotFoundError as exc:  # pragma: no cover - handled at runtime
    raise SystemExit(
        "Python 3.11 or newer is required (missing 'tomllib')."
    ) from exc

from automation import (
    BotConfig,
    BridgeMode,
    EncounterLogger,
    MgbaBridge,
    ShinyHunterBot,
)
from automation.config import MacroStep


PROJECT_ROOT = Path(__file__).resolve().parent


@dataclass
class EmulatorConfig:
    """Configuration describing how to launch the emulator."""

    enabled: bool = True
    executable: Optional[Path] = None
    rom: Optional[Path] = None
    lua_source: Optional[Path] = None
    lua_destination: Optional[Path] = None
    working_directory: Optional[Path] = None
    extra_args: Sequence[str] = ()
    copy_lua: bool = True
    apply_bridge_args: bool = True
    boot_wait_seconds: float = 0.0


@dataclass
class RuntimeConfig:
    """Options that control the runtime behaviour of the bot."""

    poll_interval: float = 0.05
    connect_timeout: float = 30.0
    connect_retry_interval: float = 1.0


@dataclass
class LauncherConfig:
    """Aggregated configuration returned by :func:`load_config`."""

    emulator: EmulatorConfig
    bot: BotConfig
    runtime: RuntimeConfig


# ---------------------------------------------------------------------------
# Configuration loading
# ---------------------------------------------------------------------------


def load_config(path: Path) -> LauncherConfig:
    """Load the TOML configuration describing the launcher setup."""

    if not path.is_file():
        raise FileNotFoundError(f"Configuration file not found: {path}")

    with path.open("rb") as handle:
        data = tomllib.load(handle)

    base_dir = path.parent

    bridge_cfg = data.get("bridge", {})
    host = str(bridge_cfg.get("host", "127.0.0.1"))
    port = int(bridge_cfg.get("port", 8765))
    mode_raw = str(bridge_cfg.get("mode", BridgeMode.PYTHON_CLIENT.value))
    bridge_mode = BridgeMode.from_string(mode_raw)

    bot_cfg = data.get("bot", {})
    runtime = RuntimeConfig(
        poll_interval=float(bot_cfg.get("poll_interval", 0.05)),
        connect_timeout=float(bot_cfg.get("connect_timeout", 30.0)),
        connect_retry_interval=float(bot_cfg.get("connect_retry_interval", 1.0)),
    )

    log_path = _resolve_path(base_dir, bot_cfg.get("log_path", "logs/encounters.log"))
    pp_threshold = int(bot_cfg.get("pp_threshold", 4))
    pp_moves = tuple(int(value) for value in bot_cfg.get("pp_recovery_moves", [0]))
    to_grass = _parse_macro(bot_cfg.get("to_grass_macro", ()))
    to_center = _parse_macro(bot_cfg.get("to_center_macro", ()))

    bot = BotConfig(
        host=host,
        port=port,
        bridge_mode=bridge_mode,
        encounter_log_path=log_path,
        to_grass_macro=to_grass,
        to_center_macro=to_center,
        pp_threshold=pp_threshold,
        pp_recovery_moves=pp_moves,
    )

    emulator_cfg = _parse_emulator_config(data.get("emulator", {}), base_dir)

    return LauncherConfig(emulator=emulator_cfg, bot=bot, runtime=runtime)


def _parse_emulator_config(raw: dict, base_dir: Path) -> EmulatorConfig:
    emulator = EmulatorConfig()
    if not raw:
        return emulator

    emulator.enabled = bool(raw.get("enabled", True))
    emulator.executable = _resolve_path(base_dir, raw.get("path"))
    emulator.rom = _resolve_path(base_dir, raw.get("rom"))
    lua_source = raw.get("lua_source", "lua/automation_bridge.lua")
    emulator.lua_source = _resolve_path(base_dir, lua_source) if lua_source else None
    emulator.lua_destination = _resolve_path(base_dir, raw.get("lua_destination"))
    emulator.working_directory = _resolve_path(base_dir, raw.get("working_directory"))
    emulator.extra_args = tuple(str(arg) for arg in raw.get("extra_args", ()))
    emulator.copy_lua = bool(raw.get("copy_lua", True))
    emulator.apply_bridge_args = bool(raw.get("apply_bridge_args", True))
    emulator.boot_wait_seconds = float(raw.get("boot_wait_seconds", 0.0))
    return emulator


def _resolve_path(base: Path, value: Optional[str]) -> Optional[Path]:
    if value is None:
        return None
    expanded = os.path.expandvars(value)
    path = Path(expanded).expanduser()
    if not path.is_absolute():
        path = (base / path).resolve()
    return path


def _parse_macro(raw_steps: Iterable[dict]) -> Sequence[MacroStep]:
    steps: List[MacroStep] = []
    for index, entry in enumerate(raw_steps):
        try:
            duration = int(entry["duration"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"Invalid macro duration at step {index}") from exc
        buttons = entry.get("buttons", [])
        if isinstance(buttons, str):
            buttons_list = [buttons]
        elif isinstance(buttons, Iterable):
            buttons_list = [str(button) for button in buttons]
        else:
            raise ValueError(f"Invalid macro buttons at step {index}")
        steps.append(MacroStep(duration=duration, buttons=buttons_list))
    return tuple(steps)


# ---------------------------------------------------------------------------
# Runtime helpers
# ---------------------------------------------------------------------------


def copy_lua_script(emulator: EmulatorConfig) -> None:
    if not emulator.copy_lua:
        return
    if not emulator.lua_source or not emulator.lua_destination:
        return

    if not emulator.lua_source.is_file():
        raise FileNotFoundError(f"Lua source script not found: {emulator.lua_source}")

    destination_parent = emulator.lua_destination.parent
    destination_parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(emulator.lua_source, emulator.lua_destination)
    print(f"[launcher] copied Lua script to {emulator.lua_destination}")


def launch_emulator(
    emulator: EmulatorConfig, bot: BotConfig
) -> Optional[subprocess.Popen[bytes]]:
    if not emulator.enabled:
        print("[launcher] emulator launch disabled by configuration")
        return None

    if emulator.executable is None:
        raise ValueError("Emulator path is not configured (see [emulator].path)")
    if not emulator.executable.exists():
        raise FileNotFoundError(f"Emulator executable not found: {emulator.executable}")

    cmd: List[str] = [str(emulator.executable)]
    cmd.extend(str(arg) for arg in emulator.extra_args)

    if emulator.apply_bridge_args and bot.bridge_mode is BridgeMode.PYTHON_SERVER:
        cmd.extend((
            f"--socket_ip={bot.host}",
            f"--socket_port={bot.port}",
        ))
    elif emulator.apply_bridge_args and bot.bridge_mode is not BridgeMode.PYTHON_SERVER:
        print(
            "[launcher] bridge.apply_bridge_args is true but bridge.mode does not require "
            "emulator client arguments; skipping"
        )
    if emulator.lua_destination:
        cmd.append(f"--lua={emulator.lua_destination}")
    if emulator.rom:
        cmd.append(str(emulator.rom))

    print("[launcher] starting emulator:")
    for part in cmd:
        print(f"  {part}")

    env = os.environ.copy()
    env.setdefault("GBA_BRIDGE_HOST", bot.host)
    env.setdefault("GBA_BRIDGE_PORT", str(bot.port))

    process = subprocess.Popen(
        cmd,
        cwd=str(emulator.working_directory) if emulator.working_directory else None,
        env=env,
    )

    if emulator.boot_wait_seconds > 0:
        print(f"[launcher] waiting {emulator.boot_wait_seconds:.1f}s for emulator boot")
        time.sleep(emulator.boot_wait_seconds)

    return process


def run_bot(config: LauncherConfig) -> None:
    bridge = MgbaBridge(config.bot)
    logger = EncounterLogger(config.bot.encounter_log_path)
    bot = ShinyHunterBot(
        bridge=bridge,
        config=config.bot,
        logger=logger,
        poll_interval=config.runtime.poll_interval,
        connect_timeout=config.runtime.connect_timeout,
        connect_retry_interval=config.runtime.connect_retry_interval,
    )
    bot.start()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="One-click launcher for the Fire Red automation bot")
    parser.add_argument(
        "--config",
        type=Path,
        default=PROJECT_ROOT / "config.toml",
        help="Path to TOML configuration file (default: config.toml in project root)",
    )
    parser.add_argument(
        "--no-launch",
        action="store_true",
        help="Skip launching the emulator (useful if it is already running)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(args.config)

    try:
        copy_lua_script(config.emulator)
    except Exception as exc:
        print(f"[launcher][error] {exc}", file=sys.stderr)
        return 1

    process: Optional[subprocess.Popen[bytes]] = None
    try:
        if not args.no_launch:
            process = launch_emulator(config.emulator, config.bot)
        else:
            print("[launcher] --no-launch specified; waiting for manual connection")

        run_bot(config)
        return 0
    except KeyboardInterrupt:
        print("\n[launcher] interrupted; shutting down")
        return 0
    except Exception as exc:
        print(f"[launcher][error] {exc}", file=sys.stderr)
        return 1
    finally:
        if process is not None:
            terminate_process(process)


def terminate_process(process: subprocess.Popen[bytes]) -> None:
    try:
        process.terminate()
        process.wait(timeout=5)
    except Exception:
        process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
