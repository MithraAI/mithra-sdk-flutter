import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'channels.dart';
import 'in_app_models.dart';

/// The handler asked whether a freshly fetched message should be shown.
typedef NaryaInAppNewMessageHandler =
    NaryaInAppShowResponse Function(NaryaInAppMessage message);

/// The handler given a json-only message's payload.
///
/// Return `true` when the payload was handled, which lets the native SDK
/// consume the message; return `false` to leave it in the replay buffer.
typedef NaryaInAppJsonOnlyHandler =
    bool Function(Map<String, Object?> payload, NaryaInAppMessage message);

/// The handler notified of an `action://<name>` link inside a message.
typedef NaryaInAppCustomActionHandler =
    void Function(String name, NaryaInAppMessage message);

/// In-app message and mobile inbox bridge, reached through `Narya.inApp`.
///
/// Every method maps to a single native call. Fetching, the display queue, the
/// message store, inbox persistence and — most importantly — **all HTML
/// rendering** stay inside the native SDKs, which already present messages in a
/// transparent web view whose HTML paints its own background and draws its own
/// close control. This class only asks the native SDK to show a message and
/// observes what happened; there is no Flutter widget that renders message
/// content.
///
/// In-app messaging starts on the first call made through this class, not
/// during `Narya.initialize`, so an app that never touches it pays for none of
/// the fetching, storage or display machinery. A configuration with
/// `NaryaInAppConfiguration.enabled` set to `false` refuses these calls with
/// the `in_app_disabled` error code on Android.
class NaryaInAppManager {
  /// Creates a manager. The plugin exposes a single instance as `Narya.inApp`.
  NaryaInAppManager(this._platform);

  final NaryaPlatform _platform;

  NaryaInAppNewMessageHandler? _onNewMessage;
  NaryaInAppJsonOnlyHandler? _onJsonOnlyMessage;
  NaryaInAppCustomActionHandler? _onCustomAction;
  bool _callbacksAttached = false;

  /// Every message currently held by the native store.
  Future<List<NaryaInAppMessage>> get messages => _messages('inApp.messages');

  /// The messages whose campaign asked for them to be kept in the inbox.
  Future<List<NaryaInAppMessage>> get inboxMessages =>
      _messages('inApp.inboxMessages');

  /// How many inbox messages are unread.
  Future<int> get unreadInboxMessageCount =>
      _platform.invokeRequired<int>('inApp.unreadInboxMessageCount');

  /// Emits the full inbox list whenever the native store changes.
  Stream<List<NaryaInAppMessage>> get onInboxMessagesChanged {
    return _platform.eventsOfType(NaryaEventType.inboxMessagesChanged).map((
      Map<String, Object?> payload,
    ) {
      final Object? raw = payload['messages'];
      return _decodeMessages(raw is List<Object?> ? raw : const <Object?>[]);
    });
  }

  /// Emits the unread inbox count whenever it changes.
  Stream<int> get onUnreadInboxMessageCountChanged {
    return _platform.eventsOfType(NaryaEventType.unreadCountChanged).map((
      Map<String, Object?> payload,
    ) {
      final Object? count = payload['count'];
      return count is int ? count : 0;
    });
  }

  /// Emits every link tapped inside an in-app message that the host must
  /// route to.
  ///
  /// The native SDK resolves `deep_link` / plain URL links through the same
  /// resolver a push deep link uses, closes the message, and hands the
  /// destination here. The **SDK never opens the URL itself**: the host routes
  /// it, which is the same contract as the Android SDK's
  /// `InAppManager.setDeepLinkHandler` and the iOS push-open handler.
  /// `narya://` control links and `action://<name>` links never appear on this
  /// stream; the latter reach [setCustomActionHandler].
  ///
  /// Events are already Mithra-originated, so do **not** gate them with
  /// `NaryaPushManager.isNaryaPush`.
  ///
  /// Pass the whole [Uri] to your router where you can; `event.url.path` alone
  /// is only the full route for an `https` destination. A custom scheme has no
  /// authority delimiter, so `Uri.parse('myapp://products/42')` reads
  /// `products` as the host and `/42` as the path, and a router given just the
  /// path would navigate to the wrong screen.
  ///
  /// ```dart
  /// Narya.inApp.onDeepLink.listen((event) {
  ///   final Uri url = event.url;
  ///   router.go(
  ///     url.scheme == 'http' || url.scheme == 'https'
  ///         ? '${url.path}${url.hasQuery ? '?${url.query}' : ''}'
  ///         : '/${url.host}${url.path}',
  ///   );
  /// });
  /// ```
  Stream<NaryaInAppDeepLinkEvent> get onDeepLink {
    return _platform
        .eventsOfType(NaryaEventType.inAppDeepLink)
        .map(NaryaInAppDeepLinkEvent.tryFromMap)
        .where((NaryaInAppDeepLinkEvent? event) => event != null)
        .cast<NaryaInAppDeepLinkEvent>();
  }

