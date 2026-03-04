import Foundation

public typealias JSONObject = [String: JSONValue]

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object(JSONObject)
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public extension JSONValue {
    static func from(any value: Any) -> JSONValue {
        switch value {
        case let v as String:
            return .string(v)
        case let v as Bool:
            return .bool(v)
        case let v as Int:
            return .number(Double(v))
        case let v as Double:
            return .number(v)
        case let v as [String: Any]:
            return .object(v.mapValues { from(any: $0) })
        case let v as [Any]:
            return .array(v.map { from(any: $0) })
        default:
            return .null
        }
    }

    func asAny() -> Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let object):
            return object.mapValues { $0.asAny() }
        case .array(let values):
            return values.map { $0.asAny() }
        case .null:
            return NSNull()
        }
    }
}
