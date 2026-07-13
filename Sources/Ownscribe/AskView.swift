import SwiftUI

struct AskView: View {
    @State private var question = ""
    @State private var answer = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask across your meetings").font(.title3).bold()
            Text("Runs `ownscribe ask` over your saved notes. Uses the local summarization model, so the first query may load the model.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                TextField("e.g. What did we decide about the Q2 demo?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(run)
                Button(action: run) {
                    if running { ProgressView().controlSize(.small) }
                    else { Text("Ask") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(running || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            ScrollView {
                if answer.isEmpty {
                    Text(running ? "Thinking…" : "Answers appear here.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(markdown: answer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
        .padding(20)
    }

    private func run() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !running else { return }
        running = true
        answer = ""
        Task.detached {
            let result = CLI.runBlocking(["ask", q])
            await MainActor.run {
                answer = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if answer.isEmpty { answer = "_(no output)_" }
                running = false
            }
        }
    }
}
