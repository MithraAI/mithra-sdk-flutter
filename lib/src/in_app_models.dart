/// The answer a host gives when the native SDK offers a new message for
/// display.
enum NaryaInAppShowResponse {
  /// Display the message now.
  show,

  /// Never display this message; the native SDK consumes it.
  skip,

  /// Leave the message queued and offer it again later.
  defer,
}

/// Why a message was removed, recorded on the native delete event.
enum NaryaInAppDeleteSource {
  /// The user swiped the row away in the inbox.
  inboxSwipe,

  /// A `narya://delete` link inside the message was followed.
  deleteButton,

  /// The SDK consumed the message after displaying or handling it.
  consume,

  /// The host called `NaryaInAppManager.removeMessage` directly.
  api,
}

/// Where a message is being shown from.
enum NaryaInAppLocation {
  /// Shown as an automatic or imperative in-app message.
  inApp,

  /// Shown because the user tapped an inbox row.
  inbox,
}

/// When a message becomes eligible for display.
enum NaryaInAppTriggerType {
  /// Eligible as soon as it is fetched.
  immediate,

  /// Eligible once [NaryaInAppTrigger.eventName] is tracked.
  event,

  /// Never displayed automatically; inbox or imperative display only.
  never,
}

/// The display trigger attached to a message.
class NaryaInAppTrigger {
  /// Creates a trigger.
  const NaryaInAppTrigger({required this.type, this.eventName});

  /// Decodes a trigger from its native wire form.
  factory NaryaInAppTrigger.fromMap(Map<String, Object?> map) {
    return NaryaInAppTrigger(
      type: _decodeTriggerType(map['type']),
      eventName: map['eventName'] as String?,
    );
  }

  /// What kind of trigger this is.
  final NaryaInAppTriggerType type;

  /// The event whose tracking makes the message eligible.
  ///
  /// Non-null only when [type] is [NaryaInAppTriggerType.event].
  final String? eventName;
}

/// The inbox row presentation supplied with a message.
class NaryaInAppInboxMetadata {
  /// Creates inbox metadata.
  const NaryaInAppInboxMetadata({
    required this.title,
    this.subtitle,
    this.icon,
  });

  /// Decodes inbox metadata from its native wire form.
  factory NaryaInAppInboxMetadata.fromMap(Map<String, Object?> map) {
    return NaryaInAppInboxMetadata(
      title: (map['title'] as String?) ?? '',
      subtitle: map['subtitle'] as String?,
      icon: map['icon'] as String?,
    );
  }

  /// The inbox row title.
  final String title;

  /// The inbox row subtitle, when the campaign supplied one.
  final String? subtitle;

  /// A URL for the inbox row icon, when the campaign supplied one.
  final String? icon;
}

/// An in-app message as the native SDK stores it.
///
/// The message HTML is deliberately absent: only the native SDK renders
/// message content, so Dart receives [hasContent] instead of the markup. See
/// `docs/api-contract.md` section 7.
class NaryaInAppMessage {
  /// Creates a message. Normally obtained from `NaryaInAppManager`, not
  /// constructed by hand.
  const NaryaInAppMessage({
    required this.messageId,
    required this.createdAt,
    required this.trigger,
    required this.saveToInbox,
    required this.priorityLevel,
    required this.read,
    required this.jsonOnly,
    required this.hasContent,
    this.campaignId,
    this.expiresAt,
    this.inboxMetadata,
    this.customPayload,
  });

  /// Decodes a message from its native wire form.
  factory NaryaInAppMessage.fromMap(Map<String, Object?> map) {
    final Object? triggerRaw = map['trigger'];
    final Object? inboxRaw = map['inboxMetadata'];
    final Object? payloadRaw = map['customPayload'];
    return NaryaInAppMessage(
      messageId: (map['messageId'] as String?) ?? '',
      campaignId: map['campaignId'] as String?,
      createdAt:
          _decodeTime(map['createdAtMillis']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: _decodeTime(map['expiresAtMillis']),
      trigger: triggerRaw is Map<String, Object?>
          ? NaryaInAppTrigger.fromMap(triggerRaw)
          : const NaryaInAppTrigger(type: NaryaInAppTriggerType.immediate),
      saveToInbox: (map['saveToInbox'] as bool?) ?? false,
      inboxMetadata: inboxRaw is Map<String, Object?>
          ? NaryaInAppInboxMetadata.fromMap(inboxRaw)
          : null,
      priorityLevel: _decodeDouble(map['priorityLevel']) ?? 300.5,
      read: (map['read'] as bool?) ?? false,
      jsonOnly: (map['jsonOnly'] as bool?) ?? false,
      customPayload: payloadRaw is Map<String, Object?> ? payloadRaw : null,
      hasContent: (map['hasContent'] as bool?) ?? false,
    );
  }

  /// The stable identifier every other in-app API takes.
  final String messageId;

  /// The campaign that produced this message, when known.
  final String? campaignId;

  /// When the message was created, in UTC.
  final DateTime createdAt;

  /// When the message stops being displayable, in UTC.
  ///
  /// `null` means the message never expires.
  final DateTime? expiresAt;

  /// When the message becomes eligible for automatic display.
  final NaryaInAppTrigger trigger;

  /// Whether the message also belongs in the mobile inbox.
  final bool saveToInbox;

  /// How an inbox row for this message should be presented.
  final NaryaInAppInboxMetadata? inboxMetadata;

  /// The display priority; lower sorts first.
  final double priorityLevel;

  /// Whether the message has been marked read.
  final bool read;

  /// Whether the message carries only a JSON payload and never renders.
  final bool jsonOnly;

  /// The campaign-supplied JSON payload, when present.
  final Map<String, Object?>? customPayload;

  /// Whether the message has renderable content.
  ///
  /// An inbox list uses this to decide whether tapping a row can show
  /// anything. The content itself stays native.
  final bool hasContent;

  /// Whether [expiresAt] is in the past.
  bool get isExpired {
    final DateTime? expiry = expiresAt;
    return expiry != null && expiry.isBefore(DateTime.now().toUtc());
  }
}

/// A link tapped inside an in-app message that the host must route to.
///
/// Emitted on `Narya.inApp.onDeepLink` for every non-`narya://` /
/// non-`action://` link the user follows in a rendered message, after the
/// native SDK has resolved it through the same resolver a push deep link uses
/// and has closed the message. The **SDK never opens the URL itself**; routing
/// is the host's job, exactly as the Android SDK's `InAppDeepLinkHandler` and
/// the iOS push-open handler contract state.
///
/// Events on this stream are already Mithra-originated: do **not** gate them
/// with `NaryaPushManager.isNaryaPush`, which exists for raw
/// `firebase_messaging` / APNs payloads only.
class NaryaInAppDeepLinkEvent {
  /// Creates an in-app deep-link event.
  const NaryaInAppDeepLinkEvent({required this.url, required this.messageId});

