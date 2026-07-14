"""Live (streaming) transcription with folder-grounded question suggestions.

Unlike the batch pipeline (record whole WAV -> transcribe -> summarize), this
captures audio through a sounddevice callback and transcribes fixed windows
with faster-whisper as the meeting runs, emitting transcript lines in real
time. If a context folder is attached, it periodically retrieves the most
relevant passages and asks the local LLM to suggest questions to ask next.

Note on audio source: sounddevice captures an *input* device. Your microphone
works out of the box. To transcribe another party's audio (e.g. a call), pick a
loopback input — on this machine "Microsoft Teams Audio" exposes call audio;
BlackHole/an Aggregate Device works generally. Use `ownscribe devices`.
"""

from __future__ import annotations

import json
import queue
import signal
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import click

from ownscribe.config import Config
from ownscribe.context import Context, load_context, retrieve

_SAMPLE_RATE = 16000
_QUESTION_SYSTEM = (
    "You are an assistant silently helping a participant during a live meeting. "
    "Given the recent transcript and any reference material, suggest 2-3 concise, "
    "specific questions the participant could ask next to clarify gaps or move the "
    "meeting forward. Output only the questions, one per line, no numbering, no preamble."
)


def _emit(kind: str, text: str, *, json_mode: bool, at: float | None = None) -> None:
    """Print an event either as JSONL (machine) or formatted text (human)."""
    if json_mode:
        payload = {"type": kind, "text": text}
        if at is not None:
            payload["t"] = round(at, 1)
        click.echo(json.dumps(payload), nl=True)
        sys.stdout.flush()
        return

    if kind == "transcript":
        stamp = ""
        if at is not None:
            stamp = f"[{int(at) // 60:02d}:{int(at) % 60:02d}] "
        click.echo(f"{stamp}{text}")
    elif kind == "questions":
        click.echo(click.style("\n  ? Suggested questions:", fg="cyan", bold=True))
        for line in text.splitlines():
            line = line.strip().lstrip("-•*0123456789. )").strip()
            if line:
                click.echo(click.style(f"    • {line}", fg="cyan"))
        click.echo("")
    elif kind == "info":
        click.echo(click.style(text, fg="yellow"), err=True)
    sys.stdout.flush()


class _QuestionWorker(threading.Thread):
    """Generates question suggestions off the audio/transcription path."""

    def __init__(self, config: Config, context: Context, json_mode: bool) -> None:
        super().__init__(daemon=True)
        self._config = config
        self._context = context
        self._json = json_mode
        self._transcript = ""
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._summarizer = None
        self._interval = 45.0

    def update_transcript(self, full_text: str) -> None:
        with self._lock:
            self._transcript = full_text

    def stop(self) -> None:
        self._stop.set()

    def run(self) -> None:
        from ownscribe.summarization import create_summarizer

        try:
            self._summarizer = create_summarizer(self._config)
            if not self._summarizer.is_available():
                _emit("info", "Question suggestions off: LLM backend unavailable.",
                      json_mode=self._json)
                return
        except Exception as exc:  # noqa: BLE001
            _emit("info", f"Question suggestions off: {exc}", json_mode=self._json)
            return

        # Wait for some conversation before the first suggestion.
        if self._stop.wait(self._interval):
            self._finish()
            return

        while not self._stop.is_set():
            self._suggest()
            if self._stop.wait(self._interval):
                break
        self._finish()

    def _suggest(self) -> None:
        with self._lock:
            recent = self._transcript[-1800:].strip()
        if len(recent) < 80:
            return  # not enough said yet

        reference = ""
        if not self._context.is_empty:
            hits = retrieve(self._context, recent, k=4)
            reference = "\n\n".join(f"[{h.source}] {h.text}" for h in hits)

        parts = []
        if reference:
            parts.append(f"Reference material:\n{reference}")
        parts.append(f"Recent transcript:\n{recent}")
        parts.append("Suggest questions:")
        try:
            out = self._summarizer.chat(_QUESTION_SYSTEM, "\n\n".join(parts))
        except Exception:  # noqa: BLE001
            return
        if out and out.strip():
            _emit("questions", out.strip(), json_mode=self._json)

    def _finish(self) -> None:
        if self._summarizer is not None:
            try:
                self._summarizer.close()
            except Exception:  # noqa: BLE001
                pass


