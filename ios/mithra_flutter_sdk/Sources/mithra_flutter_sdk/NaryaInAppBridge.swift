import Foundation
import MithraAnalytics

/// Encodes the SDK's in-app model types for the Dart side and decodes the enum
/// arguments Dart sends.
///
/// Message HTML is deliberately never encoded: rendering belongs to the native
/// SDK, so Dart receives `hasContent` instead of the markup.
enum NaryaInAppBridge {

    /// Encodes one message for the method or event channel.
    static func encode(_ message: InAppMessage) -> [String: Any?] {
        [
            "messageId": message.messageId,
            "campaignId": message.campaignId,
            "createdAtMillis": millis(from: message.createdAt),
            "expiresAtMillis": message.expiresAt.map { millis(from: $0) },
            "trigger": [
                "type": message.trigger.type.rawValue,
                "eventName": message.trigger.eventName,
            ] as [String: Any?],
            "saveToInbox": message.saveToInbox,
            "inboxMetadata": message.inboxMetadata.map { metadata in
                [
                    "title": metadata.title,
                    "subtitle": metadata.subtitle,
                    "icon": metadata.icon,
                ] as [String: Any?]
            },
            "priorityLevel": message.priorityLevel,
            "read": message.read,
            "jsonOnly": message.jsonOnly,
            "customPayload": message.customPayload.flatMap { NaryaCodec.plainValue(from: $0) },
            "hasContent": message.content != nil,
        ]
    }

    /// Encodes a list of messages.
    static func encodeAll(_ messages: [InAppMessage]) -> [[String: Any?]] {
        messages.map { encode($0) }
    }

    /// Decodes the `NaryaInAppLocation.name` wire value.
    static func decodeLocation(_ source: String?) -> InAppLocation {
        source == "inbox" ? .inbox : .inApp
    }

    /// Decodes the `NaryaInAppDeleteSource.name` wire value.
    static func decodeDeleteSource(_ source: String?) -> InAppDeleteSource {
        switch source {
        case "inboxSwipe": return .inboxSwipe
        case "deleteButton": return .deleteButton
        case "consume": return .consume
        default: return .api
        }
    }

    /// Decodes the `NaryaInAppShowResponse.name` value Dart replies with.
    static func decodeShowResponse(_ source: Any?) -> InAppShowResponse {
        switch source as? String {
        case "skip": return .skip
        case "defer": return .defer
        default: return .show
        }
    }

    private static func millis(from date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}
