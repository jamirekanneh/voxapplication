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

  String _formatLastSync(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }
  }

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
                color: Colors.white.withOpacity(0.25),
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
                    color: Colors.white.withOpacity(0.2),
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
                  color: Colors.white.withOpacity(0.2),
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
  //  BODY
  // ─────────────────────────────────────────────────────────
  Widget _buildBody() {
    final svc = AnalyticsService.instance;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 1. OVERVIEW CARDS ──────────────────────────
          _sectionLabel('Overview'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.touch_app_rounded,
                  label: 'App Opens',
                  value: svc.opensThisWeek.toString(),
                  sub: 'this week',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.timer_outlined,
                  label: 'Time Today',
                  value: _fmt(svc.todayTotalMs),
                  sub: 'screen time',
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
                  label: 'Words Looked Up',
                  value: svc.totalDictLookups.toString(),
                  sub: '${svc.uniqueWordsLookedUp} unique',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.mic_outlined,
                  label: 'Voice Commands',
                  value: svc.totalVoiceCmds.toString(),
                  sub: '${svc.uniqueVoiceCmds} types',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.star_outline_rounded,
                  label: 'Most Used',
                  value: svc.mostUsedFeature ?? '—',
                  sub: 'favourite feature',
                  smallValue: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.today_outlined,
                  label: 'Opens Today',
                  value: svc.opensToday.toString(),
                  sub: 'today',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          // Sync status card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    svc.needsSync ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                    color: _gold,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        svc.needsSync ? 'Ready to sync' : 'Synced to cloud',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _dark,
                        ),
                      ),
                      Text(
                        svc.lastSync != null
                            ? 'Last sync: ${_formatLastSync(svc.lastSync!)}'
                            : 'Never synced',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (svc.needsSync)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Tap sync button',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _gold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ─── 2. USAGE TREND ─────────────────────────────
          _sectionLabel('Usage Trend'),
          const SizedBox(height: 10),
          _periodToggle(),
          const SizedBox(height: 12),
          _trendCard(svc),

          const SizedBox(height: 28),

          // ─── 3. TIME PER FEATURE ────────────────────────
          _sectionLabel('Time Per Feature'),
          const SizedBox(height: 12),
          _featureCard(svc),

          const SizedBox(height: 28),

          // ─── 4. ACTIVITY HEATMAP ────────────────────────
          _sectionLabel('Daily Activity  ·  last 4 weeks'),
          const SizedBox(height: 12),
          _heatmapCard(svc),

          const SizedBox(height: 28),

          // ─── 5. DICTIONARY USAGE ─────────────────────────
          _sectionLabel('Dictionary Usage'),
          const SizedBox(height: 12),
          _dictionaryCard(svc),

          const SizedBox(height: 28),

          // ─── 6. VOICE COMMANDS ───────────────────────────
          _sectionLabel('Voice Commands'),
          const SizedBox(height: 12),
          _voiceCommandsCard(svc),

          const SizedBox(height: 28),

          // ─── 7. FILE OPERATIONS ──────────────────────────
          _sectionLabel('File Operations'),
          const SizedBox(height: 12),
          _fileOperationsCard(svc),

          const SizedBox(height: 28),

          // ─── 8. USER ENGAGEMENT ──────────────────────────
          _sectionLabel('User Engagement'),
          const SizedBox(height: 12),
          _engagementCard(svc),
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
            color: Colors.black.withOpacity(0.05),
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
              color: _gold.withOpacity(0.18),
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
  Widget _periodToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['week', 'month'].map((p) {
          final active = _period == p;
          return GestureDetector(
            onTap: () => setState(() => _period = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: active ? _gold : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                p == 'week' ? 'This Week' : 'This Month',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.black54,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  TREND CARD  — custom bar chart, zero extra packages
  // ─────────────────────────────────────────────────────────
  Widget _trendCard(AnalyticsService svc) {
    final days = _period == 'week' ? 7 : 30;
    final data = svc.dailyDataFor(days);
    final maxMs = data.map((d) => d.ms).fold(0, (a, b) => a > b ? a : b);
    final todKey = _dayKey(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: max-time label + period count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                maxMs > 0 ? _fmt(maxMs) : '—',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
              Text(
                '${days}d',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── BAR CHART ─────────────────────────────────
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.asMap().entries.map((e) {
                final idx = e.key;
                final d = e.value;
                final frac = maxMs == 0 ? 0.0 : d.ms / maxMs;
                final isToday = _dayKey(d.date) == todKey;

                // Week: show all labels; Month: every 5th + last
                final showLabel =
                    _period == 'week' || idx % 5 == 0 || idx == data.length - 1;
                final lbl = _period == 'week'
                    ? _shortDay(d.date.weekday)
                    : '${d.date.day}';

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                              height: frac == 0
                                  ? 4.0
                                  : (frac * 84).clamp(6.0, 84.0),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? _gold
                                    : _gold.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (showLabel)
                          Text(
                            lbl,
                            style: TextStyle(
                              fontSize: 9,
                              color: isToday ? _gold : Colors.grey[500],
                              fontWeight: isToday
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          )
                        else
                          const SizedBox(height: 11),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),
          Divider(color: Colors.black.withOpacity(0.07), height: 1),
          const SizedBox(height: 12),

          // ── SUMMARY ROW ───────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _trendStat('Total', _fmt(data.fold(0, (s, d) => s + d.ms))),
              _trendStat(
                'Active days',
                '${data.where((d) => d.ms > 0).length}/$days',
              ),
              _trendStat('Daily avg', () {
                final active = data.where((d) => d.ms > 0).toList();
                if (active.isEmpty) return '—';
                final avg = active.fold(0, (s, d) => s + d.ms) ~/ active.length;
                return _fmt(avg);
              }()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trendStat(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: _dark,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  FEATURE BREAKDOWN CARD
  // ─────────────────────────────────────────────────────────
  Widget _featureCard(AnalyticsService svc) {
    final features = svc.sortedFeatures;
    final totalMs = features.fold(0, (s, e) => s + e.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: features.isEmpty
          ? _emptyState(
              Icons.bar_chart_outlined,
              'No feature data yet.\nStart using the app!',
            )
          : Column(
              children: features.asMap().entries.map((e) {
                final rank = e.key;
                final name = e.value.key;
                final ms = e.value.value;
                final color = _barColors[rank.clamp(0, _barColors.length - 1)];
                final frac = _pct(ms, totalMs);
                final isTop = rank == 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Colour dot
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Name + optional TOP badge
                                Row(
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _dark,
                                      ),
                                    ),
                                    if (isTop) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _gold.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          'TOP',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: _gold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                // Duration + percentage
                                Row(
                                  children: [
                                    Text(
                                      _fmt(ms),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _dark,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${(frac * 100).round()}%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: Stack(
                          children: [
                            Container(height: 7, color: Colors.grey[300]),
                            FractionallySizedBox(
                              widthFactor: frac,
                              child: Container(height: 7, color: color),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ACTIVITY HEATMAP  — 4 weeks × 7 days
  // ─────────────────────────────────────────────────────────
  Widget _heatmapCard(AnalyticsService svc) {
    final data = svc.dailyDataFor(28);
    final maxMs = data.map((d) => d.ms).fold(0, (a, b) => a > b ? a : b);
    final todKey = _dayKey(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day-of-week headers
          Row(
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .map(
                  (l) => Expanded(
                    child: Center(
                      child: Text(
                        l,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),

          // 4 rows of 7 cells
          ...List.generate(4, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: List.generate(7, (col) {
                  final idx = row * 7 + col;
                  if (idx >= data.length) {
                    return Expanded(child: _heatCell(0, 0, false));
                  }
                  final d = data[idx];
                  return Expanded(
                    child: _heatCell(d.ms, maxMs, _dayKey(d.date) == todKey),
                  );
                }),
              ),
            );
          }),

          const SizedBox(height: 10),

          // Legend
          Row(
            children: [
              Text(
                'Less',
                style: TextStyle(fontSize: 9, color: Colors.grey[400]),
              ),
              const SizedBox(width: 4),
              ...List.generate(
                5,
                (i) => Container(
                  margin: const EdgeInsets.only(right: 3),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.1 + i * 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'More',
                style: TextStyle(fontSize: 9, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatCell(int ms, int maxMs, bool isToday) {
    final frac = maxMs == 0 ? 0.0 : (ms / maxMs).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      height: 26,
      decoration: BoxDecoration(
        color: ms == 0
            ? Colors.grey.withOpacity(0.15)
            : _gold.withOpacity(0.12 + frac * 0.82),
        borderRadius: BorderRadius.circular(5),
        border: isToday ? Border.all(color: _gold, width: 1.5) : null,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  DICTIONARY USAGE CARD
  // ─────────────────────────────────────────────────────────
  Widget _dictionaryCard(AnalyticsService svc) {
    final words = svc.sortedDictWords.take(10).toList();
    if (words.isEmpty) {
      return _emptyState(Icons.book_outlined, 'No dictionary lookups yet');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              const Icon(Icons.book_outlined, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'Top Words Looked Up',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...words.asMap().entries.map((entry) {
            final index = entry.key;
            final word = entry.value.key;
            final count = entry.value.value;
            final color = _barColors[index % _barColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      word,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _dark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              count.toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _dark,
                              ),
                            ),
                            Text(
                              ' lookups',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: count / words.first.value,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  VOICE COMMANDS CARD
  // ─────────────────────────────────────────────────────────
  Widget _voiceCommandsCard(AnalyticsService svc) {
    final commands = svc.sortedVoiceCmds.take(8).toList();
    if (commands.isEmpty) {
      return _emptyState(Icons.mic_outlined, 'No voice commands used yet');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              const Icon(Icons.mic_outlined, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'Voice Command Usage',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: commands.map((entry) {
              final command = entry.key;
              final count = entry.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gold.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      command,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count.toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  FILE OPERATIONS CARD
  // ─────────────────────────────────────────────────────────
  Widget _fileOperationsCard(AnalyticsService svc) {
    final operations = svc.sortedFileOps.take(6).toList();
    if (operations.isEmpty) {
      return _emptyState(Icons.file_present_outlined, 'No file operations yet');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              const Icon(Icons.file_present_outlined, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'File Operations',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...operations.map((entry) {
            final operation = entry.key;
            final count = entry.value;
            final icon = _getOperationIcon(operation);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: _gold, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _formatOperationName(operation),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _dark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _gold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

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
            color: Colors.black.withOpacity(0.05),
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
        color: _gold.withOpacity(0.08),
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
}
