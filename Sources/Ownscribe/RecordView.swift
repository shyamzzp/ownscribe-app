import SwiftUI

struct RecordView: View {
    @EnvironmentObject var recorder: Recorder
    @ObservedObject var store: MeetingStore
    @State private var showLog = false

    private let models = ["tiny", "base", "small", "medium", "large-v3"]
    private let templates = ["meeting", "lecture", "brief"]

    var body: some View {
        VStack(spacing: 16) {
            header

            if !CLI.isInstalled {
                notInstalledBanner
            }

            statusCard

            if recorder.phase == .idle || recorder.phase == .failed {
                optionsCard
            }

            controls

            if recorder.phase == .done, let dir = recorder.lastMeetingDir {
                resultCard(dir: dir)
            }

            if showLog {
                logView
            }

            Spacer()
        }
        .padding(20)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ownscribe").font(.title2).bold()
                Text("Local meeting transcription & summary")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation { showLog.toggle() }
            } label: {
                Label("Log", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
        }
    }

    private var notInstalledBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("ownscribe CLI not found. Install with `uv tool install 'ownscribe[all]'`.")
                .font(.callout)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusCard: some View {
        VStack(spacing: 10) {
            switch recorder.phase {
            case .recording:
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 12, height: 12)
                        .opacity(0.9)
                        .overlay(Circle().stroke(.red.opacity(0.4), lineWidth: 6).scaleEffect(1.4))
                    Text("Recording").font(.headline)
                    Spacer()
                    Text(recorder.elapsedString)
                        .font(.system(.title2, design: .monospaced))
                }
            case .processing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(recorder.statusLine).font(.callout)
                    Spacer()
                }
            case .done:
                Label("Done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed:
                Label(recorder.statusLine.isEmpty ? "Failed" : recorder.statusLine,
                      systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle:
                Text("Ready to record system audio.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var optionsCard: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Text("Whisper model").gridColumnAlignment(.trailing)
                Picker("", selection: $recorder.model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 160)
            }
            GridRow {
                Text("Summary template").gridColumnAlignment(.trailing)
                Picker("", selection: $recorder.template) {
                    ForEach(templates, id: \.self) { Text($0.capitalizedFirst).tag($0) }
                }.labelsHidden().frame(width: 160)
                    .disabled(!recorder.summarize)
            }
            GridRow {
                Text("Device (optional)").gridColumnAlignment(.trailing)
                TextField("system audio", text: $recorder.device)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
            }
            GridRow {
                Text("Options").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Summarize", isOn: $recorder.summarize)
                    Toggle("Capture microphone too", isOn: $recorder.mic)
                    Toggle("Speaker diarization (needs HF token)", isOn: $recorder.diarize)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch recorder.phase {
            case .idle, .failed, .done:
                Button {
                    recorder.reset()
                    recorder.start()
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!CLI.isInstalled)
            case .recording:
                Button(role: .destructive) {
                    recorder.stop()
                } label: {
                    Label("Stop & Transcribe", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .processing:
                Button {
                } label: {
                    Label("Processing…", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(true)
            }
        }
    }

    private func resultCard(dir: URL) -> some View {
        let meeting = Meeting(
            id: dir.lastPathComponent, url: dir, date: Date(),
            title: dir.lastPathComponent
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest result").font(.headline)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }.buttonStyle(.link)
            }
            if let summary = try? String(contentsOf: meeting.summaryURL, encoding: .utf8) {
                ScrollView {
                    MarkdownText(markdown: summary)
                }
                .frame(maxHeight: 200)
            } else if meeting.hasTranscript {
                Text("Transcript ready (no summary).").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var logView: some View {
        ScrollView {
            Text(recorder.log.isEmpty ? "(no output yet)" : recorder.log)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: 140)
        .padding(8)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.green)
    }
}
