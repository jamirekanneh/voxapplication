import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _kDevWhatsApp = '905488265289';

// ─────────────────────────────────────────────────────────────────────────────
// API keys loaded from --dart-define at build time so they never appear
// in plain text in your source code or git history.
//
// Run with:
//   flutter run \
//     --dart-define=EMAILJS_SERVICE_ID=service_sj1zwun \
//     --dart-define=EMAILJS_TEMPLATE_ID=template_kg6ezs8 \
//     --dart-define=EMAILJS_PUBLIC_KEY=8tlgc7LHJtmuCRZmj
//
// Or add these lines to a .env.dart file (gitignored) and import it.
// ─────────────────────────────────────────────────────────────────────────────
const _kEmailJSServiceId = String.fromEnvironment(
  'EMAILJS_SERVICE_ID',
  defaultValue: 'service_akm5fyg',
);
const _kEmailJSTemplateId = String.fromEnvironment(
  'EMAILJS_TEMPLATE_ID',
  defaultValue: 'template_ujtn37d',
);
const _kEmailJSPublicKey = String.fromEnvironment(
  'EMAILJS_PUBLIC_KEY',
  defaultValue: '7lv-I2bSLiEeBpoYg',
);
const _kBgColor = Color(0xFFF3E5AB);
const _kHeaderColor = Color(0xFFD4B96A);
const _kTextLight = Color(0xFFF3E5AB);
const _kWaGreen = Color(0xFF25D366);
const _kDarkBtn = Color(0xFF3A3A3A);

enum ContactPreference { email, whatsapp }

