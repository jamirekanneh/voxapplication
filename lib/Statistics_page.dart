import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_service.dart';
import 'language_provider.dart';
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
    _load();
  }

  @override
  void dispose() {
    AnalyticsService.instance.endFeatureSession('Statistics');
    super.dispose();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('userEmail') ?? '';

    try {
      if (user != null && !user.isAnonymous) {
        _isAnonymous = false;
        _uid = user.uid;
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
        await _fetchFirebaseData();
      }
    } catch (e) {
      debugPrint('Error loading stats profile: $e');
      _isAnonymous = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchFirebaseData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('analytics')
          .doc('daily_stats')
          .get();

      if (doc.exists) {
        setState(() {
          _firebaseData = doc.data();
        });
      } else {
        // Fallback to local service data if cloud doc is empty
        _loadLocalData();
      }
    } catch (e) {
      debugPrint('Error fetching firebase analytics: $e');
      _loadLocalData();
    }
  }

  void _loadLocalData() {
    final service = AnalyticsService.instance;
    setState(() {
      _firebaseData = {
        'totalOpens': service.opens.length,
        'todayTimeMs': service.todayTotalMs,
        'totalTimeMs': service.dailyMs.values.fold(0, (a, b) => a + (b)),
        'totalVoiceCmds': service.totalVoiceCmds,
        'totalFileOps': service.totalFileOps,
        'featureUsage': service.featureMs,
        'uniqueWords': service.uniqueWordsLookedUp,
        'activeDays': service.dailyMs.length,
        'schemaVersion': 1,
      };
    });
  }

  Future<void> _syncData() async {
    setState(() => _syncing = true);
    try {
      await AnalyticsService.instance.syncToFirebase();
      await _fetchFirebaseData();
        if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Developer analytics synced from cloud'),
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
            '$apiErrors total Groq/Firebase failures recorded. Check network timeout settings or implement exponential backoff retry.',
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
                  'App Statistics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: VoxColors.onPrimary(context),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Developer analytics & metrics',
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
    // If no data, use local data as default
    final data =
        _firebaseData ??
        {
          'totalOpens': service.opens.length,
          'todayTimeMs': service.todayTotalMs,
          'totalTimeMs': service.dailyMs.values.fold(0, (a, b) => a + (b)),
          'totalVoiceCmds': service.totalVoiceCmds,
          'totalFileOps': service.totalFileOps,
          'featureUsage': service.featureMs,
          'schemaVersion': 1,
          'uniqueWords': service.uniqueWordsLookedUp,
          'activeDays': service.dailyMs.length,
        };

    final totalOpens = data['totalOpens'] as int? ?? 0;
    final totalTimeMs = data['totalTimeMs'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€â”€ 0. GOALS & STREAKS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _buildGoalAndStreak(service),
          const SizedBox(height: 32),

          // â”€â”€â”€ 1. FIREBASE ACTIVITY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _sectionLabel('User Activity Metrics'),
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

          const SizedBox(height: 32),

          // â”€â”€â”€ 2. DEV ENGAGEMENT BREAKDOWN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _sectionLabel('Cloud Activity Triggers'),
          const SizedBox(height: 12),
          _featureAdoptionCard(
            data['featureUsage'] as Map<String, dynamic>? ?? {},
          ),

          const SizedBox(height: 32),

          // â”€â”€â”€ 3. DEVELOPER UPGRADE INSIGHTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _sectionLabel('Developer Intelligence Dashboard'),
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

