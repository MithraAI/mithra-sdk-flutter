package com.mithra.flutter.sdk

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Buffers and forwards `{type, payload}` envelopes to the Dart event channel.
 *
 * Native callbacks can fire on any thread, and can fire before Dart has
 * subscribed (a push tap processed during startup, for instance). This sink
 * hops to the main thread, which the Flutter platform channels require, and
 * holds a bounded backlog until the first subscriber arrives.
 */
internal class NaryaEventSink : EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val backlog = ArrayDeque<Map<String, Any?>>()
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        while (backlog.isNotEmpty()) {
            val pending = backlog.removeFirst()
            events?.success(pending)
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /**
     * Sends one envelope, buffering it when no subscriber is attached yet.
     *
     * The backlog holds at most [MAX_BACKLOG] envelopes. Past that the **oldest
     * envelope is dropped**, so a Dart side that never subscribes sees the most
     * recent events rather than the first ones. The bound exists because
     * nothing else would ever free the queue: the sink cannot know whether a
     * host will subscribe at all. In practice only a cold-start burst is ever
     * buffered - one push tap plus the first inbox snapshot - and the Dart
     * managers subscribe during `Narya.initialize`, so a drop means the host
     * left the streams unlistened and would not have read the events anyway.
     */
    fun send(type: String, payload: Map<String, Any?>) {
        val envelope = mapOf("type" to type, "payload" to payload)
        mainHandler.post {
            val target = sink
            if (target == null) {
                if (backlog.size >= MAX_BACKLOG) {
                    backlog.removeFirst()
                }
                backlog.addLast(envelope)
            } else {
                target.success(envelope)
            }
        }
    }

    /** Drops the buffered backlog, used on plugin detach. */
    fun clear() {
        mainHandler.post {
            backlog.clear()
            sink = null
        }
    }

    private companion object {
        /** Enough for a cold-start burst; old envelopes are dropped first. */
        const val MAX_BACKLOG = 32
    }
}
