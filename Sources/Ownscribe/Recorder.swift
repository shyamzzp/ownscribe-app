import Foundation
import Combine

/// Drives a single `ownscribe` run: record -> transcribe -> summarize.
/// Recording is stopped by sending SIGINT (the CLI catches it and proceeds
/// to transcription automatically), so one Process spans the whole pipeline.
@MainActor
final class Recorder: ObservableObject {
    enum Phase: Equatable { case idle, recording, processing, done, failed }

    @Published var phase: Phase = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var statusLine: String = ""
    @Published var log: String = ""
    @Published var lastMeetingDir: URL?

    // Options bound from the UI.
    @Published var model: String = "base"
    @Published var template: String = "meeting"
    @Published var diarize: Bool = false
    @Published var mic: Bool = false
    @Published var summarize: Bool = true
    @Published var device: String = ""

    // Video capture (ScreenCaptureKit) — optional, ownscribe is audio-only.
    @Published var videoEnabled: Bool = false
    @Published var videoSources: [CaptureSource] = []
    @Published var selectedSourceID: String?
    @Published var videoStatus: String = ""

    private let video = VideoRecorder()
    private var tempVideoURL: URL?

    private var process: Process?
    private var timer: Timer?
    private var startDate: Date?

    var isBusy: Bool { phase == .recording || phase == .processing }

    func start() {
        guard !isBusy else { return }
        guard CLI.isInstalled else {
            statusLine = "ownscribe CLI not found at ~/.local/bin/ownscribe"
            phase = .failed
            return
        }

        log = ""
        statusLine = "Recording…"
        elapsed = 0
        phase = .recording
        startDate = Date()

        var args: [String] = []
        if !summarize { args.append("--no-summarize") }
        if diarize { args.append("--diarize") }
        if mic { args.append("--mic") }
        if !model.isEmpty { args += ["--model", model] }
        if summarize && !template.isEmpty { args += ["--template", template] }
        if !device.isEmpty { args += ["--device", device] }
        // Disable auto-stop on silence; the user controls stop from the UI.
        args += ["--silence-timeout", "0"]

        let p = CLI.process(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingest(text) }
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.finish(status: proc.terminationStatus) }
        }

        do {
            try p.run()
        } catch {
            statusLine = "Failed to launch: \(error.localizedDescription)"
            phase = .failed
            return
        }
        process = p

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.startDate, self.phase == .recording else { return }
                self.elapsed = Date().timeIntervalSince(s)
            }
        }

        // Start optional window/display video capture in parallel with audio.
        if videoEnabled, let sid = selectedSourceID,
           let source = videoSources.first(where: { $0.id == sid }) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("ownscribe-video-\(UUID().uuidString).mp4")
            tempVideoURL = tmp
            videoStatus = "Recording video…"
            Task {
                do {
                    try await video.start(source: source, to: tmp)
                } catch {
                    await MainActor.run {
                        self.videoStatus = "Video failed: \(error.localizedDescription)"
                        self.tempVideoURL = nil
                    }
                }
            }
        } else {
            videoStatus = ""
        }
    }

    /// Fetch shareable windows/displays for the source picker.
    func refreshVideoSources() {
        Task {
            let sources = await VideoRecorder.availableSources()
            await MainActor.run {
                self.videoSources = sources
                if self.selectedSourceID == nil { self.selectedSourceID = sources.first?.id }
            }
        }
    }

    /// Stop recording. SIGINT -> CLI transcribes/summarizes, then exits.
    func stop() {
        guard phase == .recording else { return }
        timer?.invalidate(); timer = nil
        phase = .processing
        statusLine = "Transcribing… (first run downloads models — this can take a while)"
        process?.interrupt() // SIGINT

        // Stop video capture (if any); keep the finalized file for finish() to move.
        if videoEnabled, tempVideoURL != nil {
            videoStatus = "Finalizing video…"
            Task {
                let url = await video.stop()
                await MainActor.run {
                    self.tempVideoURL = url
                    self.videoStatus = url == nil
                        ? (self.video.lastError.map { "Video error: \($0)" } ?? "No video captured.")
                        : "Video ready."
                }
            }
        }
    }

    /// Hard-cancel everything (used when quitting).
    func cancel() {
        timer?.invalidate(); timer = nil
        process?.interrupt()
        process?.terminate()
        process = nil
        if videoEnabled, tempVideoURL != nil {
            Task { _ = await video.stop() }
        }
        if isBusy { phase = .idle }
    }

    private func ingest(_ text: String) {
        log += text
        // Keep log bounded.
        if log.count > 20_000 { log = String(log.suffix(20_000)) }

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.contains("Transcript saved to") {
                statusLine = "Summarizing…"
            } else if line.contains("Summary saved to") {
                statusLine = "Finishing up…"
            } else if line.lowercased().contains("error") {
                statusLine = line
            }
        }
    }

    private func finish(status: Int32) {
        process?.standardOutput = nil
        timer?.invalidate(); timer = nil
        process = nil

        // Newest meeting directory is the result of this run.
        lastMeetingDir = MeetingStore.newestMeetingDir()

        // Move the captured video into the meeting directory as recording.mp4.
        if let src = tempVideoURL, let dir = lastMeetingDir {
            let dest = dir.appendingPathComponent("recording.mp4")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                videoStatus = "Video saved to meeting folder."
            } catch {
                videoStatus = "Video kept at \(src.path) (move failed)."
            }
            tempVideoURL = nil
        }

        if status == 0 {
            phase = .done
            statusLine = "Done."
        } else if phase == .idle {
            // Cancelled by user before completion.
        } else {
            phase = .failed
            if statusLine.isEmpty || statusLine.hasPrefix("Transcrib") || statusLine.hasPrefix("Summariz") {
                statusLine = "ownscribe exited with code \(status). See log."
            }
        }
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
        statusLine = ""
        elapsed = 0
        log = ""
        lastMeetingDir = nil
    }

    var elapsedString: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