const List<Map<String, String>> _kCountries = [
  {'name': 'Afghanistan', 'dial': '+93', 'flag': '🇦🇫'},
  {'name': 'Albania', 'dial': '+355', 'flag': '🇦🇱'},
  {'name': 'Algeria', 'dial': '+213', 'flag': '🇩🇿'},
  {'name': 'Argentina', 'dial': '+54', 'flag': '🇦🇷'},
  {'name': 'Australia', 'dial': '+61', 'flag': '🇦🇺'},
  {'name': 'Austria', 'dial': '+43', 'flag': '🇦🇹'},
  {'name': 'Bahrain', 'dial': '+973', 'flag': '🇧🇭'},
  {'name': 'Bangladesh', 'dial': '+880', 'flag': '🇧🇩'},
  {'name': 'Belgium', 'dial': '+32', 'flag': '🇧🇪'},
  {'name': 'Brazil', 'dial': '+55', 'flag': '🇧🇷'},
  {'name': 'Canada', 'dial': '+1', 'flag': '🇨🇦'},
  {'name': 'Chile', 'dial': '+56', 'flag': '🇨🇱'},
  {'name': 'China', 'dial': '+86', 'flag': '🇨🇳'},
  {'name': 'Colombia', 'dial': '+57', 'flag': '🇨🇴'},
  {'name': 'Croatia', 'dial': '+385', 'flag': '🇭🇷'},
  {'name': 'Czech Republic', 'dial': '+420', 'flag': '🇨🇿'},
  {'name': 'Denmark', 'dial': '+45', 'flag': '🇩🇰'},
  {'name': 'Egypt', 'dial': '+20', 'flag': '🇪🇬'},
  {'name': 'Ethiopia', 'dial': '+251', 'flag': '🇪🇹'},
  {'name': 'Finland', 'dial': '+358', 'flag': '🇫🇮'},
  {'name': 'France', 'dial': '+33', 'flag': '🇫🇷'},
  {'name': 'Germany', 'dial': '+49', 'flag': '🇩🇪'},
  {'name': 'Ghana', 'dial': '+233', 'flag': '🇬🇭'},
  {'name': 'Greece', 'dial': '+30', 'flag': '🇬🇷'},
  {'name': 'Hungary', 'dial': '+36', 'flag': '🇭🇺'},
  {'name': 'India', 'dial': '+91', 'flag': '🇮🇳'},
  {'name': 'Indonesia', 'dial': '+62', 'flag': '🇮🇩'},
  {'name': 'Iran', 'dial': '+98', 'flag': '🇮🇷'},
  {'name': 'Iraq', 'dial': '+964', 'flag': '🇮🇶'},
  {'name': 'Ireland', 'dial': '+353', 'flag': '🇮🇪'},
  {'name': 'Israel', 'dial': '+972', 'flag': '🇮🇱'},
  {'name': 'Italy', 'dial': '+39', 'flag': '🇮🇹'},
  {'name': 'Japan', 'dial': '+81', 'flag': '🇯🇵'},
  {'name': 'Jordan', 'dial': '+962', 'flag': '🇯🇴'},
  {'name': 'Kenya', 'dial': '+254', 'flag': '🇰🇪'},
  {'name': 'Kuwait', 'dial': '+965', 'flag': '🇰🇼'},
  {'name': 'Lebanon', 'dial': '+961', 'flag': '🇱🇧'},
  {'name': 'Libya', 'dial': '+218', 'flag': '🇱🇾'},
  {'name': 'Malaysia', 'dial': '+60', 'flag': '🇲🇾'},
  {'name': 'Mexico', 'dial': '+52', 'flag': '🇲🇽'},
  {'name': 'Morocco', 'dial': '+212', 'flag': '🇲🇦'},
  {'name': 'Netherlands', 'dial': '+31', 'flag': '🇳🇱'},
  {'name': 'New Zealand', 'dial': '+64', 'flag': '🇳🇿'},
  {'name': 'Nigeria', 'dial': '+234', 'flag': '🇳🇬'},
  {'name': 'Norway', 'dial': '+47', 'flag': '🇳🇴'},
  {'name': 'Oman', 'dial': '+968', 'flag': '🇴🇲'},
  {'name': 'Pakistan', 'dial': '+92', 'flag': '🇵🇰'},
  {'name': 'Palestine', 'dial': '+970', 'flag': '🇵🇸'},
  {'name': 'Peru', 'dial': '+51', 'flag': '🇵🇪'},
  {'name': 'Philippines', 'dial': '+63', 'flag': '🇵🇭'},
  {'name': 'Poland', 'dial': '+48', 'flag': '🇵🇱'},
  {'name': 'Portugal', 'dial': '+351', 'flag': '🇵🇹'},
  {'name': 'Qatar', 'dial': '+974', 'flag': '🇶🇦'},
  {'name': 'Romania', 'dial': '+40', 'flag': '🇷🇴'},
  {'name': 'Russia', 'dial': '+7', 'flag': '🇷🇺'},
  {'name': 'Saudi Arabia', 'dial': '+966', 'flag': '🇸🇦'},
  {'name': 'Senegal', 'dial': '+221', 'flag': '🇸🇳'},
  {'name': 'Serbia', 'dial': '+381', 'flag': '🇷🇸'},
  {'name': 'Singapore', 'dial': '+65', 'flag': '🇸🇬'},
  {'name': 'South Africa', 'dial': '+27', 'flag': '🇿🇦'},
  {'name': 'South Korea', 'dial': '+82', 'flag': '🇰🇷'},
  {'name': 'Spain', 'dial': '+34', 'flag': '🇪🇸'},
  {'name': 'Sudan', 'dial': '+249', 'flag': '🇸🇩'},
  {'name': 'Sweden', 'dial': '+46', 'flag': '🇸🇪'},
  {'name': 'Switzerland', 'dial': '+41', 'flag': '🇨🇭'},
  {'name': 'Syria', 'dial': '+963', 'flag': '🇸🇾'},
  {'name': 'Taiwan', 'dial': '+886', 'flag': '🇹🇼'},
  {'name': 'Tanzania', 'dial': '+255', 'flag': '🇹🇿'},
  {'name': 'Thailand', 'dial': '+66', 'flag': '🇹🇭'},
  {'name': 'Tunisia', 'dial': '+216', 'flag': '🇹🇳'},
  {'name': 'Turkey', 'dial': '+90', 'flag': '🇹🇷'},
  {'name': 'UAE', 'dial': '+971', 'flag': '🇦🇪'},
  {'name': 'Uganda', 'dial': '+256', 'flag': '🇺🇬'},
  {'name': 'Ukraine', 'dial': '+380', 'flag': '🇺🇦'},
  {'name': 'United Kingdom', 'dial': '+44', 'flag': '🇬🇧'},
  {'name': 'United States', 'dial': '+1', 'flag': '🇺🇸'},
  {'name': 'Venezuela', 'dial': '+58', 'flag': '🇻🇪'},
  {'name': 'Vietnam', 'dial': '+84', 'flag': '🇻🇳'},
  {'name': 'Yemen', 'dial': '+967', 'flag': '🇾🇪'},
];

