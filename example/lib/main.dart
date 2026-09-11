// A deliberately minimal host for the mithra_flutter_sdk plugin. The full-featured
// demo, including push, in-app messages and the inbox, lives in the separate
// narya-demo-flutter repository.

import 'package:flutter/material.dart';
import 'package:mithra_flutter_sdk/mithra_flutter_sdk.dart';

void main() {
  runApp(const ExampleApp());
}

/// The example application root.
class ExampleApp extends StatelessWidget {
  /// Creates the example application.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mithra_flutter_sdk example',
      navigatorObservers: <NavigatorObserver>[NaryaRouteObserver()],
      home: const HomePage(),
    );
  }
}

/// The single screen of the example application.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'Not initialized';

  Future<void> _run(String label, Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        setState(() => _status = '$label: ok');
      }
    } on NaryaException catch (error) {
      if (mounted) {
        setState(() => _status = '$label: ${error.code} ${error.message}');
      }
    }
  }

  Future<void> _initialize() {
    return _run(
      'initialize',
      () => Narya.initialize(
        const NaryaConfiguration(
          writeKey: '<MITHRA_FLUTTER_WRITE_KEY>',
          environment: NaryaEnvironment.staging,
          logLevel: NaryaLogLevel.debug,
        ),
      ),
    );
  }

  Future<void> _track() {
    return _run(
      'track',
      () => Narya.track(
        'example_button_tapped',
        properties: <String, Object?>{'source': 'example_app'},
      ),
    );
  }

  Future<void> _screen() {
    return _run('screen', () => Narya.screen('Example Home'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('mithra_flutter_sdk example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_status, textAlign: TextAlign.center),
            ),
            FilledButton(
              onPressed: _initialize,
              child: const Text('initialize'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _track, child: const Text('track')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _screen, child: const Text('screen')),
          ],
        ),
      ),
    );
  }
}
