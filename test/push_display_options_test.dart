import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';
import 'package:mithra_flutter_sdk/src/channels.dart';

// Covers the Dart half of `Narya.push.handlePushMessage`: the
// `NaryaPushDisplayOptions` wire encoding and the `push.handlePushMessage`
// method call / reply. Native rendering (the Narya Android SDK) is not
// exercised here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaryaPushDisplayOptions', () {
    test('defaults are all unset and encode to an empty map', () {
      const NaryaPushDisplayOptions options = NaryaPushDisplayOptions();
      expect(options.smallIcon, isNull);
      expect(options.tapActivity, isNull);
      expect(options.channelId, isNull);
      expect(options.channelName, isNull);
      expect(options.toMap(), isEmpty);
    });

    test('default channel constants match the native SDK', () {
      // DEFAULT_CHANNEL_ID / DEFAULT_CHANNEL_NAME in narya-android's
      // PushDisplayOptions.kt.
      expect(NaryaPushDisplayOptions.defaultChannelId, 'narya_default');
      expect(NaryaPushDisplayOptions.defaultChannelName, 'Notifications');
    });

    test('encodes every set field under its wire key', () {
      const NaryaPushDisplayOptions options = NaryaPushDisplayOptions(
        smallIcon: 'ic_notification',
        tapActivity: 'com.example.app.MainActivity',
        channelId: 'marketing',
        channelName: 'Offers and updates',
      );
      expect(options.toMap(), <String, Object?>{
        'smallIcon': 'ic_notification',
        'tapActivity': 'com.example.app.MainActivity',
        'channelId': 'marketing',
        'channelName': 'Offers and updates',
      });
    });

    test('emits only the fields that are set', () {
      const NaryaPushDisplayOptions options = NaryaPushDisplayOptions(
        smallIcon: 'ic_notification',
      );
      expect(options.toMap(), <String, Object?>{
        'smallIcon': 'ic_notification',
      });
    });

    test('blank strings count as unset', () {
      const NaryaPushDisplayOptions options = NaryaPushDisplayOptions(
        smallIcon: '',
        tapActivity: '   ',
        channelId: '\t',
        channelName: 'Offers',
      );
      expect(options.toMap(), <String, Object?>{'channelName': 'Offers'});
    });

    test('is a const-constructible value usable as a default argument', () {
      const NaryaPushDisplayOptions a = NaryaPushDisplayOptions();
      const NaryaPushDisplayOptions b = NaryaPushDisplayOptions();
      expect(identical(a, b), isTrue);
    });

    test('toString names the type and every field', () {
      const NaryaPushDisplayOptions options = NaryaPushDisplayOptions(
        smallIcon: 'ic_notification',
      );
      expect(options.toString(), contains('NaryaPushDisplayOptions'));
      expect(options.toString(), contains('ic_notification'));
    });
  });

  group('Narya.push.handlePushMessage', () {
    final List<MethodCall> calls = <MethodCall>[];
    Object? reply;

    setUp(() {
      calls.clear();
      reply = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            (MethodCall call) async {
              calls.add(call);
              return reply;
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

    test(
      'invokes push.handlePushMessage with payload and encoded options',
      () async {
        final Map<String, Object?> data = <String, Object?>{
          'title': 'Your order shipped',
          'body': 'Arriving Thursday.',
          'tracking': '{"uj":"a","node":"b","tpl":"c"}',
          'message_id': '5f2c',
        };
        final bool posted = await Narya.push.handlePushMessage(
          data,
          options: const NaryaPushDisplayOptions(
            smallIcon: 'ic_notification',
            channelId: 'marketing',
          ),
        );

        expect(posted, isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.method, 'push.handlePushMessage');
        final Map<Object?, Object?> arguments =
            calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['payload'], data);
        expect(arguments['options'], <String, Object?>{
          'smallIcon': 'ic_notification',
          'channelId': 'marketing',
        });
      },
    );

    test('sends an empty options map by default', () async {
      await Narya.push.handlePushMessage(<String, Object?>{'tracking': 'x'});
      final Map<Object?, Object?> arguments =
          calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['options'], isEmpty);
    });

    test('accepts the loosely-typed map firebase_messaging yields', () async {
      final Map<String, dynamic> data = <String, dynamic>{
        'tracking': '{"uj":"a"}',
        'is_silent': 'true',
      };
      reply = false;
      expect(await Narya.push.handlePushMessage(data), isFalse);
    });

    test('a false reply (silent payload, or iOS) is returned as is', () async {
      reply = false;
      expect(
        await Narya.push.handlePushMessage(<String, Object?>{
          'inapp_sync': 'true',
          'is_silent': 'true',
        }),
        isFalse,
      );
    });

    test('translates a native error into NaryaException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NaryaChannels.methods),
            (MethodCall call) async {
              throw PlatformException(
                code: 'not_initialized',
                message: 'no persisted configuration',
              );
            },
          );
      await expectLater(
        Narya.push.handlePushMessage(<String, Object?>{'tracking': 'x'}),
        throwsA(
          isA<NaryaException>().having(
            (NaryaException e) => e.code,
            'code',
            'not_initialized',
          ),
        ),
      );
    });

    test('a null reply is a native_error', () async {
      reply = null;
      await expectLater(
        Narya.push.handlePushMessage(<String, Object?>{'tracking': 'x'}),
        throwsA(
          isA<NaryaException>().having(
            (NaryaException e) => e.code,
            'code',
            'native_error',
          ),
        ),
      );
    });
  });
}
