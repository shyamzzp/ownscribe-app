# ownscribe (fork)

Fully local meeting transcription and summarization CLI — a fork of
[paberr/ownscribe](https://github.com/paberr/ownscribe) that adds:

- **Live transcription** — streaming, real-time transcript as the meeting runs
  (chunked faster-whisper), instead of only batch-after-stop.
- **Folder-grounded question suggestions** — attach a folder of reference docs;
  during the call it retrieves the relevant passages plus the live transcript and
  the local LLM suggests questions to ask next.
- **Vocab priming** — the same folder primes Whisper (`initial_prompt` + hotwords)
  so names/domain terms transcribe correctly.

Everything runs on-device (WhisperX / faster-whisper + local phi-4-mini). No data
leaves the machine.

## Install

```bash
# editable dev install into a uv-managed tool env
uv tool install --force --editable .
# or into a venv
uv pip install -e '.[all]'
```

Requires macOS 14.2+, Python 3.12+, FFmpeg (`brew install ffmpeg`).

## Usage

### Live transcription

```bash
ownscribe live                         # transcribe default mic, live
ownscribe live --device 2              # pick input (see: ownscribe devices)
ownscribe live --context-folder ./docs # ground question suggestions + prime vocab
ownscribe live --no-questions          # transcript only
ownscribe live --model small --json    # bigger model, JSONL output for tooling
ownscribe live --video-screen 0        # also record display 0 -> recording-screen.mp4
ownscribe live --video-camera 0        # also record webcam -> recording-camera.mp4
ownscribe live --video-screen 1 --video-camera 0   # both
```

**Video** capture uses ffmpeg/avfoundation and records a whole **display**
and/or a **camera** (not a single window — that needs ScreenCaptureKit). Files
land in the meeting folder next to the transcript. Display capture needs Screen
Recording permission; camera capture needs Camera permission for your terminal.

Live mode captures an **input device**. Your mic works out of the box. To
transcribe another party (e.g. a call), select a loopback input — e.g.
"Microsoft Teams Audio", BlackHole, or an Aggregate Device. List them with
`ownscribe devices`. Stop with `Ctrl+C`; a transcript (and summary, if enabled)
is written to `~/ownscribe/<timestamp>/`.

**Question suggestions** print every `--question-interval` seconds (default 45):

```
  ? Suggested questions:
    • What's the timeline for the Azure AI demo now that IT review is pending?
    • Who owns the SOW AI phase-one UI updates?
```

### Batch (original behavior)

```bash
ownscribe                    # record system audio -> transcribe -> summarize
ownscribe ask "what did we decide about X?"
ownscribe summarize file.md
ownscribe devices
```

## New CLI surface

| Command / flag | Purpose |
| --- | --- |
| `ownscribe live` | Streaming transcription |
| `--context-folder DIR` | Reference docs for questions + vocab priming |
| `--question-interval N` | Cadence of suggestions (0 disables) |
| `--no-questions` | Transcript only |
| `--json` | Emit JSONL events (`{"type":"transcript"...}`) |
| `--video-screen N` | Also record display N to recording-screen.mp4 (ffmpeg) |
| `--video-camera N` | Also record camera N to recording-camera.mp4 (ffmpeg) |

## Layout

```
ownscribe/
  cli.py            entry point (adds `live`)
  live.py           streaming transcription + question loop   [new]
  context.py        folder retrieval + Whisper priming        [new]
  video.py          optional display/camera capture (ffmpeg)  [new]
  pipeline.py       batch record/transcribe/summarize
  transcription/    WhisperX
  summarization/    local (llama.cpp) / ollama / openai
  search.py         ask across notes
```

## License

MIT (fork; upstream © paberr).
