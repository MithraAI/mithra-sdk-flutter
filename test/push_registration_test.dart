import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';
import 'package:mithra_flutter_sdk/src/channels.dart';
import 'package:mithra_flutter_sdk/src/push_models.dart';

// Covers the native APNs registration surface: the
// `push.registerForRemoteNotifications` method call and its status reply, and
// the `push_token` / `push_registration_error` event envelopes that feed
// `Narya.push.onToken` / `Narya.push.onRegistrationError`. Native behaviour
// (UNUserNotificationCenter, UIApplication) is not exercised here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaryaEventType', () {
    test(
      'push_token and push_registration_error are the wire discriminators',
      () {
        // Part of the binary contract with the iOS bridge; see
        // docs/api-contract.md section 9.
        expect(NaryaEventType.pushToken, 'push_token');
        expect(NaryaEventType.pushRegistrationError, 'push_registration_error');
      },
    );
  });

  group('NaryaPushAuthorizationStatus', () {
    test('has exactly the five contract members', () {
      expect(
        NaryaPushAuthorizationStatus.values,
        <NaryaPushAuthorizationStatus>[
          NaryaPushAuthorizationStatus.authorized,
          NaryaPushAuthorizationStatus.provisional,
          NaryaPushAuthorizationStatus.denied,
          NaryaPushAuthorizationStatus.notDetermined,
          NaryaPushAuthorizationStatus.unsupported,
        ],
      );
    });

    test('decodes every wire value', () {
      expect(
        decodeNaryaPushAuthorizationStatus('authorized'),
        NaryaPushAuthorizationStatus.authorized,
      );
      expect(
        decodeNaryaPushAuthorizationStatus('provisional'),
        NaryaPushAuthorizationStatus.provisional,
      );
      expect(
        decodeNaryaPushAuthorizationStatus('denied'),
        NaryaPushAuthorizationStatus.denied,
      );
      expect(
        decodeNaryaPushAuthorizationStatus('notDetermined'),
        NaryaPushAuthorizationStatus.notDetermined,
      );
      expect(
        decodeNaryaPushAuthorizationStatus('unsupported'),
        NaryaPushAuthorizationStatus.unsupported,
      );
    });

    test('unknown, null and non-string values decode to unsupported', () {
      for (final Object? raw in <Object?>[
        null,
        '',
        'ephemeral',
        'AUTHORIZED',
        1,
      ]) {
        expect(
          decodeNaryaPushAuthorizationStatus(raw),
          NaryaPushAuthorizationStatus.unsupported,
          reason: 'raw=$raw',
        );
      }
    });
  });

  group('NaryaPushRegistrationError.fromMap', () {
    test('decodes code and message', () {
      final NaryaPushRegistrationError error =
          NaryaPushRegistrationError.fromMap(<String, Object?>{
            'code': 'NSCocoaErrorDomain:3000',
            'message': 'no valid aps-environment entitlement string found',
          });
      expect(error.code, 'NSCocoaErrorDomain:3000');
      expect(
        error.message,
        'no valid aps-environment entitlement string found',
      );
      expect(
        error.toString(),
        'NaryaPushRegistrationError(NSCocoaErrorDomain:3000): '
        'no valid aps-environment entitlement string found',
      );
    });

    test('missing or empty code falls back to registration_failed', () {
      expect(
        NaryaPushRegistrationError.fromMap(<String, Object?>{
          'message': 'x',
        }).code,
        NaryaPushRegistrationError.fallbackCode,
      );
      expect(
        NaryaPushRegistrationError.fromMap(<String, Object?>{
          'code': '',
          'message': 'x',
        }).code,
        'registration_failed',
      );
      expect(
        NaryaPushRegistrationError.fromMap(<String, Object?>{'code': 42}).code,
        'registration_failed',
      );
    });

    test('missing or non-string message decodes to an empty string', () {
      expect(
        NaryaPushRegistrationError.fromMap(<String, Object?>{
          'code': 'c',
        }).message,
        '',
      );
      expect(
        NaryaPushRegistrationError.fromMap(<String, Object?>{
          'code': 'c',
          'message': 7,
        }).message,
        '',
      );
    });
  });

  group('NaryaPushManager.registerForRemoteNotifications', () {
    const MethodChannel channel = MethodChannel(
      'test/push_registration_methods',
    );
    late NaryaPushManager push;
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      push = NaryaPushManager(NaryaPlatform(methodChannel: channel));
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void reply(Object? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return handler(call);
          });
    }

    test(
      'sends the method name and all three options, defaulting to true',
      () async {
        reply((MethodCall _) => 'authorized');

        final NaryaPushAuthorizationStatus status = await push
            .registerForRemoteNotifications();

        expect(status, NaryaPushAuthorizationStatus.authorized);
        expect(calls, hasLength(1));
        expect(calls.single.method, 'push.registerForRemoteNotifications');
        expect(calls.single.arguments, <String, Object?>{
          'alert': true,
          'badge': true,
          'sound': true,
        });
      },
    );

    test('forwards explicit options', () async {
      reply((MethodCall _) => 'provisional');

      final NaryaPushAuthorizationStatus status = await push
          .registerForRemoteNotifications(
            alert: false,
            badge: false,
            sound: true,
          );

      expect(status, NaryaPushAuthorizationStatus.provisional);
      expect(calls.single.arguments, <String, Object?>{
        'alert': false,
        'badge': false,
        'sound': true,
      });
    });

    test('decodes denied and notDetermined', () async {
      reply((MethodCall _) => 'denied');
      expect(
        await push.registerForRemoteNotifications(),
        NaryaPushAuthorizationStatus.denied,
      );

      reply((MethodCall _) => 'notDetermined');
      expect(
        await push.registerForRemoteNotifications(),
        NaryaPushAuthorizationStatus.notDetermined,
      );
    });

    test('the Android reply decodes to unsupported', () async {
      reply((MethodCall _) => 'unsupported');
      expect(
        await push.registerForRemoteNotifications(),
        NaryaPushAuthorizationStatus.unsupported,
      );
    });

    test('a null reply decodes to unsupported rather than throwing', () async {
      reply((MethodCall _) => null);
      expect(
        await push.registerForRemoteNotifications(),
        NaryaPushAuthorizationStatus.unsupported,
      );
    });

    test(
      'a PlatformException surfaces as NaryaException with its code',
      () async {
        reply((MethodCall _) {
          throw PlatformException(
            code: 'authorization_failed',
            message: 'The operation could not be completed.',
          );
        });

        await expectLater(
          push.registerForRemoteNotifications(),
          throwsA(
            isA<NaryaException>().having(
              (NaryaException e) => e.code,
              'code',
              'authorization_failed',
            ),
          ),
        );
      },
    );

    test('a missing plugin surfaces as unsupported_platform', () async {
      // No handler registered: the channel raises MissingPluginException.
      await expectLater(
        push.registerForRemoteNotifications(),
        throwsA(
          isA<NaryaException>().having(
            (NaryaException e) => e.code,
            'code',
            'unsupported_platform',
          ),
        ),
      );
    });
  });

  group('NaryaPushManager.onToken / onRegistrationError', () {
    const EventChannel channel = EventChannel('test/push_registration_events');
    late NaryaPushManager push;

    setUp(() {
      push = NaryaPushManager(NaryaPlatform(eventChannel: channel));
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    });

    void emit(List<Object?> envelopes) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            channel,
            MockStreamHandler.inline(
              onListen: (Object? arguments, MockStreamHandlerEventSink events) {
                for (final Object? envelope in envelopes) {
                  events.success(envelope);
                }
                events.endOfStream();
              },
            ),
          );
    }

    const String hexToken =
        '740f4707bebcf74f9b7c25d48e3358945f6aa01da5ddb387462c7eaf61bb78ad';

    test('onToken decodes push_token envelopes', () async {
      emit(<Object?>[
        <Object?, Object?>{
          'type': 'push_token',
          'payload': <Object?, Object?>{'token': hexToken},
        },
      ]);

      expect(await push.onToken.toList(), <String>[hexToken]);
    });

    test(
      'onToken emits again on refresh and ignores other envelopes',
      () async {
        emit(<Object?>[
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': 'aa'},
          },
          <Object?, Object?>{
            'type': 'push_opened',
            'payload': <Object?, Object?>{
              'payload': <Object?, Object?>{'aps': <Object?, Object?>{}},
              'isBodyTap': true,
              'isActionButtonTap': false,
            },
          },
          <Object?, Object?>{
            'type': 'push_registration_error',
            'payload': <Object?, Object?>{'code': 'c', 'message': 'm'},
          },
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': 'bb'},
          },
        ]);

        expect(await push.onToken.toList(), <String>['aa', 'bb']);
      },
    );

    test(
      'onToken drops envelopes with a missing, empty or non-string token',
      () async {
        emit(<Object?>[
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{},
          },
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': ''},
          },
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': 12},
          },
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': 'cc'},
          },
        ]);

        expect(await push.onToken.toList(), <String>['cc']);
      },
    );

    test(
      'onRegistrationError decodes push_registration_error envelopes',
      () async {
        emit(<Object?>[
          <Object?, Object?>{
            'type': 'push_registration_error',
            'payload': <Object?, Object?>{
              'code': 'NSCocoaErrorDomain:3000',
              'message': 'no valid aps-environment entitlement string found',
            },
          },
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': 'aa'},
          },
        ]);

        final List<NaryaPushRegistrationError> errors = await push
            .onRegistrationError
            .toList();
        expect(errors, hasLength(1));
        expect(errors.single.code, 'NSCocoaErrorDomain:3000');
        expect(
          errors.single.message,
          'no valid aps-environment entitlement string found',
        );
      },
    );

    test('onRegistrationError tolerates an empty payload', () async {
      emit(<Object?>[
        <Object?, Object?>{
          'type': 'push_registration_error',
          'payload': <Object?, Object?>{},
        },
      ]);

      final List<NaryaPushRegistrationError> errors = await push
          .onRegistrationError
          .toList();
      expect(errors.single.code, 'registration_failed');
      expect(errors.single.message, '');
    });

    test(
      'both streams are broadcast so several listeners may attach',
      () async {
        emit(<Object?>[
          <Object?, Object?>{
            'type': 'push_token',
            'payload': <Object?, Object?>{'token': 'dd'},
          },
        ]);

        final Stream<String> tokens = push.onToken;
        expect(tokens.isBroadcast, isTrue);
        expect(push.onRegistrationError.isBroadcast, isTrue);

        final Completer<String> first = Completer<String>();
        final Completer<String> second = Completer<String>();
        final StreamSubscription<String> subA = tokens.listen(first.complete);
        final StreamSubscription<String> subB = tokens.listen(second.complete);

        expect(await first.future, 'dd');
        expect(await second.future, 'dd');
        await subA.cancel();
        await subB.cancel();
      },
    );
  });
}
