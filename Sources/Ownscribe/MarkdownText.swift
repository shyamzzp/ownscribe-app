import SwiftUI

/// Lightweight block-level markdown renderer good enough for ownscribe
/// summaries/transcripts (headings, bullets, paragraphs). SwiftUI's built-in
/// AttributedString markdown only handles inline styling, so we parse blocks.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [Block] {
        markdown.components(separatedBy: "\n").map(Block.parse)
    }

    private struct Block: Identifiable {
        let id = UUID()
        let view: AnyView

        static func parse(_ raw: String) -> Block {
            let line = raw.trimmingCharacters(in: .whitespaces)

            func inline(_ s: String) -> Text {
                if let attr = try? AttributedString(
                    markdown: s,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) { return Text(attr) }
                return Text(s)
            }

            if line.isEmpty {
                return Block(view: AnyView(Spacer().frame(height: 2)))
            }
            if line.hasPrefix("### ") {
                return Block(view: AnyView(inline(String(line.dropFirst(4)))
                    .font(.headline)))
            }
            if line.hasPrefix("## ") {
                return Block(view: AnyView(inline(String(line.dropFirst(3)))
                    .font(.title3).bold().padding(.top, 4)))
            }
            if line.hasPrefix("# ") {
                return Block(view: AnyView(inline(String(line.dropFirst(2)))
                    .font(.title2).bold().padding(.top, 4)))
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                return Block(view: AnyView(
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        inline(content)
                    }.padding(.leading, 8)
                ))
            }
            return Block(view: AnyView(inline(line)))
        }
    }
}
