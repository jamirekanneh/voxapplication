import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// EmailJS credentials — replace these 3 values with your real ones from EmailJS
// Service ID  → emailjs.com → Email Services → your Gmail service
// Template ID → emailjs.com → Email Templates → Contact Us
// Public Key  → emailjs.com → Account (top right) → API Keys
// ─────────────────────────────────────────────────────────────────────────────
const _kEmailJSServiceId = 'service_sj1zwun';
const _kEmailJSTemplateId = 'template_kg6ezs8';
const _kEmailJSPublicKey = '8tlgc7LHJtmuCRZmj';
// ─────────────────────────────────────────────────────────────────────────────
// App-wide color palette — matches the VOX MenuPage theme exactly
// ─────────────────────────────────────────────────────────────────────────────
const _kBgColor = Color(0xFFF3E5AB); // warm parchment — main background
const _kHeaderColor = Color(0xFFD4B96A); // golden amber   — header/accents
const _kTextLight = Color(0xFFF3E5AB); // same as bg     — text on dark surfaces

// ─────────────────────────────────────────────────────────────────────────────
// Country list — each entry has a name, international dial code, and flag emoji
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
// _BlinkingHint — animated fading placeholder shown inside empty fields
// Fades in and out repeatedly until the user starts typing
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
    // Repeats forever: fades from fully visible down to nearly invisible
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
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Text(
        widget.text,
        style: const TextStyle(color: Colors.black38, fontSize: 13),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ContactUsPage — main widget
// ─────────────────────────────────────────────────────────────────────────────
class ContactUsPage extends StatefulWidget {
  const ContactUsPage({super.key});

  @override
  State<ContactUsPage> createState() => _ContactUsPageState();
}

class _ContactUsPageState extends State<ContactUsPage> {
  // ── Form key — triggers validation on all fields at once ───────────────────
  final _formKey = GlobalKey<FormState>();

  // ── Text controllers — one per input field ─────────────────────────────────
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  // ── Selected country — defaults to United States ───────────────────────────
  Map<String, String> _selectedCountry = _kCountries.firstWhere(
    (c) => c['name'] == 'United States',
    orElse: () => _kCountries.first,
  );

  // ── UI state flags ─────────────────────────────────────────────────────────
  bool _isSending = false; // true while HTTP request is in flight
  bool _sent = false; // true after success → shows thank-you screen

  // ── dispose — free all controllers when widget leaves the tree ─────────────
  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  // ── _send ──────────────────────────────────────────────────────────────────
  // Validates the form then POSTs to EmailJS API.
  // EmailJS sends the email to gr.1graduationproject@gmail.com directly.
  // No email app needed on the device.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    // Stop if any field fails its validator
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    try {
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _kEmailJSServiceId,
          'template_id': _kEmailJSTemplateId,
          'user_id': _kEmailJSPublicKey,
          'template_params': {
            // These keys must match exactly what you have in your EmailJS template
            'name':
                '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
            'email': _emailCtrl.text.trim(),
            'title': 'New message from VOX App',
            'message_phone':
                '${_selectedCountry['flag']} ${_selectedCountry['name']} ${_selectedCountry['dial']} ${_phoneCtrl.text.trim()}',
            'message': _messageCtrl.text.trim(),
          },
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        // Success — show the thank-you screen
        setState(() {
          _isSending = false;
          _sent = true;
        });
      } else {
        setState(() => _isSending = false);
        _showError('Failed to send (${response.statusCode}). Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showError('Network error. Check your connection.');
    }
  }

  // ── _showError — red floating snack-bar for any error message ──────────────
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── _showCountryPicker ─────────────────────────────────────────────────────
  // Bottom-sheet with a live-search list of all countries.
  // Tapping a row updates _selectedCountry and closes the sheet.
  // ──────────────────────────────────────────────────────────────────────────
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
        builder: (_, scrollCtrl) => Column(
          children: [
            // Drag handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Search text field
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

            // Filtered country list
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
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final country = filtered[i];
                      final isActive =
                          country['name'] == _selectedCountry['name'];

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCountry = country);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                country['flag']!,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  country['name']!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isActive
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                country['dial']!,
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white70
                                      : Colors.black45,
                                  fontSize: 13,
                                ),
                              ),
                              if (isActive) ...[
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

  // ── _inputDeco — shared decoration so every field looks the same ───────────
  InputDecoration _inputDeco({Widget? prefix}) {
    return InputDecoration(
      prefixIcon: prefix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
  }

  // ── _sectionLabel — small all-caps grey label above each field ─────────────
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.black38,
          letterSpacing: 2,
        ),
      ),
    );
  }

  // ── _buildSuccessView — shown after message is sent successfully ────────────
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
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
              'Message Sent!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Thank you for reaching out.\nWe\'ll get back to you as soon as possible.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _sent = false;
                    for (final ctrl in [
                      _firstNameCtrl,
                      _lastNameCtrl,
                      _emailCtrl,
                      _phoneCtrl,
                      _messageCtrl,
                    ])
                      ctrl.clear();
                  });
                },
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
          ],
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: Column(
        children: [
          // ══════════════════════════════════════════════════════════════════
          // HEADER
          // ══════════════════════════════════════════════════════════════════
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

          // ══════════════════════════════════════════════════════════════════
          // BODY
          // ══════════════════════════════════════════════════════════════════
          Expanded(
            child: _sent
                ? _buildSuccessView()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── NAME ROW ──────────────────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // First Name with blinking hint
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionLabel('FIRST NAME'),
                                    Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: _firstNameCtrl,
                                          builder: (_, val, __) =>
                                              val.text.isEmpty
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
                                          decoration: _inputDeco(
                                            prefix: const Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                              color: Colors.black38,
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

                              // Last Name with blinking hint
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionLabel('LAST NAME'),
                                    Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: _lastNameCtrl,
                                          builder: (_, val, __) =>
                                              val.text.isEmpty
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
                                          decoration: _inputDeco(
                                            prefix: const Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                              color: Colors.black38,
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

                          // ── EMAIL ─────────────────────────────────────────
                          _sectionLabel('EMAIL ADDRESS'),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration:
                                _inputDeco(
                                  prefix: const Icon(
                                    Icons.mail_outline_rounded,
                                    size: 18,
                                    color: Colors.black38,
                                  ),
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

                          // ── PHONE ─────────────────────────────────────────
                          _sectionLabel('PHONE NUMBER'),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Country selector
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
                              // Phone number input
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: _inputDeco().copyWith(
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

                          // ── MESSAGE ───────────────────────────────────────
                          _sectionLabel('MESSAGE'),
                          TextFormField(
                            controller: _messageCtrl,
                            maxLines: 6,
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

                          // ── SEND BUTTON ───────────────────────────────────
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSending ? null : _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: _kTextLight,
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
                                  : const Text(
                                      'Send Message',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── PRIVACY NOTE ──────────────────────────────────
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