  /// Decodes an event from its native wire form, or returns `null` when the
  /// envelope carries no parseable `url`.
  static NaryaInAppDeepLinkEvent? tryFromMap(Map<String, Object?> map) {
    final Object? raw = map['url'];
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    final Uri? url = Uri.tryParse(raw);
    if (url == null) {
      return null;
    }
    return NaryaInAppDeepLinkEvent(
      url: url,
      messageId: (map['messageId'] as String?) ?? '',
    );
  }

  /// The destination the message asked the host to open.
  final Uri url;

  /// The identifier of the in-app message that carried the link.
  final String messageId;
}

/// A push notification the user opened.
///
/// Every event the SDK delivers to Dart - this one on
/// `Narya.push.onPushOpened`, the payload returned by
/// `Narya.push.takeInitialPushPayload`, and `NaryaInAppDeepLinkEvent` on
/// `Narya.inApp.onDeepLink` - is already Mithra-originated: the native SDK
/// only produces them for notifications and messages it recognises. Do **not**
/// gate them with `NaryaPushManager.isNaryaPush`; that predicate is for raw
/// `firebase_messaging` / APNs payloads, and applying it here can drop valid
/// events (an in-app link, for instance, carries no push payload at all).
class NaryaPushOpenEvent {
  /// Creates a push-open event.
  const NaryaPushOpenEvent({
    required this.payload,
    required this.isBodyTap,
    required this.isActionButtonTap,
    this.deepLink,
    this.messageId,
    this.actionIdentifier,
  });

  /// Decodes a push-open event from its native wire form.
  factory NaryaPushOpenEvent.fromMap(Map<String, Object?> map) {
    final Object? payloadRaw = map['payload'];
    final String? link = map['deepLink'] as String?;
    return NaryaPushOpenEvent(
      payload: payloadRaw is Map<String, Object?>
          ? payloadRaw
          : const <String, Object?>{},
      deepLink: link == null ? null : Uri.tryParse(link),
      messageId: map['messageId'] as String?,
      actionIdentifier: map['actionIdentifier'] as String?,
      isBodyTap: (map['isBodyTap'] as bool?) ?? false,
      isActionButtonTap: (map['isActionButtonTap'] as bool?) ?? false,
    );
  }

  /// The full notification payload as delivered by APNs or FCM.
  ///
  /// A tap on a text-input action button adds `user_text`, holding what the
  /// user typed.
  final Map<String, Object?> payload;

  /// The destination the host should route to, when the campaign set one.
  ///
  /// The SDK never opens it; routing stays with the app.
  final Uri? deepLink;

  /// The Mithra message identifier, when the payload carried one.
  final String? messageId;

  /// The identifier of the action button the user tapped, or `null` for a body
  /// tap.
  ///
  /// This is the button's own id on both platforms: the iOS notification action
  /// identifier, and the Android action id. Android additionally carries the
  /// button's route type (`open_app` / `deep_link`) in [payload].
  final String? actionIdentifier;

  /// Whether the user tapped the notification body rather than a button.
  final bool isBodyTap;

  /// Whether the user tapped one of the notification's action buttons.
  final bool isActionButtonTap;
}

NaryaInAppTriggerType _decodeTriggerType(Object? raw) {
  switch (raw) {
    case 'event':
      return NaryaInAppTriggerType.event;
    case 'never':
      return NaryaInAppTriggerType.never;
    default:
      return NaryaInAppTriggerType.immediate;
  }
}

DateTime? _decodeTime(Object? raw) {
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(raw.round(), isUtc: true);
  }
  return null;
}

double? _decodeDouble(Object? raw) {
  if (raw is double) {
    return raw;
  }
  if (raw is int) {
    return raw.toDouble();
  }
  return null;
}
