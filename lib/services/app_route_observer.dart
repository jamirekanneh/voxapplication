import 'package:flutter/material.dart';

/// Shared [RouteObserver] for [RouteAware] widgets (e.g. full-screen reader).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
