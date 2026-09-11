import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';
import 'package:mithra_flutter_sdk/src/channels.dart';

// Covers the `inapp_deep_link` envelope: its wire shape, how it is decoded
// into `NaryaInAppDeepLinkEvent`, and that `NaryaInAppManager.onDeepLink`
// filters it out of the shared event stream without touching `push_opened`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaryaEventType', () {
    test('inapp_deep_link is the wire discriminator', () {
      // Part of the binary contract with both native bridges; see
      // docs/api-contract.md section 9.
      expect(NaryaEventType.inAppDeepLink, 'inapp_deep_link');
    });
  });

  group('NaryaInAppDeepLinkEvent.tryFromMap', () {
    test('decodes url and messageId', () {
      final NaryaInAppDeepLinkEvent? event = NaryaInAppDeepLinkEvent.tryFromMap(
        <String, Object?>{
          'url': 'myapp://products/42?ref=inapp',
          'messageId': 'msg-1',
        },
      );
      expect(event, isNotNull);
      expect(event!.url, Uri.parse('myapp://products/42?ref=inapp'));
      expect(event.url.scheme, 'myapp');
      // A custom scheme has no authority delimiter of its own, so `Uri` reads
      // the first segment as the host and only the rest as the path. Hosts
      // routing these must join the two, which is what the `onDeepLink`
      // dartdoc shows.
      expect(event.url.host, 'products');
      expect(event.url.path, '/42');
      expect(event.url.queryParameters['ref'], 'inapp');
      expect(event.messageId, 'msg-1');
    });

    test('accepts https destinations', () {
      final NaryaInAppDeepLinkEvent? event = NaryaInAppDeepLinkEvent.tryFromMap(
        <String, Object?>{
          'url': 'https://example.com/sale',
          'messageId': 'msg-2',
        },
      );
      expect(event?.url.host, 'example.com');
    });

    test('missing messageId decodes to an empty string', () {
      final NaryaInAppDeepLinkEvent? event = NaryaInAppDeepLinkEvent.tryFromMap(
        <String, Object?>{'url': 'myapp://home'},
      );
      expect(event, isNotNull);
      expect(event!.messageId, '');
    });

    test('missing url is dropped', () {
      expect(
        NaryaInAppDeepLinkEvent.tryFromMap(<String, Object?>{
          'messageId': 'msg-3',
        }),
        isNull,
      );
    });

    test('empty url is dropped', () {
      expect(
        NaryaInAppDeepLinkEvent.tryFromMap(<String, Object?>{
          'url': '',
          'messageId': 'msg-3',
        }),
        isNull,
      );
    });

    test('non-string url is dropped', () {
      expect(
        NaryaInAppDeepLinkEvent.tryFromMap(<String, Object?>{
          'url': 42,
          'messageId': 'msg-3',
        }),
        isNull,
      );
    });

    test('unparseable url is dropped', () {
      expect(
        NaryaInAppDeepLinkEvent.tryFromMap(<String, Object?>{
          'url': 'http://[::1',
          'messageId': 'msg-3',
        }),
        isNull,
      );
    });
  });

  group('NaryaInAppManager.onDeepLink', () {
    const EventChannel channel = EventChannel('test/in_app_deep_link_events');
    late NaryaInAppManager manager;

    setUp(() {
      manager = NaryaInAppManager(NaryaPlatform(eventChannel: channel));
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

    test('decodes inapp_deep_link envelopes', () async {
      emit(<Object?>[
        <Object?, Object?>{
          'type': 'inapp_deep_link',
          'payload': <Object?, Object?>{
            'url': 'myapp://products/42',
            'messageId': 'msg-1',
          },
        },
      ]);

      final List<NaryaInAppDeepLinkEvent> events = await manager.onDeepLink
          .toList();
      expect(events, hasLength(1));
      expect(events.single.url, Uri.parse('myapp://products/42'));
      expect(events.single.messageId, 'msg-1');
    });

    test('ignores push_opened and other envelope types', () async {
      emit(<Object?>[
        <Object?, Object?>{
          'type': 'push_opened',
          'payload': <Object?, Object?>{
            'payload': <Object?, Object?>{'aps': <Object?, Object?>{}},
            'deepLink': 'myapp://from-push',
            'messageId': 'push-1',
            'isBodyTap': true,
            'isActionButtonTap': false,
          },
        },
        <Object?, Object?>{
          'type': 'unread_count_changed',
          'payload': <Object?, Object?>{'count': 3},
        },
        <Object?, Object?>{
          'type': 'inapp_deep_link',
          'payload': <Object?, Object?>{
            'url': 'myapp://from-inapp',
            'messageId': 'msg-2',
          },
        },
      ]);

      final List<NaryaInAppDeepLinkEvent> events = await manager.onDeepLink
          .toList();
      expect(
        events.map((NaryaInAppDeepLinkEvent e) => e.url.toString()),
        <String>['myapp://from-inapp'],
      );
    });

    test('drops envelopes whose url is missing or invalid', () async {
      emit(<Object?>[
        <Object?, Object?>{
          'type': 'inapp_deep_link',
          'payload': <Object?, Object?>{'messageId': 'no-url'},
        },
        <Object?, Object?>{
          'type': 'inapp_deep_link',
          'payload': <Object?, Object?>{'url': '', 'messageId': 'empty-url'},
        },
        <Object?, Object?>{
          'type': 'inapp_deep_link',
          'payload': <Object?, Object?>{'url': 'myapp://ok', 'messageId': 'ok'},
        },
      ]);

      final List<NaryaInAppDeepLinkEvent> events = await manager.onDeepLink
          .toList();
      expect(events, hasLength(1));
      expect(events.single.messageId, 'ok');
    });

    test('is a broadcast stream so several screens may listen', () async {
      emit(<Object?>[
        <Object?, Object?>{
          'type': 'inapp_deep_link',
          'payload': <Object?, Object?>{'url': 'myapp://a', 'messageId': 'a'},
        },
      ]);

      final Stream<NaryaInAppDeepLinkEvent> stream = manager.onDeepLink;
      expect(stream.isBroadcast, isTrue);

      final Completer<Uri> first = Completer<Uri>();
      final Completer<Uri> second = Completer<Uri>();
      final StreamSubscription<NaryaInAppDeepLinkEvent> subA = stream.listen(
        (NaryaInAppDeepLinkEvent e) => first.complete(e.url),
      );
      final StreamSubscription<NaryaInAppDeepLinkEvent> subB = stream.listen(
        (NaryaInAppDeepLinkEvent e) => second.complete(e.url),
      );

      expect(await first.future, Uri.parse('myapp://a'));
      expect(await second.future, Uri.parse('myapp://a'));
      await subA.cancel();
      await subB.cancel();
    });
  });
}
