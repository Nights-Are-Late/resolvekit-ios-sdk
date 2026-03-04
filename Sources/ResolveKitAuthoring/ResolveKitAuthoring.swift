import Foundation
@_exported import ResolveKitCore

/// Adopt this protocol on your struct, then attach `@ResolveKit` to fill in everything else.
public protocol ResolveKitFunction: Sendable {}

/// Attach to a struct to auto-generate: Input struct, JSON schema, protocol conformance, and dispatch glue.
///
/// ```swift
/// @ResolveKit(name: "set_lights", description: "Turn lights on or off", timeout: 30)
/// struct SetLights: ResolveKitFunction {
///     func perform(room: String, on: Bool) async throws -> Bool {
///         return true
///     }
/// }
/// ```
@attached(member, names: named(resolveKitName), named(resolveKitDescription), named(resolveKitTimeoutSeconds), named(resolveKitRequiresApproval), named(resolveKitParametersSchema), named(Input), named(invoke))
@attached(extension, conformances: AnyResolveKitFunction)
public macro ResolveKit(name: String, description: String, timeout: Int? = nil, requiresApproval: Bool = true) = #externalMacro(module: "ResolveKitMacros", type: "ResolveKitMacro")
