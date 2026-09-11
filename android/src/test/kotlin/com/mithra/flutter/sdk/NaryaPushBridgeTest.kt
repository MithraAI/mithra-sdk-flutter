package com.mithra.flutter.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the payload readers of [NaryaPushBridge] against the shapes gwaihir
 * actually emits.
 *
 * Only the pure payload functions are exercised here: they touch nothing but
 * `org.json`, so they run as plain JVM tests. Everything that needs an `Intent`
 * or a `Context` belongs to an instrumented test instead.
 */
class NaryaPushBridgeTest {

    @Test
    fun `open_action at the root resolves`() {
        val link = NaryaPushBridge.deepLinkFrom(
            mapOf(
                "open_action" to """{"type":"deep_link","data":"myapp://products/42"}""",
            ),
        )
        assertEquals("myapp://products/42", link)
    }

    @Test
    fun `open_action in the mithra overlay resolves`() {
        val link = NaryaPushBridge.deepLinkFrom(
            mapOf(
                "mithra" to """{"open_action":{"type":"deep_link","data":"myapp://cart"}}""",
            ),
        )
        assertEquals("myapp://cart", link)
    }

    @Test
    fun `open_action in the CustomData overlay resolves`() {
        // The shape gwaihir sends for the providers that nest everything under
        // CustomData; a top-level-only reader returns null here.
        val link = NaryaPushBridge.deepLinkFrom(
            mapOf(
                "CustomData" to """{"open_action":{"type":"deep_link","data":"myapp://orders"}}""",
            ),
        )
        assertEquals("myapp://orders", link)
    }

    @Test
    fun `a decoded nested CustomData map resolves too`() {
        // A payload that round-tripped through firebase_messaging arrives with
        // real nested maps rather than strings.
        val link = NaryaPushBridge.deepLinkFrom(
            mapOf(
                "CustomData" to mapOf(
                    "open_action" to mapOf(
                        "type" to "deep_link",
                        "data" to "myapp://orders/7",
                    ),
                ),
            ),
        )
        assertEquals("myapp://orders/7", link)
    }

    @Test
    fun `a root key beats the overlays`() {
        val link = NaryaPushBridge.deepLinkFrom(
            mapOf(
                "open_action" to """{"type":"deep_link","data":"myapp://root"}""",
                "mithra" to """{"open_action":{"type":"deep_link","data":"myapp://mithra"}}""",
                "CustomData" to """{"open_action":{"type":"deep_link","data":"myapp://custom"}}""",
            ),
        )
        assertEquals("myapp://root", link)
    }

    @Test
    fun `a bare deep_link is promoted`() {
        assertEquals(
            "myapp://home",
            NaryaPushBridge.deepLinkFrom(mapOf("deep_link" to "myapp://home")),
        )
    }

    @Test
    fun `the legacy link key is promoted`() {
        assertEquals(
            "myapp://legacy",
            NaryaPushBridge.deepLinkFrom(mapOf("link" to "myapp://legacy")),
        )
    }

    @Test
    fun `a bare deep_link inside CustomData is promoted`() {
        assertEquals(
            "myapp://nested",
            NaryaPushBridge.deepLinkFrom(
                mapOf("CustomData" to """{"deep_link":"myapp://nested"}"""),
            ),
        )
    }

    @Test
    fun `the open_action type is matched case-insensitively and trimmed`() {
        assertEquals(
            "myapp://loud",
            NaryaPushBridge.deepLinkFrom(
                mapOf("open_action" to """{"type":" DEEP_LINK ","data":"myapp://loud"}"""),
            ),
        )
    }

    @Test
    fun `a double-encoded open_action resolves`() {
        // A sender that JSON-encodes the object and then puts that string into
        // the string-valued data map.
        val inner = """{"type":"deep_link","data":"myapp://twice"}"""
        val doubleEncoded = org.json.JSONObject.quote(inner)
        assertEquals(
            "myapp://twice",
            NaryaPushBridge.deepLinkFrom(mapOf("open_action" to doubleEncoded)),
        )
    }

    @Test
    fun `an unknown open_action type yields null`() {
        assertNull(
            NaryaPushBridge.deepLinkFrom(
                mapOf("open_action" to """{"type":"open_app"}"""),
            ),
        )
    }

    @Test
    fun `a present open_action does not fall back to deep_link`() {
        // The sender stated an intent; it just was not one this bridge knows.
        assertNull(
            NaryaPushBridge.deepLinkFrom(
                mapOf(
                    "open_action" to "not json at all",
                    "deep_link" to "myapp://ignored",
                ),
            ),
        )
    }

    @Test
    fun `an empty payload yields null`() {
        assertNull(NaryaPushBridge.deepLinkFrom(null))
        assertNull(NaryaPushBridge.deepLinkFrom(emptyMap<String, String>()))
    }

    @Test
    fun `a silent flag in CustomData suppresses the notification`() {
        assertFalse(
            NaryaPushBridge.postsNotification(
                mapOf("CustomData" to """{"is_silent":"true"}"""),
            ),
        )
    }

    @Test
    fun `a root silent flag beats the overlay`() {
        assertTrue(
            NaryaPushBridge.postsNotification(
                mapOf(
                    "is_silent" to "false",
                    "CustomData" to """{"is_silent":"true"}""",
                ),
            ),
        )
    }

    @Test
    fun `a payload with no silent flag posts a notification`() {
        assertTrue(NaryaPushBridge.postsNotification(mapOf("title" to "Hello")))
    }
}
