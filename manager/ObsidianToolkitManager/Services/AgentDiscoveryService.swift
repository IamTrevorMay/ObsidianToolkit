import Foundation

struct AgentDiscoveryService {
    static func loadManifest(toolkitPath: String) -> AgentManifest? {
        let url = URL(fileURLWithPath: toolkitPath)
            .appendingPathComponent("manifest.json")

        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        return try? decoder.decode(AgentManifest.self, from: data)
    }

    static func watchManifest(toolkitPath: String, onChange: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let path = (toolkitPath as NSString).appendingPathComponent("manifest.json")
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )

        source.setEventHandler {
            onChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        return source
    }
}
