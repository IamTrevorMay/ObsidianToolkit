import Foundation

struct VaultBrowserService {
    static func buildTree(at vaultPath: String, excludedFolders: [String] = []) -> [VaultNode] {
        let url = URL(fileURLWithPath: vaultPath)
        return buildChildren(at: url, relativeTo: vaultPath, excludedFolders: Set(excludedFolders))
    }

    private static func buildChildren(
        at url: URL,
        relativeTo root: String,
        excludedFolders: Set<String>
    ) -> [VaultNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var nodes: [VaultNode] = []

        for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = itemURL.lastPathComponent
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir && excludedFolders.contains(name) {
                continue
            }

            let relativePath = itemURL.path.replacingOccurrences(of: root + "/", with: "")

            if isDir {
                let children = buildChildren(at: itemURL, relativeTo: root, excludedFolders: excludedFolders)
                nodes.append(VaultNode(
                    id: relativePath,
                    name: name,
                    path: itemURL.path,
                    isDirectory: true,
                    children: children
                ))
            } else {
                nodes.append(VaultNode(
                    id: relativePath,
                    name: name,
                    path: itemURL.path,
                    isDirectory: false,
                    children: nil
                ))
            }
        }

        return nodes
    }

    static func readFile(at path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    static func fileMetadata(at path: String) -> FileMetadata? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }

        return FileMetadata(
            size: attrs[.size] as? Int64 ?? 0,
            created: attrs[.creationDate] as? Date,
            modified: attrs[.modificationDate] as? Date
        )
    }
}

struct FileMetadata {
    let size: Int64
    let created: Date?
    let modified: Date?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
