import Foundation

/// Identity rules the bridge applies before it calls the native SDK.
///
/// Pure Foundation for the same reason as `NaryaPushOwnership`: it is compiled
/// a second time as its own module by `ios/Package.swift` so it can be
/// unit-tested on a host toolchain.
enum NaryaIdentity {

    /// The user id to hand to `Analytics.identify`.
    ///
    /// A traits-only `identify` must leave the identity alone, which is what
    /// the Dart API promises. The SDK turns the user id it is handed into the
    /// new identity verbatim and treats any difference from the current id as a
    /// change, which clears the traits and, for an identified user, the user id
    /// itself. So when Dart omits the id, the current one is echoed back and
    /// the SDK takes its traits-merge path instead.
    ///
    /// - Parameters:
    ///   - requested: the id Dart sent, or `nil` for a traits-only call. Dart
    ///     must send `null` rather than `""` for such a call - an empty string
    ///     would read as a change away from the current id - which is what
    ///     test/identify_test.dart checks on the wire.
    ///   - current: `Analytics.userId`, which is `nil` for an anonymous user.
    ///     Echoing that back is exactly what passing nothing would have done,
    ///     so nothing about an anonymous identity moves either way.
    /// - Returns: `requested` when Dart sent one - including an explicit `""`,
    ///   which is a deliberate reset and must not be rewritten - and `current`
    ///   otherwise.
    static func resolveUserId(requested: String?, current: String?) -> String? {
        requested ?? current
    }
}
