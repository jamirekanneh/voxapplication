import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_service.dart';
import 'language_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  STATISTICS PAGE
//  Loads Firebase developer-centric metrics for the authenticated user natively.
// ─────────────────────────────────────────────────────────────────────────────

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  // ── Colour constants ─────────────────────────────────────
  static const Color _gold = Color(0xFF4B9EFF);
  static const Color _cream = Color(0xFFF0F4FF);
  static const Color _card = Color(0xFFE8E8E8);
  static const Color _dark = Color(0xFF1A1A1A);

  static const List<Color> _barColors = [
    Color(0xFF4B9EFF),
    Color(0xFF5C8A6E),
    Color(0xFF7A6BAB),
    Color(0xFFB05C5C),
    Color(0xFF4A7FA0),
  ];

  bool _loading = true;
  bool _syncing = false;
  bool _isAnonymous = true;
  String? _uid;
  Map<String, dynamic>? _firebaseData;

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
            .where('email',
                isEqualTo: savedEmail)
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
        _firebaseData = doc.data();
      } else {
        // Force a sync if there's no data
        await AnalyticsService.instance.syncToFirebase();
        final doc2 = await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('analytics')
            .doc('daily_stats')
            .get();
        if (doc2.exists) {
          _firebaseData = doc2.data();
        }
      }
    } catch (e) {
      debugPrint('Error fetching firebase analytics: $e');
    }
  }

  Future<void> _syncData() async {
    setState(() => _syncing = true);
    try {
      await AnalyticsService.instance.syncToFirebase();
      await _fetchFirebaseData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Developer analytics synced from cloud'),
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
          else if (_isAnonymous)
            Expanded(child: _buildGuestState())
          else
            Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildGuestState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.privacy_tip_outlined, color: Colors.grey[400], size: 60),
          const SizedBox(height: 16),
          const Text(
            'Guest Usage',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _dark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Analytics and statistics logging are fully disabled for guest accounts to ensure privacy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _dark,
              foregroundColor: _gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Log In / Sign Up', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  HEADER
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
                  'App Statistics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Developer analytics & metrics',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
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
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
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
                  child: const Icon(
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

  // ─────────────────────────────────────────────────────────
  //  BODY
  // ─────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_firebaseData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.query_stats_rounded, color: Colors.grey[400], size: 60),
            const SizedBox(height: 16),
            Text('No cloud analytics found for this user', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _syncData,
              style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _dark),
              child: const Text('Force Cloud Sync', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    final data = _firebaseData!;
    final totalOpens = data['totalOpens'] as int? ?? 0;
    final todayTimeMs = data['todayTimeMs'] as int? ?? 0;
    final totalTimeMs = data['totalTimeMs'] as int? ?? 0;
    final uniqueCmds = data['uniqueVoiceCmds'] as int? ?? 0;
    final activeDays = data['activeDays'] as int? ?? 0;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 1. FIREBASE ACTIVITY ─────────────────────────────
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

          // ─── 2. DEV ENGAGEMENT BREAKDOWN ─────────────────────────
          _sectionLabel('Cloud Activity Triggers'),
          const SizedBox(height: 12),
          _featureAdoptionCard(data['featureUsage'] as Map<String, dynamic>? ?? {}),

          const SizedBox(height: 32),

          // ─── 3. FIRESTORE DATABASE METRICS ─────────────────────
          _sectionLabel('Firestore Event Logging'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0x1F0A0E1A)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Schema Version', style: TextStyle(color: _dark, fontWeight: FontWeight.w700)),
                    Text('v${data['schemaVersion'] ?? 1}', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Today\'s Exec Time', style: TextStyle(color: _dark, fontWeight: FontWeight.w700)),
                    Text(_fmt(todayTimeMs), style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dictionary Entries', style: TextStyle(color: _dark, fontWeight: FontWeight.w700)),
                    Text('${data['uniqueWords'] ?? 0}', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('30-Day Retention Check', style: TextStyle(color: _dark, fontWeight: FontWeight.w700)),
                    Text('$activeDays Active Days', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  SECTION LABEL
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
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
              color: _gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _gold, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _dark,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  FEATURE ADOPTION CARD (From Firebase Data)
  // ─────────────────────────────────────────────────────────
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
    final totalTime = features.fold(0.0, (sum, entry) => sum + (entry.value as num).toDouble());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
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
          const Row(
            children: [
              Icon(Icons.cloud_done_outlined, color: _gold, size: 18),
              SizedBox(width: 8),
              Text(
                'Top Triggers by Time Evaluated',
                style: TextStyle(
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
            final timeMs = (e.value.value as num).toInt();
            final percentage = totalTime > 0 ? (timeMs / totalTime * 100).round() : 0;

            final color = _barColors[rank.clamp(0, _barColors.length - 1)];

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
}

