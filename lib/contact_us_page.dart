import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ★  Developer WhatsApp number — digits only, no + or spaces
// ─────────────────────────────────────────────────────────────────────────────
const _kDevWhatsApp = '905488265289';

// ─────────────────────────────────────────────────────────────────────────────
// EmailJS credentials
// ─────────────────────────────────────────────────────────────────────────────
const _kEmailJSServiceId = 'service_sj1zwun';
const _kEmailJSTemplateId = 'template_kg6ezs8';
const _kEmailJSPublicKey = '8tlgc7LHJtmuCRZmj';

// ─────────────────────────────────────────────────────────────────────────────
// App-wide color palette
// ─────────────────────────────────────────────────────────────────────────────
const _kBgColor = Color(0xFFF3E5AB);
const _kHeaderColor = Color(0xFFD4B96A);
const _kTextLight = Color(0xFFF3E5AB);
const _kWaGreen = Color(0xFF25D366);

// ─────────────────────────────────────────────────────────────────────────────
// Contact preference
// ─────────────────────────────────────────────────────────────────────────────
enum ContactPreference { email, whatsapp }

// ─────────────────────────────────────────────────────────────────────────────
// Country list
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// _BlinkingHint
// ─────────────────────────────────────────────────────────────────────────────
class _BlinkingHint extends StatefulWidget {
  final String text;
  const _BlinkingHint(this.text);
  @override
  State<_BlinkingHint> createState() => _BlinkingHintState();
}

