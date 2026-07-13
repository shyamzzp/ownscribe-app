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

- **Video** (optional): capture a selected window or display via ScreenCaptureKit
  while recording. Saved as `recording.mp4` in the meeting folder, playable from
  the History tab. `ownscribe` itself is audio-only — this is added by the app.

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

- [x] Optional window/screen **video** capture via ScreenCaptureKit, saved
      alongside the audio recording.
- [ ] Mux captured video + audio into a single file.
- [ ] Device picker populated from `ownscribe devices`.
- [ ] Live elapsed-audio level meter while recording.

## Notes

- Built as an SPM executable bundled into `Ownscribe.app`. On macOS 26 with
  Swift 6.2+, SwiftUI SPM executables can hard-crash in `isCurrentExecutor`
  (ambiguous main-actor executor). The bundle sets
  `SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE=legacy` via `LSEnvironment`
  in Info.plist to avoid it.

## License

MIT.
