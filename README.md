# Ownscribe.app

A native macOS SwiftUI front-end for [`ownscribe`](https://github.com/paberr/ownscribe) —
fully local meeting transcription and summarization. This app is a GUI wrapper: it
shells out to the installed `ownscribe` CLI, so all recording, transcription (WhisperX),
and summarization (local LLM) still happen entirely on your machine.

## Features

- **Record** system audio (optionally + microphone) with a one-click Start/Stop.
  Stopping sends `SIGINT`, which the CLI catches to run transcription → summarization.
- **History** browser: lists past meetings from `~/ownscribe`, renders summary and
  transcript markdown side by side.
- **Ask** across all your meeting notes (`ownscribe ask`).
- **Settings**: edit the `ownscribe` TOML config in-app.

> Note: `ownscribe` is **audio-only**. Recording *video* of a window is a planned
> addition (ScreenCaptureKit) tracked in this repo — see Roadmap.

## Requirements

- macOS 14.2+
- The `ownscribe` CLI installed and on `~/.local/bin`:
  ```bash
  uv tool install 'ownscribe[all]'
  ```
- Swift 5.9+ / Xcode command line tools (to build).

## Build

```bash
bash bundle.sh release      # produces Ownscribe.app (ad-hoc signed)
open Ownscribe.app
```

For a plain debug run without bundling:

```bash
swift run
```

On first recording, macOS will prompt for **Screen Recording** and (if enabled)
**Microphone** permission — grant them to `Ownscribe.app`.

## Roadmap

- [ ] Optional window/screen **video** capture via ScreenCaptureKit, saved
      alongside the audio recording.
- [ ] Device picker populated from `ownscribe devices`.
- [ ] Live elapsed-audio level meter while recording.

## License

MIT.
