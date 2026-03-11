import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  static const Color primaryGold = Color(0xFFD4B96A);
  static const Color creamBg = Color(0xFFF3E5AB);
  static const Color cardGrey = Color(0xFFE8E8E8);
  static const Color darkText = Color(0xFF1A1A1A);
  static const Color bodyText = Color(0xFF444433);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LanguageProvider>().t;
    return Scaffold(
      backgroundColor: creamBg,
      body: Column(
        children: [
          _buildHeader(context, t),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Developers ──────────────────────────
                  _sectionLabel('Developers'),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        _memberCard(
                          1,
                          'Abdurrahman Masduki',
                          '20212609',
                          'Technical Lead / Group Leader',
                          'Flutter Project Lead & Final Decision Maker',
                          isLeader: true,
                        ),
                        const SizedBox(width: 14),
                        _memberCard(
                          2,
                          'Shaheer Ahmed Farooqi',
                          '20224848',
                          'Voice & NLP Specialist',
                          'AI Integration & Speech Logic',
                        ),
                        const SizedBox(width: 14),
                        _memberCard(
                          3,
                          'Jamire M. Kanneh',
                          '20213799',
                          'Backend Infrastructure Lead',
                          'Firebase Cloud Specialist',
                        ),
                        const SizedBox(width: 14),
                        _memberCard(
                          4,
                          'Abdubakr Idris',
                          '20223372',
                          'UX/UI Interaction Designer',
                          'Visual Feedback & Animations',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Supervisor ──────────────────────────
                  _sectionLabel('Supervisor'),
                  const SizedBox(height: 12),
                  _supervisorCard(),

                  const SizedBox(height: 28),

                  // ── About the App ───────────────────────
                  _sectionLabel('About the App'),
                  const SizedBox(height: 12),
                  _aboutCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, String Function(String) t) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 18,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: primaryGold,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('about_title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  t('about_subtitle'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ───────────────────────────────────────
  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: darkText,
        letterSpacing: -0.3,
      ),
    );
  }

  // ── Member card ─────────────────────────────────────────
  Widget _memberCard(
    int index,
    String name,
    String id,
    String role,
    String resp, {
    bool isLeader = false,
  }) {
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: cardGrey,
        borderRadius: BorderRadius.circular(14),
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
          // Number strip
          Container(
            width: 44,
            height: 88,
            decoration: BoxDecoration(
              color: primaryGold,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
            ),
            child: Center(
              child: Text(
                '0$index',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: darkText,
                          ),
                        ),
                      ),
                      if (isLeader)
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryGold,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'Leader',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    id,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resp,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Supervisor card ─────────────────────────────────────
  // Deliberately different: centred layout, gold top banner,
  // circular avatar, no number strip.
  Widget _supervisorCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryGold.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gold top banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              color: primaryGold,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Center(
              child: Text(
                'PROJECT SUPERVISOR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                // Circular avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryGold.withOpacity(0.15),
                    border: Border.all(color: primaryGold, width: 2),
                  ),
                  child: const Center(
                    child: Text(
                      'NC',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: primaryGold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                const Text(
                  'Prof. Dr. Nadire Çavuş',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 6),

                // Title pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Project Supervisor',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: primaryGold,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Divider(color: Colors.black.withOpacity(0.08)),
                const SizedBox(height: 12),

                Text(
                  'We extend our sincere gratitude for her continuous support, guidance, and encouragement throughout this project. Her valuable insights played a major role in helping us complete this work.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── About card ──────────────────────────────────────────
  Widget _aboutCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardGrey,
            borderRadius: BorderRadius.circular(14),
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
              const Text(
                'Voice Command Document Reader Application',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This application is designed to assist users, especially visually impaired individuals, by allowing them to upload documents and have them read aloud using text-to-speech technology. The app also supports voice commands such as play, pause, and navigation to make the interaction hands-free. The system is developed using Flutter and Dart, and it integrates modern accessibility features to improve usability.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.65,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Features label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Text(
            'Main Features',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey[700],
            ),
          ),
        ),

        // Feature rows
        _featureRow('Uploading documents'),
        const SizedBox(height: 8),
        _featureRow('Text-to-speech reading'),
        const SizedBox(height: 8),
        _featureRow('Voice commands for controlling playback'),
      ],
    );
  }

  Widget _featureRow(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: cardGrey,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: primaryGold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: darkText,
            ),
          ),
        ],
      ),
    );
  }
}
