import Foundation

struct VaultNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [VaultNode]?

    var fileExtension: String? {
        isDirectory ? nil : (name as NSString).pathExtension
    }

    var isMarkdown: Bool {
        fileExtension?.lowercased() == "md"
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        switch fileExtension?.lowercased() {
        case "md": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "pdf": return "doc.richtext"
        case "json": return "curlybraces"
        default: return "doc"
        }
    }
}
