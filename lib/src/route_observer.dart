import 'package:flutter/widgets.dart';

import 'narya.dart';

/// Tracks a `screen` event whenever a named route is pushed or popped back to.
///
/// This is the Flutter equivalent of the native automatic screen tracking
/// (Android `setNavigationDestinationsTracking`, iOS
/// `trackApplicationScreens`), both of which stay off: a Flutter app is a
/// single native view controller or activity, so native auto-tracking would
/// emit one meaningless screen event for the whole app.
///
/// Install it on your navigator:
///
/// ```dart
/// MaterialApp(navigatorObservers: [NaryaRouteObserver()]);
/// ```
///
/// or, with `go_router`, pass it in `observers:`.
///
/// By default the screen name is `route.settings.name` and unnamed routes are
/// skipped. Supply `screenNameResolver` to name routes yourself - return an
/// empty string to skip a route - and `propertiesResolver` to attach
/// properties, for example the route arguments.
class NaryaRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  /// Creates a route observer.
  NaryaRouteObserver({
    String Function(Route<dynamic> route)? screenNameResolver,
    Map<String, Object?> Function(Route<dynamic> route)? propertiesResolver,
  }) : _screenNameResolver = screenNameResolver ?? _defaultScreenName,
       _propertiesResolver = propertiesResolver;

  final String Function(Route<dynamic> route) _screenNameResolver;
  final Map<String, Object?> Function(Route<dynamic> route)?
  _propertiesResolver;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _track(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _track(newRoute);
    }
  }

  void _track(Route<dynamic> route) {
    if (route is! PageRoute) {
      return;
    }
    final String name = _screenNameResolver(route);
    if (name.isEmpty) {
      return;
    }
    // Fire and forget: a screen event must never delay a navigation frame, and
    // a tracking failure must never surface as an unhandled navigator error.
    Narya.screen(name, properties: _propertiesResolver?.call(route)).ignore();
  }

  static String _defaultScreenName(Route<dynamic> route) {
    return route.settings.name ?? '';
  }
}