  /// Looks up one message by id, or `null` when the store does not hold it.
  Future<NaryaInAppMessage?> message(String messageId) async {
    final Map<String, Object?>? map = await _platform.invokeMap(
      'inApp.message',
      <String, Object?>{'messageId': messageId},
    );
    return map == null ? null : NaryaInAppMessage.fromMap(map);
  }

  /// Marks a message read or unread and reports the change to Mithra.
  Future<void> setRead(String messageId, {required bool read}) {
    return _platform.invoke('inApp.setRead', <String, Object?>{
      'messageId': messageId,
      'read': read,
    });
  }

  /// Deletes a message, recording why it went away.
  Future<void> removeMessage(
    String messageId, {
    NaryaInAppDeleteSource source = NaryaInAppDeleteSource.api,
  }) {
    return _platform.invoke('inApp.removeMessage', <String, Object?>{
      'messageId': messageId,
      'source': source.name,
    });
  }

  /// Asks the native SDK to display a message now.
  ///
  /// Set [consume] to `false` to keep the message in the store after it is
  /// dismissed, which is what an inbox row wants. Pass
  /// [NaryaInAppLocation.inbox] for [location] when the display was started by
  /// an inbox tap so the native analytics attribute it correctly.
  Future<void> showMessage(
    String messageId, {
    bool consume = true,
    NaryaInAppLocation location = NaryaInAppLocation.inApp,
  }) {
    return _platform.invoke('inApp.showMessage', <String, Object?>{
      'messageId': messageId,
      'consume': consume,
      'location': location.name,
    });
  }

  /// Fetches the latest messages from Mithra.
  Future<void> syncMessages() => _platform.invoke('inApp.syncMessages');

  /// Whether automatic display is currently paused.
  Future<bool> get autoDisplayPaused =>
      _platform.invokeRequired<bool>('inApp.autoDisplayPaused');

  /// Pauses or resumes automatic display.
  ///
  /// Pause it while a checkout or onboarding flow must not be interrupted.
  // The positional parameter is fixed by docs/api-contract.md section 7, which
  // mirrors the reference SDK's setAutoDisplayPaused(paused).
  // ignore: avoid_positional_boolean_parameters
  Future<void> setAutoDisplayPaused(bool paused) {
    return _platform.invoke('inApp.setAutoDisplayPaused', <String, Object?>{
      'paused': paused,
    });
  }

  /// Clears [setAutoDisplayPaused] and runs a display pass right away.
  ///
  /// This is **not** a plain nudge: it resumes automatic display as well, so it
  /// undoes an earlier `setAutoDisplayPaused(true)` even when that pause is
  /// still meant to hold. Call it when the flow that paused display is over,
  /// and use `setAutoDisplayPaused(false)` if you only want the flag cleared
  /// without an immediate pass.
  Future<void> resumeDisplay() => _platform.invoke('inApp.resumeDisplay');

  /// The json-only messages whose payloads no handler has accepted yet.
  ///
  /// The native SDK buffers them so a payload delivered before your handler was
  /// registered is not lost.
  Future<List<NaryaInAppMessage>> get unhandledJsonOnlyMessages =>
      _messages('inApp.unhandledJsonOnlyMessages');

  /// Marks one buffered json-only message handled.
  ///
  /// Returns whether the store actually held that message.
  Future<bool> markJsonOnlyMessageHandled(String messageId) {
    return _platform.invokeRequired<bool>(
      'inApp.markJsonOnlyMessageHandled',
      <String, Object?>{'messageId': messageId},
    );
  }

  /// Empties the json-only replay buffer without handling anything.
  Future<void> clearUnhandledJsonOnlyMessages() =>
      _platform.invoke('inApp.clearUnhandledJsonOnlyMessages');

  /// Starts an inbox session; call it when your inbox screen appears.
  Future<void> startInboxSession() =>
      _platform.invoke('inApp.startInboxSession');

  /// Records that an inbox row became visible.
  Future<void> startInboxImpression(String messageId) {
    return _platform.invoke('inApp.startInboxImpression', <String, Object?>{
      'messageId': messageId,
    });
  }

  /// Records that an inbox row stopped being visible.
  Future<void> endInboxImpression(String messageId) {
    return _platform.invoke('inApp.endInboxImpression', <String, Object?>{
      'messageId': messageId,
    });
  }

