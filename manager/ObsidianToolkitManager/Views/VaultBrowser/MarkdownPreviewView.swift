import SwiftUI

struct MarkdownPreviewView: View {
    let content: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(renderedContent)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    private var renderedContent: AttributedString {
        MarkdownRenderer.renderFull(content)
    }
}
