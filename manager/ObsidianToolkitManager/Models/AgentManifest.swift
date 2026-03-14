import Foundation

struct AgentManifest: Codable {
    let version: Int
    let agents: [AgentDefinition]
}

struct AgentDefinition: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let module: String
    let icon: String
    let parameters: [ParameterDefinition]
    let examples: [AgentExample]
}

struct ParameterDefinition: Codable, Identifiable {
    let name: String
    let flag: String
    let type: ParameterType
    let required: Bool
    let defaultValue: ParameterDefault?
    let description: String
    let suggestions: [String]?
    let mutuallyExclusiveGroup: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, flag, type, required
        case defaultValue = "default"
        case description, suggestions
        case mutuallyExclusiveGroup = "mutually_exclusive_group"
    }
}

enum ParameterType: String, Codable {
    case string
    case bool
    case filePath = "file_path"
    case stringArray = "string_array"
    case int
    case float
}

enum ParameterDefault: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case float(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
            return
        }
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
            return
        }
        if let doubleVal = try? container.decode(Double.self) {
            self = .float(doubleVal)
            return
        }
        if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
            return
        }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .int(let val): try container.encode(val)
        case .float(let val): try container.encode(val)
        case .null: try container.encodeNil()
        }
    }
}

struct AgentExample: Codable, Identifiable {
    let description: String
    let args: [String]

    var id: String { description }
}
