import Foundation

struct ConfigService {
    static func load(from toolkitPath: String) -> VaultConfig? {
        let url = URL(fileURLWithPath: toolkitPath)
            .appendingPathComponent("config.json")

        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        return try? decoder.decode(VaultConfig.self, from: data)
    }

    static func save(_ config: VaultConfig, to toolkitPath: String) throws {
        let url = URL(fileURLWithPath: toolkitPath)
            .appendingPathComponent("config.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
