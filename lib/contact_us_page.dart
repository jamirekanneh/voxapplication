import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _kDevWhatsApp = '905488265289';
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
const _kBgColor = Color(0xFF0A0E1A);
const _kHeaderColor = Color(0xFF0A0E1A);
const _kTextLight = Colors.white;
const _kWaGreen = Color(0xFF25D366);
const _kDarkBtn = Color(0xFF141A29);
const _kNavy = Color(0xFF141A29);

enum ContactPreference { email, whatsapp }

const List<Map<String, String>> _kCountries = [
  {'name': 'Afghanistan', 'dial': '+93', 'flag': 'ðŸ‡¦ðŸ‡«'},
  {'name': 'Albania', 'dial': '+355', 'flag': 'ðŸ‡¦ðŸ‡±'},
  {'name': 'Algeria', 'dial': '+213', 'flag': 'ðŸ‡©ðŸ‡¿'},
  {'name': 'Argentina', 'dial': '+54', 'flag': 'ðŸ‡¦ðŸ‡·'},
  {'name': 'Australia', 'dial': '+61', 'flag': 'ðŸ‡¦ðŸ‡º'},
  {'name': 'Austria', 'dial': '+43', 'flag': 'ðŸ‡¦ðŸ‡¹'},
  {'name': 'Bahrain', 'dial': '+973', 'flag': 'ðŸ‡§ðŸ‡­'},
  {'name': 'Bangladesh', 'dial': '+880', 'flag': 'ðŸ‡§ðŸ‡©'},
  {'name': 'Belgium', 'dial': '+32', 'flag': 'ðŸ‡§ðŸ‡ª'},
  {'name': 'Brazil', 'dial': '+55', 'flag': 'ðŸ‡§ðŸ‡·'},
  {'name': 'Canada', 'dial': '+1', 'flag': 'ðŸ‡¨ðŸ‡¦'},
  {'name': 'Chile', 'dial': '+56', 'flag': 'ðŸ‡¨ðŸ‡±'},
  {'name': 'China', 'dial': '+86', 'flag': 'ðŸ‡¨ðŸ‡³'},
  {'name': 'Colombia', 'dial': '+57', 'flag': 'ðŸ‡¨ðŸ‡´'},
  {'name': 'Croatia', 'dial': '+385', 'flag': 'ðŸ‡­ðŸ‡·'},
  {'name': 'Czech Republic', 'dial': '+420', 'flag': 'ðŸ‡¨ðŸ‡¿'},
  {'name': 'Denmark', 'dial': '+45', 'flag': 'ðŸ‡©ðŸ‡°'},
  {'name': 'Egypt', 'dial': '+20', 'flag': 'ðŸ‡ªðŸ‡¬'},
  {'name': 'Ethiopia', 'dial': '+251', 'flag': 'ðŸ‡ªðŸ‡¹'},
  {'name': 'Finland', 'dial': '+358', 'flag': 'ðŸ‡«ðŸ‡®'},
  {'name': 'France', 'dial': '+33', 'flag': 'ðŸ‡«ðŸ‡·'},
  {'name': 'Germany', 'dial': '+49', 'flag': 'ðŸ‡©ðŸ‡ª'},
  {'name': 'Ghana', 'dial': '+233', 'flag': 'ðŸ‡¬ðŸ‡­'},
  {'name': 'Greece', 'dial': '+30', 'flag': 'ðŸ‡¬ðŸ‡·'},
  {'name': 'Hungary', 'dial': '+36', 'flag': 'ðŸ‡­ðŸ‡º'},
  {'name': 'India', 'dial': '+91', 'flag': 'ðŸ‡®ðŸ‡³'},
  {'name': 'Indonesia', 'dial': '+62', 'flag': 'ðŸ‡®ðŸ‡©'},
  {'name': 'Iran', 'dial': '+98', 'flag': 'ðŸ‡®ðŸ‡·'},
  {'name': 'Iraq', 'dial': '+964', 'flag': 'ðŸ‡®ðŸ‡¶'},
  {'name': 'Ireland', 'dial': '+353', 'flag': 'ðŸ‡®ðŸ‡ª'},
  {'name': 'Israel', 'dial': '+972', 'flag': 'ðŸ‡®ðŸ‡±'},
  {'name': 'Italy', 'dial': '+39', 'flag': 'ðŸ‡®ðŸ‡¹'},
  {'name': 'Japan', 'dial': '+81', 'flag': 'ðŸ‡¯ðŸ‡µ'},
  {'name': 'Jordan', 'dial': '+962', 'flag': 'ðŸ‡¯ðŸ‡´'},
  {'name': 'Kenya', 'dial': '+254', 'flag': 'ðŸ‡°ðŸ‡ª'},
  {'name': 'Kuwait', 'dial': '+965', 'flag': 'ðŸ‡°ðŸ‡¼'},
  {'name': 'Lebanon', 'dial': '+961', 'flag': 'ðŸ‡±ðŸ‡§'},
  {'name': 'Libya', 'dial': '+218', 'flag': 'ðŸ‡±ðŸ‡¾'},
  {'name': 'Malaysia', 'dial': '+60', 'flag': 'ðŸ‡²ðŸ‡¾'},
  {'name': 'Mexico', 'dial': '+52', 'flag': 'ðŸ‡²ðŸ‡½'},
  {'name': 'Morocco', 'dial': '+212', 'flag': 'ðŸ‡²ðŸ‡¦'},
  {'name': 'Netherlands', 'dial': '+31', 'flag': 'ðŸ‡³ðŸ‡±'},
  {'name': 'New Zealand', 'dial': '+64', 'flag': 'ðŸ‡³ðŸ‡¿'},
  {'name': 'Nigeria', 'dial': '+234', 'flag': 'ðŸ‡³ðŸ‡¬'},
  {'name': 'Norway', 'dial': '+47', 'flag': 'ðŸ‡³ðŸ‡´'},
  {'name': 'Oman', 'dial': '+968', 'flag': 'ðŸ‡´ðŸ‡²'},
  {'name': 'Pakistan', 'dial': '+92', 'flag': 'ðŸ‡µðŸ‡°'},
  {'name': 'Palestine', 'dial': '+970', 'flag': 'ðŸ‡µðŸ‡¸'},
  {'name': 'Peru', 'dial': '+51', 'flag': 'ðŸ‡µðŸ‡ª'},
  {'name': 'Philippines', 'dial': '+63', 'flag': 'ðŸ‡µðŸ‡­'},
  {'name': 'Poland', 'dial': '+48', 'flag': 'ðŸ‡µðŸ‡±'},
  {'name': 'Portugal', 'dial': '+351', 'flag': 'ðŸ‡µðŸ‡¹'},
  {'name': 'Qatar', 'dial': '+974', 'flag': 'ðŸ‡¶ðŸ‡¦'},
  {'name': 'Romania', 'dial': '+40', 'flag': 'ðŸ‡·ðŸ‡´'},
  {'name': 'Russia', 'dial': '+7', 'flag': 'ðŸ‡·ðŸ‡º'},
  {'name': 'Saudi Arabia', 'dial': '+966', 'flag': 'ðŸ‡¸ðŸ‡¦'},
  {'name': 'Senegal', 'dial': '+221', 'flag': 'ðŸ‡¸ðŸ‡³'},
  {'name': 'Serbia', 'dial': '+381', 'flag': 'ðŸ‡·ðŸ‡¸'},
  {'name': 'Singapore', 'dial': '+65', 'flag': 'ðŸ‡¸ðŸ‡¬'},
  {'name': 'South Africa', 'dial': '+27', 'flag': 'ðŸ‡¿ðŸ‡¦'},
  {'name': 'South Korea', 'dial': '+82', 'flag': 'ðŸ‡°ðŸ‡·'},
  {'name': 'Spain', 'dial': '+34', 'flag': 'ðŸ‡ªðŸ‡¸'},
  {'name': 'Sudan', 'dial': '+249', 'flag': 'ðŸ‡¸ðŸ‡©'},
  {'name': 'Sweden', 'dial': '+46', 'flag': 'ðŸ‡¸ðŸ‡ª'},
  {'name': 'Switzerland', 'dial': '+41', 'flag': 'ðŸ‡¨ðŸ‡­'},
  {'name': 'Syria', 'dial': '+963', 'flag': 'ðŸ‡¸ðŸ‡¾'},
  {'name': 'Taiwan', 'dial': '+886', 'flag': 'ðŸ‡¹ðŸ‡¼'},
  {'name': 'Tanzania', 'dial': '+255', 'flag': 'ðŸ‡¹ðŸ‡¿'},
  {'name': 'Thailand', 'dial': '+66', 'flag': 'ðŸ‡¹ðŸ‡­'},
  {'name': 'Tunisia', 'dial': '+216', 'flag': 'ðŸ‡¹ðŸ‡³'},
  {'name': 'Turkey', 'dial': '+90', 'flag': 'ðŸ‡¹ðŸ‡·'},
  {'name': 'UAE', 'dial': '+971', 'flag': 'ðŸ‡¦ðŸ‡ª'},
  {'name': 'Uganda', 'dial': '+256', 'flag': 'ðŸ‡ºðŸ‡¬'},
  {'name': 'Ukraine', 'dial': '+380', 'flag': 'ðŸ‡ºðŸ‡¦'},
  {'name': 'United Kingdom', 'dial': '+44', 'flag': 'ðŸ‡¬ðŸ‡§'},
  {'name': 'United States', 'dial': '+1', 'flag': 'ðŸ‡ºðŸ‡¸'},
  {'name': 'Venezuela', 'dial': '+58', 'flag': 'ðŸ‡»ðŸ‡ª'},
  {'name': 'Vietnam', 'dial': '+84', 'flag': 'ðŸ‡»ðŸ‡³'},
  {'name': 'Yemen', 'dial': '+967', 'flag': 'ðŸ‡¾ðŸ‡ª'},
];

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
      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
    ),
  );
}

