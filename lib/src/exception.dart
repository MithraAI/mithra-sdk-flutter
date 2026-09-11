/// The error type every `mithra_flutter_sdk` API throws.
///
/// Every `PlatformException` raised by a platform channel is translated into a
/// [NaryaException] so that callers never have to import
/// `package:flutter/services.dart` to handle SDK failures.
class NaryaException implements Exception {
  /// Creates an exception with a machine-readable [code] and a human-readable
  /// [message].
  const NaryaException(this.code, this.message, [this.details]);

  /// A stable, machine-readable error code.
  ///
  /// Well-known values are `not_initialized` (an API was called before
  /// `Narya.initialize` completed), `missing_write_key` (the write key was not
  /// supplied), `already_initialized` (a second
  /// `Narya.initialize` call used a different configuration), `invalid_argument`
  /// and `native_error` (an unclassified failure inside the native SDK).
  final String code;

  /// A human-readable description of what went wrong.
  final String message;

  /// Optional platform-supplied detail, usually a `String` stack trace.
  final Object? details;

  @override
  String toString() => 'NaryaException($code): $message';
}
