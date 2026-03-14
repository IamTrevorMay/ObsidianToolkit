import SwiftUI

struct VaultBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var tree: [VaultNode] = []
    @State private var selectedNode: VaultNode?
    @State private var fileContent: String?
    @State private var fileMetadata: FileMetadata?
    @State private var isLoading = true
    @State private var showInspector = true

    var body: some View {
        HSplitView {
            // File tree
            List(selection: Binding(
                get: { selectedNode?.id },
                set: { id in
                    selectedNode = findNode(id: id, in: tree)
                    loadSelectedFile()
                }
            )) {
                OutlineGroup(tree, children: \.children) { node in
                    Label(node.name, systemImage: node.icon)
                        .tag(node.id)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 250, maxWidth: 350)
            .overlay {
                if isLoading {
                    ProgressView("Loading vault...")
                }
            }

            // Content area
            if let node = selectedNode, !node.isDirectory {
                VStack(spacing: 0) {
                    if let content = fileContent, node.isMarkdown {
                        MarkdownPreviewView(content: content)
                    } else if let content = fileContent {
                        ScrollView {
                            Text(content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
                .frame(minWidth: 400)
                .inspector(isPresented: $showInspector) {
                    FileMetadataView(node: node, metadata: fileMetadata)
                        .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
                }
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text",
                    description: Text("Choose a file from the vault tree to preview it.")
                )
            }
        }
        .navigationTitle("Vault Browser")
        .toolbar {
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
            }
            ToolbarItem {
                Button {
                    loadTree()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            loadTree()
        }
    }

    private func loadTree() {
        guard let config = appState.config else {
            isLoading = false
            return
        }
        isLoading = true
        Task.detached {
            let nodes = VaultBrowserService.buildTree(
                at: config.vaultPath,
                excludedFolders: config.excludedFolders
            )
            await MainActor.run {
                tree = nodes
                isLoading = false
            }
        }
    }

    private func loadSelectedFile() {
        guard let node = selectedNode, !node.isDirectory else {
            fileContent = nil
            fileMetadata = nil
            return
        }
        fileContent = VaultBrowserService.readFile(at: node.path)
        fileMetadata = VaultBrowserService.fileMetadata(at: node.path)
    }

    private func findNode(id: String?, in nodes: [VaultNode]) -> VaultNode? {
        guard let id else { return nil }
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findNode(id: id, in: children) {
                return found
            }
        }
        return nil
    }
}

struct FileMetadataView: View {
    let node: VaultNode
    let metadata: FileMetadata?

    var body: some View {
        Form {
            Section("File Info") {
                LabeledContent("Name", value: node.name)
                if let ext = node.fileExtension {
                    LabeledContent("Type", value: ext.uppercased())
                }
                if let meta = metadata {
                    LabeledContent("Size", value: meta.formattedSize)
                    if let created = meta.created {
                        LabeledContent("Created") {
                            Text(created, style: .date)
                        }
                    }
                    if let modified = meta.modified {
                        LabeledContent("Modified") {
                            Text(modified, style: .date)
                        }
                    }
                }
            }

            Section("Path") {
                Text(node.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
