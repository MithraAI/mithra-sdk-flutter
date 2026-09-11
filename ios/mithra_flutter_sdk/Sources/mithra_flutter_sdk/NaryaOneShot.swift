import Foundation

/// A thread-safe "first caller wins" latch.
///
/// The bridge hands completion closures to the `UNUserNotificationCenter`
/// delegate it chained to, and that delegate may answer from any queue - or
/// more than once, because a `FlutterAppDelegate` fans notification callbacks
/// out to every plugin. A watchdog also completes the same callback when the
/// chained delegate never does. A captured `Bool` would be read and written
/// from those different queues without synchronisation, so the latch is guarded
/// by a lock instead.
///
/// Pure state: no SDK calls, no Flutter types.
final class NaryaOneShot {

    private let lock = NSLock()
    private var claimed = false

    /// Returns `true` for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
