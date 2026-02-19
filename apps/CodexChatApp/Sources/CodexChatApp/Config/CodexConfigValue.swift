import Foundation
import TOMLKit

enum CodexConfigPathSegment: Hashable, Sendable {
    case key(String)
    case index(Int)

    var display: String {
        switch self {
        case let .key(key):
            key
        case let .index(index):
            "[\(index)]"
        }
    }
}

enum CodexConfigValue: Hashable, Sendable {
    case object([String: CodexConfigValue])
    case array([CodexConfigValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case null

    static func fromTOML(_ value: TOMLValueConvertible) -> CodexConfigValue {
        if let table = value.table {
            var object: [String: CodexConfigValue] = [:]
            for key in table.keys {
                if let child = table[key] {
                    object[key] = fromTOML(child)
                }
            }
            return .object(object)
        }

        if let array = value.array {
            return .array(array.map(fromTOML))
        }

        if let string = value.string {
            return .string(string)
        }

        if let integer = value.int {
            return .integer(integer)
        }

        if let number = value.double {
            return .number(number)
        }

        if let boolean = value.bool {
            return .boolean(boolean)
        }

        return .null
    }

    func toTOMLValue() -> TOMLValueConvertible {
        switch self {
        case let .object(object):
            let table = TOMLTable()
            for key in object.keys.sorted() {
                guard let value = object[key], value != .null else {
                    continue
                }
                table[key] = value.toTOMLValue()
            }
            return table
        case let .array(array):
            let values = array.filter { $0 != .null }.map { $0.toTOMLValue() }
            return TOMLArray(values)
        case let .string(string):
            return string
        case let .integer(integer):
            return integer
        case let .number(number):
            return number
        case let .boolean(boolean):
            return boolean
        case .null:
            return ""
        }
    }

    var objectValue: [String: CodexConfigValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [CodexConfigValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var integerValue: Int? {
        if case let .integer(value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    var booleanValue: Bool? {
        if case let .boolean(value) = self {
            return value
        }
        return nil
    }

    var printableValue: String {
        switch self {
        case let .string(value):
            value
        case let .integer(value):
            String(value)
        case let .number(value):
            String(value)
        case let .boolean(value):
            String(value)
        case .object:
            "{…}"
        case .array:
            "[…]"
        case .null:
            "null"
        }
    }

    func value(at path: [CodexConfigPathSegment]) -> CodexConfigValue? {
        guard let first = path.first else {
            return self
        }

        switch (self, first) {
        case let (.object(object), .key(key)):
            guard let child = object[key] else {
                return nil
            }
            return child.value(at: Array(path.dropFirst()))
        case let (.array(array), .index(index)):
            guard index >= 0, index < array.count else {
                return nil
            }
            return array[index].value(at: Array(path.dropFirst()))
        default:
            return nil
        }
    }

    mutating func setValue(_ newValue: CodexConfigValue?, at path: [CodexConfigPathSegment]) {
        guard let first = path.first else {
            if let newValue {
                self = newValue
            }
            return
        }

        let remaining = Array(path.dropFirst())
        switch first {
        case let .key(key):
            var object: [String: CodexConfigValue] = if case let .object(existing) = self {
                existing
            } else {
                [:]
            }

            if remaining.isEmpty {
                if let newValue {
                    object[key] = newValue
                } else {
                    object.removeValue(forKey: key)
                }
                self = .object(object)
                return
            }

            var child = object[key] ?? Self.containerSeed(for: remaining.first)
            child.setValue(newValue, at: remaining)
            object[key] = child
            self = .object(object)
        case let .index(index):
            guard index >= 0 else {
                return
            }

            var array: [CodexConfigValue] = if case let .array(existing) = self {
                existing
            } else {
                []
            }

            while array.count <= index {
                array.append(.null)
            }

            if remaining.isEmpty {
                if let newValue {
                    array[index] = newValue
                } else if index < array.count {
                    array.remove(at: index)
                }
                self = .array(array)
                return
            }

            var child = array[index]
            if child == .null {
                child = Self.containerSeed(for: remaining.first)
            }
            child.setValue(newValue, at: remaining)
            array[index] = child
            self = .array(array)
        }
    }

    mutating func removeValue(at path: [CodexConfigPathSegment]) {
        setValue(nil, at: path)
    }

    private static func containerSeed(for segment: CodexConfigPathSegment?) -> CodexConfigValue {
        switch segment {
        case .index:
            .array([])
        case .key, .none:
            .object([:])
        }
    }
}
