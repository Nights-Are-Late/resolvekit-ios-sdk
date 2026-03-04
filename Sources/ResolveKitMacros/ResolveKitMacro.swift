import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct ResolveKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ResolveKitMacro.self
    ]
}

/// `@ResolveKit(name:description:timeout:)` — generates Input struct, JSON schema, and dispatch glue.
public struct ResolveKitMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro: generate stored properties + Input struct + invoke()

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Only applies to structs
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: ResolveKitMacroMessage("@ResolveKit can only be applied to a struct", id: "struct_only", severity: .error)
            ))
            return []
        }

        // Parse macro arguments: name:, description:, timeout:
        guard let args = node.arguments?.as(LabeledExprListSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: ResolveKitMacroMessage("@ResolveKit requires name: and description: arguments", id: "missing_args", severity: .error)
            ))
            return []
        }

        var nameValue: String?
        var descriptionValue: String?
        var timeoutValue: String = "nil"
        var requiresApprovalValue: String = "true"

        for arg in args {
            let label = arg.label?.text
            switch label {
            case "name":
                nameValue = stringLiteralValue(from: arg.expression)
            case "description":
                descriptionValue = stringLiteralValue(from: arg.expression)
            case "timeout":
                // Could be an integer literal or nil
                if let intLit = arg.expression.as(IntegerLiteralExprSyntax.self) {
                    timeoutValue = intLit.literal.text
                } else if arg.expression.is(NilLiteralExprSyntax.self) {
                    timeoutValue = "nil"
                }
            case "requiresApproval":
                if let boolLit = arg.expression.as(BooleanLiteralExprSyntax.self) {
                    requiresApprovalValue = boolLit.literal.text
                }
            default:
                break
            }
        }

        guard let name = nameValue else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: ResolveKitMacroMessage("@ResolveKit requires a 'name' string literal argument", id: "missing_name", severity: .error)
            ))
            return []
        }
        guard let desc = descriptionValue else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: ResolveKitMacroMessage("@ResolveKit requires a 'description' string literal argument", id: "missing_description", severity: .error)
            ))
            return []
        }

        // Find the perform() method
        guard let performFunc = findPerformMethod(in: declaration) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: ResolveKitMacroMessage("@ResolveKit requires a 'perform(...)' method", id: "missing_perform", severity: .error)
            ))
            return []
        }

        let params = extractParameters(from: performFunc)
        let returnType = extractReturnType(from: performFunc)

        // Build Input struct members
        let inputProperties = params.map { (paramName, paramType) in
            "    public let \(paramName): \(paramType)"
        }.joined(separator: "\n")

        // Build JSON schema
        let schemaProperties = params.map { (paramName, paramType) in
            let schemaExpr = jsonSchemaExpression(for: paramType)
            return "            \"\(paramName)\": .object(\(schemaExpr))"
        }.joined(separator: ",\n")
        let schemaPropertiesLiteral = schemaProperties.isEmpty ? "[:]" : "[\n\(schemaProperties)\n        ]"

        // Only non-optional params are required
        let requiredList = params.compactMap { (paramName, paramType) in
            paramType.hasSuffix("?") ? nil : ".string(\"\(paramName)\")"
        }.joined(separator: ", ")

        // Build invoke() body: decode each param from arguments, call perform, encode result
        let performArgs = params.map { (paramName, paramType) in
            let coerce = coercionExpression(for: paramType, key: paramName)
            return "            \(paramName): \(coerce)"
        }.joined(separator: ",\n")

        let encodeOutput: String
        if returnType == "Void" || returnType == "()" {
            encodeOutput = """
                    _ = try await Self().perform(\n\(performArgs)\n            )
                            return .null
            """
        } else {
            encodeOutput = """
                    let output = try await Self().perform(\n\(performArgs)\n            )
                            return try _resolveKitEncode(output)
            """
        }

        var decls: [DeclSyntax] = []

        decls.append(
            """
            public static let resolveKitName: String = \(literal: name)
            """
        )
        decls.append(
            """
            public static let resolveKitDescription: String = \(literal: desc)
            """
        )

        if timeoutValue == "nil" {
            decls.append(
                """
                public static let resolveKitTimeoutSeconds: Int? = nil
                """
            )
        } else {
            decls.append(
                """
                public static let resolveKitTimeoutSeconds: Int? = \(raw: timeoutValue)
                """
            )
        }

        decls.append(
            """
            public static let resolveKitRequiresApproval: Bool = \(raw: requiresApprovalValue)
            """
        )

        // Input struct
        let inputStructSource: DeclSyntax = """
        public struct Input: Codable, Sendable {
        \(raw: inputProperties)
        }
        """
        decls.append(inputStructSource)

        // parametersSchema
        let schemaSource: DeclSyntax = """
        public static let resolveKitParametersSchema: JSONObject = [
            "type": .string("object"),
            "properties": .object(\(raw: schemaPropertiesLiteral)),
            "required": .array([\(raw: requiredList)])
        ]
        """
        decls.append(schemaSource)

        // invoke()
        let invokeSource: DeclSyntax = """
        public static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
            do {
                \(raw: encodeOutput)
            } catch {
                throw ResolveKitFunctionError.invalidArguments(error.localizedDescription)
            }
        }
        """
        decls.append(invokeSource)

        return decls
    }

    // MARK: - ExtensionMacro: add AnyResolveKitFunction conformance

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let ext: DeclSyntax = """
        extension \(type): AnyResolveKitFunction {}
        """
        guard let extDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
        return [extDecl]
    }

    // MARK: - Helpers

    private static func stringLiteralValue(from expr: ExprSyntax) -> String? {
        guard let strLit = expr.as(StringLiteralExprSyntax.self),
              let segment = strLit.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }

    private static func findPerformMethod(in declaration: some DeclGroupSyntax) -> FunctionDeclSyntax? {
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self),
               funcDecl.name.text == "perform" {
                return funcDecl
            }
        }
        return nil
    }

    private static func extractParameters(from funcDecl: FunctionDeclSyntax) -> [(String, String)] {
        funcDecl.signature.parameterClause.parameters.compactMap { param in
            let name = param.firstName.text
            let type = param.type.trimmedDescription
            // Skip context parameter (ResolveKitFunctionContext)
            if type.contains("ResolveKitFunctionContext") { return nil }
            if name == "_" {
                guard let second = param.secondName?.text else { return nil }
                return (second, type)
            }
            return (name, type)
        }
    }

    private static func extractReturnType(from funcDecl: FunctionDeclSyntax) -> String {
        funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"
    }

    /// Returns a Swift source expression (a JSONObject literal) representing the JSON Schema
    /// for the given Swift type. Inserted verbatim into the generated resolveKitParametersSchema.
    ///
    /// Handles recursively:
    ///   - Primitives: String, Bool, Int*, Double/Float → correct JSON Schema types
    ///   - Arrays [T] → {"type":"array","items":{...}} with recursive element schema
    ///   - Dictionaries [K:V] → {"type":"object"} (structure unknown at compile time)
    ///   - Optional T? → same schema as T (optionality expressed via `required` array)
    ///   - Nested Codable structs / enums / other → {"type":"object"}
    private static func jsonSchemaExpression(for swiftType: String) -> String {
        // Strip optional — optionality is expressed via the `required` array, not the type schema
        let base = swiftType.hasSuffix("?") ? String(swiftType.dropLast()) : swiftType

        // Array [T] or dictionary [K: V]
        if base.hasPrefix("[") && base.hasSuffix("]") {
            let inner = String(base.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.contains(":") {
                // Dictionary — generic object, structure not knowable at compile time
                return "[\"type\": .string(\"object\")]"
            }
            // Array — recurse so [[Int]] → array of array of integer
            let itemsExpr = jsonSchemaExpression(for: inner)
            return "[\"type\": .string(\"array\"), \"items\": .object(\(itemsExpr))]"
        }

        switch base {
        case "String":
            return "[\"type\": .string(\"string\")]"
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            return "[\"type\": .string(\"integer\")]"
        case "Float", "Double", "CGFloat":
            return "[\"type\": .string(\"number\")]"
        case "Bool":
            return "[\"type\": .string(\"boolean\")]"
        default:
            // Nested Codable struct, enum, Date, URL, etc. — emit as object
            return "[\"type\": .string(\"object\")]"
        }
    }

    /// Generates a Swift expression to extract and coerce a parameter from the arguments JSONObject.
    private static func coercionExpression(for swiftType: String, key: String) -> String {
        let isOptional = swiftType.hasSuffix("?")
        let base = isOptional ? String(swiftType.dropLast()) : swiftType

        let extraction: String
        switch base {
        case "Bool":
            extraction = "TypeResolver.coerceBool(arguments[\"\(key)\"] ?? .null) ?? false"
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            extraction = "TypeResolver.coerceInt(arguments[\"\(key)\"] ?? .null) ?? 0"
        case "Float", "Double", "CGFloat":
            extraction = "TypeResolver.coerceDouble(arguments[\"\(key)\"] ?? .null) ?? 0.0"
        case "String":
            extraction = "TypeResolver.coerceString(arguments[\"\(key)\"] ?? .null) ?? \"\""
        default:
            // For complex types, decode via Codable round-trip through JSONValue
            extraction = "try _resolveKitDecode(\(base).self, from: arguments[\"\(key)\"] ?? .null)"
        }

        if isOptional {
            return "arguments[\"\(key)\"] == nil ? nil : \(extraction)"
        }
        return extraction
    }
}

// MARK: - Diagnostic message helper

private struct ResolveKitMacroMessage: DiagnosticMessage {
    let message: String
    let id: String
    let severity: DiagnosticSeverity

    init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.id = id
        self.severity = severity
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ResolveKitMacros", id: id)
    }
}
