import 'package:flutter/material.dart';
import 'contact_us_page.dart';

const _kBgColor = Color(0xFFF3E5AB);
const _kHeaderColor = Color(0xFFD4B96A);
const _kNavy = Color(0xFF1A1A2E);

class AskQuestionsPage extends StatefulWidget {
  const AskQuestionsPage({super.key});

  @override
  State<AskQuestionsPage> createState() => _AskQuestionsPageState();
}

class _AskQuestionsPageState extends State<AskQuestionsPage> {
  final List<Map<String, String>> faqs = [
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

  void _showChatBox(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SupportChatBot(faqs: faqs),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        title: const Text(
          'FAQs',
          style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _kNavy),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kNavy,
        onPressed: () => _showChatBox(context),
        child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: faqs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
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
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        iconColor: _kHeaderColor,
                        collapsedIconColor: _kNavy,
                        title: Text(
                          faqs[index]['q']!,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: _kNavy),
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
            Padding(
              padding: const EdgeInsets.all(24.0),
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
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Still have a question? Contact Us'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Chatbox Widget
class _SupportChatBot extends StatefulWidget {
  final List<Map<String, String>> faqs;
  const _SupportChatBot({required this.faqs});

  @override
  State<_SupportChatBot> createState() => _SupportChatBotState();
}

class _SupportChatBotState extends State<_SupportChatBot> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {'text': 'Hi! I am your App Assistant. How can I help you today?', 'isUser': false},
  ];

  void _handleSend() {
    if (_controller.text.trim().isEmpty) return;

    final userQuery = _controller.text.trim();
    setState(() {
      _messages.add({'text': userQuery, 'isUser': true});
    });
    _controller.clear();

    // Simple Logic: Scan FAQ keys for matches
    String response = "I'm sorry, I don't quite understand that. You can try asking about 'backup', 'deleted files', or 'voice commands'!";
    
    final queryLower = userQuery.toLowerCase();
    for (var faq in widget.faqs) {
      if (queryLower.contains(faq['q']!.toLowerCase().split(' ').last) || 
          faq['q']!.toLowerCase().contains(queryLower)) {
        response = faq['a']!;
        break;
      }
    }

    // Add delay to simulate "thinking"
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _messages.add({'text': response, 'isUser': false});
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            height: 5,
            width: 40,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          const Text('App Assistant', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _kNavy)),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg['isUser'] ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: msg['isUser'] ? _kNavy : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['text'],
                      style: TextStyle(color: msg['isUser'] ? Colors.white : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a question...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: _kNavy,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _handleSend,
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