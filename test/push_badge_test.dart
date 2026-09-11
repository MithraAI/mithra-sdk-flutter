import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';
import 'package:mithra_flutter_sdk/src/channels.dart';

// Covers the app icon badge surface: the `push.setBadgeCount` method call, its
// argument map and the clamping `setBadgeCount` / `clearBadge` apply before
// the platform is reached. What the platforms then do with the count - iOS
// UNUserNotificationCenter / UIApplication, Android nothing - is native
// behaviour and is not exercised here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Narya.push badge control', () {
    final List<MethodCall> calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            (MethodCall call) async {
              calls.add(call);
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

    /// The single argument the bridge reads, for the last recorded call.
    int lastCount() {
      final Map<Object?, Object?> arguments =
          calls.last.arguments as Map<Object?, Object?>;
      return arguments['count']! as int;
    }

    test('setBadgeCount invokes push.setBadgeCount with the count', () async {
      await Narya.push.setBadgeCount(3);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'push.setBadgeCount');
      expect(calls.single.arguments, <String, Object?>{'count': 3});
    });

    test('a zero count is passed through, not skipped', () async {
      // Zero is the value that actually clears the badge, so it must reach
      // native rather than being optimised away.
      await Narya.push.setBadgeCount(0);

      expect(calls, hasLength(1));
      expect(lastCount(), 0);
    });

    test('negative counts are clamped to zero', () async {
      await Narya.push.setBadgeCount(-1);
      expect(lastCount(), 0);

      await Narya.push.setBadgeCount(-9999);
      expect(lastCount(), 0);

      expect(calls, hasLength(2));
      expect(
        calls.map((MethodCall call) => call.method),
        everyElement('push.setBadgeCount'),
      );
    });

    test('a positive count is never altered', () async {
      for (final int count in <int>[1, 2, 42, 1000]) {
        await Narya.push.setBadgeCount(count);
        expect(lastCount(), count, reason: 'setBadgeCount($count)');
      }
    });

    test('clearBadge is setBadgeCount(0) on the same method', () async {
      await Narya.push.clearBadge();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'push.setBadgeCount');
      expect(calls.single.arguments, <String, Object?>{'count': 0});
    });

    test('translates a native error into NaryaException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            (MethodCall call) async {
              throw PlatformException(
                code: 'badge_failed',
                message: 'the system refused the badge update',
              );
            },
          );

      await expectLater(
        Narya.push.clearBadge(),
        throwsA(
          isA<NaryaException>()
              .having((NaryaException e) => e.code, 'code', 'badge_failed')
              .having(
                (NaryaException e) => e.message,
                'message',
                'the system refused the badge update',
              ),
        ),
      );
    });
  });
}
