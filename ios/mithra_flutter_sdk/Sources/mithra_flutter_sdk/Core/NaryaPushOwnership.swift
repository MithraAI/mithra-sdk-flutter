import Foundation

/// Whether this app uses push, and therefore whether the plugin should own
/// `UNUserNotificationCenter.delegate`.
///
/// Split out of `MithraFlutterSdkPlugin` deliberately: the plugin imports
/// Flutter, UIKit and MithraAnalytics, none of which exist on a host toolchain,
/// so nothing in that file can be unit-tested from the command line. This type
/// is pure Foundation and is compiled a second time as its own module by
/// `ios/Package.swift`, which is where the tests live. See that manifest.
///
/// The answer has to be **persisted**, not recomputed per launch. iOS delivers
/// a notification tap that cold-started the app right after
/// `didFinishLaunchingWithOptions`, and a callback that arrives with no
/// delegate installed is dropped and never redelivered - so the role has to be
/// claimed during plugin registration, long before any Dart code or any APNs
/// callback could tell the plugin that this app uses push. The flag one launch
/// writes is what lets the next launch claim the role in time.
struct NaryaPushOwnership {

    /// Every way push can start being used. This list is the whole contract:
    /// a route that puts an APNs/FCM token into the SDK without appearing here
    /// leaves the plugin off the notification center delegate, which loses
    /// `push_delivered` / `push_opened` and every `open_action` and deep link
    /// silently - the system still shows the alert, so nothing looks broken.
    enum Entry: String, CaseIterable {
        /// `push.registerForRemoteNotifications`: the plugin performs the APNs
        /// registration itself.
        case dartRegisterForRemoteNotifications
        /// `push.setToken`: the host obtained a token elsewhere
        /// (`firebase_messaging`, typically) and hands it over.
        case dartSetToken
        /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`:
        /// *anything* in the process registered with APNs - host code in the
        /// app delegate, or `firebase_messaging`, which owns APNs registration
        /// on iOS. `FlutterPluginAppLifeCycleDelegate` fans the callback out to
        /// every plugin, so it fires for a host that reaches neither Dart entry
        /// point above. An APNs token in hand is the ground truth for "this app
        /// uses push"; a *failed* registration is not, and
        /// `didFailToRegisterForRemoteNotificationsWithError` is deliberately
        /// absent from this list.
        case apnsDeviceTokenReceived
    }

    /// The `UserDefaults` key holding the flag. Namespaced, because it lives in
    /// the host app's own defaults. Part of the documented contract (see
    /// `docs/api-contract.md`): renaming it would make every already-installed
    /// app look analytics-only for one launch, and lose a cold-start tap.
    static let pushInUseKey = "com.mithra.flutter.sdk.pushInUse"

    private let defaults: UserDefaults

    /// - Parameter defaults: the host app's defaults in production; a scratch
    ///   suite in tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether push has been in use at least once, in this launch or an
    /// earlier one.
    var isPushInUse: Bool {
        defaults.bool(forKey: Self.pushInUseKey)
    }

    /// Whether a launch path - plugin registration,
    /// `didFinishLaunchingWithOptions`, `initialize` - should claim the
    /// notification center delegate. None of them can tell on their own whether
    /// the app uses push, which is what the persisted flag answers.
    var shouldClaimDelegateOnLaunch: Bool {
        isPushInUse
    }

    /// Records that push is in use, naming the entry point in a debug line the
    /// first time (a token refresh comes back through
    /// `apnsDeviceTokenReceived` on every launch, so logging every call would
    /// be noise). Reports whether this was that first time.
    @discardableResult
    func recordPushInUse(from entry: Entry) -> Bool {
        if isPushInUse { return false }
        defaults.set(true, forKey: Self.pushInUseKey)
        NSLog(
            "[mithra_flutter_sdk] Push is in use (%@); the plugin owns "
                + "UNUserNotificationCenter.delegate from now on, this launch included.",
            entry.rawValue
        )
        return true
    }
}
