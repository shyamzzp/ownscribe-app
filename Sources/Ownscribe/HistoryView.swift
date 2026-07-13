import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: MeetingStore
    @State private var selection: Meeting.ID?

    var body: some View {
        NavigationSplitView {
            List(store.meetings, selection: $selection) { meeting in
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title).font(.body).lineLimit(1)
                    Text(meeting.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(meeting.id)
            }
            .navigationTitle("Meetings")
            .toolbar {
                Button { store.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } detail: {
            if let id = selection, let meeting = store.meetings.first(where: { $0.id == id }) {
                MeetingDetail(meeting: meeting)
            } else {
                ContentUnavailableView("No meeting selected",
                                       systemImage: "doc.text",
                                       description: Text("Pick a meeting to view its summary and transcript."))
            }
        }
    }
}

struct MeetingDetail: View {
    let meeting: Meeting
    enum Pane: String, CaseIterable { case summary = "Summary", transcript = "Transcript" }
    @State private var pane: Pane = .summary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.title3).bold()
                    Text(meeting.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([meeting.url])
                }.buttonStyle(.link)
            }

            Picker("", selection: $pane) {
                ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                MarkdownText(markdown: content)
                    .padding(.trailing, 8)
            }
        }
        .padding(16)
    }

    private var content: String {
        let url = pane == .summary ? meeting.summaryURL : meeting.transcriptURL
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            return text
        }
        return pane == .summary ? "_No summary for this meeting._" : "_No transcript found._"
    }
}
