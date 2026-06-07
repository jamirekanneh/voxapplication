import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../navigation_keys.dart';
import '../tts_service.dart';
import 'mic_coordinator.dart';

/// Updates [MicCoordinator] when the user navigates between main routes.
class MicRouteObserver extends NavigatorObserver {
  void _sync(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      MicCoordinator.instance.setRoute(name);
      _ensureMiniPlayerVisibleOnNamedRoute();
    }
  }

  /// Reader hides the global bar while it is the top route; any named route on
  /// top means the user left the reader UI and should see pause/skip controls.
  void _ensureMiniPlayerVisibleOnNamedRoute() {
    final ctx = globalNavigatorKey.currentContext;
    if (ctx == null) return;
    final tts = ctx.read<TtsService>();
    if (tts.isVisible) {
      tts.setSuppressGlobalMiniPlayer(false);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _sync(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(previousRoute);
    super.didRemove(route, previousRoute);
  }
}
