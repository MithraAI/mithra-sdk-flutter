import Foundation
import MithraAnalytics

/// Conversions between Flutter's standard message codec types and the types the
/// Narya SDK takes.
///
/// This file is pure translation: it never calls the SDK and holds no state.
enum NaryaCodec {

    /// Narrows a channel argument map into the SDK's `Properties` type.
    static func properties(from source: Any?) -> Properties? {
        guard let map = source as? [String: Any] else { return nil }
        return map
    }

    /// Converts an `InAppJSONValue` payload into a standard-codec value.
    static func plainValue(from value: InAppJSONValue) -> Any? {
        switch value {
        case .null:
            return nil
        case .bool(let flag):
            return flag
        case .number(let number):
            // Integral values cross the channel as Int so a Dart `int` field
            // decodes without a lossy double round trip.
            if number == number.rounded(), abs(number) < 9_007_199_254_740_992 {
                return Int(number)
            }
            return number
        case .string(let text):
            return text
        case .array(let elements):
            return elements.map { plainValue(from: $0) }
        case .object(let fields):
            var result: [String: Any?] = [:]
            for (key, nested) in fields {
                result[key] = plainValue(from: nested)
            }
            return result
        }
    }

    /// Converts a decoded push payload into the `userInfo` shape the SDK's
    /// push-tracking APIs take.
    static func userInfo(from source: Any?) -> [AnyHashable: Any] {
        guard let map = source as? [String: Any] else { return [:] }
        return map
    }

    /// Converts a system `userInfo` dictionary into the `[String: Any]` shape
    /// the standard message codec sends to Dart.
    ///
    /// Built key by key on purpose. An `as? [String: Any]` cast is all or
    /// nothing: a single non-`String` key - and APNs payloads do carry them,
    /// from providers and from `mutable-content` rewrites - collapses the whole
    /// payload to an empty map, and Dart then sees a non-null payload with no
    /// `mithra_message_id` and no deep link to route.
    static func payload(from userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(userInfo.count)
        for (key, value) in userInfo {
            guard let name = key as? String else { continue }
            result[name] = value
        }
        return result
    }
}
