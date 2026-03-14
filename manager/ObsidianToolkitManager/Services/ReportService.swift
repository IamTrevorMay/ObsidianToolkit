import Foundation

struct ReportFile: Identifiable {
    let id: String
    let name: String
    let path: String
    let modified: Date?

    var formattedDate: String {
        guard let modified else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modified)
    }
}

struct ReportService {
    static func listReports(toolkitPath: String) -> [ReportFile] {
        let outputDir = (toolkitPath as NSString).appendingPathComponent("output")
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: outputDir) else {
            return []
        }

        return contents
            .filter { $0.hasSuffix(".md") }
            .compactMap { name -> ReportFile? in
                let fullPath = (outputDir as NSString).appendingPathComponent(name)
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let modified = attrs?[.modificationDate] as? Date

                return ReportFile(
                    id: name,
                    name: name.replacingOccurrences(of: ".md", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized,
                    path: fullPath,
                    modified: modified
                )
            }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    static func parseAuditSummary(toolkitPath: String) -> AuditSummary? {
        let reportPath = (toolkitPath as NSString)
            .appendingPathComponent("output/audit_report.md")

        guard let content = try? String(contentsOfFile: reportPath, encoding: .utf8) else {
            return nil
        }

        var summary = AuditSummary()

        // Parse overview table values
        if let match = content.range(of: #"Markdown files\s*\|\s*(\d+)"#, options: .regularExpression) {
            let line = String(content[match])
            if let num = line.components(separatedBy: "|").last?.trimmingCharacters(in: .whitespaces),
               let val = Int(num) {
                summary.fileCount = val
            }
        }

        if let match = content.range(of: #"Folders\s*\|\s*(\d+)"#, options: .regularExpression) {
            let line = String(content[match])
            if let num = line.components(separatedBy: "|").last?.trimmingCharacters(in: .whitespaces),
               let val = Int(num) {
                summary.folderCount = val
            }
        }

        if let match = content.range(of: #"Total size\s*\|\s*([\d.]+)"#, options: .regularExpression) {
            let line = String(content[match])
            if let num = line.components(separatedBy: "|").last?.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first,
               let val = Double(num) {
                summary.totalSizeMB = val
            }
        }

        if let match = content.range(of: #"Unique tags.*?(\d+)"#, options: .regularExpression) {
            let str = String(content[match])
            if let num = str.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces),
               let val = Int(num) {
                summary.uniqueTags = val
            }
        }

        if let match = content.range(of: #"Broken links.*?(\d+)"#, options: .regularExpression) {
            let str = String(content[match])
            if let num = str.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces),
               let val = Int(num) {
                summary.brokenLinks = val
            }
        }

        if let match = content.range(of: #"Orphaned notes.*?(\d+)"#, options: .regularExpression) {
            let str = String(content[match])
            if let num = str.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces),
               let val = Int(num) {
                summary.orphanedNotes = val
            }
        }

        // Parse generation date
        if let match = content.range(of: #"Generated:\s*(.+)"#, options: .regularExpression) {
            let dateStr = String(content[match])
                .replacingOccurrences(of: "Generated:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "*", with: "")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            summary.generatedAt = formatter.date(from: dateStr)
        }

        return summary
    }
}
