import Foundation
import Combine

struct Meeting: Identifiable, Hashable {
    let id: String          // directory name
    let url: URL
    let date: Date
    let title: String

    var transcriptURL: URL { url.appendingPathComponent("transcript.md") }
    var summaryURL: URL { url.appendingPathComponent("summary.md") }
    var recordingURL: URL { url.appendingPathComponent("recording.wav") }
    var videoURL: URL { url.appendingPathComponent("recording.mp4") }

    var hasSummary: Bool { FileManager.default.fileExists(atPath: summaryURL.path) }
    var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }
    var hasVideo: Bool { FileManager.default.fileExists(atPath: videoURL.path) }
}

@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []

    init() { reload() }

    func reload() {
        meetings = Self.scan()
    }

    static func scan() -> [Meeting] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: CLI.outputDir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Meeting] = []
        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let name = url.lastPathComponent
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date.distantPast
            out.append(Meeting(
                id: name,
                url: url,
                date: parseDate(name) ?? mod,
                title: parseTitle(name)
            ))
        }
        return out.sorted { $0.date > $1.date }
    }

    static func newestMeetingDir() -> URL? {
        scan().first?.url
    }

    /// Directory names look like `2026-07-13_2133_some-title-slug`.
    private static func parseDate(_ name: String) -> Date? {
        let parts = name.split(separator: "_")
        guard parts.count >= 2 else { return nil }
        let stamp = "\(parts[0])_\(parts[1])"
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: stamp)
    }

    private static func parseTitle(_ name: String) -> String {
        let parts = name.split(separator: "_")
        guard parts.count >= 3 else { return "Untitled meeting" }
        let slug = parts[2...].joined(separator: "_")
        let words = slug.split(separator: "-").map(String.init)
        return words.joined(separator: " ").capitalizedFirst
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
