import Foundation

/// Coerces LLM-returned JSON values to the expected Swift types.
/// LLMs sometimes return `1` for `true`, `3.0` for `3`, or `"true"` for `true`.
public enum TypeResolver {
    /// Coerce a JSONValue to Bool.
    /// Accepts: .bool, .number (0 = false, nonzero = true), .string ("true"/"false"/"1"/"0")
    public static func coerceBool(_ value: JSONValue) -> Bool? {
        switch value {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// Coerce a JSONValue to Int.
    /// Accepts: .number (truncates), .string (parses), .bool (1/0)
    public static func coerceInt(_ value: JSONValue) -> Int? {
        switch value {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    /// Coerce a JSONValue to Double.
    public static func coerceDouble(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let n): return n
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1.0 : 0.0
        default: return nil
        }
    }

    /// Coerce a JSONValue to String.
    public static func coerceString(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s): return s
        case .number(let n):
            if n == Double(Int(n)) { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// Normalize a JSONObject so that Bool-typed fields aren't returned as numbers.
    /// This is a best-effort pass — actual type coercion happens during Codable decode.
    public static func normalize(_ object: JSONObject) -> JSONObject {
        object.mapValues { normalize($0) }
    }

    private static func normalize(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let obj): return .object(normalize(obj))
        case .array(let arr): return .array(arr.map { normalize($0) })
        default: return value
        }
    }
}
