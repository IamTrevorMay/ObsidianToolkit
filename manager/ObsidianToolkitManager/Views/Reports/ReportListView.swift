import SwiftUI

struct ReportListView: View {
    @Environment(AppState.self) private var appState
    @State private var reports: [ReportFile] = []
    @State private var selectedReport: ReportFile?

    var body: some View {
        HSplitView {
            List(reports, selection: Binding(
                get: { selectedReport?.id },
                set: { id in
                    selectedReport = reports.first { $0.id == id }
                }
            )) { report in
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.name)
                        .font(.body)
                    Text(report.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(report.id)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, maxWidth: 280)

            if let report = selectedReport {
                ReportDetailView(report: report, toolkitPath: appState.toolkitPath)
            } else {
                ContentUnavailableView(
                    "Select a Report",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a report from the list to view it.")
                )
            }
        }
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem {
                Button {
                    loadReports()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            if let report = selectedReport {
                ToolbarItem {
                    Button {
                        NSWorkspace.shared.selectFile(report.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show in Finder")
                }
            }
        }
        .onAppear {
            loadReports()
        }
    }

    private func loadReports() {
        reports = ReportService.listReports(toolkitPath: appState.toolkitPath)
    }
}