  /// Ends the inbox session; call it when your inbox screen disappears.
  Future<void> endInboxSession() => _platform.invoke('inApp.endInboxSession');

  /// Registers the handler asked about every newly fetched message.
  ///
  /// Registration is synchronous but dispatch is asynchronous: the native SDK
  /// asks the question over a channel and waits for the reply inside its
  /// display pass, so the handler must return promptly and must not await. Pass
  /// `null` to restore the native default, which is
  /// [NaryaInAppShowResponse.show].
  void setOnNewMessage(NaryaInAppNewMessageHandler? handler) {
    _onNewMessage = handler;
    _syncCallbackRegistration();
  }

  /// Registers the handler given every json-only payload.
  ///
  /// Pass `null` to restore the native default, which is `false` (unhandled,
  /// so the message stays in the replay buffer).
  void setOnJsonOnlyMessage(NaryaInAppJsonOnlyHandler? handler) {
    _onJsonOnlyMessage = handler;
    _syncCallbackRegistration();
  }

  /// Registers the handler notified of `action://<name>` links.
  void setCustomActionHandler(NaryaInAppCustomActionHandler? handler) {
    _onCustomAction = handler;
    _syncCallbackRegistration();
  }

  Future<List<NaryaInAppMessage>> _messages(String method) async {
    final List<Map<String, Object?>> raw = await _platform.invokeMapList(
      method,
    );
    return <NaryaInAppMessage>[
      for (final Map<String, Object?> map in raw)
        NaryaInAppMessage.fromMap(map),
    ];
  }

  List<NaryaInAppMessage> _decodeMessages(List<Object?> raw) {
    return <NaryaInAppMessage>[
      for (final Map<String, Object?> map in castMapList(raw))
        NaryaInAppMessage.fromMap(map),
    ];
  }

  void _syncCallbackRegistration() {
    final bool wanted =
        _onNewMessage != null ||
        _onJsonOnlyMessage != null ||
        _onCustomAction != null;
    if (wanted && !_callbacksAttached) {
      _platform.setCallbackHandler(_handleCallback);
      _callbacksAttached = true;
    } else if (!wanted && _callbacksAttached) {
      _platform.setCallbackHandler(null);
      _callbacksAttached = false;
    }
    // Tell the native side whether consulting Dart about a new message is
    // worth a deferred display pass. Failures are ignored: the native side
    // discovers the same fact from an unhandled callback anyway.
    _platform.invoke('inApp.notifyNewMessageHandler', <String, Object?>{
      'attached': _onNewMessage != null,
    }).ignore();
  }

  Future<Object?> _handleCallback(MethodCall call) async {
    final Object? arguments = call.arguments;
    final Map<String, Object?> args = arguments is Map
        ? castMap(arguments)
        : const <String, Object?>{};
    final Object? messageRaw = args['message'];
    final NaryaInAppMessage? message = messageRaw is Map<String, Object?>
        ? NaryaInAppMessage.fromMap(messageRaw)
        : null;

    switch (call.method) {
      case NaryaCallbackMethod.onNewMessage:
        final NaryaInAppNewMessageHandler? handler = _onNewMessage;
        if (handler == null || message == null) {
          return NaryaInAppShowResponse.show.name;
        }
        try {
          return handler(message).name;
        } catch (error, stackTrace) {
          // A throwing handler would reach the native side as a channel error,
          // which both bridges decode as `show`: a host bug would then display
          // the very message the handler was about to skip. Defer instead, so
          // the message stays queued and the handler is asked again on the next
          // display pass.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'mithra_flutter_sdk',
              context: ErrorDescription(
                'while asking the Narya onNewMessage handler about in-app '
                'message "${message.messageId}"; deferring its display',
              ),
            ),
          );
          return NaryaInAppShowResponse.defer.name;
        }
      case NaryaCallbackMethod.onJsonOnlyMessage:
        final NaryaInAppJsonOnlyHandler? handler = _onJsonOnlyMessage;
        if (handler == null || message == null) {
          return false;
        }
        final Object? payloadRaw = args['payload'];
        return handler(
          payloadRaw is Map<String, Object?>
              ? payloadRaw
              : const <String, Object?>{},
          message,
        );
      case NaryaCallbackMethod.onCustomAction:
        final NaryaInAppCustomActionHandler? handler = _onCustomAction;
        final String? name = args['name'] as String?;
        if (handler != null && message != null && name != null) {
          handler(name, message);
        }
        return null;
      default:
        return null;
    }
  }
}
