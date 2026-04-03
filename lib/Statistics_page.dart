import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'analytics_service.dart';
import 'language_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  STATISTICS PAGE
//  Design tokens are identical to the rest of the VOX app:
//    • Background  : Color(0xFFF3E5AB)  cream
//    • Header      : Color(0xFFD4B96A)  gold  (same as MenuPage, AboutUsPage)
//    • Cards       : Color(0xFFE8E8E8)  light grey (same as AboutUsPage cards)
//    • Accent gold : Color(0xFFD4B96A)
//    • Dark text   : Color(0xFF1A1A1A)
// ─────────────────────────────────────────────────────────────────────────────

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  // ── Colour constants ─────────────────────────────────────
  static const Color _gold = Color(0xFFD4B96A);
  static const Color _cream = Color(0xFFF3E5AB);
  static const Color _card = Color(0xFFE8E8E8);
  static const Color _dark = Color(0xFF1A1A1A);

  // Five colours cycle across feature bars (gold first = top feature)
  static const List<Color> _barColors = [
    Color(0xFFD4B96A), // gold
    Color(0xFF5C8A6E), // teal
    Color(0xFF7A6BAB), // purple
    Color(0xFFB05C5C), // red
    Color(0xFF4A7FA0), // blue
  ];

  bool _loading = true;
  String _period = 'week'; // 'week' | 'month'
  bool _syncing = false;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.startFeatureSession('Statistics');
    _load();
  }

  @override
  void dispose() {
    AnalyticsService.instance.endFeatureSession('Statistics');
    super.dispose();
  }

  Future<void> _load() async {
    await AnalyticsService.instance.load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _syncData() async {
    setState(() => _syncing = true);
    try {
      await AnalyticsService.instance.syncToFirebase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Analytics synced to cloud'),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Formatting helpers ────────────────────────────────────
  String _fmt(int ms) {
    if (ms <= 0) return '0s';
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  double _pct(int ms, int total) =>
      total == 0 ? 0.0 : (ms / total).clamp(0.0, 1.0);

  String _shortDay(int wd) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][wd - 1];

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // rebuild on language switch
    return Scaffold(
      backgroundColor: _cream,
      body: Column(
        children: [
          _buildHeader(context),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: _gold)),
            )
          else
            Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  HEADER  — same pattern as AboutUsPage & ContactUsPage
  // ─────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: _gold,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          // Back button — identical to AboutUsPage style
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statistics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Your usage at a glance',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Sync button and decorative icon
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sync button
              GestureDetector(
                onTap: _syncing ? null : _syncData,
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
              // Decorative icon pill
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  BODY - SIMPLIFIED FOR DEVELOPER INSIGHTS
  // ─────────────────────────────────────────────────────────
  Widget _buildBody() {
    final svc = AnalyticsService.instance;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 0. SYNC STATUS / CONFIG ─────────────────────
          _sectionLabel('Sync status'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.sync_rounded,
                  label: 'Needs Sync',
                  value: svc.needsSync ? 'Yes' : 'No',
                  sub: svc.lastSync != null ? 'Last ${svc.lastSync}' : 'Never synced',
                  smallValue: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Analytics Opt-In',
                  value: svc.analyticsEnabled ? 'On' : 'Off',
                  sub: 'User preference',
                  smallValue: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ─── 1. KEY METRICS ─────────────────────────────
          _sectionLabel('Key Metrics'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.touch_app_rounded,
                  label: 'Daily Active Users',
                  value: svc.opensToday.toString(),
                  sub: 'opens today',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.timer_outlined,
                  label: 'Avg Session Time',
                  value: _fmt(svc.todayTotalMs ~/ (svc.opensToday == 0 ? 1 : svc.opensToday)),
                  sub: 'per session',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.book_outlined,
                  label: 'Dictionary Usage',
                  value: svc.totalDictLookups.toString(),
                  sub: 'total lookups',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.mic_outlined,
                  label: 'Voice Commands',
                  value: svc.totalVoiceCmds.toString(),
                  sub: 'total commands',
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─── 2. FEATURE ADOPTION ─────────────────────────
          _sectionLabel('Feature Adoption'),
          const SizedBox(height: 12),
          _featureAdoptionCard(svc),

          const SizedBox(height: 28),

          // ─── 3. USER RETENTION ───────────────────────────
          _sectionLabel('User Retention'),
          const SizedBox(height: 12),
          _retentionCard(svc),

          const SizedBox(height: 28),

          // ─── 4. PERFORMANCE METRICS ─────────────────────
          _sectionLabel('Performance Metrics'),
          const SizedBox(height: 12),
          _performanceCard(svc),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  SECTION LABEL  — same weight & style as About Us
  // ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: _dark,
      letterSpacing: -0.3,
    ),
  );

  // ─────────────────────────────────────────────────────────
  //  OVERVIEW CARD
  // ─────────────────────────────────────────────────────────
  Widget _overviewCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    bool smallValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon bubble
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _gold, size: 18),
          ),
          const SizedBox(height: 12),
          // Value
          Text(
            value,
            style: TextStyle(
              fontSize: smallValue ? 16 : 24,
              fontWeight: FontWeight.w900,
              color: _dark,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Label
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
          // Sub-label
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PERIOD TOGGLE  (This Week / This Month)
  // ─────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────
  //  TREND CARD  — custom bar chart, zero extra packages
  // ─────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────
  //  FEATURE BREAKDOWN CARD
  // ─────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────
  //  USER ENGAGEMENT CARD
  // ─────────────────────────────────────────────────────────
  Widget _engagementCard(AnalyticsService svc) {
    final totalOpens = svc.opens.length;
    final totalTime = svc.dailyMs.values.fold(0, (a, b) => a + b);
    final avgSession = totalOpens > 0 ? totalTime ~/ totalOpens : 0;
    final activeDays = svc.dailyDataFor(30).where((d) => d.ms > 0).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_outlined, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'Engagement Metrics',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _engagementMetric(
                  'Total Opens',
                  totalOpens.toString(),
                  Icons.touch_app_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _engagementMetric(
                  'Active Days',
                  '$activeDays/30',
                  Icons.calendar_today_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _engagementMetric(
                  'Total Time',
                  _fmt(totalTime),
                  Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _engagementMetric(
                  'Avg Session',
                  _fmt(avgSession),
                  Icons.access_time_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _engagementMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: _gold, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _dark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _getOperationIcon(String operation) {
    switch (operation.toLowerCase()) {
      case 'upload':
        return Icons.upload_file_outlined;
      case 'read':
        return Icons.visibility_outlined;
      case 'delete':
        return Icons.delete_outline;
      case 'restore':
        return Icons.restore_outlined;
      case 'edit':
        return Icons.edit_outlined;
      case 'share':
        return Icons.share_outlined;
      default:
        return Icons.file_present_outlined;
    }
  }

  String _formatOperationName(String operation) {
    switch (operation.toLowerCase()) {
      case 'upload':
        return 'Files Uploaded';
      case 'read':
        return 'Files Read';
      case 'delete':
        return 'Files Deleted';
      case 'restore':
        return 'Files Restored';
      case 'edit':
        return 'Files Edited';
      case 'share':
        return 'Files Shared';
      default:
        return operation.replaceAll('_', ' ').toUpperCase();
    }
  }

  // ─────────────────────────────────────────────────────────
  //  EMPTY STATE
  // ─────────────────────────────────────────────────────────
  Widget _emptyState(IconData icon, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 38, color: Colors.grey[350]),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[450],
              height: 1.55,
            ),
          ),
        ],
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────
  //  FEATURE ADOPTION CARD - SIMPLIFIED
  // ─────────────────────────────────────────────────────────
  Widget _featureAdoptionCard(AnalyticsService svc) {
    final features = svc.sortedFeatures.take(5).toList();
    final totalTime = features.fold(0, (sum, entry) => sum + entry.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: features.isEmpty
          ? _emptyState(Icons.bar_chart_outlined, 'No feature usage data yet')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_outlined, color: _gold, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Top Features by Time',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...features.asMap().entries.map((e) {
                  final rank = e.key;
                  final name = e.value.key;
                  final timeMs = e.value.value;
                  final percentage = totalTime > 0 ? (timeMs / totalTime * 100).round() : 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _barColors[rank.clamp(0, _barColors.length - 1)].withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${rank + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: _barColors[rank.clamp(0, _barColors.length - 1)],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _dark,
                                ),
                              ),
                              Text(
                                '${_fmt(timeMs)} ($percentage%)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  RETENTION CARD - SIMPLIFIED
  // ─────────────────────────────────────────────────────────
  Widget _retentionCard(AnalyticsService svc) {
    final today = DateTime.now();
    final weekAgo = today.subtract(const Duration(days: 7));
    final monthAgo = today.subtract(const Duration(days: 30));

    final recentOpens = svc.opens.where((date) => date.isAfter(weekAgo)).length;
    final monthlyOpens = svc.opens.where((date) => date.isAfter(monthAgo)).length;
    final totalOpens = svc.opens.length;

    final weeklyRetention = totalOpens > 0 ? (recentOpens / totalOpens * 100).round() : 0;
    final monthlyRetention = totalOpens > 0 ? (monthlyOpens / totalOpens * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.refresh_rounded, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'User Retention',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _retentionMetric(
                  '7-Day',
                  '$weeklyRetention%',
                  recentOpens,
                  Icons.calendar_view_week,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _retentionMetric(
                  '30-Day',
                  '$monthlyRetention%',
                  monthlyOpens,
                  Icons.calendar_view_month,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _retentionMetric(String period, String percentage, int count, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: _gold, size: 20),
          const SizedBox(height: 6),
          Text(
            percentage,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _dark,
            ),
          ),
          Text(
            period,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '$count opens',
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PERFORMANCE CARD - SIMPLIFIED
  // ─────────────────────────────────────────────────────────
  Widget _performanceCard(AnalyticsService svc) {
    final avgSessionTime = svc.opensToday > 0 ? svc.todayTotalMs ~/ svc.opensToday : 0;
    final totalFeatures = svc.sortedFeatures.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'Performance Metrics',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _performanceMetric(
                  'Avg Session',
                  _fmt(avgSessionTime),
                  'Duration',
                  Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _performanceMetric(
                  'Features Used',
                  totalFeatures.toString(),
                  'Total types',
                  Icons.category_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _performanceMetric(
                  'Total Time',
                  _fmt(svc.dailyMs.values.fold(0, (a, b) => a + b)),
                  'All sessions',
                  Icons.access_time_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _performanceMetric(
                  'Active Days',
                  svc.dailyDataFor(30).where((d) => d.ms > 0).length.toString(),
                  'Last 30 days',
                  Icons.calendar_today_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _performanceMetric(String title, String value, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: _gold, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _dark,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 8,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