def run_live(
    config: Config,
    context_folder: str | None = None,
    device: str | None = None,
    chunk_seconds: float = 6.0,
    question_interval: float = 45.0,
    suggest_questions: bool = True,
    json_mode: bool = False,
) -> None:
    """Run live transcription until interrupted (Ctrl+C)."""
    try:
        import numpy as np
        import sounddevice as sd
        from faster_whisper import WhisperModel
    except ImportError as exc:  # noqa: BLE001
        click.echo(f"Error: live mode needs faster-whisper + sounddevice ({exc}).", err=True)
        raise SystemExit(1) from None

    # Attach context folder: retrieval + Whisper priming.
    context = Context(chunks=[], initial_prompt="", hotwords="")
    if context_folder:
        context = load_context(context_folder)
        if context.is_empty:
            _emit("info", f"No readable docs in {context_folder}.", json_mode=json_mode)
        else:
            _emit("info",
                  f"Attached {len(context.chunks)} chunks from {context_folder} "
                  f"({len(context.hotwords.split(',')) if context.hotwords else 0} hotwords).",
                  json_mode=json_mode)
            if not config.transcription.initial_prompt:
                config.transcription.initial_prompt = context.initial_prompt
            if not config.transcription.hotwords:
                config.transcription.hotwords = context.hotwords

    # Output directory (same convention as the batch pipeline).
    base = config.output.resolved_dir
    out_dir = base / datetime.now().strftime("%Y-%m-%d_%H%M")
    out_dir.mkdir(parents=True, exist_ok=True)
    transcript_path = out_dir / "transcript.md"

    # Resolve device index.
    dev_index = None
    if device:
        dev_index = int(device) if device.isdigit() else device

    _emit("info", f"Loading whisper model '{config.transcription.model}'…", json_mode=json_mode)
    model = WhisperModel(config.transcription.model, device="cpu", compute_type="int8")

    audio_q: queue.Queue = queue.Queue()

    def on_audio(indata, frames, time_info, status):  # noqa: ANN001, ARG001
        if status:
            pass  # overflow/underflow — ignore, keep streaming
        audio_q.put(indata[:, 0].copy())

    language = config.transcription.language or None
    initial_prompt = config.transcription.initial_prompt or None
    hotwords = config.transcription.hotwords or None

    stop_event = threading.Event()

    def on_interrupt(sig, frame):  # noqa: ANN001, ARG001
        stop_event.set()

    original = signal.getsignal(signal.SIGINT)
    signal.signal(signal.SIGINT, on_interrupt)

    worker: _QuestionWorker | None = None
    if suggest_questions and config.summarization.enabled:
        worker = _QuestionWorker(config, context, json_mode)
        worker._interval = question_interval
        worker.start()

    transcript_lines: list[str] = []
    full_text = ""
    chunk_samples = int(_SAMPLE_RATE * chunk_seconds)
    buffer = np.empty(0, dtype=np.float32)
    start = time.time()

    _emit("info", "Live transcription started. Press Ctrl+C to stop.", json_mode=json_mode)

    try:
        with sd.InputStream(
            samplerate=_SAMPLE_RATE, channels=1, dtype="int16",
            device=dev_index, callback=on_audio, blocksize=int(_SAMPLE_RATE * 0.5),
        ):
            while not stop_event.is_set():
                try:
                    block = audio_q.get(timeout=0.3)
                except queue.Empty:
                    continue
                buffer = np.concatenate([buffer, block.astype(np.float32) / 32768.0])

                while len(buffer) >= chunk_samples and not stop_event.is_set():
                    window = buffer[:chunk_samples]
                    buffer = buffer[chunk_samples:]
                    at = time.time() - start
                    segments, _ = model.transcribe(
                        window, language=language, beam_size=1,
                        vad_filter=True, initial_prompt=initial_prompt, hotwords=hotwords,
                    )
                    text = "".join(s.text for s in segments).strip()
                    if text:
                        transcript_lines.append(text)
                        full_text = " ".join(transcript_lines)
                        _emit("transcript", text, json_mode=json_mode, at=at)
                        if worker is not None:
                            worker.update_transcript(full_text)
                        transcript_path.write_text(_render_transcript(transcript_lines))
    finally:
        signal.signal(signal.SIGINT, original)
        if worker is not None:
            worker.stop()
            worker.join(timeout=5)

    transcript_path.write_text(_render_transcript(transcript_lines))
    _emit("info", f"\nTranscript saved to {transcript_path}", json_mode=json_mode)

    # Optional final summary using the batch summarizer.
    if config.summarization.enabled and full_text.strip():
        _finalize_summary(config, out_dir, full_text, json_mode)


def _render_transcript(lines: list[str]) -> str:
    body = "\n\n".join(lines)
    return f"# Transcript\n\n{body}\n"


def _finalize_summary(config: Config, out_dir: Path, full_text: str, json_mode: bool) -> None:
    from ownscribe.output.markdown import format_summary
    from ownscribe.pipeline import _generate_title_slug
    from ownscribe.summarization import create_summarizer

    _emit("info", "Summarizing…", json_mode=json_mode)
    try:
        summarizer = create_summarizer(config)
    except Exception as exc:  # noqa: BLE001
        _emit("info", f"Summary skipped: {exc}", json_mode=json_mode)
        return
    try:
        if not summarizer.is_available():
            _emit("info", "Summary skipped: LLM backend unavailable.", json_mode=json_mode)
            return
        summary = summarizer.summarize(full_text)
        (out_dir / "summary.md").write_text(format_summary(summary))
        slug = _generate_title_slug(summary, summarizer)
    finally:
        summarizer.close()

    if slug:
        new_dir = out_dir.parent / f"{out_dir.name}_{slug}"
        try:
            out_dir.rename(new_dir)
            out_dir = new_dir
        except Exception:  # noqa: BLE001
            pass
    _emit("info", f"Summary saved to {out_dir / 'summary.md'}", json_mode=json_mode)
