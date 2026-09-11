/// The outcome of `Narya.push.registerForRemoteNotifications`.
///
/// Mirrors `UNAuthorizationStatus` on iOS. Android always reports
/// [unsupported], because Android tokens come from Firebase Cloud Messaging and
/// are handed to the SDK with `Narya.push.setToken`.
enum NaryaPushAuthorizationStatus {
  /// The user granted notification permission; APNs registration was
  /// requested and the token will arrive on `Narya.push.onToken`.
  ///
  /// Also reported for the App Clip `ephemeral` status.
  authorized,

  /// Notifications were provisionally authorised (quiet delivery); APNs
  /// registration was requested and the token will arrive on
  /// `Narya.push.onToken`.
  provisional,

  /// The user denied notification permission, now or earlier. No registration
  /// was attempted; direct the user to the system Settings app.
  denied,

  /// Permission has not been decided. Only reported when the system prompt
  /// could not be shown.
  notDetermined,

  /// The current platform does not register natively (Android).
  unsupported,
}

/// Decodes the wire value native replies to `push.registerForRemoteNotifications`.
///
/// Unknown or missing values decode to [NaryaPushAuthorizationStatus.unsupported].
/// This is internal to the plugin and not exported from the barrel file.
NaryaPushAuthorizationStatus decodeNaryaPushAuthorizationStatus(Object? raw) {
  switch (raw) {
    case 'authorized':
      return NaryaPushAuthorizationStatus.authorized;
    case 'provisional':
      return NaryaPushAuthorizationStatus.provisional;
    case 'denied':
      return NaryaPushAuthorizationStatus.denied;
    case 'notDetermined':
      return NaryaPushAuthorizationStatus.notDetermined;
    default:
      return NaryaPushAuthorizationStatus.unsupported;
  }
}

/// An APNs registration failure reported by
/// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
///
/// Delivered on `Narya.push.onRegistrationError`. Typical causes are a missing
/// `aps-environment` entitlement, running on a simulator without a paired
/// device, or no network at launch.
class NaryaPushRegistrationError {
  /// Creates a registration error.
  const NaryaPushRegistrationError({required this.code, required this.message});

  /// Decodes an error from its native wire form.
  ///
  /// A missing `code` decodes to [fallbackCode]; a missing `message` decodes to
  /// an empty string.
  factory NaryaPushRegistrationError.fromMap(Map<String, Object?> map) {
    final Object? code = map['code'];
    final Object? message = map['message'];
    return NaryaPushRegistrationError(
      code: code is String && code.isNotEmpty ? code : fallbackCode,
      message: message is String ? message : '',
    );
  }

  /// The [code] used when the native envelope carries none.
  static const String fallbackCode = 'registration_failed';

  /// A machine-readable code, `<NSError.domain>:<NSError.code>` on iOS.
  final String code;

  /// The system's localized description of the failure.
  final String message;

  @override
  String toString() => 'NaryaPushRegistrationError($code): $message';
}

/// Android display options for `Narya.push.handlePushMessage`.
///
/// Mirrors the native `PushDisplayOptions` the Narya Android SDK takes in a
/// `FirebaseMessagingService`: the status-bar icon, the activity a tap opens
/// and the notification channel. Every field is optional; an absent field
/// falls back to the native default described on it. Ignored on iOS, where the
/// Notification Service Extension renders the notification.
///
/// ```dart
/// const NaryaPushDisplayOptions(
///   smallIcon: 'ic_notification',
///   channelId: 'marketing',
///   channelName: 'Offers and updates',
/// );
/// ```
class NaryaPushDisplayOptions {
  /// Creates display options. All arguments are optional.
  const NaryaPushDisplayOptions({
    this.smallIcon,
    this.tapActivity,
    this.channelId,
    this.channelName,
  });

  /// The notification channel id used when [channelId] is not set.
  ///
  /// Same value as the native SDK's `DEFAULT_CHANNEL_ID`.
  static const String defaultChannelId = 'narya_default';

  /// The user-visible channel name used when [channelName] is not set.
  ///
  /// Same value as the native SDK's `DEFAULT_CHANNEL_NAME`.
  static const String defaultChannelName = 'Notifications';

  /// The name of the drawable (or mipmap) resource shown in the status bar,
  /// without a `@drawable/` prefix or a file extension, e.g. `ic_notification`.
  ///
  /// Android renders the small icon as a white silhouette, so ship a dedicated
  /// monochrome asset under `android/app/src/main/res/drawable*/`. When `null`
  /// the application icon (`android:icon` from the manifest) is used, which
  /// works but usually looks like a blob. A name that resolves to no resource
  /// throws `NaryaException` with code `invalid_argument`.
  final String? smallIcon;

  /// The fully qualified class name of the activity a tap launches, e.g.
  /// `com.example.app.MainActivity`.
  ///
  /// When `null` the package's launcher activity is used, which is the single
  /// `FlutterActivity` of almost every Flutter app. Set it only when the app
  /// has several activities and the notification should not open the launcher.
  final String? tapActivity;

  /// The Android notification channel id; created idempotently on first use.
  /// Defaults to [defaultChannelId].
  final String? channelId;

  /// The user-visible name of [channelId]. Defaults to [defaultChannelName].
  final String? channelName;

  /// Encodes the options for the platform channel.
  ///
  /// Only the fields that were set are emitted, so the native bridge applies
  /// its own defaults for the rest. Blank strings are treated as unset.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_isSet(smallIcon)) 'smallIcon': smallIcon,
      if (_isSet(tapActivity)) 'tapActivity': tapActivity,
      if (_isSet(channelId)) 'channelId': channelId,
      if (_isSet(channelName)) 'channelName': channelName,
    };
  }

  static bool _isSet(String? value) => value != null && value.trim().isNotEmpty;

  @override
  String toString() =>
      'NaryaPushDisplayOptions(smallIcon: $smallIcon, '
      'tapActivity: $tapActivity, channelId: $channelId, '
      'channelName: $channelName)';
}
