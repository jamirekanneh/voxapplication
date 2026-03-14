import 'package:flutter/material.dart';
import 'analytics_service.dart';

/// Add this mixin to any StatefulWidget State to automatically track
/// how long the user spends on that page.
///
/// Usage:
/// ```dart
/// class _MyPageState extends State<MyPage> with FeatureTrackingMixin {
///   @override
///   String get featureName => 'Home'; // displayed in Statistics
/// }
/// ```
mixin FeatureTrackingMixin<T extends StatefulWidget> on State<T> {
  /// Override to set the feature name logged in analytics.
  String get featureName;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.startFeatureSession(featureName);
  }

  @override
  void dispose() {
    AnalyticsService.instance.endFeatureSession(featureName);
    super.dispose();
  }
}
