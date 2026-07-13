import SwiftUI

struct SettingsView: View {
    @State private var configText: String = ""
    @State private var loaded = false
    @State private var savedNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configuration").font(.title3).bold()
                Spacer()
                Text(CLI.configPath.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Edits the ownscribe TOML config directly. Applies to future recordings.")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $configText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            HStack {
                Button("Reload", action: load)
                Button("Save", action: save).buttonStyle(.borderedProminent)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([CLI.configPath])
                }
                Spacer()
                if !savedNote.isEmpty {
                    Text(savedNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .onAppear { if !loaded { load(); loaded = true } }
    }

    private func load() {
        configText = (try? String(contentsOf: CLI.configPath, encoding: .utf8))
            ?? "# No config file yet. Save to create one at \(CLI.configPath.path)\n"
        savedNote = ""
    }

    private func save() {
        do {
            let dir = CLI.configPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try configText.write(to: CLI.configPath, atomically: true, encoding: .utf8)
            savedNote = "Saved."
        } catch {
            savedNote = "Save failed: \(error.localizedDescription)"
        }
    }
}
