import Foundation

// MARK: - Context

public struct ResolveKitFunctionContext: Sendable {
    public let sessionID: String
    public let requestID: String?

    public init(sessionID: String, requestID: String?) {
        self.sessionID = sessionID
        self.requestID = requestID
    }
}

// MARK: - Type-erased protocol (used by registry)

public protocol AnyResolveKitFunction: Sendable {
    static var resolveKitName: String { get }
    static var resolveKitDescription: String { get }
    static var resolveKitTimeoutSeconds: Int? { get }
    static var resolveKitRequiresApproval: Bool { get }
    static var resolveKitParametersSchema: JSONObject { get }

    static var definition: ResolveKitDefinition { get }
    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue
}

public extension AnyResolveKitFunction {
    static var resolveKitRequiresApproval: Bool { true }

    static var definition: ResolveKitDefinition {
        ResolveKitDefinition(
            name: resolveKitName,
            description: resolveKitDescription,
            parametersSchema: resolveKitParametersSchema,
            timeoutSeconds: resolveKitTimeoutSeconds,
            requiresApproval: resolveKitRequiresApproval
        )
    }
}

public enum ResolveKitPlatform: String, Codable, Sendable, CaseIterable {
    case ios
    case macos
    case tvos
    case watchos
    case visionos
}

public extension ResolveKitPlatform {
    static var current: ResolveKitPlatform {
        #if os(iOS)
        return .ios
        #elseif os(macOS)
        return .macos
        #elseif os(tvOS)
        return .tvos
        #elseif os(watchOS)
        return .watchos
        #elseif os(visionOS)
        return .visionos
        #else
        return .ios
        #endif
    }
}

public protocol ResolveKitFunctionPack: Sendable {
    static var packName: String { get }
    static var supportedPlatforms: [ResolveKitPlatform] { get }
    static var functions: [any AnyResolveKitFunction.Type] { get }
}

public extension ResolveKitFunctionPack {
    static var supportedPlatforms: [ResolveKitPlatform] { ResolveKitPlatform.allCases }
}

// MARK: - Macro-generated code helpers (Foundation lives here, not in generated files)

/// Encode any Encodable value to JSONValue. Called by `@ResolveKit`-generated `invoke()` methods.
public func _resolveKitEncode<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

/// Decode a Swift value from a JSONValue. Called by `@ResolveKit`-generated `invoke()` methods.
public func _resolveKitDecode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}

// MARK: - Errors

public enum ResolveKitFunctionError: Error, LocalizedError, Sendable {
    case invalidArguments(String)
    case duplicateFunctionName(String)
    case unknownFunction(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let reason):
            return "Invalid function arguments: \(reason)"
        case .duplicateFunctionName(let name):
            return "Duplicate function name: \(name)"
        case .unknownFunction(let name):
            return "Unknown function: \(name)"
        }
    }
}
