import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key});

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  final TextEditingController _controller = TextEditingController();
  int _charCount = 0;
  int _rating = 0;
  bool _isSending = false;
  
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _controller.addListener(() {
      setState(() {
        _charCount = _controller.text.length;
      });
    });
  }

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    final ok = await _speech.initialize();
    if (mounted) setState(() => _speechAvailable = ok);
  }

  Future<void> _toggleVoice() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (r) {
          if (!mounted) return;
          _controller.text = r.recognizedWords;
          _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
          if (r.finalResult && mounted) setState(() => _isListening = false);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenMode: stt.ListenMode.dictation,
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) return;
    
    setState(() {
      _isSending = true;
    });

    try {
      final res = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': const String.fromEnvironment('EMAILJS_SERVICE_ID', defaultValue: 'service_akm5fyg'),
          'template_id': const String.fromEnvironment('EMAILJS_TEMPLATE_ID', defaultValue: 'template_ujtn37d'),
          'user_id': const String.fromEnvironment('EMAILJS_PUBLIC_KEY', defaultValue: '7lv-I2bSLiEeBpoYg'),
          'template_params': {
            'name': 'Vox User',
            'email': 'jamiremkanneh@gmail.com',
            'title': 'New Recommendation for VOX App',
            'message_phone': '-',
            'subject': 'App Recommendation (Rating: $_rating Stars)',
            'message': _controller.text.trim(),
            'reply_preference': 'Sent from Recommendations Page',
          },
        }),
      );

      if (!mounted) return;
      setState(() {
        _isSending = false;
      });

      if (res.statusCode == 200) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0A0E1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: const Text('Thank You!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            content: Text('Your recommendation and $_rating-star rating have been submitted successfully.', style: TextStyle(color: Colors.white.withOpacity(0.8))),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4B9EFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send. Please try again. (${res.statusCode})'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Check your connection.'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Recommendations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Help Us Make\nIt Better!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback helps us improve\nand build features you\'ll love.',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5), height: 1.5),
            ),
            const SizedBox(height: 32),

            // Rating Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rate Vox Features', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('How would you rate your experience so far?', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (index) {
                      return GestureDetector(
                        onTap: () => setState(() => _rating = index + 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _rating > index ? const Color(0xFF4B9EFF).withOpacity(0.15) : Colors.transparent,
                          ),
                          child: Icon(
                            _rating > index ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: _rating > index ? const Color(0xFF4B9EFF) : Colors.white.withOpacity(0.3),
                            size: 32,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Text Input Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: Color(0xFF4B9EFF), size: 24),
                      SizedBox(width: 8),
                      Text('Share Your Suggestions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('What can we improve or add next?', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLength: 1000,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Write your recommendation here...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                        counterText: '',
                        suffixIcon: _speechAvailable ? Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 8),
                              child: GestureDetector(
                                onTap: _toggleVoice,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _isListening ? Colors.red.withOpacity(0.9) : Colors.white.withOpacity(0.05),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _isListening ? Colors.red : Colors.white.withOpacity(0.15),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                                    size: 18,
                                    color: _isListening ? Colors.white : Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ) : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('$_charCount/1000', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // Ideas Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF4B9EFF).withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4B9EFF).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF4B9EFF), size: 22),
                      SizedBox(width: 8),
                      Text('Example Suggestions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildBullet('Add offline dictionary lookups'),
                  _buildBullet('Include voice note language translation'),
                  _buildBullet('Allow importing custom flashcard decks'),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            Center(
              child: Text(
                'This is optional. You can skip and do it later.',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
              ),
            ),
            
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: ((_charCount > 0 || _rating > 0) && !_isSending) ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4B9EFF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF4B9EFF).withOpacity(0.3),
                  disabledForegroundColor: Colors.white.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSending 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Recommendation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            
            const SizedBox(height: 12),
            
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white.withOpacity(0.8),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF4B9EFF)),
          ),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8), height: 1.4)),
          ),
        ],
      ),
    );
  }
}
