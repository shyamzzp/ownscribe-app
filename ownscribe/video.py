"""Optional video capture during a live session (ffmpeg / avfoundation).

Records a whole display and/or a camera to mp4 alongside the transcript. Window-
level capture is not supported here (that needs ScreenCaptureKit); use a display.

Requires Screen Recording permission for your terminal app (System Settings >
Privacy & Security > Screen Recording) for display capture, and Camera
permission for camera capture.
"""

from __future__ import annotations

import re
import shutil
import signal
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

import click

_SCREEN_RE = re.compile(r"\[(\d+)\]\s+Capture screen (\d+)")
_DEVICE_RE = re.compile(r"\[(\d+)\]\s+(.+)")


@dataclass
class AVDevices:
    # avfoundation video-device index -> label
    screens: dict[int, int] = field(default_factory=dict)   # display number -> av index
    cameras: list[tuple[int, str]] = field(default_factory=list)  # (av index, label)


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def list_devices() -> AVDevices:
    """Parse `ffmpeg -f avfoundation -list_devices` into screens and cameras."""
    devs = AVDevices()
    if not ffmpeg_available():
        return devs
    proc = subprocess.run(
        ["ffmpeg", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
        capture_output=True, text=True,
    )
    out = proc.stderr
    in_video = False
    for line in out.splitlines():
        if "AVFoundation video devices:" in line:
            in_video = True
            continue
        if "AVFoundation audio devices:" in line:
            in_video = False
            continue
        if not in_video:
            continue
        m_screen = _SCREEN_RE.search(line)
        if m_screen:
            av_index = int(m_screen.group(1))
            display_num = int(m_screen.group(2))
            devs.screens[display_num] = av_index
            continue
        m_dev = _DEVICE_RE.search(line)
        if m_dev and "Capture screen" not in line:
            devs.cameras.append((int(m_dev.group(1)), m_dev.group(2).strip()))
    return devs


def _spawn(av_index: int, out_path: Path, framerate: int) -> subprocess.Popen | None:
    """Start an ffmpeg avfoundation capture for one video device index."""
    cmd = [
        "ffmpeg", "-y",
        "-f", "avfoundation",
        "-framerate", str(framerate),
        "-capture_cursor", "1",
        "-i", f"{av_index}:none",     # video only; ownscribe handles audio
        "-c:v", "h264_videotoolbox",
        "-pix_fmt", "yuv420p",
        str(out_path),
    ]
    try:
        return subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,      # so we can send 'q' to finalize
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            process_group=0,
        )
    except Exception as exc:  # noqa: BLE001
        click.echo(f"Video capture failed to start (av {av_index}): {exc}", err=True)
        return None


class VideoCapture:
    """Manages ffmpeg processes for optional display/camera capture."""

    def __init__(self, framerate: int = 30) -> None:
        self._framerate = framerate
        self._procs: list[tuple[str, subprocess.Popen]] = []
        self.outputs: list[Path] = []

    def start(self, out_dir: Path, screen: int | None, camera: int | None) -> list[str]:
        """Start requested captures. Returns human-readable status messages."""
        msgs: list[str] = []
        if screen is None and camera is None:
            return msgs
        if not ffmpeg_available():
            return ["Video off: ffmpeg not found."]

        devs = list_devices()

        if screen is not None:
            av = devs.screens.get(screen)
            if av is None:
                msgs.append(f"Video off: display {screen} not found "
                            f"(available: {sorted(devs.screens)}).")
            else:
                out = out_dir / "recording-screen.mp4"
                p = _spawn(av, out, self._framerate)
                if p:
                    self._procs.append(("screen", p))
                    self.outputs.append(out)
                    msgs.append(f"Recording display {screen} -> {out.name}")

        if camera is not None:
            cams = devs.cameras
            if camera < 0 or camera >= len(cams):
                labels = ", ".join(f"{i}:{n}" for i, (_, n) in enumerate(cams))
                msgs.append(f"Video off: camera {camera} not found (available: {labels}).")
            else:
                av = cams[camera][0]
                out = out_dir / "recording-camera.mp4"
                p = _spawn(av, out, self._framerate)
                if p:
                    self._procs.append(("camera", p))
                    self.outputs.append(out)
                    msgs.append(f"Recording camera '{cams[camera][1]}' -> {out.name}")

        return msgs

    @property
    def active(self) -> bool:
        return any(p.poll() is None for _, p in self._procs)

    def stop(self) -> list[str]:
        """Finalize mp4s. ffmpeg writes the moov atom on 'q' / SIGINT."""
        msgs: list[str] = []
        for kind, p in self._procs:
            if p.poll() is None:
                try:
                    if p.stdin:
                        p.stdin.write(b"q")
                        p.stdin.flush()
                except Exception:  # noqa: BLE001
                    pass
                try:
                    p.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    p.send_signal(signal.SIGINT)
                    try:
                        p.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        p.terminate()
                        p.wait()
            # Report failures from stderr tail.
            if p.returncode not in (0, 255) and p.stderr:  # 255 = interrupted, ok
                tail = p.stderr.read().decode(errors="replace").strip().splitlines()[-1:]
                if tail:
                    msgs.append(f"{kind} capture: {tail[0]}")
        return msgs
