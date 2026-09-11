import Flutter
import Foundation

/// Buffers and forwards `{type, payload}` envelopes to the Dart event channel.
///
/// Native callbacks can fire before Dart has subscribed - a push tap processed
/// during startup, for instance - so this sink holds a bounded backlog until
/// the first subscriber arrives.
///
/// `onListen` / `onCancel` arrive on the platform thread and envelopes are
/// always delivered there, but `hasListener` is read from the SDK's push-open
/// handler, which runs on whichever thread delivered the notification, so the
/// state is guarded by a lock.
final class NaryaEventSink: NSObject, FlutterStreamHandler {

    /// Enough for a cold-start burst; old envelopes are dropped first.
    private static let maxBacklog = 32

    private let lock = NSLock()
    private var sink: FlutterEventSink?
    private var backlog: [[String: Any?]] = []

    /// Whether Dart is currently subscribed.
    var hasListener: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sink != nil
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        lock.lock()
        sink = eventSink
        let pending = backlog
        backlog.removeAll()
        lock.unlock()

        for envelope in pending {
            eventSink(envelope)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock()
        sink = nil
        lock.unlock()
        return nil
    }

    /// Sends one envelope, buffering it when no subscriber is attached yet.
    func send(type: String, payload: [String: Any?]) {
        let envelope: [String: Any?] = ["type": type, "payload": payload]
        let deliver = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let sink = self.sink
            if sink == nil {
                if self.backlog.count >= Self.maxBacklog {
                    self.backlog.removeFirst()
                }
                self.backlog.append(envelope)
            }
            self.lock.unlock()
            // Outside the lock: a FlutterEventSink re-enters Dart.
            sink?(envelope)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }
}
