import Foundation

/// Thread-safe actor-based registry for ResolveKit functions.
/// Functions are registered by type and dispatched by name.
public actor ResolveKitRegistry {
    public static let shared = ResolveKitRegistry()

    private var byName: [String: any AnyResolveKitFunction.Type] = [:]

    public init() {}

    /// Register a function type. Throws if the name is already taken.
    public func register(_ type: any AnyResolveKitFunction.Type) throws {
        let name = type.resolveKitName
        guard byName[name] == nil else {
            throw ResolveKitFunctionError.duplicateFunctionName(name)
        }
        byName[name] = type
    }

    /// Register multiple function types at once.
    public func register(_ types: [any AnyResolveKitFunction.Type]) throws {
        for type in types {
            try register(type)
        }
    }

    /// All registered function definitions, sorted by name.
    public var definitions: [ResolveKitDefinition] {
        byName.values.map { $0.definition }.sorted { $0.name < $1.name }
    }

    /// Look up a function type by name.
    public func resolve(_ name: String) -> (any AnyResolveKitFunction.Type)? {
        byName[name]
    }

    /// Dispatch a tool call by function name.
    /// - Security: validates the function name exists before execution.
    public func dispatch(
        functionName: String,
        arguments: JSONObject,
        context: ResolveKitFunctionContext
    ) async throws -> JSONValue {
        guard let function = byName[functionName] else {
            throw ResolveKitFunctionError.unknownFunction(functionName)
        }
        return try await function.invoke(arguments: arguments, context: context)
    }

    /// Remove all registered functions (useful for testing).
    public func reset() {
        byName.removeAll()
    }
}