class _BlinkingHintState extends State<_BlinkingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 1.0, end: 0.15).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Text(
      widget.text,
      style: const TextStyle(color: Colors.black38, fontSize: 13),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _MicButton
// ─────────────────────────────────────────────────────────────────────────────
class _MicButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onTap;
  const _MicButton({required this.isListening, required this.onTap});
  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _anim = Tween<double>(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    widget.isListening
        ? _ctrl.repeat(reverse: true)
        : (_ctrl
            ..stop()
            ..reset());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: ScaleTransition(
      scale: _anim,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: widget.isListening
              ? Colors.red.shade400
              : _kHeaderColor.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: widget.isListening
              ? [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Icon(
          widget.isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ContactUsPage
// ─────────────────────────────────────────────────────────────────────────────
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

  Map<String, String> _selectedCountry = _kCountries.firstWhere(
    (c) => c['name'] == 'Turkey',
    orElse: () => _kCountries.first,
  );

  ContactPreference _contactPref = ContactPreference.email;
  bool _isSending = false;
  bool _sent = false;

  // Speech
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String? _listeningField;

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
    if (_listeningField == key) {
      await _speech.stop();
      setState(() => _listeningField = null);
      return;
    }
    if (_listeningField != null) await _speech.stop();
    setState(() => _listeningField = key);
    await _speech.listen(
      onResult: (r) {
        ctrl.text = r.recognizedWords;
        ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: ctrl.text.length),
        );
        if (r.finalResult) setState(() => _listeningField = null);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      cancelOnError: true,
      listenMode: stt.ListenMode.dictation,
    );
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl,
      _lastNameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _messageCtrl,
    ])
      c.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Send logic ─────────────────────────────────────────────────────────────
  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    if (_contactPref == ContactPreference.whatsapp) {
      // ── Build a nicely formatted WhatsApp message to the developer ──────────
      final name = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';
      final phone =
          '${_selectedCountry['flag']} ${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}';
      final email = _emailCtrl.text.trim();
      final message = _messageCtrl.text.trim();

      final text = Uri.encodeComponent(
        '📩 *New VOX App Message*\n\n'
        '👤 *Name:* $name\n'
        '📧 *Email:* $email\n'
        '📞 *Phone:* $phone\n\n'
        '💬 *Message:*\n$message\n\n'
        '↩️ _Reply to this user via WhatsApp_',
      );

      // Opens WhatsApp pre-filled to the developer's number
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
      // ── Email via EmailJS ────────────────────────────────────────────────────
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
              'message': _messageCtrl.text.trim(),
              'reply_preference':
                  '📧 User prefers Email reply\n'
                  '📬 Reply to: ${_emailCtrl.text.trim()}',
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

  // ── Country picker ─────────────────────────────────────────────────────────
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

  // ── Helpers ────────────────────────────────────────────────────────────────
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

  // ── Contact-preference toggle ──────────────────────────────────────────────
  Widget _buildPreference() {
    final isEmail = _contactPref == ContactPreference.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('HOW SHOULD WE REPLY TO YOU?'),
        Row(
          children: [
            // Email tile
            Expanded(
              child: GestureDetector(
                onTap: () =>
                    setState(() => _contactPref = ContactPreference.email),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isEmail ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isEmail ? Colors.black : Colors.black12,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline_rounded,
                        size: 18,
                        color: isEmail ? Colors.white : Colors.black54,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Email',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isEmail ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (isEmail) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: _kHeaderColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // WhatsApp tile
            Expanded(
              child: GestureDetector(
                onTap: () =>
                    setState(() => _contactPref = ContactPreference.whatsapp),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: !isEmail ? _kWaGreen : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: !isEmail ? _kWaGreen : Colors.black12,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_rounded,
                        size: 18,
                        color: !isEmail ? Colors.white : Colors.black54,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'WhatsApp',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: !isEmail ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (!isEmail) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              isEmail ? Icons.mail_rounded : Icons.chat_rounded,
              size: 12,
              color: isEmail ? Colors.black38 : _kWaGreen,
            ),
            const SizedBox(width: 6),
            Text(
              isEmail
                  ? 'We\'ll reply to your email address'
                  : 'WhatsApp will open — just tap Send to reach us',
              style: TextStyle(
                fontSize: 11,
                color: isEmail ? Colors.black45 : _kWaGreen,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Success screen ─────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final isEmail = _contactPref == ContactPreference.email;
    final prefLabel = isEmail ? '📧 Email' : '💬 WhatsApp';
    final contact = isEmail
        ? _emailCtrl.text.trim()
        : '${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: _kHeaderColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: _kTextLight,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Message Sent! 🎉',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Thank you, ${_firstNameCtrl.text.trim()}!\nWe\'ll get back to you via $prefLabel at:\n$contact',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR SUBMISSION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black38,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                _sRow(
                  Icons.person_outline_rounded,
                  '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
                ),
                _sRow(Icons.mail_outline_rounded, _emailCtrl.text.trim()),
                _sRow(
                  Icons.phone_outlined,
                  '${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}',
                ),
                _sRow(Icons.reply_rounded, prefLabel, highlight: true),
                const Divider(height: 16, color: Colors.black12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.message_outlined,
                      size: 14,
                      color: Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _messageCtrl.text.trim(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Send Another — keeps personal details, clears only message
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() {
                _messageCtrl.clear();
                _sent = false;
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: _kTextLight,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Send Another Message',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Clear all
          TextButton(
            onPressed: () => setState(() {
              for (final c in [
                _firstNameCtrl,
                _lastNameCtrl,
                _emailCtrl,
                _phoneCtrl,
                _messageCtrl,
              ])
                c.clear();
              _sent = false;
            }),
            child: const Text(
              'Start Fresh (clear all fields)',
              style: TextStyle(color: Colors.black38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

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

  // ── build ──────────────────────────────────────────────────────────────────
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
                  child: Icon(
                    _speechAvailable
                        ? Icons.mic_rounded
                        : Icons.mail_outline_rounded,
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
                          // Voice banner
                          if (_speechAvailable)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _kHeaderColor.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _kHeaderColor.withOpacity(0.5),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.mic_rounded,
                                    size: 16,
                                    color: Colors.black54,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Tap the mic icon next to any field to fill it with your voice',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Preference
                          _buildPreference(),
                          const SizedBox(height: 18),

                          // NAME
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

                          // EMAIL
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

                          // PHONE
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

                          // MESSAGE
                          Row(
                            children: [
                              Expanded(child: _label('MESSAGE')),
                              if (_speechAvailable) ...[
                                if (_listeningField == 'message')
                                  const Text(
                                    'Listening…',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                _MicButton(
                                  isListening: _listeningField == 'message',
                                  onTap: () =>
                                      _toggleVoice('message', _messageCtrl),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ],
                          ),
                          TextFormField(
                            controller: _messageCtrl,
                            maxLines: null,
                            minLines: 6,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                            strutStyle: const StrutStyle(
                              forceStrutHeight: false,
                            ),
                            decoration: _inputDeco().copyWith(
                              hintText: 'Write your message here…',
                              hintStyle: const TextStyle(
                                color: Colors.black26,
                                fontSize: 13,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Please write your message';
                              if (v.trim().length < 10)
                                return 'Message is too short';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // SEND BUTTON — green for WhatsApp, black for email
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

                          // Privacy note
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
