import 'package:flutter/material.dart';
import 'contact_us_page.dart';

const _kBgColor = Color(0xFFF3E5AB);
const _kHeaderColor = Color(0xFFD4B96A);
const _kNavy = Color(0xFF1A1A2E);

class AskQuestionsPage extends StatelessWidget {
  const AskQuestionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = [
      {
        'q': 'How do I recover deleted files?',
        'a':
            'Open the main Menu and navigate to "Recycle Files". From there, you can view your deleted notes and files and safely restore them directly to your library.',
      },
      {
        'q': 'Is my data securely backed up?',
        'a':
            'Yes! If you are logged into an authenticated account, your files and notes are securely backed up to the cloud. If you are using Guest Mode, your data is temporary and only saves locally to your device during the session.',
      },
      {
        'q': 'How can I reach support?',
        'a':
            'You can reach out to our dedicated support team using the "Contact Us" page inside the main menu. We provide support through both WhatsApp and Email!',
      },
      {
        'q': 'Can I use Voice Commands?',
        'a':
            'Absolutely! Visit the Commands section in the Menu to view our rich library of voice commands. You can also customize them manually to better fit your workflow.',
      },
    ];

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        title: const Text(
          'Ask Questions',
          style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _kNavy),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _kNavy.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                itemCount: faqs.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _kNavy.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        iconColor: _kHeaderColor,
                        collapsedIconColor: _kNavy,
                        title: Text(
                          faqs[index]['q']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _kNavy,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                faqs[index]['a']!,
                                style: TextStyle(
                                  color: Colors.black87.withValues(alpha: 0.8),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactUsPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(double.infinity, 56),
                ),
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text(
                  'Still have a question? Contact Us',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
