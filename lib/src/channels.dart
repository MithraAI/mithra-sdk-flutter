import 'dart:async';

import 'package:flutter/services.dart';

import 'exception.dart';

/// Names of the three platform channels the plugin uses.
///
/// These names are part of the plugin's binary contract with the native
/// implementations and must not change without a matching native change.
abstract final class NaryaChannels {
  /// The method channel carrying every imperative Dart to native call.
  static const String methods = 'com.mithra.flutter.sdk/methods';

  /// The event channel carrying native to Dart notifications.
  static const String events = 'com.mithra.flutter.sdk/events';

  /// The method channel on which native asks Dart delegate questions.
  static const String callbacks = 'com.mithra.flutter.sdk/callbacks';
}

/// `type` discriminators used by envelopes on [NaryaChannels.events].
abstract final class NaryaEventType {
  /// A push notification was opened by the user.
  static const String pushOpened = 'push_opened';

  /// iOS only: APNs delivered a device token after native registration.
  static const String pushToken = 'push_token';

  /// iOS only: APNs registration failed.
  static const String pushRegistrationError = 'push_registration_error';

  /// The set of inbox messages changed.
  static const String inboxMessagesChanged = 'inbox_messages_changed';

  /// The unread inbox message count changed.
  static const String unreadCountChanged = 'unread_count_changed';

  /// A link inside an in-app message resolved to a destination the host
  /// must route to.
  static const String inAppDeepLink = 'inapp_deep_link';
}

/// Method names native uses to ask Dart a delegate question.
abstract final class NaryaCallbackMethod {
  /// Asks whether a newly fetched message should be shown.
  static const String onNewMessage = 'onNewMessage';

  /// Delivers a json-only message payload for the host to handle.
  static const String onJsonOnlyMessage = 'onJsonOnlyMessage';

  /// Reports an `action://<name>` link triggered inside a message.
  static const String onCustomAction = 'onCustomAction';
}

/// The single place where platform channels are created and where
/// `PlatformException` is translated into [NaryaException].
///
/// This type is internal to the plugin; it is not exported from
/// `package:mithra_flutter_sdk/mithra_flutter_sdk.dart`.
class NaryaPlatform {
  /// Creates a platform wrapper. Tests may inject alternative channels.
  NaryaPlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    MethodChannel? callbackChannel,
  }) : _methods = methodChannel ?? const MethodChannel(NaryaChannels.methods),
       _events = eventChannel ?? const EventChannel(NaryaChannels.events),
       _callbacks =
           callbackChannel ?? const MethodChannel(NaryaChannels.callbacks);

  /// The process-wide instance used by the public API.
  static final NaryaPlatform instance = NaryaPlatform();

  final MethodChannel _methods;
  final EventChannel _events;
  final MethodChannel _callbacks;

  Stream<Map<String, Object?>>? _envelopes;

  /// Invokes [method] natively, discarding any reply.
  Future<void> invoke(String method, [Map<String, Object?>? arguments]) async {
    await _guard(() => _methods.invokeMethod<void>(method, arguments));
  }

  /// Invokes [method] natively and returns the reply as `T`.
  Future<T?> invokeOptional<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) {
    return _guard(() => _methods.invokeMethod<T>(method, arguments));
  }

  /// Invokes [method] natively and returns a non-null reply.
  ///
  /// Throws a [NaryaException] with code `native_error` when the native side
  /// replies with `null`.
  Future<T> invokeRequired<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final T? value = await invokeOptional<T>(method, arguments);
    if (value == null) {
      throw NaryaException(
        'native_error',
        'Native method "$method" returned null but a value was required.',
      );
    }
    return value;
  }

  /// Invokes [method] natively and returns the reply as a string-keyed map.
  Future<Map<String, Object?>?> invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final Map<Object?, Object?>? raw =
        await invokeOptional<Map<Object?, Object?>>(method, arguments);
    return raw == null ? null : castMap(raw);
  }

  /// Invokes [method] natively and returns the reply as a list of maps.
  Future<List<Map<String, Object?>>> invokeMapList(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final List<Object?>? raw = await invokeOptional<List<Object?>>(
      method,
      arguments,
    );
    return castMapList(raw);
  }

  /// The decoded stream of `{'type': ..., 'payload': ...}` event envelopes.
  ///
  /// The stream is created once and broadcast, so every public stream getter
  /// filters the same native subscription.
  Stream<Map<String, Object?>> get envelopes {
    return _envelopes ??= _events
        .receiveBroadcastStream()
        .map<Map<String, Object?>>((Object? event) {
          if (event is Map) {
            return castMap(event);
          }
          return const <String, Object?>{};
        })
        .where((Map<String, Object?> envelope) => envelope['type'] is String)
        .asBroadcastStream();
  }

  /// Returns the payloads of every envelope whose `type` equals [type].
  Stream<Map<String, Object?>> eventsOfType(String type) {
    return envelopes
        .where((Map<String, Object?> envelope) => envelope['type'] == type)
        .map((Map<String, Object?> envelope) {
          final Object? payload = envelope['payload'];
          return payload is Map ? castMap(payload) : const <String, Object?>{};
        });
  }

  /// Registers [handler] as the receiver of native delegate questions.
  ///
  /// Passing `null` clears the handler. Only one handler is supported, which is
  /// enough because the in-app manager is a singleton that multiplexes the
  /// three delegate hooks itself.
  void setCallbackHandler(Future<Object?> Function(MethodCall call)? handler) {
    if (handler == null) {
      _callbacks.setMethodCallHandler(null);
    } else {
      _callbacks.setMethodCallHandler(handler);
    }
  }

  Future<T?> _guard<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (error) {
      throw NaryaException(
        error.code,
        error.message ?? 'The Narya native SDK reported an error.',
        error.details,
      );
    } on MissingPluginException catch (error) {
      throw NaryaException(
        'unsupported_platform',
        error.message ??
            'mithra_flutter_sdk is not available on the current platform.',
      );
    }
  }
}

/// Converts a platform-decoded map into a string-keyed Dart map.
///
/// Standard message codec decoding produces `Map<Object?, Object?>`; this
/// helper narrows it without copying nested structures more than once.
Map<String, Object?> castMap(Map<Object?, Object?> raw) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in raw.entries)
      if (entry.key != null) entry.key.toString(): _castValue(entry.value),
  };
}

/// Converts a platform-decoded list into a list of string-keyed maps.
List<Map<String, Object?>> castMapList(List<Object?>? raw) {
  if (raw == null) {
    return const <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final Object? element in raw)
      if (element is Map) castMap(element),
  ];
}

Object? _castValue(Object? value) {
  if (value is Map) {
    return castMap(value);
  }
  if (value is List) {
    return <Object?>[for (final Object? element in value) _castValue(element)];
  }
  return value;
}