class _MicButton extends StatelessWidget {
  final bool isListening;
  final VoidCallback onTap;
  const _MicButton({required this.isListening, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
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

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String? _listeningField;
  bool _voiceBusy = false;

  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    final ok = await _speech.initialize(onError: (e) => debugPrint('STT: $e'));
    if (mounted) setState(() => _speechAvailable = ok);
  }

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
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
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
    ]) {
      c.dispose();
    }
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }

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
        'ðŸ“© *New VOX App Message*\n\n'
        'ðŸ‘¤ *Name:* $name\n'
        'ðŸ“§ *Email:* $email\n'
        'ðŸ“ž *Phone:* $phone\n'
        'ðŸ“Œ *Subject:* ${_titleCtrl.text.trim()}\n\n'
        'ðŸ’¬ *Message:*\n$message\n\n'
        'â†©ï¸ _Reply to this user via WhatsApp_',
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
                  'ðŸ“§ User prefers Email reply\nðŸ“¬ Reply to: ${_emailCtrl.text.trim()}',
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

  void _showCountryPicker() {
    final search = ValueNotifier<String>('');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0E1A),
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
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search countryâ€¦',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
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
                builder: (context, query, _) {
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
                            color: active
                                ? const Color(0xFF4B9EFF)
                                : Colors.transparent,
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
                                        : Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                              Text(
                                c['dial']!,
                                style: TextStyle(
                                  color: active
                                      ? Colors.white70
                                      : Colors.white.withValues(alpha: 0.5),
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

  InputDecoration _inputDeco({Widget? prefix, Widget? suffix}) =>
      InputDecoration(
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4B9EFF), width: 2),
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
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Colors.white.withValues(alpha: 0.6),
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

  Widget _buildPreference() {
    final isEmail = _contactPref == ContactPreference.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PREFERRED REPLY METHOD'),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF0A0E1A).withValues(alpha: 0.06),
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
                      color: isEmail ? _kNavy : _kWaGreen,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (isEmail ? Color(0xFF0A0E1A) : _kWaGreen)
                              .withValues(alpha: 0.25),
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
                              color: isEmail
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Email',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isEmail
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.6),
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
                              color: !isEmail
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'WhatsApp',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: !isEmail
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.6),
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
                  color: isEmail ? _kNavy : _kWaGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isEmail
                    ? 'We will reply directly to your email'
                    : 'WhatsApp opens â€” tap Send to deliver your message',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isEmail ? Colors.white.withValues(alpha: 0.5) : _kWaGreen,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // â”€â”€ Professional success screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSuccess() {
    final isEmail = _contactPref == ContactPreference.email;
    final replyVia = isEmail ? 'Email' : 'WhatsApp';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),

          // â”€â”€ Check icon â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kNavy,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xFF4B9EFF),
              size: 38,
            ),
          ),
          const SizedBox(height: 24),

          // â”€â”€ Title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const Text(
            'Thank you for contacting us!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your message has been received.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We will contact you via $replyVia shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),

          // â”€â”€ Buttons â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => setState(() {
                _messageCtrl.clear();
                _sent = false;
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B9EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.edit_rounded, size: 17),
              label: const Text(
                'Send Another Message',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                ]) {
                  c.clear();
                }
                _sent = false;
              }),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text(
                'Start Fresh',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWa = _contactPref == ContactPreference.whatsapp;
    return Scaffold(
      backgroundColor: _kBgColor,
      body: Column(
        children: [
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
                      color: Colors.white.withValues(alpha: 0.25),
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
                        "We'd love to hear from you",
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
                    color: Colors.white.withValues(alpha: 0.25),
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
                          _buildPreference(),
                          const SizedBox(height: 18),

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
                                          builder: (context, v, _) => v.text.isEmpty
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
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          textCapitalization:
                                              TextCapitalization.words,
                                          textInputAction: TextInputAction.next,
                                          keyboardType: TextInputType.name,
                                          decoration: _inputDeco(
                                            prefix: Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                              color: Colors.white.withValues(alpha: 
                                                0.5,
                                              ),
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
                                          builder: (context, v, _) => v.text.isEmpty
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
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          textCapitalization:
                                              TextCapitalization.words,
                                          textInputAction: TextInputAction.next,
                                          keyboardType: TextInputType.name,
                                          decoration: _inputDeco(
                                            prefix: Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                              color: Colors.white.withValues(alpha: 
                                                0.5,
                                              ),
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

                          _label('EMAIL ADDRESS'),
                          TextFormField(
                            controller: _emailCtrl,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration:
                                _inputDeco(
                                  prefix: Icon(
                                    Icons.mail_outline_rounded,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                  suffix: _mic('email', _emailCtrl),
                                ).copyWith(
                                  hintText: 'john@example.com',
                                  hintStyle: const TextStyle(
                                    color: Color(0x420A0E1A),
                                    fontSize: 13,
                                  ),
                                ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (!RegExp(
                                r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$',
                              ).hasMatch(v.trim())) {
                                return 'Invalid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

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
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.1),
                                    ),
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
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down_rounded,
                                        size: 18,
                                        color: Colors.white.withValues(alpha: 0.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration:
                                      _inputDeco(
                                        suffix: _mic('phone', _phoneCtrl),
                                      ).copyWith(
                                        hintText: '5XX XXX XXXX',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          fontSize: 13,
                                        ),
                                      ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    if (v.trim().length < 6) return 'Too short';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          _label('SUBJECT'),
                          Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _titleCtrl,
                                builder: (context, v, _) => v.text.isEmpty
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
                                style: const TextStyle(color: Colors.white),
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.text,
                                decoration: _inputDeco(
                                  prefix: Icon(
                                    Icons.subject_rounded,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.5),
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

                          _label('MESSAGE'),
                          Stack(
                            children: [
                              TextFormField(
                                controller: _messageCtrl,
                                style: const TextStyle(color: Colors.white),
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
                                  hintText: 'Write your message hereâ€¦',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
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
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Please write your message';
                                  }
                                  if (v.trim().length < 10) {
                                    return 'Message is too short';
                                  }
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

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSending ? null : _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isWa
                                    ? _kWaGreen
                                    : const Color(0xFF4B9EFF),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFF4B9EFF,
                                ).withValues(alpha: 0.35),
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
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 12,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Your information is kept private',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.5),
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

