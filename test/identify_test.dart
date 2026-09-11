import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';
import 'package:mithra_flutter_sdk/src/channels.dart';

// Covers `Narya.identify` and, in particular, the wire contract a traits-only
// identify depends on: `userId` must reach native as `null` - never as an empty
// string - because both native bridges treat a missing user id as "keep the
// current identity" while the native SDKs treat an empty user id handed to an
// identified user as a change away from that user, which resets the anonymous
// id, the user id and the traits.
//
// The native identity rules are mirrored by `_FakeNativeIdentity` below, so the
// three documented cases can be asserted from Dart. The real native behaviour
// lives in narya-ios / narya-android and is covered there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Narya.identify', () {
    final List<MethodCall> calls = <MethodCall>[];
    late _FakeNativeIdentity native;

    setUp(() {
      calls.clear();
      native = _FakeNativeIdentity();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            (MethodCall call) async {
              calls.add(call);
              if (call.method == 'identify') {
                final Map<Object?, Object?> arguments =
                    call.arguments as Map<Object?, Object?>;
                native.identify(
                  arguments['userId'] as String?,
                  arguments['traits'] as Map<Object?, Object?>?,
                );
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            null,
          );
    });

    /// The arguments of the last recorded call.
    Map<Object?, Object?> lastArguments() =>
        calls.last.arguments as Map<Object?, Object?>;

    // (a) An explicit user id identifies the user.
    test('with a userId identifies the user and merges the traits', () async {
      await Narya.identify(
        userId: 'user-123',
        traits: <String, Object?>{'email': 'a@b.com'},
      );

      expect(calls.single.method, 'identify');
      expect(lastArguments(), <String, Object?>{
        'userId': 'user-123',
        'traits': <String, Object?>{'email': 'a@b.com'},
      });
      expect(native.userId, 'user-123');
      expect(native.traits, <String, Object?>{'email': 'a@b.com'});
      expect(native.resetCount, 0);
    });

    // (b) Traits-only for an already identified user: the identity is kept and
    // the traits are merged into the ones the user already has.
    test(
      'without a userId keeps an identified user and merges traits',
      () async {
        await Narya.identify(
          userId: 'user-123',
          traits: <String, Object?>{'email': 'a@b.com', 'plan': 'free'},
        );
        final String anonymousIdBefore = native.anonymousId;

        await Narya.identify(traits: <String, Object?>{'plan': 'pro'});

        // `null`, not '': an empty string would read as a change away from
        // user-123 and reset the whole identity natively.
        expect(lastArguments()['userId'], isNull);
        expect(native.userId, 'user-123');
        expect(native.anonymousId, anonymousIdBefore);
        expect(native.traits, <String, Object?>{
          'email': 'a@b.com',
          'plan': 'pro',
        });
        expect(native.resetCount, 0);
      },
    );

    // (c) Traits-only for an anonymous user: nothing about the identity moves.
    // This is the case the Android bridge used to break by sending ''.
    test('without a userId leaves an anonymous user unidentified', () async {
      await Narya.identify(traits: <String, Object?>{'plan': 'free'});
      final String anonymousIdBefore = native.anonymousId;

      await Narya.identify(traits: <String, Object?>{'locale': 'en'});

      expect(lastArguments()['userId'], isNull);
      // Still anonymous: no user id was invented, the anonymous id was not
      // rebuilt, the traits were merged rather than cleared, and the native
      // reset path never ran.
      expect(native.userId, isEmpty);
      expect(native.anonymousId, anonymousIdBefore);
      expect(native.traits, <String, Object?>{'plan': 'free', 'locale': 'en'});
      expect(native.resetCount, 0);
    });

    test(
      're-identifying a different user resets the previous identity',
      () async {
        await Narya.identify(
          userId: 'user-123',
          traits: <String, Object?>{'email': 'a@b.com'},
        );
        final String anonymousIdBefore = native.anonymousId;

        await Narya.identify(userId: 'user-456');

        expect(native.userId, 'user-456');
        expect(native.resetCount, 1);
        expect(native.traits, isEmpty);
        expect(native.anonymousId, isNot(anonymousIdBefore));
      },
    );

    test('sends both arguments as null when neither is given', () async {
      await Narya.identify();

      expect(lastArguments(), <String, Object?>{
        'userId': null,
        'traits': null,
      });
      expect(native.userId, isEmpty);
      expect(native.resetCount, 0);
    });

    test('translates a native error into NaryaException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            (MethodCall call) async {
              throw PlatformException(
                code: 'not_initialized',
                message: 'Narya.initialize() has not completed.',
              );
            },
          );

      await expectLater(
        Narya.identify(userId: 'user-123'),
        throwsA(
          isA<NaryaException>().having(
            (NaryaException e) => e.code,
            'code',
            'not_initialized',
          ),
        ),
      );
    });
  });
}

/// The native identity state, reduced to the rules `identify` depends on.
///
/// Mirrors what both native SDKs do with the arguments the bridge hands them
/// (`narya-android` `Analytics.identify` plus `SetUserIdAndTraitsAction`, and
/// its `narya-ios` counterpart):
///
/// * a `null` user id is a traits-only identify and never touches the identity;
/// * a user id that differs from a non-empty current one resets the identity
///   first - a fresh anonymous id, no traits;
/// * traits are merged into the existing ones whenever the user id is unchanged
///   and replace them when it changed.
class _FakeNativeIdentity {
  /// The current user id; empty while the user is anonymous.
  String userId = '';

  /// The current anonymous id, rebuilt by every reset.
  String anonymousId = 'anon-0';

  /// The traits stored for the current identity.
  Map<String, Object?> traits = <String, Object?>{};

  /// How many times the native reset path ran.
  int resetCount = 0;

  int _anonymousIdSerial = 0;

  /// Applies one bridged `identify` call.
  void identify(String? newUserId, Map<Object?, Object?>? newTraits) {
    final Map<String, Object?> incoming = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry
          in (newTraits ?? const <Object?, Object?>{}).entries)
        entry.key.toString(): entry.value,
    };

    // A traits-only identify: the identity stands, the traits merge.
    if (newUserId == null) {
      traits = <String, Object?>{...traits, ...incoming};
      return;
    }

    if (userId.isNotEmpty && userId != newUserId) {
      _reset();
    }

    final bool userIdChanged = userId != newUserId;
    userId = newUserId;
    traits = userIdChanged
        ? incoming
        : <String, Object?>{...traits, ...incoming};
  }

  void _reset() {
    resetCount++;
    _anonymousIdSerial++;
    anonymousId = 'anon-$_anonymousIdSerial';
    userId = '';
    traits = <String, Object?>{};
  }
}
