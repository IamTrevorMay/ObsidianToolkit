import Foundation

struct VaultConfig: Codable, Equatable {
    var vaultPath: String
    var inboxFolder: String
    var outputFolder: String
    var excludedFolders: [String]
    var anthropicApiKeyEnv: String

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
        case inboxFolder = "inbox_folder"
        case outputFolder = "output_folder"
        case excludedFolders = "excluded_folders"
        case anthropicApiKeyEnv = "anthropic_api_key_env"
    }
}
