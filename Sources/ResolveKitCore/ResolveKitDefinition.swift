import Foundation

public struct ResolveKitDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let parametersSchema: JSONObject
    public let timeoutSeconds: Int?
    public let requiresApproval: Bool
    public let availability: ResolveKitAvailability?
    public let source: String?
    public let packName: String?

    public init(
        name: String,
        description: String,
        parametersSchema: JSONObject,
        timeoutSeconds: Int?,
        requiresApproval: Bool = true,
        availability: ResolveKitAvailability? = nil,
        source: String? = nil,
        packName: String? = nil
    ) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
        self.timeoutSeconds = timeoutSeconds
        self.requiresApproval = requiresApproval
        self.availability = availability
        self.source = source
        self.packName = packName
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parametersSchema = "parameters_schema"
        case timeoutSeconds = "timeout_seconds"
        case requiresApproval = "requires_approval"
        case availability
        case source
        case packName = "pack_name"
    }
}

public struct ResolveKitAvailability: Codable, Sendable, Equatable {
    public let platforms: [String]?
    public let minOSVersion: String?
    public let maxOSVersion: String?
    public let minAppVersion: String?
    public let maxAppVersion: String?

    public init(
        platforms: [String]? = nil,
        minOSVersion: String? = nil,
        maxOSVersion: String? = nil,
        minAppVersion: String? = nil,
        maxAppVersion: String? = nil
    ) {
        self.platforms = platforms
        self.minOSVersion = minOSVersion
        self.maxOSVersion = maxOSVersion
        self.minAppVersion = minAppVersion
        self.maxAppVersion = maxAppVersion
    }

    enum CodingKeys: String, CodingKey {
        case platforms
        case minOSVersion = "min_os_version"
        case maxOSVersion = "max_os_version"
        case minAppVersion = "min_app_version"
        case maxAppVersion = "max_app_version"
    }
}
