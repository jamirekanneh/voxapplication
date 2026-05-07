import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';
import 'theme_provider.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LanguageProvider>().t;
    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      body: Column(
        children: [
          _buildHeader(context, t),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(context, 'Developers'),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      _memberCard(
                        context,
                        'assets/images/Abdurahman.jpeg',
                        'Abdurrahman Masduki',
                        '20212609',
                        'masdukisaleh12@gmail.com',
                        'Technical Lead / Group Leader',
                        'Flutter Project Lead & Final Decision Maker',
                        isLeader: true,
                      ),
                      const SizedBox(height: 14),
                      _memberCard(
                        context,
                        'assets/images/shaheer.jpeg',
                        'Shaheer Ahmed Farooqi',
                        '20224848',
                        'Shaheerahmed748@gmail.com',
                        'Voice & NLP Specialist',
                        'AI Integration & Speech Logic',
                      ),
                      const SizedBox(height: 14),
                      _memberCard(
                        context,
                        'assets/images/Jamire.jpeg',
                        'Jamire M. Kanneh',
                        '20213799',
                        'jamiremkanneh@gmail.com',
                        'Backend Infrastructure Lead',
                        'Firebase Cloud Specialist',
                      ),
                      const SizedBox(height: 14),
                      _memberCard(
                        context,
                        'assets/images/Abubakir.jpeg',
                        'Abdubakr Idris',
                        '20223372',
                        'abubakarelshafie@gmail.com',
                        'UX/UI Interaction Designer',
                        'Visual Feedback & Animations',
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _sectionLabel(context, 'Supervisor'),
                  const SizedBox(height: 12),
                  _supervisorCard(context),
                  const SizedBox(height: 28),
                  _sectionLabel(context, 'About the App'),
                  const SizedBox(height: 12),
                  _aboutCard(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String Function(String) t) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 18,
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

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: VoxColors.onBg(context),
      ),
    );
  }

  Widget _memberCard(
    BuildContext context,
    String imagePath,
    String name,
    String id,
    String email,
    String role,
    String resp, {
    bool isLeader = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: VoxColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoxColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 80,
            constraints: const BoxConstraints(minHeight: 165),
            decoration: BoxDecoration(
              color: VoxColors.primary(context),
              borderRadius: const BorderRadius.only(
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
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: VoxColors.onSurface(context),
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
                            color: VoxColors.primary(context).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'Leader',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: VoxColors.primary(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: $id',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: VoxColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 13,
                      color: VoxColors.primary(context),
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    role,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: VoxColors.onSurface(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    resp,
                    style: TextStyle(
                      fontSize: 11,
                      color: VoxColors.textSecondary(context),
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

  Widget _supervisorCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: VoxColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: VoxColors.primary(context).withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: VoxColors.primary(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
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
                    border: Border.all(color: VoxColors.primary(context), width: 2.5),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/IMG_3331.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Prof. Dr. Nadire Çavuş',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: VoxColors.onSurface(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This project, prepared by Group 1 Graduation Project CIS400, Class of 2025/2026, CIS Department at Near East University, reflects our collective knowledge and commitment. We extend our sincere gratitude for her continuous support, guidance, and encouragement throughout this project. Her valuable insights played a significant role in the successful completion of this work.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: VoxColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: VoxColors.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: VoxColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vox (Voice Command App.)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: VoxColors.onSurface(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This application is designed to assist users, especially students and individuals with limited abilities. The Vox app allows users upload or scan documents and have them read aloud using text-to-speech technology. The app also supports voice commands for a hands-free experience. Users can also record notes using the app and transcribe recordings to text using speech-to-text features. The Vox app is also equipped with a large dictionary that supports various fields like medical, legal, general and technical searches. This app also suports six main languages: English, Spanish, French, Arabic, Turkish and Chinese.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: VoxColors.textSecondary(context),
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
              color: VoxColors.onBg(context),
            ),
          ),
        ),
        _featureRow(context, 'Upload/Scan documents'),
        const SizedBox(height: 8),
        _featureRow(context, 'Text-to-speech reading'),
        const SizedBox(height: 8),
        _featureRow(context, 'Speech to text Notes'),
        _featureRow(context, 'Dictionary'),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _featureRow(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: VoxColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VoxColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: VoxColors.primary(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: VoxColors.onSurface(context),
            ),
          ),
        ],
      ),
    );
  }
}
