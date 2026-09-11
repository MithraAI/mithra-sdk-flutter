package com.mithra.flutter.sdk

import com.mithra.sdk.kotlin.android.Analytics
import com.mithra.sdk.kotlin.inapp.InAppDeleteSource
import com.mithra.sdk.kotlin.inapp.InAppLocation
import com.mithra.sdk.kotlin.inapp.InAppManager
import com.mithra.sdk.kotlin.inapp.InAppMessage
import com.mithra.sdk.kotlin.inapp.InAppShowResponse
import com.mithra.sdk.kotlin.inapp.InboxMetadata

/**
 * Encodes the SDK's in-app model types for the Dart side and decodes the enum
 * arguments Dart sends.
 *
 * Message HTML is deliberately never encoded: rendering belongs to the native
 * SDK, so Dart receives `hasContent` instead of the markup.
 */
internal object NaryaInAppBridge {

    /** Encodes one message for the method or event channel. */
    fun encode(message: InAppMessage): Map<String, Any?> = mapOf(
        "messageId" to message.messageId,
        "campaignId" to message.campaignId,
        "createdAtMillis" to message.createdAtMillis,
        "expiresAtMillis" to message.expiresAtMillis,
        "trigger" to mapOf(
            "type" to message.trigger.type.wireValue,
            "eventName" to message.trigger.eventName,
        ),
        "saveToInbox" to message.saveToInbox,
        "inboxMetadata" to message.inboxMetadata?.let { encodeInboxMetadata(it) },
        "priorityLevel" to message.priorityLevel,
        "read" to message.read,
        "jsonOnly" to message.jsonOnly,
        "customPayload" to NaryaCodec.fromJsonObject(message.customPayload),
        "hasContent" to (message.content != null),
    )

    /** Encodes a list of messages. */
    fun encodeAll(messages: List<InAppMessage>): List<Map<String, Any?>> =
        messages.map { encode(it) }

    private fun encodeInboxMetadata(metadata: InboxMetadata): Map<String, Any?> = mapOf(
        "title" to metadata.title,
        // The SDK models an absent subtitle as an empty string; Dart models it
        // as null so an inbox row can omit the line entirely.
        "subtitle" to metadata.subtitle.takeIf { it.isNotEmpty() },
        "icon" to metadata.icon,
    )

    /** Decodes the `NaryaInAppLocation.name` wire value. */
    fun decodeLocation(source: String?): InAppLocation = when (source) {
        "inbox" -> InAppLocation.INBOX
        else -> InAppLocation.IN_APP
    }

    /** Decodes the `NaryaInAppDeleteSource.name` wire value. */
    fun decodeDeleteSource(source: String?): InAppDeleteSource = when (source) {
        "inboxSwipe" -> InAppDeleteSource.INBOX_SWIPE
        "deleteButton" -> InAppDeleteSource.DELETE_BUTTON
        "consume" -> InAppDeleteSource.CONSUME
        else -> InAppDeleteSource.API
    }

    /** Decodes the `NaryaInAppShowResponse.name` value Dart replies with. */
    fun decodeShowResponse(source: Any?): InAppShowResponse = when (source) {
        "skip" -> InAppShowResponse.SKIP
        "defer" -> InAppShowResponse.DEFER
        else -> InAppShowResponse.SHOW
    }

    /**
     * The in-app manager of [analytics], created on first use, or `null` when
     * this configuration switched in-app messaging off.
     *
     * Creating the manager is what starts the feature - the store preload, the
     * sync and the display pump all hang off it - so the `enabled` flag has to
     * be honoured here rather than after the fact. A manager that native host
     * code already created is handed back regardless of the flag: the flag
     * decides whether the bridge *starts* the feature, not whether it may talk
     * to one that is already running.
     */
    fun managerOf(analytics: Analytics): InAppManager? {
        installedManagerOf(analytics)?.let { return it }
        if (!analytics.configuration.inApp.enabled) return null
        return InAppManager.of(analytics)
    }

    /**
     * The in-app manager of [analytics] if one already exists, never creating
     * it - the SDK's own `InAppManager.installed`.
     *
     * Every teardown and every reply-driven nudge goes through this, so a path
     * that only reacts to in-app state cannot be the thing that starts in-app
     * messaging for a host that never asked for it.
     */
    fun installedManagerOf(analytics: Analytics): InAppManager? =
        InAppManager.installed(analytics)
}
