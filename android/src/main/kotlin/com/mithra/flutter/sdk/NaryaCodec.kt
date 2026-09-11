package com.mithra.flutter.sdk

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Conversions between Flutter's standard message codec types and the
 * `kotlinx.serialization` JSON types the Narya SDK takes.
 *
 * This file is pure translation: it never calls the SDK and holds no state.
 */
internal object NaryaCodec {

    /** Converts a channel argument map into the SDK's [JsonObject] properties type. */
    fun toJsonObject(source: Map<*, *>?): JsonObject {
        if (source == null) return JsonObject(emptyMap())
        val entries = LinkedHashMap<String, JsonElement>(source.size)
        for ((key, value) in source) {
            if (key == null) continue
            entries[key.toString()] = toJsonElement(value)
        }
        return JsonObject(entries)
    }

    /** Converts one decoded channel value into a [JsonElement]. */
    fun toJsonElement(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value)
        is Long -> JsonPrimitive(value)
        is Float -> JsonPrimitive(value)
        is Double -> JsonPrimitive(value)
        is Map<*, *> -> toJsonObject(value)
        is Iterable<*> -> JsonArray(value.map { toJsonElement(it) })
        is ByteArray -> JsonArray(value.map { JsonPrimitive(it.toInt()) })
        is IntArray -> JsonArray(value.map { JsonPrimitive(it) })
        is LongArray -> JsonArray(value.map { JsonPrimitive(it) })
        is DoubleArray -> JsonArray(value.map { JsonPrimitive(it) })
        is Array<*> -> JsonArray(value.map { toJsonElement(it) })
        else -> JsonPrimitive(value.toString())
    }

    /** Converts a [JsonObject] into a map the standard message codec can encode. */
    fun fromJsonObject(source: JsonObject?): Map<String, Any?>? {
        if (source == null) return null
        return source.mapValues { (_, element) -> fromJsonElement(element) }
    }

    /** Converts one [JsonElement] into a standard-message-codec value. */
    fun fromJsonElement(element: JsonElement): Any? = when (element) {
        is JsonNull -> null
        is JsonObject -> element.mapValues { (_, child) -> fromJsonElement(child) }
        is JsonArray -> element.map { fromJsonElement(it) }
        is JsonPrimitive -> when {
            element.isString -> element.content
            else -> element.booleanOrNull
                ?: element.intOrNull
                ?: element.longOrNull
                ?: element.doubleOrNull
                ?: element.content
        }
    }

    /**
     * Flattens a decoded push payload into the `Map<String, String>` the Narya
     * Android SDK's push-tracking APIs take.
     *
     * FCM data payloads are string-valued on the wire, but a Dart caller can
     * legitimately hand over a map that already holds decoded numbers or nested
     * objects (for example after a round trip through `firebase_messaging`), so
     * non-string values are stringified rather than dropped. Nested maps and
     * lists are re-encoded as JSON so the SDK's own payload parser can read
     * them back.
     *
     * Two deliberate lossy edges, both of which only a payload that could not
     * have come off the FCM wire can hit:
     *
     * - A `null` value is dropped, because the target type has no way to
     *   express one. The SDK's parsers treat an absent key and a null value
     *   identically, so this changes no decision they make.
     * - Keys are compared as strings, so an integer key `1` and a string key
     *   `"1"` are the same entry and the later one wins. FCM data maps are
     *   string-keyed, so a payload holding both is already malformed.
     *
     * Whole-valued numbers are rendered without a decimal point (`1`, not
     * `1.0`): a Dart `1.0` and a Dart `1` denote the same wire value, and the
     * SDK's flag parsers match `"1"`.
     */
    fun toStringMap(source: Map<*, *>?): Map<String, String> {
        if (source == null) return emptyMap()
        val result = LinkedHashMap<String, String>(source.size)
        for ((key, value) in source) {
            if (key == null || value == null) continue
            result[key.toString()] = when (value) {
                is String -> value
                is Map<*, *>, is Iterable<*>, is Array<*> ->
                    toJsonElement(value).toString()
                is Double -> numberToString(value)
                is Float -> numberToString(value.toDouble())
                else -> value.toString()
            }
        }
        return result
    }

    /** Renders a whole-valued number without its `.0`, mirroring the wire form. */
    private fun numberToString(value: Double): String {
        val isWhole = !value.isNaN() &&
            !value.isInfinite() &&
            value == Math.floor(value) &&
            value >= Long.MIN_VALUE.toDouble() &&
            value <= Long.MAX_VALUE.toDouble()
        return if (isWhole) value.toLong().toString() else value.toString()
    }
}
