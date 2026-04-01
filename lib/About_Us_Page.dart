import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  static const Color primaryGold = Color(0xFFD4B96A);
  static const Color creamBg = Color(0xFFF3E5AB);
  static const Color cardGrey = Color(0xFFE8E8E8);
  static const Color darkText = Color(0xFF1A1A1A);

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
                  // ── Developers Section ──────────────────
                  _sectionLabel('Developers'),
                  const SizedBox(height: 12),

                  // ── تم التعديل هنا لعرض البطاقات عموديًا واحد تلو الآخر ──
                  Column(
                    children: [
                      _memberCard(
                        'assets/images/Abdurahman.jpeg',
                        'Abdurrahman Masduki',
                        '20212609',
                        'masdukisaleh12@gmail.com',
                        'Technical Lead / Group Leader',
                        'Flutter Project Lead & Final Decision Maker',
                        isLeader: true,
                      ),
                      const SizedBox(height: 14), // مسافة بين البطاقات
                      _memberCard(
                        'assets/images/shaheer.jpeg',
                        'Shaheer Ahmed Farooqi',
                        '20224848',
                        'Shaheerahmed748@gmail.com',
                        'Voice & NLP Specialist',
                        'AI Integration & Speech Logic',
                      ),
                      const SizedBox(height: 14),
                      _memberCard(
                        'assets/images/Jamire.jpeg',
                        'Jamire M. Kanneh',
                        '20213799',
                        'jamiremkanneh@gmail.com',
                        'Backend Infrastructure Lead',
                        'Firebase Cloud Specialist',
                      ),
                      const SizedBox(height: 14),
                      _memberCard(
                        'assets/images/Abubakir.jpeg',
                        'Abdubakr Idris',
                        '20223372',
                        'abubakarelshafie@gmail.com',
                        'UX/UI Interaction Designer',
                        'Visual Feedback & Animations',
                      ),
                    ],
                  ),

                  // ────────────────────────────────────────────────────────
                  const SizedBox(height: 28),

                  // ── Supervisor Section ──────────────────
                  _sectionLabel('Supervisor'),
                  const SizedBox(height: 12),
                  _supervisorCard(),

                  const SizedBox(height: 28),

                  // ── About App Section ───────────────────
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

  // ── Header Widget ──────────────────────────────────────
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
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  t('about_subtitle'),
                  style: const TextStyle(
                    fontSize: 13,
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

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: darkText,
      ),
    );
  }

  // ── Member Card Widget ──────────────────────────────────
  Widget _memberCard(
    String imagePath,
    String name,
    String id,
    String email,
    String role,
    String resp, {
    bool isLeader = false,
  }) {
    return Container(
      // تم تغيير العرض ليأخذ المساحة المتاحة بالكامل مع مراعاة الحواف
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardGrey,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 80,
            constraints: const BoxConstraints(minHeight: 165),
            decoration: const BoxDecoration(
              color: primaryGold,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  image: DecorationImage(
                    image: AssetImage(imagePath),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: darkText,
                          ),
                        ),
                      ),
                      if (isLeader)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'Leader',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: $id',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1A4675),
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: darkText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    resp,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
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

  // ── Supervisor Card Widget ──────────────────────────────
  Widget _supervisorCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryGold.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
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
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryGold, width: 2.5),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/IMG_3331.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Prof. Dr. Nadire Çavuş',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This project, prepared by Group 1 from the CIS Department at Near East University in 2026, reflects our collective knowledge and commitment. We extend our sincere gratitude for her continuous support, guidance, and encouragement throughout this project. Her valuable insights played a significant role in the successful completion of this work.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── About App Widget (Merged with Main Features) ────────
  Widget _aboutCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardGrey,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice Command Document Reader',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'This application is designed to assist users, especially visually impaired individuals, by allowing them to upload documents and have them read aloud using text-to-speech technology. The app also supports voice commands for a hands-free experience.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Text(
            'Main Features',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: darkText,
            ),
          ),
        ),

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
