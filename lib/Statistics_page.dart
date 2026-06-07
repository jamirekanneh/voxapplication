import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_service.dart';
import 'language_provider.dart';
import 'services/auth_session.dart';
import 'theme_provider.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  STATISTICS PAGE
//  Loads Firebase developer-centric metrics for the authenticated user natively.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  static const Map<String, (String, String, IconData)> _achievementMeta = {
    'first_launch': ('First Steps', 'Opened Vox', Icons.rocket_launch_rounded),
    'streak_3': ('On Fire', '3-day streak', Icons.local_fire_department_rounded),
    'streak_7': ('Week Warrior', '7-day streak', Icons.emoji_events_rounded),
    'streak_14': ('Unstoppable', '14-day streak', Icons.military_tech_rounded),
    'streak_30': ('Monthly Master', '30-day streak', Icons.workspace_premium_rounded),
    'dictionary_10': ('Word Explorer', '10 dictionary lookups', Icons.menu_book_rounded),
    'dictionary_50': ('Lexicon Pro', '50 dictionary lookups', Icons.auto_stories_rounded),
    'files_5': ('Organizer', '5 file actions', Icons.folder_rounded),
    'voice_10': ('Voice Pilot', '10 voice commands', Icons.mic_rounded),
    'hour_total': ('Deep Focus', '1 hour in app', Icons.hourglass_top_rounded),
    'daily_goal': ('Goal Crusher', 'Daily goal met', Icons.flag_rounded),
    'level_5': ('Rising Star', 'Reached level 5', Icons.star_rounded),
  };

  static const List<(int days, String achievementId, String title)> _streakRewards = [
    (3, 'streak_3', 'On Fire'),
    (7, 'streak_7', 'Week Warrior'),
    (14, 'streak_14', 'Unstoppable'),
    (30, 'streak_30', 'Monthly Master'),
  ];

  static List<Color> _barColors(BuildContext context) => [
    VoxColors.primary(context),
    VoxColors.primary(context).withValues(alpha: 0.8),
    VoxColors.primary(context).withValues(alpha: 0.6),
    VoxColors.primary(context).withValues(alpha: 0.4),
    VoxColors.primary(context).withValues(alpha: 0.2),
  ];

  bool _loading = true;
  bool _syncing = false;
  bool _isAnonymous = true;
  String? _uid;
  Map<String, dynamic>? _firebaseData;

  // â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.startFeatureSession('Statistics');
    AnalyticsService.instance.addListener(_onAnalyticsChanged);
    _load();
  }

  void _onAnalyticsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AnalyticsService.instance.removeListener(_onAnalyticsChanged);
    AnalyticsService.instance.endFeatureSession('Statistics');
    super.dispose();
  }

  Map<String, dynamic> _mergedLocalPayload() {
    final service = AnalyticsService.instance;
    return {
      'totalOpens': service.opens.length,
      'todayTimeMs': service.todayTotalMs,
      'totalTimeMs': service.dailyMs.values.fold(0, (a, b) => a + b),
      'totalVoiceCmds': service.totalVoiceCmds,
      'totalFileOps': service.totalFileOps,
      'featureUsage': service.featureMs,
      'dailyActivity': service.dailyMs,
      'uniqueWords': service.uniqueWordsLookedUp,
      'activeDays': service.dailyMs.length,
      'totalApiErrors': service.apiErrors.values.fold(0, (a, b) => a + b),
      'totalUnmatched': service.unmatchedCommands.values.fold(0, (a, b) => a + b),
      'ttsUsage': service.ttsUsageCount,
      'gamification': service.gamificationPayload(),
      'schemaVersion': 3,
    };
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('userEmail') ?? '';
    final savedUid = await AuthSession.savedUserId();
    final explicitGuest = await AuthSession.isExplicitGuestMode();

    try {
      if (explicitGuest) {
        _isAnonymous = true;
      } else if (user != null && !user.isAnonymous) {
        _isAnonymous = false;
        _uid = user.uid;
      } else if (savedUid != null) {
        _isAnonymous = false;
        _uid = savedUid;
      } else if (savedEmail.isNotEmpty) {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: savedEmail)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          _isAnonymous = false;
          _uid = query.docs.first.id;
        } else {
          _isAnonymous = true;
        }
      } else {
        _isAnonymous = true;
      }

      if (!_isAnonymous && _uid != null) {
        await AnalyticsService.instance.syncToFirebase();
        final cloud = await AnalyticsService.instance.fetchCloudStats();
        if (mounted) {
          setState(() {
            _firebaseData = cloud ?? _mergedLocalPayload();
          });
        }
      } else {
        if (mounted) {
          setState(() => _firebaseData = _mergedLocalPayload());
        }
      }
    } catch (e) {
      debugPrint('Error loading stats profile: $e');
      _isAnonymous = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncData() async {
    setState(() => _syncing = true);
    try {
      await AnalyticsService.instance.syncToFirebase();
      final cloud = await AnalyticsService.instance.fetchCloudStats();
      if (mounted) {
        setState(() => _firebaseData = cloud ?? _mergedLocalPayload());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Progress & stats synced to cloud'),
            backgroundColor: VoxColors.surface(context),
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

  // â”€â”€ Formatting helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  List<Map<String, dynamic>> _generateDeveloperInsights() {
    final service = AnalyticsService.instance;
    final List<Map<String, dynamic>> insights = [];

    // 1. Feature Discovery Insight
    final featureUsage = service.featureMs;
    if (featureUsage.isNotEmpty) {
      final sorted = featureUsage.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final leastUsed = sorted.first;
      if (leastUsed.value < 60000) {
        // Less than 1 minute
        insights.add({
          'icon': Icons.visibility_off_rounded,
          'title': 'Low Discovery: ${leastUsed.key}',
          'desc':
              'This feature has < 1min lifetime usage. Consider improving its UI discoverability or adding an onboarding tooltip.',
          'color': Colors.orangeAccent,
        });
      }
    }

    // 2. Voice UI Health
    final totalCmds = service.totalVoiceCmds;
    final unmatched = service.unmatchedCommands.values.fold(0, (a, b) => a + b);
    if (totalCmds > 0) {
      final failRate = (unmatched / (totalCmds + unmatched)) * 100;
      if (failRate > 20) {
        insights.add({
          'icon': Icons.mic_external_off_rounded,
          'title': 'Voice Intent Gap (${failRate.round()}%)',
          'desc':
              'High unrecognized command rate detected. Recommend expanding NLP dataset or adding custom aliases for common failures.',
          'color': Colors.redAccent,
        });
      }
    }

    // 3. API Reliability
    final apiErrors = service.apiErrors.values.fold(0, (a, b) => a + b);
    if (apiErrors > 0) {
      insights.add({
        'icon': Icons.cloud_off_rounded,
        'title': 'API Instability Detected',
        'desc':
            '$apiErrors total OpenRouter/Firebase failures recorded. Check network timeout settings or implement exponential backoff retry.',
        'color': Colors.redAccent,
      });
    }

    // 4. Conversion Opportunity
    if (_isAnonymous) {
      insights.add({
        'icon': Icons.account_circle_outlined,
        'title': 'Guest Conversion Risk',
        'desc':
            'Active user is in Guest Mode. Local-only data increases churn risk. Recommend non-intrusive Magic Link prompts.',
        'color': VoxColors.primary(context),
      });
    }

    // 5. Performance / Scaling
    final fileOps = service.totalFileOps;
    if (fileOps > 50) {
      insights.add({
        'icon': Icons.storage_rounded,
        'title': 'Storage Scaling Needs',
        'desc':
            'High frequency of file ops ($fileOps). Migration to a local SQLite cache for metadata is recommended for speed.',
        'color': Colors.blueAccent,
      });
    }

    // Fallback if no real data insights
    if (insights.isEmpty) {
      insights.add({
        'icon': Icons.insights_rounded,
        'title': 'Awaiting Data Points',
        'desc':
            'Continue using the app to generate developer-centric performance and engagement insights.',
        'color': Colors.grey,
      });
    }

    return insights;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // rebuild on language switch
    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      body: Column(
        children: [
          _buildHeader(context),
          if (_loading)
            Expanded(
              child: Center(child: CircularProgressIndicator(color: VoxColors.primary(context))),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (_isAnonymous) _buildGuestWarning(),
                    _buildBody(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGuestWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VoxColors.primary(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VoxColors.primary(context).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.privacy_tip_outlined, color: VoxColors.primary(context), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guest Mode: No Cloud Sync',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: VoxColors.onBg(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stats are saved locally only. Create an account to backup your progress to the cloud.',
                  style: TextStyle(
                    fontSize: 11,
                    color: VoxColors.textSecondary(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  HEADER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 20,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: VoxColors.primary(context),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress & Insights',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: VoxColors.onPrimary(context),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Gamification, trends & product analytics',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!_isAnonymous)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.cloud_sync_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.speed_rounded,
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BODY
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBody() {
    final service = AnalyticsService.instance;
    final data = _firebaseData ?? _mergedLocalPayload();

    final totalOpens = data['totalOpens'] as int? ?? 0;
    final totalTimeMs = data['totalTimeMs'] as int? ?? 0;
    final dailyActivity = data['dailyActivity'] is Map
        ? Map<String, dynamic>.from(data['dailyActivity'] as Map)
        : <String, dynamic>{};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGoalAndStreak(service),
          const SizedBox(height: 12),
          _buildStreakRewardsAlert(service),
          const SizedBox(height: 20),
          _buildGamificationHero(service),
          const SizedBox(height: 24),
          _buildWeeklyTrend(dailyActivity, service),
          const SizedBox(height: 24),
          _buildAchievementsGrid(service),
          const SizedBox(height: 32),

          _sectionLabel('Activity Metrics'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.timeline_rounded,
                  label: 'App Launches',
                  value: totalOpens.toString(),
                  sub: 'lifetime total',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.timer_outlined,
                  label: 'Lifetime Session',
                  value: _fmt(totalTimeMs),
                  sub: 'total duration',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.mic_external_on_outlined,
                  label: 'Total Commands',
                  value: '${data['totalVoiceCmds'] ?? 0}',
                  sub: 'voice executions',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.folder_open_rounded,
                  label: 'File Operations',
                  value: '${data['totalFileOps'] ?? 0}',
                  sub: 'reads/deletes/uploads',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.menu_book_outlined,
                  label: 'Unique Words',
                  value: '${data['uniqueWords'] ?? service.uniqueWordsLookedUp}',
                  sub: 'dictionary explored',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _overviewCard(
                  icon: Icons.calendar_month_outlined,
                  label: 'Active Days',
                  value: '${data['activeDays'] ?? service.dailyMs.length}',
                  sub: 'days with usage',
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          _sectionLabel('Feature Time (7-day trend)'),
          const SizedBox(height: 12),
          _featureAdoptionCard(
            data['featureUsage'] as Map<String, dynamic>? ?? {},
          ),

          const SizedBox(height: 32),

          _sectionLabel('Product Intelligence (for developers)'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VoxColors.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VoxColors.border(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ..._generateDeveloperInsights().asMap().entries.map((entry) {
                  final insight = entry.value;
                  final isLast =
                      entry.key == _generateDeveloperInsights().length - 1;
                  return Column(
                    children: [
                      _insightRow(
                        insight['icon'] as IconData,
                        insight['title'] as String,
                        insight['desc'] as String,
                        insight['color'] as Color,
                      ),
                      if (!isLast)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: VoxColors.border(context), height: 1),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildDevNote(),
        ],
      ),
    );
  }

  Widget _buildDevNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, color: Colors.grey, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'These insights are generated by analyzing local and cloud telemetry to guide technical debt reduction and feature roadmapping.',
              style: TextStyle(
                color: VoxColors.textHint(context),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightRow(
    IconData icon,
    String title,
    String description,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: VoxColors.textSecondary(context),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  SECTION LABEL
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _sectionLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: VoxColors.onBg(context),
      letterSpacing: -0.3,
    ),
  );

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  OVERVIEW CARD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _overviewCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VoxColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0A0E1A).withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
              decoration: BoxDecoration(
                color: VoxColors.primary(context).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: VoxColors.primary(context), size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: VoxColors.onBg(context),
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: VoxColors.onBg(context),
            ),
          ),
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  FEATURE ADOPTION CARD (From Firebase Data)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _featureAdoptionCard(Map<String, dynamic> featureUsageMap) {
    if (featureUsageMap.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bar_chart_outlined, size: 38, color: Colors.grey[350]),
              const SizedBox(height: 10),
              Text(
                'No feature usage data in cloud yet',
                style: TextStyle(fontSize: 13, color: Colors.grey[450]),
              ),
            ],
          ),
        ),
      );
    }

    final list = featureUsageMap.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    final features = list.take(5).toList();
    final totalTime = features.fold(
      0.0,
      (running, entry) =>
          running + (entry.value as num).toDouble(),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VoxColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0A0E1A).withValues(alpha: 0.05),
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
              Icon(Icons.cloud_done_outlined, color: VoxColors.primary(context), size: 18),
              SizedBox(width: 8),
              Text(
                'Top Triggers by Time Evaluated',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: VoxColors.onBg(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...features.asMap().entries.map((e) {
            final rank = e.key;
            final name = e.value.key;
            final timeMs = (e.value.value as num).toInt();
            final percentage = totalTime > 0
                ? (timeMs / totalTime * 100).round()
                : 0;

            final color = _barColors(context)[rank.clamp(0, _barColors(context).length - 1)];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${rank + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: color,
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
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: VoxColors.onBg(context),
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

  Widget _buildStreakRewardsAlert(AnalyticsService service) {
    final streak = service.currentStreak;
    final unlocked = service.achievements;

    (int days, String achievementId, String title)? nextReward;
    for (final tier in _streakRewards) {
      if (streak < tier.$1 && (unlocked[tier.$2] ?? 0) == 0) {
        nextReward = tier;
        break;
      }
    }

    final daysToNext = nextReward == null ? 0 : (nextReward.$1 - streak).clamp(1, 99);
    final nextTitle = nextReward?.$3 ?? 'Monthly Master';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.card_giftcard_rounded, color: Colors.amber.shade600, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Streak rewards',
                      style: TextStyle(
                        color: VoxColors.onBg(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextReward == null
                          ? 'You unlocked every streak badge — keep reading for XP!'
                          : 'Hit your daily goal $daysToNext more day${daysToNext == 1 ? '' : 's'} to earn “$nextTitle” (+25 XP).',
                      style: TextStyle(
                        color: VoxColors.textSecondary(context),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _streakRewards.map((tier) {
              final earned = streak >= tier.$1 || (unlocked[tier.$2] ?? 0) > 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: earned
                      ? Colors.amber.withValues(alpha: 0.22)
                      : VoxColors.onBg(context).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: earned
                        ? Colors.amber.withValues(alpha: 0.5)
                        : VoxColors.onBg(context).withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  '${tier.$1}d · ${tier.$3}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: earned
                        ? Colors.amber.shade800
                        : VoxColors.textHint(context),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGamificationHero(AnalyticsService service) {
    final xp = service.totalXp;
    final lvl = service.level;
    final progress = service.levelProgress;
    final xpInLevel = service.xpProgressInLevel;
    final xpNeeded = service.xpNeededForNextLevel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C63FF).withValues(alpha: 0.25),
            VoxColors.primary(context).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: VoxColors.primary(context).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: VoxColors.primary(context).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.military_tech_rounded,
                        color: VoxColors.primary(context), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Level $lvl',
                      style: TextStyle(
                        color: VoxColors.onBg(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!_isAnonymous)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_done_rounded,
                          size: 14, color: Colors.greenAccent.shade400),
                      const SizedBox(width: 4),
                      Text(
                        'Cloud synced',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.greenAccent.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$xp XP total',
            style: TextStyle(
              color: VoxColors.onBg(context),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$xpInLevel / $xpNeeded XP to Level ${lvl + 1}',
            style: TextStyle(
              color: VoxColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: VoxColors.onBg(context).withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(VoxColors.primary(context)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _xpStatChip(
                Icons.emoji_events_outlined,
                '${service.achievements.values.where((v) => v > 0).length}',
                'Badges',
              ),
              const SizedBox(width: 10),
              _xpStatChip(
                Icons.trending_up_rounded,
                '${service.bestStreak}',
                'Best streak',
              ),
              const SizedBox(width: 10),
              _xpStatChip(
                Icons.bolt_rounded,
                '${_weekXpTotal(service)}',
                'XP this week',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _xpStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: VoxColors.onBg(context).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: VoxColors.primary(context)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: VoxColors.onBg(context),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: VoxColors.textHint(context),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  int _weekXpTotal(AnalyticsService service) {
    final now = DateTime.now();
    var total = 0;
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      total += service.weeklyXp[key] ?? 0;
    }
    return total;
  }

  Widget _buildWeeklyTrend(
    Map<String, dynamic> dailyActivity,
    AnalyticsService service,
  ) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final ms = (dailyActivity[key] as num?)?.toInt() ??
          service.dailyMs[key] ??
          0;
      final xp = service.weeklyXp[key] ?? 0;
      return (d, ms, xp);
    });
    final maxMs = days.map((e) => e.$2).fold(0, (a, b) => a > b ? a : b);
    final maxXp = days.map((e) => e.$3).fold(1, (a, b) => a > b ? a : b);

    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('7-Day Trends'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VoxColors.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VoxColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Time in app (minutes)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: VoxColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: days.asMap().entries.map((e) {
                    final ms = e.value.$2;
                    final h = maxMs > 0 ? (ms / maxMs).clamp(0.08, 1.0) : 0.08;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: h,
                                  widthFactor: 0.65,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: VoxColors.primary(context)
                                          .withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              weekdays[e.value.$1.weekday - 1],
                              style: TextStyle(
                                fontSize: 10,
                                color: VoxColors.textHint(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'XP earned',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: VoxColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: days.asMap().entries.map((e) {
                    final xp = e.value.$3;
                    final h = maxXp > 0 ? (xp / maxXp).clamp(0.08, 1.0) : 0.08;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: h,
                                  widthFactor: 0.65,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFB74D)
                                          .withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (xp > 0)
                              Text(
                                '$xp',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: VoxColors.textHint(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementsGrid(AnalyticsService service) {
    final unlocked = service.achievements;
    final unlockedCount =
        _achievementMeta.keys.where((k) => (unlocked[k] ?? 0) > 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('Achievements')),
            Text(
              '$unlockedCount / ${_achievementMeta.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: VoxColors.primary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: _achievementMeta.length,
          itemBuilder: (context, index) {
            final id = _achievementMeta.keys.elementAt(index);
            final meta = _achievementMeta[id]!;
            final isUnlocked = (unlocked[id] ?? 0) > 0;
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? VoxColors.primary(context).withValues(alpha: 0.12)
                    : VoxColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isUnlocked
                      ? VoxColors.primary(context).withValues(alpha: 0.35)
                      : VoxColors.border(context),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    meta.$3,
                    size: 26,
                    color: isUnlocked
                        ? VoxColors.primary(context)
                        : VoxColors.textHint(context).withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meta.$1,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isUnlocked
                          ? VoxColors.onBg(context)
                          : VoxColors.textHint(context),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGoalAndStreak(AnalyticsService service) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            VoxColors.primary(context).withValues(alpha: 0.15),
            VoxColors.primary(context).withValues(alpha: 0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: VoxColors.primary(context).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Goal Progress Circle
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: service.todayGoalProgress,
                  strokeWidth: 8,
                  backgroundColor: VoxColors.onBg(context).withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(VoxColors.primary(context)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(service.todayGoalProgress * 100).toInt()}%',
                    style: TextStyle(
                      color: VoxColors.onBg(context),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'GOAL',
                    style: TextStyle(
                      color: VoxColors.textHint(context),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Streak and Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.orangeAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${service.currentStreak} Day Streak',
                      style: TextStyle(
                        color: VoxColors.onBg(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Goal: ${service.dailyGoalMinutes} mins / day',
                  style: TextStyle(color: VoxColors.textSecondary(context), fontSize: 13),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showGoalEditDialog(service),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: VoxColors.onBg(context).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Edit Daily Goal',
                      style: TextStyle(
                        color: VoxColors.primary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalEditDialog(AnalyticsService service) {
    int newGoal = service.dailyGoalMinutes;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VoxColors.surface(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Daily Reading Goal',
          style: TextStyle(color: VoxColors.onBg(ctx), fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set your daily target in minutes to stay consistent.',
              style: TextStyle(color: VoxColors.textSecondary(ctx), fontSize: 13),
            ),
            const SizedBox(height: 20),
            StatefulBuilder(
              builder: (ctx, setState) => Column(
                children: [
                  Text(
                    '$newGoal Minutes',
                    style: TextStyle(
                      color: VoxColors.primary(ctx),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Slider(
                    value: newGoal.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    activeColor: VoxColors.primary(ctx),
                    onChanged: (v) => setState(() => newGoal = v.toInt()),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: VoxColors.textHint(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              service.setDailyGoal(newGoal);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VoxColors.primary(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Save Goal',
              style: TextStyle(color: VoxColors.onPrimary(ctx), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

