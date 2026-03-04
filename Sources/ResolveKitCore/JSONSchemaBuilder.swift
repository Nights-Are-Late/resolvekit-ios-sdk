import Foundation

/// Maps Swift type names (as strings) to JSON Schema type strings.
/// Used by the @ResolveKit macro at compile time to generate inline schema literals.
public enum JSONSchemaBuilder {
    public static func defaultObjectSchema() -> JSONObject {
        [
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([])
        ]
    }

    /// Returns the JSON Schema type string for a given Swift type name.
    /// Returns nil for unmappable types (arrays/optionals are handled separately by the macro).
    public static func jsonSchemaType(for swiftType: String) -> String? {
        switch swiftType {
        case "String": return "string"
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return "integer"
        case "Float", "Double", "CGFloat": return "number"
        case "Bool": return "boolean"
        default: return nil
        }
    }
}