// ── Blinking hint ─────────────────────────────────────────────────────────────
class _BlinkingHint extends StatefulWidget {
  final String text;
  const _BlinkingHint(this.text);
  @override
  State<_BlinkingHint> createState() => _BlinkingHintState();
}

class _BlinkingHintState extends State<_BlinkingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _a = Tween(begin: 1.0, end: 0.15).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: Text(
      widget.text,
      style: const TextStyle(color: Colors.black38, fontSize: 13),
    ),
  );
}

// ── Mic button — dark rounded square, no animation/movement ──────────────────
class _MicButton extends StatelessWidget {
  final bool isListening;
  final VoidCallback onTap;
  const _MicButton({required this.isListening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isListening ? const Color(0xFFE53935) : _kDarkBtn,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isListening ? Icons.stop_rounded : Icons.mic_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ── Main page ─────────────────────────────────────────────────────────────────
class ContactUsPage extends StatefulWidget {
  const ContactUsPage({super.key});
  @override
  State<ContactUsPage> createState() => _ContactUsPageState();
}

class _ContactUsPageState extends State<ContactUsPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  Map<String, String> _selectedCountry = _kCountries.firstWhere(
    (c) => c['name'] == 'Turkey',
    orElse: () => _kCountries.first,
  );

  ContactPreference _contactPref = ContactPreference.email;
  bool _isSending = false;
  bool _sent = false;

  // ── Speech-to-text ────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String? _listeningField;
  bool _voiceBusy = false;

  // ── Text-to-speech via platform channel (no extra package needed) ─────────
  final FlutterTts _flutterTts = FlutterTts();
  bool _bannerSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    // Auto-read the full form guide when the page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _speakGuide();
      });
    });
  }

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    final ok = await _speech.initialize(onError: (e) => debugPrint('STT: $e'));
    if (mounted) setState(() => _speechAvailable = ok);
  }

  // Speak banner text using Android TTS via a simple platform channel.
  // If the channel isn't set up, falls back to showing a SnackBar.
  static const _kGuideText =
      'Welcome to Contact Us. '
      'At the top, choose Email or WhatsApp to receive our reply. '
      'First Name — tap the mic on the right to record. '
      'Last Name — tap the mic on the right to record. '
      'Email Address — tap the mic on the right to record. '
      'Phone Number — tap the flag to pick your country, then tap the mic to record. '
      'Subject — tap the mic on the right to record. '
      'Message — tap the mic in the top right corner of the box to record. '
      'When done, tap the Send button at the bottom.';

  Future<void> _speakGuide() async {
    // If already speaking — stop it
    if (_bannerSpeaking) {
      await _flutterTts.stop();
      if (mounted) setState(() => _bannerSpeaking = false);
      return;
    }
    setState(() => _bannerSpeaking = true);
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.85);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _bannerSpeaking = false);
    });
    _flutterTts.setCancelHandler(() {
      if (mounted) setState(() => _bannerSpeaking = false);
    });
    await _flutterTts.speak(_kGuideText);
  }

  Future<void> _speakBanner() => _speakGuide();

  Future<void> _toggleVoice(String key, TextEditingController ctrl) async {
    if (!_speechAvailable) {
      _showError('Microphone not available.');
      return;
    }
    if (_voiceBusy) return;
    _voiceBusy = true;
    try {
      if (_listeningField == key) {
        await _speech.stop();
        if (mounted) setState(() => _listeningField = null);
        return;
      }
      if (_speech.isListening) {
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (!mounted) return;
      setState(() => _listeningField = key);
      await _speech.listen(
        onResult: (r) {
          if (!mounted) return;
          ctrl.text = r.recognizedWords;
          ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: ctrl.text.length),
          );
          if (r.finalResult && mounted) setState(() => _listeningField = null);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      );
    } finally {
      _voiceBusy = false;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl,
      _lastNameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _titleCtrl,
      _messageCtrl,
    ])
      c.dispose();
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }

  // ── Send ──────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    if (_contactPref == ContactPreference.whatsapp) {
      final name = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';
      final phone =
          '${_selectedCountry['flag']} ${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}';
      final email = _emailCtrl.text.trim();
      final message = _messageCtrl.text.trim();
      final text = Uri.encodeComponent(
        '📩 *New VOX App Message*\n\n'
        '👤 *Name:* $name\n'
        '📧 *Email:* $email\n'
        '📞 *Phone:* $phone\n'
        '📌 *Title:* ${_titleCtrl.text.trim()}\n\n'
        '💬 *Message:*\n$message\n\n'
        '↩️ _Reply to this user via WhatsApp_',
      );
      final waUrl = Uri.parse('https://wa.me/$_kDevWhatsApp?text=$text');
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _sent = true;
        });
      } else {
        if (!mounted) return;
        setState(() => _isSending = false);
        _showError('WhatsApp is not installed on this device.');
      }
    } else {
      try {
        final res = await http.post(
          Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'service_id': _kEmailJSServiceId,
            'template_id': _kEmailJSTemplateId,
            'user_id': _kEmailJSPublicKey,
            'template_params': {
              'name':
                  '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
              'email': _emailCtrl.text.trim(),
              'title': 'New message from VOX App',
              'message_phone':
                  '${_selectedCountry['flag']} ${_selectedCountry['name']} ${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}',
              'subject': _titleCtrl.text.trim(),
              'message': _messageCtrl.text.trim(),
              'reply_preference':
                  '📧 User prefers Email reply\n📬 Reply to: ${_emailCtrl.text.trim()}',
            },
          }),
        );
        if (!mounted) return;
        if (res.statusCode == 200) {
          setState(() {
            _isSending = false;
            _sent = true;
          });
        } else {
          setState(() => _isSending = false);
          _showError('Failed to send (${res.statusCode}). Try again.');
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSending = false);
        _showError('Network error. Check your connection.');
      }
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  // ── Country picker ────────────────────────────────────────────────────────
  void _showCountryPicker() {
    final search = ValueNotifier<String>('');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kBgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search country…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => search.value = v.toLowerCase(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: search,
                builder: (_, query, __) {
                  final filtered = _kCountries
                      .where(
                        (c) =>
                            c['name']!.toLowerCase().contains(query) ||
                            c['dial']!.contains(query),
                      )
                      .toList();
                  return ListView.builder(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final active = c['name'] == _selectedCountry['name'];
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCountry = c);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: active ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                c['flag']!,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c['name']!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: active
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                c['dial']!,
                                style: TextStyle(
                                  color: active
                                      ? Colors.white70
                                      : Colors.black45,
                                  fontSize: 13,
                                ),
                              ),
                              if (active) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  InputDecoration _inputDeco({Widget? prefix, Widget? suffix}) =>
      InputDecoration(
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kHeaderColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400, width: 2),
        ),
      );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Colors.black38,
        letterSpacing: 2,
      ),
    ),
  );

  Widget _mic(String key, TextEditingController ctrl) => _speechAvailable
      ? Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _MicButton(
            isListening: _listeningField == key,
            onTap: () => _toggleVoice(key, ctrl),
          ),
        )
      : const SizedBox.shrink();

  // ── Segmented preference selector ─────────────────────────────────────────
  Widget _buildPreference() {
    final isEmail = _contactPref == ContactPreference.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PREFERRED REPLY METHOD'),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: isEmail
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isEmail ? const Color(0xFF1A1A2E) : _kWaGreen,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (isEmail ? Colors.black : _kWaGreen)
                              .withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _contactPref = ContactPreference.email,
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mail_outline_rounded,
                              size: 16,
                              color: isEmail ? Colors.white : Colors.black45,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Email',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isEmail ? Colors.white : Colors.black54,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _contactPref = ContactPreference.whatsapp,
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_rounded,
                              size: 16,
                              color: !isEmail ? Colors.white : Colors.black45,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'WhatsApp',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: !isEmail ? Colors.white : Colors.black54,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Row(
            key: ValueKey(isEmail),
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isEmail ? const Color(0xFF1A1A2E) : _kWaGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isEmail
                    ? 'We will reply directly to your email'
                    : 'WhatsApp opens — tap Send to deliver your message',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isEmail ? Colors.black54 : _kWaGreen,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Success screen ────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final isEmail = _contactPref == ContactPreference.email;
    final replyVia = isEmail ? 'Email' : 'WhatsApp';
    final replyIcon = isEmail ? Icons.mail_rounded : Icons.chat_rounded;
    final replyColor = isEmail ? const Color(0xFF1A1A2E) : _kWaGreen;
    final contact = isEmail
        ? _emailCtrl.text.trim()
        : '${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}';
    final firstName = _firstNameCtrl.text.trim();

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Top hero banner ─────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 28),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: Column(
              children: [
                // Animated check circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _kHeaderColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kHeaderColor.withOpacity(0.45),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Message Sent!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Thank you, $firstName. We have received your message.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.65),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Reply method chip ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: replyColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: replyColor.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: replyColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(replyIcon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'You will be contacted via $replyVia',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: replyColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              contact,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Submission summary card ───────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Card header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.receipt_long_rounded,
                              color: _kHeaderColor,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'SUBMISSION SUMMARY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Rows
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _sRow2(
                              Icons.person_rounded,
                              'Full Name',
                              '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
                            ),
                            _sRow2(
                              Icons.mail_outline_rounded,
                              'Email',
                              _emailCtrl.text.trim(),
                            ),
                            _sRow2(
                              Icons.phone_rounded,
                              'Phone',
                              '${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}',
                            ),
                            _sRow2(
                              Icons.subject_rounded,
                              'Subject',
                              _titleCtrl.text.trim(),
                            ),
                            const Divider(height: 20, color: Color(0xFFEEEEEE)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(
                                    Icons.message_rounded,
                                    size: 16,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Message',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black38,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _messageCtrl.text.trim(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.black87,
                                          height: 1.5,
                                        ),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Send Another ──────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _messageCtrl.clear();
                      _sent = false;
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text(
                      'Send Another Message',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Start Fresh ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      for (final c in [
                        _firstNameCtrl,
                        _lastNameCtrl,
                        _emailCtrl,
                        _phoneCtrl,
                        _titleCtrl,
                        _messageCtrl,
                      ])
                        c.clear();
                      _sent = false;
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.black12, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Start Fresh',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sRow2(IconData icon, String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF888888)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black38,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                val,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // keep old _sRow for any remaining usages
  Widget _sRow(IconData icon, String val, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Colors.black38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            val,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.normal,
              color: highlight ? Colors.black87 : Colors.black54,
            ),
          ),
        ),
      ],
    ),
  );

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isWa = _contactPref == ContactPreference.whatsapp;
    return Scaffold(
      backgroundColor: _kBgColor,
      body: Column(
        children: [
          // HEADER
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: _kHeaderColor,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _kTextLight,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Us',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _kTextLight,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'We\'d love to hear from you',
                        style: TextStyle(
                          fontSize: 12,
                          color: _kTextLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mail_outline_rounded,
                    color: _kTextLight,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // BODY
          Expanded(
            child: _sent
                ? _buildSuccess()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Voice hint banner — tap anywhere or tap speaker to replay guide ──
                          if (_speechAvailable)
                            GestureDetector(
                              onTap: _speakGuide,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _bannerSpeaking
                                      ? const Color(0xFF555555)
                                      : _kDarkBtn,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    // Animated speaker icon on the left
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: _bannerSpeaking
                                            ? const Color(0xFF25D366)
                                            : Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                        _bannerSpeaking
                                            ? Icons.volume_up_rounded
                                            : Icons.volume_up_outlined,
                                        size: 17,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _bannerSpeaking
                                                ? 'Reading form guide…'
                                                : 'Tap to hear the form guide',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _bannerSpeaking
                                                ? 'Explains each field and mic button location'
                                                : 'Reads out all fields & where to tap to record',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white.withOpacity(
                                                0.65,
                                              ),
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      _bannerSpeaking
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white.withOpacity(0.8),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // ── Preference ───────────────────────────────────────────────
                          _buildPreference(),
                          const SizedBox(height: 18),

                          // ── Name row ─────────────────────────────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _label('FIRST NAME'),
                                    Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: _firstNameCtrl,
                                          builder: (_, v, __) => v.text.isEmpty
                                              ? const Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 48,
                                                  ),
                                                  child: _BlinkingHint(
                                                    'First name',
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                        TextFormField(
                                          controller: _firstNameCtrl,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          textInputAction: TextInputAction.next,
                                          keyboardType: TextInputType.name,
                                          decoration: _inputDeco(
                                            prefix: const Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                              color: Colors.black38,
                                            ),
                                            suffix: _mic(
                                              'firstName',
                                              _firstNameCtrl,
                                            ),
                                          ),
                                          validator: (v) =>
                                              (v == null || v.trim().isEmpty)
                                              ? 'Required'
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _label('LAST NAME'),
                                    Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: _lastNameCtrl,
                                          builder: (_, v, __) => v.text.isEmpty
                                              ? const Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 48,
                                                  ),
                                                  child: _BlinkingHint(
                                                    'Last name',
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                        TextFormField(
                                          controller: _lastNameCtrl,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          textInputAction: TextInputAction.next,
                                          keyboardType: TextInputType.name,
                                          decoration: _inputDeco(
                                            prefix: const Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                              color: Colors.black38,
                                            ),
                                            suffix: _mic(
                                              'lastName',
                                              _lastNameCtrl,
                                            ),
                                          ),
                                          validator: (v) =>
                                              (v == null || v.trim().isEmpty)
                                              ? 'Required'
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // ── Email ────────────────────────────────────────────────────
                          _label('EMAIL ADDRESS'),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration:
                                _inputDeco(
                                  prefix: const Icon(
                                    Icons.mail_outline_rounded,
                                    size: 18,
                                    color: Colors.black38,
                                  ),
                                  suffix: _mic('email', _emailCtrl),
                                ).copyWith(
                                  hintText: 'john@example.com',
                                  hintStyle: const TextStyle(
                                    color: Colors.black26,
                                    fontSize: 13,
                                  ),
                                ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Required';
                              if (!RegExp(
                                r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$',
                              ).hasMatch(v.trim()))
                                return 'Invalid email address';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── Phone ────────────────────────────────────────────────────
                          _label('PHONE NUMBER'),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: _showCountryPicker,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        _selectedCountry['flag']!,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _selectedCountry['dial']!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.arrow_drop_down_rounded,
                                        size: 18,
                                        color: Colors.black38,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration:
                                      _inputDeco(
                                        suffix: _mic('phone', _phoneCtrl),
                                      ).copyWith(
                                        hintText: '5XX XXX XXXX',
                                        hintStyle: const TextStyle(
                                          color: Colors.black26,
                                          fontSize: 13,
                                        ),
                                      ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty)
                                      return 'Required';
                                    if (v.trim().length < 6) return 'Too short';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // ── Title ───────────────────────────────────────────────────
                          _label('SUBJECT'),
                          Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _titleCtrl,
                                builder: (_, v, __) => v.text.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.only(left: 16),
                                        child: _BlinkingHint(
                                          'Enter a subject for your message',
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              TextFormField(
                                controller: _titleCtrl,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.text,
                                decoration: _inputDeco(
                                  prefix: const Icon(
                                    Icons.subject_rounded,
                                    size: 18,
                                    color: Colors.black38,
                                  ),
                                  suffix: _mic('title', _titleCtrl),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // ── Message ──────────────────────────────────────────────────
                          _label('MESSAGE'),
                          Stack(
                            children: [
                              TextFormField(
                                controller: _messageCtrl,
                                maxLines: null,
                                minLines: 6,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                strutStyle: const StrutStyle(
                                  forceStrutHeight: false,
                                ),
                                decoration: _inputDeco().copyWith(
                                  hintText: 'Write your message here…',
                                  hintStyle: const TextStyle(
                                    color: Colors.black26,
                                    fontSize: 13,
                                  ),
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    56,
                                    16,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty)
                                    return 'Please write your message';
                                  if (v.trim().length < 10)
                                    return 'Message is too short';
                                  return null;
                                },
                              ),
                              if (_speechAvailable)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: _MicButton(
                                    isListening: _listeningField == 'message',
                                    onTap: () =>
                                        _toggleVoice('message', _messageCtrl),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Send button ──────────────────────────────────────────────
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSending ? null : _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isWa
                                    ? _kWaGreen
                                    : Colors.black,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.black
                                    .withOpacity(0.35),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isWa
                                              ? Icons.chat_rounded
                                              : Icons.send_rounded,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isWa
                                              ? 'Open WhatsApp & Send'
                                              : 'Send via Email',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 12,
                                  color: Colors.black38,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Your information is kept private',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
