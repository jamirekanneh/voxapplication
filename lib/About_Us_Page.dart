import 'package:flutter/material.dart';

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage>
    with SingleTickerProviderStateMixin {
  // ── VOX Color Palette (matches menu + contact pages) ──────────────
  static const Color primaryGold = Color(0xFFD4B96A); // header gold
  static const Color darkGold = Color(0xFFB89A45);
  static const Color creamBg = Color(0xFFF3E5AB); // menu bg
  static const Color sectionBg1 = Color(0xFFF2EDE0); // light warm cream
  static const Color sectionBg2 = Color(0xFFF7F3EA); // slightly lighter
  static const Color darkText = Color(0xFF1A1A1A);
  static const Color bodyText = Color(0xFF444433);
  static const Color mutedText = Color(0xFF888877);

  // Board of Directors
  final List<Map<String, String>> _directors = [
    {
      'name': 'Abdurrahman Masduki',
      'id': '20212609',
      'title': 'Team Leader',
      'role':
          'Overall coordination\nBackend command-execution logic and flow of the system.',
      'initials': 'AM',
    },
    {
      'name': 'Shaheer Ahmed Farooqi',
      'id': '20224848',
      'title': '',
      'role':
          'Dashboard development\nViewer of system logs and real-time feedback interface.',
      'initials': 'SA',
    },
    {
      'name': 'Jamire M. Kanneh',
      'id': '20213799',
      'title': '',
      'role':
          'Development of voice interface UI.\nLanguages: Dart, JavaScript, and others.',
      'initials': 'JK',
    },
    {
      'name': 'Abdubakr Idris',
      'id': '20223372',
      'title': '',
      'role':
          'Command recognition model tuning.\nVoice recognition and device operation.',
      'initials': 'AI',
    },
  ];

  // Testimonials
  final List<Map<String, String>> _testimonials = [
    {
      'quote':
          '"VOX is a platform that listens and invests in its users. They know that our success is their success."',
      'name': 'FRANK LOUGHAN',
      'role': 'VP Revenue Operations',
      'company': 'ARC Document Solutions',
      'initials': 'FL',
    },
    {
      'quote':
          '"Since using VOX, our team productivity has grown by over 40%. The interface is intuitive and powerful."',
      'name': 'SARAH MITCHELL',
      'role': 'Head of Marketing',
      'company': 'Brightwave Inc.',
      'initials': 'SM',
    },
    {
      'quote':
          '"VOX transformed how we manage customer relationships. We would not go back to any other tool."',
      'name': 'JAMES OKORO',
      'role': 'CEO',
      'company': 'Nexus Retail Group',
      'initials': 'JO',
    },
    {
      'quote':
          '"The onboarding was seamless and the support team is world-class. Highly recommend VOX to every business."',
      'name': 'LINDA VOSS',
      'role': 'Operations Director',
      'company': 'Summit Logistics',
      'initials': 'LV',
    },
  ];

  int _currentTestimonial = 0;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _changeTestimonial(int index) {
    _fadeCtrl.reset();
    setState(() => _currentTestimonial = index);
    _fadeCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sectionBg1,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeroSection(),
                  _buildBoardSection(),
                  _buildMissionSection(),
                  _buildStorySection(),
                  _buildTestimonialsSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
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
                const Text(
                  'About Us',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'We\'d love to share our story',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 38, height: 38), // spacer to balance header
        ],
      ),
    );
  }

  // ── Hero ───────────────────────────────────────────────────────────
  Widget _buildHeroSection() {
    return Container(
      color: sectionBg1,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About Us',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: darkText,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "We are Group 1, presenting our project and providing an overview of our team, our objectives, and the purpose behind our application.",
            style: TextStyle(fontSize: 12.5, color: bodyText, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── Board of Directors ─────────────────────────────────────────────
  Widget _buildBoardSection() {
    return Container(
      color: sectionBg2,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
      child: Column(
        children: [
          const Text(
            'Group Members',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: darkText,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 24),

          // Stacked column of 4 wide horizontal cards
          Column(
            children: _directors.asMap().entries.map((entry) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key < _directors.length - 1 ? 10 : 0,
                ),
                child: _directorCard(entry.value, entry.key + 1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _directorCard(Map<String, String> director, int index) {
    final name = director['name']!;
    final id = director['id']!;
    final title = director['title']!;
    final role = director['role']!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFD4B96A), Color(0xFF9A7A2E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB89A45).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ── Top-right corner accent ──────────────────────────
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 24,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),

          // ── Number badge on left ─────────────────────────────
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 42,
              color: Colors.black.withOpacity(0.18),
              child: Center(
                child: Text(
                  '0$index',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),

          // ── Text content ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(54, 10, 36, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name + title badge on same row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                // ID
                Text(
                  id,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withOpacity(0.82),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                // Role — full multi-line
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Mission ────────────────────────────────────────────────────────
  Widget _buildMissionSection() {
    return Container(
      color: sectionBg1,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Our Mission: Improve Education, blind or visually impaired people, and Productivity',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: darkText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'We were working on voice command application, which is an intelligent application that enables the user to control what is read aloud, perform certain functions, and access different forms of knowledge by merely giving commands by the mouth. The solution is innovative, as it eliminates the necessity of a manual interaction with the user as it provides a hands-free and efficient experience with digital content.',
            style: TextStyle(fontSize: 12, color: bodyText, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── Story ──────────────────────────────────────────────────────────
  Widget _buildStorySection() {
    return Container(
      color: sectionBg2,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About the App',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            'This project focuses on the design and development of a Voice Command Mobile Application that allows users to control application features, access documents, and receive audio-based information using natural voice commands. The importance of this project comes from addressing common limitations in many existing applications, such as poor design, heavy dependence on internet connectivity, and lack of proper documentation. In addition, most current voice-enabled applications are general-purpose and do not specifically support students or users who need academic assistance.',
            style: TextStyle(fontSize: 12, color: bodyText, height: 1.65),
          ),
          const SizedBox(height: 11),
          Text(
            'The main objective of the application is to provide a user-friendly and customizable learning tool. It enables users to upload documents, listen to content through text-to-speech, generate study summaries, create flashcards, and use personalized voice commands. A key feature of the system is the ability to work offline for certain functions, which improves accessibility and usability for students.',
            style: TextStyle(fontSize: 12, color: bodyText, height: 1.65),
          ),
          const SizedBox(height: 11),
          Text(
            'The system is developed following the Software Development Life Cycle (SDLC) using the Agile methodology, allowing iterative development, continuous testing, and user feedback. The application uses Flutter (Dart) for cross-platform mobile development and JavaScript for backend logic. Python-based Natural Language Processing (NLP) is used for speech-to-text and summarization, while Firebase Firestore stores user data, documents, and learning materials securely. Overall, the application aims to improve learning efficiency and accessibility, especially for users with visual or physical impairments.',
            style: TextStyle(fontSize: 12, color: bodyText, height: 1.65),
          ),
        ],
      ),
    );
  }

  // ── Testimonials ───────────────────────────────────────────────────
  Widget _buildTestimonialsSection() {
    final t = _testimonials[0]; // show only the first testimonial

    return Container(
      color: sectionBg1,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          const Text(
            'Our Sincere',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: darkText,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 24),

          // Single card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.black.withOpacity(0.07),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'This project represents not only our effort but also the shared dedication and inspiration provided and gratitude by Prof. Dr. Nadire Çavuş for her continuous support, guidance and encouragement throughout this project. Her valuable insights and advice have played a major role in helping us complete this work. Our Assist. Dr. Oke Oluwafemi for giving us some tips for this project and Assist. Prof. Nasim Ahmedzadeh, also our Course Advisor Assoc. Dr. Sahar Ebadinezhad for helping us revising the diagrams by her guidance we leant how to draw the diagrams and make them more meaningful and clearer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: bodyText,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 18),
                Divider(color: Colors.black.withOpacity(0.07)),
                const SizedBox(height: 12),
                const Text(
                  'VOX',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: darkText,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
