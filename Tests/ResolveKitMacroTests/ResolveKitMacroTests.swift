import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import ResolveKitMacros
@testable import ResolveKitAuthoring

let testMacros: [String: Macro.Type] = [
    "ResolveKit": ResolveKitMacro.self
]

@Suite("@ResolveKit macro expansion")
struct ResolveKitMacroTests {

    @Test("Expands correctly for a simple function")
    func simpleExpansion() {
        assertMacroExpansion(
            """
            @ResolveKit(name: "set_lights", description: "Turn lights on or off", timeout: 30)
            struct SetLights: ResolveKitFunction {
                func perform(room: String, on: Bool) async throws -> Bool {
                    return true
                }
            }
            """,
            expandedSource: """
            struct SetLights: ResolveKitFunction {
                func perform(room: String, on: Bool) async throws -> Bool {
                    return true
                }
                public static let resolveKitName: String = "set_lights"
                public static let resolveKitDescription: String = "Turn lights on or off"
                public static let resolveKitTimeoutSeconds: Int? = 30
                public static let resolveKitRequiresApproval: Bool = true
                public struct Input: Codable, Sendable {
                    public let room: String
                    public let on: Bool
                }
                public static let resolveKitParametersSchema: JSONObject = [
                    "type": .string("object"),
                    "properties": .object([
                        "room": .object(["type": .string("string")]),
                        "on": .object(["type": .string("boolean")])
                    ]),
                    "required": .array([.string("room"), .string("on")])
                ]
                public static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
                    do {
                        let output = try await Self().perform(
                            room: TypeResolver.coerceString(arguments["room"] ?? .null) ?? "",
                            on: TypeResolver.coerceBool(arguments["on"] ?? .null) ?? false
                        )
                        return try _resolveKitEncode(output)
                    } catch {
                        throw ResolveKitFunctionError.invalidArguments(error.localizedDescription)
                    }
                }
            }

            extension SetLights: AnyResolveKitFunction {}
            """,
            macros: testMacros
        )
    }

    @Test("Array param gets items schema, optional param excluded from required")
    func arrayAndOptionalParams() {
        assertMacroExpansion(
            """
            @ResolveKit(name: "demo", description: "Demo")
            struct Demo: ResolveKitFunction {
                func perform(tags: [String], limit: Int?) async throws -> String { "" }
            }
            """,
            expandedSource: """
            struct Demo: ResolveKitFunction {
                func perform(tags: [String], limit: Int?) async throws -> String { "" }
                public static let resolveKitName: String = "demo"
                public static let resolveKitDescription: String = "Demo"
                public static let resolveKitTimeoutSeconds: Int? = nil
                public static let resolveKitRequiresApproval: Bool = true
                public struct Input: Codable, Sendable {
                    public let tags: [String]
                    public let limit: Int?
                }
                public static let resolveKitParametersSchema: JSONObject = [
                    "type": .string("object"),
                    "properties": .object([
                        "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "limit": .object(["type": .string("integer")])
                    ]),
                    "required": .array([.string("tags")])
                ]
                public static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
                    do {
                        let output = try await Self().perform(
                            tags: try _resolveKitDecode([String].self, from: arguments["tags"] ?? .null),
                            limit: arguments["limit"] == nil ? nil : TypeResolver.coerceInt(arguments["limit"] ?? .null) ?? 0
                        )
                        return try _resolveKitEncode(output)
                    } catch {
                        throw ResolveKitFunctionError.invalidArguments(error.localizedDescription)
                    }
                }
            }

            extension Demo: AnyResolveKitFunction {}
            """,
            macros: testMacros
        )
    }

    @Test("Error on class instead of struct")
    func errorOnClass() {
        assertMacroExpansion(
            """
            @ResolveKit(name: "foo", description: "bar")
            class Foo: ResolveKitFunction {
                func perform() async throws -> String { "" }
            }
            """,
            expandedSource: """
            class Foo: ResolveKitFunction {
                func perform() async throws -> String { "" }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@ResolveKit can only be applied to a struct", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }
}
