import 'package:flutter_test/flutter_test.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';

// `isNaryaPush` is pure Dart: it never touches a platform channel, so no
// channel mocking is needed and `Narya.initialize` is never called here.
//
// Every expectation below mirrors the iOS reference implementation
// (`PushNotificationPayload.isNaryaPush` in narya-ios) and the Android
// `IsNaryaPushPayloadTest`; see docs/api-contract.md for the parity table.
void main() {
  group('NaryaPushManager.isNaryaPush', () {
    bool gate(Map<Object?, Object?> payload) => Narya.push.isNaryaPush(payload);

    group('rule 1: tracking', () {
      test('top-level tracking blob', () {
        expect(
          gate(<String, Object?>{
            'message_id': 'feed-1',
            'tracking': '{"uj":"a","node":"b","tpl":"c"}',
          }),
          isTrue,
        );
      });

      test('empty string is not present', () {
        expect(gate(<String, Object?>{'tracking': ''}), isFalse);
      });

      test('whitespace-only string is present, like on iOS', () {
        // iOS isNonEmptyValue tests String.isEmpty without trimming.
        expect(gate(<String, Object?>{'tracking': '   '}), isTrue);
      });

      test('already-decoded map counts only when non-empty', () {
        expect(
          gate(<String, Object?>{
            'tracking': <String, Object?>{'uj': 'a'},
          }),
          isTrue,
        );
        expect(
          gate(<String, Object?>{'tracking': <String, Object?>{}}),
          isFalse,
        );
      });

      test('any other non-null value counts as present', () {
        // Mirrors the iOS default branch: numbers, booleans and lists (even
        // empty ones) are present.
        expect(gate(<String, Object?>{'tracking': 1}), isTrue);
        expect(gate(<String, Object?>{'tracking': false}), isTrue);
        expect(gate(<String, Object?>{'tracking': <Object?>[]}), isTrue);
      });

      test('null is absent', () {
        expect(gate(<String, Object?>{'tracking': null}), isFalse);
      });
    });

    group('rule 2: inapp_sync', () {
      test('every accepted truthy shape', () {
        for (final Object? flag in <Object?>[
          true,
          'true',
          'TRUE',
          '1',
          1,
          2,
          -1,
          1.5,
          'yes',
          'Yes',
        ]) {
          expect(
            gate(<String, Object?>{'inapp_sync': flag}),
            isTrue,
            reason: 'inapp_sync=$flag should be truthy',
          );
        }
      });

      test('falsy shapes', () {
        for (final Object? flag in <Object?>[
          false,
          'false',
          '0',
          0,
          0.0,
          '',
          'no',
          null,
          <String, Object?>{},
          <Object?>[1],
        ]) {
          expect(
            gate(<String, Object?>{'inapp_sync': flag}),
            isFalse,
            reason: 'inapp_sync=$flag should be falsy',
          );
        }
      });

      test('padded strings are not trimmed, like on iOS', () {
        expect(gate(<String, Object?>{'inapp_sync': ' YES '}), isFalse);
        expect(gate(<String, Object?>{'inapp_sync': 'true '}), isFalse);
      });
    });

    group('rule 3: mithra_message_id', () {
      test('non-empty string', () {
        expect(gate(<String, Object?>{'mithra_message_id': 'feed-1'}), isTrue);
      });

      test('empty string is not present', () {
        expect(gate(<String, Object?>{'mithra_message_id': ''}), isFalse);
      });

      test('whitespace-only string is present, like on iOS', () {
        expect(gate(<String, Object?>{'mithra_message_id': ' '}), isTrue);
      });

      test('non-string values never match', () {
        expect(gate(<String, Object?>{'mithra_message_id': 5}), isFalse);
        expect(gate(<String, Object?>{'mithra_message_id': true}), isFalse);
        expect(
          gate(<String, Object?>{'mithra_message_id': <String, Object?>{}}),
          isFalse,
        );
      });
    });

    group('rule 4: mithra envelope', () {
      test('object as a map, including an empty one', () {
        expect(
          gate(<String, Object?>{
            'mithra': <String, Object?>{'title': 'hello'},
          }),
          isTrue,
        );
        expect(gate(<String, Object?>{'mithra': <String, Object?>{}}), isTrue);
      });

      test('object as a JSON string, including an empty one', () {
        expect(gate(<String, Object?>{'mithra': '{"title":"hello"}'}), isTrue);
        expect(gate(<String, Object?>{'mithra': '{}'}), isTrue);
        expect(
          gate(<String, Object?>{'mithra': ' {"title":"hello"} '}),
          isTrue,
        );
      });

      test('non-object values do not count', () {
        for (final Object? value in <Object?>[
          null,
          '',
          '   ',
          'yes',
          '"{}"',
          '42',
          42,
          true,
          '[]',
          '[{"title":"hello"}]',
          <Object?>[],
          'null',
          '{not-json',
        ]) {
          expect(
            gate(<String, Object?>{'mithra': value}),
            isFalse,
            reason: 'mithra=$value should not be an envelope',
          );
        }
      });

      test('marker keys nested in the mithra envelope', () {
        expect(
          gate(<String, Object?>{'mithra': '{"mithra_message_id":"feed-1"}'}),
          isTrue,
        );
        expect(
          gate(<String, Object?>{
            'mithra': <String, Object?>{'inapp_sync': true},
          }),
          isTrue,
        );
      });

      test('a mithra object nested inside CustomData is not the envelope', () {
        expect(
          gate(<String, Object?>{
            'CustomData': <String, Object?>{
              'mithra': <String, Object?>{'title': 'hello'},
            },
          }),
          isFalse,
        );
        expect(
          gate(<String, Object?>{
            'CustomData': '{"mithra":"{\\"tracking\\":\\"x\\"}"}',
          }),
          isFalse,
        );
      });
    });

    group('CustomData level', () {
      test('as a JSON string', () {
        expect(
          gate(<String, Object?>{
            'CustomData': '{"tracking":"{\\"uj\\":\\"a\\"}"}',
          }),
          isTrue,
        );
        expect(
          gate(<String, Object?>{'CustomData': '{"inapp_sync":"1"}'}),
          isTrue,
        );
        expect(
          gate(<String, Object?>{
            'CustomData': '{"mithra_message_id":"feed-1"}',
          }),
          isTrue,
        );
      });

      test('as a map', () {
        expect(
          gate(<String, Object?>{
            'CustomData': <String, Object?>{'tracking': '{"uj":"a"}'},
          }),
          isTrue,
        );
        expect(
          gate(<String, Object?>{
            'CustomData': <String, Object?>{'inapp_sync': true},
          }),
          isTrue,
        );
      });

      test('nested tracking object counts only when non-empty', () {
        expect(
          gate(<String, Object?>{'CustomData': '{"tracking":{"uj":"a"}}'}),
          isTrue,
        );
        expect(
          gate(<String, Object?>{'CustomData': '{"tracking":{}}'}),
          isFalse,
        );
        expect(
          gate(<String, Object?>{'CustomData': '{"tracking":""}'}),
          isFalse,
        );
      });

      test('malformed or non-object CustomData is ignored, not thrown', () {
        expect(gate(<String, Object?>{'CustomData': 'not-json'}), isFalse);
        expect(gate(<String, Object?>{'CustomData': '[]'}), isFalse);
        expect(gate(<String, Object?>{'CustomData': ''}), isFalse);
        expect(
          gate(<String, Object?>{'CustomData': 'not-json', 'tracking': '{}'}),
          isTrue,
        );
      });
    });

    group('level independence', () {
      test('a blank root marker does not mask a valid nested one', () {
        // Each level is evaluated on its own, as on iOS; there is no
        // root-wins precedence in this predicate.
        expect(
          gate(<String, Object?>{
            'tracking': '',
            'CustomData': '{"tracking":"{\\"uj\\":\\"a\\"}"}',
          }),
          isTrue,
        );
        expect(
          gate(<String, Object?>{
            'inapp_sync': 'false',
            'mithra': <String, Object?>{'inapp_sync': true},
          }),
          isTrue,
        );
        expect(
          gate(<String, Object?>{
            'mithra_message_id': '',
            'CustomData': <String, Object?>{'mithra_message_id': 'feed-1'},
          }),
          isTrue,
        );
      });

      test('a valid root marker wins regardless of a blank nested one', () {
        expect(
          gate(<String, Object?>{
            'CustomData': '{"tracking":""}',
            'tracking': '{"uj":"a"}',
          }),
          isTrue,
        );
      });
    });

    group('negative rules', () {
      test('empty map', () {
        expect(gate(<String, Object?>{}), isFalse);
      });

      test('gcm.message_id alone is not enough', () {
        expect(
          gate(<String, Object?>{'gcm.message_id': '1757000000000000'}),
          isFalse,
        );
      });

      test('bare message_id alone is not enough', () {
        expect(
          gate(<String, Object?>{
            'message_id': 'feed-1',
            'gcm.message_id': '1757000000000000',
            'title': 'hello',
            'body': 'world',
          }),
          isFalse,
        );
      });

      test('other-provider payload', () {
        expect(
          gate(<String, Object?>{
            'gcm.message_id': '1757000000000000',
            'google.c.sender.id': '123',
            'campaign': 'braze-1',
          }),
          isFalse,
        );
      });

      test('non-string keys are ignored', () {
        expect(gate(<Object?, Object?>{1: 'tracking', null: 'x'}), isFalse);
      });
    });

    test('accepts the loosely-typed map firebase_messaging yields', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'tracking': '{"uj":"a"}',
      };
      expect(gate(data), isTrue);
    });

    test('accepts a real gwaihir data-only payload', () {
      expect(
        gate(<String, Object?>{
          'title': 'Your order shipped',
          'body': 'Arriving Thursday.',
          'actions': '',
          'is_silent': 'false',
          'tracking': '{"uj":"a","node":"b","tpl":"c"}',
          'message_id': '5f2c',
          'user_journey_uuid': 'a',
          'node_id': 'b',
          'template_id': 'c',
          'user_id': 'u',
          'gcm.message_id': '0:1700000000%abcdef',
        }),
        isTrue,
      );
    });
  });
}
