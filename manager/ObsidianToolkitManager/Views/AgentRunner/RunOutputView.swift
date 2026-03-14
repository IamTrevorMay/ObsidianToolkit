import SwiftUI

struct RunOutputView: View {
    let lines: [AgentRunnerView.OutputLine]
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isRunning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.isStderr ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minHeight: 150)
    }
}
